# Pi-MCS — Arbeitsregeln

Eine All-in-one-Lösung für einen PaperMC-Server auf dem Raspberry Pi:
klonen, `./install.sh` starten, vom Assistenten durchführen lassen — danach
läuft ein Server, der sich über eine Weboberfläche bedienen lässt.

Kern ist **PaperMC**. Dieses Projekt ersetzt Paper nicht und erweitert es
nicht funktional. Es legt eine durchdachte Installation, Verwaltung und
Wartung darum herum.

Das Lastenheft (`docs/lastenheft-minecraft-server.md`) beschreibt das **WAS
und WOZU**, die Pflichtenhefte je Etappe (`docs/pflichtenheft-etappe-*.md`)
das **WIE**. Bei Widersprüchen gilt das Lastenheft.

## Leitsätze — und ihre Reihenfolge zählt

Im Zweifel wird nach diesen Sätzen entschieden, in dieser Reihenfolge:

1. **Die Leistung des Minecraft-Servers hat Vorrang.** Nichts, was drumherum
   läuft, darf ihm spürbar Rechenzeit oder Speicher wegnehmen. Konkret: Der
   Metrik-Sammler läuft mit `Nice`, RCON wird sparsam benutzt (es läuft im
   Hauptthread des Servers — eine Abfrage je Klick ist richtig, eine je
   Sekunde nicht).
2. **Leichtgewichtig.** Keine Bauteile, die es nicht braucht.
3. **Einfach, aber ausgeklügelt.** Lieber einmal mehr nachgedacht, wie es
   rund wird, als es zu verkomplizieren.
4. **Lesbar für Pi-Anfänger.** Wer den Code aufmacht, soll ihn verstehen.
   Das ist ein Feature, kein Zufall — und der Grund, warum hier Bash und
   Flask stehen und nicht ein Go-Binary, das 25 MB RAM spart.
5. **Ehrlich statt bequem.** Lieber melden, dass etwas nicht funktioniert,
   als es zu verstecken. Ein Test, der bei fehlendem Werkzeug still
   durchwinkt, ist schlimmer als kein Test.
6. **Mit Liebe gemacht.** Minimalistisch, aber nicht lieblos.

**Kommentare erklären das WARUM, nicht das WAS.** Das ist im Bestand
durchgehend so und soll so bleiben. Ein Kommentar, der eine Messung oder
einen Befund festhält, nennt Datum und Ergebnis.

## Nicht-Ziele

Keine kommerzielle Hosting-Lösung. Keine andere Plattform als der Raspberry
Pi. Keine Minecraft-Inhalte. Kein Fork und kein Ersatz von Paper. Keine
großen Spielerzahlen (ausgelegt auf 5 gleichzeitig, maximal 10).
**Kein Docker** — begründet verworfen. **Kein npm, kein Node, kein
CDN**: Die Oberfläche ist Flask + Jinja + HTMX ohne Build-Schritt, und alles
wird lokal ausgeliefert, damit sie auch ohne Internet funktioniert.

## Sprache

**Deutsch, überall:** Code, Kommentare, Oberfläche, Dokumentation,
Commit-Nachrichten. Bezeichner ebenfalls (`fehler_merken`, `konsole_laeuft`,
`ausrollen`). In Commit-Nachrichten und Skript-Kommentaren werden Umlaute
als `ae/oe/ue` geschrieben, im Fließtext der Markdown-Dateien nicht.

## Regeln, bei denen das Naheliegende falsch ist

Diese Punkte sind gemessen, nicht vermutet. Wer sie beim Prüfen nicht kennt,
hält korrekten Code für falsch — oder umgekehrt.

- **Paper schreibt `server.properties` beim START neu, nicht beim
  Herunterfahren.** Und es schreibt die *ganze* Datei aus dem Speicher neu,
  sobald ein Befehl eine dort gespeicherte Einstellung **tatsächlich
  ändert** (ein Nullvorgang wie `whitelist on` bei bereits aktiver Whitelist
  löst nichts aus). Eine Änderung von außen kann daher jederzeit lautlos
  verschwinden. Deshalb: bei laufendem Server **vormerken**, nicht
  schreiben. Die YAML-Dateien dürfen dagegen geschrieben werden, sie wirken
  beim nächsten Start. Eigene Kommentare in `server.properties` überleben
  den nächsten Start nicht.
- **`ops.json` verhält sich beim Start GENAU UMGEKEHRT zur
  `server.properties`.** Am 01.09.2026 gemessen (M9 in
  `tests/messung-im-container.sh`), weil die Übertragung der bekannten Regel
  hier in die Irre führt:

  | | `server.properties` | `ops.json` |
  |---|---|---|
  | beim Stoppen | überlebt | überlebt |
  | beim **Start** | **wird verworfen** | **wird gelesen und überlebt** |
  | bei laufendem Server, nach einem ändernden Befehl | wird verworfen | wird verworfen |

  Belegt, nicht geschlossen: Bei gestopptem Server alle Stufen auf `3`
  gesetzt, gestartet — die `3` stand noch da. Dass sie auch im
  Arbeitsspeicher stand, zeigte erst ein erzwungenes Neuschreiben (`op` auf
  einen Neuen): Danach trugen die alten Einträge weiterhin `3`, nur der neue
  die Vorgabe `4`.

  Daraus folgt für die **Operator-Stufe**: Ein Vanilla-RCON kennt kein
  Kommando dafür — `op <name> <stufe>` gibt es nicht (`Incorrect argument for
  command`), auch nicht als `minecraft:op`; `op <name>` vergibt immer
  `op-permission-level`. Der einzige Weg ist, `ops.json` **bei gestopptem
  Server** zu schreiben. Bei laufendem Server gilt: **nichts Schreibendes an
  `ops.json`** — es verschwindet beim nächsten `op` oder `deop` lautlos.
  Umgesetzt seit dem 02.09.2026 in `spieler.stufe_setzen()`: Es fragt
  `service_state(frisch=True)` und schreibt nur, wenn der Server steht.
  Die Oberfläche bietet die Stufenwahl deshalb **genau dann an, wenn alles
  andere auf der Spielerseite nicht geht**. Das ist kein Fehler im Aufbau,
  sondern die Messung — wer es „vereinheitlicht", baut den stillen
  Rechteverlust wieder ein.
- **Ein Schlüssel, den Paper nicht mehr kennt, sieht aus wie eine
  Abweichung.** `spawn-monsters` stand bis zum 02.09.2026 in der Vorlage, in
  `install.sh` und als Schalter in der Oberfläche — Paper 26.2 kennt ihn
  nicht mehr, ebenso wenig `spawn-animals` und `spawn-npcs`. Folge: eine
  Dauermeldung von `deploy.sh` über einen Wert, den Paper beim nächsten Start
  wegwirft, und ein Schalter, der schreibt und dann wieder auf „aus" steht.
  Wer keine Monster will, stellt heute die Schwierigkeit auf `peaceful`.
  > **Und die Messfalle dabei:** Die `paper.jar` nach dem Schlüsselnamen zu
  > durchsuchen taugt **nicht** — sie ist ein Lader, die Klassen liegen
  > komprimiert darin, und auch `spawn-protection` liefert dort null Treffer.
  > Der tragfähige Beleg ist eine `server.properties`, die **Paper selbst**
  > vollständig geschrieben hat (nach einem Start, 71 statt 21 Schlüssel):
  > Was dort fehlt, kennt Paper nicht. Vor jeder Behauptung über einen
  > Schlüssel erst am Kontrollschlüssel prüfen, ob das Instrument überhaupt
  > misst.
- **`difficulty` und `white-list` stehen in der Welt, nicht in der Datei.**
  Der Wert in `server.properties` zählt nur, wenn eine Welt neu erzeugt
  wird; danach übergeht Paper ihn beim Start. Wer den Wert wissen will,
  fragt den laufenden Server, nicht die Datei — sonst steht auf jeder
  gewachsenen Welt eine Falschaussage.
- **RCON lässt sich nicht auf `127.0.0.1` beschränken.** Es bindet immer an
  alle Netzwerkkarten; einen Schlüssel `rcon.ip` gibt es nicht, und
  `server-ip` muss leer bleiben. **Die Firewall ist die einzige
  Abschottung** — daher eine ausdrückliche `DENY`-Regel für den RCON-Port,
  zusätzlich zur Grundregel. Auf einer *geteilten* RCON-Verbindung reißt
  `whitelist add` die Verbindung ab: Für Befehle, die den Rechner verlassen
  (`whitelist add`, `op` — sie schlagen den Namen bei Mojang nach), je eine
  eigene Verbindung.
- **`tar … | grep -q` ist hier eine Falle**, weil überall `set -o pipefail`
  gilt: `grep -q` hört beim ersten Treffer auf, tar bekommt SIGPIPE und
  endet mit **141** — die Pipeline gilt als fehlgeschlagen, obwohl der
  Treffer da war. Ausgelöst wird es erst ab einer gewissen Archivgröße, im
  Container also oft gar nicht. Stattdessen in eine Variable lesen und mit
  Here-String suchen, oder `find … -print -quit`.
  > **Gilt für JEDEN Erzeuger, nicht nur tar** — am 2026-09-23 lief
  > `ip -6 addr … | grep -qv …` im DNS-Skript genau so hinein (nachgestellt
  > mit 20000 Adresszeilen: rc 141). Und beim Here-String auf eine
  > **leere** Variable achten: `<<<""` ist eine leere Zeile, und die trifft
  > `grep -v`.
- **`screen -X stuff` wertet DREI Zeichen aus: `\`, `^` und `$`.** `^M` ist
  ein Wagenrücklauf (`say hallo^Mstop` wird zu zwei Befehlen), und `$VAR`
  bzw. `${VAR}` setzt screen aus der **Umgebung des Minecraft-Dienstes**
  ein — samt Geheimnissen aus dessen Drop-ins (API-Schlüssel). Beide
  Fassungen (`server/lib-konsole.sh`, `admin/konsole.py`) escapen seit dem
  2026-09-23 alle drei, nach der Verdopplung der Backslashes. Gemessen an
  einer Wegwerf-Sitzung mit einer Testvariable.
- **„Leer“ ist bei DNS nicht „weg“.** Ein leerer Wert an deSEC LÖSCHT den
  Eintrag, `preserve` lässt ihn stehen. `dns-update.sh` sendet leer nur,
  wenn es die Adresse wirklich nicht gibt (IPv4: keine Standardroute;
  IPv6: keine globale, nicht veraltete, nicht private Adresse am Pi), und
  `preserve`, wenn nur die Abfrage scheiterte. Gemerkt wird der
  **gemeldete** Zustand — sonst sieht der echte Wegfall nach einem
  Aussetzer aus wie „unverändert“ und wird nie gemeldet.
- **Ein Absturz hinterlässt eine Leiche.** Stirbt Java hart, bleibt der
  Sockel der Sitzung als `(Dead ???)` in `screen -ls` stehen, und
  `Restart=always` legt die nächste daneben. Wer nur nach dem Namen sucht,
  hält den Server für laufend. Deshalb schließt die Prüfung `(Dead` aus, und
  aufgeräumt wird mit `screen -wipe` (an einer toten Sitzung scheitert
  `-X quit`).
- **Paper schreibt für EINE Trennung ZWEI Zeilen**, in wechselnder
  Reihenfolge und nicht immer in derselben Sekunde: „… hat das Spiel
  verlassen" und „… hat die Verbindung verloren (Grund: …)". Nur die
  zweite trägt den Grund. Wer die erste gewinnen lässt, schreibt
  **Sortierreihenfolge** in die Datenbank und nennt sie Grund.
  Am 21.09.2026 an 364 echten Trennungen nachgezählt: 350 Paare, 7-mal nur
  die eine Zeile, 7-mal nur die andere, und **14 Paare überspannen eine
  Sekundengrenze**. Deshalb ein Zwei-Sekunden-Fenster statt eines
  Gleichheitstests.
  > **Und die Falle dahinter:** Beim Anmelden von einem zweiten Gerät
  > meldet Paper **zuerst den neuen Beitritt** und wirft erst danach die
  > alte Verbindung hinaus. Wer die Abmeldezeilen der gerade eröffneten
  > Sitzung zuschlägt, erzeugt eine Sitzung von **null Sekunden** und
  > lässt die echte ohne Dauer als „Absturz" stehen. Zwei der drei
  > vermeintlichen Abstürze auf diesem Pi waren genau das. Erkennungs-
  > merkmal, und es ist exakt: Die offene Sitzung begann **genau in dem
  > Moment**, in dem die vorige geschlossen wurde.
  >
  > Der Grund ist keine Formsache — neben `Disconnected` kamen
  > `You have been idle for too long!`, `Server closed`, `Timed out` und
  > `You logged in from another location` vor.
- **In den Serverlogzeilen steht kein Datum**, nur `[HH:MM:SS]`, und es
  gibt **zwei** Herleitungen — die zweite vergisst man beim Nachbauen:
  Ein Archiv nennt im Dateinamen den **ersten** Tag (vorwärts rechnen),
  `latest.log` dagegen trägt seine Änderungszeit zur **letzten** Zeile
  (rückwärts rechnen). Beide stehen seit dem 21.09.2026 in
  `admin/logdatum.py` und nirgends sonst.
  > Daraus folgt eine Einschränkung, die von außen wie eine verpasste
  > Optimierung aussieht: **`latest.log` lässt sich nicht ab einer
  > Lesemarke stückweise auswerten.** Das Datum der ersten Zeile hängt am
  > Ende der Datei. Es wird jedes Mal ganz gelesen — bei einer Datei, die
  > jeder Serverstart neu anlegt, ist das billig.
- **Seit Paper 26.3 steht vor Beitritt und Verlassen `System chat: `**
  (`…]: System chat: Steve joined the game`), vor `lost connection`,
  `logged in` und `UUID of player` dagegen nicht. Vom 14. bis 21.10.2026
  fanden die Muster deshalb keinen einzigen Beitritt: 0 Spieler in der
  Oberfläche, eine Woche ohne Sitzung in der Historie, und `mcs restart`
  warf Spieler **ohne Vorwarnung** hinaus. Gemeldet hat das nichts, denn
  „nichts gefunden“ ist für jede Auswertung ein gültiges Ergebnis.
  `MUSTER_BEITRITT` und `MUSTER_VERLASSEN` haben den Vorsatz jetzt als
  optionale Gruppe. Bash kennt kein `(?:…)`, darum steht der **Name dort
  in Gruppe 3**, überall sonst in Gruppe 2. `make muster` prüft das an den
  echten Nutzern. Merksatz: **Nach einem Wechsel der Minecraft-Version das
  Logformat an echten Zeilen prüfen.** Ein `Done (` im Log beweist nur,
  dass der Server läuft, nicht, dass ihn jemand richtig liest.
  > **Seit dem 21.10.2026 meldet sich ein Rückfall selbst:**
  > `protokollpruefung.beitritte_unerkannt()` zählt `joined the game` und
  > `logged in with entity id` **lose**, also unabhängig von
  > `log-muster.sh`. Findet es Zeugen, aber `MUSTER_BEITRITT` keinen
  > Treffer, erscheint ein Kreuz im Balken der Startseite, eine Meldung auf
  > der Spielerseite und eine Warnung in `mcs status`. **Den Zeugen nie
  > auf die gemeinsamen Muster umstellen**, sonst fällt er mit dem Muster
  > aus, das er bewacht. Außerdem ist die Reihenfolge der beiden Zeilen
  > nicht fest: bis 26.2 erst `logged in`, seit 26.3 erst `joined`.
- **Ein Pl3xMap-Update kann `plugins/Pl3xMap/config.yml` komplett auf die
  Vorgaben zurücksetzen.** 26.3-557 tat das am 14.10.2026 beim ersten
  Start: Port 8080 (der Port der Oberfläche auf einer älteren
  Installation), `bind 0.0.0.0`, `web-address http://localhost:8080`,
  dazu ein anderer Renderer. Der Kartenserver kam nicht hoch, und die
  Kartenseite bettete sich selbst ein. Seit dem 21.10. fragt
  `seite_karte.kartenserver_antwortet()` nach und sagt es auf der Seite.
  Vor einem Pl3xMap-Update die Datei sichern.
- **`player_activity.log` ist ein Hauptbuch, kein Protokoll.** Es gehört in
  **keine** logrotate-Regel. `admin/spieler.py` liest es als **Ganzes**, um
  „zuletzt gesehen" zu beantworten — eine Rotation schneidet genau diese
  Antwort weg, und zwar lautlos: Nach dem Lauf vom 06.09.2026 stand die
  Live-Datei auf 0 Byte, und die Spielerseite meldete für jeden Spieler
  „nicht aufgezeichnet", auch für den mit dreistelliger Stundenzahl.
  Gefunden erst zwei Wochen später — „keine Daten" sieht dort genauso aus
  wie „war noch nie da". Die Größe war nie ein Argument: gemessen 139 KB
  in einem halben Jahr.
  > Seit dem 21.09.2026 ist die Zeile aus `install.sh` raus, `deploy.sh`
  > (Abschnitt 3d) nimmt sie auf bestehenden Installationen heraus, und
  > `admin/protokollpruefung.py` meldet auf der Spielerseite, wenn das
  > Protokoll hinter den Serverprotokollen zurückbleibt. **Beide Skripte
  > schreiben denselben Hinweis in die Regel, wortgleich** — sonst fände
  > `deploy.sh` seine Marke auf einer frischen Installation nicht und
  > ergänzte bei jedem Lauf eine weitere Erklärung.
  >
  > **Merksatz, doppelt:** Bevor eine Datei in eine Rotationsregel kommt,
  > fragen, ob irgendwer ihre *Vergangenheit* liest. Und: Eine Reparatur
  > ist erst fertig, wenn geprüft ist, was sie regelmäßig wieder
  > kaputtmacht — das Nachtragen vom 01.09. (W3) war richtig und hat
  > trotzdem nur fünf Tage gehalten.
- **Der Weltname ist frei wählbar** und steht in `level-name`. Nirgends
  `world` fest verdrahten — auch nicht in Tests. Genau das ist einmal
  passiert: Der Test prüfte ins Leere und meldete trotzdem Erfolg.
  **Spielerdateien liegen je nach Weltformat unter `<welt>/players/stats/`
  *oder* `<welt>/stats/`** — beide Orte kommen vor, und entschieden wird
  anhand der Datei, nicht des Ordners.
- **`enable`-Verweise folgen dem `[Install]`-Abschnitt, der beim
  `systemctl enable` galt.** `daemon-reload` fasst sie **nicht** an, und
  `reenable` fasst nur an, was schon aktiviert ist. Die Wahrheit steht in
  `systemctl show <einheit> -p WantedBy`, nicht in der Unit-Datei. Wer eine
  neue Einheit hinzufügt, muss dafür sorgen, dass sie auch auf **bestehenden**
  Installationen ankommt — nicht nur bei einer frischen.
- **Ein Wert in der `mcs.conf` wird von DREI Lesern gelesen, und sie sind
  sich nicht einig.** Die Shell (`. mcs.conf`), systemd (`EnvironmentFile=`,
  sechs Einheiten) und Python. Ein Wert mit Leerzeichen — der ganz
  gewöhnliche Einhängepunkt `/media/pi/My Passport` — zerlegte die Shell in
  zwei Wörter und führte das zweite aus (`127`); jedes Backup starb daran in
  seiner Source-Zeile, also **vor** `trap` und Merkzettel: lautlos. Am
  2026-08-31 gemessen, und das Naheliegende ist falsch herum:
  `'wert'` nehmen Shell *und* systemd wörtlich — richtig. `"wert"` nimmt nur
  systemd wörtlich; die Shell führt `$(…)` darin **aus**, was aus der
  Reparatur eine Befehlsausführung über ein Webformular gemacht hätte.
  Geschrieben wird deshalb über `konfig.wert_fuer_mcs_conf()` bzw.
  `mcs_conf_wert()` (install.sh), gelesen mit Abnehmen der
  Anführungszeichen. Python muss das selbst tun, die anderen beiden nicht.
- **`hmac.compare_digest` verweigert `str` mit Nicht-ASCII.** In einem
  durchweg deutschen Projekt, dessen Assistent ein eigenes Passwort erfragt
  und nur dessen Länge prüft, ist ein Umlaut das Naheliegende — und die
  Folge war ein `TypeError`, also ein Serverfehler bei **jedem**
  Anmeldeversuch statt einer Meldung. Verglichen wird deshalb `.encode()`,
  nicht `str`. Beide Testpasswörter sind ASCII; der Test hätte es nie
  gefunden.
- **`${X:-standard}` greift nicht bei einer ausdrücklichen `0`.** Aus
  `MCS_BACKUP_BEHALTEN=0` — die naheliegende Schreibweise für „keine
  Rotation" — wurde `tail -n +1`, also *jede* Zeile: Ein Lauf räumte beide
  Backup-Platten leer. `MCS_ARCHIV_JEDES=0` war eine Division durch null,
  an der das Skript **nach** einem gelungenen Backup starb und dauerhaft
  einen Fehlschlag meldete. Seit 2026-08-31 heißt `0` ausdrücklich „aus",
  und was keine Zahl ist, fällt laut gemeldet auf den Standard zurück
  (`zahl_aus_conf`). Gelöscht wird nie auf Grundlage eines Wertes, dem das
  Skript nicht trauen kann.
- **Ein Zwischenspeicher, den zwei Takte teilen, misst für keinen von
  beiden.** `cpu_usage_percent()` hob die vorige `/proc/stat`-Probe auf, um
  ohne `sleep` eine Differenz bilden zu können — für sich richtig. Falsch
  war, dass **ein** solcher Zustand **zwei** Aufrufern gehörte: dem
  Metrik-Sammler (60 s) und den Kacheln der Startseite (5 s). Wer die Probe
  liest, setzt sie zurück. Bei geöffneter Oberfläche maß der Sammler deshalb
  nicht seine Minute, sondern die Restspanne seit dem letzten Seitenaufruf,
  mitunter Millisekunden — und über eine so kurze Spanne ist die Auslastung
  beliebig. Gemessen am 2026-09-01: 1434 Werte über 24 Stunden, 0,0 bis
  93,6 Prozent, 394 Sprünge über 30 Punkte, bei durchgehend 20,0 TPS und
  höchstens 18,5 ms je Tick. Dass es Rauschen war und keine Last, zeigte die
  Verteilung: gleichmäßig über alle Tagesstunden. Echte Last hätte ein
  Muster (das nächtliche Backup, die Timer der Widgets); Rauschen hat keins.
  Wieder **ein zweiter Weg zur selben Sache, der die Regel des ersten nicht
  kennt** — und der Kommentar der Funktion verteidigte das geteilte
  Verhalten sogar ausdrücklich. Für die *Anzeige* stimmte der Satz auch.
  Seit v1.1 wird die Probe je Aufrufer geführt (`cpu_auslastung(aufrufer)`),
  dazu eine Untergrenze von einer Sekunde — sonst kehrte derselbe Fehler
  zurück, sobald jemand zwei Browserfenster offen hat. Merksatz: **Wer einen
  Zustand zwischen Aufrufen aufhebt, muss aufschreiben, WESSEN Zustand es
  ist.**
- **Der Aufrüstweg kann weniger als die Frischinstallation.** `install.sh`
  richtet ein, `deploy.sh` rollt auf eine bestehende Installation aus. Alles
  Neue — eine systemd-Einheit, ein `mcs.conf`-Schlüssel — braucht in
  `deploy.sh` eine **eigene** Abfrage. Eine Sammelbedingung („wenn der erste
  Schlüssel fehlt") lässt später Hinzugekommenes stillschweigend liegen.
  > **Für DATEIEN gilt das seit dem 2026-09-02 nicht mehr — sie stehen in
  > `lib/dateien.sh`**, und beide Skripte arbeiten dieselbe Liste ab
  > (`install.sh` kopiert, `deploy.sh` vergleicht). Wer eine Datei ergänzt,
  > ergänzt sie dort, an einer Stelle. Vorher gab es zwei Listen, und sie
  > waren auseinandergelaufen: `lib/hardware.sh` fehlte in `deploy.sh`, also
  > benutzte `mcs hardware` auf einer nur ausgerollten Installation eine
  > veraltete Fassung.
  >
  > Der Modus in Spalte drei ist kein Schmuck: `nur-wenn-fehlt` heißt
  > „Vorlage, gehört ab dem ersten Start dem Pi" (`plugins.txt`) und wird von
  > `deploy.sh` **übersprungen**, `neustart` heißt „wirkt erst nach einem
  > Server-Neustart". `install.sh` ruft `deploy.sh` **nicht** auf: Das zöge
  > Konfigurationsvergleich, systemd-Verankerung und Dienstneustarts mitten
  > in eine Erstinstallation.
  >
  > **`neustart` gilt nur für `minecraft.service`.** Zwei Dauerdienste lesen
  > ihren Code ebenfalls nur beim Start: `mcs-admin` (die Oberfläche) und
  > `mcs-playerlog` (Spielerprotokoll samt `log-muster.sh`). `deploy.sh`
  > nennt für beide einen eigenen Neustart-Hinweis — für das
  > Spielerprotokoll erst seit dem 2026-09-24; vorher liefe ein
  > ausgerollter Fix dort bis zum nächsten Neustart des Pi nicht.

- **`mcs update` ohne Zusatz holt den NEUESTEN Build, nicht den
  festgelegten** (seit 2026-10-03). Den festgelegten aus `versions.env`
  installiert `--festgelegt` — so ruft es `install.sh`, damit zwei
  Installationen desselben Stands gleich sind. Wer einen weiteren Aufrufer
  von `paper-update.sh` baut, entscheidet bewusst, welchen der beiden er
  will. Die Minecraft-Version wechselt nur mit `--minecraft`, nie nebenbei.
  > Vorher war der Standard „installiere, was festgelegt ist", und der Knopf
  > in der Oberfläche rief genau das: Er meldete bei **jedem** Klick „nichts
  > zu tun" (im Aktionsprotokoll am 22.09. und 03.10.2026), zeigte aber nur
  > „Gestartet". Ein Build-Update hieß: Nummer und Prüfsumme von Hand in
  > `versions.env`, ausrollen, `mcs update`, committen.

  Drei Dinge daran sind nicht naheliegend:
  - **Das Skript schreibt `versions.env` selbst — in der Installation UND im
    Repository — und committet dort genau diese eine Datei.** Sonst drehte
    das nächste `./deploy.sh` den Build zurück. Hatte die Datei im Repo
    schon offene Änderungen, wird **nicht** committet: Die gehören jemandem.
    Ohne Git-Identität (auf einem frisch geklonten Pi der Normalfall)
    committet es als `Pi-MCS <pi-mcs@localhost>`. Gepusht wird nie.
  - **„Verfügbar" heißt STABIL.** Am 03.10.2026 hatte 26.3 bei PaperMC 143
    Builds, alle im Kanal BETA. Die alte Prüfung nannte 26.3 trotzdem
    „verfügbar" — und dazu 26.1.2 und 26.1.1 als „neuere" Versionen, weil
    sie einfach die ersten Einträge der Liste nahm. `--minecraft 26.3` wäre
    erst **nach** dem minutenlangen Backup an „kein stabiler Build"
    gescheitert; die Prüfung steht jetzt davor.
  - **Die Oberfläche fragt PaperMC nicht selbst.** Sie ruft
    `paper-update.sh --pruefen` und liest danach die Notiz
    `mc_server/paper.verfuegbar` (`admin/paper.py`). Eine eigene Abfrage in
    Python wäre der zweite Weg zur selben Sache, der die Stabil-Regel nicht
    kennt. Beim Aufbau der Seite geht nichts nach außen (Lastenheft 5.7.2).
    Ob ein neuer Build schon **läuft**, entscheidet der Vergleich der
    Änderungszeit von `paper.jar` mit `ActiveEnterTimestamp` des Dienstes —
    `paper.installiert` sagt nur, was **daliegt**.

- **Die Kopien außer Haus (v1.4) löschen — und deshalb gilt dort mehr
  Vorsicht als irgendwo sonst.** USB-Stick und Cloud räumen auf, und
  ein Aufräumen ist die Stelle, an der ein Backup-Werkzeug Daten vernichtet
  statt rettet. Drei Regeln, alle mit Absicht so:
  - **Die Cloud räumt nach ZAHL auf, nie nach Alter und nie per „sync".**
    `sync` spiegelt ein Unglück (leerer Backup-Ordner → leere Cloud), „älter
    als 30 Tage" räumt die Cloud leer, wenn die Backups ausbleiben — genau
    dann, wenn man die alten braucht. Und nie weniger als auf dem Pi, sonst
    lädt jeder Lauf die lokal noch vorhandenen wieder hoch.
  - **Auf dem Stick wird nur angefasst, was im eigenen Ordner liegt und
    `backup_*.tar.gz` heißt**, und nur an einem Stick mit dem richtigen
    Namen. `tests/pruefung-kopien.sh` prüft vor allem, was NICHT
    verschwinden darf.
  - **Nur verschlüsselt außer Haus.** `cloud-kopie.sh` verweigert jedes
    rclone-Ziel, das nicht vom Typ `crypt` ist: In jedem Archiv stehen das
    RCON-Passwort und die Whitelist.
- **Die USB-Kopie ist die eine Ausnahme von „Dienste laufen nie als root",
  und sie ist so klein wie möglich gehalten.** Einhängen und die LED darf
  nur root. Alles, was Dateien anfasst, läuft per `setpriv` als Benutzer des
  Servers — liest root im Backup-Ordner, genügt ein Symlink auf
  `/etc/shadow`, und die Datei landet auf dem Stick. Deshalb liegt
  `usb-kopie.sh` unter `/usr/local/lib/pi-mcs/` (nicht im beschreibbaren
  Backup-Ordner), und deshalb stehen solche Dateien in `lib/dateien.sh` in
  einer **eigenen** Liste (`mcs_systemdateien`). Wer dort etwas ergänzt,
  fragt zuerst, ob es als root laufen muss.
  > **Und die `mcs.conf` bekommt ein root-Dienst NIE als `EnvironmentFile=`**
  > — auch wenn alle anderen Einheiten es so machen. Sie gehört dem
  > Benutzer, und ihre Variablen landen in der Umgebung des root-Prozesses:
  > `BASH_ENV=/home/pi/x.sh` oder `LD_PRELOAD` genügen für root-Rechte,
  > `MCS_USER=root` hebelt den Wechsel per `setpriv` aus, ein LED-Name mit
  > `../` schreibt irgendwo unter `/sys`. Der erste Entwurf vom 22.10.2026
  > tat genau das; eine Sicherheitsprüfung fand es vor der
  > Veröffentlichung. Seither liest `usb-kopie.sh` drei Schlüssel selbst
  > (`conf_lesen`, jeder gegen ein Muster), vertraut nur `MCS_USER` und
  > `MCS_CONF` aus seiner Einheit (die root gehört, `deploy.sh` setzt sie
  > ein), weist `MCS_USER` mit UID 0 ab und gibt dem Datei-Teil eine
  > geleerte Umgebung (`env -i`) mit.
- **Ausgelöst werden die Kopien über `mcs_backup/.neuestes-backup`, nicht
  über `OnSuccess=`.** Ein Backup entsteht auf drei Wegen (Timer, `mcs
  backup`, Knopf in der Oberfläche), und nur der erste läuft über systemd.
  Die Datei schreibt das Backup-Skript ganz am Ende, nach der Rotation; die
  `.path`-Einheiten warten darauf. Wer am Ende des Backup-Skripts etwas
  ergänzt, setzt es **vor** diese Zeile.
- **`sed … datei | head` auf eine Datei, die es noch nicht gibt, reißt unter
  `set -e` und `pipefail` das Skript ab** — sed endet mit 2, und das gilt
  auch in `X=$(…)` und in `${X:-$(…)}`. Am 22.10.2026 fand
  `tests/pruefung-kopien.sh` so, dass die Cloud-Kopie beim **ersten** Lauf
  nie einen Stand schrieb: Sie wollte einen alten Wert lesen, den es noch
  nicht gab. Gelesen werden solche Dateien seither mit `awk` und vorheriger
  Prüfung, ob sie existieren. Dieselbe Familie wie die SIGPIPE-Falle oben:
  Der Exit-Status einer Pipe ist eine Behauptung.
- **Ein Vergleich direkt nach dem Schreiben liest den Arbeitsspeicher, nicht
  den Stick.** Die USB-Kopie liest deshalb mit `dd iflag=direct` zurück (am
  22.10.2026 an exFAT und FAT32 gemessen, beide können es) und vergleicht mit
  `cmp`. Das fängt auch Sticks, die mehr Speicher vorgeben, als sie haben.

## Trennung von Vorlage und Installation

Was der Installation gehört, wird nie überschrieben: `mcs.conf` (im Repo nur
`mcs.conf.beispiel`), `plugins.txt` (nur `.beispiel`), und in
`server.properties` die instanzspezifischen Schlüssel `level-name`, `motd`,
`server-port` und seit dem 02.09.2026 `enable-command-block`. Ohne diesen
Schutz stellte ein Ausrollen die Welt auf `world` um — die vorhandene bliebe
liegen, der Server öffnete sie aber nicht mehr.

`enable-command-block` ist dabei die Erweiterung des Begriffs: Die ersten
drei beschreiben, **wo** eine Installation steht. Der vierte beschreibt,
**wie gespielt wird** — und das entscheidet der Betreiber, nicht die
Vorlage, genau wie beim Spielmodus. Solange er nicht markiert war, hätte
ein `--konfig-uebernehmen` bei gestopptem Server die Befehlsblöcke
abgeschaltet: kein Ausrollschritt, sondern ein Eingriff ins Spiel.

**Markiert werden sie seit 2026-08-31 in der Vorlage selbst**, mit der Zeile
`# Pi-MCS: instanzspezifisch` direkt über dem Wert; `deploy.sh` liest die
Liste daraus. Vorher stand sie dort als feste Zeichenkette — und musste
zweimal von Hand nachgezogen werden, beide Male erst *nachdem* es beinahe
schiefgegangen war. Wer jetzt einen solchen Wert hinzufügt, sieht die
Markierung der Nachbarn. Findet `deploy.sh` keine einzige, bricht es ab:
Eine leere Liste sähe aus wie „nichts zu schützen" und wäre das Gegenteil.

**Weicht eine Vorlage dauerhaft von der Installation ab, ist meist die
Vorlage falsch** — außer bei genau diesen instanzspezifischen Werten.
Dauerrauschen macht echte Abweichungen unsichtbar.

Und umgekehrt: **Tut die Vorlage mehr als die Installation, ist das kein
Beweis, dass sie es besser tut.** Erst lesen, warum die Installation weniger
tat.

## Prüfen, bevor etwas abgegeben wird

```bash
make                        # Syntax, pyflakes, shellcheck, Konfigvorlagen
bash tests/abnahme.sh       # volle Installation in einem ARM64-Container
```

**`make` prüft kein JavaScript — dafür gibt es hier keinen Interpreter.**
Am 2026-09-02 hat ein `*/` zu viel den kompletten `<script>`-Block der
Kartenseite abgeschaltet: kein Rahmen, kein Link, keine Fehlermeldung, und
beide Prüfungen blieben grün. Seither zählt `make` wenigstens `/*` gegen
`*/` in den Vorlagen. Wer an einem Skriptblock arbeitet, prüft ihn zusätzlich
im **Browser** — dass die richtigen Zeichenketten im Quelltext stehen, sagt
nichts darüber, ob er läuft.

`make` überspringt `pyflakes`, wenn es fehlt, und sagt das deutlich — ein
grünes `make` ohne pyflakes sagt **weniger** als die GitHub Action. Genau so
ist einmal ein ungenutzter Import auf `main` gelandet.

**Der Abnahmetest wurde am 01.09.2026 an zwei Stellen repariert — beide
ließen ihn grün melden, wo er es nicht war.**

Erstens: **Er endete mit dem Rückgabewert des letzten `echo`, also immer 0.**
Die beiden Installationsläufe wurden nur als Zahl ausgegeben. Ein
fehlgeschlagener Lauf hat den Test damit **nie** rot gemacht — aufgefallen
ist es, als eine Änderung an `install.sh` den *zweiten* Lauf brach (eine
Variable, die nur im `else`-Zweig gesetzt war, unter `set -u`; der erste Lauf
nahm den anderen Zweig und ging durch). Im Protokoll stand „Lauf 2 Exitcode:
1", und der Test meldete Erfolg. Merksatz: **Ein Fehler, den nur der
Wiederholungslauf zeigt, findet nur ein Test, der auch beim zweiten Lauf rot
wird.**

Zweitens: **Ein grüner Abnahmetest kann trotzdem nichts geprüft haben.** Die
Python-Blöcke darin laufen als `su … python3 - <<PYTEST`; stirbt einer mit
einer Ausnahme, steht der Traceback zwar im Protokoll, aber der Lauf gilt
weiter als bestanden. Am 01.09.2026 gefunden: Zwei Blöcke waren seit der
Vollprüfung tot — eine `service_state`-Attrappe ohne den inzwischen
hinzugekommenen Parameter `frisch`, und ein Aufruf von
`routen._geheimnisse_verdecken`, das mit seinem Endpunkt entfernt worden war.
Damit prüfte der Test **die Vormerkung und die Verdeckung des RCON-Passworts
zwei Etappen lang überhaupt nicht** — und meldete Erfolg. Wer den Test
ändert, liest die Ausgabe auf `Traceback` durch; der Rückgabewert allein
sagt es nicht. Und wer eine Signatur ändert, sucht nach ihren **Attrappen**,
nicht nur nach ihren Aufrufern.

Drittens (2026-09-22/23): **Eine Inhaltsprüfung zählt nur, wenn eine Wache sie
liest.** `tests/abnahme.sh` hat seither drei: `Traceback` im Protokoll, das
Wort `FEHLER` (fest vorgegebene Formen) und `tests/muss-zeilen.py`, das
jede Zeile `Wert (muss X sein|bleiben[, Nachsatz])` vergleicht. Wer eine
Prüfung hinzufügt, schreibt sie in einer dieser Formen — eine nackte
Ausgabe `… : True` wird von **keiner** gelesen (am 23.09. waren es 35).
Überschriften (`--- … ---`) werden nicht verglichen; die Prüfung gehört in
eine eigene Zeile darunter.

**`Done (` im Log heißt nicht, dass der Server läuft — und schon gar nicht,
dass er bereit ist.** Zwei getrennte Fallen, beide am 01.09.2026 gemessen:

- Paper leert `latest.log` beim Start nicht sofort. Wer nach dem **zweiten**
  Start darin nach `Done (` sucht, findet das des **ersten** und meldet
  Erfolg nach einer Sekunde. Also die alte Datei vorher wegräumen.
  `tests/abnahme-im-container.sh` tut das seit jeher an seiner zweiten
  Startstelle und sagt dort auch warum — `tests/messung-im-container.sh` tat
  es nirgends. Wieder **zweiter Weg zur selben Sache ohne die Regel des
  ersten**, und diesmal in genau den Werkzeugen, die solche Fehler finden
  sollen.
- Und selbst ein echtes `Done (` heißt nur „oben", nicht „nimmt Befehle an".
  Wer danach sofort über RCON misst, bekommt `Connection refused` — und
  schreibt eine Fehlermeldung als Messwert auf. Für alles, was RCON braucht,
  erst auf eine Antwort warten (`rcon_bereit`).

Der Schaden war beide Male derselbe: Die Messung lief gegen einen Server, den
es nicht gab, und der Auswertungssatz darunter hätte daraus einen Befund
gemacht. **Eine Messung ohne Prüfung ihrer Voraussetzung ist keine Messung.**

**Was der Container nicht kann:** systemd läuft dort nicht als PID 1,
`systemctl` ist ein Platzhalter. Autostart, Neustartverhalten, Abstürze und
alles rund um `enable`/`disable` lassen sich nur auf echter Hardware prüfen.
Die Liste dafür ist `PRUEFEN-AUF-DEM-PI.md`; Ergebnisse gehören mit Datum
dort hinein.

Ein zweiter Lauf der Installation muss durchlaufen, ohne etwas zu verändern
oder zu zerstören.

## Was nicht ins Repository gehört

Dieses Repository soll öffentlich werden und auf einem **fremden** Pi
laufen. Deshalb gehört hier nichts Instanzspezifisches hinein: keine echten
Spielernamen, UUIDs oder IP-Adressen, keine LAN- oder Tailscale-Adressen,
kein Weltname, keine abweichenden Portnummern, keine Token. Platzhalter
beweisen in Messbelegen dasselbe.

Das gilt auch für die **Historie**: Ein Platzhalter nur im Endstand hilft
nicht, weil `git show <commit>` jeden alten Stand hergibt.

Geheimnisse stehen nie in `mcs.conf` (die liest Shell, Python *und* systemd
und hat entsprechend offene Rechte), sondern in eigenen Dateien mit
`chmod 600` — `dns.env`, `ntfy.env`, `admin/.env`. Wer einen Editor für eine
Konfigurationsdatei baut, muss vorher fragen, ob dort ein Geheimnis stehen
kann. Die maßgebliche Liste steht **je Datei** in `admin/konfig.py`
(`DATEIEN` → `"geheim"`) und deckt properties *und* YAML ab. Bis zum
2026-08-31 gab es daneben eine zweite, schwächere in `admin/routen.py`; sie
ist mit dem Endpunkt verschwunden, der sie benutzte.
> **Die Liste veraltet mit jeder Minecraft-Version.** Minecraft 1.21.9
> brachte `management-server-secret` (40 Zeichen, von niemandem
> eingetragen, also vom Server erzeugt) und
> `management-server-tls-keystore-password`. Beide
> zeigte der Editor bis zum 21.10.2026 im Klartext, weil die Prüfung vom
> 28.08. älter war. Nach einem Versionswechsel neue Schlüssel in
> `server.properties` auf Geheimnisse durchsehen. Gemessen am 21.10.2026
> mit Paper 26.3 in einem Wegwerf-Start: Ein **geleertes**
> `management-server-secret` lässt Paper leer und startet trotzdem. Wann
> genau es eins erzeugt (vermutlich nur, wenn der Schlüssel ganz fehlt),
> ist nicht gemessen.

## Worauf es bei einer Prüfung ankommt

Nach Gewicht geordnet — ein Fehler oben ist teurer als drei unten:

1. **Datenverlust.** Alles, was Welt oder Backups berührt. Die Backup-Platte
   ist im Zweifel die einzige Kopie. Ein Archiv muss fertig geschrieben und
   *geprüft* sein, bevor die Rotation etwas löscht; ein abgebrochener Lauf
   darf nichts hinterlassen, was wie ein gültiges Backup aussieht.
2. **Stiller Ausfall.** Etwas tut nicht, was es soll, und sagt nichts. Das
   ist die teuerste Fehlerklasse dieses Projekts: Das Backup fiel einmal
   zwei Monate lang aus, ohne dass es jemandem auffiel. Verdächtig sind
   `|| true`, unterdrückte Ausgaben, `set -e` in Verbindung mit Pipes, und
   jeder Zweig, der einen Fehler zu einem Hinweis herabstuft.
3. **Zustand nach einem Abbruch.** Was passiert, wenn das Skript mitten
   im Lauf stirbt — bleibt `save-off` gesetzt, eine halbe Datei liegen, ein
   Dienst in `failed`? Für Signale und Fehler gibt es `trap`.
4. **Sicherheit.** Siehe unten. Besonders: Rechte auf Dateien mit
   Geheimnissen, und ob sie *vor* dem Schreiben gesetzt werden.
5. **Erst dann Lesbarkeit und Vereinfachung** — und auch die nur, wenn sie
   Leitsatz 4 dient, nicht der Kürze wegen.

**Das Folgende ist bewusst so und kein Befund:**

- Bash, `screen` und Flask statt eines robusteren Stapels (Leitsatz 4).
- Das Passwort der Weboberfläche steht im Klartext in einer Datei mit
  `chmod 600`, nicht als Hash. Nachschlagbarkeit war wichtiger; die Bedingung
  ist ein eigenes, nirgends sonst benutztes Passwort.
- `tar.gz` statt zstd, restic oder borg: Ein Backup muss ohne Spezialwerkzeug
  zu öffnen sein.
- Deutsche Bezeichner und Meldungen.
- **Die Pixelschrift in den Kachelwerten** (`.kachel__wert` benutzt
  „Pixelify Sans"). Dass die Ziffer 5 dadurch schlechter zu lesen ist,
  stimmt und wurde gemeldet — die Schrift ist trotzdem der Charakter dieser
  Oberfläche und im Lastenheft gewollt. Wer die Werte doch lesbarer haben
  will, tauscht in `static/mcs.css` eine Zeile: `--schrift-zahl` liegt mit
  `tabular-nums` fertig daneben.
- Der RCON-Port ist offen und nur durch die Firewall gesperrt — anders geht
  es nicht, siehe oben.
- Kein Docker, kein npm, kein CDN, kein Build-Schritt.

Wer einen dieser Punkte für einen Fehler hält, hat recht — für ein anderes
Projekt. Hier sind sie abgewogen und im Lastenheft begründet.

## Sicherheit

Die Weboberfläche ist so mächtig wie ein SSH-Zugang — sie gehört ins LAN
oder hinter Tailscale, nie ins Internet. Dienste laufen nie als root, die
sudo-Regeln bleiben eng. Anmeldung über Sitzungs-Cookie mit `SameSite=Lax`
statt HTTP Basic Auth, mit einfacher Ratenbegrenzung.

**Erreichbarkeit von außen ist vom Pi selbst nicht prüfbar** (kein
NAT-Hairpinning, `lo` umgeht Firewall-Quellregeln). „Von hier aus
erreichbar" ist niemals ein Beleg — und ein Prüfergebnis darf lieber
„nicht feststellbar" sagen als etwas Falsches behaupten.

**Ein Sicherheitsheader kann im Browser-Cache veralten** (gefunden
2026-09-02 an der Kartenseite). Pl3xMap schickt `ETag` und `Last-Modified`,
aber kein `Cache-Control`; Browser rechnen sich daraus eine eigene Frist aus
und liefern die Antwort samt ihrer `Content-Security-Policy` weiter aus dem
Zwischenspeicher. Eine Änderung am Header erreicht sie dann nicht — der
Rahmen blieb weiß, und im Zugriffsprotokoll stand **nichts**, weil gar nicht
gefragt wurde.

> Daran erkennt man es: **keine Anfrage im Protokoll = Zwischenspeicher,
> eine Anfrage = Header.** Wer einen Sicherheitsheader ändert, sorgt dafür,
> dass die Antwort nicht cachebar ist (`Cache-Control: no-store`) — und
> hängt einen Stempel an die eingebettete Adresse, damit auch schon
> liegende Einträge nicht mehr getroffen werden.
