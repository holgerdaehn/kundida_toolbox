# Sicherheitsrichtlinie

Die Kundida Toolbox lädt Apps aus dem Internet herunter und installiert sie.
Sicherheit hat daher hohe Priorität.

## Unterstützte Versionen

| Version | Unterstützt |
| ------- | ----------- |
| 1.0.x   | ✅          |

## Eine Sicherheitslücke melden

**Bitte melde Sicherheitslücken nicht über öffentliche GitHub-Issues.**

Bevorzugt über **GitHub Private Vulnerability Reporting**:
„Security“ → „Report a vulnerability“ im
[Repository](https://github.com/holgerdaehn/Kundida_Toolbox/security/advisories/new).

Alternativ per E-Mail an **support@kundida.de** mit dem Betreff
`[Kundida Toolbox Security]`.

Bitte gib an:
- betroffene Version / Commit,
- eine Beschreibung des Problems und der möglichen Auswirkung,
- nach Möglichkeit eine Reproduktion (Proof of Concept).

Du erhältst in der Regel innerhalb von **7 Tagen** eine erste Rückmeldung.

## Sicherheitsrelevantes Design (Kurzüberblick)

- **Keine Hintergrund-Installationen:** Installiert, aktualisiert und deinstalliert
  wird ausschließlich nach einem Klick. Automatisch wird nur nach Updates gesucht.
- **Integrität:** Jeder Download wird per SHA-256 gegen den Katalog
  (`releases.json`) bzw. die Angabe von GitHub geprüft, bevor er entpackt wird.
- **Herkunft:** Kundida-Apps müssen mit der Developer ID `LX259B8S89` signiert sein
  (`SecStaticCodeCheckValidity` mit Designated Requirement), sonst wird nichts
  installiert.
- **Sicheres Ersetzen:** Eine vorhandene App wird erst entfernt, wenn die neue
  vollständig vorliegt; bei Fehlern wird die alte Version wiederhergestellt.
- **Deinstallation** legt Apps in den Papierkorb (wiederherstellbar).
- **Selbstaktualisierung** über Sparkle mit EdDSA-signiertem Appcast.
- **Keine Anmeldung, keine Telemetrie.** Netzwerkzugriffe gehen nur an
  download.kundida.de, itunes.apple.com (App-Store-Versionen) und api.github.com.
