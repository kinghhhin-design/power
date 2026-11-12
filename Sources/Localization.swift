import Foundation
import Combine

enum AppLanguage: String, CaseIterable, Identifiable {
    case traditional = "zh-Hant", simplified = "zh-Hans", english = "en", korean = "ko", japanese = "ja"
    var id: String { rawValue }
    var name: String {
        switch self {
        case .traditional: return "繁體中文"
        case .simplified: return "简体中文"
        case .english: return "English"
        case .korean: return "한국어"
        case .japanese: return "日本語"
        }
    }
    var shortName: String {
        switch self {
        case .traditional: return "繁中"
        case .simplified: return "简中"
        case .english: return "EN"
        case .korean: return "한국어"
        case .japanese: return "日本語"
        }
    }
    var column: Int { switch self { case .traditional: return 0; case .simplified: return 1; case .english: return 2; case .korean: return 3; case .japanese: return 4 } }
}
final class LanguageSettings: ObservableObject {
    static let shared = LanguageSettings()
    @Published var language: AppLanguage {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "interfaceLanguage") }
    }
    init() {
        language = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "interfaceLanguage") ?? "") ?? .traditional
        // CLI preview only; does not change the user's saved preference.
        if let index = CommandLine.arguments.firstIndex(of: "--language"), CommandLine.arguments.count > index+1,
           let selected = AppLanguage(rawValue: CommandLine.arguments[index+1]) { language = selected }
    }
}
enum Translations {
    static let strings: [String: [String]] = [
        "總供電": ["總供電", "总供电", "Total supply", "총 공급 전력", "総供給電力"],
        "關於 PowerLens": ["關於 PowerLens", "关于 PowerLens", "About PowerLens", "PowerLens 정보", "PowerLens について"],
        "選單列上的即時電力監測": ["選單列上的即時電力監測", "菜单栏上的实时电力监测", "Live power monitoring in your menu bar", "메뉴 막대의 실시간 전력 모니터", "メニューバーで電力をリアルタイムに確認"],
        "即時讀數": ["即時讀數", "实时读数", "Live readings", "실시간 측정값", "リアルタイム測定"],
        "每 2 秒讀取電源、電池、螢幕與接口功率。選單列顯示與流向圖一致的總供電功率。": ["每 2 秒讀取電源、電池、螢幕與接口功率。選單列顯示與流向圖一致的總供電功率。", "每 2 秒读取电源、电池、屏幕与接口功率。菜单栏显示与流向图一致的总供电功率。", "Reads input, battery, display and port power every 2 seconds. The menu bar shows total supply, matching the flow diagram.", "2초마다 전원, 배터리, 화면 및 포트 전력을 읽습니다. 메뉴 막대는 흐름도와 동일한 총 공급 전력을 표시합니다.", "2秒ごとに電源・バッテリー・画面・ポートの電力を取得。メニューバーにはフロー図と同じ総供給電力を表示します。"],
        "讀數說明": ["讀數說明", "读数说明", "Understanding the numbers", "측정값 안내", "数値について"],
        "螢幕數值為背光功率；系統數值為扣除已知分項後的估算。感測資料不可用時顯示「—」。": ["螢幕數值為背光功率；系統數值為扣除已知分項後的估算。感測資料不可用時顯示「—」。", "屏幕数值为背光功率；系统数值为扣除已知分项后的估算。传感数据不可用时显示“—”。", "Display power measures the backlight. System power is estimated after subtracting known components. Unavailable readings appear as “—”.", "화면 전력은 백라이트 측정값입니다. 시스템 전력은 알려진 항목을 뺀 추정값이며, 측정할 수 없는 값은 “—”로 표시합니다.", "画面の数値はバックライト電力です。システム電力は既知の項目を差し引いた推定値です。取得できない値は「—」で表示します。"],
        "本機運作": ["本機運作", "本机运行", "On your Mac", "Mac에서만 처리", "Mac 内で動作"],
        "只讀取電力資料，不調整充電設定，也不傳送資料。": ["只讀取電力資料，不調整充電設定，也不傳送資料。", "只读取电力数据，不调整充电设置，也不传送数据。", "Reads power data without changing charging settings or sending data over the network.", "전력 정보만 읽으며, 충전 설정을 변경하거나 네트워크로 정보를 전송하지 않습니다.", "電力情報を読み取るだけで、充電設定の変更やネットワークへのデータ送信は行いません。"],
        "開源致謝": ["開源致謝", "开源致谢", "Open-source credits", "오픈 소스 크레딧", "オープンソースへの謝辞"],

        "電源輸入": ["電源輸入", "电源输入", "Power input", "전원 입력", "電源入力"],
        "電池功率": ["電池功率", "电池功率", "Battery power", "배터리 전력", "バッテリー電力"],
        "電池充電": ["電池充電", "电池充电", "Battery charging", "배터리 충전", "バッテリー充電"],
        "電池放電": ["電池放電", "电池放电", "Battery discharge", "배터리 방전", "バッテリー放電"],
        "電池待機": ["電池待機", "电池待机", "Battery idle", "배터리 대기", "バッテリー待機"],
        "未回報功率": ["未回報功率", "未报告功率", "Power unavailable", "전력 정보 없음", "電力情報なし"],
        "未找到電池": ["未找到電池", "未找到电池", "No battery detected", "배터리 없음", "バッテリー未検出"],
        "電池數據更新中": ["電池數據更新中", "电池数据更新中", "Updating battery data", "배터리 정보 갱신 중", "バッテリー情報を更新中"],
        "電池供電 · 更新中": ["電池供電 · 更新中", "电池供电 · 更新中", "On battery · updating", "배터리 사용 · 갱신 중", "バッテリー使用 · 更新中"],
        "電池充電中": ["電池充電中", "电池充电中", "Charging battery", "배터리 충전 중", "バッテリー充電中"],
        "電池放電中": ["電池放電中", "电池放电中", "Running on battery", "배터리 사용 중", "バッテリー使用中"],
        "外接電源 · 電池待機": ["外接電源 · 電池待機", "外接电源 · 电池待机", "Plugged in · battery idle", "외부 전원 · 배터리 대기", "外部電源 · バッテリー待機"],
        "IORegistry 電壓 × 電流": ["IORegistry 電壓 × 電流", "IORegistry 电压 × 电流", "IORegistry voltage × current", "IORegistry 전압 × 전류", "IORegistry 電圧 × 電流"],
        "電池平均電流 × 電壓": ["電池平均電流 × 電壓", "电池平均电流 × 电压", "Average current × voltage", "평균 전류 × 전압", "平均電流 × 電圧"],
        "電池即時電流 × 電壓": ["電池即時電流 × 電壓", "电池实时电流 × 电压", "Live current × voltage", "실시간 전류 × 전압", "リアルタイム電流 × 電圧"],
        "SMC 即時電壓 × 電流": ["SMC 即時電壓 × 電流", "SMC 实时电压 × 电流", "Live SMC voltage × current", "SMC 실시간 전압 × 전류", "SMC リアルタイム電圧 × 電流"],
        "正在等待放電感測值": ["正在等待放電感測值", "正在等待放电读数", "Waiting for discharge reading", "방전 측정값 대기 중", "放電の測定値を待機中"],
        "未找到 SMC": ["未找到 SMC", "未找到 SMC", "SMC not found", "SMC 없음", "SMC が見つかりません"],
        "SMC 存取被拒絕 ({0})": ["SMC 存取被拒絕 ({0})", "SMC 访问被拒绝 ({0})", "SMC access denied ({0})", "SMC 접근 거부 ({0})", "SMC アクセス拒否 ({0})"],
        "IORegistry 實測值": ["IORegistry 實測值", "IORegistry 实测值", "IORegistry measurement", "IORegistry 측정값", "IORegistry 測定値"],
        "低於 0.20 W 顯示門檻": ["低於 0.20 W 顯示門檻", "低于 0.20 W 显示阈值", "Below 0.20 W threshold", "0.20 W 표시 기준 미만", "表示しきい値 0.20 W 未満"],
        "電源輸入 →": ["電源輸入 →", "电源输入 →", "Power input →", "전원 입력 →", "電源入力 →"],
        "電池供電 →": ["電池供電 →", "电池供电 →", "Battery power →", "배터리 전원 →", "バッテリー供給 →"],
        "電池輔助供電 →": ["電池輔助供電 →", "电池辅助供电 →", "Battery assist →", "배터리 보조 →", "バッテリー補助 →"],
        "系統": ["系統", "系统", "System", "시스템", "システム"],
        "螢幕": ["螢幕", "屏幕", "Display", "디스플레이", "ディスプレイ"],
        "接口": ["接口", "接口", "Ports", "포트", "ポート"],
        "供電 W": ["供電 W", "供电 W", "Supply W", "공급 W", "供給 W"],
        "電源與放電電池在左，充電電池在右；流帶寬度為示意。": ["電源與放電電池在左，充電電池在右；流帶寬度為示意。", "电源与放电电池在左，充电电池在右；流带宽度为示意。", "Sources are on the left; a charging battery is on the right. Band widths are illustrative.", "전원은 왼쪽, 충전 중인 배터리는 오른쪽에 표시됩니다. 흐름의 폭은 예시입니다.", "電源と放電中のバッテリーは左、充電中のバッテリーは右に表示。帯の幅は模式的です。"],
        "系統功率": ["系統功率", "系统功率", "System power", "시스템 전력", "システム電力"],
        "等待整機與螢幕資料": ["等待整機與螢幕資料", "等待整机与屏幕数据", "Waiting for system and display", "시스템 및 디스플레이 정보 대기", "本体・ディスプレイ情報を待機"],
        "含晶片及未分離接口": ["含晶片及未分離接口", "含芯片及未分离接口", "Includes chip and unseparated ports", "칩 및 미분리 포트 포함", "チップ・未分離ポートを含む"],
        "含晶片 · 扣除螢幕及已回報接口": ["含晶片 · 扣除螢幕及已回報接口", "含芯片 · 扣除屏幕及已报告接口", "Chip included; display & ports excluded", "칩 포함 · 화면 및 측정 포트 제외", "チップを含む・画面と測定済ポートを除く"],
        "螢幕功率": ["螢幕功率", "屏幕功率", "Display power", "디스플레이 전력", "ディスプレイ電力"],
        "內置螢幕背光": ["內置螢幕背光", "内置屏幕背光", "Built-in display backlight", "내장 화면 백라이트", "内蔵ディスプレイのバックライト"],
        "接口供電  ›": ["接口供電  ›", "接口供电  ›", "Port output  ›", "포트 출력  ›", "ポート出力  ›"],
        " · 點擊查看": [" · 點擊查看", " · 点击查看", " · Details", " · 자세히", " · 詳細"],
        "正在更新感測資料": ["正在更新感測資料", "正在更新传感数据", "Updating sensor data", "센서 정보 갱신 중", "センサー情報を更新中"],
        "待機 · 未充放電": ["待機 · 未充放電", "待机 · 未充放电", "Idle · no charge or discharge", "대기 · 충전 및 방전 없음", "待機 · 充放電なし"],
        "即時功率": ["即時功率", "实时功率", "Live power", "실시간 전력", "リアルタイム電力"],
        "每 2 秒讀取": ["每 2 秒讀取", "每 2 秒读取", "Every 2 sec", "2초마다 갱신", "2秒ごとに更新"],
        "結束": ["結束", "退出", "Quit", "종료", "終了"],
        "語言": ["語言", "语言", "Language", "언어", "言語"],
        "接口與感測資料": ["接口與感測資料", "接口与传感数据", "Ports & sensors", "포트 및 센서", "ポートとセンサー"],
        "返回": ["返回", "返回", "Back", "뒤로", "戻る"],
        "接口供電：": ["接口供電：", "接口供电：", "Port output: ", "포트 출력: ", "ポート出力："],
        "已回應的接口未有超過 0.20 W 的對外供電。": ["已回應的接口未有超過 0.20 W 的對外供電。", "已响应的接口没有超过 0.20 W 的对外供电。", "No responding port reports output above 0.20 W.", "응답한 포트의 출력이 0.20 W를 넘지 않습니다.", "応答したポートに 0.20 W を超える出力はありません。"],
        "系統未回報接口功率；不代表沒有連接設備。": ["系統未回報接口功率；不代表沒有連接設備。", "系统未报告接口功率；不代表没有连接设备。", "No port power was reported. Devices may still be connected.", "포트 전력이 보고되지 않았습니다. 기기가 연결되어 있을 수 있습니다.", "ポート電力は未報告です。機器が未接続とは限りません。"],
        "USB-C 通道 {0}": ["USB-C 通道 {0}", "USB-C 通道 {0}", "USB-C channel {0}", "USB-C 채널 {0}", "USB-C チャンネル {0}"],
        "USB 裝置名稱": ["USB 裝置名稱", "USB 设备名称", "USB device names", "USB 기기 이름", "USB デバイス名"],
        "未取得裝置名稱；不能據此判定未連接。": ["未取得裝置名稱；不能據此判定未連接。", "未取得设备名称；不能据此判定未连接。", "No device names available; this does not mean disconnected.", "기기 이름이 없습니다. 연결되지 않았다는 의미는 아닙니다.", "デバイス名を取得できません。未接続とは限りません。"],
        "外接輸入：{0} W · 整機：{1} W": ["外接輸入：{0} W · 整機：{1} W", "外接输入：{0} W · 整机：{1} W", "Input: {0} W · System total: {1} W", "입력: {0} W · 전체: {1} W", "入力：{0} W · 本体合計：{1} W"],
        "電池功率來源：": ["電池功率來源：", "电池功率来源：", "Battery power source: ", "배터리 전력 출처: ", "バッテリー電力の取得元："],
        "電池溫度：": ["電池溫度：", "电池温度：", "Battery temperature: ", "배터리 온도: ", "バッテリー温度："],
        "測試資料": ["測試資料", "测试数据", "Test data", "테스트 데이터", "テストデータ"],
        "測試設備": ["測試設備", "测试设备", "Test device", "테스트 기기", "テスト機器"],
        "測試資料，非實機讀數": ["測試資料，非實機讀數", "测试数据，非实机读数", "Test data, not a live reading", "테스트 데이터이며 실제 측정값이 아님", "テストデータ・実測値ではありません"],
        "ports_info": ["來源：{0}。優先讀取 D1–D4 電壓 × 電流，排除充電輸入接口；無 SMC 回應才讀 PowerOutDetails.Watts。不使用 PD 協商容量。低於 0.20 W 視為待機。通道依 USB-C 端口排序映射，非所有機型都已驗證；HDMI／音訊不包含在這個供電合計。", "来源：{0}。优先读取 D1–D4 电压 × 电流，排除充电输入接口；无 SMC 响应才读 PowerOutDetails.Watts。不使用 PD 协商容量。低于 0.20 W 视为待机。通道依 USB-C 端口排序映射，并非所有机型均已验证；HDMI／音频不在此合计内。", "Source: {0}. Uses D1–D4 voltage × current, excluding the charging input port. Falls back to PowerOutDetails.Watts only if SMC does not respond. PD contract capacity is not used. Below 0.20 W is idle. Channel mapping follows USB-C port order and is not verified on every model. HDMI/audio are excluded.", "출처: {0}. 충전 입력 포트를 제외한 D1–D4 전압 × 전류를 사용합니다. SMC 응답이 없을 때만 PowerOutDetails.Watts를 사용합니다. PD 협상 용량은 사용하지 않습니다. 0.20 W 미만은 대기로 처리합니다. 채널은 USB-C 포트 순서이며 모든 모델에서 검증되지는 않았습니다. HDMI/오디오는 제외됩니다.", "取得元：{0}。充電入力ポートを除き、D1–D4 の電圧 × 電流を使用します。SMC が応答しない場合のみ PowerOutDetails.Watts を使用。PD の契約電力は使用しません。0.20 W 未満は待機扱いです。USB-C の順序でチャンネルを対応付けますが、全モデルでの検証は未完了です。HDMI・音声は対象外です。"],
        "display_info": ["螢幕：SMC {0}，為背光電源軌。系統＝整機−背光−已回報接口，仍含其他未分離的損耗及設備。接口資料缺失時，系統值仍包含接口，會另作標示。", "屏幕：SMC {0}，读取背光电源轨。系统＝整机−背光−已报告接口，仍含其他未分离损耗和设备。接口数据缺失时，系统值仍包含接口，并另作标示。", "Display: SMC {0}, measuring the backlight rail. System = total − backlight − reported ports; other losses and devices remain included. If port data is missing, system power still includes ports and is labelled accordingly.", "디스플레이: SMC {0}, 백라이트 전원 레일 측정값입니다. 시스템 = 전체 − 백라이트 − 보고된 포트이며 기타 손실과 기기를 포함합니다. 포트 정보가 없으면 시스템 전력에 포트가 포함되며 별도로 표시합니다.", "画面：SMC {0}、バックライトの電源レールを測定。本体合計からバックライトと報告済みポートを差し引きます。その他の損失や機器は含まれます。ポート情報がない場合はシステム電力に含み、その旨を表示します。"],
    ]
    static func text(_ key: String, language: AppLanguage) -> String {
        strings[key]?[language.column] ?? key
    }
}
func L(_ key: String) -> String { Translations.text(key, language: LanguageSettings.shared.language) }
func LF(_ key: String, _ args: String...) -> String {
    args.enumerated().reduce(L(key)) { $0.replacingOccurrences(of: "{\($1.offset)}", with: $1.element) }
}

func localizedSMCStatus(_ status: String) -> String {
    let prefix = "SMC 存取被拒絕 ("
    if status.hasPrefix(prefix), status.hasSuffix(")") {
        return LF("SMC 存取被拒絕 ({0})", String(status.dropFirst(prefix.count).dropLast()))
    }
    return L(status)
}
