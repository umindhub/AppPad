<p align="center">
  <img src="../../AppPad/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" alt="AppPad">
</p>

<h1 align="center">AppPad</h1>

<p align="center">
  把原汁原味的啟動台帶回到 macOS 26+，也支援 macOS 15 —— 另附剪貼簿、工作流程、App 快速鍵與視窗控制。
</p>

<p align="center">
  <a href="https://apppad.youmindhub.com">官網</a><br>
  <a href="#wechat-donate">☕ 微信讚賞</a>
</p>

<p align="center">
  <a href="../../README.md">English</a> ·
  <a href="README.zh-CN.md">简体中文</a> ·
  繁體中文 ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.ko.md">한국어</a> ·
  <a href="README.de.md">Deutsch</a> ·
  <a href="README.es.md">Español</a> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.it.md">Italiano</a> ·
  <a href="README.nl.md">Nederlands</a>
</p>

---

## 安裝

### 方式一：下載 DMG

[下載最新版本](https://github.com/umindhub/AppPad/releases/latest)，打開 DMG 後將 AppPad 拖入「應用程式」檔案夾。

### 方式二：Homebrew

```bash
brew tap umindhub/tap
brew trust umindhub/tap
brew install --cask apppad
```

## 功能

### 啟動台
- 完整還原經典 macOS 啟動台，預設佈局與系統順序一致
- 四指捏合、選單列或點按 Dock 中的 AppPad 開啟（再次點按關閉）
- 檔案夾、拖移排序 / 合併成檔案夾，長按圖像或按住 ⌥ 進入編輯模式
- 內建乾淨解除安裝：刪除 App 的同時清除殘留檔案
- 格狀搜尋、頁面指示器（圓點 / 數字）、「液態玻璃」控制項目（macOS 26+）
- 背景：白色 / 淺灰色 / 深灰色 / 背景圖片 / 自訂顏色，淺色與深色外觀分別儲存設定

### 剪貼簿
- 支援文字和圖片永久保存
- 拷貝的內容可儲存
- `⌘1`–`⌘0` 快速貼上，來源 App 篩選和 `App名稱::` 搜尋語法，右側即時預覽

### 工作流程 & AI MCP
- `⌘Space` 開啟工作流程面板：App 與工作流程依使用頻率統一排序
- 工作流程可執行 Shell 腳本、AppleScript、捷徑或 HTTP 請求，支援參數（如 `time 10`）
- 內建：清空垃圾桶、設定倒數計時、設定鬧鐘、設定音量、結束所有 App……
- 權限宣告由真正的沙盒強制執行（允許一次 / 不允許 / 永遠允許）
- 以 JSON 檔案或連結匯入、分享工作流程
- 內建 MCP 服務：支援 MCP 的 AI 助理可直接呼叫和控制你的工作流程
- AI 可透過 MCP 讀取工作流程撰寫規範，直接幫你建立新的工作流程
- AI 執行的工作流程與你手動執行一樣，經過同一套權限確認與沙盒

### 計算機
- 在工作流程面板搜尋欄直接輸入算式即可計算（支援科學記號）

### App 快速鍵
- 為任意 App 設定全域快速鍵

### 視窗控制
- 靠左 / 靠右排列（½ → ⅓ → ⅔）、最大化、復原、移到其他顯示器，快速鍵皆可自訂

### 其他
- 支援開機啟動
- `⌘⇧J` / `⌘⇧K` 在啟動台、剪貼簿、工作流程面板之間變形切換
- 10 種語言：德、英、西、法、義、日、韓、荷、簡中、繁中

## 系統需求

- macOS 15 或以上版本
- Xcode 27（從原始碼建置）

## 建置

1. 開啟 `AppPad.xcodeproj`
2. 選擇 Scheme：`AppPad Dev`、`AppPad Beta` 或 `AppPad`
3. 設定你自己的簽署 Team，然後建置並執行

相依套件由 Swift Package Manager 自動取得。

## 授權條款

AppPad 採用分層授權：

| 部分 | 授權 |
| --- | --- |
| AppPad 應用程式原始碼（下方未列出的全部內容） | [AGPL-3.0](../../LICENSE) |
| 內建工作流程（`AppPad/Workflow/BuiltinWorkflows.swift`、`*.shortcut`） | [MIT](../../LICENSE-MIT) |
| 工作流程格式規範 | [MIT](../../LICENSE-MIT) |
| 工作流程市集中的第三方工作流程 | [MIT](../../LICENSE-MIT)，版權歸各作者 |

- **AGPL-3.0**：可以使用、修改和再散布 AppPad，但散布或透過網路提供的衍生作品必須同樣以 AGPL-3.0 公開全部原始碼。
- **商業授權**：如需閉源或專有用途，請透過[官網](https://apppad.youmindhub.com)聯絡作者取得商業授權。
- **工作流程採用 MIT**：任何人都可以自由編寫、分享甚至販售工作流程，也可以在其他工具中實作該工作流程格式，不受 AGPL 約束。
- 你自己編寫的工作流程歸你所有；提交到工作流程市集的工作流程須採用 MIT 授權。
- 「AppPad」名稱與圖像不在上述授權範圍內，分支專案須使用不同的名稱和圖像。

## 參與貢獻

歡迎提交 Issue 和 Pull Request。提交貢獻即表示你同意該貢獻依所修改部分的授權發布，並授權維護者同時以商業授權散布你的貢獻。

## 致謝

- [GRDB.swift](https://github.com/groue/GRDB.swift) —— MIT 授權
- [Sparkle](https://github.com/sparkle-project/Sparkle) —— MIT 授權

<a id="wechat-donate"></a>

## 支持 AppPad

AppPad 免費且開源。如果它讓你的 Mac 用起來更順手一點，歡迎用微信請我喝杯咖啡，金額隨意；幫專案點個 Star 也是很大的鼓勵。謝謝你！

<p align="center">
  <img src="../images/wechat-donate.png" width="300" alt="WeChat">
  <br>
  <sub>使用微信掃一掃</sub>
</p>

---

© 2026 YouMindHub
