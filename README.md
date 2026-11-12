# PowerLens

原生 macOS 選單列電力監測工具，使用 SwiftUI、AppKit 和 IOKit。

## 功能

- 選單列、面板主讀數及流向圖統一顯示總供電。
- 顯示電池充放電、內置螢幕背光、USB-C 接口供電與系統估算功率。
- 深色毛玻璃面板、動態電力流向、接口與設備明細。
- 支援繁體中文、简体中文、English、한국어、日本語，記住語言選擇。
- 本機唯讀取樣，沒有網絡傳輸或修改充電設定。

## 安裝

從 [Releases](https://github.com/kinghhhin-design/power/releases/latest) 下載 App ZIP，解壓後將 PowerLens.app 拖到「應用程式」。升級前請先結束舊版。

目前發布包為 Apple Silicon arm64，最低部署目標 macOS 13。未在所有 macOS 版本和機型驗證。App 使用 ad-hoc 簽署，沒有 Developer ID 公證，因此下載後可能受到 Gatekeeper 限制；亦可自行從原始碼建置。

## 建置

需要 macOS 及 Xcode Command Line Tools。在專案根目錄執行：

```sh
chmod +x build.command
./build.command
```

產生 PowerLens.app，並執行 29 項功率檢查及五語言翻譯完整性檢查。建置腳本依本機架構編譯；Intel 版本需自行建置與驗證。

```sh
./PowerLens.app/Contents/MacOS/PowerLens --diagnose
./PowerLens.app/Contents/MacOS/PowerLens --self-test
```

## 讀數含義

電池優先使用 SMC B0AV × B0AC，回退 IOKit 電流與電壓。背光使用 PDBR／PBwo／PBLR。USB-C 供電優先使用 D1–D4 電壓 × 電流並排除充電輸入接口，回退 PowerOutDetails.Watts，不使用 PD 協商容量代替實測。

系統功率是總負載扣除已知分項後的估算，仍可能包含未分離損耗與設備。背光不代表整個顯示器的耗電。接口通道映射未在所有機型驗證，HDMI、音訊等不屬於此供電合計。低於 0.20 W 的接口視為待機；資料不可用顯示「—」。底層感測器更新頻率可能比兩秒取樣慢。

## 專案結構

- `Sources/`：完整 Swift 原始碼。
- `Assets/`：App 圖示 SVG、PNG、ICNS。
- `Resources/Info.plist`：目前版本的 App 資訊參考；建置腳本內亦包含此設定。
- `build.command`：建置與驗證腳本。
- `LICENSE-StatusTrio.txt`、`NOTICE-StatusTrio.txt`：第三方授權與聲明。
- `release/`：本地準備的 Release 附件，不提交到程式碼倉庫。

接口供電解析與設備映射包含 Status Trio v1.9.5 的 Apache-2.0 程式碼，詳見附帶聲明。本專案採用 Apache-2.0 授權，詳見 `LICENSE`。
