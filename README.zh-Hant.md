<p align="center">
  <img src="docs/images/icon.png" width="128" height="128" alt="Triwarden App 圖示">
</p>

<h1 align="center">Triwarden</h1>

<p align="center">
  專為 <a href="https://github.com/dani-garcia/vaultwarden">Vaultwarden</a> 與 Bitwarden 打造的原生 Mac 密碼管理器。<br>
  使用 Swift 與 SwiftUI 開發，支援 macOS 26。
</p>

<p align="center">
  <a href="README.md">English</a> · 繁體中文 · <a href="README.zh-HK.md">粵語</a> ·
  <a href="README.zh-Hans.md">简体中文</a> · <a href="README.ja.md">日本語</a> ·
  <a href="README.ko.md">한국어</a> · <a href="README.fr.md">Français</a> ·
  <a href="README.es.md">Español</a>
</p>

<p align="center">
  <a href="https://github.com/sinhong2011/triwarden/releases/latest/download/Triwarden.dmg"><img src="https://img.shields.io/badge/下載-適用於%20macOS-000000?style=for-the-badge&amp;logo=apple&amp;logoColor=white" alt="下載最新版 Triwarden macOS DMG"></a>
</p>

<p align="center">
  <a href="https://github.com/sinhong2011/triwarden/actions/workflows/ci.yml"><img src="https://github.com/sinhong2011/triwarden/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0-blue" alt="授權條款：GPL-3.0"></a>
  <img src="https://img.shields.io/badge/macOS-26%2B-black?logo=apple" alt="macOS 26 或以上">
  <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&amp;logoColor=white" alt="Swift 6">
</p>

<p align="center">
  <img src="promo/public/shots/vault-dark.png" width="820" alt="Triwarden 深色主題密碼庫畫面">
</p>

> 本翻譯已於 2026 年 11 月 6 日與[英文 README](README.md)同步；英文版保留完整的功能與技術細節。

> **狀態：**目前仍是早期版本（0.x）。Triwarden 已可連接真實的 Vaultwarden 與 Bitwarden 帳戶，
> 並完成兩者的相容性測試；在 1.0 推出前，仍建議保留您原本使用的客戶端。畫面截圖使用內建示範密碼庫。

## 安裝

需要 macOS 26（Tahoe）或更新版本。

```bash
brew install --cask sinhong2011/tap/triwarden
```

您也可以按上方的下載按鈕，取得已簽署並公證的最新版 DMG。您可在「設定 › 關於」檢查已簽署的更新；自動檢查與安裝須自行開啟。

## 開始使用

1. 開啟 Triwarden，選擇您的 Vaultwarden 伺服器、Bitwarden US 或 Bitwarden EU，然後登入現有帳戶。
2. 前往「系統設定 › 一般 › 自動填寫與密碼」啟用 Triwarden，即可填寫密碼、通行密鑰與驗證碼。
3. 在 Triwarden 中按 **⌘F** 搜尋密碼庫；在任何 App 中按 **⇧⌘Space** 開啟指令面板。
   自動輸入需要授予 **Triwarden Auto-Type** 輔助使用權限；瀏覽器擴充功能則可在設定中選用及連接。

**離線使用：**您可以解鎖並查看已加密儲存在這部 Mac 上的密碼庫。新增、編輯、匯入與刪除項目時必須連線到伺服器；變更不會排隊等待稍後上傳。

**官方版本與付費授權：**個人使用可永久免費使用所有功能。使用官方版本管理工作帳戶時，每位使用者需要一組一次性付費授權；一組授權涵蓋該使用者的所有 Mac。詳情請參閱[付費授權條款](docs/LICENSE-TERMS.md)。

## 功能

**原生密碼庫體驗**

- 管理登入資料、安全筆記、信用卡、身分資料與 SSH 金鑰，並支援資料夾、收藏、自訂欄位、附件、封存區及垃圾桶。
- 同時使用多個 Vaultwarden 或 Bitwarden 帳戶，包括共享密碼庫與集合；透過 WebSocket 即時同步。支援密碼、雙重驗證與單一登入（SSO）。
- 搜尋所有密碼庫，以類型、資料夾、收藏、一次性密碼、通行密鑰及 Watchtower 問題篩選結果。
- 在項目編輯器中新增、下載或移除附件；從目前瀏覽器分頁新增登入資料時，自動預填網站資訊。

**快速取用**

- 在任何 App 中使用指令面板尋找項目、複製資料或自動輸入使用者名稱與密碼。
- 自訂全域快速鍵，從選單列面板查看相關登入資料、一次性密碼及密碼產生器。
- Safari、Chrome、Edge、Brave 與 Firefox 的瀏覽器擴充功能可在 App 內核准後填寫及儲存登入資料。通行密鑰登入使用 macOS 系統自動填寫；瀏覽器擴充功能目前尚未處理通行密鑰登入。

**macOS 整合與安全工具**

- 系統自動填寫支援密碼、通行密鑰與一次性密碼；可使用 Touch ID 或 PIN 解鎖。
- 已複製的機密資料會自動從剪貼簿清除；SSH agent 可使用密碼庫中的 SSH 金鑰簽署 Git 提交。
- 可在螢幕分享、錄影與截圖時隱藏 Triwarden；自架伺服器可使用私人 CA 與 Cloudflare Access 等額外請求標頭。
- Watchtower 會找出弱密碼、重複使用、外洩及不安全的密碼，並提示尚未啟用雙重驗證的網站。
- 支援雙重驗證、裝置管理、緊急存取、Send、密碼與使用者名稱產生器，以及多種匯入／匯出格式。

完整功能與限制請參閱[英文 README](README.md)及[產品路線圖](docs/ROADMAP.md)。

## 命令列與本機 API 金鑰

在「設定 › 開發者」啟用 **Answer the tw command**，再使用 **Terminal Helper Setup…** 安裝 `tw`。

```bash
tw get github | pbcopy
tw code github
tw status
tw run
tw tools list
tw generate --length 32
tw lock
```

本機 API 金鑰功能預設隱藏。啟用「設定 › 開發者 › Show Secrets」後，可按照引導完成「儲存金鑰 → 提供給工具或專案 → 檢查授權 → 再次使用」的流程。請參閱[入門指南](docs/local-api-keys-getting-started.md)。
每個 API 金鑰項目會顯示使用它的工具；「Access › Permissions」與「Access › History」可檢查有效授權與過往決定。

## 從原始碼建置

需要 macOS 26、Xcode 26、[XcodeGen](https://github.com/yonaskolb/XcodeGen)、Node.js 與 pnpm。

```bash
brew install xcodegen node pnpm
```

```bash
git clone https://github.com/sinhong2011/triwarden.git
cd triwarden
make run
```

執行 `make` 可查看所有指令；常用指令包括 `make test`、`make selftest`、`make uitest` 與 `make snapshots`。

## 安全性、輔助使用與語言

您的主密碼與金鑰不會離開這部 Mac；伺服器只會收到加密資料。詳情與漏洞回報方式請參閱 [SECURITY.md](SECURITY.md)。

Triwarden 提供 VoiceOver 標籤、鍵盤快速鍵、增加對比與減少動態效果支援。App 支援 English、繁體中文、粵語、简体中文、日本語、한국어、Français、Español 及ไทย；已知限制請參閱 [ACCESSIBILITY.md](ACCESSIBILITY.md)。

## 支援與貢獻

購買或產品問題請寄信至 [support@triwarden.cc](mailto:support@triwarden.cc)。錯誤回報與功能建議請建立 [GitHub issue](https://github.com/sinhong2011/triwarden/issues)。歡迎提交 issue 與 pull request；發布流程請參閱 [docs/RELEASING.md](docs/RELEASING.md)。

## 授權條款

Triwarden 是依 [GNU General Public License v3.0](LICENSE) 發布的自由軟體。程式碼授權不包含「Triwarden」名稱與 App 圖示；修改版本必須使用自己的名稱與圖示。Triwarden 與 Bitwarden, Inc. 或 Vaultwarden 專案沒有從屬或合作關係。
