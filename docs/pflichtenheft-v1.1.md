# Pflichtenheft v1.1 — Was die Oberfläche behauptet, muss stimmen

Grundlage ist `docs/v1.1 Verbesserungen.md`: 21 Punkte, die nach der Umsetzung
des Lastenhefts beim Benutzen aufgefallen sind. Sie wurden am 01.09.2026 auf
einer laufenden Installation nachgemessen, statt sie zu übernehmen.

Das Ergebnis änderte den Zuschnitt erheblich:

- **Drei Punkte waren keine Aufgabe.** Der Neustart-Hinweis bei Plugins steht
  längst in der Oberfläche; die Logs zeigen einen kerngesunden Server; die
  fehlgeschlagene Operator-Vergabe war eine korrekt durchgereichte Antwort des
  Servers, kein Programmfehler.
- **Zwei Punkte waren Instanzpflege**, nicht Projektarbeit — sie stehen unten
  unter „Was v1.1 nicht umfasst".
- **Der Rest hat eine gemeinsame Ursache**, und die ist der eigentliche Anlass
  dieser Etappe: Die Oberfläche behauptet an mehreren Stellen etwas, das sie
  nicht weiß. Sie zeigt eine CPU-Kurve, die Rauschen ist. Sie schreibt „war
  noch nie da" über jemanden mit hunderten Stunden Spielzeit. Sie schreibt
  „unbekannt" über einen Port, dessen Besitzer sie hätte nachschlagen können.

Nach der Rangfolge in `CLAUDE.md` ist das die zweitteuerste Fehlerklasse dieses
Projekts: nicht ein Ausfall, sondern ein **stiller Ausfall** — etwas tut nicht,
was es soll, und sagt nichts. Ein Messwerkzeug, dem man nicht trauen kann, ist
schlimmer als keines, weil man ihm trotzdem glaubt.

---

## 0. Was diese Etappe voraussetzt und was sie nicht messen kann

**Voraussetzung:** Etappe D ist abgenommen (30.08.2026).

**Was der Container nicht prüfen kann** — gehört nach `PRUEFEN-AUF-DEM-PI.md`:

- Die getrennte CPU-Messung (W1). Ihr Beweis ist eine Spanne von 60 Sekunden
  bei gleichzeitig geöffneter Oberfläche; im Container gibt es weder das eine
  noch das andere.
- Das Drop-in für die Backup-Uhrzeit (W9). `systemctl` ist dort ein
  Platzhalter, ein Timer läuft nicht.
- Der Nachtrag aus den Serverprotokollen (W3) braucht gewachsene Logs. Der
  Container hat keine.

**Was hier bewusst nicht steht:** Die Beispielinstallation, an der gemessen
wurde, hatte eigene Defekte — ein Dienst, der beim Systemstart an einer fest
verdrahteten LAN-Adresse scheiterte, und ein Kartenserver, der auf einer
anderen Netzwerkkarte lauschte als der davorgeschaltete Webserver erwartete.
Beides ist Konfiguration jener Maschine und gehört in deren Dokumentation, nicht
hierher. Was Pi-MCS daraus lernt, steht in E17 und W2.

---

## 1. Entscheidungen, die diese Etappe trifft

### E16 — Sammler und Anzeige teilen sich keine Messprobe mehr

`cpu_usage_percent()` in `admin/system.py` misst die Auslastung als Differenz
zur **vorigen Messung** und hebt diese Probe in einem Modulzustand auf. Das ist
für sich richtig und war eine bewusste Verbesserung (31.08.2026: kein
`time.sleep(0,2)` mehr im Anfragethread).

Falsch ist, dass es **einen** solchen Zustand für **zwei** Aufrufer mit völlig
verschiedenem Takt gibt:

| Aufrufer | Takt | erwartet eine Spanne von |
|---|---|---|
| Metrik-Sammler (`metrik.sammler_starten`) | 60 s | einer Minute |
| Kacheln der Startseite (`teile/kacheln.html`) | 5 s | fünf Sekunden |

Ist die Oberfläche geöffnet, greift sie zwölfmal je Minute auf die Probe zu und
setzt sie dabei zurück. Der Sammler misst dann nicht seine Minute, sondern die
Restspanne seit dem letzten Seitenaufruf — mitunter Millisekunden. Über eine so
kurze Spanne ist die Auslastung beliebig.

**Gemessen am 01.09.2026** an einer Installation mit einem Spieler: 1434
Messwerte über 24 Stunden, Spanne 0,0 bis 93,6 Prozent, Mittel 14,2, **394
Sprünge über 30 Punkte** — bei durchgehend 20,0 TPS, höchstens 18,5 ms je Tick
von 50 ms Budget und keiner einzigen Warnung im Serverprotokoll.

Der Beweis, dass es Rauschen ist und keine Last, liegt in der Verteilung: Die
Ausschläge liegen **gleichmäßig über alle Minuten und alle Tagesstunden**. Echte
Last hätte ein Muster — das nächtliche Backup, die Timer der Widgets. Rauschen
hat keins.

> Das Muster dahinter ist bekannt und steht schon zweimal in `CLAUDE.md`:
> **ein zweiter Weg zur selben Sache, der die Regel des ersten nicht kennt.**
> Der Kommentar der Funktion verteidigt das geteilte Verhalten sogar
> ausdrücklich — *„für eine Anzeige, die alle paar Sekunden erneuert wird, ist
> das sogar das ehrlichere Mittel"*. Für die Anzeige stimmt der Satz. Für den
> Sammler ist er falsch, und niemand hat gemerkt, dass beide am selben Zustand
> hängen.

**Entschieden:** Die Probe wird je Aufrufer geführt. Zusätzlich gilt eine
Untergrenze für die Spanne — sonst kehrt derselbe Fehler zurück, sobald jemand
zwei Browserfenster offen hat.

### E17 — Wo die Oberfläche etwas nicht weiß, sagt sie das

Drei Stellen raten, statt es zuzugeben. Sie werden alle drei nach demselben
Grundsatz behandelt, und der ist Leitsatz 5: **ehrlich statt bequem.**

| Stelle | behauptet heute | weiß in Wahrheit |
|---|---|---|
| Spielerliste | „war noch nie da" | nur, dass seit Beginn des Protokolls niemand gesehen wurde |
| Portanzeige | „unbekannt" | den Port, und meist auch den Prozess dahinter |
| CPU-Kachel | eine Zahl | dass die Messspanne zu kurz für eine Aussage war |

Eine Anzeige darf „nicht feststellbar" sagen. Sie darf nicht das Gegenteil
behaupten. Das ist derselbe Satz, der in `CLAUDE.md` schon für den
Erreichbarkeitstest steht.

### E18 — Die Vergangenheit wird nachgetragen, einmalig und wiederholbar

Das Spielerprotokoll entsteht erst, seit `mcs-playerlog` läuft. Alles davor
fehlt, obwohl es in den Serverprotokollen steht: Paper schreibt jede An- und
Abmeldung nach `logs/`, und die alten Läufe liegen dort gepackt.

**Entschieden:** Ein Werkzeug in `tools/` liest sie aus und trägt die früheren
Besuche im Format des Spielerprotokolls nach. Es muss **wiederholbar** sein —
zweimal laufen darf nichts verdoppeln —, und es muss ohne Argumente
funktionieren, weil es sonst niemand benutzt.

> Das Werkzeug gehört ins Repository, **seine Ausgabe nicht**: Im
> Spielerprotokoll stehen echte Namen und Heimnetzadressen. Wer einen Messbeleg
> braucht, nimmt Platzhalter.

### E19 — Die Version der Installation ist etwas anderes als die des Repos

Der Wunsch war, die Version sehen zu können. Die naheliegende Umsetzung — eine
Zahl im Quelltext, angezeigt in der Fußzeile — beantwortet aber die falsche
Frage. Interessant ist nie, welche Version das Repository hat, sondern
**welcher Stand tatsächlich ausgerollt ist.**

Diese Unterscheidung ist in diesem Projekt schon zweimal teuer gewesen: Eine
Einheitendatei sagte etwas anderes als die Installation
(`systemctl show … -p WantedBy`), und eine Vorlage sagte etwas anderes als die
Live-Konfiguration. Beide Male war die Datei überzeugend und falsch.

**Entschieden:** Eine `VERSION` im Wurzelverzeichnis ist die einzige Wahrheit
der Vorlage. `deploy.sh` und `install.sh` schreiben beim Ausrollen fest, welcher
Stand angekommen ist. Die Oberfläche zeigt **den zweiten** Wert, und wenn beide
auseinanderlaufen, sagt sie das.

### E20 — Die Backup-Uhrzeit wird als Drop-in geschrieben

Die Uhrzeit steht in `mcs-backup.timer` und lässt sich nur dort ändern —
`OnCalendar` liest systemd nicht aus einer `EnvironmentFile`, die `mcs.conf`
scheidet also aus.

Die Einheitendatei selbst zu ändern wäre falsch: `deploy.sh` ersetzt sie beim
nächsten Ausrollen, und die eingestellte Zeit wäre stillschweigend wieder 04:00.
Genau dieses Muster — eine Einstellung, die ein Ausrollen unbemerkt zurücksetzt
— ist der Grund für den ganzen Abschnitt „Trennung von Vorlage und
Installation" in `CLAUDE.md`.

**Entschieden:** `/etc/systemd/system/mcs-backup.timer.d/zeit.conf`. Das Drop-in
gehört der Installation, die Einheit der Vorlage. `deploy.sh` fasst es nicht an.

### E21 — Kein zusätzliches sudo für die Portanzeige

`ss -ltnp` nennt den Prozess hinter einem Port nur dann, wenn er dem fragenden
Benutzer gehört. Die Oberfläche läuft als `pi`; Dienste wie der Webserver oder
`sshd` laufen als `root` und blieben damit namenlos.

Der bequeme Weg wäre eine sudo-Regel. Er wird nicht genommen: Die
Weboberfläche ist ohnehin so mächtig wie ein SSH-Zugang, und jede weitere
Ausnahme macht diesen Satz wahrer. Die Anzeige sagt stattdessen „von einem
anderen Benutzer" — das ist weniger Auskunft, aber keine falsche.

### E22 — Die Pixelschrift bleibt

Gemeldet wurde, dass die Ziffer 5 in den Kacheln schwer zu lesen ist. Das
stimmt und hat eine klare Ursache: `.kachel__wert` benutzt „Pixelify Sans", eine
Pixelschrift, während direkt daneben eine Ziffernschrift mit `tabular-nums`
bereitliegt.

**Trotzdem bleibt es so.** Die Pixelschrift ist der Charakter dieser Oberfläche
und im Lastenheft gewollt. Der Punkt wandert damit dorthin, wo er hingehört: zu
den bewussten Entscheidungen, nicht zu den Befunden. Wer die Kachelwerte später
doch lesbarer haben will, tauscht in `static/mcs.css` eine einzige Zeile — die
Alternative steht als `--schrift-zahl` fertig daneben.

---

## 2. Arbeitspakete

### W1 — Die CPU-Messung trennen

`admin/system.py`: Die Probe wird je Aufrufer geführt statt einmal für alle.
Der Sammler misst damit wieder seine volle Minute, die Kacheln ihre fünf
Sekunden, und keiner stört den anderen.

Dazu die Untergrenze aus E16: Liegt zwischen zwei Proben desselben Aufrufers
weniger als eine Sekunde, wird kein Wert erfunden. Was die Oberfläche in dem
Fall zeigt, ist eine Entscheidung von E17 — den vorigen Wert, erkennbar als
solchen, statt einer frischen Zufallszahl.

`admin/metrik.py` ruft die Messung mit dem eigenen Aufrufernamen auf.

**Altdaten:** Die CPU-Spalte in `metrik.db` ist bis zur Umstellung Rauschen und
wird verworfen — die Spalte auf `NULL`, die Zeilen und alle übrigen Werte
(RAM, Platte, Temperatur, TPS, mspt, Spielerzahl) bleiben unangetastet. Das
Vorgehen dabei ist die Regel aus `CLAUDE.md`: **erst prüfen, dann löschen.**
Vor dem Schreiben eine Sicherung der Datei, und wenn die nicht angelegt werden
kann, wird nichts geändert.

**Prüfbar durch:** Eine Stunde Sammeln bei geöffneter Oberfläche. Vorher lagen
über 20 Prozent der Werte über 40; danach muss die Kurve dem entsprechen, was
`uptime` und `top` im selben Zeitraum sagen.

### W2 — Die Portanzeige sagt, was sie weiß

`admin/konfig.py`, `offene_ports()`: Die Zuordnung kennt heute vier Ports —
Spielserver, RCON, SSH, Weboberfläche. Alles andere fällt auf „unbekannt".

Das bleibt im Kern richtig: Eine feste Liste weiterer Ports wäre falsch, weil
sie instanzspezifisch ist. Ergänzt wird stattdessen:

1. Der **Prozessname** aus `ss -ltnp`, wo er ohne sudo lesbar ist (E21).
2. „von einem anderen Benutzer", wo er es nicht ist.
3. Ein **Hinweis bei fest verdrahteten Adressen.** Die Funktion unterscheidet
   heute nur „auf allen Netzwerkkarten" von „nur *dieser* Adresse". Der zweite
   Fall ist genau dann eine Zeitbombe, wenn diese Adresse per DHCP vergeben
   wird: Beim nächsten Systemstart kann der Dienst nicht binden und stirbt —
   und zwar bevor irgendetwas davon in einer Weboberfläche sichtbar wäre.

Punkt 3 ist die Lehre aus der Instanzreparatur (Abschnitt 0) und der einzige
Teil davon, der ins Projekt gehört. Er kostet wenige Zeilen: Die Adresse ist
bekannt, und ob sie dynamisch vergeben wurde, steht in `ip -4 addr`.

### W3 — „Zuletzt gesehen" stimmt oder sagt, dass es fehlt

Zwei Teile, die zusammengehören.

**Teil 1, `tools/`:** Ein Werkzeug liest `logs/*.log.gz` und `logs/latest.log`
und trägt die dort verzeichneten An- und Abmeldungen im Format des
Spielerprotokolls nach (E18). Wiederholbar, sortiert, ohne Dubletten.

> Achtung bei der Umsetzung: Gepackte Protokolle und `set -o pipefail` sind in
> diesem Projekt bereits einmal aufeinandergestoßen. Ein `… | grep -q` endet
> mit 141, sobald grep vor dem Erzeuger fertig ist — und erst ab einer gewissen
> Dateigröße, im Container also oft nie. Die Regel steht in `CLAUDE.md`.

**Teil 2, `admin/spieler.py`:** `alle()` unterscheidet künftig **drei**
Zustände statt zwei:

| Zustand | wann | Anzeige |
|---|---|---|
| nachweislich nie da | keine Statistikdatei zur UUID | „war noch nie da" |
| nicht aufgezeichnet | Statistikdatei vorhanden, kein Protokolleintrag | „vor dem TT.MM.JJJJ nicht aufgezeichnet" |
| bekannt | Protokolleintrag | Datum |

Der mittlere Fall ist der, der heute fehlt — und der Grund, warum die Anzeige
falsch war. Das Datum darin ist der Beginn des Protokolls, nicht der Tag der
Installation: Nur das Protokoll weiß, ab wann es etwas weiß.

**Gemessen am 01.09.2026:** Die Spielzeiten waren durchgehend korrekt (die
Statistikdateien werden am richtigen Ort gelesen). Falsch war ausschließlich
„zuletzt gesehen" — bei vier von fünf Spielern leer, darunter einer mit über
500 Stunden.

### W4 — Leerlauf-Anzeige auf der Startseite

Neben die CPU-Kachel kommt, ob der Server gerade **arbeitet oder leerläuft**:
Spielerzahl und Millisekunden je Tick, gegen das Tickbudget gestellt.

Der Zweck ist nicht Schmuck, sondern eine Antwort: Wer eine hohe CPU-Zahl sieht,
will als Nächstes wissen, ob sie vom Spielserver kommt. Heute steht diese
Auskunft auf einer anderen Seite. Beide Werte liegen bereits vor — TPS und mspt
holt der Sammler ohnehin über RCON.

Kein zusätzlicher RCON-Verkehr: Leitsatz 1 gilt, eine Abfrage je Klick ist
richtig, eine je Sekunde nicht.

### W5 — Die automatische Aktualisierung dimmt nicht mehr

`static/mcs.css`: `.htmx-request` setzt heute jedes ladende Element auf 55
Prozent Deckkraft. Für einen Klick ist das die richtige Rückmeldung. Die
Kacheln aktualisieren sich aber alle fünf Sekunden von selbst — dort hat niemand
geklickt, und es gibt nichts zurückzumelden. Sichtbar ist es als regelmäßiges
kurzes Grauwerden.

Die Regel wird auf benutzerausgelöste Elemente eingegrenzt. Behälter mit
`hx-trigger="every …"` sind ausgenommen.

### W6 — Versionsanzeige

Nach E19: `VERSION` im Wurzelverzeichnis, `install.sh` und `deploy.sh` halten
den ausgerollten Stand fest, die Oberfläche zeigt ihn in der Fußzeile und meldet
eine Abweichung zur Vorlage.

`deploy.sh` braucht dafür — wie alles Neue — eine **eigene** Abfrage. Eine
Sammelbedingung lässt später Hinzugekommenes liegen; auch das steht so in
`CLAUDE.md` und ist dort mit einem Vorfall belegt.

Diese Etappe schließt mit `VERSION` = `1.1`.

### W7 — Operator-Stufe festlegen  *(erst messen)*

**Der Weg dahin ist ungemessen, deshalb steht hier noch keine Lösung.**

Bekannt ist: Die Stufen stehen in `ops.json`, und die schreibt Paper aus dem
Arbeitsspeicher — dieselbe Falle wie bei `server.properties`. Ein Vanilla-RCON
kennt kein Kommando, das eine Stufe setzt; `op <name>` vergibt die Vorgabe aus
`op-permission-level`.

**Zuerst zu messen** (Ergebnis nach `PRUEFEN-AUF-DEM-PI.md`, mit Datum):

1. Womit lässt sich die Stufe bei laufendem Server ändern, ohne dass Paper die
   Änderung beim nächsten Schreiben verwirft?
2. Wirkt eine Änderung an `ops.json` sofort, oder erst beim nächsten Start?
3. Verhält sich `ops.json` beim Start genauso wie `server.properties`, oder
   anders? Die naheliegende Annahme war dort schon einmal genau falsch herum.

Erst danach wird das Arbeitspaket geschrieben. Bis dahin gilt: **Nichts
Schreibendes an `ops.json`.**

### W8 — Whitelist für jemanden, der nie da war  *(erst prüfen)*

Vermutlich **bereits erfüllt**: `whitelist add` setzt keinen anwesenden Spieler
voraus, sondern einen bei Mojang existierenden Namen — der Server läuft mit
`online-mode=true` und schlägt dort nach.

Gemeldet wurde ein Fehlschlag mit *„That player does not exist"*. Das ist genau
diese Antwort, korrekt durchgereicht. `admin/spieler.py` behandelt sie richtig
als Warnung und erfindet keinen Erfolg.

Was fehlt, ist nicht Technik, sondern **eine Erklärung**: Die rohe englische
Serverantwort sagt einem Benutzer nicht, dass der Name bei Mojang nicht
existiert, dass ein Tippfehler die häufigste Ursache ist und dass Bedrock-Namen
hier grundsätzlich nicht funktionieren.

**Zu tun:** (1) prüfen, ob die Spielerseite überhaupt ein Eingabefeld für einen
noch unbekannten Namen hat, und es andernfalls ergänzen; (2) die Meldung
erklären. Ergibt die Prüfung, dass beides schon da ist, entfällt das Paket —
und das wird so aufgeschrieben, nicht stillschweigend weggelassen.

### W9 — Backup-Uhrzeit einstellbar

Nach E20 als Drop-in. `admin/backups.py` liest die Uhrzeit bereits aus der
Einheit und zeigt sie an; ergänzt wird das Schreiben.

Zu bedenken:

- Nach dem Schreiben `daemon-reload` **und** ein Neustart des Timers, sonst
  wirkt nichts. Ob es gewirkt hat, sagt `systemctl show … NextElapseUSecRealtime`
  — nicht die Datei, die man gerade selbst geschrieben hat.
- Eine unsinnige Eingabe darf den Timer nicht kaputtmachen. Vor dem Übernehmen
  mit `systemd-analyze calendar` prüfen; scheitert das, bleibt alles beim Alten
  und die Oberfläche sagt warum.
- Die Uhrzeit ist instanzspezifisch. Sie gehört nicht in die Vorlage.

### W10 — Dokumentation

Pflicht im selben Durchgang, nicht danach:

- `README.md`: Versionsanzeige, Backup-Uhrzeit, die drei Zustände der
  Spielerliste.
- `CLAUDE.md`: Die geteilte Messprobe aus E16 gehört zu den Regeln, bei denen
  das Naheliegende falsch ist — sie ist ein weiterer Beleg für „zweiter Weg zur
  selben Sache ohne die Regel des ersten". Die Pixelschrift (E22) gehört zu den
  bewussten Entscheidungen.
- `PRUEFEN-AUF-DEM-PI.md`: W1, W3, W7 und W9 mit Datum und Ergebnis.
- **Beantwortete Fragen**, die keine Arbeitspakete wurden, gehören trotzdem
  aufgeschrieben — sonst werden sie wieder gefragt:
  - Plugins wirken erst beim nächsten Serverstart. Die Oberfläche sagt es
    bereits an zwei Stellen; im README fehlt es.
  - Welche Ports an einem Router freizugeben sind und welche ausdrücklich
    **nicht** — der interne Port des Kartenservers gehört nie nach außen, er
    wird vom Webserver weitergereicht.

---

## 3. Reihenfolge

W1 zuerst, allein und mit Abstand: Solange die CPU-Kurve Rauschen ist, lässt
sich die Wirkung keiner anderen Änderung beurteilen. Danach eine Stunde messen,
bevor es weitergeht.

Dann W2, W3, W5 — die übrigen Falschaussagen. Dann W4 und W6. W9 danach, weil
es als einziges außerhalb des Projektverzeichnisses schreibt.

W7 und W8 zuletzt: Beide beginnen mit einer Messung, deren Ergebnis das
Arbeitspaket erst schreibt. Keines von beiden darf vorgezogen werden, weil es
klein aussieht.

W10 läuft nicht am Ende, sondern in jedem Schritt mit.

---

## 4. Abnahme der Etappe

1. `make` läuft durch — **mit** `pyflakes`. Ein grünes `make` ohne pyflakes sagt
   weniger als die GitHub Action, und genau so ist schon einmal ein ungenutzter
   Import auf `main` gelandet.
2. `bash tests/abnahme.sh` läuft durch.
3. Ein zweiter Lauf der Installation verändert nichts.
4. **Auf echter Hardware**, weil der Container es nicht kann:
   - Nach einer Stunde bei geöffneter Oberfläche stimmt die CPU-Kurve mit
     `uptime` überein. Keine Sprünge über 30 Punkte ohne erkennbaren Anlass.
   - Die geänderte Backup-Uhrzeit überlebt ein `deploy.sh`.
   - Das Nachtragswerkzeug zweimal laufen lassen ändert beim zweiten Mal nichts.
   - Die Oberfläche zeigt nach dem Ausrollen die Version der **Installation**.
5. Vor dem Push: Diff daraufhin ansehen, dass nichts Instanzspezifisches
   hineingeraten ist — keine Spielernamen, keine UUIDs, keine LAN-Adressen,
   kein Weltname, keine abweichenden Portnummern. Das gilt auch für Messbelege
   und für die Historie.

---

## 5. Was v1.1 nicht umfasst

**Die Reparatur der Beispielinstallation.** Ein ausgefallener Webserver, ein
Kartenserver auf der falschen Netzwerkkarte, eine Portweiterleitung am Router
und die Reste eines abgelösten DNS-Anbieters — alles Konfiguration einer
bestimmten Maschine. Sie wird dort behoben und dort dokumentiert. Ins Projekt
kommt davon nur die Lehre, und die steht in W2.

**Die Spieler-Historie (v1.2).** Wer war wann online, wie lange, und was wurde
im Chat geschrieben oder als Befehl ausgeführt. Braucht eine Datenhaltung, die
es nicht gibt, und davor zwei Entscheidungen, die dieses Pflichtenheft nicht
treffen kann: wie lange so etwas aufbewahrt wird, und wie Namen und
Chat-Inhalte behandelt werden. Ein Protokoll, das mitschreibt, was Menschen
einander schreiben, ist keine Kleinigkeit.

W3 arbeitet dieser Etappe allerdings zu: Danach reicht das Spielerprotokoll
erstmals über die ganze Lebenszeit des Servers.

> ## ✅ v1.2 ist am 21.09.2026 umgesetzt und ausgerollt.
> Die Seite „Historie" zeigt Spielzeit je Tag, die Sitzungen einzeln,
> Chat und Befehle. Belege mit Datum als **H2** in
> `PRUEFEN-AUF-DEM-PI.md`, Beschreibung im README.
>
> **Nachgetragen am 21.09.2026 — der Punkt hat einen Plan und beide
> Entscheidungen sind getroffen:**
> [`docs/superpowers/plans/2026-09-21-spieler-historie.md`](superpowers/plans/2026-09-21-spieler-historie.md).
> Aufbewahrung: `MCS_HISTORIE_TAGE`, Vorgabe `0` = unbegrenzt. Namen und
> Chat-Inhalte: `admin/historie.db` mit `chmod 600`, bleibt auf dem Pi,
> Platzhalter in jedem Messbeleg.
>
> **Und W3 selbst hat nur fünf Tage gehalten.** Am 06.09. hat logrotate
> das Spielerprotokoll geleert — es stand in `/etc/logrotate.d/pi-mcs`,
> während die Oberfläche genau diese Live-Datei liest. Etappe 1 des Plans
> behebt das; ohne sie stünde diese Etappe auf einer Datei, die
> wöchentlich geleert wird.

**Plugin-Konfiguration in der Oberfläche (v1.3).** Ein Editor für
Plugin-Konfigurationen wirft dieselbe Frage auf, die `admin/konfig.py` für die
Serverdateien schon beantwortet: **Kann in dieser Datei ein Geheimnis stehen?**
Bei mindestens einem verbreiteten Plugin ist die Antwort ja — ein Schlüssel für
einen fremden Dienst. Ohne eine Liste je Datei, wie sie `DATEIEN` bereits führt,
würde ein solcher Editor Zugangsdaten in einer Weboberfläche anzeigen.

**Nicht als Mangel zu behandeln:** die Pixelschrift in den Kacheln (E22), und
dass die Portanzeige fremde Prozesse nicht benennt (E21).
