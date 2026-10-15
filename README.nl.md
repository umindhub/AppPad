<p align="center">
  <img src="AppPad/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" alt="AppPad">
</p>

<h1 align="center">AppPad</h1>

<p align="center">
  Het originele Launchpad, terug op macOS 26+, met klembord, workflows, app-sneltoetsen en vensterbeheer.
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
  <a href="README.de.md">Deutsch</a> ·
  <a href="README.es.md">Español</a> ·
  <a href="README.fr.md">Français</a> ·
  <a href="README.it.md">Italiano</a> ·
  Nederlands
</p>

---

## Installatie

### Optie 1: DMG downloaden

[Download de nieuwste versie](https://github.com/umindhub/AppPad/releases/latest), open de DMG en sleep AppPad naar de map Apps.

### Optie 2: Homebrew

```bash
brew tap umindhub/tap
brew trust umindhub/tap
brew install --cask apppad
```

## Functies

### Launchpad
- Getrouwe nabootsing van het klassieke macOS-Launchpad, standaardindeling volgt de systeemvolgorde
- Openen door met vier vingers te knijpen, via de menubalk of door op AppPad in het Dock te klikken (nogmaals klikken sluit)
- Mappen, slepen om te ordenen of mappen te maken; houd een symbool of de ⌥-toets ingedrukt voor de wijzigmodus
- Ingebouwde schone verwijdering: verwijdert de app samen met achtergebleven bestanden
- Zoeken in raster, pagina-indicator (stippen / cijfers), Liquid Glass-regelaars
- Achtergronden: wit / lichtgrijs / donkergrijs / bureaubladachtergrond / aangepaste kleur, aparte instellingen voor lichte en donkere weergave

### Klembord
- Tekst en afbeeldingen worden permanent bewaard
- Elk gekopieerd onderdeel kan worden bewaard
- `⌘1`–`⌘0` om snel te plakken, filter op bron-app, zoeksyntaxis `AppNaam::`, live voorvertoning

### Workflows
- `⌘Space` opent het workflowpaneel: apps en workflows samen gesorteerd op gebruik
- Workflows voeren shellscripts, AppleScript, Opdrachten of HTTP-verzoeken uit, met argumenten (bijv. `time 10`)
- Ingebouwd: Leeg prullenmand, Stel timer in, Stel wekker in, Stel volume in, Stop alle apps…
- Opgegeven toestemmingen worden afgedwongen door een echte sandbox (Sta eenmaal toe / Sta niet toe / Sta altijd toe)
- Workflows importeren en delen als JSON-bestand of link

### Rekenmachine
- Typ een berekening direct in het zoekveld van het workflowpaneel (wetenschappelijke notatie wordt ondersteund)

### App-sneltoetsen
- Wijs aan elke app een globale sneltoets toe

### Vensterbeheer
- Links / rechts vastzetten (½ → ⅓ → ⅔), maximaliseren, herstellen, naar een ander scherm verplaatsen — alle sneltoetsen zijn aanpasbaar

### Overig
- Starten bij inloggen
- `⌘⇧J` / `⌘⇧K` wisselt met een animatie tussen Launchpad, klembord en workflows
- 10 talen: de, en, es, fr, it, ja, ko, nl, zh-Hans, zh-Hant

## Systeemvereisten

- macOS 26 of nieuwer
- Xcode 27 (om vanuit de broncode te bouwen)

## Bouwen

1. Open `AppPad.xcodeproj`
2. Kies een scheme: `AppPad Dev`, `AppPad Beta` of `AppPad`
3. Stel je eigen ondertekeningsteam in, bouw en start

Afhankelijkheden worden opgehaald via Swift Package Manager.

## Licentie

AppPad gebruikt een gesplitste licentie:

| Onderdeel | Licentie |
| --- | --- |
| Broncode van de app AppPad (alles wat hieronder niet staat) | [AGPL-3.0](LICENSE) |
| Ingebouwde workflows (`AppPad/Workflow/BuiltinWorkflows.swift`, `*.shortcut`) | [MIT](LICENSE-MIT) |
| Specificatie van het workflowformaat | [MIT](LICENSE-MIT) |
| Workflows van derden in de Workflow Market | [MIT](LICENSE-MIT), © de makers |

- **AGPL-3.0**: je mag AppPad gebruiken, wijzigen en verspreiden, maar elk verspreid of via een netwerk aangeboden afgeleid werk moet onder AGPL-3.0 met volledige broncode worden gepubliceerd.
- **Commerciële licentie**: voor closed-source of propriëtair gebruik neem je via de [website](https://apppad.youmindhub.com) contact op met de maker voor een commerciële licentie.
- **MIT voor workflows**: iedereen mag vrij workflows schrijven, delen of verkopen en het workflowformaat in andere tools implementeren, zonder AGPL-verplichtingen.
- Workflows die je zelf maakt zijn van jou. Workflows die je in de Workflow Market plaatst moeten onder MIT vallen.
- De naam "AppPad" en het symbool vallen niet onder deze licenties; forks moeten een andere naam en een ander symbool gebruiken.

## Bijdragen

Issues en pull requests zijn welkom. Door een bijdrage in te dienen ga je ermee akkoord dat deze valt onder de licentie van het onderdeel dat je wijzigt, en geef je de beheerder het recht je bijdrage ook onder de commerciële licentie te verspreiden.

## Dankbetuiging

- [GRDB.swift](https://github.com/groue/GRDB.swift) — MIT-licentie

---

© 2026 YouMindHub
