<p align="center">
  <img src="docs/images/icon.png" width="128" height="128" alt="Triwarden App 图标">
</p>

<h1 align="center">Triwarden</h1>

<p align="center">
  专为 <a href="https://github.com/dani-garcia/vaultwarden">Vaultwarden</a> 和 Bitwarden 打造的原生 Mac 密码管理器。<br>
  使用 Swift 和 SwiftUI 开发，支持 macOS 26。
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README.zh-Hant.md">繁體中文</a> ·
  <a href="README.zh-HK.md">粵語</a> · 简体中文 · <a href="README.ja.md">日本語</a> ·
  <a href="README.ko.md">한국어</a> · <a href="README.fr.md">Français</a> ·
  <a href="README.es.md">Español</a>
</p>

<p align="center">
  <a href="https://github.com/sinhong2011/triwarden/releases/latest/download/Triwarden.dmg"><img src="https://img.shields.io/badge/下载-适用于%20macOS-000000?style=for-the-badge&amp;logo=apple&amp;logoColor=white" alt="下载最新版 Triwarden macOS DMG"></a>
</p>

<p align="center">
  <a href="https://github.com/sinhong2011/triwarden/actions/workflows/ci.yml"><img src="https://github.com/sinhong2011/triwarden/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0-blue" alt="许可证：GPL-3.0"></a>
  <img src="https://img.shields.io/badge/macOS-26%2B-black?logo=apple" alt="macOS 26 或更高版本">
  <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&amp;logoColor=white" alt="Swift 6">
</p>

<p align="center">
  <img src="promo/public/shots/vault-dark.png" width="820" alt="Triwarden 深色主题密码库界面">
</p>

> 本翻译已于 2026 年 11 月 22 日与[英文 README](README.md)同步；完整功能和技术细节以英文版为准。

> **状态：**目前仍处于早期版本（0.x）。Triwarden 已经可以连接真实的 Vaultwarden 和 Bitwarden 账户，
> 并完成了两者的兼容性测试；在 1.0 发布前，仍建议保留你原来使用的客户端。截图使用内置演示密码库。

## 安装

需要 macOS 26（Tahoe）或更高版本。

```bash
brew install --cask sinhong2011/tap/triwarden
```

你也可以点击上方的下载按钮，获取已经签名和公证的最新版 DMG。你可以在“设置 › 关于”检查已签名的更新；自动检查和安装需要自行启用。

## 开始使用

1. 打开 Triwarden，选择你的 Vaultwarden 服务器、Bitwarden US 或 Bitwarden EU，然后登录现有账户。
2. 前往“系统设置 › 通用 › 自动填充与密码”启用 Triwarden，即可填充密码、通行密钥和验证码。
3. 在 Triwarden 中按 **⌘F** 搜索密码库；在任何 App 中按 **⇧⌘Space** 打开命令面板。
   自动输入需要授予 **Triwarden Auto-Type** 辅助功能权限；浏览器扩展则可在设置中选择和连接。

**离线使用：**你可以解锁并查看加密存储在这台 Mac 上的密码库。新增、编辑、导入和删除项目时必须连接服务器；更改不会排队等待稍后上传。

**官方版本与付费许可：**个人使用无需付费许可，即可永久使用所有功能。约 30 天后，未注册的官方版本可能会在启动时显示购买提醒，最多每周一次；一次性付费许可可移除提醒，并涵盖该用户的所有 Mac。使用官方版本管理工作账户时，每位用户需要一份付费许可。详情请参阅[付费许可条款](docs/LICENSE-TERMS.md)。

## 功能

**原生密码库体验**

- 管理登录信息、安全笔记、银行卡、身份信息和 SSH 密钥，并支持文件夹、收藏、自定义字段、附件、归档和回收站。
- 同时使用多个 Vaultwarden 或 Bitwarden 账户，包括共享密码库和集合；通过 WebSocket 实时同步。支持密码、双重验证和单点登录（SSO）。
- 搜索所有密码库，并按类型、文件夹、收藏、一次性密码、通行密钥及 Watchtower 问题筛选结果。
- 在项目编辑器中添加、下载或移除附件；从当前浏览器标签页新建登录信息时，自动预填网站信息。

**快速访问**

- 在任何 App 中使用命令面板查找项目、复制信息或自动输入用户名和密码。
- 自定义全局快捷键，从菜单栏面板查看相关登录信息、一次性密码和密码生成器。
- 浏览器扩展可在 App 内批准后填充和保存登录信息，支持 Safari、Chrome、Edge、Brave、Arc 和 Firefox，以及 Vivaldi、Opera、Helium、Zen、LibreWolf 等大多数基于 Chromium 或 Firefox 的浏览器（在设置中连接）。在注册表单上，它会建议强密码和你的邮箱或私密地址（`you+tag@`），并在页面内询问“保存此登录信息？”。通行密钥登录使用 macOS 系统自动填充；浏览器扩展目前尚未处理通行密钥登录。

**macOS 集成与安全工具**

- 系统自动填充支持密码、通行密钥和一次性密码；可使用 Touch ID 或 PIN 解锁。
- 已复制的机密信息会自动从剪贴板清除；SSH agent 可使用密码库中的 SSH 密钥签署 Git 提交。
- 可在屏幕共享、录制和截图时隐藏 Triwarden；自托管服务器可使用私有 CA 和 Cloudflare Access 等额外请求标头。
- Watchtower 会找出弱密码、重复使用、泄露和不安全的密码，并提示尚未启用双重验证的网站。重复使用的密码可按引导清理：选出要保留的登录信息，再更改或删除其余项目。
- 支持双重验证、设备管理、紧急访问、Send、密码与用户名生成器，以及多种导入／导出格式；还可导出为受密码保护的 KeePass（.kdbx）数据库，在 KeePassXC、KeePassium 和 Strongbox 中打开。

完整功能与限制请参阅[英文 README](README.md)和[产品路线图](docs/ROADMAP.md)。

## 命令行与本地 API 密钥

在“设置 › 开发者”启用 **Answer the tw command**，再使用 **Terminal Helper Setup…** 安装 `tw`。

```bash
tw get github | pbcopy
tw code github
tw status
tw run
tw tools list
tw generate --length 32
tw lock
```

本地 API 密钥功能默认隐藏。启用“设置 › 开发者 › Show Secrets”后，可以按照引导完成“保存密钥 → 提供给工具或项目 → 检查授权 → 再次使用”的流程。请参阅[入门指南](docs/local-api-keys-getting-started.md)。
每个 API 密钥项目会显示使用它的工具；“Access › Permissions”和“Access › History”可用于检查有效授权和以往决定。

## 从源代码构建

需要 macOS 26、Xcode 26、[XcodeGen](https://github.com/yonaskolb/XcodeGen)、Node.js 和 pnpm。

```bash
brew install xcodegen node pnpm
```

```bash
git clone https://github.com/sinhong2011/triwarden.git
cd triwarden
make run
```

运行 `make` 可查看所有命令；常用命令包括 `make test`、`make selftest`、`make uitest` 和 `make snapshots`。

## 安全性、辅助功能与语言

你的主密码和密钥不会离开这台 Mac；服务器只会收到加密数据。详情与漏洞报告方式请参阅 [SECURITY.md](SECURITY.md)。

Triwarden 提供 VoiceOver 标签、键盘快捷键、增强对比度和减弱动态效果支持。App 支持 English、繁體中文、粵語、简体中文、日本語、한국어、Français、Español 和ไทย；已知限制请参阅 [ACCESSIBILITY.md](ACCESSIBILITY.md)。

## 支持与贡献

购买或产品问题请发送邮件至 [support@triwarden.cc](mailto:support@triwarden.cc)。错误报告和功能建议请创建 [GitHub issue](https://github.com/sinhong2011/triwarden/issues)。欢迎提交 issue 和 pull request；发布流程请参阅 [docs/RELEASING.md](docs/RELEASING.md)。

## 许可证

Triwarden 是依照 [GNU General Public License v3.0](LICENSE) 发布的自由软件。代码许可证不包含“Triwarden”名称和 App 图标；修改版本必须使用自己的名称和图标。Triwarden 与 Bitwarden, Inc. 或 Vaultwarden 项目没有隶属或合作关系。
