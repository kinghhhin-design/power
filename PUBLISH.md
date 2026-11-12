# GitHub 發布說明

此資料夾包含 PowerLens 1.9.5 的發布文件，尚未上傳 GitHub。

## 1. 上傳原始碼

建立 GitHub 倉庫，將本資料夾內的 Sources、Assets、Resources、build.command、README.md、LICENSE、第三方 LICENSE/NOTICE、PUBLISH.md 及 RELEASE_NOTES.md 上傳到倉庫根目錄。使用 Git 時也提交 .gitignore。

不要把 release 資料夾或解壓後的 .app 當作原始碼提交。資料夾內沒有帳號憑證或個人診斷日誌。發布前確認專案授權選擇；第三方授權與 NOTICE 必須保留。

## 2. 建立下載版本

在倉庫的 Releases 選 Draft a new release：

- Tag：v1.9.5
- Title：PowerLens v1.9.5
- 說明：貼上 RELEASE_NOTES.md 的內容。
- 附件：上傳 release 內的 App ZIP 與 SHA256SUMS.txt。

檢查後發布。GitHub 會自行提供 Source code 壓縮包。

此版本是 Apple Silicon、本機 ad-hoc 簽署且未公證。正式廣泛發佈前可使用自己的 Developer ID 簽署、公證並重新壓縮及計算校驗碼。現有包未宣稱可繞過 Gatekeeper。

官方操作說明：https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository
