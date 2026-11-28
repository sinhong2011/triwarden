<p align="center">
  <img src="docs/images/icon.png" width="128" height="128" alt="Ikona aplikacji Triwarden">
</p>

<h1 align="center">Triwarden</h1>

<p align="center">
  Natywny menedżer haseł dla Maca, zgodny z <a href="https://github.com/dani-garcia/vaultwarden">Vaultwarden</a> i Bitwarden.<br>
  Napisany w Swift i SwiftUI dla macOS 26.
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README.zh-Hant.md">繁體中文</a> ·
  <a href="README.zh-HK.md">粵語</a> · <a href="README.zh-Hans.md">简体中文</a> ·
  <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> ·
  <a href="README.fr.md">Français</a> · <a href="README.es.md">Español</a> ·
  <a href="README.de.md">Deutsch</a> · Polski
</p>

<p align="center">
  <a href="https://github.com/sinhong2011/triwarden/releases/latest/download/Triwarden.dmg"><img src="https://img.shields.io/badge/Pobierz-dla%20macOS-000000?style=for-the-badge&amp;logo=apple&amp;logoColor=white" alt="Pobierz najnowszy plik DMG Triwarden dla macOS"></a>
</p>

<p align="center">
  <a href="https://github.com/sinhong2011/triwarden/actions/workflows/ci.yml"><img src="https://github.com/sinhong2011/triwarden/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0-blue" alt="Licencja: GPL-3.0"></a>
  <img src="https://img.shields.io/badge/macOS-26%2B-black?logo=apple" alt="macOS 26 lub nowszy">
  <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&amp;logoColor=white" alt="Swift 6">
</p>

<p align="center">
  <img src="promo/public/shots/vault-dark.png" width="820" alt="Sejf Triwarden w trybie ciemnym">
</p>

> To tłumaczenie zostało zsynchronizowane z [angielskim README](README.md) 28 listopada 2026 r. Tam znajdziesz pełną listę funkcji i więcej szczegółów technicznych.

> **Status:** Triwarden jest wciąż na wczesnym etapie rozwoju (0.x). Aplikacja działa z prawdziwymi kontami Vaultwarden i Bitwarden i jest testowana z oboma serwisami. Do wersji 1.0 warto mieć pod ręką dotychczasowego klienta. Zrzuty ekranu pokazują wbudowany sejf demonstracyjny.

## Instalacja

Wymaga macOS 26 (Tahoe) lub nowszego.

```bash
brew install --cask sinhong2011/tap/triwarden
```

Przyciskiem powyżej pobierzesz najnowszy podpisany i poświadczony notarialnie przez Apple plik DMG. W **Ustawienia › Informacje** możesz sprawdzić, czy są podpisane aktualizacje. Automatyczne sprawdzanie i instalowanie są opcjonalne.

## Pierwsze kroki

1. Otwórz Triwarden, wybierz swój serwer Vaultwarden, Bitwarden US lub Bitwarden EU i zaloguj się na istniejące konto.
2. Włącz Triwarden w **Ustawienia systemowe › Ogólne › Autouzupełnianie i hasła**, aby wypełniać hasła, klucze dostępu i kody weryfikacyjne.
3. Szukaj w sejfie skrótem **⌘F** albo otwórz paletę poleceń z dowolnej aplikacji skrótem **⇧⌘Spacja**.
   Automatyczne wpisywanie (**Triwarden Auto-Type**) wymaga dostępu do funkcji Dostępności. Rozszerzenie przeglądarki jest opcjonalne i łączy się je w Ustawieniach.

**Offline:** możesz odblokować i przeglądać sejf zapisany w postaci zaszyfrowanej na tym Macu. Tworzenie, edycja, import i usuwanie elementów wymagają połączenia z serwerem. Zmiany nie są kolejkowane do późniejszego wysłania.

**Oficjalne wersje i płatna licencja:** do użytku prywatnego wszystkie funkcje są dostępne bez płatnej licencji i bez limitu czasu. Po około 30 dniach niezarejestrowana oficjalna wersja może przy uruchomieniu przypomnieć o zakupie, najwyżej raz w tygodniu. Jednorazowo kupiona licencja usuwa przypomnienie i obejmuje jedną osobę na wszystkich jej Macach. Używanie oficjalnej wersji z kontami firmowymi wymaga płatnej licencji dla każdej osoby. Więcej informacji znajdziesz w [warunkach licencji](docs/LICENSE-TERMS.md). Wersje zbudowane z kodu źródłowego objęte są prawami GPL opisanymi poniżej.

## Funkcje

**Twój sejf, natywnie na Macu**

- Zarządzaj danymi logowania, bezpiecznymi notatkami, kartami, tożsamościami, kluczami SSH, kontami bankowymi, prawami jazdy i paszportami, z folderami, ulubionymi, polami własnymi, załącznikami, archiwum i koszem.
- Korzystaj z wielu kont Vaultwarden lub Bitwarden jednocześnie, łącznie z sejfami współdzielonymi i kolekcjami, z bieżącą synchronizacją przez WebSocket. Obsługiwane jest logowanie hasłem, logowanie dwuetapowe i jednokrotne logowanie (SSO).
- Przeszukuj wszystkie sejfy i filtruj według typu, folderu, ulubionych, kodów jednorazowych, kluczy dostępu lub problemów wykrytych przez Watchtower.
- Dodawaj, pobieraj i usuwaj załączniki w edytorze elementu. Nowy login utworzony z aktywnej karty przeglądarki od razu dostaje jej nazwę i adres.

**Szybki dostęp**

- Paleta poleceń działa z każdej aplikacji: znajdziesz w niej elementy, skopiujesz ich dane albo automatycznie wpiszesz nazwę użytkownika i hasło.
- Ustaw globalne skróty klawiszowe i sięgaj z paska menu po pasujące loginy, kody jednorazowe i generator.
- Rozszerzenie przeglądarki wypełnia loginy i po twojej zgodzie zapisuje je w aplikacji. Obsługuje Safari, Chrome, Edge, Brave, Arc i Firefox, a także Vivaldi, Opera, Helium, Zen, LibreWolf i większość innych przeglądarek opartych na Chromium lub Firefoksie (połączysz je w Ustawieniach). Przy formularzach rejestracji proponuje silne hasło oraz twój adres e-mail lub adres prywatny, np. `ty+tag@`. Potem pyta bezpośrednio na stronie, czy zapisać login. Logowanie kluczami dostępu odbywa się przez systemowe Autouzupełnianie macOS. Rozszerzenie przeglądarki jeszcze go nie obsługuje.

**Integracja z macOS i bezpieczeństwo**

- Systemowe Autouzupełnianie obsługuje hasła, klucze dostępu i kody jednorazowe. Sejf odblokujesz przez Touch ID lub kod PIN.
- Skopiowane poufne dane są automatycznie usuwane ze schowka. Agent SSH może podpisywać commity Git kluczami SSH z twojego sejfu.
- Triwarden można ukryć na zrzutach ekranu, nagraniach i podczas udostępniania ekranu. Serwery hostowane samodzielnie mogą używać prywatnych urzędów certyfikacji i dodatkowych nagłówków HTTP, np. Cloudflare Access.
- Watchtower wykrywa słabe, powtórzone i ujawnione hasła, loginy przez nieszyfrowane HTTP oraz strony, na których nie masz jeszcze logowania dwuetapowego. Porządkowanie powtórzonych haseł prowadzi cię krok po kroku: wybierasz login, który zostaje, a pozostałe zmieniasz lub usuwasz.
- Logowanie dwuetapowe, zarządzanie urządzeniami, dostęp awaryjny, Send, generatory haseł i nazw użytkowników oraz wiele formatów importu i eksportu, w tym chroniona hasłem baza KeePass (.kdbx), którą otworzysz w KeePassXC, KeePassium i Strongbox.

Pełną listę funkcji i znane ograniczenia znajdziesz w [angielskim README](README.md) i w [planie rozwoju](docs/ROADMAP.md).

## Wiersz poleceń i lokalne klucze API

Włącz **Odpowiadaj na polecenie tw** w **Ustawienia › Deweloper** i zainstaluj `tw` przez **Konfiguracja pomocnika terminala…**.

```bash
tw get github | pbcopy
tw code github
tw status
tw run
tw tools list
tw generate --length 32
tw lock
```

Funkcje lokalnych kluczy API są domyślnie ukryte. Włącz **Ustawienia › Deweloper › Pokaż sekrety** i przejdź przewodnik konfiguracji: zapisz klucz → udostępnij go narzędziu lub projektowi → sprawdź dostęp → używaj ponownie. Więcej informacji znajdziesz w [przewodniku na start](docs/local-api-keys-getting-started.md).
Przy każdym kluczu API widać, które narzędzia go używają. W **Dostęp › Uprawnienia** i **Dostęp › Historia** znajdziesz aktywne zgody i wcześniejsze decyzje.

## Budowanie z kodu źródłowego

Wymaga macOS 26, Xcode 26, [XcodeGen](https://github.com/yonaskolb/XcodeGen), Node.js i pnpm.

```bash
brew install xcodegen node pnpm
```

```bash
git clone https://github.com/sinhong2011/triwarden.git
cd triwarden
make run
```

`make` wyświetla listę wszystkich poleceń. Najczęściej używane to `make test`, `make selftest`, `make uitest` i `make snapshots`.

## Bezpieczeństwo, dostępność i języki

Hasło główne i odszyfrowane klucze sejfu nigdy nie opuszczają Maca. Serwer otrzymuje wyłącznie zaszyfrowane dane sejfu. Szczegóły, model zagrożeń i zasady poufnego zgłaszania podatności znajdziesz w [SECURITY.md](SECURITY.md).

Triwarden ma etykiety VoiceOver i skróty klawiszowe oraz obsługuje ustawienia macOS „Zwiększ kontrast” i „Ogranicz ruch”. Aplikacja jest dostępna w językach: English, Deutsch, 繁體中文, 粵語, 简体中文, 日本語, 한국어, Français, Español, Polski i ไทย. Znane ograniczenia opisuje [ACCESSIBILITY.md](ACCESSIBILITY.md).

## Wsparcie i współpraca

W sprawach zakupu lub produktu napisz na [support@triwarden.cc](mailto:support@triwarden.cc). Błędy i propozycje funkcji zgłaszaj jako [zgłoszenie na GitHubie](https://github.com/sinhong2011/triwarden/issues). Zgłoszenia i pull requesty są mile widziane. Proces wydawania opisuje [docs/RELEASING.md](docs/RELEASING.md).

## Licencja

Triwarden to wolne oprogramowanie na licencji [GNU General Public License v3.0](LICENSE). Licencja kodu źródłowego nie obejmuje nazwy „Triwarden” ani ikony aplikacji. Bez zgody zmodyfikowane wersje muszą mieć własną nazwę i ikonę. Triwarden nie jest powiązany z Bitwarden, Inc. ani z projektem Vaultwarden.
