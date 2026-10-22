# Was noch auf dem Pi geprüft werden muss

Diese Liste sammelt alles, was sich **nur auf echter Hardware** prüfen lässt
und deshalb im automatischen Abnahmetest offenbleibt.

**Warum der Container das nicht kann:** `tests/abnahme.sh` läuft in einem
ARM64-Debian-Container, in dem systemd **nicht als PID 1** läuft. `systemctl`
ist dort ein Platzhalter, der Aufrufe protokolliert und Erfolg meldet. Damit
lassen sich Autostart, Neustartverhalten, Abstürze und alles rund um
`enable`/`disable` grundsätzlich nicht nachstellen. Die Dienstdateien selbst
prüft dafür `systemd-analyze verify` — aber ob sie im Betrieb das Richtige
tun, zeigt erst der Pi.

Abgehakte Punkte bitte hier eintragen (Datum + Ergebnis), damit der Stand
nachvollziehbar bleibt.

> ⚠️ **Diese Datei liegt in einem Repository, das öffentlich werden soll.**
> (Am 30.08.2026 nachgesehen: Es ist derzeit noch privat — anonym antworten
> API und HTML-Seite mit 404. Das ist ein Aufschub, keine Entwarnung: Ab dem
> Umschalten ist jeder Commit der Historie mit `git show` lesbar, auch die
> alten.) Messwerte gehören hier hinein, personenbezogene Angaben nicht:
> **keine echten Spielernamen, keine UUIDs, keine IP-Adressen von
> Mitspielern.** Sie
> beweisen nichts, was Platzhalter nicht genauso beweisen — die Beweiskraft
> steckt in den Zahlen und in der Kette, nicht in der Identität.
> Am 29.08.2026 standen hier vier echte Namen samt Spielzeiten und die
> Heimnetzadresse eines Mitspielers; sie sind vor dem ersten Push durch
> „Spieler A" bis „Spieler E" und `192.168.x.y` ersetzt worden. Ein Push
> ist nicht zurückzunehmen — Forks, Klone und Caches bleiben.
>
> **Nachgezogen am 31.08.2026:** Die Regel galt bis dahin nur für Personen,
> nicht für die Installation. Ersetzt wurden deshalb zusätzlich der echte
> Weltname (37×, jetzt `MeineWelt`), der echte Serverport (3×, jetzt
> `25570`) und der echte DynDNS-Name (1×, jetzt `meinserver.dedyn.io`) — in
> dieser Datei, im Lastenheft und in der Entwurfsnotiz. Sie beweisen
> dasselbe wie vorher. **Offen bleibt die Historie:** In den Commits davor
> stehen die echten Werte weiter, und `git show` gibt sie her. Vor dem
> Umschalten auf öffentlich ist zu entscheiden, ob die Historie neu
> geschrieben wird — das ist eine Entscheidung mit Force-Push und neuen
> Commit-Kennungen, keine Nebenbei-Änderung.

---

## Stand nach dem ersten Abnahmetag (29.08.2026)

Etappe C ist ausgerollt, alle Dienste laufen. **Achtzehn Punkte sind ganz
oder teilweise erledigt**, darunter alle mit dem höchsten Risiko: der
Hauptschalter über zwei Neustarts (A-P1), der Absturz-Neustart (P-B) und
das Zurückspielen im Ernst (C-P10). Dabei kamen **zwölf Befunde** heraus;
alle sind im Repository behoben, nichts wurde von Hand am System
zurechtgebogen.

### Was noch offen ist — und was es dafür braucht

> ⚠️ **Diese Liste ist der Stand vom 29.08.2026 und inzwischen überholt.**
> Sie steht hier, weil sie zeigt, womit dieser Abnahmetag endete — als
> *aktuelle* Liste ist sie falsch. Maßgeblich sind die **Statustabellen**
> weiter unten (⬜ = noch gar nichts, 🟡 = angefangen, äußerer Teil fehlt,
> ✅ = fertig).
>
> Auf der Beispielinstallation führt
> `/home/pi/pi-manager-status.md` unter **„Was noch offen ist — die
> Übersicht"** beide Zustände zusammen und zählt auf, was jeder Punkt
> braucht. Ein Punkt, eine Stelle.
>
> **Ein Beispiel dafür, warum das nötig ist:** Hier steht bei C-P6 „braucht
> ein paar Tage Laufzeit". Am 22.09.2026 hält `metrik.db` sieben volle Tage
> — der Blocker ist längst weg, und die Zeile behauptet weiter das
> Gegenteil.

| Punkt | Was fehlt | Braucht |
|---|---|---|
| **B-P1** | Zugriffsversuch auf 25575 | zweites Gerät im WLAN |
| **C-P2** Punkt 1 | Anmelden im privaten Fenster | Browser |
| **C-P3** | Darstellung auf dem Handy | Handy |
| **C-P6** | Kurven über sieben Tage | ein paar Tage Laufzeit |
| **C-P7** | kicken, sperren, `/stats` im Spiel | echte Spieler, Zweitkonto |
| **C-P8** | HTTPS-Zweig im Browser | Tailscale-Aufruf |
| **P-D/P-E** | Temperatur und TPS unter Last | fünf Spieler gleichzeitig |
| **P-F** | Firewall sperrt nicht aus | zweite SSH-Sitzung beim nächsten `ufw enable` |
| **D-P2** | die SD-Karten-Warnung im Original | eine SD-Karte zum Einstecken |
| **D-P4/D-P5** | nur noch die **Zustellung** aufs Handy | Handy mit der App ntfy und ein eigenes Thema |
| **D-P8** | nur noch der Verbindungsversuch **ohne Portangabe** | ein Mitspieler |
| **D-P9** | nur noch die Probe über einen echten Neustart | ein Zeitpunkt, an dem der Pi neu starten darf |
| **D-P10** | Zugriff über Tailscale | Handy mit Tailscale, im selben Tailnet |
| **D-P11** | Installation an einen anderen Ort | ein frischer Pi oder eine wegwerfbare Kopie |

**Womit anfangen:** mit **B-P1**, vom Handy im WLAN —
`nc -vz -w 3 <pi-adresse> 25575` darf **nicht** verbinden. Danach der Rest
in beliebiger Reihenfolge; keiner davon greift noch in laufende Dienste ein.

~~**Was noch herumliegt:** die beiseitegelegten Weltordner aus C-P10
(`~/mcs/mc_server/MeineWelt.vor-restore-20260829-205819`, 829 MB). Wegräumen,
sobald die Welt im Spiel begutachtet ist.~~ **Weggeräumt am 21.10.2026**,
nach sieben Wochen Spielbetrieb auf der zurückgespielten Welt.

---

## Stand nach dem zweiten Abnahmetag (30.08.2026)

Etappe D ist auf dem Pi ausgerollt (`deploy.sh`, 26 Dateien) und der Server
läuft darauf. **Von den elf D-Punkten sind sechs ganz und vier teilweise
erledigt**; was offenbleibt, braucht ausnahmslos etwas, das dieser Pi nicht
selbst hergibt — eine SD-Karte, ein Handy, einen Mitspieler, einen Neustart
oder einen zweiten Rechner.

Dabei kamen **zwei Befunde** heraus, beide im Repository behoben:

**D-B1 — `deploy.sh` aktivierte neu hinzugekommene Einheiten nicht.**
Nach dem Ausrollen von Etappe D stand:

```
systemctl is-enabled mcs-dns.timer        -> disabled
systemctl show mcs-dns.timer -p WantedBy  -> (leer)
```

als einzige der fünf Einheiten. Die Ursache ist eine Lücke zwischen den
beiden Wegen: `install.sh` aktiviert den DNS-Timer bei einer frischen
Installation **immer** („Der DNS-Timer wird IMMER eingerichtet, auch ohne
eingestellten Anbieter"), aber `deploy.sh` hängt mit `systemctl reenable`
nur um, was **schon aktiviert ist** — und eine Einheit, die es vorher gar
nicht gab, war das noch nie.

Wer also aufrüstet statt neu zu installieren — der Weg, den diese Datei
oben selbst vorschreibt —, bekam den Timer ausgerollt, aber nie aktiviert.
Der Name wäre nie nachgeführt worden, und der Fehler wäre **still**
geblieben: Ein Timer, der nicht läuft, meldet nichts. Nach `mcs an` wäre er
mangels `WantedBy` auch nicht hochgekommen.

Behoben: `deploy.sh` merkt sich, welche Dienstdateien dieser Lauf zum ersten
Mal anlegt, und aktiviert genau die — mit derselben Rücksicht wie
`install.sh` (ist PiCraft gerade aus, wird aktiviert, aber nicht gestartet).
Was schon dalag, bleibt unberührt; wer eine Einheit selbst abgeschaltet hat,
behält sie abgeschaltet. Nachgeprüft, indem die Datei entfernt und neu
ausgerollt wurde: `enabled`, `active`, `WantedBy=mcs.target`.

**D-B2 — Die Prüfanleitung zu D-P5 konnte nicht aufgehen.** Sie ließ das
Backup scheitern, indem sie das Backupverzeichnis schreibgeschützt machte
(`chmod 500`) — und erwartete danach den Merkzettel `.letzter-fehler`
**in genau diesem Verzeichnis**. Gemessen:

```
minecraft-backup.sh: line 160: .../.letzter-fehler: Permission denied
```

Das Skript verhält sich dabei richtig: `fehler_merken()` schreibt den
Merkzettel mit `|| true` und **benachrichtigt trotzdem**, lässt sich also
vom Schreibfehler nicht aufhalten. Falsch war die Erwartung. Wer dem alten
Text folgte, hätte den Merkzettel für kaputt gehalten, obwohl er funktioniert
— dieselbe Sorte Falle wie bei K3, wo ein Nullvorgang die Messung wertlos
macht. Die Anleitung unten ist neu gefasst.

### Was am 30.08. gemessen wurde

| Punkt | Ergebnis |
|---|---|
| D-P1 | `Raspberry Pi 5 Model B Rev 1.1`, 64-Bit, 8 GB, `NVMe-SSD (nvme0n1)` — deckt sich mit `findmnt` (`/dev/nvme0n1p2`) und `lsblk` (`nvme`, `ROTA=0`). **Und die USB-Falle sitzt:** Die Sicherungsplatte an `sda` meldet `rotational=1`, wird aber korrekt als „USB-Datenträger — über USB lässt sich nicht sicher sagen, ob SSD oder Festplatte" eingeordnet, nicht als Festplatte. |
| D-P3 | Beide `APT::Periodic`-Zeilen auf `"1"`, Timer mit nächstem Termin, Protokolleinträge vom 28., 29. und 30.08. `Automatic-Reboot` steht in `52unattended-upgrades-local` ausdrücklich auf `"false"`. Die Neustart-Meldung erscheint nach `touch /var/run/reboot-required` mit Paketnamen und Rat. |
| D-P5 | Die **dritte und wichtigste** Probe sitzt: mit `MCS_NTFY_SERVER=http://127.0.0.1:1` endete `mcs backup` mit **Exitcode 0**, das Archiv entstand und wurde geprüft (710 MB). Ein Backup scheitert nicht an der Benachrichtigung. Fehlschlag und Entwarnung siehe unten. |
| D-P6 | Urteil stimmt mit der Wirklichkeit überein: „von außen kommt niemand an" — die Router-Weiterleitung ist seit dem 24.07.2026 tot. Der Test behauptet **nicht** DS-Lite, sondern nennt beide möglichen Ursachen und sagt, wie man sie unterscheidet. `--lokal` zeigt korrekt **keine** öffentliche Adresse. |
| D-P7 | `mcs-dns.service` läuft sauber durch (`Finished`, kein `226/NAMESPACE`); `ReadWritePaths`, `EnvironmentFile` und `ExecStart` zeigen auf den echten Ort. Der Timer-Pfad (ohne Argument) **schweigt bei unveränderter Adresse** und schreibt keine zweite Logzeile. |
| D-P8 | `dig +short _minecraft._tcp.<name> SRV` → `0 5 <port> <name>.` — richtiges Format, Punkt am Ende, und der Port stimmt mit dem in der echten `server.properties` überein. Auch direkt bei `ns1.desec.io` gegengeprüft, also nicht nur aus einem Zwischenspeicher. |
| D-P9 | `mcs-dns.timer`: `enabled`, `active`, `WantedBy=mcs.target`, `PartOf=mcs.target` — jetzt verdrahtet wie die vier anderen Einheiten. Die Probe über einen echten Neustart steht noch aus. |
| D-P11 | Der auf einer bestehenden Installation prüfbare Teil sitzt: `installationsort_erfragen()` kehrt bei vorhandener `mcs.conf` sofort zurück (`install.sh`, `[ -f "$MCS_CONF" ] && return 0`) — ein zweiter Lauf kann gar nicht erneut fragen. |
| B-P1 | Soweit vom Pi aus prüfbar erledigt: RCON lauscht tatsächlich auf `*:25575` (belegt K1 erneut), und die `DENY`-Regel steht in **v4 und v6**, mit zwei Treffern im echten `nft`-Regelwerk. Der Zugriffsversuch von außen bleibt offen. |

**Nebenbei mitgenommen:** `pyflakes` fehlte auf dem Pi, worauf `make` selbst
hinweist — ein grünes `make` sagte damit weniger als die GitHub Action, und
genau so ist am 29.08. ein ungenutzter Import auf `main` gelandet. Nachgeholt
(`pyflakes3`); `make` ist jetzt vollständig grün.

### Die zwölf Befunde vom 29.08.

| # | Wo | Was |
|---|---|---|
| 1 | `deploy.sh` | `[Install]`-Änderungen wurden nie wirksam — der Hauptschalter wäre beim Neustart wirkungslos gewesen |
| 2 | `install.sh` | Backup-Timer wurde `enable`d, aber nicht gestartet — bei entferntem Cronjob lief **gar kein Backup** |
| 3 | `install.sh` | `sudo -v` verlangt ein Terminal — `--standard` war ohne Terminal unbenutzbar |
| 4 | `deploy.sh` | `server-port` fehlte in `INSTANZ_SCHLUESSEL` |
| 5 | `install.sh` | trug noch die von K3 widerlegte Begründung |
| 6 | `install-admin.sh` | meldete einen Ausweichport, den sie gar nicht verwendete |
| 7 | `seite_karte.py` | las die Bindeadresse nicht — toter Rahmen und toter Knopf |
| 8 | Lastenheft / `CLAUDE.md` | K3 präzisiert: Paper schreibt nur bei **echter** Änderung neu |
| 9 | `tools/mcs` | **`mcs restore` fand die Welt nicht, die im Archiv lag** — `tar \| grep -q` endet unter `pipefail` an SIGPIPE. Das Zurückspielen war unmöglich (C-P10) |
| 10 | `lib-konsole.sh` | eine **tote** Screen-Sitzung galt als laufender Server: `mcs stop` wartete 240 s, warnte falsch vor Datenverlust, endete in `failed` — und `mcs restore` verweigerte sich nach jedem Absturz (P-B) |
| 11 | `spieler.py` | Statistiken wurden in `<welt>/stats/` gesucht, liegen aber seit der Formatumstellung in `<welt>/players/stats/` — **die Spielzeit war für alle leer** (C-P7) |
| 12 | Prüfliste selbst | `pkill -9 -f paper.jar` killt die eigene Shell; P-C suchte „Saving worlds", das Paper 26.2 nicht mehr schreibt; C-P6 maß `metrik.db` statt `metrik.db*` (WAL) |

> **Die Lehre aus 9, 10 und 11:** Alle drei brauchten **echte Größe** oder
> **echte Geschichte**, um überhaupt aufzutreten — ein 710-MB-Archiv, einen
> wirklichen Absturz, eine gewachsene Welt im neuen Format. Im Container
> war jeder von ihnen unsichtbar, und zwei davon hätten erst im Ernstfall
> zugeschlagen. Genau dafür gibt es diese Liste.

Dazu korrigiert: `/home/pi/CLAUDE.md` (falsche Angabe zum Vorlagen-Port, dazu
K1/K3/K4/K7 ergänzt — die Aufgabe aus Pflichtenheft C, Zeile 703, war liegen
geblieben) und `/home/pi/pi-manager-status.md` (Cron→Timer, RCON,
`minecraft-modus` gelöscht, `plugins.txt`-Regel umgekehrt).

> **Noch beiseitegelegt:** Die DuckDNS→deSEC-Umstellung im Repository liegt in
> `git stash` (`stash@{0}`, angelegt 29.08.). Sie kollidiert an sechs Stellen
> in der `README` und bei `tools/duckdns.sh` mit Etappe A (`c0ae8f8`). Der
> **laufende** deSEC-Betrieb hängt nicht daran — der Cron nutzt
> `~/desec/update.sh` und lief durchgehend weiter.

---

## Stand nach der Vollprüfung (31.08.2026)

Eine Prüfung des ganzen Repositorys (Ultra-Review über zehn Prüfwinkel plus
Abgleich gegen die Leitsätze): **18 belegte Befunde, alle behoben.** `make`
und `tests/abnahme.sh` laufen danach grün — auf `main` selbst nachgemessen,
der Abnahmetest auch im zweiten, unverändernden Lauf.

> Die Arbeit lief auf einem eigenen Branch `vollpruefung`, der gegen eine
> leere Basis aufgesetzt war. Er ist am 01.09.2026 als Commit `e215788` auf
> `main` übernommen und danach samt `pruefbasis` gelöscht worden — beide
> Bäume waren zu diesem Zeitpunkt bitgleich mit `main`, es ging nichts
> verloren. **`main` ist seither der einzige Branch.**

**Vorab gemessen, und es ändert die Einordnung:** Keiner der vier
gefährlichsten Befunde war auf diesem Pi scharf. Es waren Fehler im Code,
keine akuten Fehler am System — kein `mcs.conf`-Wert enthielt ein
Leerzeichen, beide Zähler standen auf `10`, das Admin-Passwort ist ASCII.
Ohne diese Messung wäre aus einem Repo-Befund ein Systemalarm geworden.

Die Befunde hatten fast alle **dieselbe Gestalt**: eine Regel, die auf einem
Weg sauber durchgesetzt wird und auf einem zweiten Weg zur selben Datei
fehlt — `konfig.py` gegen `routen.py`, `konsole.py` gegen `lib-konsole.sh`,
`install.sh` gegen `deploy.sh`. Wer künftig eine Regel prüft, prüft sie an
**allen** Wegen zur Datei.

Die schwerwiegendsten, mit dem Beleg der Behebung:

| # | Was | Behoben durch | Nachgemessen |
|---|---|---|---|
| 01 | Ein Leerzeichen im Zweitziel tötete jedes Backup lautlos (vor `trap` und Merkzettel) | `wert_fuer_mcs_conf()` / `mcs_conf_wert()`, einfache Anführungszeichen | Rundlauf schreiben → bash, systemd und Python lesen alle `/media/pi/My Passport` |
| 02 | `MCS_BACKUP_BEHALTEN=0` löschte **alle** Backups auf beiden Platten | `zahl_aus_conf()`, `0` heißt jetzt „aus" | Lauf mit `=0`: 3 alte + 1 neues bleiben liegen |
| 03 | Die Zweitkopie hatte kein `.unfertig`-Verfahren | Zwischenname, `tar -tzf`, dann `mv` | Ziel nicht beschreibbar → keine Reste, echter `cp`-Grund im Protokoll |
| 05 | `/api/server-properties` schrieb an Vormerkung und K3 vorbei | ersatzlos entfernt | Endpunkt liefert 404 |
| 10 | `MCS_ARCHIV_JEDES=0` meldete ein **gelungenes** Backup dauerhaft als Fehlschlag | dieselbe Zahlenprüfung | Lauf mit `=0`: Rückgabewert 0, kein `.letzter-fehler` |
| 11 | `mcs restore` verweigerte ein gültiges Archiv bei Regex-Zeichen im Weltnamen | wörtlicher `case`-Vergleich statt `grep`-Muster | `world[1]` wird gefunden, `world1` richtig nicht |
| 12 | Ein Umlaut im Admin-Passwort sperrte dauerhaft aus (500 statt Meldung) | Vergleich über `.encode()` | Anmeldung mit `Schlüsselwort2026` → 302, Sitzung trägt |
| 15 | Autorisierung hing an einem Dekorator je Route | `before_request`-Engpass mit Ausnahmeliste | ohne Anmeldung: alles 302 außer `/anmelden` und Statuspunkt |

**Am 01.09.2026 auf dem Pi ausgerollt und nachgemessen.** `./deploy.sh` hat
17 Dateien übernommen, keine systemd-Einheit hat sich geändert. Bedingungen:
alle Dienste aktiv, **0 Spieler online**, frisches Backup von 04:02 Uhr, kein
Fehler-Merkzettel. Der Minecraft-Server lief durch (Betriebszeit 22:54 h),
nur `mcs-admin.service` wurde neu gestartet.

- [x] **`--konfig-uebernehmen` bei laufendem Server verweigert sich.**
      Gemessen mit `--konfig-uebernehmen --probe`: „Der Minecraft-Server
      läuft — server.properties wird NICHT geschrieben", und die
      Abweichungen werden trotzdem aufgeführt. *Die andere Hälfte (mit
      gestopptem Server übernehmen) steht bewusst noch aus* — sie schriebe
      `spawn-monsters` und `enable-command-block` in die Live-Datei, und das
      ist eine eigene Entscheidung, kein Prüfschritt.
- [x] **Die `INSTANZ_SCHLUESSEL` aus der Vorlage greifen auf der echten
      Installation.** Gemeldet als „gehört dieser Installation, wird nie
      übernommen": `level-name`, `motd`, `server-port` — genau die drei.
      Daneben stehen weiterhin die zwei echten Meldungen `spawn-monsters`
      und `enable-command-block`. Kein Dauerrauschen dazugekommen.

> **Nachgemessen am 02.09.2026 — die beiden „echten Meldungen" sind nicht
> mehr dasselbe.** Ausgelöst hat es ein Serverstart am 01.09. um 20:18, bei
> dem Paper `server.properties` **vollständig** neu geschrieben hat: 71
> Schlüssel statt der 21 der Vorlage, Kopfzeile mit dem Zeitstempel des
> Starts. Danach:
>
> - **`enable-command-block` fehlt nicht mehr**, es steht jetzt mit einem
>   Wert da — und zwar mit dem *anderen* als in der Vorlage. Aus einer
>   Meldung „fehlt, Paper nimmt den Standard" ist damit eine **echte
>   Wertabweichung** geworden. Wer hier `--konfig-uebernehmen` bei
>   gestopptem Server laufen lässt, ändert eine Spieleinstellung. Das ist
>   eine Entscheidung, kein Ausrollschritt.
> - **`spawn-monsters` fehlt weiterhin — und das ist jetzt belegt, nicht
>   vermutet.** Paper hat die Datei vollständig ausgeschrieben und den
>   Schlüssel *trotzdem* nicht gesetzt. Paper 26.2 kennt ihn nicht mehr; die
>   Zeile in `server/server.properties` ist tot. Nach der Regel aus
>   `CLAUDE.md` („weicht die Vorlage dauerhaft ab, ist meist die Vorlage
>   falsch") gehört sie entfernt — sonst bleibt eine Dauermeldung stehen,
>   die nichts mehr bedeutet.
>
> **Beides ist noch am 02.09.2026 erledigt worden.** `spawn-monsters` ist aus
> der Vorlage gelöscht; `enable-command-block` ist als
> `# PiCraft: instanzspezifisch` markiert und wird damit weiter gemeldet, aber
> nie geschrieben. Der Haken oben („genau die drei") gilt seither nicht mehr:
> Es sind **vier** — `level-name`, `motd`, `server-port` und
> `enable-command-block`. Nachgemessen mit `./deploy.sh --probe` auf dem Pi:
> vier Meldungen in `server.properties`, alle vier als „gehört dieser
> Installation" ausgewiesen, keine einzige echte Wertabweichung mehr.
>
> **Nachgeschärft am selben Tag, weil die erste Messung nichts taugte.** Der
> naheliegende Griff war, die `paper.jar` nach dem Schlüsselnamen zu
> durchsuchen — null Treffer, sah nach einem Beleg aus. Die Gegenprobe mit
> `spawn-protection` und `op-permission-level`, die beide nachweislich in der
> Datei stehen, lieferte **ebenfalls null**: `paper.jar` ist ein Lader, die
> Klassen liegen komprimiert darin. Das Instrument war unbrauchbar, nicht das
> Ergebnis. Der tragfähige Beleg ist die von Paper selbst geschriebene Datei
> — 71 Schlüssel, `op-permission-level` und `spawn-protection` mitten drin,
> und **`spawn-monsters`, `spawn-animals` und `spawn-npcs` alle drei nicht**.
> Drei verschwundene Geschwister sind eine Entfernung, einer wäre ein Zufall.
>
> **Erledigt am 02.09.2026:** `spawn-monsters` ist an allen vier lebenden
> Stellen entfernt — Vorlage, `install.sh` (der Assistent setzte es je nach
> Spielmodus), `EINSTELLUNGEN` in `konfig.py` und die Test-Vorlage. Der
> Schalter in der Oberfläche war der schlimmste davon: Er hätte geschrieben,
> Paper hätte den Wert beim nächsten Start weggeworfen, und danach stünde er
> wieder auf „aus" — eine Oberfläche, die etwas behauptet, was sie nicht
> weiß, also genau der Anlass für v1.1. An jeder Stelle steht jetzt ein
> Kommentar mit Datum und Messung, damit ihn niemand gutmeinend wieder
> einträgt. Wer keine Monster will, stellt die Schwierigkeit auf „friedlich".
>
> Merksatz: **Eine Abweichungsmeldung kann ihre Bedeutung ändern, ohne dass
> jemand etwas ändert.** Paper schreibt die Datei beim Start neu (K3), und
> aus „Schlüssel fehlt" wird dabei „Schlüssel steht auf dem anderen Wert".
> Wer die Meldungsliste einmal als „erklärt und harmlos" abgelegt hat, muss
> sie nach jedem Neustart erneut lesen, nicht abgleichen.
- [x] **Der Anmelde-Engpass wirkt an der laufenden Oberfläche.** Ohne
      Anmeldung: `/`, `/spieler`, `/konfiguration`, `/backups` und
      `/api/status` alle **302**; offen bleiben nur `/anmelden` und
      `/teil/kopfzustand` (**200**). Der entfernte Endpunkt
      `/api/server-properties` liefert **404**.
- [x] **`journalctl -u mcs-admin.service | grep -i metrik` ist leer** — der
      Sammler läuft. Ebenso keine Einträge ab Stufe `warning`.

Zusätzlich gegengeprüft: `systemctl show <einheit> -p WantedBy` liefert für
alle fünf Einheiten `mcs.target`, `mcs.target` ist `enabled` (die Regel aus
`CLAUDE.md`: die Wahrheit steht dort, nicht in der Unit-Datei). `mcs status`
und `mcs say` laufen über die neu ausgerollte `lib-konsole.sh` einwandfrei.

---

## Offen und erledigt aus v1.1 (Stand 01.09.2026)

Etappe v1.1 hat einen gemeinsamen Anlass: **Die Oberfläche behauptete an
mehreren Stellen etwas, das sie nicht weiß.** Entsprechend sind die
Prüfpunkte hier fast alle vom Typ „stimmt die Aussage jetzt".

**Am 01.09.2026 um 15:27 auf dem Pi ausgerollt.** `./deploy.sh` hat 18
Dateien übernommen (darunter erstmals `VERSION` und `admin/version.py`), die
Einheit `mcs-backup.timer` aktualisiert und die einmalige Bereinigung der
CPU-Altwerte angestoßen — 3332 Messwerte, Spalte auf `NULL`, Zeilen und alle
übrigen Werte unangetastet, Sicherung als `metrik.db.vor-cpu-bereinigung`
daneben. Bedingungen, weil sie zum Ergebnis gehören: alle fünf Dienste aktiv,
**0 Spieler online**, der Minecraft-Server lief durch; neu gestartet wurden
nur `mcs-admin.service` und `mcs-backup.timer`.

Danach: keine Journal-Einträge ab Stufe `warning` für `mcs-admin.service`,
`/anmelden` antwortet mit 200, und `mcs.conf`, `plugins.txt` sowie die drei
instanzspezifischen Schlüssel wurden erwartungsgemäß nur gemeldet, nicht
angefasst. Es bleiben dieselben neun Konfigurationsmeldungen wie bisher —
kein Dauerrauschen dazugekommen.

Vor dem Ausrollen lief `make` grün (mit pyflakes und shellcheck) und
`tests/abnahme.sh` viermal; der letzte Lauf mit Rückgabewert 0, beiden
Installationsläufen 0 und **null Tracebacks** im Protokoll.

### Nebenbefund: Der Abnahmetest selbst war an drei Stellen blind

Nicht im Pflichtenheft, aber beim Abarbeiten gefunden — und schwerer als die
meisten Punkte darunter, weil es das Werkzeug betrifft, mit dem alles andere
geprüft wird. Alle drei sind behoben.

1. **`tests/abnahme.sh` endete mit dem Rückgabewert des letzten `echo`.**
   Die Exitcodes der beiden Installationsläufe wurden nur ausgegeben. Ein
   fehlgeschlagener Lauf hat den Test damit **nie** rot gemacht. Gefunden,
   weil genau das passierte: Eine Änderung an `install.sh` brach den zweiten
   Lauf, „Lauf 2 Exitcode: 1" stand im Protokoll — und der Test meldete
   Erfolg.
2. **Eine `service_state`-Attrappe ohne den Parameter `frisch`.** Der kam bei
   der Vollprüfung dazu; die Attrappe wurde nicht nachgezogen. Der Block
   starb mit `TypeError`, und damit prüfte der Test die **Vormerkung von
   `server.properties`** nicht mehr — den Mechanismus, der Korrektur K3
   umsetzt.
3. **Ein Aufruf von `routen._geheimnisse_verdecken`,** das mit seinem
   Endpunkt entfernt worden war (Vollprüfung, Befund 05). `AttributeError` —
   und damit war **zwei Etappen lang ungeprüft, ob das RCON-Passwort im
   Editor verdeckt wird.** Die Prüfung geht jetzt gegen `konfig.py`, wo die
   maßgebliche Liste steht.

Nachgemessen nach der Reparatur: keine Tracebacks mehr im Lauf, und die
beiden zuvor toten Prüfungen liefern wieder Ergebnisse („Passwort im
Klartext ausgeliefert: nein, richtig", „beim Speichern wiederhergestellt:
True").

### W1 — Die getrennte CPU-Messung

- [x] **Der Fehler ist auf diesem Pi reproduziert.** Sammler (60 s) und
      Kacheln der Startseite (5 s) teilten sich eine `/proc/stat`-Probe; wer
      sie liest, setzt sie zurück. Über 24 Stunden: 1434 Werte, 0,0 bis
      93,6 Prozent, **394 Sprünge über 30 Punkte** — bei durchgehend
      20,0 TPS und höchstens 18,5 ms je Tick. Die Ausschläge lagen
      gleichmäßig über alle Tagesstunden; echte Last hätte ein Muster.
- [x] **Getrennte Proben greifen.** Zwölf Anzeigeaufrufe hintereinander
      lassen die Probe des Sammlers nachweislich unberührt.
- [x] **Die Untergrenze greift.** Ein zweiter Aufruf desselben Aufrufers
      innerhalb einer Sekunde liefert `frisch=False` und den vorigen Wert —
      und lässt die Probe **liegen**. Würde sie erneuert, wäre der Schutz
      wirkungslos, sobald jemand zwei Browserfenster offen hat.
- [x] **Die Altwerte sind verworfen.** `tools/cpu-altwerte-verwerfen.py`
      gegen eine Kopie: 100 Zeilen, CPU auf `NULL`, alle übrigen Spalten
      (RAM, Platte, Temperatur, TPS, mspt, Spielerzahl) unverändert, in der
      Sicherung stehen die alten Werte noch. Zweiter Lauf: „bereits erledigt",
      Datei unberührt.
      > **Das Werkzeug ist am 2026-09-02 entfernt worden.** Eine Migration ist
      > irgendwann fertig; ihre Erklärung nicht — die steht jetzt im Kopf von
      > `admin/metrik.py`, damit einordbar bleibt, was die CPU-Kurve einer
      > Datenbank von vor v1.1 wert ist. Dieser Haken bleibt als Beleg stehen.
- [x] **Nach dem Ausrollen 3,5 Stunden gesammelt (01.09.2026, 15:27–19:02).**
      Das ist mehr als die geforderte Stunde. Gegenübergestellt der Sicherung,
      die den alten Zustand konserviert:

      | | vorher (geteilte Probe) | nachher (getrennte Proben) |
      |---|---|---|
      | Werte | 3332 | 216 |
      | Spanne | 0,0 – 93,6 % | 1,1 – 47,1 % |
      | Median | 2,5 % | 1,4 % |
      | über 40 % | 333 (**10,0 %**) | 1 (**0,5 %**) |
      | Sprünge > 30 Punkte | **667** | **1** |

      **Der eine verbliebene Sprung hat einen erkennbaren Anlass:** Er liegt
      in der Minute 15:27 — genau der Minute, in der `./deploy.sh` lief. Echte
      Last, richtig gemessen. Genau das war die Bedingung („keine Sprünge über
      30 Punkte *ohne erkennbaren Anlass*").
      Gegenprobe gegen das System: `load average: 0.32, 0.14, 0.04` bei
      4 Kernen, also rund **3,5 % je Kern** im 5-Minuten-Mittel — dieselbe
      Größenordnung wie der Median von 1,4 %. Vorher lag der Median mit 2,5 %
      zwar ähnlich, aber jeder zehnte Wert über 40 %: Der Mittelwert stimmte
      ungefähr, die einzelnen Werte waren Zufall.
      *Einschränkung, damit sie nicht später als Beleg missverstanden wird:*
      Ob während dieser 3,5 Stunden durchgehend ein Browserfenster offen war,
      ist nicht festgehalten. Der Beweis der Trennung liegt deshalb im
      Abnahmetest, der sie deterministisch prüft, nicht in dieser Messung.

### W3 — „Zuletzt gesehen"

- [x] **Der Befund ist reproduziert.** Vor dem Nachtrag reichte das
      Spielerprotokoll nur bis zum 23.07.2026, während die Serverprotokolle
      bis zum 14.03.2026 zurückreichen. Drei von fünf Spielern — mit 42, 69
      und 302 Stunden Spielzeit — standen als „war noch nie da".
- [x] **Das Nachtragswerkzeug läuft und ist wiederholbar.** 206
      Serverprotokolle gelesen, 1770 Ereignisse gefunden, **1694
      nachgetragen**; das Protokoll reicht jetzt vom 14.03. bis heute.
      Zweiter Lauf: 0 nachzutragen, Datei unverändert (gleiche Prüfsumme).
      Nachgemessen: kein Eintrag des Altbestands verloren, Reihenfolge
      lückenlos aufsteigend, kein Protokolltag vor dem ältesten Archiv.
- [x] **Die Mitternachtslogik ist geprüft.** Auf diesem Pi gibt es keinen
      einzigen echten Fall, die Logik wäre also von den Daten ungeprüft
      geblieben. Deshalb synthetisch nachgestellt (Platzhalternamen): Ein
      Archiv `…-05-10-1.log.gz` mit 23:58 → 00:03 datiert korrekt auf den
      10. und 11.; eine `latest.log` mit Änderungszeit am 12.05. 00:20 und
      den Zeiten 23:50 → 00:10 auf den 11. und 12.
- [x] **Die drei Zustände stimmen gegen die echten Daten.** Vor dem
      Nachtrag: 1× `bekannt`, 3× `nicht_aufgezeichnet`, 1× `nie`. Danach:
      4× `bekannt` mit Datum, 1× `nie` — und der eine ist der, zu dem es
      **keine Statistikdatei** gibt. Genau die Unterscheidung, die gefehlt hat.
- [x] **Nebenbefund, gemessen statt angenommen:** Ein Spieler mit 42 Stunden
      erscheint erstmals am 11.04., das älteste Serverprotokoll ist vom
      14.03., seine Statistikdatei wurde zuletzt am 11.04. geschrieben. Die
      Spielzeit stammt also aus der Zeit vor den vorhandenen Protokollen.
      „erstmals" wäre dort schlicht falsch gewesen — die Anzeige sagt jetzt
      **„bekannt seit"**. (Ebenfalls aufgefallen: 12 Statistikdateien, aber
      nur 4 im `usercache.json` — abgelaufene Einträge. Kein Befund dieser
      Etappe, aber notiert.)

> ⚠️ **W3 hat nur fünf Tage gehalten — nachgemessen am 21.09.2026.**
> Am 06.09. hat logrotate das Spielerprotokoll geleert, weil es in
> `/etc/logrotate.d/picraft` stand (`weekly`, `copytruncate`). Seither
> meldete die Spielerseite wieder für **jeden** Spieler „nicht
> aufgezeichnet". Die 1694 nachgetragenen Einträge lagen unversehrt in
> `player_activity.log.2.gz` — nur eben dort, wo die Oberfläche nicht
> liest. Behoben; siehe den Abschnitt direkt unten.
>
> **Die Lehre gehört zu W3, nicht zum Folgebefund:** Eine Reparatur ist
> erst fertig, wenn geprüft ist, was sie regelmäßig wieder kaputtmacht.
> Das Nachtragen war richtig und trotzdem wirkungslos.

### H1 — Das Hauptbuch wird nicht mehr rotiert (21.09.2026)

Alles auf diesem Pi gemessen, nicht im Container.

- [x] **Der Befund ist reproduziert.** `player_activity.log` war seit dem
      13.09. 00:19 exakt 0 Byte. `spieler.alle()` lieferte für alle fünf
      Spieler `zuletzt=None`, darunter einer mit 545 h und einer mit 302 h
      Spielzeit. `protokoll_auswerten()` gab `beginn=None` zurück.
- [x] **Die Ursache ist belegt, nicht geschlossen.** Die Datei stand in
      `/etc/logrotate.d/picraft`; `.1` (613 B) und `.2.gz` (1796 Zeilen,
      14.03.–02.09.) enthielten die vollständige Historie.
      Kein Zeitzonenfehler: geschrieben Lokalzeit, gerendert Lokalzeit.
- [x] **Die Rotationsregel ist bereinigt.**
      `grep -c player_activity /etc/logrotate.d/picraft` → **0**.
      `sudo logrotate -d /etc/logrotate.d/picraft` behandelt vier Protokolle,
      keine Fehlermeldung, Rückgabewert 0.
- [x] **Der Aufrüstweg greift.** `./deploy.sh` hat die Zeile auf dieser
      bestehenden Installation selbst entfernt (Abschnitt 3d) und den
      Hinweis ergänzt, warum sie fehlt. Zweiter Lauf: Nullvorgang.
- [x] **Beide Wege schreiben wortgleich dasselbe.** In einer Sandbox
      geprüft: Die alte Regel nach der Migration und die von `install.sh`
      frisch geschriebene sind **byteweise identisch**; ein zweiter Lauf
      ändert auf beiden nichts. (Der erste Versuch mit `sed` scheiterte an
      `unknown option to 's'` — der einzufügende Text beginnt selbst mit
      `#`. Deshalb `awk`. Gefunden in der Sandbox, bevor es die Maschine
      erreichte.)
- [x] **Die Historie ist zurück.** `.2.gz` + `.1` zurückgeführt → 1803
      Zeilen, **14.03. bis 11.09.** Das Nachtragswerkzeug meldete danach
      „Nachzutragen: 0", also war die Zusammenführung vollständig; ein
      zweiter Lauf ließ die Prüfsumme unverändert
      (`e452850205eab8f2c337f166073ca42e`).
- [x] **Der Wächter stimmt in beide Richtungen.** Gegen die echten Daten:
      **vor** der Reparatur ein Befund („kein einziger Eintrag, aber
      Serverprotokolle ab 2026-03-14"), **nach** der Reparatur `None`.
      Dazu sechs synthetische Fälle in `tests/pruefung-historie.py`,
      darunter die beiden, die man leicht übersieht: ein Hauptbuch mit
      **nur den Kopfzeilen** (der Zustand direkt nach `copytruncate`) und
      eine **frische Installation ohne Serverprotokolle**, bei der
      geschwiegen werden muss.
- [x] **Der Hinweis erscheint dort, wo die falsche Aussage steht.** Die
      Vorlage gerendert: Das Warnbanner stand über den drei Zeilen „nicht
      aufgezeichnet"; nach der Reparatur ist es weg und vier Spieler
      tragen wieder ein Datum (06.09., 02.09., 12.05., 11.04.).
- [x] **Die Last ist gemessen, nicht geschätzt.** `protokoll_befund()`
      braucht **1,8 ms** je echtem Aufruf; 200 zwischengespeicherte Aufrufe
      zusammen 0,1 ms. Eigener 300-s-Zwischenspeicher statt des
      3-Sekunden-Takts der übrigen Statuswerte — die Prüfung listet den
      `logs`-Ordner (hier 235 Einträge), und der Befund ändert sich
      höchstens einmal am Tag.
- [x] **Abnahmetest im ARM64-Container.** Beide Installationsläufe
      Rückgabewert **0**, keine Tracebacks im Protokoll. Eine frische
      Installation schreibt die Regel schon ohne das Hauptbuch. Die neue
      Inhaltsprüfung ist gegengeprüft: Sie meldet die alte Fassung und
      schweigt bei der neuen, auch wenn ein Kommentar den Dateinamen nennt.
- [x] **Im Browser angesehen — vom User bestätigt am 21.09.2026.** Die
      Spielerseite zeigt die Daten in der Spalte „zuletzt gesehen", kein
      Warnbanner darüber. Damit ist H1 vollständig; die Bestätigung kam von
      einem Menschen vor der echten Seite, nicht aus einem `curl` und nicht
      aus einer gerenderten Vorlage.

> **Nebenbefunde, mitbehoben:** `make` prüfte `admin/` und `tools/`, aber
> nicht `tests/` — dieselbe Lücke wie zuvor bei `tools/` und `lib/`, jetzt
> zum dritten Mal. Und `tests/abnahme-im-container.sh` konnte **nur** an
> einem fehlgeschlagenen Installationslauf scheitern; inhaltliche
> Prüfungen liefen als Text mit. `FEHLER_GEFUNDEN` schließt das.
>
> **Nebenbefund, offen gelassen:** `player_activity.log` ist `rw-rw-r--`
> und enthält IP-Adressen. Die Datei gehört `pi:pi`; der Kommentar im
> Skript sagt genau das und nichts über Leserechte, ist also nicht falsch.
> Auf einem Pi mit einem Benutzer folgenlos. Wer es enger will: `640` in
> `install.sh` **und** im laufenden System.

### H2 — Die Spieler-Historie (21.09.2026)

Etappe 2 des Plans `docs/superpowers/plans/2026-09-21-spieler-historie.md`.
Alles auf diesem Pi gemessen, nicht im Container.

- [x] **Die Datumsherleitung steht an einer Stelle.** `admin/logdatum.py`
      herausgelöst aus `tools/spielerprotokoll-nachtragen.py`, wörtlich
      übernommen. Beleg, dass sich nichts geändert hat: Das umgestellte
      Werkzeug meldet Zahl für Zahl dasselbe (229 Serverprotokolle, 1799
      Ereignisse, 0 nachzutragen), und die Prüfsumme des Spielerprotokolls
      ist nach einem echten Lauf unverändert.
      > **Der Plan lag hier falsch.** Er kannte nur die Vorwärtsdatierung.
      > Tatsächlich gibt es **zwei**: Ein Archiv nennt im Dateinamen den
      > ersten Tag, `latest.log` trägt seine Änderungszeit zur *letzten*
      > Zeile. Aufgefallen beim Lesen des vorhandenen Werkzeugs — und es
      > kippte gleich die geplante Byte-Lesemarke mit: `latest.log` lässt
      > sich nicht stückweise auswerten, weil das Datum der ersten Zeile
      > am Ende der Datei hängt.
- [x] **Sitzungen: 358 aus 1803 Protokollzeilen, in 19 ms.** Gegenprobe
      gegen die Rohzählung: genau 358 „ist dem Spiel beigetreten"-Zeilen.
- [x] **Der Grund einer Trennung kommt aus der Verbindungszeile.** Paper
      schreibt für **eine** Trennung **zwei** Zeilen, in wechselnder
      Reihenfolge; nur eine trägt den Grund. Nachgezählt: 350 Paare, 7-mal
      nur „verlassen", 7-mal nur „Verbindung verloren", **14 Paare über
      eine Sekundengrenze**.
      **Beleg, dass es jetzt stimmt:** 357 Gründe in der Datenbank = 357
      Gründe im Protokoll, aufgeschlüsselt identisch (`Disconnected` 317,
      `idle for too long` 19, `Server closed` 12, `Timed out` 6,
      `logged in from another location` 2, ein Kick-Grund 1).
- [x] **Zwei der drei „Abstürze" waren Doppelanmeldungen.** Paper meldet
      beim Anmelden vom zweiten Gerät **zuerst** den neuen Beitritt und
      wirft erst danach die alte Verbindung hinaus. Vorher: die echte
      Sitzung ohne Dauer als „abbruch", daneben eine von **null
      Sekunden**. Nachher: **0 Sitzungen mit null Sekunden**, genau
      **ein** echter Absturz, und ein Spieler hat zwei fälschlich
      verlorene Stunden zurück (63 h 54 → 65 h 54).
- [x] **Chat und Befehle: 3539 Einträge aus 229 Protokollen in 1,0 s**
      (2161 Befehle, 1378 Chat). Jeder weitere Lauf 25 ms, weil nur noch
      `latest.log` gelesen wird.
- [x] **Fremddateien im logs-Ordner werden übersprungen.** `gc.log` und
      seine fünf Rotationen sind zusammen 24 455 Zeilen mit **null**
      Muster-Treffern — der Filter verhindert keine Falschdaten, sondern
      rund 100 000 umsonst gelesene Zeilen je Seitenaufruf.
- [x] **Die Seite antwortet, und die anderen auch.** Alle elf Routen
      liefern 200, auch mit unbekanntem Namen im Filter. Ohne Anmeldung
      antwortet die laufende Installation mit **302**.
      > Die Regressionsprobe läuft in einem **eigenen Prozess**:
      > `einstellungen.py` liest die `MCS_*`-Variablen beim Import, wer
      > sie danach setzt, ändert nichts mehr. Der erste Versuch lief
      > deshalb still gegen die echten Daten des Pi und hielt das Ergebnis
      > für einen Befund.
- [x] **Last gemessen, nicht geschätzt.** Kalter Aufbau über den
      Browserweg 1,02 s, danach **57 ms** je Aufruf. Mit
      `tools/historie-aufbauen.py` vorweg: 1,6 s einmalig, danach 0,1 s.
- [x] **Rechte.** `historie.db` wird mit `0o600` **angelegt**, nicht
      nachträglich gesetzt; nachgemessen an einer frisch erzeugten Datei
      auf dem Pi (`-rw-------`). Eine zu offen liegende Datei wird beim
      Öffnen richtiggestellt — auf dem Pi tatsächlich vorgekommen und
      behoben. Die Historie läuft im Standard-Journalmodus, es liegt keine
      `-wal` daneben; die Prüfung deckt den Fall trotzdem ab.
- [x] **Aufbewahrung.** `MCS_HISTORIE_TAGE=0` löscht nachweislich nichts,
      ebenso wenig `None`, `""`, `"viele"` oder `-5`. Mit einer echten
      Frist verschwinden Sitzung *und* Äußerung.
- [x] **Der Aufrüstweg greift.** `deploy.sh` trägt `MCS_HISTORIE_DB` und
      `MCS_HISTORIE_TAGE` mit **eigener** Abfrage nach; auf diesem Pi
      geschehen. Eine frische Installation bekommt sie aus
      `mcs.conf.beispiel` — im Container nachgemessen
      (`MCS_HISTORIE_DB=…/mcs/admin/historie.db`, `MCS_HISTORIE_TAGE=0`).
- [x] **Abnahmetest im ARM64-Container.** Beide Installationsläufe **0**,
      keine Tracebacks, keine Inhaltsprüfung mit Befund.
- [x] **Im Browser angesehen — vom User am 21.09.2026 auf iPad und
      MacBook geprüft.** Inhalt, Sitzungen, Chat und Filter: sauber.
      **Ein Befund: die Tagesbalken waren zu breit.**
- [x] **Der Balkenbefund ist behoben (22.09.2026) — und er war kein
      Schönheitsfehler.** `.taglinie` ist ein Flex-Container, die Breite
      stand direkt am Balken; Prozente beziehen sich dort auf die **ganze
      Zeile**, nicht auf den freien Platz darin. Bei einem vollen Tag war
      der Balken also so breit wie die Zeile (bei 1100 px Rahmen rund
      1036 px) und schob Datum und Wert hinaus — die drei Elemente stehen
      alle auf `flex: none` und schrumpfen nicht.
      Behoben mit einer eigenen **Bahn** (`.taglinie__bahn`,
      `flex: 1 1 auto; min-width: 0; max-width: 28rem`), in der sich der
      Balken misst. Nachgerechnet: statt 1036 px jetzt höchstens 420 px,
      und bei 400 px Fensterbreite bleiben 175 px für die Bahn — kein
      Überlauf an keiner Breite.
      > **Die Lehre ist allgemeiner als der Balken:** Der Fehler steckte
      > nicht in der Zahl, sondern darin, **worauf sie sich bezog**. Die
      > Prozentwerte waren von Anfang an richtig berechnet.
      >
      > Und: Gefunden hat ihn ein Mensch vor dem Gerät. Der Test-Client
      > liefert dasselbe HTML und sagt über Breiten nichts — `make` prüft
      > kein CSS, und ein `curl` schon gar nicht.
- [x] **Nach der Korrektur noch einmal angesehen — vom User am 22.09.2026
      abgenommen.** Damit ist H2 vollständig und die Spieler-Historie
      (v1.2) fertig.

### W7 — Operator-Stufe

**Gemessen am 01.09.2026** als **M9** in `tests/messung-im-container.sh`
(Paper 26.2 Build 119, ARM64-Container, wiederholbar mit
`./tests/messung-paper-verhalten.sh`). Alle drei Fragen sind beantwortet —
und die dritte fällt genau andersherum aus als bei `server.properties`.

**Frage 1 — Womit lässt sich die Stufe bei laufendem Server ändern?
Antwort: gar nicht.**

| Befehl | Antwort des Servers |
|---|---|
| `op Steve` | `Made Steve a server operator` — Stufe wird `4` |
| `op Alex 2` | `Incorrect argument for command` |
| `minecraft:op Alex 3` | `Incorrect argument for command` |

Ein Vanilla-RCON kennt kein Kommando, das eine Stufe setzt. `op <name>`
vergibt immer die Vorgabe aus `op-permission-level` (hier `4`).

**Frage 2 — Wirkt eine Änderung an `ops.json` bei laufendem Server?
Antwort: nein, sie wird verworfen.** Alle Stufen von Hand auf `2` gesetzt,
danach ein `op Notch` (ein Befehl, der die Datei *wirklich* ändert):
Anschließend stand überall wieder `4`. Paper schreibt die ganze Datei aus dem
Arbeitsspeicher neu — **dieselbe Falle wie bei `server.properties`**
(Korrektur K3).

**Frage 3 — Verhält sich `ops.json` beim START wie `server.properties`?
Antwort: NEIN, genau umgekehrt.** Bei gestopptem Server alle Stufen auf `3`
gesetzt, dann gestartet: Die `3` stand noch da. Das allein beweist aber nur,
dass niemand die Datei neu geschrieben hat — nicht, was im Arbeitsspeicher
steht. Deshalb anschließend ein `op Herobrine`, um ein Neuschreiben *aus dem
Speicher* zu erzwingen. Ergebnis:

```
Stufen nach erzwungenem Neuschreiben:  3   4   3   3
                                       ^   ^
                              Altbestand   der neue Eintrag
```

**Der Server hatte die `3` beim Start gelesen und behalten.**

> Damit steht die Regel dieses Projekts auf dem Kopf, wenn man sie von
> `server.properties` überträgt:
>
> | | `server.properties` | `ops.json` |
> |---|---|---|
> | beim Stoppen | überlebt | überlebt |
> | beim **Start** | **wird verworfen** | **wird gelesen und überlebt** |
> | bei laufendem Server, nach einem ändernden Befehl | wird verworfen | wird verworfen |
>
> Genau davor warnte das Pflichtenheft („Die naheliegende Annahme war dort
> schon einmal genau falsch herum") — und die Warnung war berechtigt.

**Was daraus für das Arbeitspaket folgt** (zu schreiben, nicht hier zu
entscheiden): Der einzige Weg zu einer anderen Stufe als der Vorgabe ist
`ops.json` **bei gestopptem Server** zu schreiben. Bei laufendem Server gilt
weiterhin: **nichts Schreibendes an `ops.json`** — die Änderung wäre nicht
nur wirkungslos, sondern verschwände beim nächsten `op` oder `deop` lautlos.
Eine Oberfläche, die das anbietet, muss den Server also stoppen lassen oder
vormerken, wie bei `server.properties` auch.

**Am 02.09.2026 gebaut — und zwar der erste der beiden Wege.** Vormerken
wäre hier ein Rückschritt gewesen: Eine Vormerkung ist ein vollständiger
Dateiabzug, und wer zwischen Vormerken und Neustart im Spiel `/op` tippt,
verlöre den neuen Operator beim nächsten Start lautlos. Die Stufe ist nichts,
was man wöchentlich ändert; ein stiller Rechteverlust dafür einzuhandeln,
wäre der schlechtere Tausch.

- `spieler.stufe_setzen()` schreibt `ops.json` **nur**, wenn
  `service_state(frisch=True)` nicht `active` meldet — `frisch=True` aus
  demselben Grund wie in `konfig.server_laeuft()`: Von dieser einen Antwort
  hängt ab, **ob** geschrieben wird.
- Geschrieben wird über `konfig.datei_ersetzen()` (dafür ist es jetzt
  öffentlich statt `_datei_ersetzen`), also atomar und mit den Rechten der
  Zieldatei. Eine halb geschriebene `ops.json` wäre kein Schönheitsfehler:
  Paper liest sie beim Start, und wer dann nicht mehr darin steht, ist kein
  Operator mehr.
- Die Oberfläche zeigt die Stufenwahl **genau dann, wenn der Server steht**
  — also gerade dann, wenn alles andere auf dieser Seite nicht geht. Läuft
  er, steht neben dem Operator „Stufe änderbar nur bei gestopptem Server".
- Neu ist außerdem `op-permission-level` in den Einstellungen: die Vorgabe
  für **neue** Operatoren. Sie läuft über die vorhandene
  `server.properties`-Vormerkung und ist deshalb auch im Betrieb änderbar.

**Am 02.09.2026 um 10:17 auf dem Pi ausgerollt.** `./deploy.sh` hat vier
Dateien übernommen (`konfig.py`, `seite_spieler.py`, `spieler.py`,
`teile/spielerliste.html`), keine systemd-Einheit hat sich geändert.
Bedingungen, weil sie zum Ergebnis gehören: alle sechs Einheiten
`active`/`enabled`, **0 Spieler online**, frisches Backup von 04:00, kein
Fehler-Merkzettel. Neu gestartet wurde nur `mcs-admin.service`; der
Minecraft-Server lief durch. Danach keine Journal-Einträge ab Stufe
`warning`, `/anmelden` antwortet mit 200, und `~/mcs/ausgerollt` trägt den
neuen Zeitstempel.

- [x] **Bei laufendem Server wird die Datei nicht angefasst — gegen die
      echte Installation gemessen, nicht gegen eine Attrappe.**
      `service_state(frisch=True)` meldete `active`, `stufe_setzen()` auf
      einen tatsächlich eingetragenen Operator lieferte `fehler` mit der
      Begründung, und die **SHA256 der `ops.json` war vorher und nachher
      dieselbe**. Ein untergeschobenes `was=stufe` mit Stufe `9` wurde mit
      „muss zwischen 1 und 4 liegen" abgewiesen. Gegenprobe zur Auslieferung:
      `op-permission-level` ist in den Einstellungen vorhanden,
      `spawn-monsters` nicht mehr.
- [x] **Die Oberfläche bietet die Stufenwahl nur im richtigen Zustand an.**
      Die Vorlage in beiden Zuständen übersetzt und gerendert: bei laufendem
      Server erscheint kein `name="stufe"`, dafür der Satz „Stufe änderbar
      nur bei gestopptem Server"; bei gestopptem Server ist es genau
      umgekehrt, und für einen Nicht-Operator entsteht dort gar kein
      Formular.

**Was auf dem Pi noch offen ist** — es braucht einen Serverstopp, also einen
Zeitpunkt, an dem das niemanden stört:

- [ ] Server stoppen, einem Operator Stufe 2 geben, Server starten, danach
      `mcs rcon "op <name>"` auf einen **anderen** Namen — die Stufe 2 muss
      danach noch stehen. Das ist die Gegenprobe aus M9 auf echter Hardware:
      Erst ein erzwungenes Neuschreiben zeigt, ob der Server die Stufe
      wirklich in den Arbeitsspeicher übernommen hat. Im Container ist genau
      das gemessen; was hier fehlt, ist dieselbe Probe auf einer gewachsenen
      Welt mit echten Einträgen.

> **Zwei Fehler im Messgerüst, die zuerst gefunden werden mussten** — die
> erste Messung war ungültig und hätte beinahe das Gegenteil belegt:
>
> 1. `hoch()` suchte `Done (` in `latest.log` — und fand das des **vorigen**
>    Laufs. „(oben nach 1s)", während gar nichts gestartet war. Der
>    Abnahmetest kennt diese Falle an seiner zweiten Startstelle seit jeher
>    und sagt dort auch warum; das Messskript kannte sie nirgends. Wieder
>    zweiter Weg zur selben Sache ohne die Regel des ersten.
> 2. Selbst ein echtes `Done (` heißt nur „oben", nicht „nimmt Befehle an".
>    Die erste Messung lief gegen `Connection refused` — und der
>    Auswertungssatz darunter hätte daraus „ops.json wird beim Start nicht
>    neu geschrieben" gemacht, ohne dass irgendetwas gemessen war.
>
> Behoben: `hoch()` räumt die alte Logdatei weg, `rcon_bereit()` wartet auf
> eine echte Antwort, und M9 zieht keine Schlussfolgerung mehr, wenn die
> Voraussetzung fehlt. Danach: Starts nach 50 s, 23 s und 21 s statt „1 s".

### W8 — Whitelist für jemanden, der nie da war

- [x] **Geprüft, und es war *nicht* schon erfüllt.** Das Pflichtenheft hielt
      das für wahrscheinlich. Die Prüfung ergab: Jede Aktion der Spielerseite
      hing an einer Zeile der Liste, und wer nie da war, hat keine — über
      diese Seite ließ sich also **niemand** einladen, der noch nie hier war.
      Ergänzt: ein Eingabefeld für einen freien Namen.
- [x] **Die Meldung erklärt sich jetzt.** „That player does not exist" war
      korrekt durchgereicht und kein Programmfehler; was fehlte, war die
      Erklärung. Sie steht jetzt unter der rohen Serverantwort — Mojang kennt
      den Namen nicht, häufigste Ursachen Tippfehler, geänderter Name oder
      ein Bedrock-Konto.

### W9 — Backup-Uhrzeit

- [x] **Das Drop-in wird geschrieben und wirkt.** Über die Oberfläche von
      `*-*-* 04:00:00` auf `*-*-* 03:30:00` gesetzt.
      `systemctl show -p TimersCalendar` meldet danach den neuen Wert,
      `NextElapseUSecRealtime` einen entsprechend verschobenen Termin —
      geprüft wurde also systemd, nicht die selbst geschriebene Datei.
- [x] **Eine unsinnige Eingabe ändert nichts.** `systemd-analyze calendar`
      läuft **vor** dem Schreiben; „Unsinn" wird mit der Begründung des
      Systems abgelehnt, und es wird nichts angefasst.
- [x] **Die geänderte Uhrzeit überlebt ein `./deploy.sh`** — im Abnahmetest
      nachgemessen, und dort ist es auch aussagekräftig: Das Drop-in stand
      auf `Mon..Fri 05:17:00`, nach dem Ausrollen galt weiterhin
      `Mon..Fri 05:17:00`, während die Einheit wieder die Vorgabe
      `*-*-* 04:00:00` trug. Genau die Trennung, um die es geht.
      *Auf diesem Pi ist derselbe Lauf kein Beleg:* Hier stehen Drop-in und
      Vorgabe beide auf 04:00, ein Rücksetzen wäre also nicht zu sehen. Das
      Ausrollen am 01.09.2026 hat die Einheit tatsächlich ersetzt
      (`~ aktualisiert: /etc/systemd/system/mcs-backup.timer`), und
      `systemctl show -p TimersCalendar` meldete danach unverändert
      `*-*-* 04:00:00` bei nächstem Termin 02.09. 04:00.
- [ ] **Die Migration einer Installation von vor v1.1.** `deploy.sh`
      übernimmt eine abweichende Uhrzeit **einmalig** aus der alten Einheit
      ins Drop-in. Auf diesem Pi nicht mehr auslösbar, weil das Drop-in schon
      existiert; auf einer Installation ohne Drop-in noch zu prüfen.

### W6 — Versionsanzeige

- [x] **Alle vier Fälle geprüft** (mit einem Wegwerf-Verzeichnis):
      nichts vorhanden → „nicht feststellbar"; nur `VERSION` (Installation
      von vor v1.1) → ebenfalls „nicht feststellbar"; beide gleich → Stand
      mit Zeit und Werkzeug; `VERSION` neuer als `ausgerollt` → **Abweichung
      gemeldet**, also ein steckengebliebenes Ausrollen.
- [x] **Nach dem echten `./deploy.sh` zeigt die Fußzeile den Stand der
      Installation** (01.09.2026, 15:27). `~/mcs/ausgerollt` trägt
      `MCS_STAND=1.1`, `MCS_STAND_WOMIT=deploy.sh` und den Zeitstempel;
      `version.stand()` auf der **ausgerollten** Installation liefert
      Installation `1.1`, Vorlage `1.1`, Abweichung `False`.


### U1 — Paper-Update über `mcs update` und die Tafel „Paper" (v1.3.0, 03.10.2026)

- [x] **Das Skript gegen eine Wegwerf-Installation** (Kopie von
      `mc_server`, Klon des Repos): echter Download Build 119 → 129 in
      sechs Sekunden, Prüfsumme geprüft, `paper.jar.vorher` angelegt, beide
      `versions.env` geschrieben, im Klon **genau eine Datei committet**.
      Danach die Sonderfälle: zweiter Lauf → „nichts zu tun";
      `--festgelegt` → „nichts zu tun"; zweiter Lauf bei gehaltener Sperre →
      abgewiesen; `--minecraft 26.3` → „noch kein stabiler Build", **ohne**
      vorher ein Backup anzulegen; Vorgabe 26.3 bei installiertem 26.2 →
      verweigert; `--minecraft 26.1.2` → „Rückschritt nicht möglich";
      Ausrollen hat eine ältere `versions.env` gebracht → Vorgabe
      nachgezogen und committet, ohne neuen Download; fremde offene
      Änderung an der Datei → **kein** Commit, Befehl genannt; ohne
      Git-Identität → Commit als „PiCraft"; ohne Repository → Warnung nur,
      wenn sich etwas geändert hat.
- [x] **Die Oberfläche mit dem Flask-Testclient** gegen dieselbe Attrappe:
      Tafel ohne Notiz, nach „Nachsehen" mit Knopf „Auf Build 129
      aktualisieren" und 26.3 als „in Vorbereitung", Klick → „Build 129 ist
      installiert" samt Ausgabe, zweiter Klick → „Nichts zu tun". Ohne
      CSRF-Token 403. Ohne Netz → „nicht feststellbar" mit dem curl-Grund.
      Das Aktionsprotokoll trägt Start, Ausgabe und `ENDE update_paper: 0`.
- [x] **Live nach `./deploy.sh`** (Stand 1.3.0): Anmeldung über HTTP,
      die Seite Konfiguration hat die Tafel und keinen alten Knopf mehr,
      `/teil/paper` zeigt Build 119, „Build 129 ist verfügbar", 26.3 „in
      Vorbereitung"; „Nachsehen" per POST funktioniert. Keine
      Neustart-Warnung — richtig, die `paper.jar` ist älter als der Dienst.
- [ ] **Der Container-Abnahmetest** (`tests/abnahme.sh`) ist für v1.3.0
      **nicht gelaufen** — am 03.10.2026 auf Entscheidung des Betreibers
      ausgelassen (ein Spieler war online, der Test braucht einen zweiten
      Server mit 3 GB Heap). Er prüft neu die Tafel „Paper" und die
      Prüfsumme nach `install.sh` (`--festgelegt`); beim nächsten Lauf die
      Ausgabe auf `Traceback` und die `(muss …)`-Zeilen ansehen.
- [ ] **Im Browser:** Erscheint beim Aktualisieren die Rückfrage, ist der
      Knopf während des Ladens gesperrt, und tauscht HTMX danach die Tafel
      sauber aus? (Mit `curl` nicht prüfbar.)
- [ ] **Der echte Klick auf „Auf Build N aktualisieren"** auf dem Pi, dann:
      die Tafel warnt „läuft noch mit dem vorigen Build"; im Repo steht ein
      Commit „Paper 26.2 Build N festgelegt (mcs update)"; nach „Neu
      starten" verschwindet die Warnung, und `logs/latest.log` nennt den
      neuen Build.

---

## Bevor es losgeht: den Pi auf den neuen Stand bringen

Auf dem Pi läuft der Stand von Etappe B. Ohne diesen Schritt prüft man die
alte Fassung.

```bash
cd ~/PiCraft
git pull
./deploy.sh --probe          # erst ansehen, was passieren würde
./deploy.sh
sudo systemctl restart mcs-admin.service
```

Drei Dinge daran sind neu und leicht zu übersehen:

- Vorlagen und statische Dateien werden als **ganze Bäume** ausgerollt, und
  was im Repository gelöscht wurde, verschwindet auch auf dem Pi —
  darunter die alte `templates/index.html`.
- **`MCS_ADMIN_SECRET`** wird in die `.env` nachgetragen. Ohne diesen Wert
  meldet jeder Neustart des Dienstes alle ab; `install-admin.sh` legt ihn
  nur bei einer *frischen* `.env` an.
- Fehlt **`python3-yaml`**, wird das gemeldet. Der Expertenmodus der
  Konfigurationsseite prüft damit beim Speichern, ob eine YAML-Datei noch
  gültig ist:

  ```bash
  sudo apt-get install -y python3-yaml
  ```

---

## Die Reihenfolge ist keine Empfehlung

Sie ist nach Risiko sortiert, und zwar absteigend:

| Zuerst | Punkt | Warum zuerst |
|---|---|---|
| 1 | **A-P1** Hauptschalter | Stimmt etwas an den `[Install]`-Abschnitten nicht, kommt der Server **nach dem nächsten Neustart nicht mehr hoch**. Alles andere ist danach egal. |
| 2 | **B-P1** RCON von außen | Steht der Port offen, kann jeder im Heimnetz den Server fernsteuern, der das Passwort aus der `server.properties` liest. |
| 3 | **C-P1/C-P2** Oberfläche und Anmeldung | Ohne die geht keiner der übrigen C-Punkte. |
| 4 | der Rest | in beliebiger Reihenfolge |

**Ausnahme, die zuletzt kommt:** `C-P10` (wiederherstellen im Ernst)
tauscht Weltdaten aus. Erst machen, wenn alles andere steht — und mit einem
frischen Backup im Rücken.

### Überblick

Stand 29.08.2026 — ✅ erledigt · 🟡 teilweise · ⬜ offen

| | Punkt | Worum es geht | |
|---|---|---|---|
| A-P1 | Hauptschalter | `mcs an`/`mcs aus` überlebt den Neustart | ✅ |
| A-P2 | Backup-Warnung bei „aus" | kein falscher Alarm in der Sommerpause | ✅ |
| A-P3 | Cron → Timer | das Backup läuft nicht doppelt | ✅ |
| A-P4 | altes `minecraft-modus` | zwei Ausschalter sind schlimmer als keiner | ✅ |
| A-P5 | Portkonflikt | Oberfläche und Karte auf verschiedenen Ports | ✅ |
| A-P6 | Benutzername | nirgends mehr `pi` | ✅ |
| B-P1 | RCON von außen | **muss** unerreichbar sein | ⬜ |
| B-P2 | RCON nachholen | auf einer laufenden Installation | ✅ |
| B-P3 | Verlauf füllt sich | `metrik.db` bekommt plausible Werte | ✅ |
| B-P4 | Module ausgerollt | die Oberfläche läuft nach der Aufteilung | ✅ |
| C-P1 | Oberfläche vollständig | alle Vorlagen und statischen Dateien da | ✅ |
| C-P2 | Anmeldung | Cookie, Abmelden, Ratenbegrenzung | 🟡 |
| C-P3 | Handy | sechs Kacheln auf einen Bildschirm | ⬜ |
| C-P4 | RCON-Takt | sechs Verbindungen je Minute, nicht vierundzwanzig | ✅ |
| C-P5 | Vormerkung | über zwei Prozesse und einen Neustart | ✅ |
| C-P6 | Kurven | echte Daten über sieben Tage | 🟡 |
| C-P7 | Spielerseite | Spielzeit, Adresse, kicken, sperren | 🟡 |
| C-P8 | Karte über Tailscale | HTTPS blockiert den Rahmen | 🟡 |
| C-P9 | Plugin installieren | über Modrinth, und `deploy.sh` danach | ✅ |
| C-P10 | **Wiederherstellen** | der Punkt, der die Backup-Kette beweist | ✅ |
| P-A | Autostart beim Booten | fiel bei A-P1 Schritt 5 mit ab | ✅ |
| P-B | Neustart nach Absturz | `Restart=always` fängt ihn in 10 s | ✅ |
| P-C | Sauberes Herunterfahren | „All dimensions are saved" vor dem Ende | ✅ |
| D-P1 | Hardware-Erkennung | Modell, RAM und Speichermedium stimmen | ✅ |
| D-P2 | SD-Karten-Warnung | erscheint sie, wenn eine im Slot steckt? | ⬜ |
| D-P3 | Sicherheitsupdates | `unattended-upgrades` hat gelaufen | ✅ |
| D-P4 | Testnachricht | kommt sie wirklich auf dem Handy an? | 🟡 |
| D-P5 | Fehlschlag und Entwarnung | beide Nachrichten, in dieser Reihenfolge | 🟡 |
| D-P6 | Erreichbarkeit | stimmt das Urteil am echten Anschluss? | ✅ |
| D-P7 | DNS wird nachgeführt | nach einem Adresswechsel | 🟡 |
| D-P8 | SRV-Eintrag | Mitspieler verbindet sich **ohne Portangabe** | 🟡 |
| D-P9 | DNS-Timer bei „aus" | `mcs aus` schaltet auch ihn ab | 🟡 |
| D-P10 | Zugriff über Tailscale | vom Handy, ohne Portfreigabe | ⬜ |
| D-P11 | Installation an anderen Ort | der Assistent fragt, und alles zieht mit | 🟡 |

Stand der D-Zeile: 30.08.2026. 🟡 heißt hier durchweg *„der Teil, den dieser
Pi beantworten kann, ist beantwortet"* — was fehlt, steht oben in der Tabelle
„Was noch offen ist".

---

## Offen aus Etappe A (Stand 28.08.2026)

### A-P1 — Der Hauptschalter, vor allem anderen

Das ist die Änderung mit den größten Folgen: Stimmt an den
`[Install]`-Abschnitten etwas nicht, kommt der Server **nach einem Neustart
nicht mehr hoch**. Deshalb in dieser Reihenfolge, und nicht anders:

**1. Erst hinsehen, nichts anfassen.**

```bash
systemctl list-dependencies mcs.target
```

Erwartet: `minecraft.service`, `mcs-playerlog.service`, `mcs-backup.timer`
hängen darunter (falls die Weboberfläche installiert ist, auch
`mcs-admin.service`).

```bash
systemctl is-enabled mcs.target minecraft.service mcs-playerlog.service mcs-backup.timer
```

Erwartet: viermal `enabled`.

```bash
systemctl list-timers mcs-backup.timer
```

Erwartet: ein Termin in der Zukunft, zur eingestellten Uhrzeit.

**Stimmt hier etwas nicht, NICHT weitermachen** — dann erst klären, sonst
steht der Server nach dem Neustart in Schritt 4 still.

**2. Abschalten.**

```bash
mcs aus
```

Erwartet: Server, Weboberfläche und Spielerprotokoll gehen aus, der
Backup-Timer ebenso. Danach:

```bash
systemctl is-active minecraft.service mcs-playerlog.service mcs-backup.timer
systemctl is-enabled mcs.target
```

Erwartet: dreimal `inactive`, dann `disabled`.

**3. Prüfen, dass der Aus-Zustand hält.**

```bash
mcs start
```

Erwartet: Der Befehl **verweigert** sich mit dem Hinweis auf `mcs an`.
Startet der Server hier trotzdem, ist die Absicherung wirkungslos.

**4. Neustart — der eigentliche Test.**

```bash
sudo reboot
```

Nach dem Hochfahren:

```bash
systemctl is-active minecraft.service
```

Erwartet: `inactive`. **Das ist der Punkt, den es vorher nicht gab.**

**5. Wieder einschalten.**

```bash
mcs an
```

Erwartet: Alles kommt hoch. Nach etwa einer Minute:

```bash
mcs status
```

Und zur Sicherheit noch ein `sudo reboot` — danach muss der Server von selbst
wieder laufen.

- [x] **Schritte 4–5 geprüft am 29.08.2026 abends · Ergebnis: bestanden.
  Der Hauptschalter übersteht den Neustart.**

  Die beiden Neustarts sind belegt, und zwar unabhängig von der Erinnerung
  daran — das Journal dieses Pi ist flüchtig (`/var/log/journal` existiert,
  ist aber leer; `journalctl -b -1` sagt "no persistent journal was found"),
  frühere Boots sind darin also nicht nachlesbar. Die Serverlogs und die
  Zeitstempel der enable-Verweise reichen aber aus:

  ```
  18:39:39   Server sauber beendet ("All dimensions are saved")   <- mcs aus
             ... Neustart 1 ...
             KEIN Serverstart dazwischen — 61 Minuten Lücke
  19:40:43   /etc/systemd/system/multi-user.target.wants/mcs.target angelegt
                                                                  <- mcs an
  19:40:46   Server startet (Log 2026-08-29-7.log.gz)
  19:42:02   Server sauber beendet                                <- reboot 2
  19:42:20   Boot
  19:42:22   mcs-playerlog, mcs-backup.timer   aktiv
  19:42:24   mcs-admin                          aktiv
  19:42:34   minecraft.service                  aktiv, "Reached target mcs.target"
  ```

  **Schritt 4:** Zwischen 18:39:39 und 19:40:46 liegt kein einziger
  Serverstart, obwohl das System in dieser Zeit neu gestartet ist. Der
  Aus-Zustand hat den Neustart also überlebt — genau der Punkt, den es
  vorher nicht gab. Auch die Messwertdatenbank zeigt diese Lücke
  (18:39 → 19:40), weil der Sammler im abgeschalteten `mcs-admin` steckt.

  **Schritt 5:** Der Symlink von 19:40:43 ist **zwei Minuten älter** als der
  Boot um 19:42:20. `mcs an` lief also vor dem zweiten Neustart, und danach
  kam alles von selbst hoch, ohne Zutun — 14 Sekunden nach dem Boot stand
  der Server. Damit ist zugleich **P-A** (Autostart beim Booten) erledigt.

  Verankerung danach unverändert richtig: `multi-user.target.wants/` enthält
  nur `mcs.target`, `mcs.target.wants/` die vier Einheiten
  (minecraft, mcs-admin, mcs-playerlog, mcs-backup.timer), alle `enabled`.

- [x] **Schritte 1–3 geprüft am 29.08.2026 · Ergebnis: Befund gefunden und
  behoben.**

  **Schritt 1 hat genau das gefunden, wofür er da ist.** Die Dienste waren
  noch unter `multi-user.target` verankert, obwohl die ausgerollte Datei
  bereits `WantedBy=mcs.target` sagte:

  ```
  Datei sagt:            WantedBy=mcs.target
  systemctl show sagt:   WantedBy=multi-user.target
  ```

  Ursache: `deploy.sh` rollte die geänderten `[Install]`-Abschnitte aus und
  rief `daemon-reload` — das liest die Dateien neu ein, fasst die
  enable-Verweise aber nicht an. Die stammten vom 26.08. und zeigten weiter
  auf `multi-user.target`. `mcs an`/`mcs aus` schaltet nur `mcs.target`
  selbst und räumt sie ebenfalls nicht ab.

  **Der Hauptschalter wäre damit wirkungslos gewesen:** `mcs aus` stoppt die
  Dienste über `PartOf=`, aber beim Booten hätte `multi-user.target` sie über
  die alten Verweise wieder hochgezogen. Der Fehlschlag wäre erst in
  Schritt 4 aufgefallen, mit unklarer Ursache.

  **Behoben im Repository** (nicht von Hand am System): `deploy.sh` hängt die
  Verankerung jetzt selbst um (`systemctl reenable`) — aber nur bei Diensten,
  die bereits aktiviert sind, damit ein bewusst deaktivierter Dienst
  deaktiviert bleibt. Wird dabei etwas umgehängt und ist `mcs.target` nicht
  aktiviert, wird es nachgezogen: Ein Ausrollen darf den Autostart-Zustand
  nicht verändern, sonst käme nach dem nächsten Neustart nichts mehr hoch.

  Danach gemessen: `multi-user.target.wants/` enthält nur noch `mcs.target`,
  `mcs.target.wants/` die drei Dienste, `mcs.target` ist `enabled`.

  **Schritt 2** (`mcs aus`): Server, Weboberfläche, Spielerprotokoll und
  Backup-Timer `inactive`, `mcs.target` `disabled`, kein Java-Prozess mehr. ✓

  **Schritt 3** (`mcs start` verweigert sich): Der Befehl bricht mit dem
  Hinweis auf `mcs an` ab, Rückgabewert **1**, der Server startet nicht. ✓

  Offen: `mcs-backup.timer` ist noch `disabled` und hängt darum nicht unter
  `mcs.target` — der Umstieg von Cron auf den Timer ist noch nicht vollzogen
  (siehe A-P3). Für den Hauptschalter ist das ohne Folgen.

### A-P2 — Keine falsche Backup-Warnung bei „aus"

Die 48-Stunden-Warnung darf bei abgeschaltetem PiCraft nicht anschlagen. Sonst
meldet `mcs status` nach zwei Tagen Sommerpause einen Ausfall, den es nicht
gibt — und Alarm, der falsch liegt, wird bald gar nicht mehr gelesen.

```bash
mcs aus
mcs status
```

Erwartet: die Zeile
`Betrieb: ABGESCHALTET (mcs aus) — kein Backup, keine Dienste`,
**keine** Meldung über ein zu altes Backup, und Rückgabewert 0:

```bash
mcs status >/dev/null; echo "Rueckgabewert: $?"
```

Danach `mcs an` nicht vergessen.

- [x] **geprüft am 29.08.2026 · Ergebnis: bestanden.** Die Zeile
  `Betrieb: ABGESCHALTET (mcs aus) — kein Backup, keine Dienste` steht da,
  keine Backup-Warnung, Rückgabewert 0.

  Weil das letzte Backup nur 5,7 h alt war, hätte die 48-Stunden-Warnung
  ohnehin nicht angeschlagen — bestanden wäre der Punkt also auch dann, wenn
  die Ausnahme gar nicht griffe. Deshalb die Gegenprobe über die Grenze
  selbst:

  ```bash
  MCS_BACKUP_WARNUNG_STUNDEN=1 mcs status   # 5,7 h altes Backup, Grenze 1 h
  ```

  Auch damit **keine** Warnung und Rückgabewert 0. Der Code-Pfad dahinter ist
  `backup_alter_melden()` in `/usr/local/bin/mcs`, der bei `mcs_abgeschaltet`
  vor der Altersprüfung abzweigt. Damit ist die Ausnahme belegt und nicht nur
  nicht widerlegt.

### A-P3 — Der Umstieg von Cron auf den Timer

Auf diesem Pi lief das Backup bisher über einen Cronjob. Die Installation
entfernt ihn, wenn der Timer kommt — sonst liefe das Backup zweimal: zwei
gleichzeitige `tar`-Läufe über dieselben Weltdateien, und die Rotation räumte
doppelt so schnell ab.

```bash
crontab -l | grep -c minecraft-backup.sh    # muss 0 sein
systemctl list-timers mcs-backup.timer      # muss einen Termin zeigen
```

Und einmal wirklich laufen lassen:

```bash
sudo systemctl start mcs-backup.service
journalctl -u mcs-backup.service -n 30 --no-pager
```

Erwartet: ein neues Archiv in `~/mcs/mcs_backup/`, im Protokoll die Zeile
„Backup geprüft und in Ordnung".

- [x] **geprüft am 29.08.2026 · Ergebnis: bestanden — nach einem behobenen
  Befund, der das Backup stillgelegt hatte.**

  **Der Umstieg selbst lief richtig:** Der Cronjob ist weg (`crontab -l` zeigt
  nur noch den deSEC-Eintrag), der Timer ist eingerichtet.

  **Aber er lief nicht.** Direkt nach dem Installationslauf:

  ```
  systemctl is-enabled mcs-backup.timer  -> enabled
  systemctl is-active  mcs-backup.timer  -> inactive (dead)
  systemctl list-timers mcs-backup.timer -> 0 timers listed   (Trigger: n/a)
  ```

  Ursache: `install.sh` rief `systemctl enable mcs-backup.timer` **ohne
  `--now`**. Das legt nur den Verweis für den nächsten Systemstart an. Da im
  selben Lauf der Cronjob entfernt wird, lief zwischen Installation und
  nächstem Neustart **überhaupt kein Backup** — und beide Zustände sehen für
  sich plausibel aus („enabled" hier, „kein doppelter Cronjob" dort). Genau so
  fällt ein Backup lautlos aus. `Persistent=true` rettet das nicht: Es holt
  verpasste Läufe nach, aber auch erst, wenn der Timer läuft.

  **Behoben in `install.sh`:** `enable --now`, außer wenn PiCraft gerade
  abgeschaltet ist (`mcs aus`) — dann wird nur eingerichtet und gesagt, dass
  `mcs an` es nachholt.

  Danach: `active`, nächster Lauf `Sun 2026-08-30 04:01`.

  **Testlauf** (`sudo systemctl start mcs-backup.service`, 58 s):

  ```
  Server läuft — starte Online-Backup (ohne Unterbrechung für Spieler).
  Speichern bestätigt nach 1s — beginne mit dem Kopieren.
  Hinweis: Dateien haben sich während des Sicherns geändert (tar-Status 1).
  Backup geprüft und in Ordnung: backup_2026-08-29_09-55-27.tar.gz (710M, 41s,
    Inhalt: MeineWelt server.properties whitelist.json ops.json ... plugins.txt)
  Rotation: 1 alte(s) Backup(s) gelöscht (behalte die neuesten 10).
  ```

  Der Inhalt nennt **`MeineWelt`**, nicht `world` — die Welt wird richtig erfasst.
  Der `tar`-Status 1 (Pl3xMap rendert während des Laufs weiter) wird korrekt
  als Hinweis behandelt und reißt das Backup nicht ab.

### A-P4 — Das alte `minecraft-modus`-Skript ablösen

Auf diesem Pi existierte ein lokales Skript `minecraft-modus ein|aus`, das nie
Teil des Repositories war. Es schaltete drei Dienste und kommentierte die
Backup-Zeile in der Crontab aus. `mcs an` / `mcs aus` ersetzt es vollständig.

Nachsehen, ob es noch herumliegt, und es dann entfernen — zwei Ausschalter
nebeneinander sind schlimmer als keiner:

```bash
command -v minecraft-modus; ls -l ~/mcs/minecraft-modus* /usr/local/bin/minecraft-modus 2>/dev/null
```

- [x] **geprüft und erledigt am 29.08.2026 · Ergebnis: gefunden und gelöscht.**

  Gefunden: `/usr/local/bin/minecraft-modus` (6931 Bytes, 23.07.2026,
  `root:root`). In `~/mcs/` lag nichts mehr.

  `mcs an` / `mcs aus` ersetzt es vollständig und ist ihm überlegen: Das alte
  Skript kommentierte die Backup-Zeile in der Crontab aus — dieselbe Zeile,
  die es seit dem Umstieg auf den Timer (A-P3) gar nicht mehr gibt. **Es
  hätte also ein Backup abgeschaltet, das dort nicht mehr steht, und den
  Timer weiterlaufen lassen.** Nicht nur überflüssig, sondern irreführend.

  Vor dem Löschen geprüft, dass nichts mehr darauf verweist:

  ```
  Crontab (pi und root)   -> nichts
  /etc/systemd/system/    -> nichts
  Skripte in ~/mcs, /usr/local/bin, ~/PiCraft  -> nichts
  ```

  Eine Kopie liegt im Sitzungs-Scratchpad
  (`sicherung/minecraft-modus-geloescht-2026-08-29`). Danach `mcs status`
  weiterhin einwandfrei.

  Doku nachgezogen: `CLAUDE.md` (Regel auf `mcs an`/`aus` umgeschrieben, dazu
  die Falle mit den `enable`-Verweisen; `/usr/local/bin/{mcs,minecraft-modus}`
  → `mcs`) und `pi-manager-status.md` (Werkzeugliste, Pl3xMap-502-Hinweis).
  Ältere Einträge, die das Skript als *Vergangenheit* erwähnen, bleiben
  bewusst stehen.

### A-P5 — Weboberfläche und Portkonflikt

Pl3xMap benutzt standardmäßig ebenfalls Port 8080. Die Installation weicht
jetzt aus.

```bash
grep MCS_ADMIN_PORT ~/mcs/admin/.env
ss -ltnp | grep -E ':(8080|8081)'
```

Erwartet: Weboberfläche und Karte auf **verschiedenen** Ports, beide
erreichbar. Die Weboberfläche im Browser öffnen und anmelden.

- [x] **geprüft am 29.08.2026 · Ergebnis: bestanden, kein Konflikt.**

  ```
  Weboberfläche  8080   (.env, es lauscht python3 auf 0.0.0.0:8080)
  Pl3xMap        8090   (plugins/Pl3xMap/config.yml, java auf 127.0.0.1:8090)
  ```

  Verschiedene Ports. Die 8080-Regeln in `ufw` (LAN + tailscale0) sind
  unverändert.

  **Nebenbefund, behoben:** Der Installationslauf meldete
  „Port 8080 ist belegt (von python3). Die Weboberfläche benutzt stattdessen
  Port 8081." — beides irreführend. Der „Beleger" war die eigene, gerade
  laufende Oberfläche, und benutzt wurde anschließend weiter 8080, weil die
  bestehende `.env` unverändert bleibt (Schritt 3/5). Wer der Meldung folgt,
  sucht die Oberfläche auf einem Port, auf dem nichts lauscht.

  Ursache: Die Portsuche in `install-admin.sh` lief, *bevor* geprüft wurde, ob
  schon eine `.env` existiert. Behoben — liegt ein `MCS_ADMIN_PORT` vor, gilt
  der, und die Suche entfällt.

  Das Öffnen im Browser und die Anmeldung gehören zu C-P1/C-P2.

### A-P6 — Der Benutzername stimmt überall

Kernbefund B1: Es gibt keinen Benutzer `pi` mehr.

```bash
grep -r 'pi' ~/mcs/mcs.conf
systemctl cat minecraft.service mcs-admin.service | grep -E '^(User|Group)='
sudo grep '' /etc/sudoers.d/mcs-admin
```

Erwartet: überall der tatsächliche Benutzername, nirgends `pi` — sofern der
Benutzer nicht zufällig doch so heißt.

- [x] **geprüft am 29.08.2026 · Ergebnis: bestanden — mit dem Vorbehalt, den
  der Punkt selbst nennt.**

  Der Benutzer auf diesem Pi heißt tatsächlich `pi` (`whoami` → `pi`), und
  überall steht `pi`:

  ```
  mcs.conf              MCS_USER=pi, MCS_DIR=/home/pi/mcs, ...
  minecraft.service     User=pi  Group=pi
  mcs-admin.service     User=pi  Group=pi
  ```

  **Dieser Pi kann Befund B1 also nicht widerlegen.** Hier stimmt jedes `pi`
  zufällig — ein hartkodiertes und ein korrekt ermitteltes sehen identisch
  aus. Der Punkt ist damit nur *auf diesem Gerät* abgehakt; ob der Name
  wirklich ermittelt statt angenommen wird, zeigt allein ein Pi mit einem
  anderen Benutzernamen (der Container-Abnahmetest prüft genau das).

---

## Offen aus Etappe B (Stand 28.08.2026)

### B-P1 — RCON ist von außen NICHT erreichbar

Der wichtigste Punkt dieser Etappe. Am 28.08. nachgemessen: RCON lauscht auf
**allen** Netzwerkkarten (`RCON running on 0.0.0.0:25575`) und lässt sich nicht
auf die lokale Adresse beschränken — einen Schlüssel `rcon.ip` gibt es nicht.
Die Firewall ist damit die einzige Abschottung.

Auf dem Pi:

```bash
ss -ltn | grep 25575 && sudo ufw status | grep 25575
```

Erwartet: Der Port lauscht, und `ufw` zeigt eine `DENY`-Regel dafür.

**Und dann von einem ANDEREN Gerät im Netz** (Laptop, Handy):

```bash
nc -vz -w 3 <pi-adresse> 25575
```

Erwartet: **keine** Verbindung. Kommt eine zustande, kann jeder im Heimnetz,
der das Passwort aus der `server.properties` liest, den Server fernsteuern.

- [~] **angesehen am 29.08.2026 · Ergebnis: derzeit nicht prüfbar — muss nach
  B-P2 wiederholt werden.**

  Auf diesem Pi ist RCON noch gar nicht eingerichtet:

  ```
  mcs rcon list  -> Fehler: RCON ist nicht eingerichtet: In der
                    server.properties fehlt 'rcon.password', oder
                    'enable-rcon' steht nicht auf true.
  ss -ltn | grep 25575  -> nichts
  ```

  Damit ist der Port zwar unerreichbar, aber nur weil es ihn nicht gibt —
  das beweist nichts über die Abschottung. **Die Risikoreihenfolge der Liste
  setzt hier voraus, dass RCON bereits läuft; auf einem Pi aus der Zeit davor
  ist sie umgekehrt: erst B-P2, dann B-P1.**

  Was schon geprüft ist: Die Firewall ist aktiv mit
  `Default: deny (incoming)`, also ist 25575 auch nach dem Einrichten nicht
  von außen erreichbar. Die von K1 zusätzlich verlangte **ausdrückliche**
  `DENY`-Regel fehlt noch — sie wird von `install.sh` angelegt, aber nur wenn
  `enable-rcon=true` schon in der Datei steht (`install.sh`, Zeile 1030 ff.).
  Sie kommt also im selben Lauf wie B-P2.

  Vor B-P2 geprüft, weil beides Fallen wären:
  - `install.sh` setzt eine **bereits aktive** Firewall nicht neu auf, es
    ergänzt nur Regeln (Zeile 1039 ff.). Die sorgfältig gesetzten LAN-Regeln
    für Time Machine, Home Assistant, Beszel, Cockpit, Glance und die Widgets
    bleiben also erhalten.
  - Eine **bestehende** `server.properties` wird nicht angetastet (Zeile 559,
    565, 828). `level-name=MeineWelt` ist damit sicher, und die Firewall-Regel
    liest den echten Port 25570 aus der Datei (Zeile 944), nicht die 25565
    aus der Vorlage.

### B-P2 — RCON auf der bestehenden Installation nachholen

`install.sh` richtet RCON nur bei **gestopptem** Server ein. Der Grund ist
seit der Messung zu Etappe C genauer bekannt (Korrektur K3): Paper schreibt
die `server.properties` nicht beim Herunterfahren neu, sondern beim Start —
und noch einmal jedes Mal, wenn ein Befehl eine dort gespeicherte Einstellung
ändert. Eine Änderung von außen kann also jederzeit lautlos verschwinden,
nicht erst am Ende.

Auf einem Pi, auf dem der Server läuft, muss das also einmal nachgeholt werden:

```bash
mcs stop && ./install.sh --standard && mcs status
grep -E '^(enable-rcon|rcon.port|broadcast-rcon-to-ops)=' ~/mcs/mc_server/server.properties
mcs rcon list
```

Erwartet: `enable-rcon=true`, und `mcs rcon list` liefert eine **Antwort**.

- [x] **geprüft am 29.08.2026 · Ergebnis: bestanden — nach einem behobenen
  Befund im Skript selbst.**

  **Der erste Versuch brach sofort ab:**

  ```
  ===== 0/7: Vorab-Prüfungen =====
  sudo: a terminal is required to read the password
  Fehler: 'pi' darf kein sudo ausführen (oder das Passwort war falsch).
  ```

  Die Meldung zeigte in die falsche Richtung — `pi` hat `NOPASSWD: ALL`.
  Gemessen, welche Form ohne Terminal funktioniert:

  ```
  sudo -n true  -> OK
  sudo true     -> OK
  sudo -v       -> a terminal is required
  ```

  `sudo -v` frischt den Zeitstempel der Passworteingabe auf und verlangt
  dafür ein Terminal — auch dann, wenn es gar kein Passwort zu prüfen gibt.
  Damit war ausgerechnet `--standard`, der Modus **für Skripte und Tests**,
  ohne Terminal unbenutzbar. Behoben in `install.sh`: erst `sudo -n true`,
  und nur wenn das scheitert *und* ein Terminal da ist, wird nachgefragt.

  **Danach lief der Durchgang durch. Ergebnis:**

  ```
  enable-rcon=true
  rcon.port=25575
  broadcast-rcon-to-ops=false
  rcon.password           gesetzt
  server.properties       Rechte 600          (K2 erfüllt)
  level-name=MeineWelt         UNVERÄNDERT         (die Falle hat nicht gegriffen)
  mcs rcon list           "There are 0 of a max of 5 players online:"
  ```

  **K1 auf echter Hardware bestätigt:** `ss -ltn` zeigt `*:25575` — RCON
  bindet tatsächlich an alle Netzwerkkarten, wie im Container gemessen.
  Die ausdrückliche Sperre ist jetzt da, für v4 **und** v6:

  ```
  25575/tcp        DENY  Anywhere
  25575/tcp (v6)   DENY  Anywhere (v6)
  ```

  Die bestehenden Firewall-Regeln haben den Lauf unverändert überstanden
  (22 ALLOW / 3 DENY vorher, Time Machine, Home Assistant, Beszel, Cockpit,
  Glance und Widgets alle noch da). Der Lauf hat den echten Serverport 25570
  erkannt, nicht die 25565 aus der Vorlage.

### B-P3 — Der Verlauf füllt sich wirklich

Der Sammler läuft im Dienst der Weboberfläche; im Container ließ sich das
nicht prüfen, weil dort kein systemd arbeitet.

Nach etwa einer Stunde Laufzeit:

```bash
sqlite3 ~/mcs/admin/metrik.db "SELECT COUNT(*), MIN(datetime(zeit,'unixepoch','localtime')), MAX(datetime(zeit,'unixepoch','localtime')) FROM messwerte;"
sqlite3 ~/mcs/admin/metrik.db "SELECT datetime(zeit,'unixepoch','localtime'), cpu, ram, temp, tps, mspt, spieler FROM messwerte ORDER BY zeit DESC LIMIT 5;"
```

Erwartet: rund 60 Zeilen, plausible Werte, **TPS nahe 20** und eine Temperatur,
die nicht `NULL` ist. Steht dort überall `NULL` bei `tps`, kommt RCON nicht
durch — dann B-P2 prüfen.

Nach ein paar Tagen: `ls -lh ~/mcs/admin/metrik.db` — die Datei darf nicht über
ein paar Megabyte wachsen.

- [x] **geprüft am 29.08.2026 · Ergebnis: bestanden.**

  Nach 55 Minuten Laufzeit:

  ```
  50 Zeilen, von 2026-08-29 09:36:00 bis 2026-08-29 10:30:00
  Datei: 4,0 KB

  zeit                 cpu  ram   temp  tps   mspt  spieler
  2026-08-29 10:30:00  4.9  50.9  45.5  20.0  0.1   0
  2026-08-29 10:29:00  4.9  50.4  45.0  20.0  0.1   0
  ```

  Eine Zeile je Minute, **TPS 20,0**, `mspt` 0,1 (Leerlauf), Temperatur in
  **keiner** Zeile `NULL`.

  **Zu den 11 `NULL`-Werten bei `tps`:** Sie liegen alle am Anfang und haben
  eine belegbare Ursache — nicht die, vor der der Punkt warnt, sondern deren
  Vorgeschichte:

  ```
  tps NULL:      09:36:00 bis 09:49:00
  tps hat Werte: ab 09:52:00
  RCON eingerichtet (server.properties geschrieben): 09:51:50
  ```

  Der Sammler lief also vor B-P2 ins Leere, weil es RCON schlicht noch nicht
  gab. Genau der Fall, den der Punkt beschreibt („Steht dort überall `NULL`
  bei `tps`, kommt RCON nicht durch — dann B-P2 prüfen") — hier bereits
  behoben. Die Größenprüfung über mehrere Tage steht noch aus; bei 4 KB für
  50 Zeilen ist nichts zu befürchten.

### B-P4 — Die Weboberfläche nach der Aufteilung

`app.py` war eine Datei mit 980 Zeilen und ist jetzt auf zehn Module verteilt.
Nach dem Ausrollen muss der Dienst neu starten, sonst läuft die alte Fassung
weiter:

```bash
./deploy.sh && sudo systemctl restart mcs-admin.service
systemctl status mcs-admin.service --no-pager | head -5
```

Dann die Oberfläche im Browser öffnen: Startseite, Logs, `server.properties`
bearbeiten, eine Chat-Nachricht senden. Alles muss aussehen und funktionieren
wie vorher — an der Oberfläche selbst wurde in dieser Etappe **nichts**
geändert, das kommt erst in Etappe C.

- [x] **geprüft am 29.08.2026 · Ergebnis: bestanden.**

  Ausgerollt und neu gestartet; alle sieben Seiten wurden angemeldet
  abgerufen. Ein fehlendes oder falsch eingebundenes Modul fiele hier als
  `500` auf:

  ```
  PFAD             HTTP   BYTES   TITEL
  /                200     7335   PiCraft
  /spieler         200     9220   Spieler — PiCraft
  /leistung        200    11782   Leistung — PiCraft
  /konfiguration   200    27936   Konfiguration — PiCraft
  /backups         200    39011   Backups — PiCraft
  /plugins         200    12550   Plugins — PiCraft
  /karte           200     4179   Weltkarte — PiCraft
  ```

  Dass die Seiten auch inhaltlich arbeiten, zeigen die anderen Punkte:
  `server.properties` bearbeiten über C-P5 (Vormerkung), Statusabfragen über
  C-P4. Die Beurteilung des **Aussehens** braucht ein Auge und steht in C-P3.

  > Anmerkung zur Formulierung des Punktes: „an der Oberfläche wurde in
  > dieser Etappe **nichts** geändert" stimmt für Etappe B, wird hier aber
  > zwangsläufig zusammen mit Etappe C geprüft — auf dem Pi lag bis heute
  > der B-Stand. Geprüft ist also die C-Oberfläche auf der B-Modulstruktur.

---

## Offen aus Etappe C (Stand 28.08.2026)

### C-P1 — Die neue Oberfläche kommt vollständig an

Das größte Risiko beim Ausrollen ist nicht ein Fehler im Code, sondern eine
Datei, die nicht mitkopiert wurde. Bis Etappe C bestand die Oberfläche aus
einer einzigen HTML-Datei, die in `install-admin.sh` und `deploy.sh`
namentlich stand. Jetzt sind es zwei Verzeichnisbäume (`templates/`,
`static/`), und beide Skripte laufen sie durch. Fehlt dabei etwas, sieht man
keine Fehlermeldung — man sieht eine Seite ohne Gestaltung.

```bash
./deploy.sh && sudo systemctl restart mcs-admin.service
```

Danach vergleichen, ob wirklich alles dort ist:

```bash
find ~/PiCraft/admin/templates ~/PiCraft/admin/static -type f | wc -l
find ~/mcs/admin/templates ~/mcs/admin/static -type f | wc -l
```

Erwartet: **dieselbe Zahl**. Dann im Browser öffnen — die Seite muss dunkel
sein, eckig, mit Reiterleiste. Ist sie weiß und unformatiert, fehlt
`static/mcs.css`.

Und die alte Oberfläche darf nicht liegenbleiben:

```bash
ls ~/mcs/admin/templates/index.html    # muss "No such file" sagen
```

- [x] **geprüft am 29.08.2026 · Ergebnis: bestanden.**

  ```
  Repo: 28 Dateien     Pi: 28 Dateien      -> gleiche Zahl
  ~/mcs/admin/templates/index.html   -> No such file (richtig entfernt)
  ~/mcs/admin/static/mcs.css         -> vorhanden, 23901 Bytes
  ```

  Die Oberfläche antwortet auf `http://127.0.0.1:8080/` mit `302` nach
  `/anmelden?weiter=/` — und **ohne** `WWW-Authenticate`-Kopfzeile. Die
  Umstellung weg von HTTP Basic Auth ist damit auch auf dem Pi wirksam.
  Die Beurteilung des Aussehens (dunkel, eckig, Reiterleiste) gehört zu
  C-P3 und braucht ein echtes Auge.

### C-P2 — Anmeldung mit Sitzungs-Cookie

Die Anmeldung lief bisher über HTTP Basic Auth und läuft jetzt über ein
Cookie. Der Browser hat die alten Zugangsdaten möglicherweise noch
gespeichert — deshalb einmal in einem **privaten Fenster** prüfen, sonst
testet man den Zwischenspeicher des Browsers.

```bash
grep -c '^MCS_ADMIN_SECRET=' ~/mcs/admin/.env    # muss 1 sein
stat -c '%a' ~/mcs/admin/.env                     # muss 600 sein
```

Steht dort **keine** Zeile `MCS_ADMIN_SECRET` (das ist auf einer bestehenden
Installation der Normalfall, weil die `.env` nicht überschrieben wird), zeigt
die Oberfläche oben eine gelbe Warnung an, und jeder Neustart des Dienstes
meldet alle ab. Dann eine erzeugen und eintragen:

```bash
head -c 512 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9' | head -c 48; echo
```

Im Browser dann:

1. Anmelden — es kommt eine Seite mit Formular, **kein** Browser-Dialog.
2. „Abmelden" drücken. Danach führt jeder Aufruf zurück zum Formular.
3. Fünfmal ein falsches Passwort eingeben. Beim sechsten Mal muss die
   Sperre greifen — **auch mit dem richtigen Passwort**.
4. Fünf Minuten warten, dann geht es wieder.

- [~] **Punkte 2, 3 und 4 geprüft am 29.08.2026 · Ergebnis: bestanden.
  Offen bleibt nur Punkt 1 im privaten Fenster.**

  **Punkt 2 (Abmelden):** `POST /abmelden` antwortet mit `302` nach
  `/anmelden`; danach führt jeder Aufruf zurück zum Formular
  (`GET /` → `302` nach `/anmelden?weiter=/`, `GET /spieler` ebenso).
  Die Gegenprobe ohne Token: `403`. Der CSRF-Schutz greift also auch beim
  Abmelden.

  > ⚠️ Beim ersten Anlauf kam genau diese `403` — und sah aus wie ein
  > Befund am Abmelden. Es war der Prüfaufruf: Das Token steht in
  > `basis.html` als `hx-headers='{"X-CSRF-Token": "…"}'`, nicht als
  > Formularfeld. Wer es sich aus der Seite herausschneidet, muss diese
  > Stelle treffen. Erst danach ließ sich Punkt 2 überhaupt prüfen.

  **Punkt 4 (die Sperre läuft ab):** nach den fünf Fehlversuchen aus
  Punkt 3 gemessen, von `127.0.0.1`:

  ```
  nach 120 s   "Zu viele Fehlversuche. Bitte 3 Minuten warten"   GET / -> 302
  nach 320 s   Anmeldung mit dem richtigen Passwort -> 302 nach /
               GET / -> 200,  GET /spieler -> 200
  ```

  Entscheidend ist die letzte Zeile des Laufs: **Die PID der Weboberfläche
  war vorher und nachher dieselbe (1159).** Sonst wäre nur bewiesen, dass
  ein Neustart die Zählung vergisst — die Sperre ist wirklich durch
  Zeitablauf gefallen. Die Grenzen stehen in `sicherheit.py`:
  `VERSUCHE_ERLAUBT = 5`, `SPERRE = 5 * 60`, `MERKDAUER = 15 * 60`.

  Nachgelesen und nicht nur vermutet: Ein Versuch **während** der Sperre
  wird nicht als weiterer Fehlversuch gezählt (`seite_anmeldung.py`, der
  `if rest:`-Zweig kommt vor `fehlversuch_merken`). Die Sperre verlängert
  sich also nicht, solange jemand weiter probiert — sonst käme man nie
  wieder hinein.

- [~] **teilweise geprüft am 29.08.2026 · Ergebnis: Punkt 3 bestanden, der
  Rest braucht einen Browser.**

  Vorbedingungen erfüllt:

  ```
  grep -c '^MCS_ADMIN_SECRET=' ~/mcs/admin/.env   -> 1   (48 Zeichen)
  stat -c '%a' ~/mcs/admin/.env                    -> 600
  ```

  Die Anmeldeseite liefert ein **Formular** (`benutzer`, `passwort`,
  `csrf_token`, `weiter`), keinen Browser-Dialog. Die gelbe Warnung wegen
  fehlendem Sitzungsschlüssel erscheint korrekt **nicht** — `deploy.sh` hat
  ihn beim Ausrollen nachgetragen.

  **Punkt 3 geprüft** (von `127.0.0.1`, damit keine echte Adresse gesperrt
  wird):

  ```
  Versuch 1–5 (falsches Passwort):  "Das Passwort stimmt nicht."
  Versuch 6 mit dem RICHTIGEN Passwort:
      HTTP 200 (Formular erneut, keine Anmeldung)
      "Zu viele Fehlversuche. Bitte 5 Minuten warten und es dann noch einmal…"
      /api/status danach -> 302  (keine Sitzung entstanden)
  ```

  Genau wie in E4 vorgesehen: fünf Versuche, beim sechsten die Sperre — und
  sie lässt auch das richtige Passwort nicht durch. Sonst wäre sie wertlos.

  > ⚠️ **Messfalle, in die ich zuerst selbst getappt bin — und die diesen
  > Nachweis beinahe verfälscht hätte:** Der Schlüssel in der `.env` heißt
  > `MCS_ADMIN_PASSWORD` (englisch), nicht `MCS_ADMIN_PASSWORT`. Mein erster
  > Durchgang las den deutschen Namen, bekam eine leere Zeichenkette und
  > schickte damit **zweimal dasselbe falsche Passwort**. Die Ausgabe („Zu
  > viele", kein `Set-Cookie") sah exakt aus wie ein bestandener Test.
  >
  > Wer diesen Punkt automatisiert prüft, muss also nachweisen, dass er
  > wirklich das richtige Passwort geschickt hat — sonst prüft er nur, dass
  > eine Sperre falsche Passwörter abweist, und das ist die triviale Hälfte.
  > In einem sonst durchgehend deutschen Projekt ist dieser eine englische
  > Schlüssel eine echte Stolperstelle.

  **Offen, weil nur im Browser zu machen:** Anmelden im **privaten Fenster**
  (Punkt 1, sonst testet man den Zwischenspeicher), „Abmelden" (Punkt 2) und
  das Auslaufen der Sperre nach fünf Minuten (Punkt 4).

### C-P3 — Sieht es auf dem Handy gut aus?

Das ist das meistbenutzte Gerät (Lastenheft) und lässt sich am Schreibtisch
nur schlecht beurteilen. Am Telefon prüfen:

- Passen die sechs Kacheln auf einen Bildschirm, ohne zu wischen?
- Lässt sich die Reiterleiste seitlich schieben, und ist der aktive Reiter
  sichtbar?
- Ist im Dunkeln nichts blendend hell?
- Reagiert ein Knopfdruck spürbar (die Fase dreht sich um)?

- [ ] geprüft am ________ · Ergebnis: ______________________________

### C-P4 — Wie oft fragt die Oberfläche wirklich bei RCON nach?

Beim Bau der Startseite ist aufgefallen, dass jede Statusabfrage zwei
RCON-Befehle auslöste — bei einer Erneuerung alle fünf Sekunden also
vierundzwanzig je Minute, im Hauptthread des Servers. Seit Etappe C gilt ein
gemessener Wert zwanzig Sekunden lang (`tps` und `mspt` liefern ohnehin
Minutenmittel). Auf dem Pi nachsehen, ob das wirkt:

```bash
mcs console          # mitlesen, Verlassen mit Strg+A, dann D
```

Oder ruhiger, ohne die Konsole zu belegen: die Oberfläche eine Minute lang
offen lassen und danach zählen, wie viele RCON-Verbindungen der Server
protokolliert hat.

```bash
grep -c 'Thread RCON Client' ~/mcs/mc_server/logs/latest.log
```

Erwartet: rund **sechs** Verbindungen je Minute (drei Abfragen à zwei
Befehle), nicht vierundzwanzig.

- [x] **geprüft am 29.08.2026 · Ergebnis: bestanden — der Zwischenspeicher
  wirkt. Die erwartete Zahl im Punkt ist um eine Runde zu niedrig.**

  Statt die Seite von Hand offen zu lassen, wurden zwölf Statusabfragen im
  Abstand von fünf Sekunden geschickt — genau das, was die offene Startseite
  tut:

  ```
  Zeitraum:            10:33:26 bis 10:34:29 (60 s)
  Statusabfragen:      12
  RCON-Verbindungen:   12   (ohne Zwischenspeicher waeren es 24)
  ```

  Die Grundlast ohne offene Oberfläche liegt bei **4** Verbindungen je Minute
  (im Log über 10:27–10:32 und 10:34 durchgehend). Auf die Statusabfragen
  entfallen also **8**.

  Acht, nicht sechs — und das ist richtig so: Bei einem Zwischenspeicher von
  zwanzig Sekunden liegen in einer Minute **vier** Auffrischungen (bei 0, 20,
  40 und 60 s), nicht drei. Vier Runden à zwei Befehle sind acht. Der Punkt
  rechnet mit drei Runden und kommt deshalb auf sechs.

  Entscheidend ist der Vergleich mit der Ausgangslage: **8 statt 24**. Der
  Zwischenspeicher tut, was er soll.

### C-P5 — Die Vormerkung im echten Betrieb

Der Container prüft den Übergang bereits (Abnahmetest 4 und 6b), aber nur
mit einem von Hand abgelegten Merkzettel. Auf dem Pi einmal den ganzen Weg
gehen — er führt über zwei Prozesse und einen Neustart:

```bash
mcs start        # der Server muss LAUFEN, sonst wird direkt geschrieben
```

Dann in der Oberfläche unter *Leistung* die Sichtweite ändern und speichern.
Erwartet: eine gelbe Meldung „Vorgemerkt", **nicht** „Gespeichert".

```bash
ls -l ~/mcs/vorgemerkt/
grep '^view-distance=' ~/mcs/mc_server/server.properties   # noch der ALTE Wert
```

Jetzt neu starten und nachsehen:

```bash
mcs restart
grep '^view-distance=' ~/mcs/mc_server/server.properties   # der NEUE Wert
ls ~/mcs/vorgemerkt/                                        # muss leer sein
ls ~/mcs/mc_server/server.properties.vor-vormerkung-*       # die Vorfassung
```

Und die Gegenprobe, die zeigt, warum es die Vormerkung überhaupt gibt: bei
laufendem Server von Hand die `motd` ändern, danach `mcs rcon "whitelist on"`
schicken und noch einmal nachsehen. Die Handänderung muss verschwunden
sein — genau das passiert der Weboberfläche ohne Vormerkung.

- [x] **geprüft am 29.08.2026 · Ergebnis: bestanden, zweimal durchlaufen.
  Die Gegenprobe hat K3 dabei präzisiert.**

  **Der Weg über zwei Prozesse und einen Neustart** (`view-distance` 16 → 15
  über die Leistungsseite, bei laufendem Server):

  ```
  Meldung:            "Vorgemerkt. Der Server läuft gerade, und Paper würde
                       die Änderung überschreiben — sie wird beim näch..."
  server.properties:  view-distance=16      (noch der ALTE Wert)
  ~/mcs/vorgemerkt/:  server.properties     (72 Zeilen, darin view-distance=15)
  ```

  Nach `mcs restart`:

  ```
  server.properties:  view-distance=15      (der NEUE Wert)
  ~/mcs/vorgemerkt/:  leer
  Vorfassung:         server.properties.vor-vormerkung-20260829-103600
  ```

  Anschließend genauso von 15 zurück auf 16 — der Ausgangswert der
  Optimierung vom 27.07. ist wiederhergestellt.

  > ⚠️ `mcs restart` kehrt **sofort** zurück („Neustart eingeleitet"). Wer
  > direkt danach die Datei prüft, sieht noch den alten Wert und hält den
  > Punkt für gescheitert. Erst nach dem Hochlaufen messen — `pgrep java`
  > oder `systemctl show minecraft.service -p ActiveEnterTimestamp`.

  **Die Gegenprobe — und eine Korrektur an K3:**

  ```
  motd von Hand auf "K3-PROBE-2026-08-29" gesetzt
  mcs rcon "whitelist on"   -> "Whitelist is already turned on"
    motd danach: K3-PROBE-2026-08-29        UNVERAENDERT
  mcs rcon "whitelist off"  -> "Whitelist is now turned off"
    motd danach: §2§lMinecraft or die       HANDAENDERUNG WEG
  mcs rcon "whitelist on"   -> wieder an, white-list=true
  ```

  K3 sagt, Paper schreibe die Datei neu, „sobald ein Befehl eine dort
  gespeicherte Einstellung ändert". Genauer ist: **sobald er sie tatsächlich
  ändert.** Ein `whitelist on` auf eine bereits aktive Whitelist ist ein
  Nullvorgang und löst nichts aus — die Handänderung überlebte ihn.

  Das ist mehr als eine Feinheit: Wer die Falle mit dem Befehl aus dem Punkt
  nachstellen will und die Whitelist schon an hat, sieht **nichts passieren**
  und schließt daraus, die Falle gebe es nicht. Sie ist aber echt — mit einer
  Änderung, die wirklich eine ist, war die Handänderung sofort weg.

### C-P6 — Sehen die Kurven nach echten Daten aus?

Im Container gibt es keine Verlaufsdaten; die Kurven wurden gegen
Attrappenwerte gezeichnet. Auf dem Pi nach ein paar Tagen Laufzeit:

- Zeigt *Leistung* über **7 Tage** eine durchgehende Kurve, oder klafft
  nachts eine Lücke? (Eine Lücke ist richtig, wenn der Server pausiert —
  `pause-when-empty-seconds`. Eine Lücke bei laufendem Server nicht.)
- Fällt die TPS-Kurve dort ein, wo tatsächlich jemand gespielt hat?
- Sind die Achsen deutsch beschriftet (`20:00`, nicht `8pm`)?
- Lädt die Seite auf dem Handy zügig? Sieben Tage sind rund 10.000
  Messwerte, ausgedünnt auf 1.500 Punkte.

> **Bevor eine Lücke als Ausfall gilt** (nachgemessen am 30.08.2026): Der
> Sammler schreibt **nur, während der Minecraft-Server läuft** — so gebaut
> und in `metrik.py` begründet, denn sonst füllte sich die Datenbank über
> eine Sommerpause mit Zehntausenden Nullzeilen, und die Kurve zeigte
> hinterher eine flache Linie, wo schlicht nichts lief.
>
> In der Datenbank standen 772 Werte über 35 Stunden — auf den ersten Blick
> viel zu wenig für „einer je Minute". Die größte Lücke (29.08. 21:53 bis
> 30.08. 18:28, 20,6 h) deckte sich aber **auf die Minute** mit der Zeit, in
> der der Dienst gestoppt war. Wer das prüft, vergleicht die Lücken zuerst
> mit `journalctl -u minecraft`, bevor er den Sammler verdächtigt. Erst eine
> Lücke bei *laufendem* Server ist ein Befund.

- [~] **Zwischenstand vom 29.08.2026 · Ergebnis: Was heute prüfbar war,
  stimmt. Das Sieben-Tage-Bild braucht weiter Zeit.**

  Nach elf Stunden Laufzeit: 575 Zeilen von 09:36 bis 20:18, eine je
  Minute, `temp` in keiner Zeile `NULL`, TPS 20,0.

  **Die beiden Lücken sind erklärt und beide richtig:**

  ```
  09:40 -> 09:44  (4 min)    Neustart der Weboberfläche beim Ausrollen
  18:39 -> 19:40  (61 min)   "mcs aus" + Neustart  (A-P1, Schritte 2-4)
  ```

  Die zweite Lücke ist sogar ein Beleg: Der Sammler steckt im Dienst
  `mcs-admin`, und den schaltet der Hauptschalter mit ab. Eine Lücke bei
  abgeschaltetem PiCraft ist also kein Ausfall, sondern die Anzeige davon.

  **Die Achsen sind deutsch** (`leistung.html` formatiert mit
  `Intl.DateTimeFormat("de-DE", …)`), und die Ausdünnung steht in
  `metrik.py`: `verlauf(stunden, hoechstens=1500)` greift gleichmäßig
  heraus, der Bereich "7 Tage" ist als `24 * 7` angelegt.

  > ⚠️ **Die Größenprüfung im Punkt misst die falsche Datei.**
  > `ls -lh ~/mcs/admin/metrik.db` zeigt seit dem ersten Tag **4,0 KB** —
  > und das bleibt so, egal wie viele Messwerte dazukommen. Die Datenbank
  > läuft im WAL-Modus; die Daten liegen in `metrik.db-wal` und wandern
  > erst bei einem Checkpoint (Schwelle: 1000 Seiten = 4 MB) in die
  > Hauptdatei. Heute Abend: Hauptdatei 4 KB, WAL **2,4 MB**.
  >
  > Richtig ist `du -ch ~/mcs/admin/metrik.db*`. Zu befürchten ist
  > trotzdem nichts: `AUFBEWAHRUNG_TAGE = 7` deckelt den Bestand bei rund
  > 9.000 Zeilen, und der WAL selbst deckelt bei ~4 MB.

### C-P7 — Die Spielerseite mit echten Spielern

Im Container gab es genau einen erfundenen Spieler. Auf dem Pi mit echten:

- Stimmt die **Spielzeit**? Sie kommt aus
  `<welt>/players/stats/<uuid>.json` (auf einer Welt im alten Format:
  `<welt>/stats/`), Schlüssel `minecraft:play_time`, in Ticks.
  Gegenprobe im Spiel: `/stats` oder das Statistikmenü im Pausenbildschirm.
- Steht bei jedem eine **letzte Adresse**? Die Zeile dafür schreibt
  `log_player_activity.sh` erst seit Etappe C — bei Spielern, die seither
  nicht da waren, bleibt sie leer. Das ist richtig, sieht aber aus wie ein
  Fehler.
- **Kicken und Sperren** einmal wirklich ausprobieren, am besten mit einem
  Zweitkonto. Erwartet: Der Spieler fliegt sofort raus, und die Zeile in der
  Liste sieht danach anders aus.
- `whitelist add` **ohne Internet**: Netzwerkstecker ziehen und es
  versuchen. Erwartet: eine Meldung, die sagt, dass der Server den Namen bei
  Mojang nachschlagen muss — nicht „RCON kaputt".

- [~] **teilweise geprüft am 29.08.2026 · Ergebnis: Ein Befund gefunden und
  behoben — die Spielzeit war auf diesem Pi für ALLE Spieler leer. Kicken
  und Sperren brauchen weiter echte Spieler.**

  **Der Befund:** `spieler.py` las die Statistiken aus
  `<welt>/stats/<uuid>.json`. Diesen Ordner gibt es hier nicht:

  ```
  ~/mcs/mc_server/MeineWelt/stats/           existiert NICHT
  ~/mcs/mc_server/MeineWelt/players/stats/   12 Dateien
  ~/mcs/mc_server/MeineWelt_oid/stats/       10 Dateien   (Sicherung, altes Format)
  ```

  Seit der Formatumstellung sammelt Minecraft die Spielerdateien unter
  `<welt>/players/` — stats, advancements und playerdata beisammen. Die
  Welt `MeineWelt` ist im April 2026 umgestellt worden; `MeineWelt_oid` ist die
  Sicherung davor und hat ihr `stats/` noch obenauf. Der Code las also den
  Ort, den es nur noch in der Sicherung gibt.

  **Die Folge war nicht sichtbar, und das ist das Unangenehme daran:** Die
  Spielerseite zeigte bei jedem einen Strich. Genau so soll sie es auch
  anzeigen, wenn jemand wirklich nie gespielt hat — "wissen wir nicht" ist
  dort Absicht. Ein leerer Strich sah damit aus wie ein gültiges Ergebnis.

  **Behoben** in `admin/spieler.py`: `stats_ordner()` liefert beide
  Orte, den neuen zuerst; `spielzeit_sekunden()` und `uuid_pfad_frei()`
  benutzen sie. Danach auf dem Pi gemessen:

  ```
  Spieler A        1943683 s   539 h 54 min
  Spieler B        1088571 s   302 h 22 min
  Spieler C         250683 s    69 h 38 min
  Spieler D         152624 s    42 h 23 min
  Spieler E            None   (keine Datei -> Strich, richtig so)
  ```

  Über die Oberfläche gegengeprüft: `/spieler` zeigt dieselben vier Werte.

  **Auch die Tests nachgezogen** — sonst hätte der Container den Fehler
  weiter gedeckt: `tests/oberflaeche-ansehen.sh` legt seine Attrappen jetzt
  in **beiden** Formaten an, und `tests/abnahme-im-container.sh` prüft die
  Spielzeit aus beiden Orten (72000 Ticks → 3600 s). Vorher lag dort nur
  der alte Ort, und der geprüfte Zweig war gerade der, den es auf dem Pi
  nicht gibt.

  **Die letzte Adresse** ist ohne echten Spieler belegt, über die ganze
  Kette statt über eine Behauptung:

  ```
  Paper schreibt:   SpielerA[/192.168.x.y:59125] logged in with entity id 1 …
  MUSTER_ANMELDUNG trifft  -> Name "SpielerA", Adresse "192.168.x.y:59125"
  log_player_activity.sh   -> "SpielerA meldet sich an von 192.168.x.y:59125"
  spieler.py (_ANMELDUNG)  -> liest es zurück, schneidet den Port ab
  ```

  Im Protokoll steht bei den bisherigen Anmeldungen noch keine Adresse —
  der letzte Eintrag stammt vom 28.08. 17:26, und die Zeile schreibt das
  Skript erst seit Etappe C (ausgerollt am 29.08.). Genau wie der Punkt es
  voraussagt. Sichtbar wird sie bei der nächsten echten Anmeldung.

  **Offen:** Spielzeit im Spiel gegenprüfen (`/stats`), kicken und sperren
  mit einem Zweitkonto, `whitelist add` ohne Internet.

### C-P8 — Die Karte über Tailscale

Der Fall, den nur echte Hardware zeigt: Wird die Oberfläche über Tailscale
mit **HTTPS** aufgerufen, blockiert der Browser einen Rahmen, der auf
`http://` zeigt.

1. Die Oberfläche über die lokale Adresse öffnen (`http://…`) → die Karte
   muss **im Rahmen** erscheinen.
2. Dieselbe Seite über den Tailscale-Namen mit HTTPS öffnen → statt eines
   weißen Kastens muss dort der **Hinweis** stehen, dass sich die Karte hier
   nicht einbetten lässt, und der Knopf „In neuem Tab öffnen" muss
   funktionieren.

- [~] **teilweise geprüft am 29.08.2026 · Ergebnis: Ein Befund gefunden und
  behoben, der noch vor dem HTTPS-Fall liegt. Der Browser-Teil steht aus.**

  Die HTTPS-Erkennung selbst fällt im Browser
  (`window.location.protocol === "https:"`) und ist deshalb mit `curl`
  grundsätzlich nicht prüfbar. Beim Lesen fiel aber etwas anderes auf:

  ```
  plugins/Pl3xMap/config.yml:  bind: 127.0.0.1   port: 8090
  ss -ltnp:                    [::ffff:127.0.0.1]:8090   (nur lokal)
  ufw:                         keine Regel für 8090
  curl http://<pi-adresse>:8090/  ->  HTTP 000 (keine Verbindung)
  nginx:                       proxy_pass http://127.0.0.1:8090
                               server_name meinserver.dedyn.io
  ```

  Die Kartenseite baute ihre Adresse aus `window.location.hostname` plus dem
  Port aus der Config — die **Bindeadresse las sie nicht**. Auf dieser
  Installation horcht Pl3xMap aber nur auf `127.0.0.1`, weil nginx die Karte
  nach außen liefert. Das ist der übliche Fall, sobald ein Reverse-Proxy
  davorsteht.

  **Folge:** Schritt 1 dieses Punktes („über die lokale Adresse öffnen → die
  Karte muss im Rahmen erscheinen") wäre auf diesem Pi fehlgeschlagen —
  leerer Rahmen, sobald man die Oberfläche von einem anderen Gerät als dem Pi
  selbst aufruft. Und der Knopf „In neuem Tab öffnen" hätte auf
  `http://<pi-adresse>:8090/` gezeigt, wo nichts horcht, und zwar unter dem
  Hinweistext „dort funktioniert sie".

  **Behoben:** `seite_karte.py` liest jetzt auch `bind`; das Template zeigt
  bei einer nur lokalen Bindung einen ehrlichen Hinweis samt Weg zur Abhilfe
  und deaktiviert den toten Knopf, statt einen leeren Kasten zu zeigen — im
  Geist des Kommentars, der dort schon stand („lieber sagen, was los ist").
  Ausgerollt und geprüft: `kartenport()` liefert
  `{'port': 8090, 'an': True, 'nur_lokal': True}`, und die Seite enthält
  `const nurLokal = true`.

  **Offen (braucht Browser):** Ob der HTTPS-Zweig beim echten Tailscale-Aufruf
  greift. Auf diesem Pi wird allerdings **zuerst** der neue Hinweis
  erscheinen, weil die lokale Bindung schon vorher zutrifft — der HTTPS-Fall
  ist hier gar nicht erreichbar, solange Pl3xMap auf `127.0.0.1` steht.

### C-P9 — Ein Plugin wirklich installieren

Die Modrinth-Suche wird im Abnahmetest bewusst nicht geprüft — sie braucht
Internet und fremde Server. Auf dem Pi einmal den ganzen Weg gehen:

1. Reiter **Plugins**, nach `chunky` suchen, eine Fassung installieren.
2. Erwartet: Meldung „installiert und geprüft", die Datei liegt als
   `plugins/Chunky.jar`, und in `~/mcs/mc_server/plugins.txt` steht eine
   neue Zeile mit Prüfsumme.
3. `mcs plugins` im Terminal — muss dasselbe sagen.
4. `mcs restart`, dann im Serverlog nachsehen, ob das Plugin geladen wurde.
5. **Danach `./deploy.sh`** und noch einmal in die `plugins.txt` sehen: Die
   neue Zeile muss noch da sein. Wäre sie weg, gehörte die Datei doch nicht
   dem Pi (Entscheidung E6).

- [x] **geprüft am 29.08.2026 · Ergebnis: bestanden, alle fünf Schritte.**

  Der ganze Weg über die Oberfläche, von der Suche bis zum Ausrollen:

  ```
  1) Suche "chunky"   -> chunky, chunkyborder, chunky-extended
  2) Fassungen        -> MdY6JATr
  3) Installiert      -> plugins/Chunky.jar (304616 Bytes)
     plugins.txt:  Chunky|1.5.3|https://cdn.modrinth.com/data/fALzjamp/
                   versions/MdY6JATr/Chunky-Bukkit-1.5.3.jar|530d2c74…
  4) mcs plugins      -> "ok  Chunky 1.5.3"   (5 passend, 0 fehlend, 0 Fehler)
     mcs restart      -> "Initialized 7 plugins … Chunky (1.5.3), GSit …"
  5) ./deploy.sh      -> "0 Datei(en) ausgerollt", Chunky-Zeile unverändert da
  ```

  **Entscheidung E6 hält:** `deploy.sh` fasst die `plugins.txt` des Pi nicht
  an; im Repository liegt Chunky nur als auskommentierter Vorschlag in
  `plugins.txt.beispiel`. Ein über die Oberfläche installiertes Plugin
  überlebt das Ausrollen also.

  Nebenbei bestätigt: `mcs plugins` meldet `hsrails` und `villagertalk` als
  „liegt auf dem Pi, steht aber nicht in der Liste" und löscht sie **nicht** —
  wie in `CLAUDE.md` festgehalten (keine öffentliche Bezugsquelle).

  Auch **E7** ist damit belegt: Die Modrinth-Anfragen liefen ausschließlich auf
  den ausdrücklichen Klick hin; die übrigen sechs Seiten wurden vorher ohne
  jede Verbindung nach außen ausgeliefert.

  > **Chunky ist jetzt dauerhaft installiert.** Es erzeugt Gelände im Voraus
  > und tut von sich aus nichts, ist also harmlos. Wer es nicht will:
  > `rm ~/mcs/mc_server/plugins/Chunky.jar`, die Zeile aus
  > `~/mcs/mc_server/plugins.txt` entfernen, `mcs restart`.

### C-P10 — Wiederherstellen, einmal im Ernst

Der eine Punkt, der die ganze Backup-Kette beweist — und der einzige, den
niemand gern übt. Am besten mit einer Welt, die man notfalls entbehren kann,
oder direkt nach einem frischen Backup.

```bash
mcs stop
```

Dann in der Oberfläche unter **Backups** ein Archiv **prüfen** (das ist
gefahrlos) und anschließend **wiederherstellen** — der Name muss abgetippt
werden.

```bash
mcs start && mcs log
ls -d ~/mcs/mc_server/*.vor-restore-*
```

Erwartet: Der Server startet, die Welt ist die aus dem Backup, und die
bisherigen Weltordner liegen als `*.vor-restore-*` daneben. Erst löschen,
wenn alles gut aussieht.

- [x] **vollständig geprüft am 29.08.2026 abends, unter Aufsicht · Ergebnis:
  bestanden — nach dem schwersten Befund dieser Abnahme. Das
  Zurückspielen war auf diesem Pi vorher unmöglich.**

  **Der Befund: `mcs restore` fand die Welt nicht, die im Archiv lag.**

  ```
  mcs restore backup_2026-08-29_20-29-03.tar.gz --ja
    Prüfe das Archiv...
    Fehler: In …/backup_2026-08-29_20-29-03.tar.gz ist keine Welt namens
            'MeineWelt' enthalten.

  tar -tzf …/backup_2026-08-29_20-29-03.tar.gz | head -1
    MeineWelt/            <- sie ist der ALLERERSTE Eintrag
  ```

  Und `--probe` sagte zur selben Datei "Welt laut Archiv: MeineWelt". Die
  gefahrlose Prüfung war also zufrieden, der Ernstfall scheiterte —
  schlimmer als ein Fehler, der beiden auffällt.

  **Die Ursache** steht in `tools/mcs`, in der Erkennungsschleife:

  ```bash
  if tar -tzf "$ARCHIV" | grep -q "^${W}/"; then
  ```

  `grep -q` hört beim ersten Treffer auf. tar schreibt danach in eine
  geschlossene Pipe, bekommt **SIGPIPE** und endet mit 141. Ganz oben im
  Skript steht `set -o pipefail` — und damit gilt die ganze Pipeline als
  fehlgeschlagen. Aus einem gefundenen Treffer wird ein "nicht gefunden".
  Gemessen:

  ```
  MeineWelt           tar=141  grep=0     -> if-Zweig: NICHT gefunden
  MeineWelt_nether    tar=0    grep=1     -> gibt es wirklich nicht
  MeineWelt_the_end   tar=0    grep=1     -> gibt es wirklich nicht
  ```

  Ausgerechnet der Normalfall löst es aus, gleich doppelt: Der Weltordner
  ist der **erste** Eintrag im Archiv, grep hört also sofort auf. Und
  Schritt 2 des Skripts hat das Archiv unmittelbar davor komplett gelesen,
  es liegt also im Zwischenspeicher — tar ist dadurch schnell genug, um
  überhaupt in die geschlossene Pipe zu geraten. Beim ersten, kalten
  Versuch ließ sich derselbe Aufruf **nicht** nachstellen; er sah aus wie
  ein Zufall. Er ist keiner: Im echten Ablauf ist der Zwischenspeicher
  immer warm.

  **Warum es im Container nie auffiel:** Dort ist das Testarchiv so klein,
  dass tar fertig ist, bevor grep abbricht. Der Fehler braucht eine
  gewachsene Welt — also genau das, was nur der Pi hat.

  **Behoben in `tools/mcs`:** Das Inhaltsverzeichnis wird einmal in eine
  Variable gelesen und mit einem Here-String durchsucht
  (`grep -q "^${W}/" <<<"$INHALT"`). Ein Here-String ist keine Pipeline,
  `pipefail` greift gar nicht erst — und das Archiv wird einmal statt
  viermal gelesen. Dieselbe Bauart steckte in der Liste des Dauerarchivs
  (`find … | grep -q .`); dort ist sie jetzt `find … -print -quit`.

  **Danach der ganze Weg über die Oberfläche, mit Nachweis.** Damit
  belegbar ist, dass wirklich die Archivwelt kommt und nicht die alte
  liegenbleibt, lag vorher eine Markierung in der Welt, die im Archiv
  **nicht** enthalten ist:

  ```
  vorher   MeineWelt/RESTORE-PROBE.txt angelegt (im Archiv: 0 Treffer)
  Prüfen   "Größe 710M, 3811 Einträge, Welt laut Archiv: MeineWelt, level.dat 16K"
  Gegenprobe: falsch abgetippter Name
           -> "Zur Sicherheit muss der Name des Backups genau abgetippt werden"
  Wiederherstellen (Name abgetippt), 24 s:
           "MeineWelt beiseitegelegt als MeineWelt.vor-restore-20260829-205819"
           "Packe die Welten aus... Fertig."
  nachher  MeineWelt/RESTORE-PROBE.txt                       WEG
           MeineWelt.vor-restore-…/RESTORE-PROBE.txt         da
           MeineWelt/ 829M, players/stats mit 12 Dateien
  ```

  Die Markierung ist weg und liegt im beiseitegelegten Ordner: Die Welt
  kommt aus dem Archiv, und die alte ist vollständig gesichert.

  **Server danach:** `Preparing level "MeineWelt"`, `Done (22.901s)`, RCON
  antwortet, alle vier Einheiten aktiv, die Spielzeiten auf der
  Spielerseite unverändert richtig.

  > **Die beiseitegelegten Ordner liegen noch da**
  > (`MeineWelt.vor-restore-20260829-205819`, 829 MB). Wegräumen erst, wenn die
  > Welt im Spiel begutachtet ist:
  > `rm -rf ~/mcs/mc_server/*.vor-restore-20260829-205819`

  > **Merkhilfe zur Aufrufform** (hier zweimal falsch geraten): Das Archiv
  > ist das **erste** Argument, die Schalter kommen danach —
  > `mcs restore <archiv> --probe`. Umgekehrt (`--probe <archiv>`) wird
  > `--probe` als Archivname gelesen: „Backup '--probe' nicht gefunden".

- [~] **Prüf-Teil geprüft am 29.08.2026 mittags · Ergebnis: bestanden.**

  Der gefahrlose Teil — `mcs restore <archiv> --probe`:

  ```
  Prüfe backup_2026-08-29_09-55-27.tar.gz ...
    Größe: 710M, vom 2026-08-29 09:56
    Inhaltsverzeichnis lesbar: 3807 Einträge
    Vollständig ausgepackt: 1001M
    Welt laut Archiv: MeineWelt
    level.dat gefunden: 16K
  Das Backup ist in Ordnung. Verändert wurde nichts.        (Rückgabewert 0)
  ```

  Damit ist mehr belegt als nur „die Datei ist lesbar": Das Archiv lässt sich
  vollständig auspacken, und es enthält **`MeineWelt`** — nicht den
  `world`-Altbestand. Aus „wir haben Backups" ist „wir haben ein geprüftes
  Backup" geworden.

  > **Und genau da lag der Denkfehler, den der Abend aufgedeckt hat:** Aus
  > „geprüft" folgt nicht „zurückspielbar". Dieselbe Datei, die `--probe`
  > für in Ordnung erklärte, ließ sich nicht wiederherstellen — die
  > Prüfung nahm einen anderen Weg durch den Code als der Ernstfall. Wer
  > die Backup-Kette beweisen will, muss sie **zu Ende** gehen. Siehe den
  > Eintrag oben.

---

## Dauerhaft nur auf dem Pi prüfbar

Diese Punkte gelten nicht nur für Etappe A, sondern nach jeder größeren
Änderung an Diensten oder Start-/Stopp-Verhalten:

| | Was | Wie | Stand 29.08. |
|---|---|---|---|
| P-A | Autostart beim Booten | `sudo reboot`, danach `mcs status` | ✅ |
| P-B | Neustart nach Absturz | `pkill -9 -f 'paper[.]jar'`, nach ~10 s muss der Dienst wieder laufen (`Restart=always`) | ✅ |
| P-C | Sauberes Herunterfahren bei `reboot` | Im Server-Log muss „All dimensions are saved" vor dem Ende stehen — kein hartes Abwürgen | ✅ |
| P-D | Temperatur unter Last | `mcs status` während fünf Spielern; dauerhaft über 80 °C heißt Drosselung | ⬜ |
| P-E | Echte Spielbarkeit | Fünf Spieler, hohe Sichtweite, TPS bleibt bei 20 | ⬜ |
| P-F | Firewall sperrt nicht aus | Nach `ufw enable` eine **zweite** SSH-Sitzung öffnen, bevor die erste geschlossen wird | ⬜ |

**P-A und P-C, geprüft am 29.08.2026** — beide fielen bei A-P1 Schritt 5 mit
ab: Nach dem Neustart um 19:42:20 stand der Server um 19:42:34 von selbst
wieder, und die Serverlogs beider Neustarts enden mit
`ThreadedAnvilChunkStorage: All dimensions are saved` (18:39:39 und
19:42:02). Kein hartes Abwürgen.

> Die Zeile im Punkt hieß bis heute „Saving worlds". Paper 26.2 schreibt
> das nicht mehr; wer danach sucht, findet nichts und hält ein sauberes
> Herunterfahren für eines mit Datenverlust.

**P-B, geprüft am 29.08.2026 · bestanden, mit zwei Befunden im Schlepptau:**

```
20:30:47  pkill -9         java weg
20:30:57  Dienst wieder aktiv        (10 s, RestartUSec=10s, NRestarts=1)
20:31:20  "Done (22.141s)"           spielbereit, RCON antwortet
```

> ⚠️ **Der Befehl im Punkt killt die eigene Shell mit.** `pkill -9 -f
> paper.jar` sucht in ganzen Kommandozeilen — und die Kommandozeile, in
> der der Befehl steht, enthält „paper.jar" ebenfalls. Der erste Versuch
> brach hier wortlos ab (Rückgabewert 143), und es sah aus, als sei der
> Test fehlgeschlagen. Richtig ist `pkill -9 -f 'paper[.]jar'`: Die
> eckigen Klammern stehen in der eigenen Kommandozeile mit drin und
> passen dort nicht auf sich selbst. Der Punkt ist entsprechend
> korrigiert.

**Der zweite Befund war der teure** — er kam erst danach heraus, beim
Stoppen: Ein harter Absturz hinterlässt den Sockel der alten
Screen-Sitzung als `(Dead ???)`, und `Restart=always` legt die nächste
daneben. `konsole_laeuft()` in `lib-konsole.sh` suchte nur nach dem
**Namen** und zählte die Leiche als laufenden Server. Die Folgen, alle
gemessen:

```
mcs stop   wartete die vollen 240 s auf einen Server, der weg war,
           warnte danach "Die Welt wurde möglicherweise nicht
           vollständig gespeichert"  (sie war sauber gespeichert),
           und endete mit Fehler -> Dienst im Zustand "failed"
mcs restore verweigerte sich mit "Der Server läuft noch."
```

Das Zurückspielen war damit **ausgerechnet nach einem Absturz gesperrt** —
in dem Fall, für den es die Backups gibt. Und die Falschmeldung über
möglichen Datenverlust ist genau der Alarm, der falsch liegt und den
A-P2 vermeiden wollte.

**Behoben** in `server/lib-konsole.sh`: `konsole_laeuft()` schließt
`(Dead` aus; `konsole_abraeumen()` räumt zusätzlich mit
`screen -wipe "$KONSOLE_SITZUNG"` ab, weil `-X quit` an einer toten
Sitzung scheitert (`No screen session found`, Rückgabewert 1) — das war
die Ursache für den `failed`-Zustand. Und `server/start-minecraft.sh`
räumt jetzt **vor** dem Start ab, damit sich Leichen nicht über mehrere
Abstürze sammeln.

**Gegenprobe nach dem Fix**, mit demselben Ablauf (Absturz, Neustart,
dann stoppen):

```
alte Fassung gegen den Ist-Zustand:  "Server läuft"   <- falsch
neue Fassung:                        "läuft nicht"    <- richtig
mcs stop:      1 Sekunde (statt 240), "Minecraft-Server gestoppt."
               is-active = inactive, Result = success  (statt failed)
mcs start:     die Leiche ist danach weg, nur die lebende Sitzung steht da
```

---

## Offen aus Etappe D (Stand 30.08.2026)

Diese neun Punkte haben eines gemeinsam: Sie hängen an etwas, das der
Container grundsätzlich nicht hat — an echter Hardware, an einem echten
Internetanschluss oder an einem Konto bei einem fremden Dienst. Was sich
ohne das prüfen ließ, prüft `tests/abnahme-im-container.sh` bereits
(Abschnitte 5a, 10b, 10c, 11).

### D-P1 — Was für ein Gerät ist das, und worauf liegt der Server?

```bash
mcs hardware
```

**Erwartet:** Modell („Raspberry Pi 5 Model B Rev …"), 64-Bit,
Arbeitsspeicher in GB, und die Zeile „Server liegt auf: …".

**Worauf es ankommt:** Die letzte Zeile muss das Speichermedium **richtig**
benennen. Auf einem Pi 5 mit NVMe-HAT heißt das
`NVMe-SSD (nvme0n1)`. Gegenprobe von Hand:

```bash
findmnt -no SOURCE --target ~/mcs
lsblk -o NAME,TYPE,TRAN,ROTA
```

Steht dort etwas anderes als in der Meldung, ist es ein Befund.

**Die zwei Fallen, die hier auffallen würden:**

- Eine **SSD im USB-Gehäuse** darf **nicht** als „Festplatte" gemeldet
  werden. Viele USB-SATA-Brücken melden `rotational=1`, obwohl eine SSD
  dahintersteckt. Richtig ist die Meldung „USB-Datenträger — über USB lässt
  sich nicht sicher sagen, ob SSD oder Festplatte".
- Auf einem **Compute Module** darf der eMMC-Speicher nicht als SD-Karte
  gemeldet werden.

### D-P2 — Die SD-Karten-Warnung

Der wichtigste Text der ganzen Etappe — und der einzige, den man auf einem
Pi mit SSD nie zu sehen bekommt.

**Nachstellen, ohne etwas umzubauen:** Eine SD-Karte einstecken, mounten,
und die Erkennung darauf loslassen:

```bash
lsblk                                  # den Gerätenamen suchen, z. B. mmcblk0
sudo mount /dev/mmcblk0p1 /mnt
bash -c '. ~/mcs/hardware.sh; hardware_bericht /mnt'
sudo umount /mnt
```

**Erwartet:** `SD-Karte (mmcblk0)` und darunter der Warnblock („die
häufigste Ursache für einen ruckelnden Server — und für tote Karten").

**Wer keine SD-Karte zur Hand hat:** Der Abnahmetest im Container prüft
dieselbe Einordnung an einem nachgebauten `/sys`-Baum (Abschnitt 11), und
zwar alle acht Fälle. Dann steht hier nur noch die Frage offen, ob echte
Geräte dieselben Namen liefern — und die beantwortet D-P1.

### D-P3 — Automatische Sicherheitsupdates

```bash
cat /etc/apt/apt.conf.d/20auto-upgrades
systemctl list-timers apt-daily-upgrade.timer
sudo cat /var/log/unattended-upgrades/unattended-upgrades.log | tail -20
```

**Erwartet:** Beide `APT::Periodic`-Zeilen auf `"1"`, ein Timer mit einem
nächsten Termin, und nach ein bis zwei Tagen Einträge im Protokoll.

**Wichtig ist die Gegenprobe:** In `20auto-upgrades` darf **kein**
`Automatic-Reboot` stehen. Ein Server, der sich nachts selbst neu startet,
wirft Spieler heraus.

```bash
grep -ri "Automatic-Reboot" /etc/apt/apt.conf.d/ | grep -v '^\s*//'
```

Kommt hier etwas anderes als eine auskommentierte Zeile aus der
Debian-Vorgabe, ist es ein Befund.

**Und die Kehrseite:** Nach einem Kernel-Update muss die Startseite der
Oberfläche einen offenen Neustart melden. Nachstellen lässt sich das ohne
echtes Update:

```bash
sudo touch /var/run/reboot-required
printf 'linux-image-arm64\n' | sudo tee /var/run/reboot-required.pkgs
mcs status | tail -5
# in der Oberfläche: Startseite neu laden -> "Ein Punkt von 6 ..."
sudo rm -f /var/run/reboot-required /var/run/reboot-required.pkgs
```

### D-P4 — Kommt die Testnachricht an?

1. Auf dem Handy die App **ntfy** installieren.
2. In der Oberfläche unter **Backups → Benachrichtigung** den
   vorgeschlagenen Themennamen übernehmen.
3. Denselben Namen in der App abonnieren.
4. „Testnachricht senden" klicken — oder im Terminal `mcs melden`.

**Erwartet:** Die Nachricht kommt binnen Sekunden an, mit Titel
„PiCraft Testnachricht".

**Wenn nicht:** Fast immer ist ein anderes Thema abonniert als eingetragen.
Zweiter Verdacht: ausgehendes HTTPS ist gesperrt.

**Wer kein Handy zur Hand hat** (oder erst wissen will, *was* überhaupt
hinausgeht), stellt sich einen Briefkasten daneben. Das trennt die beiden
Fragen sauber: „wird richtig gesendet?" und „kommt es an?".

```bash
# Fängt eine Nachricht ab und antwortet mit 200 — curl braucht das wegen -f.
printf 'HTTP/1.1 200 OK\r\nContent-Length: 3\r\nConnection: close\r\n\r\nok\n' \
  | nc -l 127.0.0.1 8099 &
sed -i 's#^MCS_NTFY_SERVER=.*#MCS_NTFY_SERVER=http://127.0.0.1:8099#' ~/mcs/mcs.conf
mcs melden
# danach unbedingt zuruecksetzen:
sed -i 's#^MCS_NTFY_SERVER=.*#MCS_NTFY_SERVER=https://ntfy.sh#' ~/mcs/mcs.conf
```

**Erwartet** (am 30.08.2026 so gemessen): ein `POST` mit
`Content-Type: application/json` und einem Körper wie

```json
{"topic":"...","title":"PiCraft Testnachricht","message":"Wenn du das liest,
 funktioniert die Benachrichtigung. Von <rechnername>, <datum>.",
 "priority":3,"tags":["package"]}
```

Steht das da, ist alles bis zum Netzwerkrand in Ordnung, und ein Ausbleiben
auf dem Handy liegt am Thema oder an der App.

> Den benutzten Themennamen **nicht** in diese Datei schreiben. Bei ntfy.sh
> ist er das ganze Geheimnis — wer ihn liest, liest alle Nachrichten mit.

### D-P5 — Fehlschlag und Entwarnung, in dieser Reihenfolge

Der Punkt, der die Kette wirklich beweist. Ein Fehlschlag muss sich
**herbeiführen** lassen, ohne die Welt anzufassen.

> **Neu gefasst am 30.08.2026 (Befund D-B2).** Hier stand, man solle das
> Backupverzeichnis mit `chmod 500` schreibgeschützt machen und danach den
> Merkzettel `.letzter-fehler` erwarten. Das kann nicht aufgehen: Der
> Merkzettel liegt **in genau diesem Verzeichnis**. Gemessen:
>
> ```
> minecraft-backup.sh: line 160: .../.letzter-fehler: Permission denied
> ```
>
> Das Skript ist dabei in Ordnung — `fehler_merken()` schreibt mit `|| true`
> und benachrichtigt trotzdem. Nur die Erwartung war falsch, und wer ihr
> folgte, hätte den Merkzettel für kaputt gehalten.

Der Fehlschlag lässt sich weiter mit `chmod 500` erzwingen — nur eben nicht
am Merkzettel ablesen:

```bash
# 1) Fehlschlag erzwingen (das Backupverzeichnis kurz schreibgeschützt)
chmod 500 ~/mcs/mcs_backup
~/mcs/mcs_backup/minecraft-backup.sh ; echo "Exitcode: $?"
chmod 700 ~/mcs/mcs_backup
```

**Erwartet:** Exitcode **1**, im Protokoll eine Zeile „FEHLER: tar ist mit
Status 2 abgebrochen — kein brauchbares Backup", eine Nachricht „Backup
fehlgeschlagen" auf dem Handy — und **kein** halbfertiges Archiv, das die
Rotation für ein gültiges Backup halten könnte (die `.unfertig-`-Datei wird
aufgeräumt; am 30.08. nachgesehen, es blieb nichts liegen).

**Den Merkzettel dagegen so prüfen** — bei beschreibbarem Verzeichnis, indem
der Zustand nach einem Fehlschlag von Hand hergestellt wird:

```bash
printf '%s | Testfall\n' "$(date '+%F %T')" > ~/mcs/mcs_backup/.letzter-fehler
mcs status | tail -6        # muss "!!! Letzter Backup-Fehlschlag" zeigen
```

```bash
# 2) Entwarnung
mcs backup
sleep 60; cat ~/mcs/mcs_backup/.letzter-fehler 2>/dev/null || echo "Merkzettel weg - richtig"
```

**Erwartet:** eine zweite Nachricht „Backup wieder in Ordnung", und der
Merkzettel ist verschwunden.

**Die dritte Probe, und die wichtigste:** Ein Backup darf nie an der
Benachrichtigung scheitern.

```bash
sed -i 's#^MCS_NTFY_SERVER=.*#MCS_NTFY_SERVER=http://127.0.0.1:1#' ~/mcs/mcs.conf
mcs backup ; echo "Exitcode: $?"       # muss 0 sein, und ein Archiv muss entstehen
sed -i 's#^MCS_NTFY_SERVER=.*#MCS_NTFY_SERVER=https://ntfy.sh#' ~/mcs/mcs.conf
```

(Diese dritte Probe läuft auch im Container — hier zählt sie mit echtem
systemd und echtem Netz.)

### D-P6 — Stimmt das Urteil am echten Anschluss?

```bash
mcs erreichbarkeit
```

**Erwartet:** ein Urteil, das mit der Wirklichkeit übereinstimmt. Das ist
der springende Punkt: Der Test darf lieber „nicht feststellbar" sagen als
etwas Falsches behaupten.

**Gegenproben, je nach Ergebnis:**

| Urteil | Wie du es überprüfst |
|---|---|
| „erreichbar" | Handy ins Mobilnetz (WLAN aus), im Minecraft-Client verbinden |
| „nur IPv6" | Ein Mitspieler mit IPv6 kommt rein, einer ohne nicht |
| „DS-Lite" | Im Router unter der Internetverbindung nachsehen: keine eigene IPv4, dafür „DS-Lite" oder „AFTR" |
| „keine Freigabe" | Portfreigabe im Router anlegen und erneut prüfen |

**Wenn hier etwas nicht stimmt, ist es ein Befund** — der Test ist nur so
viel wert wie sein Urteil.

Zweite Probe, ohne Netzzugriff:

```bash
mcs erreichbarkeit --lokal
```

Das darf **keine** öffentliche Adresse anzeigen. Mitschneiden lässt sich das
zur Not mit `sudo tcpdump -n 'port 443' -c 5` in einer zweiten Sitzung.

### D-P7 — Wird der Name nach einem Adresswechsel nachgeführt?

Braucht ein Konto bei deSEC (oder DuckDNS) und einen Token.

**Vorab, und unabhängig vom Konto:** `mcs-dns.service` ist enger
abgesichert als die übrigen Dienste (`ProtectSystem=strict`,
`ProtectHome=read-only`, `ReadWritePaths`). Das lässt sich im Container
nicht ausprobieren — dort läuft systemd nicht als PID 1, und
`systemd-analyze verify` prüft nur die Syntax. Also zuerst:

```bash
sudo systemctl start mcs-dns.service
systemctl status mcs-dns.service --no-pager
```

**Erwartet:** `Active: inactive (dead)` mit `status=0/SUCCESS`. Steht dort
etwas über **„mount namespacing"** oder `226/NAMESPACE`, zeigt
`ReadWritePaths` ins Leere — dann stimmt `MCS_DIR` in der Dienstdatei nicht
mit dem tatsächlichen Installationsort überein. Das ist ein Befund.

```bash
grep -E 'ReadWritePaths|EnvironmentFile|ExecStart' /etc/systemd/system/mcs-dns.service
```

Alle drei müssen auf den echten Installationsort zeigen, nicht auf
`/home/pi/mcs`.

1. In der Oberfläche unter **Konfiguration → Dauerhafter Name** eintragen.
2. „Jetzt melden" klicken.
3. Nachsehen, ob der Eintrag stimmt:

```bash
mcs dns
dig +short mc.deinname.dedyn.io A
dig +short mc.deinname.dedyn.io AAAA
```

4. **Der eigentliche Test:** Den Router neu verbinden lassen (bei vielen
   Anschlüssen gibt es dann eine neue Adresse). Danach höchstens fünf
   Minuten warten und noch einmal nachsehen.

**Erwartet:** Der A-Eintrag zeigt auf die neue Adresse, und in
`~/mcs/dns.log` steht genau **eine** neue Zeile — nicht eine je fünf
Minuten. Wird bei unveränderter Adresse gemeldet, ist es ein Befund.

**Und die Gegenprobe zum AAAA-Eintrag:** Hat der Anschluss kein IPv6 (oder
wird es abgeschaltet), muss der AAAA-Eintrag **verschwinden**, nicht
veraltet stehen bleiben.

> **Stand 30.08.2026 auf diesem Pi.** Die Härtung ist geprüft (siehe oben),
> und der Timer-Pfad schweigt bei unveränderter Adresse — zweimal
> hintereinander aufgerufen, keine zweite Zeile in `dns.log`.
>
> Wichtig beim Nachstellen: `mcs dns --jetzt` ist intern auf `--erzwingen`
> abgebildet und meldet **absichtlich** auch ohne Änderung. Wer damit prüft,
> misst das Falsche und hält die Merkdatei für wirkungslos. Der Timer ruft
> `dns-update.sh` **ohne Argument** auf; nur dieser Weg fragt
> `.dns-zuletzt`. Offen bleibt allein der Adresswechsel selbst — dafür muss
> der Router neu verbinden.
>
> **Und eine Lehre, die fast danebengegangen wäre.** Der zuvor benutzte
> eigene Updater meldete nur IPv4; ein AAAA-Eintrag existierte nie. Beim
> Umstieg setzte `dns-update.sh` ihn — scheinbar ein Gewinn, denn IPv6 kennt
> kein NAT und käme ohne Portfreigabe aus.
>
> Es war das Gegenteil. Dass nur IPv4 gemeldet wurde, war eine **bewusste
> Entscheidung**, gemessen und an anderer Stelle begründet: Die
> IPv6-Firewall dieses Routers lässt nichts durch, und ein AAAA behauptet
> dann eine Erreichbarkeit, die es nicht gibt. Clients bevorzugen IPv6,
> laufen in einen Timeout und fallen erst danach auf IPv4 zurück — der
> Server wirkt für jeden mit IPv6 langsam oder tot, obwohl über IPv4 alles
> läuft. Der Eintrag ist rückgängig gemacht.
>
> Daraus wurde ein Schalter: **`MCS_DNS_NUR_IPV4=ja`** lässt den AAAA weg
> und löscht einen vorhandenen mit. Das ist kein Sonderfall dieser
> Installation — die meisten Heimrouter blocken eingehendes IPv6 ab Werk.
> Wer es freigegeben hat, lässt den Schalter leer; was gilt, sagt
> `mcs erreichbarkeit`.
>
> Die allgemeine Lehre: Eine Vorlage, die „mehr" tut als die Installation,
> tut nicht automatisch etwas Besseres. Vor dem Umstellen gehört gelesen,
> **warum** die Installation weniger tat.

### D-P8 — Der SRV-Eintrag: ohne Portangabe verbinden

Nur mit deSEC. Voraussetzung: D-P7 steht, und in den Einstellungen ist eine
**Zone** eingetragen.

1. In der Oberfläche „SRV-Eintrag anlegen" klicken (oder `mcs dns --srv`).
2. Warten — bis eine Stunde (TTL 3600).

```bash
dig +short _minecraft._tcp.mc.deinname.dedyn.io SRV
```

**Erwartet:** `0 5 <port> mc.deinname.dedyn.io.` — mit Punkt am Ende.

3. **Der Beweis:** Ein Mitspieler trägt im Client nur
   `mc.deinname.dedyn.io` ein, **ohne** `:25565`, und kommt rein.

Das ist der ganze Grund, warum deSEC die Empfehlung ist. Klappt es nicht,
ist es ein Befund.

### D-P9 — Schaltet `mcs aus` auch den DNS-Timer ab?

```bash
systemctl list-timers mcs-dns.timer
mcs aus
systemctl is-enabled mcs-dns.timer ; systemctl is-active mcs-dns.timer
sudo reboot
```

Nach dem Neustart:

```bash
systemctl is-active mcs-dns.timer     # muss "inactive" sein
mcs an
systemctl is-active mcs-dns.timer     # muss wieder "active" sein
```

**Erwartet:** Der Timer läuft nach `mcs aus` nicht mehr und kommt auch nach
einem Neustart nicht von selbst wieder hoch. Das ist derselbe Mechanismus
wie beim Backup-Timer (A-P1) — geprüft wird hier nur, dass die neue Einheit
richtig verdrahtet ist. `PartOf` und `WantedBy` prüft der Container schon;
was er nicht prüfen kann, ist das Verhalten über einen echten Neustart.

### D-P10 — Vom Handy über Tailscale auf die Oberfläche

Der Weg, den Entscheidung 12 vorsieht, und bis zum 30.08.2026 nirgends
beschrieben. Die Anleitung steht jetzt im README unter „Zugriff über
Tailscale"; hier steht, was daran zu prüfen ist.

**Voraussetzung:** Tailscale läuft auf dem Pi und auf dem Handy, beide im
selben Tailnet.

```bash
tailscale status | head -5
tailscale ip -4
```

**Erst der Gegenbeweis, und der ist der wichtigste Teil:** Am Router darf
für die Weboberfläche **nichts** freigegeben sein. Wenn der Zugriff
funktioniert und trotzdem kein Port offen ist, ist genau das bewiesen, was
Lastenheft 5.3 verlangt.

#### Weg A — direkte Tailscale-Adresse

Nach der Anleitung einrichten, dann vom Handy `http://100.x.y.z:<port>`
aufrufen.

**Erwartet:** Die Anmeldung erscheint, das Passwort wird angenommen, die
Startseite lädt.

**Wenn nichts kommt**, in dieser Reihenfolge nachsehen:

```bash
ss -ltn | grep <port>            # lauscht sie auf der 100.x.y.z?
sudo ufw status | grep tailscale # ist tailscale0 erlaubt?
```

Die Firewall ist hier der wahrscheinlichste Grund: `default deny incoming`
verwirft auch Verkehr über `tailscale0`, solange keine Regel ihn zulässt.

#### Weg B — Tailscale Serve

```bash
sudo tailscale serve --bg <port>
tailscale serve status
```

Vom Handy `https://<pi-name>.<tailnet>.ts.net` aufrufen.

**Erwartet:** grünes Schloss, keine Zertifikatswarnung.

**Drei Dinge, die hier zu prüfen sind und die der Container nicht zeigen
kann:**

1. **Ein schreibender Klick muss durchgehen** — etwa „Testnachricht senden"
   auf der Backupseite oder das Speichern einer Einstellung. Kommt
   stattdessen *„Diese Anfrage kam nicht von dieser Oberfläche"*, reicht
   Tailscale Serve den `Host`-Kopf nicht durch, und die Herkunftsprüfung in
   `nur_eigene_oberflaeche` schlägt an. Das wäre ein Befund — dann gehört
   die Prüfung um den weitergereichten Namen erweitert.
2. **`MCS_ADMIN_HTTPS=1` gesetzt?** Danach neu anmelden und prüfen, dass die
   Sitzung hält. Ohne das Merkmal `Secure` funktioniert es zwar auch, aber
   das Cookie ginge über eine unverschlüsselte Verbindung mit, falls je eine
   zustande käme.
3. **Die Kartenseite** — das ist zugleich der offene Teil von **C-P8**: Über
   HTTPS muss dort der Hinweis samt „In neuem Tab öffnen" stehen, kein
   weißer Kasten.

**Und die Ratenbegrenzung:** Bei Weg B kommen alle Anfragen von
`127.0.0.1`. Fünf falsche Passwörter sperren dann *jedes* Gerät für fünf
Minuten, nicht nur das schuldige. Einmal ausprobieren, damit man es weiß,
bevor es einen im Ernstfall überrascht — die Sperre läuft von selbst ab.

> **Niemals `tailscale funnel`** statt `serve`: Das veröffentlicht die
> Oberfläche ins offene Internet. Falls doch einmal getippt, sofort
> `sudo tailscale funnel reset` und mit `mcs erreichbarkeit` gegenprüfen.

### D-P11 — Installation an einen anderen Ort

Seit dem 30.08.2026 fragt der Assistent als Erstes nach dem
Installationsort (Lastenheft 5.1, Entscheidung 6). Im Container ist das
nicht prüfbar: Dort läuft `--standard`, und der überspringt die Frage.

**Warum es das überhaupt gibt:** Wer die Warnung vor der SD-Karte gelesen
hat (D-P2), will genau jetzt auf seine SSD ausweichen. Die Frage steht
deshalb *vor* der Vorprüfung — die misst den freien Platz auf dem Ziel.

Auf einem Pi, auf dem noch nichts installiert ist (oder in einer
wegwerfbaren Kopie):

```bash
./install.sh
# bei "Installationsort" etwas anderes eingeben, z. B. /mnt/ssd/mcs
```

**Erwartet:**

1. Die Zusammenfassung nennt unter „Zielverzeichnis" den **gewählten** Ort.
2. Die Vorprüfung meldet den freien Platz und das Speichermedium des
   **gewählten** Datenträgers, nicht des Heimatverzeichnisses.
3. Nach der Installation:

```bash
grep -E '^MCS_(DIR|SERVER_DIR|BACKUP_DIR)=' /mnt/ssd/mcs/mcs.conf
grep -E 'WorkingDirectory|ExecStart|EnvironmentFile' /etc/systemd/system/minecraft.service
ls -d /mnt/ssd/mcs/mc_server /mnt/ssd/mcs/mcs_backup
```

Alles muss auf den gewählten Ort zeigen — **nirgends** darf noch
`/home/<benutzer>/mcs` stehen. Tut es das doch, ist es ein Befund: Dann
zieht eine Stelle den Ort nicht mit.

4. **Ein zweiter Lauf darf nicht erneut fragen.** `./install.sh` noch
   einmal starten: Da nun eine `mcs.conf` am gewählten Ort liegt, muss die
   Frage übersprungen werden.

   Diesen Teil kann man auch auf einer bestehenden Installation prüfen,
   ohne etwas zu verschieben — dort darf die Frage schlicht nicht
   auftauchen.

**Die beiden anderen Punkte aus derselben Änderung** lassen sich nebenbei
mitnehmen:

```bash
./install.sh --ohne-oberflaeche --standard
```

Danach darf es **keinen** Dienst `mcs-admin.service` geben und kein
Verzeichnis `<ort>/admin`. Und beim geführten Lauf muss die Frage nach dem
Passwort der Weboberfläche kommen — ein selbst gewähltes darf am Ende
**nicht** noch einmal im Terminal erscheinen.

---

## Offen aus v1.4: Kopien außer Haus (Stand 22.10.2026)

Was ohne Stick und ohne Google-Konto ging, ist am 22.10.2026 geprüft:

- `make kopien` (28 Prüfungen): Datei-Teil der USB-Kopie gegen einen
  Ordner, Cloud-Kopie gegen einen mit rclone crypt verschlüsselten Ordner.
- **Der root-Teil mit Loop-Geräten** als Stick (exFAT und FAT32, Name
  `MCS-BACKUP`): einhängen, als Benutzer kopieren, mit `iflag=direct`
  zurücklesen, aushängen. Zu kleiner Stick → klare Meldung, LED blinkt
  schnell, Stick ausgehängt. Zweiter Lauf → „liegt schon auf dem Stick".
  `--led-normal` stellt die LED auf `mmc0` zurück.
- **Über systemd, mit allen Schutzeinstellungen der Einheit:** Schreiben von
  `.neuestes-backup` stieß beide `.path`-Einheiten an; die USB-Kopie legte
  das echte Backup (650 MB) in 6 s auf ein 1-GB-Abbild, die Cloud-Kopie
  endete sofort mit „nicht eingerichtet".

### V4-P1 — Ein echter Stick

Was die Loop-Geräte nicht zeigen: die udev-Regel (Loop-Geräte tragen kein
`ID_BUS=usb`) und ob die LED zu sehen ist.

1. Stick am Mac als ExFAT mit dem Namen `MCS-BACKUP` formatieren.
2. Am Pi einstecken. **Erwartet:** Die grüne LED blinkt im Herzschlag,
   nach ein bis zwei Minuten leuchtet sie dauerhaft.
3. `mcs usb` → „ok", der Name des Backups, freier Platz.
4. Abziehen. **Erwartet:** LED wieder im Normalzustand.
5. Am Mac: Ordner `PiCraft-Backups`, darin das Backup und `LIESMICH.txt`;
   Doppelklick öffnet das Archiv.
6. Einen Stick mit anderem Namen einstecken. **Erwartet:** nichts, auch
   nicht in `journalctl -u mcs-usb-kopie`.

Ergebnis: _offen_

### V4-P2 — Google Drive einrichten und der erste Abgleich

1. `mcs cloud einrichten` in einer SSH-Sitzung (Anmeldung über einen der
   beiden Wege aus dem README).
2. **Erwartet:** `~/mcs/cloud-schluessel.txt` mit `-rw-------`, in Google
   Drive der Ordner `PiCraft-Sicherung` mit `LIESMICH.txt` und
   `verschluesselt/`.
3. Nach dem ersten Abgleich: `mcs cloud` → „ok", Zahl der täglichen und
   der Archiv-Stände wie auf dem Pi; Probe „ok".
4. In Google Drive eine Datei `….tar.gz.bin` herunterladen und mit `gzip -t`
   prüfen. **Erwartet:** Fehler — sie ist verschlüsselt.

Ergebnis: _offen_

### V4-P3 — Die erste Nacht

Am Morgen nach dem Einrichten: `journalctl -u mcs-cloud-kopie --since
yesterday` zeigt einen Lauf kurz nach dem Backup, `mcs status` eine Zeile
„Cloud-Kopie: ok". Steckte ein Stick, dasselbe für `mcs-usb-kopie`.

Ergebnis: _offen_

### V4-P4 — Zurückholen ohne den Pi

Der eigentliche Zweck. An einem anderen Rechner nur mit dem Inhalt von
`cloud-schluessel.txt` und den aus Google Drive geladenen Dateien
entschlüsseln (Anleitung in derselben Datei). **Erwartet:** ein
`backup_*.tar.gz`, das sich öffnen lässt.

Ergebnis: _offen_

---

## Wenn etwas nicht stimmt

Nichts von Hand am System reparieren, sondern hier notieren und im Repository
beheben — sonst weicht der Pi wieder von dem ab, was im Repository steht.
Genau daraus sind die Befunde B1 bis B7 entstanden.

Rückweg, falls der Hauptschalter Ärger macht:

```bash
sudo systemctl enable minecraft.service mcs-playerlog.service
sudo systemctl start minecraft.service
```

Damit läuft der Server wieder, unabhängig von `mcs.target`.
