# Änderungsprotokoll

<p align="center">
  <a href="../../CHANGELOG.md">English</a> ·
  <a href="CHANGELOG.zh-CN.md">简体中文</a> ·
  <a href="CHANGELOG.zh-TW.md">繁體中文</a> ·
  <a href="CHANGELOG.ja.md">日本語</a> ·
  <a href="CHANGELOG.ko.md">한국어</a> ·
  Deutsch ·
  <a href="CHANGELOG.es.md">Español</a> ·
  <a href="CHANGELOG.fr.md">Français</a> ·
  <a href="CHANGELOG.it.md">Italiano</a> ·
  <a href="CHANGELOG.nl.md">Nederlands</a>
</p>

Alle wichtigen Änderungen an AppPad werden in dieser Datei dokumentiert.
Das Format basiert auf [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), und das Projekt folgt der [semantischen Versionierung](https://semver.org/).

> Dies ist eine Übersetzung von [CHANGELOG.md](../../CHANGELOG.md). Bei Abweichungen gilt die englische Fassung.

## v1.2.0

### Changed
- Launchpad: Beim Klick auf eine App schließt sich Launchpad jetzt mit derselben Zoom- und Ausblendanimation wie beim Klick auf eine leere Stelle, statt sofort zu verschwinden.

## v1.1.9

### Hinzugefügt
- Launchpad: App-Symbole zeigen jetzt dieselben roten Kennzeichen wie das Dock (ungelesene Anzahl, Updates). Ordner zeigen die Summe der Kennzeichen ihrer Apps oder einen roten Punkt, wenn die Apps darin nur Text-Kennzeichen haben.
- Einstellungen › Allgemein: neuer Schalter „App-Kennzeichen anzeigen“, standardmäßig aktiviert. Die Kennzeichen werden aus dem Dock gelesen und benötigen die Berechtigung für Bedienungshilfen; ohne sie zeigt der Schalter einen Hinweis mit einer Taste, die die Systemeinstellungen öffnet.

## v1.1.8

### Geändert
- Erscheinungsbild: Tastenformen und Schalterfarben überarbeitet.
- Kurzbefehle: Leistung der Kurzbefehlliste verbessert.
- Gesicherte Clips: Umgang mit doppelten Einträgen der Zwischenablage geändert.

### Behoben
- Ein Problem beim Einstellen der Breite der linken Seite wurde behoben.

## v1.1.7

### Geändert
- Erscheinungsbild: Alle Schalter sind jetzt grün, und alle Tasten haben dieselbe Pillenform.
- Deinstallation: Bestätigungsseite zum Löschen überarbeitet.

## v1.1.6

### Hinzugefügt

#### Willkommensanleitung
- Beim ersten Start öffnet AppPad jetzt eine Willkommensanleitung statt des Launchpads: eine kurze Tour durch die Funktionen, gefolgt von einigen Einrichtungsschritten. Jeder Schritt kann übersprungen werden, und Esc oder ⌘W schließt die Anleitung.
- Vier-Finger-Zusammenziehen: ein- oder ausschalten, sehen, welche macOS-Gesten in welcher Reihenfolge deaktiviert werden müssen, und die Trackpad-Einstellungen mit einem Klick öffnen.
- Zwischenablage: Verlauf ein- oder ausschalten, die Kurzbefehle und die nützlichsten Tasten (⌘1–⌘0, ⌘S, ⌘↩) sehen und erfahren, wie ein Klick auf ein App-Symbol nur das zeigt, was aus dieser App kopiert wurde.
- ⌘Space für Workflows: den Spotlight-Kurzbefehl mit einem Klick deaktivieren. Die Änderung wirkt sofort, ohne Abmelden, und lässt sich auf derselben Seite rückgängig machen. Kann sie nicht automatisch vorgenommen werden, verweist die Anleitung auf die Tastatureinstellungen.
- App-Kurzbefehle: mit einem Klick Safari den Kurzbefehl ⌃⌘J zuweisen und ausprobieren, weitere dann unter Einstellungen › App-Kurzbefehle hinzufügen.
- KI schreibt Workflows: KI-Assistenten (MCP) aktivieren, die Einrichtung für Claude Code oder andere Clients kopieren und Beispiel-Prompts ausprobieren. Jeder von der KI geschriebene Workflow braucht weiterhin deine Zustimmung.
- Berechtigungen und Start: Bedienungshilfen erlauben (nötig zum Einsetzen und für die Fenstersteuerung) und „Beim Anmelden starten“ aktivieren, jeweils mit Live-Status.
- Die letzte Seite listet die Kurzbefehle für Launchpad, Zwischenablage, gesicherte Einträge und Workflows; „AppPad öffnen“ führt direkt zum Launchpad.
- Mit zwei Fingern nach links oder rechts streichen oder auf die Punkte unten klicken bzw. daran entlangziehen, um zwischen den Seiten zu wechseln.
- Die Anleitung lässt sich jederzeit über Einstellungen › Über › Willkommensanleitung anzeigen … erneut öffnen.

### Geändert
- Die Willkommensanleitung ersetzt die bisherigen einmaligen Hinweise zum Zusammenziehen und zu Spotlight. Wenn du diese Hinweise bereits gesehen hast, öffnet sich die Anleitung nicht von selbst.
- Automatische Updates warten, bis die Willkommensanleitung geschlossen ist.

## v1.1.5

### Geändert
- Launchpad: Klicke jederzeit auf den Namen eines Ordners, um ihn umzubenennen – nicht nur im Bearbeitungsmodus.

### Behoben
- Launchpad: Der Name eines Ordners verschiebt sich nach dem Umbenennen mit ↩ nicht mehr nach links.

## v1.1.4

### Behoben
- Behoben: Neu installierte Apps (z. B. über Homebrew) konnten ein leeres Symbol anzeigen, bis AppPad neu gestartet wurde.

## v1.1.3

### Hinzugefügt
- Launchpad: Apps, die gerade aus dem App Store geladen werden, erscheinen sofort – abgedunkelt mit Fortschrittsbalken – und werden nach der Installation normal angezeigt.
- Launchpad: Beim Löschen einer App erscheint ein Fortschrittsbalken unter ihrem Symbol; das Symbol verschwindet, sobald der Vorgang abgeschlossen ist.

### Geändert
- Deinstallation: App-Einstellungen und -Daten in den Sandbox-Containern bleiben erhalten, wie beim Löschen im Finder, sodass eine erneute Installation sie wiederherstellt.

### Behoben
- Deinstallation: Apps aus dem App Store und andere Apps im Besitz des Systems können wieder gelöscht werden (der Finder fragt nach deinem Passwort oder Touch ID). Restdateien in `/Library` werden auf dieselbe Weise entfernt.
- Deinstallation: Noch laufende Widgets und Erweiterungen der App verhindern das Löschen nicht mehr.

## v1.1.2

### Geändert
- Launchpad: Das Öffnen und Schließen eines Ordners per Klick ist jetzt zuverlässiger.

## v1.1.1

### Geändert
- Updates: Die Update-Meldung zählt jetzt herunter und schließt sich von selbst, wenn die Zeit abgelaufen ist.

## v1.1.0

### Geändert
- Launchpad: Das Öffnen und Schließen eines Ordners ist jetzt flüssiger und reagiert schneller, da während der Animation pro Bild weniger Arbeit anfällt.

## v1.0.9

### Hinzugefügt

#### Launchpad
- Die Suche findet jetzt auch Ordner nach Namen, einschließlich Pinyin und Anfangsbuchstaben, genau wie Apps.
- Mit `|` oder `||` nach mehreren Dingen gleichzeitig suchen, z. B. zeigt `WeChat | Social` die App und den Ordner zusammen an, sodass du die App direkt in den Ordner ziehen kannst.

### Geändert
- AppPad unterstützt jetzt macOS 15 Sequoia und neuer (bisher macOS 26 Tahoe oder neuer). Liquid-Glass-Steuerelemente sind weiterhin ab macOS 26 verfügbar.

## v1.0.8

### Hinzugefügt

#### Launchpad
- Beim Deinstallieren einer mit Homebrew (`brew install --cask`) installierten App wird sie jetzt auch aus Homebrew entfernt: Nachdem die App und ihre Restdateien im Papierkorb liegen, führt AppPad `brew uninstall --cask` für ihren Cask aus. Ohne Homebrew oder bei Apps, die kein Cask sind, ändert sich nichts.
- Kann Homebrew den Vorgang nicht selbst abschließen (z. B. wenn der Cask ein Administratorpasswort benötigt), zeigt AppPad den im Terminal auszuführenden Befehl samt Taste zum Kopieren an.

#### Workflows
- Im Workflow-Panel beginnt das Ergebnis eines eingegebenen Arguments jetzt mit einem grünen Häkchen, wenn es gültig ist, und mit einem roten Kreuz, wenn nicht.

### Geändert
- Beim Wechsel vom Launchpad zum Zwischenablage- oder Workflow-Panel wird der Schatten des Panels jetzt während der Überblendung eingeblendet statt erst danach.
- Panel-Schatten werden von AppPad gezeichnet und bleiben außerhalb des Panels. Mit transparentem Hintergrund sehen das Zwischenablage- und das Workflow-Panel jetzt genau wie das Launchpad aus – mit derselben Unschärfe und Transparenz und ohne zusätzliche Abdunklung.
- Workflow-Panel: Ein gültiges Argument-Ergebnis wird in der normalen Textfarbe statt in Grün angezeigt; ein ungültiges bleibt rot.
- Wird im Menüleistenmenü Launchpad, Zwischenablage oder Workflows gewählt, während ein anderes Panel geöffnet ist, erfolgt der Wechsel jetzt genauso wie mit ⌘⇧J / ⌘⇧K.

### Behoben
- Beim Wechsel zwischen Zwischenablage- und Workflow-Panel mit ⌘⇧J / ⌘⇧K konnte es kurz flackern.
- Beim Öffnen eines Panels über die Menüleiste, während ein anderes geöffnet war, war kurz der Schreibtisch zu sehen.

## v1.0.7

### Hinzugefügt

#### KI-Assistenten (MCP)
- Claude, Cursor und andere MCP-Clients können deine Workflows auflisten und ausführen und dabei wie im Workflow-Panel ein Argument übergeben. Die Ergebnisse gehen an die KI statt als Mitteilungen.
- KI-Assistenten können auch Workflows für dich schreiben. Jeder neue oder geänderte Workflow wird vollständig angezeigt, einschließlich der Skripte, und erst gespeichert, nachdem du auf „Installieren“ klickst.
- Ausführungen nutzen dieselben Bestätigungen und Berechtigungsabfragen wie das Workflow-Panel. Deaktivierte Workflows bleiben verborgen.
- Neuer Tab „KI-Assistenten (MCP)“ in den Einstellungen, unterhalb von „Workflows“: standardmäßig aktiviert, zeigt den Verbindungsstatus und bietet sofort kopierbare Einrichtungen für Claude Desktop, Cursor und Claude Code.
- Läuft AppPad nicht, startet der KI-Client es im Hintergrund, ohne das Launchpad zu öffnen.

## v1.0.6

### Hinzugefügt

#### Launchpad
- Die Suche behält Ordner bei: Eine App in einem Ordner wird jetzt als ihr Ordner angezeigt. Öffne ihn per Klick oder ↩; die passende App wird hervorgehoben, und ein weiteres ↩ öffnet sie.
- Suchergebnisse lassen sich ziehen: Ziehe eine App aus dem Panel ins Dock oder in den Finder.
- Ordner beim Suchen erstellen: Lege eine App langsam auf ein anderes Ergebnis, um einen neuen Ordner zu erstellen, oder auf einen Ordner, um sie hinzuzufügen. Apps, die aus einem in den Ergebnissen geöffneten Ordner gezogen werden, lassen sich genauso ablegen. Halte am Rand des Panels inne, um zur nächsten oder vorherigen Ergebnisseite zu blättern.

### Geändert
- Bleibt in einem Ordner nur eine App übrig, wächst diese App jetzt langsam aus dem Ordner heraus, statt plötzlich zu erscheinen.
- Beim Suchen bleiben der geöffnete Ordner, die Ergebnisseite und die Auswahl erhalten, wenn sich die Anordnung ändert (Umsortieren in einem Ordner, Umbenennen, Deinstallieren), und die Ergebnisse behalten nach dem Zusammenführen ihre Reihenfolge, statt neu sortiert zu werden.

### Behoben
- Ein Klick während einer Ablegeanimation (z. B. auf einen Ordner, der noch entsteht) konnte das Launchpad schließen.

## v1.0.5

### Hinzugefügt

#### Automatische Updates
- AppPad hält sich jetzt selbst auf dem neuesten Stand. Jeden Tag um 4:00 Uhr sucht es nach einer neuen Version, lädt sie im Hintergrund und installiert sie, sobald kein Panel geöffnet ist; danach startet es unauffällig neu, ohne das Launchpad zu öffnen.
- Prüfung verpasst, weil der Mac im Ruhezustand oder ausgeschaltet war? AppPad holt sie kurz nach dem Aufwachen nach und versucht es alle 30 Minuten erneut, falls das Netzwerk noch nicht bereit ist.
- Neuer Bereich „Updates“ unter Einstellungen › Über: automatische Updates ein- oder ausschalten (standardmäßig ein), Prüfzeit wählen, letzte Prüfung sehen und jetzt prüfen.
- „Nach Updates suchen …“ im Menüleistenmenü.
- Wartet ein Update, während du in den Einstellungen bist, installiert „Neu starten und aktualisieren“ es sofort.
- Updates werden vor der Installation mit einer EdDSA-Signatur überprüft.

### Geändert
- Einstellungen › Über führt Sparkle unter den Danksagungen auf.

### Hinweis
- Versionen vor 1.0.5 können sich nicht selbst aktualisieren: Installiere 1.0.5 einmalig aus der DMG oder mit `brew upgrade --cask apppad`; spätere Versionen kommen dann automatisch.

## v1.0.4

### Hinzugefügt
- Gesicherte Clips: Bei Texteinträgen lässt sich jetzt neben dem Namen auch der Inhalt bearbeiten. Klicke auf den Text, um den Editor zu öffnen; ⌘↩ sichert, Esc bricht ab. Eine Bearbeitung, die einen anderen Eintrag duplizieren würde, wird abgelehnt.

### Geändert
- Gesicherte Clips: Die Taste „Kopieren“ wird nach erfolgreichem Kopieren kurz zu einem grünen Häkchen; die Zeilenhöhe bleibt gleich.

### Behoben
- Gesicherte Clips: Das Kopieren eines Eintrags ändert dessen Quell-App nicht mehr auf AppPad. Das Kopieren zählt jetzt als Nutzung, wie das Einsetzen aus dem Zwischenablage-Panel, und verschiebt den Eintrag an den Anfang des Verlaufs.

## v1.0.3

### Hinzugefügt

#### Zwischenablage
- Neuer Tab „Gesicherte Clips“ in den Einstellungen zum Durchsuchen und Verwalten der gesicherten Sammlung: Symbol der Quell-App, Name, zweizeilige Vorschau und Datum für jeden Eintrag, mit den Tasten „Kopieren“ und „Entfernen“.
- Gesicherte Einträge können einen Namen haben. Namen sind sowohl in den Einstellungen als auch im Zwischenablage-Panel durchsuchbar, und benannte Einträge zeigen ihren Namen in der Liste fett an.
- ⌘↩ auf einem beliebigen Eintrag der Zwischenablage öffnet ihn unter Einstellungen › Gesicherte Clips, mit dem Namensfeld bereit zur Eingabe; nicht gesicherte Einträge werden zuerst gesichert. Auch über das Kontextmenü verfügbar („In Gesicherte Clips bearbeiten“).

#### Backup & Wiederherstellung
- Backups enthalten jetzt die Namen der Einträge. Ältere Backups werden wie bisher wiederhergestellt; beim Zusammenführen bleibt ein auf diesem Mac bereits vergebener Name erhalten.

### Geändert
- Zwischenablage: Einträge werden mit ⌘⇧⌫ gelöscht (bisher ⌘⌫), sodass ⌘⌫ im Suchfeld wieder bis zum Zeilenanfang löscht.
- Zwischenablage: „Im Finder anzeigen“ wurde von ⌘↩ auf ⌘⇧↩ verlegt.

## v1.0.2

### Hinzugefügt

#### Workflows
- Neue Option „Vor dem Ausführen fragen“ im Workflow-Editor: Vor dem Ausführen erscheint eine Bestätigung, egal ob der Workflow im Workflow-Panel oder in den Einstellungen gestartet wird.
- Im Workflow-Panel öffnet sich die Bestätigung innerhalb des Panels: ↩ führt aus, Esc bricht ab, andere Tasten werden ignoriert. Ein gehaltenes oder schnell wiederholtes ↩ bestätigt nie.
- Das Workflow-Format erhält ein optionales Feld `"confirm": true`; bestehende Dateien ohne dieses Feld laufen wie bisher.

### Geändert
- Der integrierte Workflow „Alle Apps beenden“ (v1.4) fragt jetzt nach einer Bestätigung, sodass Tab oder ↩ im Workflow-Panel nicht mehr versehentlich alle Apps beenden können.

## v1.0.1

### Hinzugefügt

#### Backup & Wiederherstellung
- Neuer Tab „Backup“ in den Einstellungen: in eine einzelne `.apppadbackup`-Datei exportieren und auf diesem oder einem anderen Mac wiederherstellen.
- Auswählen, was enthalten sein soll: App-Kurzbefehle (plus die Kurzbefehle für Workflows, Zwischenablage und Fenster), die Launchpad-Anordnung mit Rastergröße, installierte Workflows (mit Symbolen, Panel-Kurzbefehlen und Ein/Aus-Status), Verlauf der Zwischenablage und die gesicherte Sammlung.
- Die Wiederherstellung zeigt den Inhalt eines Backups, bevor etwas geändert wird; wähle die wiederherzustellenden Teile und ob mit dem Vorhandenen zusammengeführt oder es ersetzt werden soll.
- Beim Zusammenführen wird Fehlendes ergänzt: Neuere Workflow-Versionen ersetzen ältere, und Einträge der Zwischenablage werden nach Inhalt abgeglichen, sodass nichts doppelt vorkommt.
- Die Launchpad-Anordnung wird immer ersetzt; auf diesem Mac nicht installierte Apps werden übersprungen, und Apps, die nicht im Backup sind, werden am Ende hinzugefügt.
- Schlüsselbund-Geheimnisse und „Immer erlauben“-Berechtigungen werden nie in ein Backup geschrieben; wiederhergestellte Workflows fragen bei der ersten Ausführung erneut nach Berechtigungen.

## v1.0.0

Erste öffentliche Version. Erfordert macOS 26 Tahoe oder neuer (Universal: Apple Silicon + Intel).

### Hinzugefügt

#### Launchpad
- Das klassische Launchpad ist zurück auf macOS 26+, mit der vertrauten Standardanordnung (weniger genutzte System-Apps im Ordner „Andere“ gruppiert).
- Öffnen per Vier-Finger-Zusammenziehen, über die Menüleiste oder per Klick auf AppPad im Dock (erneuter Klick schließt). Ein Klick bricht die Zusammenzieh-Animation jederzeit ab.
- Blättern per Zwei-Finger-Streichen; Seitenanzeige als Punkte oder Zahlen, antippbar und per Ziehen durchsuchbar mit einer Liquid-Glass-Lupe.
- Sofortsuche wie beim Launchpad unter macOS 15; Ergebnisse sortiert danach, wie oft und wie kürzlich du jede App verwendest.
- Bearbeitungsmodus durch langes Drücken auf ein App-Symbol oder Halten von ⌥ Option: zum Umsortieren ziehen, Apps aufeinander ablegen, um Ordner zu erstellen. Ordner können sich über mehrere Seiten erstrecken.
- Integrierte saubere Deinstallation: Lösche eine App im Bearbeitungsmodus, und AppPad entfernt auch ihre Restdateien.
- Die Fenstergröße folgt dem Bildschirm mit getrennten Prozentwerten für Breite und Höhe; in voller Größe kann es die Menüleiste überdecken und bleibt von der Notch frei.
- Öffnet sich auf dem Bildschirm unter dem Mauszeiger (optional) und bleibt auf dem Space, auf dem es geöffnet wurde, wie das Original-Launchpad.

#### Zwischenablage
- Verlauf der Zwischenablage für Texte und Bilder, dauerhaft gespeichert; Bilder bleiben erhalten, auch wenn die Originaldatei gelöscht wird.
- Gesicherte Sammlung für häufig genutzte Einträge – „Gesichert“ neben dem Suchfeld umschalten; gesicherte Einträge stehen in der Suche an erster Stelle.
- Öffnen mit ⌘. (gesicherte Sammlung: ⌘⌥.), Einsetzen mit ⌘1–⌘0, Vorschaubereich rechts.
- Symbol der Quell-App bei jedem Eintrag, Filter-Chips für deine meistgenutzten Apps und Suchsyntax `AppName::`.
- ⌘↩ zeigt den Quellordner eines Bildes im Finder.
- Verlauf nach Alter bereinigen (letzte Stunde, Tag, Woche … über ein Jahr), ohne die gesicherte Sammlung anzutasten.

#### Workflows
- Workflow-Panel (⌘Space), das Apple-Kurzbefehle, AppleScript und Shell-Skripte ausführt und Apps aus derselben Suche startet.
- Argumente: nach dem ersten Leerzeichen eingeben, z. B. `Set-Timer 10:00`. Tab vervollständigt den ausgewählten Eintrag.
- Integrierte Workflows: Papierkorb entleeren, Timer stellen, Wecker stellen, Lautstärke einstellen, Stummschalten, Alle Apps beenden und ein Rechner mit wissenschaftlicher Notation.
- Berechtigungssystem mit echter Sandbox für Shell- und AppleScript-Workflows: Einmal erlauben / Nicht erlauben / Immer erlauben.
- Workflows aus JSON-Dateien oder Links importieren, mit eindeutigen IDs, Revisionen und mehrsprachigen Namen.
- Mitteilungen bei Erfolg und Fehler pro Workflow.
- Apps und Workflows teilen sich ein gemeinsames Nutzungsranking.

#### Fenstersteuerung
- ⌃⌥← / ⌃⌥→ links / rechts andocken, im Wechsel ½ → ⅓ → ⅔.
- ⌃⌥↩ maximieren, ⌃⌥⌫ wiederherstellen, ⌃⌥⌘↑ / ⌃⌥⌘↓ auf den vorherigen / nächsten Bildschirm verschieben.
- Alle Kurzbefehle sind anpassbar.

#### App-Kurzbefehle
- Globale Tastaturkurzbefehle zum Öffnen beliebiger Apps, mit einer App-Liste von A–Z und Konflikterkennung.

#### Erscheinungsbild & Allgemein
- Suchfeld, Seitenanzeige und Einstellungs-Tabs in Liquid Glass.
- Design: Automatisch / Hell / Dunkel.
- Hintergründe: Weiß, Hellgrau, Dunkelgrau, Hintergrundbild oder eigene Farbe, jeweils mit eigener Transparenz und Unschärfe für helles und dunkles Design. Zwischenablage- und Workflow-Panel können dem Launchpad-Hintergrund folgen.
- ⌘⇧J / ⌘⇧K wechselt mit einer fließenden Überblendung zwischen Launchpad, Zwischenablage und Workflows.
- Nur in der Menüleiste (kein Dock-Symbol, außer du fixierst es), Start beim Anmelden.
- Optionaler Wechsel zur Eingabequelle ABC beim Öffnen jedes Panels.
- Einstellbares Verhalten von Esc (sofort schließen oder zuerst die Suche leeren).
- Lokalisiert in 10 Sprachen: English, Deutsch, Español, Français, Italiano, 日本語, 한국어, Nederlands, 简体中文, 繁體中文.

#### Vertrieb
- Mit Developer ID signiert und von Apple notariell beglaubigt.
- Installation mit Homebrew: `brew tap umindhub/tap && brew trust umindhub/tap && brew install --cask apppad`.
- Quellcode unter AGPL-3.0. Integrierte Workflows, das Workflow-Format und Workflows von Drittanbietern unter MIT.
