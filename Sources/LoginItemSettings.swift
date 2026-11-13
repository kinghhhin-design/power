import AppKit
import SwiftUI
import ServiceManagement

/// The OS owns persistence; never show a saved preference as proof of registration.
@MainActor final class LoginItemSettings: ObservableObject {
    @Published private(set) var status = SMAppService.mainApp.status
    @Published var errorMessage: String?
    var requested: Bool { status == .enabled || status == .requiresApproval }
    func refresh() { status = SMAppService.mainApp.status }
    func setEnabled(_ enabled: Bool) {
        refresh()
        do {
            if enabled {
                if status == .requiresApproval {
                    SMAppService.openSystemSettingsLoginItems()
                } else if status != .enabled {
                    try SMAppService.mainApp.register()
                }
            } else if requested {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        refresh()
    }
}

struct LoginItemMenu: View {
    @StateObject private var settings = LoginItemSettings()
    @ObservedObject private var language = LanguageSettings.shared
    var body: some View {
        Menu {
            Toggle(L("開機自啟動"), isOn: Binding(
                get: { settings.requested }, set: { settings.setEnabled($0) }))
            Text(L("登入 Mac 時自動啟動"))
            if settings.status == .requiresApproval {
                Button(L("需要批准 · 開啟系統設定")) {
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
        } label: {
            Image(systemName: "gearshape")
        }
        .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
        .help(L("設定")).accessibilityLabel(L("設定"))
        .onAppear { settings.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in settings.refresh() }
        .onReceive(Timer.publish(every: 2, on: .main, in: .common).autoconnect()) { _ in settings.refresh() }
        .alert(L("無法更改自啟動設定"), isPresented: Binding(
            get: { settings.errorMessage != nil },
            set: { if !$0 { settings.errorMessage = nil } })) {
                Button(L("好"), role: .cancel) { settings.errorMessage = nil }
            } message: { Text(settings.errorMessage ?? "") }
    }
}
