# Beitragen zur Kundida Toolbox

Danke, dass du die Kundida Toolbox verbessern möchtest!

## Voraussetzungen

- **macOS 14 (Sonoma)** oder neuer
- **Xcode** mit Swift 5.10 oder neuer

## Projekt bauen

```bash
swift build                # Debug-Build
Scripts/make_app.sh        # baut build/KundidaToolbox.app inkl. Sparkle
open build/KundidaToolbox.app
```

Die App-Version (`CFBundleShortVersionString`) wird in `Distribution/Info.plist`
gepflegt. Die Build-Nummer setzt `make_app.sh` automatisch als `JJJJ.MM.TT.HHMM`
(monoton steigend, wichtig für Sparkle).

## Aufbau

| Datei | Inhalt |
| ----- | ------ |
| `Catalog.swift` | Datenmodell, Versionsvergleich, Kurztexte (`appSummaries`), GitHub-Quellen |
| `Appcast.swift` | Sparkle-Appcast lesen (Build-Nummer, Neuerungen) |
| `Installer.swift` | Prüfsumme, Entpacken, Signaturprüfung, sicheres Ablegen |
| `ToolboxStore.swift` | Katalog laden, Status, Installieren/Aktualisieren/Deinstallieren |
| `ToolboxView.swift` | Menüleisten-Fenster |
| `SettingsView.swift` | Einstellungen |
| `AppUpdater.swift` | Selbstaktualisierung (Sparkle) |

## Konventionen

- Kommentare und UI-Texte auf **Deutsch**.
- Keine neuen Abhängigkeiten ohne guten Grund.
- Nichts im Hintergrund installieren – jede Änderung am System nur nach Nutzeraktion.
- Änderungen in [CHANGELOG.md](CHANGELOG.md) unter „Unveröffentlicht“ eintragen.

## Release

```bash
~/Developer/signing/release.sh KundidaToolbox <Version>
```

Baut, signiert, notarisiert, taggt, legt das GitHub-Release an und
aktualisiert Download-Seite und Sparkle-Appcast.
