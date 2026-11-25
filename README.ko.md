<p align="center">
  <img src="docs/images/icon.png" width="128" height="128" alt="Triwarden 앱 아이콘">
</p>

<h1 align="center">Triwarden</h1>

<p align="center">
  <a href="https://github.com/dani-garcia/vaultwarden">Vaultwarden</a>와 Bitwarden을 위한 Mac 네이티브 암호 관리자입니다.<br>
  Swift와 SwiftUI로 제작되었으며 macOS 26을 지원합니다.
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README.zh-Hant.md">繁體中文</a> ·
  <a href="README.zh-HK.md">粵語</a> · <a href="README.zh-Hans.md">简体中文</a> ·
  <a href="README.ja.md">日本語</a> · 한국어 · <a href="README.fr.md">Français</a> ·
  <a href="README.es.md">Español</a>
</p>

<p align="center">
  <a href="https://github.com/sinhong2011/triwarden/releases/latest/download/Triwarden.dmg"><img src="https://img.shields.io/badge/다운로드-macOS용-000000?style=for-the-badge&amp;logo=apple&amp;logoColor=white" alt="최신 Triwarden macOS DMG 다운로드"></a>
</p>

<p align="center">
  <a href="https://github.com/sinhong2011/triwarden/actions/workflows/ci.yml"><img src="https://github.com/sinhong2011/triwarden/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0-blue" alt="라이선스: GPL-3.0"></a>
  <img src="https://img.shields.io/badge/macOS-26%2B-black?logo=apple" alt="macOS 26 이상">
  <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&amp;logoColor=white" alt="Swift 6">
</p>

<p align="center">
  <img src="promo/public/shots/vault-dark.png" width="820" alt="Triwarden 다크 테마 볼트 화면">
</p>

> 이 번역은 2026년 11월 22일에 [영문 README](README.md)와 동기화했습니다. 전체 기능 및 기술 정보는 영문판을 확인하세요.

> **상태:** 현재 초기 릴리스(0.x) 단계입니다. 실제 Vaultwarden 및 Bitwarden 계정에서 작동하며 두 서비스 모두를 대상으로 테스트했지만,
> 1.0 전까지는 기존에 사용하던 클라이언트를 함께 유지하는 것을 권장합니다. 스크린샷은 내장 데모 볼트를 사용합니다.

## 설치

macOS 26(Tahoe) 이상이 필요합니다.

```bash
brew install --cask sinhong2011/tap/triwarden
```

위의 다운로드 버튼으로 서명 및 공증된 최신 DMG를 바로 받을 수 있습니다. ‘설정 › 정보’에서 서명된 업데이트를 확인할 수 있으며 자동 확인과 설치는 사용자가 직접 활성화해야 합니다.

## 시작하기

1. Triwarden을 열고 Vaultwarden 서버, Bitwarden US 또는 Bitwarden EU를 선택한 다음 기존 계정으로 로그인합니다.
2. ‘시스템 설정 › 일반 › 자동 완성 및 암호’에서 Triwarden을 활성화하면 암호, 패스키, 인증 코드를 채울 수 있습니다.
3. Triwarden에서 **⌘F**로 볼트를 검색하거나 어느 앱에서든 **⇧⌘Space**로 명령 팔레트를 엽니다.
   자동 입력에는 **Triwarden Auto-Type**의 손쉬운 사용 권한이 필요합니다. 브라우저 확장 기능은 설정에서 선택적으로 연결할 수 있습니다.

**오프라인:** 이 Mac에 암호화되어 저장된 볼트는 오프라인에서도 잠금을 해제하고 읽을 수 있습니다. 항목 생성, 편집, 가져오기 및 삭제에는 서버 연결이 필요하며 변경 사항은 나중에 전송되도록 대기열에 저장되지 않습니다.

**공식 빌드와 유료 라이선스:** 개인 용도에서는 유료 라이선스 없이도 모든 기능을 기간 제한 없이 사용할 수 있습니다. 등록하지 않은 공식 빌드는 약 30일이 지나면 실행할 때 구매 안내를 표시할 수 있으며, 많아야 일주일에 한 번입니다. 일회성 유료 라이선스를 등록하면 안내가 사라지고, 해당 사용자의 모든 Mac에 적용됩니다. 공식 빌드로 업무용 계정을 관리하려면 사용자 한 명당 유료 라이선스가 필요합니다. [유료 라이선스 약관](docs/LICENSE-TERMS.md)을 확인하세요.

## 기능

**Mac 네이티브 볼트**

- 로그인, 보안 메모, 카드, 신원 정보, SSH 키, 은행 계좌, 운전면허증, 여권을 폴더, 즐겨찾기, 사용자 지정 필드, 첨부 파일, 보관함 및 휴지통과 함께 관리합니다.
- 여러 Vaultwarden 또는 Bitwarden 계정과 공유 볼트 및 컬렉션을 동시에 사용하고 WebSocket으로 실시간 동기화합니다. 암호, 2단계 인증 및 SSO 로그인을 지원합니다.
- 모든 볼트를 한 번에 검색하고 유형, 폴더, 즐겨찾기, 일회용 암호, 패스키 및 Watchtower 문제로 필터링합니다.
- 항목 편집기에서 첨부 파일을 추가, 다운로드 또는 제거할 수 있습니다. 현재 브라우저 탭에서 로그인을 만들면 사이트 정보가 자동으로 입력됩니다.

**빠른 접근**

- 어느 앱에서든 명령 팔레트로 항목을 찾고 복사하거나 사용자 이름과 암호를 자동 입력합니다.
- 전역 단축키를 지정하고 메뉴 막대에서 관련 로그인, 일회용 암호 및 생성기에 접근합니다.
- 브라우저 확장 기능은 앱에서 승인한 뒤 로그인을 채우고 저장합니다. Safari, Chrome, Edge, Brave, Arc, Firefox는 물론 Vivaldi, Opera, Helium, Zen, LibreWolf 등 대부분의 Chromium·Firefox 기반 브라우저를 지원합니다(설정에서 연결). 가입 양식에서는 강력한 암호와 이메일 또는 비공개 주소(`you+tag@`)를 제안하고, 페이지 안에서 ‘이 로그인을 저장할까요?’라고 묻습니다. 패스키 로그인은 macOS 시스템 자동 완성을 사용하며 브라우저 확장 기능에서는 아직 처리하지 않습니다.

**macOS 통합 및 보안 도구**

- 시스템 자동 완성은 암호, 패스키 및 일회용 암호를 지원하며 Touch ID 또는 PIN으로 잠금을 해제할 수 있습니다.
- 복사한 비밀 정보는 클립보드에서 자동으로 지워집니다. SSH agent는 볼트의 SSH 키로 Git 커밋에도 서명할 수 있습니다.
- 화면 공유, 녹화 및 스크린샷에서 Triwarden을 숨길 수 있습니다. 자체 호스팅 서버에서는 사설 CA와 Cloudflare Access 같은 추가 요청 헤더를 사용할 수 있습니다.
- Watchtower는 취약하거나 재사용되었거나 유출되었거나 안전하지 않은 암호와 2단계 인증을 설정하지 않은 사이트를 찾아냅니다. 재사용된 암호는 안내에 따라 정리할 수 있습니다. 남길 로그인을 하나 고르고 나머지는 변경하거나 삭제하세요.
- 2단계 인증, 기기 관리, 긴급 접근, Send, 암호·사용자 이름 생성기 및 다양한 가져오기·내보내기 형식을 지원합니다. KeePassXC, KeePassium, Strongbox에서 열 수 있는 암호로 보호된 KeePass(.kdbx) 데이터베이스로도 내보낼 수 있습니다.

전체 기능과 제한 사항은 [영문 README](README.md)와 [로드맵](docs/ROADMAP.md)을 확인하세요.

## 명령줄과 로컬 API 키

‘설정 › 개발자’에서 **Answer the tw command**를 활성화하고 **Terminal Helper Setup…**에서 `tw`를 설치합니다.

```bash
tw get github | pbcopy
tw code github
tw status
tw run
tw tools list
tw generate --length 32
tw lock
```

로컬 API 키 기능은 기본적으로 숨겨져 있습니다. ‘설정 › 개발자 › Show Secrets’를 활성화하면 ‘키 저장 → 도구나 프로젝트에 제공 → 승인 검토 → 다시 사용’ 과정을 안내에 따라 완료할 수 있습니다. [시작 안내서](docs/local-api-keys-getting-started.md)를 참고하세요.
각 API 키 항목에는 그 키를 사용하는 도구가 표시됩니다. ‘Access › Permissions’와 ‘Access › History’에서 활성 권한과 이전 결정을 확인할 수 있습니다.

## 소스에서 빌드

macOS 26, Xcode 26, [XcodeGen](https://github.com/yonaskolb/XcodeGen), Node.js 및 pnpm이 필요합니다.

```bash
brew install xcodegen node pnpm
```

```bash
git clone https://github.com/sinhong2011/triwarden.git
cd triwarden
make run
```

`make`를 실행하면 모든 명령을 볼 수 있습니다. 자주 쓰는 명령은 `make test`, `make selftest`, `make uitest`, `make snapshots`입니다.

## 보안, 손쉬운 사용 및 언어

마스터 암호와 키는 Mac을 떠나지 않으며 서버에는 암호화된 데이터만 전송됩니다. 자세한 내용과 비공개 취약점 신고 방법은 [SECURITY.md](SECURITY.md)를 확인하세요.

Triwarden은 VoiceOver 레이블, 키보드 단축키, 대비 증가 및 동작 줄이기를 지원합니다. English, 繁體中文, 粵語, 简体中文, 日本語, 한국어, Français, Español, ไทย를 사용할 수 있습니다. 알려진 제한 사항은 [ACCESSIBILITY.md](ACCESSIBILITY.md)에 설명되어 있습니다.

## 지원 및 기여

구매 또는 제품 관련 문의는 [support@triwarden.cc](mailto:support@triwarden.cc)으로 보내 주세요. 버그 및 기능 제안은 [GitHub issue](https://github.com/sinhong2011/triwarden/issues)에 등록해 주세요. Issue와 Pull Request를 환영합니다. 릴리스 절차는 [docs/RELEASING.md](docs/RELEASING.md)를 참고하세요.

## 라이선스

Triwarden은 [GNU General Public License v3.0](LICENSE)에 따라 배포되는 자유 소프트웨어입니다. 코드 라이선스에는 ‘Triwarden’ 이름과 앱 아이콘이 포함되지 않으며 수정 버전은 자체 이름과 아이콘을 사용해야 합니다. Triwarden은 Bitwarden, Inc. 또는 Vaultwarden 프로젝트와 제휴하지 않습니다.
