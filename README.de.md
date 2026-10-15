<p align="center">
  <img src="AppPad/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" alt="AppPad">
</p>

<h1 align="center">AppPad</h1>

<p align="center">
  Das originale Launchpad – zurück auf macOS 26+. Dazu Zwischenablage, Workflows, App-Kurzbefehle und Fenstersteuerung.
</p>

<p align="center">
  <a href="https://apppad.youmindhub.com">Website</a>
</p>

<p align="center">
  <a href="README.md">English</a> ·
  <a href="README.zh-CN.md">简体中文</a> ·
  <a href="README.zh-TW.md">繁體中文</a> ·
  <a href="README.ja.md">日本語</a> ·
  <a href="README.ko.md">한국어</a> ·
  Deutsch ·
  <a href="README.es.md">Español</a> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.it.md">Italiano</a> ·
  <a href="README.nl.md">Nederlands</a>
</p>

---

## Installation

### Option 1: DMG herunterladen

[Neueste Version herunterladen](https://github.com/umindhub/AppPad/releases/latest), DMG öffnen und AppPad in den Ordner „Programme“ ziehen.

### Option 2: Homebrew

```bash
brew tap umindhub/tap
brew trust umindhub/tap
brew install --cask apppad
```

## Funktionen

### Launchpad
- Originalgetreue Nachbildung des klassischen macOS-Launchpads, Standardanordnung folgt der Systemreihenfolge
- Öffnen per Vier-Finger-Zusammenziehen, über die Menüleiste oder per Klick auf AppPad im Dock (erneuter Klick schließt)
- Ordner, Apps per Drag & Drop anordnen oder zu Ordnern zusammenfassen, langes Drücken auf ein Symbol oder ⌥ gedrückt halten für den Bearbeitungsmodus
- Integrierte saubere Deinstallation: entfernt die App samt Restdateien
- Rastersuche, Seitenanzeige (Punkte / Zahlen), Liquid-Glass-Steuerelemente
- Hintergründe: Weiß / Hellgrau / Dunkelgrau / Hintergrundbild / eigene Farbe, getrennte Einstellungen für helles und dunkles Erscheinungsbild

### Zwischenablage
- Texte und Bilder werden dauerhaft gespeichert
- Jeder kopierte Eintrag kann gesichert werden
- `⌘1`–`⌘0` zum schnellen Einsetzen, Filter nach Quell-App, Suchsyntax `AppName::`, Live-Vorschau

### Workflows
- `⌘Space` öffnet das Workflow-Panel: Apps und Workflows gemeinsam nach Nutzung sortiert
- Workflows führen Shell-Skripte, AppleScript, Kurzbefehle oder HTTP-Anfragen aus, auch mit Argumenten (z. B. `time 10`)
- Integriert: Papierkorb entleeren, Timer stellen, Wecker stellen, Lautstärke einstellen, Alle Apps beenden …
- Deklarierte Berechtigungen werden durch eine echte Sandbox erzwungen (Einmal erlauben / Nicht erlauben / Immer erlauben)
- Workflows als JSON-Datei oder Link importieren und teilen

### Rechner
- Rechenausdruck direkt in das Suchfeld des Workflow-Panels eingeben (wissenschaftliche Notation wird unterstützt)

### App-Kurzbefehle
- Jeder App einen globalen Tastaturkurzbefehl zuweisen

### Fenstersteuerung
- Links / rechts andocken (½ → ⅓ → ⅔), maximieren, wiederherstellen, auf einen anderen Bildschirm verschieben – alle Kurzbefehle anpassbar

### Sonstiges
- Beim Anmelden starten
- `⌘⇧J` / `⌘⇧K` wechselt mit einer fließenden Animation zwischen Launchpad, Zwischenablage und Workflows
- 10 Sprachen: de, en, es, fr, it, ja, ko, nl, zh-Hans, zh-Hant

## Systemvoraussetzungen

- macOS 26 oder neuer
- Xcode 27 (zum Kompilieren aus dem Quellcode)

## Kompilieren

1. `AppPad.xcodeproj` öffnen
2. Ein Scheme wählen: `AppPad Dev`, `AppPad Beta` oder `AppPad`
3. Eigenes Signing-Team einstellen, dann kompilieren und ausführen

Abhängigkeiten werden über den Swift Package Manager geladen.

## Lizenz

AppPad verwendet eine geteilte Lizenz:

| Teil | Lizenz |
| --- | --- |
| Quellcode der App AppPad (alles, was unten nicht aufgeführt ist) | [AGPL-3.0](LICENSE) |
| Integrierte Workflows (`AppPad/Workflow/BuiltinWorkflows.swift`, `*.shortcut`) | [MIT](LICENSE-MIT) |
| Spezifikation des Workflow-Formats | [MIT](LICENSE-MIT) |
| Workflows von Drittanbietern im Workflow Market | [MIT](LICENSE-MIT), © ihre Autoren |

- **AGPL-3.0**: Du darfst AppPad nutzen, ändern und weitergeben, aber jedes verbreitete oder über ein Netzwerk bereitgestellte abgeleitete Werk muss unter der AGPL-3.0 mit vollständigem Quellcode veröffentlicht werden.
- **Kommerzielle Lizenz**: Für Closed-Source- oder proprietäre Nutzung wende dich über die [Website](https://apppad.youmindhub.com) an den Autor, um eine kommerzielle Lizenz zu erhalten.
- **MIT für Workflows**: Jeder darf Workflows frei schreiben, teilen oder verkaufen und das Workflow-Format in anderen Tools implementieren – ohne AGPL-Pflichten.
- Von dir erstellte Workflows gehören dir. Im Workflow Market eingereichte Workflows müssen unter MIT lizenziert sein.
- Der Name „AppPad“ und das Symbol sind nicht Teil dieser Lizenzen; Forks müssen einen anderen Namen und ein anderes Symbol verwenden.

## Mitwirken

Issues und Pull Requests sind willkommen. Mit dem Einreichen eines Beitrags stimmst du zu, dass er unter der Lizenz des geänderten Teils steht, und räumst dem Maintainer das Recht ein, deinen Beitrag auch unter der kommerziellen Lizenz zu vertreiben.

## Danksagungen

- [GRDB.swift](https://github.com/groue/GRDB.swift) — MIT-Lizenz

---

© 2026 YouMindHub
