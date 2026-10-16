<p align="center">
  <img src="AppPad/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" alt="AppPad">
</p>

<h1 align="center">AppPad</h1>

<p align="center">
  Riporta il Launchpad originale su macOS 26+ (compatibile anche con macOS 15), con appunti, flussi di lavoro, abbreviazioni per le app e controllo delle finestre.
</p>

<p align="center">
  <a href="https://apppad.youmindhub.com">Sito web</a>
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
  Italiano ·
  <a href="README.nl.md">Nederlands</a>
</p>

---

## Installazione

### Opzione 1: scarica il DMG

[Scarica l’ultima versione](https://github.com/umindhub/AppPad/releases/latest), apri il DMG e trascina AppPad nella cartella Applicazioni.

### Opzione 2: Homebrew

```bash
brew tap umindhub/tap
brew trust umindhub/tap
brew install --cask apppad
```

## Funzionalità

### Launchpad
- Ricostruzione fedele del classico Launchpad di macOS, disposizione predefinita secondo l’ordine di sistema
- Si apre con il pizzico a quattro dita, dalla barra dei menu o facendo clic su AppPad nel Dock (un altro clic lo chiude)
- Cartelle, trascina per riordinare o creare cartelle; tieni premuta un’icona o il tasto ⌥ per la modalità modifica
- Disinstallazione pulita integrata: rimuove l’app insieme ai file residui
- Ricerca a griglia, indicatore di pagina (punti / numeri), controlli Liquid Glass (macOS 26+)
- Sfondi: bianco / grigio chiaro / grigio scuro / sfondo scrivania / colore personalizzato, impostazioni separate per aspetto chiaro e scuro

### Appunti
- Testi e immagini conservati in modo permanente
- Qualsiasi elemento copiato può essere salvato
- `⌘1`–`⌘0` per incollare rapidamente, filtro per app di origine, sintassi di ricerca `NomeApp::`, anteprima dal vivo

### Flussi di lavoro
- `⌘Space` apre il pannello Flussi di lavoro: app e flussi di lavoro ordinati insieme in base all’utilizzo
- I flussi di lavoro eseguono script shell, AppleScript, Comandi Rapidi o richieste HTTP, con argomenti (es. `time 10`)
- Integrati: Svuota il Cestino, Imposta timer, Imposta sveglia, Imposta volume, Esci da tutte le app…
- I permessi dichiarati sono applicati da una vera sandbox (Consenti una volta / Non consentire / Consenti sempre)
- Importa e condividi flussi di lavoro come file JSON o link

### Calcolatrice
- Digita un’espressione direttamente nel campo di ricerca del pannello Flussi di lavoro per calcolare (supporta la notazione scientifica)

### Abbreviazioni app
- Assegna un’abbreviazione da tastiera globale a qualsiasi app

### Controllo finestre
- Aggancia a sinistra / destra (½ → ⅓ → ⅔), ingrandisci, ripristina, sposta su un altro monitor — tutte le abbreviazioni sono personalizzabili

### Altro
- Avvia al login
- `⌘⇧J` / `⌘⇧K` passa con un’animazione tra Launchpad, Appunti e Flussi di lavoro
- 10 lingue: de, en, es, fr, it, ja, ko, nl, zh-Hans, zh-Hant

## Requisiti

- macOS 15 o successivo
- Xcode 27 (per compilare dai sorgenti)

## Compilazione

1. Apri `AppPad.xcodeproj`
2. Scegli uno schema: `AppPad Dev`, `AppPad Beta` o `AppPad`
3. Imposta il tuo team di firma, poi compila ed esegui

Le dipendenze sono gestite da Swift Package Manager.

## Licenza

AppPad usa una licenza suddivisa:

| Parte | Licenza |
| --- | --- |
| Codice sorgente dell’app AppPad (tutto ciò che non è elencato sotto) | [AGPL-3.0](LICENSE) |
| Flussi di lavoro integrati (`AppPad/Workflow/BuiltinWorkflows.swift`, `*.shortcut`) | [MIT](LICENSE-MIT) |
| Specifica del formato dei flussi di lavoro | [MIT](LICENSE-MIT) |
| Flussi di lavoro di terze parti nel Workflow Market | [MIT](LICENSE-MIT), © i rispettivi autori |

- **AGPL-3.0**: puoi usare, modificare e ridistribuire AppPad, ma qualsiasi opera derivata distribuita od offerta via rete deve essere pubblicata sotto AGPL-3.0 con il codice sorgente completo.
- **Licenza commerciale**: per un uso closed source o proprietario, contatta l’autore tramite il [sito web](https://apppad.youmindhub.com) per ottenere una licenza commerciale.
- **MIT per i flussi di lavoro**: chiunque può scrivere, condividere o vendere flussi di lavoro liberamente e implementarne il formato in altri strumenti, senza obblighi AGPL.
- I flussi di lavoro che crei sono tuoi. Quelli inviati al Workflow Market devono avere licenza MIT.
- Il nome “AppPad” e la sua icona non sono coperti da queste licenze; i fork devono usare un nome e un’icona diversi.

## Contribuire

Issue e pull request sono benvenute. Inviando un contributo accetti che venga pubblicato con la licenza della parte che modifichi e concedi al maintainer il diritto di distribuirlo anche con la licenza commerciale.

## Ringraziamenti

- [GRDB.swift](https://github.com/groue/GRDB.swift) — licenza MIT

---

© 2026 YouMindHub
