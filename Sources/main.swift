import AppKit
import SwiftUI
import IOKit
import IOKit.ps
import Combine
import ImageIO
import UniformTypeIdentifiers
struct PortReading: Identifiable {
    let id: Int
    let power: Double?
    let voltage: Double?
    let current: Double?
    var name: String? = nil
}
struct Reading {
    // One definition for the status item, headline and flow's supply node.
    // Charging is an output branch; it must not replace total supply.
    var supplyPower: Double? {
        if external { return input.map { $0 + max(0, -(battery ?? 0)) } }
        guard let battery, battery < 0 else { return nil }
        return -battery
    }
    var headlinePower: Double? { supplyPower }
    var headlineTitle: String { "總供電" }
    var batteryTitle: String {
        guard let battery else { return "電池功率" }
        if battery > 0.05 { return "電池充電" }
        if battery < -0.05 { return "電池放電" }
        return "電池待機"
    }
    // Hide only confirmed idle; keep unknown readings visible.
    var batteryOnRight: Bool { external && (battery.map { $0 > 0.05 } ?? true) }
    var batterySource = "IORegistry 電壓 × 電流"
    var battery: Double?
    var input: Double?
    var load: Double?
    var display: Double?
    var displayKey = ""
    var smcStatus = ""
    var temperature: Double?
    var adapterRating: Double?
    var ports: [PortReading] = []
    var hasPortTelemetry = false
    var portSource = "未回報功率"
    var portPower: Double? {
        guard hasPortTelemetry, ports.allSatisfy({ $0.power != nil }) else { return nil }
        return ports.reduce(0) { $0 + ($1.power ?? 0) }
    }
    var system: Double? {
        guard let load, let display else { return nil }
        let result = load - display - (portPower ?? 0)
        return result >= 0 ? result : nil
    }
    var portStatus: String { portPower != nil ? portSource : "未回報功率" }
    var percent: Int?
    var external = false
    var installed = false
    var devices: [String] = []
    var date = Date()
    var state: String {
        guard installed else { return "未找到電池" }
        guard let battery else { return external ? "電池數據更新中" : "電池供電 · 更新中" }
        if battery > 0.05 { return "電池充電中" }
        if battery < -0.05 { return "電池放電中" }
        return external ? "外接電源 · 電池待機" : "電池待機"
    }
    static func parse(_ p: [String: Any], externalOverride: Bool? = nil) -> Reading {
        var r = Reading()
        r.installed = (p["BatteryInstalled"] as? Bool) ?? !p.isEmpty
        r.external = externalOverride ?? (p["ExternalConnected"] as? Bool ?? false)
        if let entries = p["PowerOutDetails"] as? [[String: Any]] {
            r.hasPortTelemetry = true
            var seen = Set<Int>()
            for (index, entry) in entries.enumerated() {
                let id = (entry["PortIndex"] as? NSNumber)?.intValue ?? index
                guard seen.insert(id).inserted else { continue }
                func valid(_ key: String, _ scale: Double, _ upper: Double) -> Double? {
                    guard let n = entry[key] as? NSNumber else { return nil }
                    let v = n.doubleValue / scale
                    return v.isFinite && v >= 0 && v <= upper ? v : nil
                }
                // PowerOutDetails.Watts is milliwatts, unlike AdapterDetails.Watts.
                let power = valid("Watts", 1000, 240)
                r.ports.append(PortReading(id: id, power: power, voltage: valid("AdapterVoltage", 1000, 50), current: valid("Current", 1000, 10)))
            }
        }
        r.adapterRating = ((p["AdapterDetails"] as? [String: Any])?["Watts"] as? NSNumber)?.doubleValue
        if let c = p["CurrentCapacity"] as? NSNumber, let m = p["MaxCapacity"] as? NSNumber, m.doubleValue > 0 { r.percent = Int(min(100,max(0,c.doubleValue/m.doubleValue*100))) }
        if let v = p["Voltage"] as? NSNumber, v.doubleValue > 0 && v.doubleValue < 30000 {
            for key in ["InstantAmperage", "Amperage"] {
                guard let a = p[key] as? NSNumber else { continue }
                // Both 32-bit and 64-bit unsigned two's-complement values occur.
                let raw = a.uint64Value
                let signed = raw > UInt64(Int32.max) && raw <= UInt64(UInt32.max) ? Int64(Int32(bitPattern: UInt32(raw))) : a.int64Value
                let amps = Double(signed)
                let watts = v.doubleValue * amps / 1_000_000
                guard abs(amps) < 50000 && abs(watts) < 600 else { continue }
                // Offline zero/positive readings can be stale after unplugging.
                guard r.external || watts < -0.05 else { continue }
                r.battery = watts
                r.batterySource = key == "Amperage" ? "電池平均電流 × 電壓" : "電池即時電流 × 電壓"
                break
            }
        }
        if r.external, let t = p["PowerTelemetryData"] as? [String: Any], let n = t["SystemPowerIn"] as? NSNumber {
            let w = n.doubleValue/1000
            if w > 0 && w < 600 { r.input = w }
        }
        if let b = r.battery {
            if let i = r.input, i-b >= 0 { r.load = i-b }
            else if !r.external && b <= 0 { r.load = -b }
        }
        return r
    }
    mutating func applyBattery(volts: Double?, amps: Double?) {
        if let volts, let amps, volts.isFinite, amps.isFinite,
           (1...30).contains(volts), abs(amps) <= 30 {
            let watts = volts * amps
            if external || watts < -0.05 {
                battery = watts
                batterySource = "SMC 即時電壓 × 電流"
            }
        }
        if !external {
            input = nil
            if let b = battery, b < -0.05 { load = -b }
            else { battery = nil; load = nil; batterySource = "正在等待放電感測值" }
        } else if let input, let b = battery {
            load = input - b >= 0 ? input - b : nil
        } else { load = nil }
    }

}
func properties(_ entry: io_registry_entry_t) -> [String: Any] {
    var value: Unmanaged<CFMutableDictionary>?
    guard IORegistryEntryCreateCFProperties(entry, &value, kCFAllocatorDefault, 0) == KERN_SUCCESS else { return [:] }
    return value?.takeRetainedValue() as? [String: Any] ?? [:]
}
// Read-only SMC protocol. Fixed 80-byte ABI; never issue write commands.
final class SMCReader {
    var acknowledgedKeys = Set<String>()
    var connection: io_connect_t = 0
    var status = ""
    init() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSMC"))
        guard service != 0 else { status = "未找到 SMC"; return }
        defer { IOObjectRelease(service) }
        let result = IOServiceOpen(service, mach_task_self_, 0, &connection)
        if result != KERN_SUCCESS { status = "SMC 存取被拒絕 (\(result))"; connection = 0 }
    }
    deinit { if connection != 0 { IOServiceClose(connection) } }
    func read(_ key: String) -> Double? {
        guard connection != 0, key.utf8.count == 4 else { return nil }
        var input = [UInt8](repeating: 0, count: 80)
        var output = input
        func put(_ n: UInt32, _ offset: Int) {
            withUnsafeBytes(of: n) { input.replaceSubrange(offset..<offset+4, with: $0) }
        }
        func call() -> Bool {
            var size = 80
            let result = input.withUnsafeBytes { i in output.withUnsafeMutableBytes { o in
                IOConnectCallStructMethod(connection, 2, i.baseAddress, 80, o.baseAddress, &size)
            } }
            return result == KERN_SUCCESS && size == 80 && output[40] == 0
        }
        put(key.utf8.reduce(0) { ($0 << 8) | UInt32($1) }, 0)
        input[42] = 9
        guard call() else { return nil }
        acknowledgedKeys.insert(key)
        let length = output[28..<32].enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << ($1.offset * 8) }
        let type = String(bytes: output[32..<36].reversed(), encoding: .ascii) ?? ""
        guard length > 0 && length <= 32 else { return nil }
        put(length, 28); input[42] = 5
        guard call() else { return nil }
        let bytes = Array(output[48..<80])
        if key == "B0AC" || key == "B0AV" { return Self.decodeBattery(key: key, type: type, bytes: Array(bytes.prefix(Int(length)))) }
        let value: Double
        if type == "flt " && length == 4 {
            let bits = bytes.prefix(4).enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << ($1.offset * 8) }
            value = Double(Float(bitPattern: bits))
        } else if type == "fpe2" && length == 2 {
            value = Double(UInt16(bytes[0]) << 8 | UInt16(bytes[1])) / 4
        } else if type == "sp78" && length == 2 {
            value = Double(Int16(bitPattern: UInt16(bytes[0]) << 8 | UInt16(bytes[1]))) / 256
        } else { return nil }
        return value.isFinite ? value : nil
    }
    // Apple Silicon B0AC si16=mA and B0AV ui16=mV are little-endian,
    // unlike sp78/fpe2 sensor payloads. Reference: Status Trio v1.9.5.
    static func decodeBattery(key: String, type: String, bytes: [UInt8]) -> Double? {
        if bytes.count == 2 && ((key == "B0AC" && type == "si16") || (key == "B0AV" && type == "ui16")) {
            let raw = UInt16(bytes[0]) | UInt16(bytes[1]) << 8
            return (key == "B0AC" ? Double(Int16(bitPattern: raw)) : Double(raw)) / 1000
        }
        if type == "flt " && bytes.count == 4 {
            let bits = bytes.enumerated().reduce(UInt32(0)) { $0 | UInt32($1.element) << ($1.offset * 8) }
            let value = Double(Float(bitPattern: bits))
            return value.isFinite ? value : nil
        }
        return nil
    }

}
func sample() -> Reading {
    let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
    var r = Reading()
    var registry: [String: Any] = [:]
    if service != 0 {
        registry = properties(service)
        var external: Bool?
        if let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
           let type = IOPSGetProvidingPowerSourceType(info)?.takeUnretainedValue() {
            let state = type as String
            if state == kIOPSACPowerValue { external = true }
            else if state == kIOPSBatteryPowerValue { external = false }
        }
        r = Reading.parse(registry, externalOverride: external); IOObjectRelease(service)
    }
    let smc = SMCReader(); r.smcStatus = smc.status
    for k in ["PDBR","PBwo","PBLR"] {
        if let v = smc.read(k), v >= 0 && v < 100 { r.display = v; r.displayKey = k; break }
    }
    if let v = smc.read("PDTR"), r.external && v > 0 && v < 600 { r.input = v }
    if let v = smc.read("PSTR"), v > 0 && v < 600 { r.load = v }
    else if let b = r.battery, let i = r.input { r.load = max(0,i-b) }
    #if arch(arm64)
    r.applyBattery(volts: smc.read("B0AV"), amps: smc.read("B0AC"))
    #else
    r.applyBattery(volts: nil, amps: nil)
    #endif
    if let v = smc.read("TB0T"), v > 0 && v < 90 { r.temperature = v }
    let topology = USBPortTopologyReader.read()
    let began = Date()
    var railValues: [PortRail] = []
    var electrical: [Int: (Double, Double)] = [:]
    for channel in 1...4 {
        let v = smc.read("D\(channel)JV"), a = smc.read("D\(channel)JI")
        if let v, let a, v >= 0, a >= 0, (v*a).isFinite, v*a <= 150 {
            railValues.append(PortRail(channel: channel, watts: v*a))
            electrical[channel] = (v, a)
        }
    }
    let answered = (1...4).contains { smc.acknowledgedKeys.contains("D\($0)JV") || smc.acknowledgedKeys.contains("D\($0)JI") }
    let rails: PortOutputRails = answered ? .measured(rails: railValues, readAt: began) : .unavailable
    // Resolve live rails first; exclude the input channel before summing.
    // Upstream uses a 0.20 W floor to distinguish idle CC/VConn from accessory power.
    let output = USBOutputReader.resolve(portRails: rails, registry: registry, topology: topology)
    r.ports = []; r.hasPortTelemetry = false
    if let output, output.isFresh(at: Date()) {
        r.hasPortTelemetry = true
        r.portSource = answered ? "SMC 即時電壓 × 電流" : "IORegistry 實測值"
        r.ports = output.ports.map { port in
            PortReading(id: port.channel, power: port.watts, voltage: electrical[port.channel]?.0,
                        current: electrical[port.channel]?.1, name: port.name)
        }
    } else if answered && !railValues.isEmpty && railValues.filter({ $0.channel != topology.inputChannel }).allSatisfy({ $0.watts < 0.20 }) {
        r.hasPortTelemetry = true
        r.portSource = "低於 0.20 W 顯示門檻"
    }

    var iterator: io_iterator_t = 0
    if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"), &iterator) == KERN_SUCCESS {
        defer { IOObjectRelease(iterator) }
        while true {
            let d = IOIteratorNext(iterator); if d == 0 { break }
            let p = properties(d)
            if let name = (p["USB Product Name"] ?? p["kUSBProductString"]) as? String { r.devices.append(name) }
            IOObjectRelease(d)
        }
    }
    r.devices = Array(Set(r.devices)).sorted(); return r
}
func watts(_ v: Double?) -> String { v.map { String(format:"%.1f",abs($0)) } ?? "—" }
@MainActor final class Monitor: ObservableObject {
    @Published var details = false
    @Published var about = false
    @Published var languageMenuOpen = false
    @Published var reading = Reading()
    var onUpdate: (() -> Void)?
    private var timer: Timer?
    private var busy = false
    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in Task { @MainActor in self?.refresh() } }
        timer?.tolerance = 0.4
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }
    func refresh() {
        guard !busy else {return}; busy = true
        DispatchQueue.global(qos: .utility).async {
            let next = sample()
            DispatchQueue.main.async { self.reading = next; self.busy = false; self.onUpdate?() }
        }
    }
}
struct Ribbon: Shape {
    var startY: CGFloat
    var endY: CGFloat
    var thickness: CGFloat
    func path(in rect: CGRect) -> Path {
        var p = Path(); let x = rect.width
        p.move(to: CGPoint(x:0,y:startY))
        p.addCurve(to: CGPoint(x:x,y:endY), control1: CGPoint(x:x*0.45,y:startY), control2: CGPoint(x:x*0.55,y:endY))
        p.addLine(to: CGPoint(x:x,y:endY+thickness))
        p.addCurve(to: CGPoint(x:0,y:startY+thickness), control1: CGPoint(x:x*0.55,y:endY+thickness), control2: CGPoint(x:x*0.45,y:startY+thickness))
        p.closeSubpath();return p
    }
}
enum Theme {
    static let mint = Color(red: 0.43, green: 0.88, blue: 0.76)
    static let blue = Color(red: 0.49, green: 0.69, blue: 0.98)
    static let purple = Color(red: 0.73, green: 0.61, blue: 0.96)
    static let amber = Color(red: 0.96, green: 0.76, blue: 0.45)
}
struct FlowDiagram: View {
    @ObservedObject private var language = LanguageSettings.shared
    let r: Reading
    func node(_ icon: String, _ tint: Color, _ x: CGFloat, _ y: CGFloat, _ h: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 12)
            .fill(LinearGradient(colors: [tint.opacity(0.22), .white.opacity(0.025)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(tint.opacity(0.22), lineWidth: 0.7))
            .shadow(color: tint.opacity(0.08), radius: 8, y: 2)
            .overlay(Image(systemName: icon).font(.system(size: 19, weight: .light)).foregroundStyle(tint))
            .frame(width: 40, height: h).position(x: x, y: y)
    }
    func label(_ value: Double?, _ name: String, _ tint: Color, _ x: CGFloat, _ y: CGFloat) -> some View {
        VStack(spacing: 3) {
            Text(watts(value) + " W").font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(name).font(.system(size: 9)).lineLimit(1).minimumScaleFactor(0.7).frame(maxWidth: 110).foregroundStyle(tint.opacity(0.8))
        }.position(x: x, y: y)
    }
    func band(_ start: CGFloat, _ end: CGFloat, _ width: CGFloat, _ tint: Color, _ x: CGFloat) -> some View {
        Ribbon(startY: start, endY: end, thickness: width)
            .fill(LinearGradient(colors: [tint.opacity(0.035), tint.opacity(0.15)], startPoint: .leading, endPoint: .trailing))
            .overlay(Ribbon(startY: start, endY: end, thickness: width).stroke(tint.opacity(0.18), lineWidth: 0.6))
            .frame(width: 114, height: 180).position(x: x, y: 90)
    }
    var body: some View {
        let hybrid = r.external && (r.battery ?? 0) < -0.05
        let rightBattery = r.batteryOnRight
        ZStack {
            // Battery-only mode has one source and no unused adapter node.
            band(hybrid ? 76 : 52, hybrid ? 73 : 52, hybrid ? 80 : 84, Theme.mint, 98)
            node(r.external ? "powerplug.fill" : "battery.100percent", Theme.mint, 20, hybrid ? 116 : 94, 84)
            label(r.external ? r.input : r.battery, r.external ? L("電源輸入 →") : L("電池供電 →"), Theme.mint, 96, hybrid ? 114 : 94)
            if hybrid {
                band(16, 42, 8, Theme.mint, 98)
                node("battery.100percent", Theme.mint, 20, 20, 32)
                label(r.battery, L("電池輔助供電 →"), Theme.mint, 97, 24)
            }
            node("laptopcomputer", .white.opacity(0.85), 179, 94, 112)
            if rightBattery {
                band(43, 7, 32, Theme.amber, 260)
                band(88, 65, 10, Theme.blue, 260)
                band(111, 110, 10, Theme.purple, 260)
                band(132, 151, 18, Theme.mint, 260)
                node("cpu", Theme.amber, 344, 24, 40)
                node("display", Theme.blue, 344, 70, 32)
                node("cable.connector", Theme.purple, 344, 115, 32)
                node("battery.100percent", Theme.mint, 344, 160, 32)
                label(r.system, L("系統"), Theme.amber, 261, 23)
                label(r.display, L("螢幕"), Theme.blue, 261, 68)
                label(r.portPower, L("接口"), Theme.purple, 261, 113)
                label(r.battery, L(r.batteryTitle) + " →", Theme.mint, 261, 158)
            } else {
                band(43, 12, 44, Theme.amber, 260)
                band(105, 100, 12, Theme.blue, 260)
                band(132, 151, 17, Theme.purple, 260)
                node("cpu", Theme.amber, 344, 34, 50)
                node("display", Theme.blue, 344, 106, 34)
                node("cable.connector", Theme.purple, 344, 160, 34)
                label(r.system, L("系統"), Theme.amber, 261, 35)
                label(r.display, L("螢幕"), Theme.blue, 261, 103)
                label(r.portPower, L("接口"), Theme.purple, 261, 157)
            }
            Text(watts(r.supplyPower))
                .font(.system(size: 12, weight: .semibold, design: .rounded)).position(x: 179, y: 121)
            Text(L("供電 W")).font(.system(size: 8)).foregroundStyle(.secondary).position(x: 179, y: 136)
        }.frame(width: 364, height: 180)
        .help(L("電源與放電電池在左，充電電池在右；流帶寬度為示意。"))
    }

}
struct BatteryLevelIndicator: View {
    let percent: Int?
    let charging: Bool
    var body: some View {
        HStack(spacing: 1) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 2.5).stroke(Theme.mint.opacity(0.65), lineWidth: 1)
                if let percent {
                    RoundedRectangle(cornerRadius: 1.3)
                        .fill(Theme.mint)
                        .frame(width: 18 * CGFloat(min(100, max(0, percent))) / 100, height: 7)
                        .padding(.leading, 2)
                }
                if charging {
                    Image(systemName: "bolt.fill").font(.system(size: 8, weight: .bold))
                        .foregroundStyle(Color(red: 0.08, green: 0.15, blue: 0.16))
                        .frame(width: 22, height: 11)
                } else if percent == nil {
                    Text("?").font(.system(size: 8, weight: .semibold)).foregroundStyle(Theme.mint)
                        .frame(width: 22, height: 11)
                }
            }.frame(width: 22, height: 11)
            RoundedRectangle(cornerRadius: 0.7).fill(Theme.mint.opacity(0.65)).frame(width: 2, height: 4)
        }.fixedSize().accessibilityHidden(true)
    }
}
/// Native macOS material samples the desktop behind the popover.
/// System accessibility settings (Reduce transparency) remain respected.
struct FrostedPanelBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
}
struct AboutView: View {
    @ObservedObject private var language = LanguageSettings.shared
    let onBack: () -> Void
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
    private func section(_ icon: String, _ title: String, _ description: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon).font(.system(size: 14)).foregroundStyle(Theme.mint).frame(width: 20).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text(L(title)).font(.system(size: 12, weight: .semibold)).foregroundStyle(.white.opacity(0.9))
                Text(L(description)).font(.system(size: 11)).foregroundStyle(.white.opacity(0.6))
                    .fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Text(L("關於 PowerLens")).font(.system(size: 13, weight: .semibold))
                Spacer()
                Button(L("返回"), action: onBack).buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.mint)
            }
            VStack(spacing: 3) {
                if let url = Bundle.main.url(forResource: "PowerLens", withExtension: "icns"), let icon = NSImage(contentsOf: url) {
                    Image(nsImage: icon).resizable().frame(width: 66, height: 66)
                } else {
                    Image(systemName: "bolt.circle.fill").font(.system(size: 46)).foregroundStyle(Theme.mint).frame(height: 66)
                }
                HStack(alignment: .firstTextBaseline, spacing: 7) {
                    Text("PowerLens").font(.system(size: 22, weight: .semibold, design: .rounded))
                    Text("v" + version).font(.system(size: 10)).foregroundStyle(.white.opacity(0.45))
                }
                Text(L("選單列上的即時電力監測")).font(.system(size: 10)).foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            }
            VStack(alignment: .leading, spacing: 14) {
                section("waveform.path", "即時讀數", "每 2 秒讀取電源、電池、螢幕與接口功率。選單列顯示與流向圖一致的總供電功率。")
                section("chart.bar.xaxis", "讀數說明", "螢幕數值為背光功率；系統數值為扣除已知分項後的估算。感測資料不可用時顯示「—」。")
                section("lock.shield", "本機運作", "只讀取電力資料，不調整充電設定，也不傳送資料。")
            }.padding(14).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 14))
            Spacer(minLength: 0)

        }.padding(20).frame(width: 400, height: 480)
            .background(LinearGradient(colors: [Color(red: 0.11, green: 0.14, blue: 0.16), Color(red: 0.075, green: 0.085, blue: 0.10)], startPoint: .topLeading, endPoint: .bottomTrailing))
            .environment(\.colorScheme, .dark).foregroundStyle(.white.opacity(0.9))
    }
}
struct Dashboard: View {
    @ObservedObject var monitor: Monitor
    @ObservedObject private var language = LanguageSettings.shared
    func row(_ icon: String, _ title: String, _ caption: String, _ power: Double?, _ tint: Color) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).font(.system(size: 15)).foregroundStyle(tint)
                .frame(width: 30, height: 30).background(tint.opacity(0.09), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 11, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                Text(caption).font(.system(size: 9)).lineLimit(1).truncationMode(.tail).foregroundStyle(.secondary)
            }
            Spacer()
            Text(watts(power)).fixedSize().font(.system(size: 19, weight: .medium, design: .rounded)).monospacedDigit()
            Text("W").font(.system(size: 10)).foregroundStyle(.secondary)
        }.frame(height: 35)
    }
    var body: some View {
        let r = monitor.reading
        VStack(spacing: 9) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(spacing: 6) {
                        Image(systemName: "bolt.circle.fill").foregroundStyle(Theme.mint)
                        Text("PowerLens").fontWeight(.semibold)
                    }.font(.system(size: 13))
                    Text(L(r.headlineTitle)).font(.system(size: 10)).foregroundStyle(.secondary)
                }
                Spacer()
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(watts(r.headlinePower)).font(.system(size: 31, weight: .light, design: .rounded)).monospacedDigit()
                    Text("W").font(.system(size: 12)).foregroundStyle(Theme.mint)
                }
            }
            HStack(spacing: 6) {
                Circle().fill(r.battery == nil ? Color.orange : Theme.mint).frame(width: 4, height: 4)
                Text(L(r.state)).font(.system(size: 9)).foregroundStyle(.secondary)
                Spacer()
                BatteryLevelIndicator(percent: r.percent, charging: (r.battery ?? 0) > 0.05)
                Text(r.percent.map { "\($0)%" } ?? "—").monospacedDigit()
            }.font(.system(size: 10))
            FlowDiagram(r: r)
            VStack(spacing: 1) {
                row("cpu", L("系統功率"), r.system == nil ? L("等待整機與螢幕資料") : (r.portPower == nil ? L("含晶片及未分離接口") : L("含晶片 · 扣除螢幕及已回報接口")), r.system, Theme.amber)
                Divider().opacity(0.4)
                row("display", L("螢幕功率"), L("內置螢幕背光"), r.display, Theme.blue)
                Divider().opacity(0.4)
                Button { monitor.about = false; monitor.details = true } label: {
                    row("cable.connector", L("接口供電  ›"), L(r.portStatus) + L(" · 點擊查看"), r.portPower, Theme.purple)
                }.buttonStyle(.plain)
                Divider().opacity(0.4)
                row("battery.100percent", !r.external || (r.battery ?? 0) < 0 ? L("電池放電") : L("電池充電"), r.battery == nil ? L("正在更新感測資料") : ((r.battery ?? 0) == 0 ? L("待機 · 未充放電") : L("即時功率")), r.battery, Theme.mint)
            }.padding(.horizontal, 12).padding(.vertical, 7)
                .background(.white.opacity(0.035), in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).stroke(.white.opacity(0.055), lineWidth: 0.7))
            HStack(spacing: 5) {
                Text(L("每 2 秒讀取")).font(.system(size: 9)).foregroundStyle(.tertiary)
                Spacer()
                Button { monitor.details = false; monitor.languageMenuOpen = false; monitor.about = true } label: { Image(systemName: "info.circle") }.buttonStyle(.plain).help(L("關於 PowerLens")).accessibilityLabel(L("關於 PowerLens"))
                Button { monitor.refresh() } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).padding(.leading, 9)
                Button(L("結束")) { NSApp.terminate(nil) }.buttonStyle(.plain).padding(.leading, 9)
            }.font(.system(size: 10)).foregroundStyle(.secondary)
            .overlay {
                Button { monitor.languageMenuOpen.toggle() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "globe")
                        Text(language.language.shortName)
                        Image(systemName: "chevron.down").font(.system(size: 7))
                    }.font(.system(size: 10)).foregroundStyle(.secondary)
                        .padding(.horizontal, 7).padding(.vertical, 4)
                        .background(.white.opacity(monitor.languageMenuOpen ? 0.09 : 0), in: RoundedRectangle(cornerRadius: 6))
                }.buttonStyle(.plain).fixedSize().help(L("語言")).accessibilityLabel(L("語言"))

            }
        }.padding(18).frame(width: 400, height: 480)
        .background {
            ZStack {
                // Native behind-window materials cannot be exported by ImageRenderer.
                // Use a neutral backdrop only for explicit CLI layout previews.
                if CommandLine.arguments.contains("--render") {
                    Color(red: 0.09, green: 0.11, blue: 0.13)
                } else {
                    FrostedPanelBackground()
                }
                LinearGradient(colors: [Color(red: 0.115, green: 0.13, blue: 0.15).opacity(0.22), Color(red: 0.075, green: 0.085, blue: 0.10).opacity(0.35)], startPoint: .topLeading, endPoint: .bottomTrailing)
            }.allowsHitTesting(false)
        }
        .environment(\.colorScheme, .dark).preferredColorScheme(.dark).foregroundStyle(Color.white.opacity(0.9))
        .overlay(alignment: .bottom) {
            if monitor.languageMenuOpen {
                ZStack(alignment: .bottom) {
                    Color.black.opacity(0.001).contentShape(Rectangle())
                        .onTapGesture { monitor.languageMenuOpen = false }
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L("語言")).font(.system(size: 10, weight: .medium)).foregroundStyle(.white.opacity(0.55)).padding(.horizontal, 9).padding(.vertical, 5)
                        ForEach(AppLanguage.allCases) { value in
                            Button {
                                language.language = value
                                monitor.languageMenuOpen = false
                            } label: {
                                HStack {
                                    Text(value.name)
                                    Spacer()
                                    Image(systemName: "checkmark").opacity(language.language == value ? 1 : 0)
                                }.font(.system(size: 12)).foregroundStyle(language.language == value ? Theme.mint : .white.opacity(0.9))
                                    .padding(.horizontal, 9).frame(height: 29)
                                    .background(.white.opacity(language.language == value ? 0.07 : 0), in: RoundedRectangle(cornerRadius: 6))
                                    .contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityLabel(value.name)
                        }
                    }.padding(7).frame(width: 180)
                        .background(Color(red: 0.13, green: 0.145, blue: 0.16), in: RoundedRectangle(cornerRadius: 12))
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(.white.opacity(0.12), lineWidth: 0.7))
                        .shadow(color: .black.opacity(0.4), radius: 12, y: 4).padding(.bottom, 42)
                }
            }
        }
        .overlay {
            if monitor.details {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text(L("接口與感測資料")).font(.system(size: 15, weight: .semibold))
                        Spacer()
                        Button(L("返回")) { monitor.details = false }.buttonStyle(.plain).foregroundStyle(Theme.mint)
                    }
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            Text(L("接口供電：") + watts(r.portPower) + " W").font(.title3).monospacedDigit()
                            if r.ports.isEmpty {
                                Text(r.hasPortTelemetry ? L("已回應的接口未有超過 0.20 W 的對外供電。") : L("系統未回報接口功率；不代表沒有連接設備。"))
                            }
                            ForEach(r.ports) { port in
                                HStack {
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(port.name ?? LF("USB-C 通道 {0}", String(port.id)))
                                        Text("\(watts(port.voltage)) V · \(watts(port.current)) A").font(.system(size: 10)).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Text(watts(port.power) + " W").monospacedDigit()
                                }.padding(10).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
                            }
                            Text(LF("ports_info", L(r.portSource)))
                            Divider()
                            Text(L("USB 裝置名稱")).fontWeight(.semibold)
                            Text(r.devices.isEmpty ? L("未取得裝置名稱；不能據此判定未連接。") : r.devices.joined(separator: "、"))
                            Divider()
                            Text(LF("display_info", r.displayKey.isEmpty ? "PDBR / PBwo / PBLR" : r.displayKey))
                            if !r.smcStatus.isEmpty { Text(localizedSMCStatus(r.smcStatus)).foregroundStyle(.orange) }
                            Text(LF("外接輸入：{0} W · 整機：{1} W", watts(r.input), watts(r.load)))
                            Text(L("電池功率來源：") + L(r.batterySource))
                            Text(L("電池溫度：") + (r.temperature.map { String(format: "%.1f °C", $0) } ?? "—"))
                        }.font(.system(size: 11)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
                    }
                }.padding(20).frame(width: 400, height: 480).background(Color(red: 0.09, green: 0.10, blue: 0.12))
            }
        }
        .overlay {
            if monitor.about { AboutView { monitor.about = false } }
        }

    }
}
@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    let monitor = Monitor()
    var item: NSStatusItem!
    let popover = NSPopover()
    var languageSubscription: AnyCancellable?
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: "local.kinson.PowerLens") where app.processIdentifier != ProcessInfo.processInfo.processIdentifier { app.terminate() }
        item = NSStatusBar.system.statusItem(withLength:NSStatusItem.variableLength)
        item.button?.font = NSFont.monospacedDigitSystemFont(ofSize:11,weight:.regular)
        item.button?.target = self; item.button?.action = #selector(toggle)
        popover.behavior = .transient; popover.contentSize = NSSize(width: 400, height: 480)
        popover.contentViewController = NSHostingController(rootView:Dashboard(monitor:monitor))
        monitor.onUpdate = { [weak self] in
            guard let self else{return}; let r = self.monitor.reading
            let title = "\(watts(r.headlinePower))W"
            self.item.button?.title = title
            let font = self.item.button?.font ?? NSFont.systemFont(ofSize: 11)
            let textWidth = (title as NSString).size(withAttributes: [.font: font]).width
            self.item.length = ceil(textWidth) + 6
            self.item.button?.toolTip = "PowerLens · \(L(r.headlineTitle)) \(watts(r.headlinePower)) W · \(L(r.state))"
        }
        languageSubscription = LanguageSettings.shared.$language.dropFirst().sink { [weak self] _ in
            DispatchQueue.main.async { self?.monitor.onUpdate?() }
        }
        monitor.start()
        if CommandLine.arguments.contains("--preview") {toggle()}
    }
    @objc func toggle() {
        guard let b = item.button else{return}
        if popover.isShown { popover.performClose(nil) }
        else {monitor.refresh();popover.show(relativeTo:b.bounds,of:b,preferredEdge:.minY);NSApp.activate(ignoringOtherApps:true)}
    }
}
if CommandLine.arguments.contains("--self-test") {
    func check(_ c:Bool,_ s:String) {if !c {fatalError(s)}}
    let d = Reading.parse(["Voltage":12000,"InstantAmperage":NSNumber(value: UInt64.max-999),"ExternalConnected":false])
    check(d.battery == -12 && d.load == 12,"discharge")
    let c = Reading.parse(["Voltage":12000,"InstantAmperage":2000,"ExternalConnected":true,"PowerTelemetryData":["SystemPowerIn":60000]])
    check(c.battery == 24 && c.load == 36,"charge")
    check(Reading.parse([:]).battery == nil,"missing")
    check(Reading.parse(["Voltage":12000,"InstantAmperage":0,"ExternalConnected":true]).battery == 0,"plugged idle zero")
    check(Reading.parse(["AdapterDetails":["Watts":140],"ExternalConnected":true]).input == nil,"rated")
    check(Reading.parse(["Voltage":12000,"InstantAmperage":999999]).battery == nil,"invalid")
    let ports = Reading.parse(["PowerOutDetails": [["PortIndex": 2, "Watts": 7078, "AdapterVoltage": 5202, "Current": 1360], ["PortIndex": 3, "Watts": 1500]]])
    check(abs((ports.portPower ?? -1) - 8.578) < 0.00001, "port milliwatt conversion and sum")
    check(Reading.parse([:]).portPower == nil, "missing port telemetry is unknown")
    check(Reading.parse(["PowerOutDetails": [["Watts": 0]]]).portPower == 0, "reported zero is valid")
    check(Reading.parse(["PowerOutDetails": [["Watts": 1000], ["PortIndex": 2]]]).portPower == nil, "partial total must stay unknown")
    check(Reading.parse(["PowerOutDetails": [["Watts": -1]]]).portPower == nil, "negative power rejected")
    check(Reading.parse(["PowerOutDetails": [["Watts": 300000]]]).portPower == nil, "invalid port power rejected")
    check(Reading.parse(["PowerOutDetails": [["PDPowermW": 15000]]]).portPower == nil, "PD capacity must not become measured output")
    let topo = USBPortTopology.make(usbCPorts: [.init(portDescription: "left", portNumber: 1, typeDescription: "USB-C"), .init(portDescription: "right", portNumber: 2, typeDescription: "USB-C")], devices: [.init(portDescription: "right", name: "SSD", deviceClass: 0, locationID: 1)], inputPort: .init(portDescription: "left", portNumber: 1, typeDescription: "USB-C"))
    let out = USBOutputReader.resolve(portRails: .measured(rails: [.init(channel: 1, watts: 300), .init(channel: 2, watts: 3.5)], readAt: Date()), registry: [:], topology: topo)
    check(out?.watts == 3.5 && out?.ports.first?.name == "SSD", "exclude charging channel before cap and name accessory")
    check(USBOutputReader.resolve(portRails: .measured(rails: [.init(channel: 2, watts: 0.1)], readAt: Date()), registry: ["PowerOutDetails": [["Watts": 10000]]]) == nil, "idle live rail must not use stale registry")
    check(USBOutputReader.resolve(portRails: .unavailable, registry: ["PowerOutDetails": [["PortIndex": 2, "Watts": 2461, "PDPowermW": 15000]]])?.watts == 2.461, "fallback measured not negotiated")
    check(SMCReader.decodeBattery(key: "B0AC", type: "si16", bytes: [0x18, 0xfc]) == -1, "SMC signed discharge mA")
    check(SMCReader.decodeBattery(key: "B0AV", type: "ui16", bytes: [0x48, 0x31]) == 12.616, "SMC little-endian mV")
    check(SMCReader.decodeBattery(key: "B0AC", type: "ui16", bytes: [0x18, 0xfc]) == nil, "reject wrong battery type")
    var unplugged = Reading.parse(["Voltage":12000,"InstantAmperage":0,"ExternalConnected":true], externalOverride: false)
    unplugged.applyBattery(volts: 12.616, amps: -1)
    check(unplugged.battery == -12.616 && unplugged.load == 12.616 && unplugged.input == nil, "live discharge supersedes stale registry zero and AC state")
    let average = Reading.parse(["Voltage":12000,"InstantAmperage":0,"Amperage":-1000,"ExternalConnected":false])
    check(average.battery == -12, "average fallback if instant zero offline")
    var unavailable = Reading.parse(["Voltage":12000,"InstantAmperage":0,"ExternalConnected":false])
    unavailable.applyBattery(volts: 12, amps: 0)
    check(unavailable.battery == nil && unavailable.load == nil, "offline zero is unavailable not idle")
    var charging = Reading.parse(["ExternalConnected":true,"PowerTelemetryData":["SystemPowerIn":60000]])
    charging.applyBattery(volts: 12, amps: 2)
    check(charging.battery == 24 && charging.load == 36, "charging budget excludes battery charging")
    check(Reading.parse(["Voltage":12000,"InstantAmperage":NSNumber(value: UInt32.max-999)]).battery == -12, "32 bit negative discharge")
    var standby = Reading()
    standby.external = true; standby.battery = 0; standby.input = 14.9
    check(standby.headlinePower == 14.9 && standby.headlineTitle == "總供電", "standby displays total supply")
    standby.battery = 46.3; standby.input = 72.7
    check(standby.headlinePower == 72.7 && standby.supplyPower == 72.7 && standby.battery == 46.3, "charging: supply stays 72.7 W; battery branch stays 46.3 W")
    standby.external = false; standby.battery = -15.4
    check(standby.headlinePower == 15.4 && standby.supplyPower == 15.4, "discharging: ignore stale adapter reading")
    standby.external = true; standby.input = 20; standby.battery = -10
    check(standby.headlinePower == 30 && standby.supplyPower == 30, "hybrid supply adds battery contribution")
    standby.battery = 0; standby.input = nil
    check(standby.headlinePower == nil, "missing adapter input does not become zero")
    for language in AppLanguage.allCases {
        for (key, values) in Translations.strings {
            check(values.count == 5 && !Translations.text(key, language: language).isEmpty, "translation coverage")
        }
    }
    print("PASS: 29 power checks; complete 5-language translation catalog")
} else if CommandLine.arguments.contains("--render") {
    MainActor.assumeIsolated {
        let monitor = Monitor()
        monitor.reading = sample()
        if CommandLine.arguments.contains("--battery-fixture") {
            // Explicit CLI-only rendering fixture; never used by live monitoring.
            var fixture = Reading.parse(["BatteryInstalled": true, "ExternalConnected": false, "Voltage": 12000, "Amperage": -1550, "CurrentCapacity": 76, "MaxCapacity": 100])
            fixture.applyBattery(volts: 12, amps: -1.55)
            fixture.display = 4.2; fixture.hasPortTelemetry = true
            fixture.portSource = "測試資料"
            fixture.ports = [PortReading(id: 2, power: 3, voltage: 5, current: 0.6, name: "測試設備")]
            fixture.batterySource = "測試資料，非實機讀數"
            monitor.reading = fixture
        }
        if CommandLine.arguments.contains("--charging-fixture") {
            var fixture = Reading.parse(["BatteryInstalled": true, "ExternalConnected": true, "Voltage": 12000, "Amperage": 2000, "CurrentCapacity": 76, "MaxCapacity": 100, "PowerTelemetryData": ["SystemPowerIn": 42600]])
            fixture.applyBattery(volts: 12, amps: 2)
            fixture.display = 4.2; fixture.hasPortTelemetry = true; fixture.portSource = "測試資料"
            fixture.ports = [PortReading(id: 2, power: 3, voltage: 5, current: 0.6, name: "測試設備")]
            monitor.reading = fixture
        }
        monitor.languageMenuOpen = CommandLine.arguments.contains("--show-languages")
        monitor.details = CommandLine.arguments.contains("--show-details")
        let content: AnyView = CommandLine.arguments.contains("--show-about") ? AnyView(AboutView(onBack: {})) : AnyView(Dashboard(monitor: monitor))
        let renderer = ImageRenderer(content: content)
        renderer.scale = 2
        if let cg = renderer.cgImage, let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: CommandLine.arguments.last!) as CFURL, UTType.png.identifier as CFString, 1, nil) {
            CGImageDestinationAddImage(dest, cg, nil)
            print("render=", CGImageDestinationFinalize(dest))
        } else { print("render unavailable") }
    }
} else if CommandLine.arguments.contains("--diagnose") {
    let r = sample()
    print("state=\(r.state) battery=\(watts(r.battery))W batterySource=\(r.batterySource) input=\(watts(r.input))W display=\(watts(r.display))W smc=\(r.smcStatus) ports=\(r.ports.count) portPower=\(watts(r.portPower))W USBDevices=\(r.devices.count)")
} else {
    MainActor.assumeIsolated {
        let app = NSApplication.shared; let delegate = AppDelegate(); app.delegate = delegate; app.run()
    }
}
