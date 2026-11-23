<p align="center">
  <img src="docs/images/icon.png" width="128" height="128" alt="Triwarden App 圖示">
</p>

<h1 align="center">Triwarden</h1>

<p align="center">
  為 <a href="https://github.com/dani-garcia/vaultwarden">Vaultwarden</a> 同 Bitwarden 而設嘅原生 Mac 密碼管理器。<br>
  用 Swift 同 SwiftUI 開發，支援 macOS 26。
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README.zh-Hant.md">繁體中文</a> · 粵語 ·
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

> 呢個翻譯已經喺 2026 年 11 月 22 日同[英文 README](README.md)同步；完整功能同技術細節以英文版為準。

> **狀態：**而家仲係早期版本（0.x）。Triwarden 已經可以連接真正嘅 Vaultwarden 同 Bitwarden 帳戶，
> 亦測試過兩邊嘅相容性；1.0 推出之前，建議你保留平時用開嘅客戶端。截圖用嘅係內置示範密碼庫。

## 安裝

需要 macOS 26（Tahoe）或更新版本。

```bash
brew install --cask sinhong2011/tap/triwarden
```

你亦可以撳上面嘅下載按鈕，直接拎到已簽署同公證嘅最新 DMG。你可以喺「設定 › 關於」檢查已簽署嘅更新；自動檢查同安裝要自己開啟。

## 開始使用

1. 開 Triwarden，揀你嘅 Vaultwarden 伺服器、Bitwarden US 或 Bitwarden EU，再登入現有帳戶。
2. 去「系統設定 › 一般 › 自動填寫與密碼」開啟 Triwarden，就可以填密碼、通行密鑰同驗證碼。
3. 喺 Triwarden 撳 **⌘F** 搜尋密碼庫；喺任何 App 撳 **⇧⌘Space** 開指令面板。
   自動輸入要畀 **Triwarden Auto-Type** 輔助使用權限；瀏覽器擴充功能就可以喺設定入面選擇同連接。

**離線使用：**你可以解鎖同睇返加密儲存喺呢部 Mac 嘅密碼庫。新增、編輯、匯入同刪除項目就要連線去伺服器；變更唔會排隊等遲啲先上傳。

**官方版本同付費授權：**個人使用唔使付費授權，都可以永久用晒所有功能。大約 30 日之後，未註冊嘅官方版本可能會喺開啟時顯示購買提醒，最多每星期一次；一次性付費授權可以移除提醒，並包該使用者所有 Mac。用官方版本管理工作帳戶時，每位使用者要有一組付費授權。詳情請睇[付費授權條款](docs/LICENSE-TERMS.md)。

## 功能

**原生密碼庫體驗**

- 管理登入資料、安全筆記、信用卡、身份資料、SSH 金鑰、銀行戶口、駕駛執照同護照，亦支援資料夾、收藏、自訂欄位、附件、封存區同垃圾桶。
- 同時用多個 Vaultwarden 或 Bitwarden 帳戶，包括共享密碼庫同集合；透過 WebSocket 即時同步。支援密碼、雙重驗證同單一登入（SSO）。
- 一次搜尋所有密碼庫，再用類型、資料夾、收藏、一次性密碼、通行密鑰同 Watchtower 問題篩選。
- 喺項目編輯器加入、下載或者移除附件；由目前瀏覽器分頁新增登入資料時，網站資料會自動填好。

**隨時快速拎到資料**

- 喺任何 App 用指令面板搵項目、複製資料，或者自動輸入用戶名稱同密碼。
- 自訂全域快捷鍵，再由選單列面板睇相關登入資料、一次性密碼同密碼產生器。
- 瀏覽器擴充功能可以喺 App 入面批核之後填寫同儲存登入資料，支援 Safari、Chrome、Edge、Brave、Arc 同 Firefox，仲有 Vivaldi、Opera、Helium、Zen、LibreWolf 等大部分以 Chromium 或 Firefox 為基礎嘅瀏覽器（喺設定入面連接）。喺註冊表格度，佢會建議高強度密碼同你嘅電郵或者私人地址（`you+tag@`），再喺頁面入面問你「要唔要儲存呢個登入資料？」。通行密鑰登入用 macOS 系統自動填寫；瀏覽器擴充功能而家未支援通行密鑰登入。

**macOS 整合同安全工具**

- 系統自動填寫支援密碼、通行密鑰同一次性密碼；可以用 Touch ID 或 PIN 解鎖。
- 複製咗嘅機密資料會自動喺剪貼簿清除；SSH agent 可以用密碼庫嘅 SSH 金鑰簽署 Git commit。
- 可以喺螢幕分享、錄影同截圖嗰陣隱藏 Triwarden；自架伺服器可以用私人 CA 同 Cloudflare Access 等額外請求標頭。
- Watchtower 會搵出弱密碼、重複使用、外洩同唔安全嘅密碼，亦會提示未開雙重驗證嘅網站。重複使用嘅密碼可以跟住引導整理：揀一個要保留嘅登入資料，其餘嘅就更改或者刪除。
- 支援雙重驗證、裝置管理、緊急存取、Send、密碼同用戶名稱產生器，同埋多種匯入／匯出格式；亦可以匯出成受密碼保護嘅 KeePass（.kdbx）資料庫，用 KeePassXC、KeePassium 同 Strongbox 都開到。

完整功能同限制可以睇[英文 README](README.md)同[產品路線圖](docs/ROADMAP.md)。

## 命令列同本機 API 金鑰

喺「設定 › 開發者」開啟 **Answer the tw command**，再用 **Terminal Helper Setup…** 安裝 `tw`。

```bash
tw get github | pbcopy
tw code github
tw status
tw run
tw tools list
tw generate --length 32
tw lock
```

本機 API 金鑰功能預設會收埋。開啟「設定 › 開發者 › Show Secrets」之後，可以跟指引完成「儲存金鑰 → 畀工具或專案使用 → 檢查授權 → 下次再用」嘅流程。詳情睇[入門指南](docs/local-api-keys-getting-started.md)。
每個 API 金鑰項目會顯示邊啲工具用緊佢；「Access › Permissions」同「Access › History」可以檢查有效授權同以往決定。

## 由原始碼建置

需要 macOS 26、Xcode 26、[XcodeGen](https://github.com/yonaskolb/XcodeGen)、Node.js 同 pnpm。

```bash
brew install xcodegen node pnpm
```

```bash
git clone https://github.com/sinhong2011/triwarden.git
cd triwarden
make run
```

執行 `make` 可以睇全部指令；常用指令包括 `make test`、`make selftest`、`make uitest` 同 `make snapshots`。

## 安全、輔助使用同語言

你嘅主密碼同金鑰唔會離開部 Mac；伺服器只會收到加密資料。詳情同漏洞回報方法請睇 [SECURITY.md](SECURITY.md)。

Triwarden 有 VoiceOver 標籤、鍵盤快捷鍵、增加對比同減少動態效果支援。App 支援 English、繁體中文、粵語、简体中文、日本語、한국어、Français、Español 同ไทย；已知限制請睇 [ACCESSIBILITY.md](ACCESSIBILITY.md)。

## 支援同貢獻

購買或者產品問題可以電郵去 [support@triwarden.cc](mailto:support@triwarden.cc)。錯誤同功能建議請開 [GitHub issue](https://github.com/sinhong2011/triwarden/issues)。歡迎提交 issue 同 pull request；發布流程請睇 [docs/RELEASING.md](docs/RELEASING.md)。

## 授權條款

Triwarden 係按 [GNU General Public License v3.0](LICENSE) 發布嘅自由軟件。程式碼授權唔包括「Triwarden」個名同 App 圖示；修改版本一定要用自己嘅名稱同圖示。Triwarden 同 Bitwarden, Inc. 或 Vaultwarden 專案冇從屬或合作關係。
