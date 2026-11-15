# Kundida Toolbox

Eine App für alle Kundida-Apps: installieren, aktualisieren und starten – direkt aus der Menüleiste.

[![CI](https://github.com/holgerdaehn/Kundida_Toolbox/actions/workflows/ci.yml/badge.svg)](https://github.com/holgerdaehn/Kundida_Toolbox/actions/workflows/ci.yml)
![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![Lizenz MIT](https://img.shields.io/badge/Lizenz-MIT-green)

**Download:** [download.kundida.de](https://download.kundida.de/#toolbox) – signiert mit Apple Developer ID und von Apple notarisiert.

## Funktionen

- **Alle Apps auf einen Blick:** installiert, verfügbar und mit Update – jeweils mit einer kurzen Beschreibung, was die App macht.
- **Installieren und aktualisieren mit einem Klick:** Download mit Fortschritt, Prüfung, Installation. Laufende Apps werden auf Wunsch beendet.
- **Neuerungen** zu jeder Version direkt in der Detailansicht.
- **Drei Quellen:**
  - Mac-Apps von [download.kundida.de](https://download.kundida.de) (Forseti, Triglav, IT Command Center, Bifröst, Vardscan)
  - Apps aus dem App Store (Perun, Chronorius, Bifröst) – Installation und Updates über den App Store
  - Kostenlose Tools von GitHub ([Save the Date](https://github.com/holgerdaehn/save_the_date), [Schredder](https://github.com/holgerdaehn/schredder))
- **Öffnen, im Finder zeigen, deinstallieren** (in den Papierkorb).
- **Aktualisiert sich selbst** über Sparkle.
- **Ohne Konto, ohne Tracking.**

## Installation

1. ZIP von [download.kundida.de](https://download.kundida.de/#toolbox) laden und entpacken.
2. `KundidaToolbox.app` in „Programme“ ziehen und starten.
3. Das Symbol erscheint in der Menüleiste.

Voraussetzung: macOS 14 Sonoma oder neuer, Apple Silicon oder Intel.

## Sicherheit

- Jeder Download wird per **SHA-256** gegen den Katalog bzw. die Angabe von GitHub geprüft.
- Kundida-Apps müssen mit der **Developer ID** `LX259B8S89` signiert sein, sonst wird nichts installiert.
- Eine vorhandene App wird erst ersetzt, wenn die neue vollständig vorliegt.
- Installiert wird nur nach einem Klick – automatisch wird ausschließlich nach Updates gesucht.

Details und Meldung von Sicherheitslücken: [SECURITY.md](SECURITY.md)

## Entwicklung

```bash
swift build                                              # Debug-Build
Scripts/make_app.sh                                      # build/KundidaToolbox.app inkl. Sparkle
~/Developer/signing/release.sh KundidaToolbox <Version>  # Release: signieren, notarisieren, veröffentlichen
```

Mehr dazu in [CONTRIBUTING.md](CONTRIBUTING.md), Änderungen in [CHANGELOG.md](CHANGELOG.md).

### Datenquellen

| Quelle | Inhalt |
| ------ | ------ |
| `https://download.kundida.de/data/releases.json` | Katalog der Mac-Apps (Version, ZIP, SHA-256) |
| `https://download.kundida.de/appcast/<app>.xml` | Build-Nummer (`sparkle:version`) und Neuerungen |
| `https://itunes.apple.com/lookup?id=6792370458` | App-Store-Apps des Entwicklerkontos |
| `https://api.github.com/repos/holgerdaehn/<repo>` | GitHub-Tools und deren neuestes Release |

## Lizenz

[MIT](LICENSE) © 2026 Holger Dähn
