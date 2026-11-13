# Wijzigingslogboek

<p align="center">
  <a href="../../CHANGELOG.md">English</a> ·
  <a href="CHANGELOG.zh-CN.md">简体中文</a> ·
  <a href="CHANGELOG.zh-TW.md">繁體中文</a> ·
  <a href="CHANGELOG.ja.md">日本語</a> ·
  <a href="CHANGELOG.ko.md">한국어</a> ·
  <a href="CHANGELOG.de.md">Deutsch</a> ·
  <a href="CHANGELOG.es.md">Español</a> ·
  <a href="CHANGELOG.fr.md">Français</a> ·
  <a href="CHANGELOG.it.md">Italiano</a> ·
  Nederlands
</p>

Alle noemenswaardige wijzigingen in AppPad worden in dit bestand bijgehouden.
De opmaak is gebaseerd op [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) en het project volgt [semantisch versiebeheer](https://semver.org/).

> Dit is een vertaling van [CHANGELOG.md](../../CHANGELOG.md). Bij verschillen is de Engelse versie leidend.

> **Licentiewijziging:** AppPad tot en met v1.4.3 is uitgebracht onder AGPL-3.0. Latere versies zijn propriëtaire commerciële software.

## v1.7.1

### Gewijzigd
- Instellingen: De indeling van het instellingenvenster is verfijnd voor een consistentere uitstraling.

## v1.7.0

### Gewijzigd
- OCR: Snellere en soepelere tekstherkenning.

## v1.6.9

### Added

#### Workbench
- Als een workflow-zoekopdracht geen resultaten oplevert, worden nu een app-marktcategorie en de app-marktwebsite aangeboden.

### Changed
- Klembord: De weergave van opgeslagen klemborditems is verbeterd.

### Fixed
- Instellingen: Een probleem met de avatarcache in Account is opgelost.

## v1.6.8

### Toegevoegd

#### Vensters
- Pas het formaat van vensters aan naar het kwart linksboven, linksonder, rechtsboven of rechtsonder van het scherm.

#### Workflows
- Workflows kunnen nu apps beheren: verbergen, openen, afsluiten en de venstergrootte instellen.

## v1.6.7

### Fixed
- Launchpad: Het flikkeren van het Dock bij het verplaatsen van symbolen is verholpen.

## v1.6.6

### Gewijzigd
- Launchpad: De knijpbeweging met vier vingers is verbeterd en werkt nu soepeler en responsiever.

## v1.6.5

### Gewijzigd
- Launchpad: Openen met de knijpbeweging met vier vingers gaat sneller en vloeiender.
- Launchpad: Opent sneller met de bureaubladachtergrond als achtergrond.

### Opgelost
- Launchpad: Kort haperen opgelost bij openen met de knijpbeweging direct na het starten of na het wisselen naar een ander scherm.

## v1.6.4

### Gewijzigd
- Account: Na een netwerkstoring blijft AppPad het enkele uren op de achtergrond opnieuw proberen, zodat je aanmelding en licentie zich vanzelf herstellen.

## v1.6.3

### Gewijzigd
- Account: Je blijft betrouwbaar ingelogd; een kort netwerk- of serverprobleem logt je niet meer uit.

### Opgelost
- Account: AppPad kon je ongemerkt op de achtergrond uitloggen.

## v1.6.2

### Gewijzigd
- Launchpad: Openen met het knijpgebaar met vier vingers verloopt vloeiender, ook na lange tijd niet gebruikt.
- Launchpad: Opent sneller na het wisselen naar een ander beeldscherm.

### Opgelost
- Launchpad: De eerste keer openen na het wisselen tussen lichte en donkere weergave hapert niet meer.

## v1.6.1

### Gewijzigd
- Launchpad: Bladeren tussen pagina’s en openen met het knijpgebaar met vier vingers verlopen vloeiender.

### Opgelost
- Launchpad: De eerste keer naar elke pagina vegen na het openen hapert niet meer.

## v1.6.0

### Gewijzigd
- Klembord: De filters voor tekst, afbeeldingen en bestanden blijven altijd zichtbaar. Typen waarvoor de geselecteerde apps geen items hebben, worden vervaagd weergegeven en zijn nog steeds aanklikbaar (de lijst is dan gewoon leeg).
- Klembord: Bij het selecteren van apps of typen worden de andere niet meer vervaagd; de selectie wordt alleen nog door de markering aangegeven.
- Klembord: ⌘ ingedrukt houden toont geen nummerbadges meer in de lijst; de hints ⌘1–⌘0 blijven zoals voorheen.

### Opgelost
- Klembord: De filterbalk verspringt niet meer bij het wisselen van app.

## v1.5.9

### Gewijzigd
- Workflows: scripts draaien in een strengere sandbox en kunnen niet meer zelf apps, bestanden of links openen of opdrachten uitvoeren. Gebruik een stap ‘Open URL’ voor links en een stap ‘Opdracht’ voor opdrachten.
- Workflows: stappen ‘Open URL’ openen geen bestanden meer en voeren geen opdrachten meer uit; alle andere links werken zoals voorheen.
- Workflows: scripts kunnen geen andere apps bedienen (macOS staat dat niet toe) en vragen daarom niet meer om toegang tot Automatisering.
- Workflows: workflows die door AI-assistenten worden geschreven, volgen deze regels.

### Opgelost
- Workflows: AppleScript-stappen werden niet uitgevoerd, zelfs heel eenvoudige niet.
- Workflows: sommige shellscripts die tekst van meerdere regels schrijven, werden niet uitgevoerd.

### Opmerking
- Als een van je eigen workflows in een script apps of links opent of een opdracht uitvoert, vervang dat deel dan door een stap ‘Open URL’ of ‘Opdracht’.

## v1.5.8

### Gewijzigd
- Back-up: Ingebouwde workflows worden niet meer in back-ups opgenomen en worden bij het herstellen overgeslagen; ze komen altijd met de app mee.

### Opgelost
- Workflows: De ingebouwde workflows voor toevoegen/verwijderen in Claude Desktop verschijnen na een update niet meer dubbel.
- Back-up: Het herstellen van een oudere back-up voegt verouderde ingebouwde workflows niet meer toe als workflows van derden.

### Opmerking
- De aan/uit-status en paneelsnelkoppelingen van ingebouwde workflows worden niet meer uit back-ups hersteld.

## v1.5.7

### Opgelost
- Launchpad: Een map voor het eerst openen na het starten hapert niet meer; mappen openen meteen vloeiend.

## v1.5.6

### Toegevoegd

#### Launchpad
- Houd de linkermuisknop ingedrukt en sleep over een lege plek om te bladeren; indrukken en slepen op het trackpad werkt ook. Mappen en zoekresultaten blader je op dezelfde manier.

### Gewijzigd
- Launchpad: Het muiswiel naar beneden draaien gaat nu naar de volgende pagina, ongeacht de systeeminstelling voor natuurlijk scrollen; de nieuwe schakelaar 'Natuurlijk bladeren met muiswiel' onder 'Snel bladeren' (standaard uit) keert de richting om.
- Instellingen: 'Snel bladeren met trackpad' heet nu 'Snel bladeren' en maakt ook bladeren met het muiswiel sneller: blijf draaien om meerdere pagina's verder te gaan.

### Opgelost
- Launchpad: Muizen met vloeiend scrollen konden niet bladeren met het muiswiel.

## v1.5.5

### Toegevoegd

#### Workflowmarkt
- Installeer workflows uit de Workflowmarkt op youmindhub.com met één klik. Voordat een workflow wordt toegevoegd, laat AppPad zien wat hij doet en om welke rechten hij vraagt.
- Instellingen › Workflows heeft een nieuwe banner die de Workflowmarkt opent, met een link om je eigen workflows te publiceren.

### Gewijzigd
- Workflows: Workflows uit de Workflowmarkt krijgen het label ‘Workflowmarkt’ met hun auteur.
- Workflows: ‘Controleer op workflowupdates’ werkt ook workflows uit de Workflowmarkt bij en meldt het als er een niet meer beschikbaar is.

### Opmerking
- Installatielinks van de oude Workflowmarkt-pagina werken niet meer. Open de workflow opnieuw op youmindhub.com.

## v1.5.4

### Toegevoegd

#### Workflows
- Nieuwe ingebouwde workflow ‘Open Systeeminstellingen’: typ ‘system beeldschermen’ om direct naar dat onderdeel te gaan; zonder onderdeel opent Systeeminstellingen.
- Typ de naam van een onderdeel, zoals ‘beeldscherm’ of ‘wifi’, en passende onderdelen van Systeeminstellingen verschijnen als eigen rijen; druk op Return om te openen.
- Namen werken in alle talen van AppPad, ook onderdelen van Privacy en beveiliging zoals Camera, Microfoon en Schermopname.

## v1.5.3

### Gewijzigd
- Over: De link naar de officiële website verwijst nu naar het nieuwe adres.

## v1.5.2

### Gewijzigd
- Updates: In het venster ‘Up-to-date’ vervaagt het OK-label tijdens het aftellen en is het in elke taal verdwenen voordat de krimpende knop het bereikt.

## v1.5.1

### Gewijzigd
- AI-assistenten: Door AI geschreven scriptworkflows gebruiken nu de standaardshell van de Mac en werken daardoor betrouwbaarder.
- Updates: In het venster ‘Up-to-date’ krimpt het label van de OK-knop tijdens het aftellen nu mee met de knop.

### Opgelost
- AI-assistenten: Scrollen in het controlevenster wanneer AI een workflow bewaart, hapert niet meer.

## v1.5.0

### Gewijzigd
- Instellingen: 'Snel bladeren' is verplaatst van Algemeen naar het tabblad AppPad, in een eigen sectie 'Snel bladeren met trackpad'.

### Opgelost
- Launchpad: apps waarvan de identiteit per versie verandert (bijv. SEGGER J-Link) blijven na een update in hun map in plaats van over de pagina's verspreid te raken.
- Back-up: bij het terugzetten komt ook de herkende tekst van klembordafbeeldingen terug, zodat zoeken nog steeds tekst in afbeeldingen vindt. Afbeeldingen uit oudere back-ups worden direct na het terugzetten herkend.

## v1.4.9

### Gewijzigd
- Klembord: filtersymbolen verschijnen, verdwijnen en verschuiven nu soepel als je erop klikt.
- Welkomstgids: de pagina over app-sneltoetsen gebruikt nu de Finder met ⌃⌘E als voorbeeld.

## v1.4.8

### Toegevoegd

#### Klembord
- Filteren op type: tekst, afbeeldingen of bestanden, met de knoppen naast Bewaard of ⌃1 / ⌃2 / ⌃3.
- Tekst in afbeeldingen wordt op deze Mac herkend, zodat zoeken ook tekst in schermafbeeldingen vindt. De herkende tekst staat onder de afbeeldingsvoorvertoning en kan worden geselecteerd en gekopieerd. Uit te schakelen via Instellingen › Klembord.

### Gewijzigd
- Klembord: met tekst geselecteerd in de voorvertoning kopieert ⌘C alleen de selectie en blijft het paneel open.
- Klembord: afbeeldingen die als JPEG, HEIC, GIF of WebP zijn gekopieerd, worden nu ook bewaard.

### Opgelost
- Klembord: afbeeldingen gekopieerd vanuit WeChat werden niet bewaard.

### Opmerking
- Na de update worden bestaande afbeeldingen geleidelijk op de achtergrond herkend.

## v1.4.7

### Gewijzigd
- Account: De naam van deze Mac is nu standaard het Mac-model (bijv. MacBook Pro 16); dubbelklik om de naam te wijzigen, klik ernaast of druk op Return om te bewaren.
- Account: E-mail en Open ID kunnen nu worden geselecteerd en met de rechtermuisknop worden gekopieerd.

### Opgelost
- Account: Het Account-symbool in de navigatiekolom van Instellingen wordt bij selectie niet langer een volledig blauwe cirkel.
- Account: De knop 'Beheer apparaten…' is nu verticaal uitgelijnd met zijn rij.

## v1.4.6

### Gewijzigd
- Updates: Een gedownloade update start AppPad niet meer opnieuw zolang het aanmeldvenster open is.

### Opgelost
- Updates: AppPad kan nu ook worden bijgewerkt als je bent afgemeld. 'Zoek naar updates…' (⌘U) staat in de menubalk en in het aanmeldvenster, zodat een serverprobleem dat het aanmelden blokkeert toch met een update kan worden opgelost.

## v1.4.5

### Opgelost
- Account: De foutmelding "De openbare licentiesleutel ontbreekt in deze build" na het inloggen is opgelost.

## v1.4.4

### Toegevoegd

#### Account
- Log in met je YouMindHub-account via Instellingen › Account.
- Gratis proefperiode bij de eerste start; daarna aankoop om AppPad te blijven gebruiken.

### Opmerking
- AppPad is nu een betaalde app voor $ 4,99.

## v1.4.3

### Toegevoegd

#### Klembord
- Met ⌥1–8 filter je op de bijbehorende app; met ⌘-klik of ⌘⌥1–8 op meerdere apps tegelijk. Houd ⌥ ingedrukt om de nummers te zien. Er worden maximaal 8 app-filters getoond.

### Opgelost
- Launchpad: Mappen haperen niet meer bij de eerste keer openen na het starten of na lange inactiviteit.

## v1.4.2

### Toegevoegd

#### Instellingen
- Nieuw tabblad Doneren boven Over: steun AppPad door de WeChat-QR-code te scannen, of geef een ster op GitHub.

## v1.4.1

### Toegevoegd

#### Workflows
- Als niets overeenkomt, biedt het paneel nu aanpasbare rijen: standaard 10, maximaal 15. Kies per rij een categorie en een site, sleep om de volgorde te wijzigen en verwijder met −.
- 14 categorieën (AI, zoeken op het web, winkelen, sociale media, wetenschappelijke literatuur, video, muziek, kaarten en reizen, vertalen, nieuws en meer) met populaire wereldwijde en regionale sites, plus eigen URL’s.
- Elke rij toont het pictogram van de site zelf.

### Gewijzigd
- Workflows: de lijst vervangt de vaste rijen voor zoeken op het web / AI vragen; je eerdere keuzes blijven behouden.

### Opmerking
- Sitepictogrammen worden eenmalig van elke site gedownload en op je Mac in de cache bewaard.

## v1.4.0

### Added

#### Workflows
- Als niets overeenkomt, biedt het paneel de rijen 'Vraag het AI' en 'Zoeken op het web' aan met alles wat je hebt getypt; ↩ of Tab opent de geselecteerde rij (standaard AI eerst).
- Een webadres zoals apple.com typen toont bovenaan een vastgezette rij 'Website openen'.
- Zoeken op het web gebruikt standaard de zoekmachine van de browser (Safari, Chrome, Edge, Brave, Firefox en meer).

#### Instellingen
- Workflows › Als niets overeenkomt: kies de browser, de zoekmachine, de AI (ChatGPT, ChatGPT Search, Google AI Mode, Perplexity, Claude, Grok, Copilot, Le Chat, 秘塔 AI 搜索) of een aangepaste URL, en welke rij eerst komt.

### Note
- Claude, Grok en Copilot vullen de vraag alleen in; verstuur hem zelf op de pagina. Gemini ondersteunt geen links, gebruik in plaats daarvan Google AI Mode.

## v1.3.9

### Changed
- Launchpad: Bij het neerzetten van een symbool wordt niet meer de hele pagina opnieuw opgebouwd, zodat verplaatsen en groeperen soepel blijft.

### Fixed
- Launchpad: Een ander symbool oppakken terwijl het vorige nog animeert, flikkert of blokkeert niet meer.
- Launchpad: Een map gaat nu direct open als je erop klikt meteen nadat je er een app in hebt gezet.
- Launchpad: Symbolen die nog naar hun plek schuiven, kun je aanklikken en slepen waar ze op het scherm staan.

## v1.3.8

### Added

#### Workflows
- Knop Voer uit (⌘S) in het workflowpaneel: voert de geselecteerde workflow uit, houdt het paneel open en toont het resultaat onder ‘Laatste uitvoering’.
- Ingebouwde workflows zijn nu te bekijken (alleen-lezen) in Instellingen.

### Changed
- Workflows: uitvoeren zonder verplicht argument markeert de hint nu met een waarschuwingssymbool en een korte trilling.

### Fixed
- Launchpad: de indeling wordt niet meer gewist wanneer een .pkg-update of herinstallatie lang duurt.

## v1.3.7

### Changed
- Bewaarde clips: Het naamveld loopt nu door tot de datum en de inhoud lijnt uit met de naam; in Wijzig inhoud lijnen titel en naam uit met de tekst.

### Fixed
- Instellingen: Het instellingenvenster komt nu naar voren wanneer het wordt geopend vanuit Launchpad, Workflows, Klembord of de menubalk.
- Bewaarde clips: ⌘Q en Stop AppPad werken nu ook terwijl Wijzig inhoud of een bevestiging open is.

## v1.3.6

### Added

#### Instellingen
- Nieuwe schakelaar 'Toon pijlen om van paneel te wisselen' in Algemeen: toont of verbergt de pijlen ← / → naast de titels van Klembord en Workflows. ⌘⇧K / ⌘⇧J wisselen nog steeds van paneel.
- Nieuwe schakelaar 'Toon sneltoetshints' in Algemeen: toont of verbergt de regel met sneltoetsen onder de titels van Klembord en Workflows. Indien uit, staat de titel op één lijn met het zoekveld.
- Beide staan standaard aan.

## v1.3.5

### Added

#### Launchpad
- Optionele sneltoets om Launchpad te openen (standaard ⌥Spatie, standaard uit): druk nogmaals om te sluiten. Zet hem aan en wijzig hem in Instellingen › AppPad › Openen met sneltoets; als hij aan staat, verschijnt hij ook in het menubalkmenu.

#### Welkomstgids
- Op de knijppagina kun je nu de Launchpad-sneltoets aanzetten en een actieve hoek voor Launchpad kiezen.

### Changed
- Reservekopie: reservekopieën van sneltoetsen bevatten nu ook de Launchpad-sneltoets.

## v1.3.4

### Added

#### Launchpad
- Snel bladeren (Instellingen › Algemeen, standaard uit): een korte veeg met twee vingers slaat al een pagina om, en één veeg kan meerdere pagina's verder gaan. Vegen omhoog/omlaag volgt je vingers op dezelfde manier.
- Met snel bladeren aan kun je de paginapunten ingedrukt houden en slepen om de pagina's vloeiend te scrollen; bij loslaten klikt de dichtstbijzijnde pagina vast. Werkt ook in mappen.

### Changed
- Launchpad: Je kunt het volgende symbool al slepen terwijl het vorige nog naar zijn plek vliegt (bijvoorbeeld in een map), zonder op het einde van de animatie te wachten.

## v1.3.3

### Added

#### Actieve hoeken
- Nieuwe actieve hoeken in Instellingen › AppPad: elke schermhoek kan AppPad, Workflows of het Klembord openen, of een macOS-actie uitvoeren (Mission Control, Programmavensters, Bureaublad, Berichtencentrum, Snelle notitie, schermbeveiliging, beeldscherm in sluimerstand, Vergrendel scherm).
- Houd ⌘, ⌥, ⌃ of ⇧ (of meerdere) ingedrukt terwijl je een actie kiest, zodat die hoek alleen werkt terwijl die toetsen zijn ingedrukt, net als in macOS.

### Note
- Berichtencentrum en Snelle notitie hebben toestemming voor toegankelijkheid nodig.
- Is een hoek ook ingesteld bij de actieve hoeken van macOS, dan worden beide uitgevoerd; AppPad toont dan een waarschuwing met een snelkoppeling naar Systeeminstellingen.

## v1.3.2

### Added

#### Workflows
- Nieuwe ingebouwde actie 'Terminal-opdracht vooraf invullen': opent Terminal in de gekozen map met een opdracht al bij de prompt. Er wordt niets uitgevoerd tot je op Return drukt. `{{input}}` wordt vervangen door het argument.

### Changed
- Workflows: 'Installeer Homebrew' vult de officiële installatieopdracht nu alleen in Terminal in; druk op Return om te beginnen.
- Workflows: voordat een script een andere app bedient, vraagt AppPad eerst macOS om toestemming, zodat de app verschijnt bij Privacy en beveiliging › Automatisering. Wordt toegang geweigerd, dan stopt de workflow met een duidelijke melding.
- AI-assistenten: AI kan workflows schrijven die Terminal-opdrachten vooraf invullen; ook Homebrew installeren via AI vult de opdracht alleen in.

### Note
- Vraagt Terminal bij het sluiten van het venster of een actief proces moet worden beëindigd, voeg dan `zsh` toe aan de genegeerde processen in de instellingen van Terminal (Profielen › Shell › Vraag voor sluiten).

## v1.3.1

### Added

#### Workflows
- Nieuwe ingebouwde workflow ‘Zoeken in App Store’: typ `mas` of `appstore` gevolgd door zoektermen om de resultaten direct in de App Store te openen.

### Fixed
- Workflowpaneel: ⌘1–⌘0 op een workflow met een argument selecteert die nu en vult de naam in, klaar voor het argument, in plaats van niets te doen.

## v1.3.0

### Fixed
- Klembord: in AppPad gekopieerde rekenresultaten tonen nu het AppPad-icoon als bron-app in plaats van een lege plaatshouder.

## v1.2.9

### Added

#### Workflows
- Elke workflow toont zijn herkomst: Ingebouwd (groen), Eigen (blauw, door jou geschreven of door een AI-assistent bewaard) of Derde partij (oranje, met de website waar hij vandaan komt of 'Geïmporteerd bestand').
- Het workflowpaneel markeert rijen van derden met een oranje symbool; de voorvertoning toont de volledige link en wanneer hij is geïmporteerd.
- Toestemmingsvragen tonen de herkomst van de workflow; uitvoerbevestigingen tonen die bij workflows van derden.

### Changed
- Workflows: Als je de stappen of toestemmingen van een ingebouwde workflow of een workflow van derden wijzigt, wordt hij gemarkeerd als 'Bewerkt'; een workflow van derden blijft na bewerken van derden.
- Workflows: Wordt een workflow vervangen door een uit een andere bron, dan vraagt AppPad opnieuw om toestemming.

### Fixed
- Workflows: Geïmporteerde workflows konden ingebouwde vervangen door hun ID te hergebruiken; ze worden nu overgeslagen.
- Reservekopie: Bij herstellen worden ingebouwde workflows niet meer overschreven; alleen de aan/uit-status en de paneelsneltoets worden hersteld.

### Note
- Niet-ingebouwde workflows die vóór deze versie zijn toegevoegd, verschijnen als 'Eigen', omdat hun herkomst niet was vastgelegd.

## v1.2.8

### Added

#### AI-assistenten
- AI-assistenten kunnen apps zoeken, installeren en verwijderen met Homebrew. Alleen apps uit de officiële Homebrew-catalogus die door Apple zijn genotariseerd worden geïnstalleerd (opdrachtregeltools alleen vanuit de app), en elke app wordt na installatie opnieuw gecontroleerd.
- Elke installatie en verwijdering vraagt eerst om je bevestiging. Je kunt dit uitzetten via Instellingen › AI-assistenten; een waarschuwing somt dan de risico’s op.
- Ontbreekt Homebrew, dan biedt AppPad aan Terminal te openen met de officiële installatieopdracht.

#### Workflows
- Nieuwe ingebouwde workflow ‘Installeer Homebrew’.

### Changed
- AI-assistenten: Bevestigingen die de AI start (installeren, verwijderen, workflows bewaren, uitvoeren, rechten) verschijnen nu vooraan zonder de andere vensters van AppPad naar voren te halen.

### Note
- Met Homebrew verwijderde apps worden meteen gewist, niet naar de prullenmand verplaatst.
- Formules en taps van derden worden niet ondersteund. Homebrew wordt alleen gevonden in /opt/homebrew en /usr/local.

## v1.2.7

### Added

#### Menubalk
- 'Zoek naar updates…' heeft nu de toetscombinatie ⌘U.

### Fixed
- Menubalk: Globale toetscombinaties (Workflows, Klembord, app- en venstercombinaties) die je indrukt terwijl het menu open is, sluiten het menu nu direct en worden meteen uitgevoerd, in plaats van te wachten tot het menu dicht is.
- Menubalk: Instellingen openen met ⌘, vanuit het menu terwijl Workflows of Klembord open is, maakt de achtergrond van het paneel niet langer even transparant.

## v1.2.6

### Fixed
- Launchpad: Het aantal rijen of kolommen van het raster wijzigen herschikt niet langer alle pagina’s. Wordt het raster groter, dan halen alleen pagina’s die vol waren symbolen van het begin van de volgende pagina, en pagina’s die niet vol waren blijven ongewijzigd; wordt het kleiner, dan schuiven symbolen die niet meer passen naar het begin van de volgende pagina.

## v1.2.5

### Changed
- Launchpad: Apps die nog uit de App Store worden gedownload, tonen hun symbool nu met 70% dekking, zodat ze beter herkenbaar zijn.

### Fixed
- Launchpad: Na afloop van een App Store-download verscheen kort een leeg, gestippeld vak vóór het app-symbool. Het symbool wisselt nu direct.
- Launchpad: Apps die net met Homebrew zijn geïnstalleerd of naar Apps zijn gesleept, tonen niet meer eerst het algemene app-symbool.

## v1.2.4

### Added

#### AI-assistenten (MCP)
- Claude Desktop met één klik instellen: de knoppen ‘Toevoegen aan Claude Desktop’ en ‘Verwijderen uit Claude Desktop’ tonen de huidige status (Toegevoegd / Niet toegevoegd / Niet geïnstalleerd). Alleen de eigen vermelding van AppPad in claude_desktop_config.json wordt gewijzigd; je andere MCP-servers blijven zoals ze zijn.
- Is AppPad na het toevoegen verplaatst, dan meldt de status dat en werkt ‘Toevoegen aan Claude Desktop’ het pad bij.

#### Workflows
- Nieuwe ingebouwde workflows ‘AppPad toevoegen aan Claude Desktop’ en ‘AppPad verwijderen uit Claude Desktop’. Typ ‘claude’ of ‘mcp’ in het workflowpaneel om ze te vinden.

#### Welkomstgids
- De AI-pagina heeft nu dezelfde knoppen om Claude Desktop toe te voegen of te verwijderen.

### Note
- Start Claude Desktop opnieuw na het toevoegen of verwijderen van AppPad om de wijziging toe te passen.
- Is Claude Desktop niet geïnstalleerd, dan wordt er niets toegevoegd en meldt AppPad dat.
- Vóór elke wijziging wordt een reservekopie van het vorige bestand ernaast bewaard als claude_desktop_config.json.apppad-backup.

## v1.2.3

### Fixed
- Klembord: Bewaarde items worden nu net als de geschiedenis gesorteerd op meest recent gebruik. Een item komt bovenaan na plakken of kopiëren, in plaats van in de volgorde van bewaren te blijven.

## v1.2.2

### Changed
- Workflow-paneel: 'Laatste uitvoering' in het voorbeeld toont nu een statuspictogram in dezelfde stijl als de argumentcontrole, een tint lichter: groen ✓ bij geslaagd, rood ✕ bij mislukt, grijs – bij geannuleerd, met bijpassende tekstkleur, zodat je het laatste resultaat in één oogopslag ziet.
- Workflow-paneel: Een geannuleerde uitvoering wordt niet meer rood weergegeven alsof die mislukt is.

## v1.2.1

### Changed
- Launchpad: Slepen en neerzetten tussen apps en mappen is verbeterd.

### Fixed
- Instellingen: Een probleem opgelost waarbij het instellingenvenster andere vensters overlapte bij het openen.

## v1.2.0

### Changed
- Launchpad: als je op een app klikt, sluit Launchpad nu met dezelfde zoom- en vervaganimatie als bij een klik op een lege plek, in plaats van meteen te verdwijnen.

## v1.1.9

### Toegevoegd
- Launchpad: app-symbolen tonen nu dezelfde rode badges als het Dock (ongelezen aantallen, updates). Mappen tonen het totaal van de badges van hun apps, of een rode stip als de apps erin alleen tekstbadges hebben.
- Instellingen › Algemeen: nieuwe schakelaar ‘Toon app-badges’, standaard aan. Badges worden uit het Dock gelezen en vereisen toestemming voor Toegankelijkheid; zonder die toestemming toont de schakelaar een hint met een knop om Systeeminstellingen te openen.

## v1.1.8

### Gewijzigd
- Weergave: vorm van knoppen en kleur van schakelaars verfijnd.
- Sneltoetsen: prestaties van de sneltoetsenlijst verbeterd.
- Bewaarde clips: de omgang met dubbele klembordonderdelen is gewijzigd.

### Opgelost
- Een probleem bij het instellen van de breedte aan de linkerkant is opgelost.

## v1.1.7

### Gewijzigd
- Weergave: alle schakelaars zijn nu groen en alle knoppen hebben dezelfde pilvorm.
- Verwijderen: de bevestigingspagina voor verwijderen is verfijnd.

## v1.1.6

### Toegevoegd

#### Welkomstgids
- Bij de eerste start opent AppPad nu een welkomstgids in plaats van Launchpad: een korte rondleiding langs de functies, gevolgd door een paar instelstappen. Elke stap kan worden overgeslagen, en Esc of ⌘W sluit de gids.
- Knijpen met vier vingers: zet het aan of uit, bekijk welke macOS-gebaren je in welke volgorde moet uitschakelen en open de trackpadinstellingen met één klik.
- Klembord: zet de geschiedenis aan of uit, bekijk de sneltoetsen en de handigste toetsen (⌘1–⌘0, ⌘S, ⌘↩), en zie hoe een klik op het symbool van een app alleen toont wat uit die app is gekopieerd.
- ⌘Space voor workflows: schakel de sneltoets van Spotlight met één klik uit. De wijziging werkt meteen, zonder af te melden, en kan op dezelfde pagina ongedaan worden gemaakt. Lukt het niet automatisch, dan verwijst de gids naar de toetsenbordinstellingen.
- App-sneltoetsen: probeer het door Safari met één klik ⌃⌘J te geven en voeg er daarna meer toe via Instellingen › App-sneltoetsen.
- AI schrijft workflows: zet AI-assistenten (MCP) aan, kopieer de configuratie voor Claude Code of andere clients en probeer de voorbeeldprompts. Elke workflow die de AI schrijft, heeft nog steeds jouw goedkeuring nodig.
- Toestemmingen en opstarten: geef toestemming voor Toegankelijkheid (nodig voor plakken en vensterbeheer) en zet starten bij inloggen aan, met een live status voor elk.
- De laatste pagina toont de sneltoetsen voor Launchpad, Klembord, bewaarde onderdelen en Workflows; ‘Open AppPad’ gaat direct naar Launchpad.
- Veeg met twee vingers naar links of rechts, of klik of sleep langs de stippen onderaan, om tussen pagina’s te wisselen.
- Open de gids op elk moment opnieuw via Instellingen › Over › Toon welkomstgids….

### Gewijzigd
- De welkomstgids vervangt de losse, eenmalige hints over knijpen en Spotlight. Als je die hints al hebt gezien, opent de gids niet vanzelf.
- Automatische updates wachten tot de welkomstgids is gesloten.

## v1.1.5

### Gewijzigd
- Launchpad: klik op de naam van een map om die op elk moment te wijzigen, niet alleen in de wijzigmodus.

### Opgelost
- Launchpad: de naam van een map schuift niet meer naar links na het wijzigen met ↩.

## v1.1.4

### Opgelost
- Opgelost: pas geïnstalleerde apps (bijv. via Homebrew) konden een leeg symbool tonen totdat AppPad opnieuw werd gestart.

## v1.1.3

### Toegevoegd
- Launchpad: apps die uit de App Store worden gedownload, verschijnen meteen, gedimd met een voortgangsbalk, en worden normaal zodra ze zijn geïnstalleerd.
- Launchpad: bij het verwijderen van een app verschijnt een voortgangsbalk onder het symbool; het symbool verdwijnt zodra het klaar is.

### Gewijzigd
- Verwijderen: app-instellingen en -gegevens in de sandboxcontainers blijven bewaard, net als bij verwijderen via de Finder, zodat ze na opnieuw installeren terugkomen.

### Opgelost
- Verwijderen: App Store-apps en andere apps die eigendom zijn van het systeem kunnen weer worden verwijderd (de Finder vraagt om je wachtwoord of Touch ID). Restanten in `/Library` worden op dezelfde manier verwijderd.
- Verwijderen: widgets en extensies van de app die nog actief zijn, blokkeren het verwijderen niet meer.

## v1.1.2

### Gewijzigd
- Launchpad: een map openen en sluiten door te klikken werkt nu betrouwbaarder.

## v1.1.1

### Gewijzigd
- Updates: de updatemelding telt nu af en sluit zichzelf zodra de tijd om is.

## v1.1.0

### Gewijzigd
- Launchpad: een map openen en sluiten verloopt nu soepeler en reageert sneller, met minder werk per frame tijdens de animatie.

## v1.0.9

### Toegevoegd

#### Launchpad
- Zoeken vindt nu ook mappen op naam, inclusief pinyin en beginletters, net als apps.
- Zoek naar meerdere dingen tegelijk met `|` of `||`; bijv. `WeChat | Social` toont de app en de map samen, zodat je de app direct in de map kunt slepen.

### Gewijzigd
- AppPad ondersteunt nu macOS 15 Sequoia en nieuwer (voorheen macOS 26 Tahoe of nieuwer). Liquid Glass-regelaars blijven beschikbaar op macOS 26 en nieuwer.

## v1.0.8

### Toegevoegd

#### Launchpad
- Bij het verwijderen van een app die met Homebrew (`brew install --cask`) is geïnstalleerd, wordt die nu ook uit Homebrew verwijderd: nadat de app en de restanten in de prullenmand staan, voert AppPad `brew uninstall --cask` uit voor de bijbehorende cask. Zonder Homebrew, of bij apps die geen cask zijn, verandert er niets.
- Als Homebrew het niet zelf kan afronden (bijvoorbeeld wanneer de cask een beheerderswachtwoord nodig heeft), toont AppPad de opdracht die je in Terminal moet uitvoeren, met een knop om die te kopiëren.

#### Workflows
- In het workflowpaneel begint het resultaat van een getypt argument nu met een groen vinkje als het geldig is en met een rood kruis als het dat niet is.

### Gewijzigd
- Bij het wisselen van Launchpad naar het klembord- of workflowpaneel verschijnt de schaduw van het paneel nu geleidelijk tijdens de overgang in plaats van erna.
- Paneelschaduwen worden door AppPad getekend en blijven buiten het paneel. Met een doorschijnende achtergrond zien het klembord- en workflowpaneel er nu precies zo uit als Launchpad, met dezelfde vervaging en transparantie en zonder extra verduistering.
- Workflowpaneel: een geldig argumentresultaat wordt in de normale tekstkleur getoond in plaats van groen; een ongeldig resultaat blijft rood.
- Als je in het menubalkmenu Launchpad, Klembord of Workflows kiest terwijl een ander paneel open is, wordt nu op dezelfde manier gewisseld als met ⌘⇧J / ⌘⇧K.

### Opgelost
- Wisselen tussen het klembord- en workflowpaneel met ⌘⇧J / ⌘⇧K kon even flikkeren.
- Een paneel openen via de menubalk terwijl een ander open was, toonde kort het bureaublad.

## v1.0.7

### Toegevoegd

#### AI-assistenten (MCP)
- Claude, Cursor en andere MCP-clients kunnen je workflows weergeven en uitvoeren, met een argument net als in het workflowpaneel. De resultaten gaan terug naar de AI in plaats van als meldingen te verschijnen.
- AI-assistenten kunnen ook workflows voor je schrijven. Elke nieuwe of gewijzigde workflow wordt volledig getoond, inclusief scripts, en pas bewaard nadat je op Installeer klikt.
- Uitvoeringen gebruiken dezelfde bevestigingen en toestemmingsvragen als het workflowpaneel. Uitgeschakelde workflows blijven verborgen.
- Nieuw tabblad AI-assistenten (MCP) in Instellingen, onder Workflows: standaard aan, toont de verbindingsstatus en bevat kant-en-klare configuraties om te kopiëren voor Claude Desktop, Cursor en Claude Code.
- Als AppPad niet actief is, start de AI-client het op de achtergrond zonder Launchpad te openen.

## v1.0.6

### Toegevoegd

#### Launchpad
- Zoeken behoudt mappen: een app in een map verschijnt nu als die map. Open de map met een klik of ↩; de overeenkomende app wordt gemarkeerd en nogmaals ↩ opent hem.
- Zoekresultaten kunnen worden gesleept: sleep een app uit het paneel naar het Dock of naar de Finder.
- Mappen maken tijdens het zoeken: laat een app langzaam op een ander resultaat vallen om een nieuwe map te maken, of op een map om hem toe te voegen. Apps die uit een vanuit de resultaten geopende map worden gesleept, kunnen op dezelfde manier worden neergezet. Houd de app aan de rand van het paneel om naar de volgende of vorige resultatenpagina te bladeren.

### Gewijzigd
- Als er in een map nog maar één app over is, groeit die app nu langzaam uit de map in plaats van plotseling te verschijnen.
- Tijdens het zoeken blijven de geopende map, de resultatenpagina en de selectie behouden wanneer de indeling verandert (ordenen binnen een map, naam wijzigen, verwijderen), en houden de resultaten na een samenvoeging hun volgorde in plaats van opnieuw te worden gerangschikt.

### Opgelost
- Klikken tijdens een neerzetanimatie (bijvoorbeeld op een map die nog wordt gevormd) kon Launchpad sluiten.

## v1.0.5

### Toegevoegd

#### Automatische updates
- AppPad houdt zichzelf nu up-to-date. Elke dag om 4:00 controleert het op een nieuwe versie, downloadt die op de achtergrond en installeert hem zodra er geen paneel open is; daarna start het onopvallend opnieuw zonder Launchpad te openen.
- Controle gemist omdat de Mac in de sluimerstand stond of uit was? AppPad haalt die kort na het ontwaken in en probeert het elke 30 minuten opnieuw als het netwerk nog niet klaar is.
- Nieuw gedeelte Updates in Instellingen › Over: zet automatische updates aan of uit (standaard aan), kies het tijdstip van de controle, bekijk wanneer de laatste controle was en controleer nu.
- ‘Zoek naar updates…’ in het menubalkmenu.
- Staat er een update klaar terwijl je in Instellingen bent, dan installeert ‘Herstart om bij te werken’ hem meteen.
- Updates worden vóór installatie gecontroleerd met een EdDSA-handtekening.

### Gewijzigd
- Instellingen › Over vermeldt Sparkle bij de dankbetuigingen.

### Opmerking
- Versies vóór 1.0.5 kunnen zichzelf niet bijwerken: installeer 1.0.5 eenmalig vanaf de DMG of met `brew upgrade --cask apppad`; latere versies komen daarna automatisch.

## v1.0.4

### Toegevoegd
- Bewaarde clips: van tekstonderdelen kan nu naast de naam ook de inhoud worden gewijzigd. Klik op de tekst om de editor te openen; ⌘↩ bewaart, Esc annuleert. Een wijziging die een ander onderdeel zou dupliceren, wordt geweigerd.

### Gewijzigd
- Bewaarde clips: de knop Kopieer verandert na een geslaagde kopie kort in een groen vinkje; de rij behoudt zijn hoogte.

### Opgelost
- Bewaarde clips: het kopiëren van een onderdeel verandert de bron-app niet meer in AppPad. Kopiëren telt nu als gebruik, net als plakken vanuit het klembordpaneel, en verplaatst het onderdeel naar de bovenkant van de geschiedenis.

## v1.0.3

### Toegevoegd

#### Klembord
- Nieuw tabblad ‘Bewaarde clips’ in Instellingen om de bewaarde bibliotheek te bekijken, te doorzoeken en te beheren: symbool van de bron-app, naam, voorvertoning van twee regels en datum voor elk onderdeel, met de knoppen Kopieer en Verwijder.
- Bewaarde onderdelen kunnen een naam krijgen. Namen zijn doorzoekbaar in Instellingen en in het klembordpaneel, en onderdelen met een naam tonen die naam vetgedrukt in de lijst.
- ⌘↩ op een willekeurig klembordonderdeel opent het in Instellingen › Bewaarde clips, met het naamveld klaar om te typen; niet-bewaarde onderdelen worden eerst bewaard. Ook beschikbaar via het contextmenu (‘Wijzig in Bewaarde clips’).

#### Reservekopie en herstel
- Reservekopieën bevatten nu de namen van onderdelen. Oudere reservekopieën worden hersteld zoals voorheen; bij samenvoegen blijft een naam die al op deze Mac is ingesteld behouden.

### Gewijzigd
- Klembord: verwijder een onderdeel met ⌘⇧⌫ (was ⌘⌫), zodat ⌘⌫ in het zoekveld weer tot het begin van de regel wist.
- Klembord: ‘Toon in Finder’ is verplaatst van ⌘↩ naar ⌘⇧↩.

## v1.0.2

### Toegevoegd

#### Workflows
- Nieuwe optie ‘Vraag voor uitvoeren’ in de workfloweditor: er verschijnt een bevestiging voordat de workflow wordt uitgevoerd, of hij nu vanuit het workflowpaneel of vanuit Instellingen wordt gestart.
- In het workflowpaneel opent de bevestiging binnen het paneel: ↩ voert uit, Esc annuleert, andere toetsen worden genegeerd. Een ingehouden of snel herhaalde ↩ bevestigt nooit.
- Het workflowformaat krijgt een optioneel veld `"confirm": true`; bestaande bestanden zonder dit veld werken zoals voorheen.

### Gewijzigd
- De ingebouwde workflow ‘Stop alle apps’ (v1.4) vraagt nu om bevestiging, zodat Tab of ↩ in het workflowpaneel niet meer per ongeluk alle apps kan stoppen.

## v1.0.1

### Toegevoegd

#### Reservekopie en herstel
- Nieuw tabblad Reservekopie in Instellingen: exporteer naar één `.apppadbackup`-bestand en herstel het op deze of een andere Mac.
- Kies wat je meeneemt: app-sneltoetsen (plus de sneltoetsen voor Workflows, Klembord en vensters), de Launchpad-indeling met rastergrootte, geïnstalleerde workflows (met symbolen, paneelsneltoetsen en aan/uit-status), de klembordgeschiedenis en de bewaarde bibliotheek.
- Herstellen toont wat een reservekopie bevat voordat er iets verandert; kies welke delen je herstelt en of je ze samenvoegt met wat er al is of dat vervangt.
- Samenvoegen voegt toe wat ontbreekt: nieuwere workflowversies vervangen oudere, en klembordonderdelen worden op inhoud vergeleken, zodat niets dubbel voorkomt.
- De Launchpad-indeling wordt altijd vervangen; apps die niet op deze Mac zijn geïnstalleerd, worden overgeslagen en apps die niet in de reservekopie staan, worden achteraan toegevoegd.
- Sleutelhangergeheimen en ‘Sta altijd toe’-toestemmingen worden nooit in een reservekopie opgeslagen; herstelde workflows vragen bij hun eerste uitvoering opnieuw om toestemming.

## v1.0.0

Eerste openbare release. Vereist macOS 26 Tahoe of nieuwer (Universal: Apple silicon + Intel).

### Toegevoegd

#### Launchpad
- Het klassieke Launchpad is terug op macOS 26+, met de vertrouwde standaardindeling (minder gebruikte systeemapps gegroepeerd in een map ‘Overige’).
- Openen door met vier vingers te knijpen, via de menubalk of door op AppPad in het Dock te klikken (nogmaals klikken sluit). Een klik annuleert de knijpanimatie op elk moment.
- Bladeren met twee vingers vegen; pagina-indicator als stippen of cijfers, aan te tikken en te doorlopen door te slepen met een Liquid Glass-lens.
- Direct zoeken, net als Launchpad op macOS 15; resultaten gerangschikt op hoe vaak en hoe recent je elke app gebruikt.
- Wijzigmodus door een app-symbool lang ingedrukt te houden of ⌥ Option ingedrukt te houden: sleep om te ordenen, laat apps op elkaar vallen om mappen te maken. Mappen kunnen meerdere pagina’s beslaan.
- Ingebouwde schone verwijdering: verwijder een app vanuit de wijzigmodus en AppPad verwijdert ook de achtergebleven bestanden.
- De venstergrootte volgt het scherm met aparte percentages voor breedte en hoogte; op volledige grootte kan het de menubalk bedekken en blijft het uit de buurt van de inkeping.
- Opent op het scherm onder de muisaanwijzer (optioneel) en blijft op de Space waar het is geopend, net als het originele Launchpad.

#### Klembord
- Klembordgeschiedenis voor tekst en afbeeldingen, permanent bewaard; afbeeldingen blijven behouden, zelfs als het originele bestand is verwijderd.
- Bewaarde bibliotheek voor veelgebruikte onderdelen — schakel ‘Bewaard’ naast het zoekveld in; bewaarde onderdelen staan bovenaan in de zoekresultaten.
- Openen met ⌘. (bewaarde bibliotheek: ⌘⌥.), plakken met ⌘1–⌘0, voorvertoningspaneel rechts.
- Symbool van de bron-app bij elk onderdeel, filterchips voor je meestgebruikte apps en zoeksyntaxis `AppName::`.
- ⌘↩ toont de bronmap van een afbeelding in de Finder.
- Geschiedenis opschonen op ouderdom (afgelopen uur, dag, week … meer dan een jaar) zonder de bewaarde bibliotheek aan te raken.

#### Workflows
- Workflowpaneel (⌘Space) dat Apple Opdrachten, AppleScript en shellscripts uitvoert en apps start vanuit dezelfde zoekopdracht.
- Argumenten: typ ze na de eerste spatie, bijv. `Set-Timer 10:00`. Tab vult het geselecteerde onderdeel aan.
- Ingebouwde workflows: Leeg prullenmand, Stel timer in, Stel wekker in, Stel volume in, Geluid uit, Stop alle apps, en een rekenmachine met wetenschappelijke notatie.
- Toestemmingssysteem met een echte sandbox voor shell- en AppleScript-workflows: Sta eenmaal toe / Sta niet toe / Sta altijd toe.
- Workflows importeren uit JSON-bestanden of links, met unieke id’s, revisies en meertalige namen.
- Meldingen bij succes en mislukking per workflow.
- Apps en workflows delen één gebruiksrangschikking.

#### Vensterbeheer
- ⌃⌥← / ⌃⌥→ zet links / rechts vast, wisselend tussen ½ → ⅓ → ⅔.
- ⌃⌥↩ maximaliseert, ⌃⌥⌫ herstelt, ⌃⌥⌘↑ / ⌃⌥⌘↓ verplaatst naar het vorige / volgende scherm.
- Alle sneltoetsen zijn aanpasbaar.

#### App-sneltoetsen
- Globale sneltoetsen om elke app te openen, met een app-lijst van A tot Z en conflictdetectie.

#### Weergave en algemeen
- Liquid Glass-zoekveld, pagina-indicator en instellingentabbladen.
- Thema: Automatisch / Licht / Donker.
- Achtergronden: wit, lichtgrijs, donkergrijs, bureaubladachtergrond of aangepaste kleur, elk met eigen transparantie en vervaging voor het lichte en donkere thema. Het klembord- en workflowpaneel kunnen de Launchpad-achtergrond volgen.
- ⌘⇧J / ⌘⇧K wisselt met een vloeiende overgangsanimatie tussen Launchpad, Klembord en Workflows.
- Alleen in de menubalk (geen Dock-symbool, tenzij je het vastzet), starten bij inloggen.
- Optioneel overschakelen naar de invoerbron ABC wanneer een paneel opent.
- Instelbaar gedrag van Esc (meteen sluiten, of eerst de zoekopdracht wissen).
- Gelokaliseerd in 10 talen: English, Deutsch, Español, Français, Italiano, 日本語, 한국어, Nederlands, 简体中文, 繁體中文.

#### Distributie
- Ondertekend met Developer ID en genotariseerd door Apple.
- Installeren met Homebrew: `brew tap umindhub/tap && brew trust umindhub/tap && brew install --cask apppad`.
- Broncode onder AGPL-3.0. Ingebouwde workflows, het workflowformaat en workflows van derden onder MIT.
