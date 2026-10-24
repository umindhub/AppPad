# Registro delle modifiche

<p align="center">
  <a href="../../CHANGELOG.md">English</a> ·
  <a href="CHANGELOG.zh-CN.md">简体中文</a> ·
  <a href="CHANGELOG.zh-TW.md">繁體中文</a> ·
  <a href="CHANGELOG.ja.md">日本語</a> ·
  <a href="CHANGELOG.ko.md">한국어</a> ·
  <a href="CHANGELOG.de.md">Deutsch</a> ·
  <a href="CHANGELOG.es.md">Español</a> ·
  <a href="CHANGELOG.fr.md">Français</a> ·
  Italiano ·
  <a href="CHANGELOG.nl.md">Nederlands</a>
</p>

Tutte le modifiche rilevanti di AppPad sono documentate in questo file.
Il formato si basa su [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) e il progetto segue il [versionamento semantico](https://semver.org/).

> Questo documento è una traduzione di [CHANGELOG.md](../../CHANGELOG.md). In caso di differenze, fa fede la versione inglese.

## v1.3.9

### Changed
- Launchpad: Il rilascio di un’icona non ricostruisce più l’intera pagina, quindi spostare e raggruppare le icone resta fluido.

### Fixed
- Launchpad: Ora è possibile afferrare un’altra icona mentre la precedente è ancora in animazione, senza sfarfallii o blocchi.
- Launchpad: Facendo clic su una cartella subito dopo avervi rilasciato un’app, la cartella si apre immediatamente.
- Launchpad: Le icone che stanno ancora scorrendo al loro posto si possono cliccare e trascinare dove appaiono sullo schermo.

## v1.3.8

### Added

#### Flussi di lavoro
- Pulsante Esegui (⌘S) nel pannello dei flussi di lavoro: esegue il flusso selezionato, lascia aperto il pannello e mostra il risultato in «Ultima esecuzione».
- I flussi di lavoro integrati ora si possono visualizzare (sola lettura) nelle Impostazioni.

### Changed
- Flussi di lavoro: eseguendo senza un argomento obbligatorio, il suggerimento viene segnalato con un’icona di avviso e una breve vibrazione.

### Fixed
- Launchpad: risolto il problema per cui la disposizione veniva cancellata quando un aggiornamento o una reinstallazione tramite .pkg richiedeva molto tempo.

## v1.3.7

### Changed
- Clip salvate: Il campo del nome ora arriva fino alla data e il contenuto è allineato al nome; in Modifica contenuto, titolo e nome sono allineati al testo.

### Fixed
- Impostazioni: La finestra Impostazioni ora passa in primo piano quando viene aperta da Launchpad, Flussi di lavoro, Appunti o dalla barra dei menu.
- Clip salvate: ⌘Q ed Esci da AppPad ora funzionano anche con Modifica contenuto o una conferma aperti.

## v1.3.6

### Added

#### Impostazioni
- Nuovo interruttore «Mostra frecce per cambiare pannello» in Generali: mostra o nasconde le frecce ← / → accanto ai titoli di Appunti e Flussi di lavoro. ⌘⇧K / ⌘⇧J cambiano comunque pannello.
- Nuovo interruttore «Mostra suggerimenti abbreviazioni» in Generali: mostra o nasconde la riga delle abbreviazioni sotto i titoli di Appunti e Flussi di lavoro. Se disattivo, il titolo è allineato al campo di ricerca.
- Entrambi sono attivi per impostazione predefinita.

## v1.3.5

### Added

#### Launchpad
- Abbreviazione da tastiera opzionale per aprire Launchpad (⌥Spazio di default, disattivata di default): premila di nuovo per chiuderlo. Attivala e modificala in Impostazioni › AppPad › Apri con abbreviazione; quando è attiva compare anche nel menu della barra dei menu.

#### Guida di benvenuto
- La pagina del pizzico ora permette di attivare l’abbreviazione di Launchpad e di scegliere un angolo attivo per Launchpad.

### Changed
- Backup: i backup delle abbreviazioni ora includono l’abbreviazione di Launchpad.

## v1.3.4

### Added

#### Launchpad
- Scorrimento rapido delle pagine (Impostazioni › Generali, disattivato di default): basta un breve scorrimento con due dita per cambiare pagina, e un solo scorrimento può avanzare di più pagine. Anche gli scorrimenti in alto/in basso seguono le dita.
- Con lo scorrimento rapido attivo, tieni premuti e trascina i punti di pagina per scorrere le pagine in modo continuo; al rilascio si posiziona sulla pagina più vicina. Funziona anche nelle cartelle.

### Changed
- Launchpad: Puoi trascinare l’icona successiva mentre la precedente sta ancora raggiungendo il suo posto (ad esempio una cartella), senza attendere la fine dell’animazione.

## v1.3.3

### Added

#### Angoli attivi
- Nuovi angoli attivi in Impostazioni › AppPad: ogni angolo dello schermo può aprire AppPad, Flussi di lavoro o Appunti, oppure eseguire un’azione di macOS (Mission Control, Finestre applicazioni, Scrivania, Centro Notifiche, Nota Rapida, salvaschermo, stop del monitor, Blocca schermo).
- Tieni premuti ⌘, ⌥, ⌃ o ⇧ (anche insieme) mentre scegli un’azione per far funzionare quell’angolo solo con quei tasti premuti, come in macOS.

### Note
- Centro Notifiche e Nota Rapida richiedono il permesso di accessibilità.
- Se un angolo è impostato anche negli angoli attivi di macOS, vengono eseguiti entrambi; AppPad mostra un avviso con un collegamento a Impostazioni di Sistema.

## v1.3.2

### Added

#### Workflow
- Nuova azione integrata “Precompila comando nel Terminale”: apre il Terminale nella cartella scelta con un comando già inserito nel prompt. Non viene eseguito nulla finché non premi A capo. `{{input}}` viene sostituito dall’argomento.

### Changed
- Workflow: “Installa Homebrew” ora precompila il comando di installazione ufficiale nel Terminale; premi A capo per avviarlo.
- Workflow: prima che uno script controlli un’altra app, AppPad chiede il permesso a macOS, così l’app compare in Privacy e sicurezza › Automazione. Se l’accesso viene negato, il workflow si interrompe con un messaggio chiaro.
- Assistenti IA: l’IA può scrivere workflow che precompilano comandi nel Terminale; anche l’installazione di Homebrew tramite IA si limita a precompilare il comando.

### Note
- Se il Terminale chiede di terminare un processo in esecuzione quando chiudi la finestra, aggiungi `zsh` ai processi ignorati nelle impostazioni del Terminale (Profili › Shell › Chiedi prima di chiudere).

## v1.3.1

### Added

#### Flussi di lavoro
- Nuovo flusso di lavoro integrato “Cerca su App Store”: digita `mas` o `appstore` seguito dalle parole chiave per aprire i risultati direttamente nell’App Store.

### Fixed
- Pannello Flussi di lavoro: ⌘1–⌘0 su un flusso che accetta un argomento ora lo seleziona e ne inserisce il nome, pronto per l’argomento, invece di non fare nulla.

## v1.3.0

### Fixed
- Appunti: i risultati della calcolatrice copiati in AppPad ora mostrano l’icona di AppPad come app di origine invece di un segnaposto vuoto.

## v1.2.9

### Added

#### Flussi di lavoro
- Ogni flusso di lavoro mostra la sua origine: Integrato (verde), Mio (blu, scritto da te o salvato da un assistente IA) o Di terze parti (arancione, con il sito di provenienza o “File importato”).
- Il pannello dei flussi di lavoro segna le righe di terze parti con un’icona arancione; l’anteprima mostra il link completo e quando è stato importato.
- Le richieste di permesso mostrano l’origine del flusso di lavoro; le conferme di esecuzione la mostrano per quelli di terze parti.

### Changed
- Flussi di lavoro: Modificare passaggi o permessi di un flusso integrato o di terze parti lo contrassegna come “Modificato”; uno di terze parti resta di terze parti anche dopo la modifica.
- Flussi di lavoro: Quando un flusso di lavoro viene sostituito da uno di origine diversa, AppPad chiede di nuovo i suoi permessi.

### Fixed
- Flussi di lavoro: I flussi importati potevano sostituire quelli integrati riutilizzandone l’ID; ora vengono saltati.
- Backup: Il ripristino non sovrascrive più i flussi integrati; vengono ripristinati solo lo stato attivo/disattivo e la scorciatoia del pannello.

### Note
- I flussi di lavoro non integrati aggiunti prima di questa versione appaiono come “Mio”, perché la loro origine non era registrata.

## v1.2.8

### Added

#### Assistenti IA
- Gli assistenti IA possono cercare, installare e disinstallare app con Homebrew. Vengono installate solo app del catalogo ufficiale di Homebrew autenticate da Apple (strumenti da riga di comando solo dall’interno dell’app), e ogni app viene ricontrollata dopo l’installazione.
- Ogni installazione e disinstallazione chiede prima la tua conferma. Puoi disattivarla in Impostazioni › Assistenti IA; un avviso elenca allora i rischi.
- Se Homebrew manca, AppPad propone di aprire Terminale con il comando di installazione ufficiale.

#### Flussi di lavoro
- Nuovo flusso di lavoro integrato “Installa Homebrew”.

### Changed
- Assistenti IA: le conferme avviate dall’IA (installazione, disinstallazione, salvataggio dei flussi, esecuzione, permessi) ora appaiono in primo piano senza portare avanti le altre finestre di AppPad.

### Note
- Le app disinstallate con Homebrew vengono eliminate subito, non spostate nel Cestino.
- Formule e tap di terze parti non sono supportati. Homebrew viene rilevato solo in /opt/homebrew e /usr/local.

## v1.2.7

### Added

#### Barra dei menu
- «Controlla aggiornamenti…» ora ha la scorciatoia ⌘U.

### Fixed
- Barra dei menu: Le scorciatoie globali (Workflow, Appunti, scorciatoie di app e finestre) premute con il menu aperto ora lo chiudono ed eseguono subito l’azione, invece di attendere la chiusura del menu.
- Barra dei menu: Aprire Impostazioni con ⌘, dal menu mentre Workflow o Appunti sono aperti non rende più trasparente per un istante lo sfondo del pannello.

## v1.2.6

### Fixed
- Launchpad: Modificare il numero di righe o colonne della griglia non riordina più tutte le pagine. Quando la griglia si ingrandisce, solo le pagine che erano piene prendono icone dall’inizio della pagina successiva e quelle non piene restano invariate; quando si riduce, le icone che non entrano più passano all’inizio della pagina successiva.

## v1.2.5

### Changed
- Launchpad: le app ancora in download dall’App Store mostrano ora la loro icona con opacità al 70%, così sono più facili da riconoscere.

### Fixed
- Launchpad: al termine di un download dall’App Store compariva per un attimo un riquadro vuoto tratteggiato prima dell’icona dell’app. Ora l’icona cambia direttamente.
- Launchpad: le app appena installate con Homebrew o trascinate in Applicazioni non mostrano più prima l’icona generica.

## v1.2.4

### Added

#### Assistenti IA (MCP)
- Configurazione di Claude Desktop con un clic: i pulsanti «Aggiungi a Claude Desktop» e «Rimuovi da Claude Desktop» mostrano lo stato attuale (Aggiunto / Non aggiunto / Non installato). Viene modificata solo la voce di AppPad in claude_desktop_config.json; gli altri server MCP restano invariati.
- Se AppPad è stato spostato dopo l’aggiunta, lo stato lo segnala e «Aggiungi a Claude Desktop» aggiorna il percorso.

#### Flussi di lavoro
- Nuovi flussi di lavoro integrati «Aggiungi AppPad a Claude Desktop» e «Rimuovi AppPad da Claude Desktop». Digita «claude» o «mcp» nel pannello dei flussi di lavoro per trovarli.

#### Guida di benvenuto
- La pagina IA ora ha gli stessi pulsanti Aggiungi / Rimuovi per Claude Desktop.

### Note
- Riavvia Claude Desktop dopo aver aggiunto o rimosso AppPad per applicare la modifica.
- Se Claude Desktop non è installato, non viene aggiunto nulla e AppPad te lo segnala.
- Prima di ogni modifica, accanto al file viene salvato un backup della versione precedente come claude_desktop_config.json.apppad-backup.

## v1.2.3

### Fixed
- Appunti: Gli elementi salvati ora sono ordinati per uso più recente, come la cronologia. Un elemento sale in cima dopo averlo incollato o copiato, invece di restare nell’ordine di salvataggio.

## v1.2.2

### Changed
- Pannello dei workflow: «Ultima esecuzione» nell’anteprima ora mostra un’icona di stato nello stesso stile del controllo dell’argomento, di una tonalità più chiara: ✓ verde se riuscita, ✕ rossa se non riuscita, – grigio se annullata, con il colore del testo abbinato, così l’ultimo risultato si capisce a colpo d’occhio.
- Pannello dei workflow: Un’esecuzione annullata non viene più mostrata in rosso come un errore.

## v1.2.1

### Changed
- Launchpad: Migliorato il trascinamento tra app e cartelle.

### Fixed
- Impostazioni: Risolto un problema per cui la finestra Impostazioni si sovrapponeva ad altre finestre all'apertura.

## v1.2.0

### Changed
- Launchpad: facendo clic su un’app, Launchpad ora si chiude con la stessa animazione di zoom e dissolvenza del clic su uno spazio vuoto, invece di sparire all’istante.

## v1.1.9

### Aggiunto
- Launchpad: le icone delle app ora mostrano gli stessi badge rossi del Dock (messaggi non letti, aggiornamenti). Le cartelle mostrano la somma dei badge delle app che contengono, oppure un punto rosso quando quelle app hanno solo badge di testo.
- Impostazioni › Generali: nuovo interruttore «Mostra i badge delle app», attivo per impostazione predefinita. I badge vengono letti dal Dock e richiedono il permesso di Accessibilità; senza di esso, l’interruttore mostra un suggerimento con un pulsante per aprire Impostazioni di Sistema.

## v1.1.8

### Modificato
- Aspetto: perfezionate la forma dei pulsanti e il colore degli interruttori.
- Abbreviazioni: migliorate le prestazioni dell’elenco delle abbreviazioni.
- Clip salvati: cambiata la gestione degli elementi duplicati degli Appunti.

### Corretto
- Corretto un problema nell’impostazione della larghezza del lato sinistro.

## v1.1.7

### Modificato
- Aspetto: tutti gli interruttori ora sono verdi e tutti i pulsanti hanno la stessa forma a pillola.
- Disinstallazione: perfezionata la pagina di conferma dell’eliminazione.

## v1.1.6

### Aggiunto

#### Guida di benvenuto
- Al primo avvio AppPad ora apre una guida di benvenuto invece di Launchpad: un breve tour delle funzioni, seguito da alcuni passaggi di configurazione. Ogni passaggio si può saltare, ed Esc o ⌘W chiudono la guida.
- Pizzico a quattro dita: attivalo o disattivalo, scopri quali gesti di macOS disattivare e in quale ordine, e apri le impostazioni del trackpad con un clic.
- Appunti: attiva o disattiva la cronologia, scopri le sue abbreviazioni e i tasti più utili (⌘1–⌘0, ⌘S, ⌘↩), e come un clic sull’icona di un’app mostri solo ciò che è stato copiato da quell’app.
- ⌘Space per i Flussi di lavoro: disattiva l’abbreviazione di Spotlight con un clic. La modifica ha effetto subito, senza uscire dall’account, e si può annullare dalla stessa pagina. Se non può essere cambiata automaticamente, la guida rimanda alle impostazioni della Tastiera.
- Abbreviazioni app: provale assegnando ⌃⌘J a Safari con un clic, poi aggiungine altre in Impostazioni › Abbreviazioni app.
- L’IA scrive flussi di lavoro: attiva Assistenti IA (MCP), copia la configurazione per Claude Code o altri client e prova i prompt di esempio. Ogni flusso di lavoro scritto dall’IA richiede comunque la tua approvazione.
- Permessi e avvio: concedi l’Accessibilità (necessaria per incollare e per il controllo finestre) e attiva l’avvio al login, con lo stato in tempo reale di ciascuno.
- L’ultima pagina elenca le abbreviazioni per Launchpad, Appunti, elementi salvati e Flussi di lavoro; «Apri AppPad» porta direttamente a Launchpad.
- Scorri a sinistra o a destra con due dita, oppure fai clic o trascina lungo i punti in basso, per spostarti tra le pagine.
- Riapri la guida in qualsiasi momento da Impostazioni › Info › Mostra guida di benvenuto….

### Modificato
- La guida di benvenuto sostituisce i suggerimenti separati e una tantum sul pizzico e su Spotlight. Se avevi già visto quei suggerimenti, la guida non si apre da sola.
- Gli aggiornamenti automatici attendono la chiusura della guida di benvenuto.

## v1.1.5

### Modificato
- Launchpad: fai clic sul nome di una cartella per rinominarla in qualsiasi momento, non solo in modalità modifica.

### Corretto
- Launchpad: il nome di una cartella non si sposta più a sinistra dopo averla rinominata con ↩.

## v1.1.4

### Corretto
- Corretto: le app appena installate (ad es. tramite Homebrew) potevano mostrare un’icona vuota fino al riavvio di AppPad.

## v1.1.3

### Aggiunto
- Launchpad: le app in download dall’App Store compaiono subito, attenuate con una barra di avanzamento, e tornano normali una volta installate.
- Launchpad: l’eliminazione di un’app mostra una barra di avanzamento sotto la sua icona; l’icona scompare al termine.

### Modificato
- Disinstallazione: le impostazioni e i dati dell’app nei contenitori sandbox vengono mantenuti, come quando si elimina dal Finder, così una reinstallazione li ripristina.

### Corretto
- Disinstallazione: le app dell’App Store e le altre app di proprietà del sistema si possono di nuovo eliminare (il Finder chiede la tua password o Touch ID). I residui in `/Library` vengono rimossi allo stesso modo.
- Disinstallazione: widget ed estensioni dell’app ancora in esecuzione non impediscono più di eliminarla.

## v1.1.2

### Modificato
- Launchpad: aprire e chiudere una cartella con un clic ora è più affidabile.

## v1.1.1

### Modificato
- Aggiornamenti: l’avviso di aggiornamento ora mostra un conto alla rovescia e si chiude da solo allo scadere del tempo.

## v1.1.0

### Modificato
- Launchpad: aprire e chiudere una cartella ora è più fluido e reattivo, con meno lavoro per fotogramma durante l’animazione.

## v1.0.9

### Aggiunto

#### Launchpad
- La ricerca ora trova anche le cartelle per nome, inclusi pinyin e iniziali, proprio come le app.
- Cerca più cose contemporaneamente con `|` o `||`, ad es. `WeChat | Social` mostra insieme l’app e la cartella, così puoi trascinare l’app direttamente nella cartella.

### Modificato
- AppPad ora supporta macOS 15 Sequoia e successivi (in precedenza macOS 26 Tahoe o successivi). I controlli Liquid Glass restano disponibili su macOS 26 e successivi.

## v1.0.8

### Aggiunto

#### Launchpad
- Disinstallare un’app installata con Homebrew (`brew install --cask`) ora la rimuove anche da Homebrew: dopo aver spostato l’app e i suoi residui nel Cestino, AppPad esegue `brew uninstall --cask` per il suo cask. Senza Homebrew, o per le app che non sono un cask, non cambia nulla.
- Se Homebrew non riesce a completare da solo (ad esempio quando il cask richiede una password di amministratore), AppPad mostra il comando da eseguire nel Terminale, con un pulsante per copiarlo.

#### Flussi di lavoro
- Nel pannello Flussi di lavoro, il risultato di un argomento digitato ora inizia con un segno di spunta verde quando è valido e con una croce rossa quando non lo è.

### Modificato
- Passando da Launchpad al pannello Appunti o Flussi di lavoro, l’ombra del pannello ora compare in dissolvenza durante la trasformazione invece che dopo.
- Le ombre dei pannelli sono disegnate da AppPad e restano all’esterno del pannello. Con uno sfondo traslucido, i pannelli Appunti e Flussi di lavoro ora appaiono esattamente come Launchpad, con la stessa sfocatura e trasparenza e senza scurimenti aggiuntivi.
- Pannello Flussi di lavoro: un risultato valido dell’argomento viene mostrato nel colore normale del testo invece che in verde; uno non valido resta rosso.
- Scegliere Launchpad, Appunti o Flussi di lavoro dal menu della barra dei menu mentre un altro pannello è aperto ora effettua il passaggio come ⌘⇧J / ⌘⇧K.

### Corretto
- Il passaggio tra i pannelli Appunti e Flussi di lavoro con ⌘⇧J / ⌘⇧K poteva produrre un breve sfarfallio.
- Aprire un pannello dalla barra dei menu mentre ne era aperto un altro mostrava brevemente la scrivania.

## v1.0.7

### Aggiunto

#### Assistenti IA (MCP)
- Claude, Cursor e altri client MCP possono elencare ed eseguire i tuoi flussi di lavoro, passando un argomento proprio come nel pannello Flussi di lavoro. I risultati tornano all’IA invece di apparire come notifiche.
- Gli assistenti IA possono anche scrivere flussi di lavoro per te. Ogni flusso nuovo o modificato viene mostrato per intero, script compresi, e viene salvato solo dopo che fai clic su Installa.
- Le esecuzioni usano le stesse conferme e richieste di permesso del pannello Flussi di lavoro. I flussi disattivati restano nascosti.
- Nuovo pannello Assistenti IA (MCP) nelle Impostazioni, sotto Flussi di lavoro: attivo per impostazione predefinita, mostra lo stato della connessione e offre configurazioni pronte da copiare per Claude Desktop, Cursor e Claude Code.
- Se AppPad non è in esecuzione, il client IA lo avvia in background senza aprire Launchpad.

## v1.0.6

### Aggiunto

#### Launchpad
- La ricerca mantiene le cartelle: un’app all’interno di una cartella ora appare come la sua cartella. Aprila con un clic o con ↩; l’app corrispondente viene evidenziata e un altro ↩ la apre.
- I risultati della ricerca si possono trascinare: trascina un’app fuori dal pannello sul Dock o nel Finder.
- Crea cartelle durante la ricerca: rilascia lentamente un’app su un altro risultato per creare una nuova cartella, oppure su una cartella per aggiungerla. Le app trascinate fuori da una cartella aperta dai risultati si possono rilasciare allo stesso modo. Fermati sul bordo del pannello per passare alla pagina di risultati successiva o precedente.

### Modificato
- Quando in una cartella resta una sola app, quell’app ora esce dalla cartella ingrandendosi lentamente invece di comparire di colpo.
- Durante la ricerca, la cartella aperta, la pagina dei risultati e la selezione vengono mantenute quando la disposizione cambia (riordino all’interno di una cartella, rinomina, disinstallazione), e i risultati mantengono il loro ordine dopo un’unione invece di essere riordinati.

### Corretto
- Un clic durante un’animazione di rilascio (ad esempio su una cartella ancora in formazione) poteva chiudere Launchpad.

## v1.0.5

### Aggiunto

#### Aggiornamenti automatici
- AppPad ora si mantiene aggiornato da solo. Ogni giorno alle 4:00 controlla se c’è una nuova versione, la scarica in background e la installa non appena nessun pannello è aperto, poi si riavvia silenziosamente senza aprire Launchpad.
- Controllo saltato perché il Mac era in stop o spento? AppPad lo recupera poco dopo il risveglio e riprova ogni 30 minuti se la rete non è pronta.
- Nuova sezione Aggiornamenti in Impostazioni › Info: attiva o disattiva gli aggiornamenti automatici (attivi per impostazione predefinita), scegli l’orario del controllo, vedi quando è stato eseguito l’ultimo e controlla ora.
- «Cerca aggiornamenti…» nel menu della barra dei menu.
- Se un aggiornamento è in attesa mentre sei nelle Impostazioni, «Riavvia per aggiornare» lo installa subito.
- Gli aggiornamenti vengono verificati con una firma EdDSA prima dell’installazione.

### Modificato
- Impostazioni › Info elenca Sparkle nei Ringraziamenti.

### Nota
- Le versioni precedenti alla 1.0.5 non possono aggiornarsi da sole: installa una volta la 1.0.5 dal DMG o con `brew upgrade --cask apppad`; le versioni successive arrivano automaticamente.

## v1.0.4

### Aggiunto
- Clip salvati: degli elementi di testo ora si può modificare anche il contenuto, oltre al nome. Fai clic sul testo per aprire l’editor; ⌘↩ salva, Esc annulla. Una modifica che duplicherebbe un altro elemento viene rifiutata.

### Modificato
- Clip salvati: il pulsante Copia diventa per un attimo un segno di spunta verde dopo una copia riuscita; la riga mantiene la sua altezza.

### Corretto
- Clip salvati: copiare un elemento non cambia più la sua app di origine in AppPad. La copia ora conta come un utilizzo, come incollare dal pannello Appunti, e sposta l’elemento in cima alla cronologia.

## v1.0.3

### Aggiunto

#### Appunti
- Nuovo pannello «Clip salvati» nelle Impostazioni per sfogliare, cercare e gestire la libreria salvata: icona dell’app di origine, nome, anteprima di due righe e data per ogni elemento, con i pulsanti Copia e Rimuovi.
- Gli elementi salvati possono avere un nome. I nomi sono ricercabili sia nelle Impostazioni sia nel pannello Appunti, e gli elementi con nome mostrano il nome in grassetto nell’elenco.
- ⌘↩ su qualsiasi elemento degli Appunti lo apre in Impostazioni › Clip salvati con il campo del nome pronto per la digitazione; gli elementi non salvati vengono prima salvati. Disponibile anche dal menu contestuale («Modifica in Clip salvati»).

#### Backup e ripristino
- I backup ora includono i nomi degli elementi. I backup meno recenti si ripristinano come prima; durante un’unione, il nome già impostato su questo Mac viene mantenuto.

### Modificato
- Appunti: per eliminare un elemento si usa ⌘⇧⌫ (prima ⌘⌫), così ⌘⌫ nel campo di ricerca torna a cancellare fino all’inizio della riga.
- Appunti: «Mostra nel Finder» passa da ⌘↩ a ⌘⇧↩.

## v1.0.2

### Aggiunto

#### Flussi di lavoro
- Nuova opzione «Chiedi prima di eseguire» nell’editor dei flussi di lavoro: prima dell’esecuzione compare una conferma, sia che il flusso venga avviato dal pannello Flussi di lavoro sia dalle Impostazioni.
- Nel pannello Flussi di lavoro la conferma si apre all’interno del pannello: ↩ esegue, Esc annulla, gli altri tasti vengono ignorati. Un ↩ tenuto premuto o ripetuto rapidamente non conferma mai.
- Il formato dei flussi di lavoro acquisisce un campo facoltativo `"confirm": true`; i file esistenti senza di esso vengono eseguiti come prima.

### Modificato
- Il flusso integrato «Esci da tutte le app» (v1.4) ora chiede conferma, così Tab o ↩ nel pannello Flussi di lavoro non possono più chiudere tutte le app per errore.

## v1.0.1

### Aggiunto

#### Backup e ripristino
- Nuovo pannello Backup nelle Impostazioni: esporta in un unico file `.apppadbackup` e ripristinalo su questo o su un altro Mac.
- Scegli cosa includere: abbreviazioni app (più quelle per Flussi di lavoro, Appunti e finestre), la disposizione di Launchpad con la dimensione della griglia, i flussi di lavoro installati (con icone, abbreviazioni del pannello e stato attivo/disattivo), la cronologia degli Appunti e la libreria salvata.
- Il ripristino mostra il contenuto di un backup prima di modificare qualsiasi cosa; scegli le parti da ripristinare e se unirle a quanto già presente o sostituirlo.
- L’unione aggiunge ciò che manca: le versioni più recenti dei flussi di lavoro sostituiscono quelle più vecchie, e gli elementi degli Appunti vengono confrontati per contenuto, così nulla viene duplicato.
- La disposizione di Launchpad viene sempre sostituita; le app non installate su questo Mac vengono saltate e quelle assenti dal backup vengono aggiunte in fondo.
- I segreti del Portachiavi e i permessi «Consenti sempre» non vengono mai scritti in un backup; i flussi di lavoro ripristinati chiedono di nuovo i permessi alla prima esecuzione.

## v1.0.0

Prima versione pubblica. Richiede macOS 26 Tahoe o successivo (Universal: Apple Silicon + Intel).

### Aggiunto

#### Launchpad
- Il Launchpad classico torna su macOS 26+, con la familiare disposizione predefinita (le app di sistema meno usate raggruppate in una cartella «Altro»).
- Si apre con il pizzico a quattro dita, dalla barra dei menu o facendo clic su AppPad nel Dock (un altro clic lo chiude). Un clic annulla in qualsiasi momento l’animazione del pizzico.
- Cambio pagina con lo scorrimento a due dita; indicatore di pagina a punti o numeri, toccabile e trascinabile con una lente Liquid Glass.
- Ricerca istantanea, proprio come Launchpad su macOS 15; risultati ordinati in base a quanto spesso e quanto di recente usi ogni app.
- Modalità modifica tenendo premuta l’icona di un’app o il tasto ⌥ Option: trascina per riordinare, rilascia le app una sull’altra per creare cartelle. Le cartelle possono estendersi su più pagine.
- Disinstallazione pulita integrata: elimina un’app dalla modalità modifica e AppPad rimuove anche i suoi file residui.
- La dimensione della finestra segue lo schermo, con percentuali separate per larghezza e altezza; a dimensione piena può coprire la barra dei menu ed evita il notch.
- Si apre sul monitor sotto il puntatore (opzionale) e resta sullo Spazio in cui è stato aperto, come il Launchpad originale.

#### Appunti
- Cronologia degli Appunti per testi e immagini, conservata in modo permanente; le immagini restano anche se il file originale viene eliminato.
- Libreria salvata per gli elementi usati spesso: attiva «Salvati» accanto al campo di ricerca; gli elementi salvati compaiono per primi nella ricerca.
- Si apre con ⌘. (libreria salvata: ⌘⌥.), si incolla con ⌘1–⌘0, riquadro di anteprima sulla destra.
- Icona dell’app di origine su ogni elemento, filtri rapidi per le app più usate e sintassi di ricerca `AppName::`.
- ⌘↩ mostra nel Finder la cartella di origine di un’immagine.
- Pulizia della cronologia per età (ultima ora, giorno, settimana… oltre un anno) senza toccare la libreria salvata.

#### Flussi di lavoro
- Pannello Flussi di lavoro (⌘Space) che esegue Comandi Rapidi di Apple, AppleScript e script shell, e avvia app dalla stessa ricerca.
- Argomenti: digitali dopo il primo spazio, ad es. `Set-Timer 10:00`. Tab completa l’elemento selezionato.
- Flussi integrati: Svuota il Cestino, Imposta timer, Imposta sveglia, Imposta volume, Silenzia, Esci da tutte le app e una calcolatrice con notazione scientifica.
- Sistema di permessi con una vera sandbox per i flussi shell e AppleScript: Consenti una volta / Non consentire / Consenti sempre.
- Importazione di flussi di lavoro da file JSON o link, con ID univoci, revisioni e nomi multilingue.
- Notifiche di successo e di errore per ogni flusso di lavoro.
- App e flussi di lavoro condividono un’unica classifica di utilizzo.

#### Controllo finestre
- ⌃⌥← / ⌃⌥→ aggancia a sinistra / destra, alternando ½ → ⅓ → ⅔.
- ⌃⌥↩ ingrandisce, ⌃⌥⌫ ripristina, ⌃⌥⌘↑ / ⌃⌥⌘↓ sposta sul monitor precedente / successivo.
- Tutte le abbreviazioni sono personalizzabili.

#### Abbreviazioni app
- Abbreviazioni da tastiera globali per aprire qualsiasi app, con un elenco di app dalla A alla Z e rilevamento dei conflitti.

#### Aspetto e generali
- Campo di ricerca, indicatore di pagina e pannelli delle impostazioni in Liquid Glass.
- Tema: Automatico / Chiaro / Scuro.
- Sfondi: bianco, grigio chiaro, grigio scuro, sfondo scrivania o colore personalizzato, ciascuno con trasparenza e sfocatura proprie per i temi chiaro e scuro. I pannelli Appunti e Flussi di lavoro possono seguire lo sfondo di Launchpad.
- ⌘⇧J / ⌘⇧K passa tra Launchpad, Appunti e Flussi di lavoro con una fluida animazione di trasformazione.
- Solo nella barra dei menu (nessuna icona nel Dock, a meno che tu non la fissi), avvio al login.
- Passaggio facoltativo alla sorgente di input ABC all’apertura di ogni pannello.
- Comportamento di Esc configurabile (chiudi subito, oppure cancella prima la ricerca).
- Localizzato in 10 lingue: English, Deutsch, Español, Français, Italiano, 日本語, 한국어, Nederlands, 简体中文, 繁體中文.

#### Distribuzione
- Firmato con Developer ID e autenticato da Apple.
- Installazione con Homebrew: `brew tap umindhub/tap && brew trust umindhub/tap && brew install --cask apppad`.
- Codice sorgente sotto AGPL-3.0. Flussi di lavoro integrati, formato dei flussi di lavoro e flussi di terze parti sotto MIT.
