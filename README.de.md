<p align="center">
  <img src="docs/images/icon.png" width="128" height="128" alt="Triwarden-App-Symbol">
</p>

<h1 align="center">Triwarden</h1>

<p align="center">
  Ein nativer Passwortmanager für Mac, kompatibel mit <a href="https://github.com/dani-garcia/vaultwarden">Vaultwarden</a> und Bitwarden.<br>
  Entwickelt mit Swift und SwiftUI für macOS 26.
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README.zh-Hant.md">繁體中文</a> ·
  <a href="README.zh-HK.md">粵語</a> · <a href="README.zh-Hans.md">简体中文</a> ·
  <a href="README.ja.md">日本語</a> · <a href="README.ko.md">한국어</a> ·
  <a href="README.fr.md">Français</a> · <a href="README.es.md">Español</a> · Deutsch
</p>

<p align="center">
  <a href="https://github.com/sinhong2011/triwarden/releases/latest/download/Triwarden.dmg"><img src="https://img.shields.io/badge/Download-f%C3%BCr%20macOS-000000?style=for-the-badge&amp;logo=apple&amp;logoColor=white" alt="Aktuellste Triwarden-DMG für macOS herunterladen"></a>
</p>

<p align="center">
  <a href="https://github.com/sinhong2011/triwarden/actions/workflows/ci.yml"><img src="https://github.com/sinhong2011/triwarden/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPL--3.0-blue" alt="Lizenz: GPL-3.0"></a>
  <img src="https://img.shields.io/badge/macOS-26%2B-black?logo=apple" alt="macOS 26 oder neuer">
  <img src="https://img.shields.io/badge/Swift-6-F05138?logo=swift&amp;logoColor=white" alt="Swift 6">
</p>

<p align="center">
  <img src="promo/public/shots/vault-dark.png" width="820" alt="Der Triwarden-Tresor im Dunkelmodus">
</p>

> Diese Übersetzung wurde am 28. November 2026 mit dem [englischen README](README.md) abgeglichen. Dort findest du die vollständige Funktionsübersicht und weitere technische Details.

> **Status:** Triwarden befindet sich noch in einer frühen Entwicklungsphase (0.x). Die App funktioniert mit echten Vaultwarden- und Bitwarden-Konten und wird mit beiden Diensten getestet. Bis Version 1.0 solltest du deinen bisherigen Client weiterhin zur Verfügung haben. Die Screenshots zeigen den integrierten Demo-Tresor.

## Installation

Erfordert macOS 26 (Tahoe) oder neuer.

```bash
brew install --cask sinhong2011/tap/triwarden
```

Über die Schaltfläche oben kannst du die neueste signierte und von Apple notarisierte DMG direkt herunterladen. Unter **Einstellungen › Über** kannst du nach signierten Updates suchen. Die automatische Suche und Installation sind optional.

## Erste Schritte

1. Öffne Triwarden, wähle deinen Vaultwarden-Server, Bitwarden US oder Bitwarden EU und melde dich mit deinem bestehenden Konto an.
2. Aktiviere Triwarden unter **Systemeinstellungen › Allgemein › Automatisch ausfüllen & Passwörter**, um Passwörter, Passkeys und Bestätigungscodes auszufüllen.
3. Suche mit **⌘F** im Tresor oder öffne mit **⇧⌘Leertaste** die Befehlspalette aus einer beliebigen App.
   Für die automatische Eingabe benötigt **Triwarden Auto-Type** Zugriff auf die Bedienungshilfen. Die Browser-Erweiterung ist optional und lässt sich über die Einstellungen verbinden.

**Offline:** Du kannst den auf diesem Mac verschlüsselt gespeicherten Tresor entsperren und einsehen. Zum Erstellen, Bearbeiten, Importieren und Löschen von Einträgen ist eine Verbindung zum Server erforderlich. Änderungen werden nicht für eine spätere Übertragung vorgemerkt.

**Offizielle Builds und kostenpflichtige Lizenz:** Für private Nutzung stehen alle Funktionen ohne kostenpflichtige Lizenz und ohne zeitliche Einschränkung zur Verfügung. Nach etwa 30 Tagen kann ein nicht registrierter offizieller Build beim Start eine Kauferinnerung anzeigen, höchstens einmal pro Woche. Eine einmalig erworbene Lizenz entfernt die Erinnerung und gilt für eine Person auf all ihren Macs. Die Nutzung eines offiziellen Builds mit geschäftlichen Konten erfordert eine kostenpflichtige Lizenz pro Person. Weitere Informationen findest du in den [Lizenzbedingungen](docs/LICENSE-TERMS.md). Für aus dem Quellcode erstellte Builds gelten die unten beschriebenen Rechte der GPL.

## Funktionen

**Dein Tresor, nativ auf dem Mac**

- Verwalte Logins, sichere Notizen, Karten, Identitäten, SSH-Schlüssel, Bankkonten, Führerscheine und Reisepässe mit Ordnern, Favoriten, benutzerdefinierten Feldern, Anhängen, Archiv und Papierkorb.
- Nutze mehrere Vaultwarden- oder Bitwarden-Konten gleichzeitig, einschließlich gemeinsamer Tresore und Sammlungen, mit direkter Synchronisierung über WebSocket. Die Anmeldung per Passwort, Zwei-Schritt-Anmeldung und Single Sign-On (SSO) werden unterstützt.
- Durchsuche alle Tresore und filtere nach Typ, Ordner, Favoriten, Einmalcodes, Passkeys oder Watchtower-Problemen.
- Füge im Eintragseditor Anhänge hinzu, lade sie herunter oder entferne sie. Beim Erstellen eines Logins aus dem aktiven Browser-Tab werden Name und Website automatisch übernommen.

**Schneller Zugriff**

- Nutze die Befehlspalette aus jeder App, um Einträge zu finden, deren Daten zu kopieren oder Benutzernamen und Passwörter automatisch einzugeben.
- Konfiguriere globale Kurzbefehle und greife über die Menüleiste auf passende Logins, Einmalcodes und den Generator zu.
- Die Browser-Erweiterung füllt Logins aus und speichert sie nach deiner Zustimmung in der App. Sie unterstützt Safari, Chrome, Edge, Brave, Arc und Firefox sowie Vivaldi, Opera, Helium, Zen, LibreWolf und die meisten anderen Chromium- oder Firefox-basierten Browser (über die Einstellungen verbinden). Bei Registrierungsformularen schlägt sie ein starkes Passwort und deine E-Mail-Adresse oder eine private Adresse wie `du+tag@` vor. Anschließend fragt sie direkt auf der Seite, ob du den Login speichern möchtest. Die Anmeldung mit Passkeys erfolgt über die systemweite AutoFill-Funktion von macOS. Die Browser-Erweiterung unterstützt diese Anmeldung noch nicht.

**macOS-Integration und Sicherheitsfunktionen**

- Die systemweite AutoFill-Funktion unterstützt Passwörter, Passkeys und Einmalcodes. Entsperre deinen Tresor mit Touch ID oder PIN.
- Kopierte vertrauliche Daten werden automatisch aus der Zwischenablage gelöscht. Der SSH-Agent kann Git-Commits mit den SSH-Schlüsseln aus deinem Tresor signieren.
- Triwarden lässt sich bei Screenshots, Bildschirmaufzeichnungen und Bildschirmfreigaben ausblenden. Selbst gehostete Server können private Zertifizierungsstellen und zusätzliche HTTP-Header wie Cloudflare Access verwenden.
- Watchtower erkennt schwache, wiederverwendete und kompromittierte Passwörter, Logins über unverschlüsseltes HTTP sowie Websites, auf denen die Zwei-Schritt-Anmeldung noch nicht eingerichtet ist. Beim Bereinigen wiederverwendeter Passwörter wirst du durch den Vorgang geführt. Wähle den Login aus, den du behalten möchtest, und ändere oder entferne die übrigen.
- Zwei-Schritt-Anmeldung, Geräteverwaltung, Notfallzugriff, Send, Generatoren für Passwörter und Benutzernamen sowie zahlreiche Import- und Exportformate, darunter eine passwortgeschützte KeePass-Datenbank (.kdbx), die sich in KeePassXC, KeePassium und Strongbox öffnen lässt.

Im [englischen README](README.md) und in der [Roadmap](docs/ROADMAP.md) findest du die vollständige Funktionsübersicht und die bekannten Einschränkungen.

## Befehlszeile und lokale API-Schlüssel

Aktiviere **Den tw-Befehl beantworten** unter **Einstellungen › Entwickler** und installiere `tw` über **Terminal-Helfer einrichten…**.

```bash
tw get github | pbcopy
tw code github
tw status
tw run
tw tools list
tw generate --length 32
tw lock
```

Die Funktionen für lokale API-Schlüssel sind standardmäßig ausgeblendet. Aktiviere **Einstellungen › Entwickler › Zugangsdaten anzeigen**, um der Einrichtungsanleitung zu folgen: Schlüssel speichern → für ein Tool oder Projekt bereitstellen → Zugriff prüfen → erneut verwenden. Weitere Informationen findest du in der [Anleitung für den Einstieg](docs/local-api-keys-getting-started.md).
Bei jedem API-Schlüssel siehst du, welche Tools ihn verwenden. Unter **Zugriff › Berechtigungen** und **Zugriff › Verlauf** findest du aktive Freigaben und frühere Entscheidungen.

## Aus dem Quellcode erstellen

Erfordert macOS 26, Xcode 26, [XcodeGen](https://github.com/yonaskolb/XcodeGen), Node.js und pnpm.

```bash
brew install xcodegen node pnpm
```

```bash
git clone https://github.com/sinhong2011/triwarden.git
cd triwarden
make run
```

Mit `make` erhältst du eine Übersicht aller Befehle. Häufig verwendet werden `make test`, `make selftest`, `make uitest` und `make snapshots`.

## Sicherheit, Bedienungshilfen und Sprachen

Dein Master-Passwort und die entschlüsselten Tresorschlüssel verlassen den Mac nie. Der Server erhält ausschließlich verschlüsselte Tresordaten. Details, das Bedrohungsmodell und Informationen zur vertraulichen Meldung von Schwachstellen findest du in [SECURITY.md](SECURITY.md).

Triwarden bietet VoiceOver-Beschriftungen und Tastaturkurzbefehle und unterstützt die macOS-Einstellungen „Kontrast erhöhen“ und „Bewegung reduzieren“. Die App ist auf Englisch, Deutsch, 繁體中文, 粵語, 简体中文, 日本語, 한국어, Français, Español und ไทย verfügbar. Bekannte Einschränkungen sind in [ACCESSIBILITY.md](ACCESSIBILITY.md) dokumentiert.

## Support und Mitarbeit

Bei Fragen zum Kauf oder zum Produkt wende dich an [support@triwarden.cc](mailto:support@triwarden.cc). Fehler und Funktionswünsche kannst du als [GitHub-Issue](https://github.com/sinhong2011/triwarden/issues) melden. Issues und Pull Requests sind willkommen. Informationen zum Veröffentlichungsprozess findest du in [docs/RELEASING.md](docs/RELEASING.md).

## Lizenz

Triwarden ist freie Software unter der [GNU General Public License v3.0](LICENSE). Die Lizenz des Quellcodes umfasst weder den Namen „Triwarden“ noch das App-Symbol. Ohne Erlaubnis müssen veränderte Versionen einen eigenen Namen und ein eigenes Symbol verwenden. Triwarden steht in keiner Verbindung zu Bitwarden, Inc. oder dem Vaultwarden-Projekt.
