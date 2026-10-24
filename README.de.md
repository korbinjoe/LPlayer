# LPlayer

[English](README.md) · [简体中文](README.zh-CN.md) · [日本語](README.ja.md) · [Français](README.fr.md) · **Deutsch** · [Español](README.es.md)

Ein lokaler Videoplayer für macOS, entwickelt mit AppKit und libmpv. Tastenkürzel machen das Durchsuchen von Videos, das Spulen und die Wiedergabe flüssig, damit du dich ganz auf das Video konzentrieren kannst.

## Funktionen

- **Tastenkürzel.** Durchsuche Videos, spule und passe die Wiedergabe mit reaktionsschnellen, anpassbaren Bedienelementen an.
- **Lokale Wiedergabe.** Dateien oder Ordner öffnen, Videos ins Fenster ziehen oder über den Finder öffnen. Die Standardversion sucht im Hintergrund nach weiteren Videos im selben Ordner und passenden Untertiteln.
- **Vorschau in der Wiedergabeliste.** Ein Klick auf ein Video startet die Wiedergabe. Beim Durchblättern mit der Tastatur erscheint vor der Bestätigung eine stumme Miniaturvorschau. Es stehen eine kompakte Ansicht und eine Ansicht mit großer Vorschau zur Verfügung.
- **Globale Lautstärke.** Die Lautstärkeeinstellung gilt für alle Videos und bleibt bei Dateiwechseln sowie nach einem Neustart der App erhalten. Ältere Verlaufseinträge eines Videos können den aktuellen Pegel nicht überschreiben.
- **Fortsetzen und private Wiedergabe.** Wiedergabeposition, Geschwindigkeit, Untertitel und Audiospur werden für jede Datei wiederhergestellt. Die private Wiedergabe fügt weder Verlaufseinträge noch dauerhafte Dateizugriffsrechte hinzu.
- **Trackpad und Zeitleiste.** Mit einer Pinch-Geste bis zu 5× zoomen, das Bild mit zwei Fingern verschieben und beim Bewegen des Zeigers über die Zeitleiste eine unabhängige Miniaturvorschau anzeigen.
- **Native Darstellung.** AppKit-Bedienelemente, eine automatisch ausgeblendete Wiedergabeleiste, ein Manrope-Schriftzug und eine nicht modale Seitenleiste als Tastenkürzelreferenz.

Die Anwendungsoberfläche unterstützt derzeit **Englisch** und **vereinfachtes Chinesisch**. Die oben verlinkten README-Übersetzungen sind Dokumentationssprachen; sie erweitern nicht die verfügbaren Oberflächensprachen der App.

## Erstellen und starten

Voraussetzungen sind macOS 13 oder neuer, die Xcode Command Line Tools und Homebrew. Der lokale Standardbuild wurde auf Apple Silicon geprüft.

Im Stammverzeichnis des Repositorys ausführen:

```sh
brew install mpv pkg-config
./scripts/build-app.sh
open dist/LPlayer.app
```

Alternativ lässt sich [`打开LPlayer.command`](打开LPlayer.command) per Doppelklick starten. Das Startskript erstellt die App bei Bedarf und öffnet sie; nach Änderungen am Quellcode wird sie neu erstellt.

Nach dem Start **Open Video…** wählen, `⌘O` drücken, ein Video ins Fenster ziehen oder einen der drei enthaltenen Demofilme ausprobieren. LPlayer kann im Finder-Menü **Öffnen mit** ausgewählt werden; der systemweite Standardplayer wird nicht automatisch geändert.

Dies ist ein lokaler Entwicklungsbuild mit Ad-hoc-Signatur. Ein mit Developer ID signiertes und notarisiertes Installationspaket wurde bislang nicht veröffentlicht.

## Sprachen und Einstellungen

Die App startet unabhängig von der macOS-Sprache auf **Englisch** und merkt sich die gewählte Sprache. Zwischen Englisch und vereinfachtem Chinesisch lässt sich unter **Settings → General → Language** oder über **LPlayer → Language** wechseln.

Ein Sprachwechsel aktualisiert Menüs, Tooltips, Schnellsteuerungen, Wiedergabeliste, Tastenkürzelhilfe und Wiedergabefehlermeldungen. Mediendateinamen und Untertiteltexte bleiben unverändert. Native Systemdialoge verwenden die beim Start der App ausgewählte Sprache.

Die Einstellungen umfassen **General**, **Shortcuts** und **About**. Sie lassen sich über **LPlayer → Settings…**, das Menü **More** in der Wiedergabeleiste oder am unteren Rand der Schnellsteuerungen öffnen. `⌘,` öffnet direkt die Seite **Shortcuts**. Zu den allgemeinen Einstellungen gehören außerdem die standardmäßige Handbelegung und die Empfindlichkeit beim Verschieben des Bildes.

## Tastatursteuerung

Dies sind die aktuellen Standardbelegungen. Bereits angepasste Belegungen behalten bei Updates ihre wirksamen Tastenkürzel; das Zurücksetzen der Kürzel einer Hand übernimmt die neuen Standardwerte.

| Aktion | Linke Hand | Rechte Hand |
| --- | --- | --- |
| Wiedergabe / Pause | `Space` | `Space` |
| Vorheriges / nächstes Video | `W` / `S` | `I` / `K` |
| 5 Sekunden zurück / vor | `A` / `D` | `J` / `L` |
| 30 Sekunden zurück / vor | `Shift+A` / `Shift+D` | `Shift+J` / `Shift+L` |
| Lauter / leiser | `Shift+W` / `Shift+S` | `Shift+I` / `Shift+K` |
| Langsamer / schneller | `Q` / `E` | `U` / `O` |
| Normale Geschwindigkeit | `R` | `P` |
| Wiedergabeliste | `T` | `'` (auch `B`) |
| Schnellsteuerungen | `C` | `,` |
| Tastenkürzelhilfe | `V` | `Y` |
| Vollbild | `F` | `H` |
| Untertitel ein- / ausblenden | `G` | `;` |
| Positionssprung rückgängig machen | `Z` | `M` |
| Video an Fenster anpassen | `0` | `0` |

`W/A/S/D` und `I/J/K/L` entsprechen `↑/←/↓/→`. Ihr Verhalten richtet sich nach dem sichtbaren Modus:

| Modus | Auf / ab | Links / rechts | Space / Enter |
| --- | --- | --- | --- |
| Wiedergabe | Vorheriges / nächstes Video | 5 Sekunden springen | Space startet / pausiert |
| Wiedergabeliste | Auswählen und stumme Vorschau anzeigen | Hauptvideo unverändert lassen | Ausgewählten Eintrag abspielen |
| Schnellsteuerungen | Bedienelement auswählen | Wert ändern | Bedienelement aktivieren oder zurücksetzen |

Während der Wiedergabe ändert `Shift+↑/↓` die Lautstärke und `Shift+←/→` springt um 30 Sekunden, entsprechend den zugehörigen Buchstabentasten. In der Wiedergabeliste und den Schnellsteuerungen bleibt Shift mit einer Richtung dem sichtbaren Modus zugeordnet. Das Gedrückthalten einer Taste für den Videowechsel überspringt nicht mehrere Videos.

Weitere Tastenkürzel:

- `⌘O`: Video oder Ordner öffnen.
- `⌘L`: Wiedergabeliste ein- / ausblenden.
- `⌘[` / `⌘]`: vorheriges / nächstes Video.
- `⌘N`: private Wiedergabe ein- / ausschalten.
- `0` oder `⌘0`: Bild an das Fenster anpassen.
- `?`, `/` oder `⌘/`: Tastenkürzelhilfe ein- / ausblenden.
- `Esc`: aktives Panel oder aktive Seitenleiste schließen, danach Vollbild verlassen.

Die Tastenkürzelreferenz ist nicht modal: Wiedergabebefehle bleiben bei geöffneter Hilfe verfügbar. Dateidialoge und bearbeitbare Textfelder behalten ihre normale Texteingabe.

### Wiedergabeliste und Schnellsteuerungen

Die Wiedergabeliste ist beim Start geschlossen. Ein Mausklick spielt den jeweiligen Eintrag sofort ab; die Tastaturnavigation wählt ihn aus und startet nach einer kurzen Pause eine stumme Vorschau. `Home` / `End` wählt den ersten / letzten Eintrag. Enter oder Space bestätigt die Auswahl, ohne die Navigation in der Wiedergabeliste zu schließen. Die Bestätigung des aktuellen Videos setzt es an seiner aktuellen Position fort; ein beendetes Video kann neu starten.

Wiedergabeliste und Schnellsteuerungen können nicht gleichzeitig geöffnet sein. Die Schnellsteuerungen behalten 15 Aktionen: Geschwindigkeit, Lautstärke, Zoom, Empfindlichkeit beim Verschieben, Untertitelsichtbarkeit, Untertitelversatz, Audiospur, Untertitelspur, Handbelegung, private Wiedergabe, Dateien oder Ordner öffnen, Ordnerzugriff, Wiedergabeliste, Sprache und Anpassung der Tastenkürzel. Die feste Schaltfläche **Settings…** am unteren Rand ist ein zusätzliches Ziel für die Tastaturnavigation.

Die Untertitelschaltfläche schaltet Untertitel direkt ein oder aus. Die Geschwindigkeitsschaltfläche öffnet die Schnellsteuerungen mit ausgewählter Geschwindigkeitszeile; die horizontalen Navigationstasten ändern die Geschwindigkeit in Schritten von 0,1×.

### Tastenkürzel anpassen

Unter **Settings → Shortcuts** lassen sich die 29 Aktionen durchsuchen und Belegungen getrennt für jede Hand aufzeichnen. Unterstützt werden Buchstaben, Ziffern, Funktionstasten und Kombinationen mit Modifikatortasten. Esc bricht die Aufzeichnung ab; Delete löscht eine bearbeitbare primäre Belegung. Konflikte und reservierte Kürzel werden abgewiesen; feste Navigationskürzel und Menü-Aliasse bleiben verfügbar. Änderungen gelten sofort und werden lokal gespeichert.

## Lautstärke, Verlauf und Datenschutz

Die Lautstärke ist eine playerweite Einstellung für alle Dateien, einschließlich privater Wiedergabe, und bleibt nach einem Neustart der App erhalten. Das Lautstärkefeld in alten Wiedergabemerkpunkten bleibt aus Gründen der Formatkompatibilität bestehen, wird jedoch nicht mehr wiederhergestellt.

Bei normaler Wiedergabe werden die 30 zuletzt verwendeten Dateien unter `~/Library/Application Support/PalmPlayer/history.json` gespeichert. Wiederhergestellt werden Position, Geschwindigkeit, Untertitelversatz und -sichtbarkeit sowie die ausgewählten Audio- und Untertitelspuren. Beendete Dateien starten wieder am Anfang. Der Verlauf wird im Hintergrund geschrieben; die ursprüngliche Anwendungskennung und der Speicherort des Verlaufs bleiben mit dem früheren Namen PalmPlayer kompatibel.

Der lokale Standardbuild öffnet eine ausgewählte Datei sofort und sucht anschließend nach weiteren Videos im selben Ordner und passenden Untertiteln, ohne die Wiedergabe zu blockieren. Die Suche ist auf diesen Ordner beschränkt, überspringt versteckte Dateien und Unterordner und verwendet eine natürliche Sortierung, etwa für Episoden 1, 2 und 10. Werden mehrere Dateien ausdrücklich ausgewählt, bleibt deren Auswahlreihenfolge erhalten. Am Ende eines Videos wird der nächste Eintrag der Warteschlange abgespielt.

Vor dem Einschalten der privaten Wiedergabe wird der normale Wiedergabefortschritt gespeichert. Anschließend liest oder schreibt die App für neu geöffnete Dateien keinen Wiedergabeverlauf mehr. Diese Dateien starten am Anfang; vorhandene Verlaufseinträge bleiben erhalten. Globale Lautstärke und Anwendungseinstellungen werden weiterhin gespeichert. Der Wiedergabeverlauf lässt sich im Menü **File** löschen.

## Trackpad und Vorschauen

Mit einer Pinch-Geste über dem Video wird um den Zeiger herum gezoomt. Bei vergrößertem Bild verschieben zwei Finger ohne Druck auf das Trackpad das Bild; die Bewegung folgt den Fingern und endet beim Abheben. Die Empfindlichkeit ist von 25 % bis 150 % einstellbar, standardmäßig 100 %. Das Bild bleibt innerhalb seiner Grenzen; beim Videowechsel werden Zoom und Verschiebung zurückgesetzt.

Zweimaliges Tippen mit zwei Fingern wechselt zwischen 2×-Zoom und Anpassung an das Fenster. `0` / `⌘0` setzt die Ansicht ebenfalls zurück. Gesten, die über der Wiedergabeliste, den Bedienelementen oder der Hilfeseitenleiste beginnen, behalten die Interaktion des jeweiligen Bereichs.

Die Miniaturen der Zeitleiste verwenden einen separaten Decoder mit niedriger Auflösung und einen Arbeitsspeichercache, ohne die Hauptwiedergabeposition zu verändern. Auch die bewegten Vorschauen der Wiedergabeliste sind getrennt und ohne Audio. Vorschaubilder werden nicht auf den Datenträger geschrieben.

## Interaktiver HTML-Prototyp

Unter [`prototypes/lplayer`](prototypes/lplayer/README.md) liegt ein reiner Frontend-Prototyp. Er verwendet lokale Videos, Schriftarten und Symbole und benötigt keine npm-Abhängigkeiten:

```sh
python3 prototypes/lplayer/serve.py
```

<http://127.0.0.1:4178/> öffnen. Der Prototyp hat derzeit eine chinesische Oberfläche. Seine Tastaturkontexte entsprechen dem nativen Player; Funktionen, die native Decodierung oder macOS-APIs benötigen, sind gekennzeichnet. Lokale Dateien werden über Objekt-URLs des Browsers abgespielt und nicht hochgeladen; die Formatunterstützung des Browsers unterscheidet sich von libmpv. Der Prototyp implementiert weder den nativen Verlauf noch das Backend für Dateizugriffsrechte.

Die drei enthaltenen Demofilme sind stumme Clips aus KI-generierten Landschaftsstandbildern mit langsamen, per FFmpeg erzeugten Kamerabewegungen und SRT-Untertiteln, **keine Aufnahmen vor Ort**. Siehe die [Herkunft der Demos](Resources/Demo/README.txt).

## Validierung

Zusätzliche Wiedergabeprüfungen benötigen die FFmpeg-Kommandozeilenwerkzeuge:

```sh
brew install ffmpeg
./scripts/check-core.sh
./scripts/check-viewport.sh
./scripts/make-demo.sh
./scripts/check-engine.sh
./scripts/check-gestures.sh
./scripts/check-thumbnails.sh
./scripts/check-seeking.sh production-final Sources/PalmPlayer
python3 scripts/interaction/run-controller.py
```

Die Kernprüfungen decken Tastenbelegungen, Modifikatoren, Verlauf, Persistenz und die Migration von Tastenkürzeln ab. Der [Controller-Testaufbau](scripts/interaction/README.md) prüft den tatsächlichen Handler mit generierten Medien und isoliertem Speicher, einschließlich globaler Lautstärke beim Wechsel zwischen Dateien mit Verlauf und nach einem Neustart. Generierte Berichte liegen im ignorierten Verzeichnis `artifacts/`; historische Nachweise sind nicht im Quellcodepaket enthalten.

Engine- und Gestenprüfungen können kurzzeitig unabhängige Testfenster anzeigen. Der verborgene Controller-Testaufbau verwendet lokale Ereignisse und weist weder physische Tastatureingaben noch Vordergrundfokus, Vollbild-Spaces oder das Verhalten von Systemdialogen nach. Diese Prüfungen ersetzen keine Tests mit echten Geräten und Medien. Frühere Messungen und deren Umfang stehen in den [Leistungshinweisen (中文)](docs/PERFORMANCE.md).

## Sandbox-Vorschau und Distribution

Eine separate Sandbox-Vorschau verwendet kontrollierte Abhängigkeiten sowie eine unabhängige App-Identität und einen eigenen Container. Ihr dokumentiertes Ziel sind Apple Silicon und macOS 15 oder neuer. Sie wurde weder beim Mac App Store eingereicht noch von ihm genehmigt:

```sh
./scripts/build-store-deps.sh
./scripts/build-store-app.sh --preview
./scripts/check-store-app.py
```

Die Sandbox spielt zunächst nur die ausgewählte Datei ab. `⌘⇧O` gewährt schreibgeschützten Ordnerzugriff für weitere Videos und passende Untertitel; die Berechtigungen verwenden Security-Scoped Bookmarks und lassen sich im Menü File löschen. Der private Modus fügt weder dauerhafte Berechtigungen noch Verlaufseinträge hinzu.

Der Standardbuild bündelt die tatsächlich vom Programm verwendeten Nicht-Systembibliotheken, schreibt deren Ladepfade um, validiert sie und signiert die App ad hoc. Nach dem Anlegen einer Sicherung ersetzen Builds `dist/LPlayer.app` atomar und starten einen laufenden Player nicht neu. Die enthaltene Schriftart Manrope muss nicht systemweit installiert werden.

Versionen der Abhängigkeiten und Lizenzhinweise stehen in [`Resources/licenses`](Resources/licenses/README.md). Der auf Homebrew basierende Standardbuild enthält GPL-lizenzierte Komponenten; die Sandbox verwendet eine separate Abhängigkeitskonfiguration. Die beigefügten Hinweise stellen keine vollständige Distribution des zugehörigen Quellcodes dar. Siehe [Veröffentlichung vorbereiten (中文)](docs/APP_STORE_RELEASE.md) und [historische Sandbox-Validierung (中文)](docs/APP_STORE_VALIDATION.md).

Das Rendering verwendet derzeit die OpenGL-Pipeline von libmpv. Metal-Rendering, Online-Untertitelsuche, automatische Untertitelsynchronisierung und KI-Funktionen sind nicht implementiert. HDR-Korrektheit, Audio-Passthrough, sämtliche Codecs und der Energieverbrauch auf unterschiedlichen Geräten wurden nicht umfassend validiert.
