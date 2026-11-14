# PiCraft — Arbeitsregeln

All-in-one-Lösung für einen PaperMC-Server auf dem Raspberry Pi
(`./install.sh`); Kern ist **PaperMC**.

Diese Datei nennt nur den heutigen Stand jeder Regel mit einem Satz
Begründung; die Messungen und Anlässe dahinter stehen in
`docs/regeln-chronik.md`, dort nachlesen, bevor man eine Regel für
überflüssig hält. Ändert sich eine Regel, wird sie hier umgeschrieben, nicht
ergänzt. Das Lastenheft (`docs/lastenheft-minecraft-server.md`) gibt das
**WAS und WOZU**, die Pflichtenhefte (`docs/pflichtenheft-etappe-*.md`) das
**WIE**; bei Widerspruch gilt das Lastenheft.

## Leitsätze — und ihre Reihenfolge zählt

Im Zweifel wird nach diesen Sätzen entschieden, in dieser Reihenfolge:

1. **Die Leistung des Minecraft-Servers hat Vorrang.** Nichts drumherum darf
   ihm spürbar Rechenzeit oder Speicher wegnehmen: Metrik-Sammler mit
   `Nice`, RCON höchstens eine Abfrage je Klick.
2. **Leichtgewichtig.** Keine Bauteile, die es nicht braucht.
3. **Einfach, aber ausgeklügelt.** Lieber einmal mehr nachgedacht, wie es
   rund wird, als es zu verkomplizieren.
4. **Lesbar für Pi-Anfänger.** Ein Feature, kein Zufall, und der Grund, warum
   hier Bash und Flask stehen und kein Go-Binary, das 25 MB RAM spart.
5. **Ehrlich statt bequem.** Lieber melden, dass etwas nicht funktioniert;
   ein still durchwinkender Test ist schlimmer als keiner.
6. **Mit Liebe gemacht.** Minimalistisch, aber nicht lieblos.

**Kommentare erklären das WARUM, nicht das WAS** und nennen bei Messungen
Datum und Befund.

## Nicht-Ziele

Keine kommerzielle Hosting-Lösung, keine andere Plattform als der Raspberry
Pi, keine Minecraft-Inhalte, kein Fork von Paper, keine großen Spielerzahlen
(5, max. 10). **Kein Docker. Kein npm, kein Node, kein CDN:** Flask + Jinja
+ HTMX ohne Build-Schritt, alles lokal ausgeliefert.

## Sprache

**Deutsch, überall:** Code, Kommentare, Oberfläche, Dokumentation,
Commit-Nachrichten, Bezeichner. In Commit-Nachrichten und Skript-Kommentaren
Umlaute als `ae/oe/ue`, in Markdown-Fließtext nicht.

## Regeln, bei denen das Naheliegende falsch ist

- **Paper schreibt `server.properties` beim START neu**, bei laufendem
  Server die *ganze* Datei, sobald ein Befehl dort Gespeichertes tatsächlich
  ändert: dann vormerken, nicht schreiben. YAML-Dateien dürfen geschrieben
  werden. Eigene Kommentare gehen verloren.
- **`ops.json` verhält sich beim Start GENAU UMGEKEHRT**:

  | | `server.properties` | `ops.json` |
  |---|---|---|
  | beim Stoppen | überlebt | überlebt |
  | beim **Start** | **verworfen** | **gelesen, überlebt** |
  | laufend, nach ändernden Befehl | verworfen | verworfen |

  RCON kann keine Operator-Stufe setzen (`op <name> <stufe>` gibt es nicht,
  `op <name>` vergibt immer `op-permission-level`): `ops.json` nur bei
  gestopptem Server schreiben. Bei laufendem nichts Schreibendes, es
  verschwindet beim nächsten `op` oder `deop` lautlos.
  `spieler.stufe_setzen()` prüft `service_state(frisch=True)`; die
  Stufenwahl der Oberfläche nur bei stehendem Server anbieten, nicht
  „vereinheitlichen“.
- **Ein Schlüssel, den Paper nicht mehr kennt, sieht aus wie eine
  Abweichung:** `spawn-monsters`, `spawn-animals`, `spawn-npcs` (Paper 26.2)
  gehören nicht in Vorlage, `install.sh` oder Oberfläche (Monster aus:
  `peaceful`). Beleg ist nur eine von Paper selbst geschriebene
  `server.properties` (nicht die `paper.jar`).
- **`difficulty` und `white-list` stehen in der Welt, nicht in der Datei:**
  den laufenden Server fragen.
- **RCON lässt sich nicht auf `127.0.0.1` beschränken** (kein `rcon.ip`,
  `server-ip` bleibt leer): Die Firewall ist die einzige Abschottung, mit
  `DENY`-Regel für den RCON-Port. `whitelist add` und `op` je auf eigener
  RCON-Verbindung.
- **`tar … | grep -q` ist unter `set -o pipefail` eine Falle** (Erzeuger
  endet mit 141, gilt für jeden Erzeuger, tritt oft erst ab einer gewissen
  Größe auf, im Container also gar nicht): in eine Variable lesen und
  Here-String, oder `find … -print -quit`. Achtung: `<<<""` ist eine
  Leerzeile, und die trifft `grep -v`.
- **`screen -X stuff` wertet `\`, `^` und `$` aus** (`^M` trennt Befehle,
  `$VAR` setzt Geheimnisse des Dienstes ein); `server/lib-konsole.sh` und
  `admin/konsole.py` escapen alle drei.
- **„Leer“ ist bei DNS nicht „weg“:** Leer an deSEC LÖSCHT den Eintrag,
  `preserve` lässt ihn. `dns-update.sh` sendet leer nur, wenn es die Adresse
  nicht gibt, sonst `preserve`. Gemerkt wird der **gemeldete** Zustand,
  sonst sieht ein echter Wegfall nach einem Aussetzer aus wie „unverändert“.
- **Ein Absturz hinterlässt `(Dead ???)` in `screen -ls`:** Die Prüfung
  schließt `(Dead` aus, `screen -wipe` räumt auf.
- **Paper schreibt für EINE Trennung ZWEI Zeilen** („hat das Spiel
  verlassen“, „hat die Verbindung verloren (Grund: …)“), in wechselnder
  Reihenfolge, auch über eine Sekundengrenze; nur die zweite hat den Grund.
  Daher ein Zwei-Sekunden-Fenster, kein Gleichheitstest. Bei einem zweiten
  Gerät kommt zuerst der neue Beitritt, dann fliegt die alte Verbindung:
  deren Abmeldezeilen nicht der neuen Sitzung zuschlagen (sonst eine
  Null-Sekunden-Sitzung und ein falscher „Absturz“). Exaktes Merkmal: Die
  offene Sitzung begann genau, als die vorige geschlossen wurde. Der Grund
  ist keine Formsache (Leerlauf, Timeout, anderes Gerät, Serverende).
- **Serverlogzeilen haben kein Datum** (`[HH:MM:SS]`): Archiv = erster Tag
  im Dateinamen (vorwärts), `latest.log` = Änderungszeit zur letzten Zeile
  (rückwärts), nur in `admin/logdatum.py`. `latest.log` wird nie ab einer
  Lesemarke, sondern ganz gelesen.
- **Seit Paper 26.3 steht vor Beitritt und Verlassen `System chat: `**, vor
  `lost connection`, `logged in`, `UUID of player` nicht.
  `MUSTER_BEITRITT`/`MUSTER_VERLASSEN` haben den Vorsatz als optionale
  Gruppe; der Name steht dort in Gruppe 3, sonst in Gruppe 2 (`make
  muster`). Merksatz: **Nach einem Wechsel der Minecraft-Version das
  Logformat an echten Zeilen prüfen.**
  `protokollpruefung.beitritte_unerkannt()` zählt `joined the game` und
  `logged in with entity id` lose und warnt, wenn `MUSTER_BEITRITT` trotz
  Zeugen nichts trifft: den Zeugen nie auf die gemeinsamen Muster umstellen,
  sonst fällt er mit dem Muster aus, das er bewacht. Die Reihenfolge von
  `logged in` und `joined` ist nicht fest.
- **Ein Pl3xMap-Update kann `plugins/Pl3xMap/config.yml` auf die Vorgaben
  zurücksetzen** (`seite_karte.kartenserver_antwortet()` meldet es): vorher
  sichern.
- **`player_activity.log` ist ein Hauptbuch: in keine logrotate-Regel.**
  `admin/spieler.py` liest es als Ganzes für „zuletzt gesehen“, eine
  Rotation schneidet das lautlos ab. `install.sh` führt die Zeile nicht,
  `deploy.sh` (Abschnitt 3d) nimmt sie heraus, `admin/protokollpruefung.py`
  warnt bei Rückstand. `install.sh` und `deploy.sh` schreiben denselben
  Hinweis in die Regel **wortgleich**, sonst findet `deploy.sh` seine Marke
  nicht und ergänzt bei jedem Lauf eine weitere. Merksatz: **Vor einer
  Rotationsregel fragen, ob jemand die Vergangenheit der Datei liest. Eine
  Reparatur ist erst fertig, wenn geprüft ist, was sie regelmäßig wieder
  kaputtmacht.**
- **Der Weltname steht in `level-name`**, nie `world` fest verdrahten, auch
  nicht in Tests; Spielerdateien: `<welt>/players/stats/` *oder*
  `<welt>/stats/`.
- **`enable`-Verweise folgen dem `[Install]` beim `systemctl enable`**
  (`daemon-reload` fasst sie nicht an, `reenable` nur schon Aktiviertes):
  Die Wahrheit steht in `systemctl
  show <einheit> -p WantedBy`. Neue Einheiten müssen auch auf bestehenden
  Installationen ankommen.
- **Einen Wert in `mcs.conf` lesen DREI Leser** (Shell, systemd
  `EnvironmentFile=`, Python). Leerzeichen zerlegen die Shell. `'wert'`
  nehmen Shell und systemd wörtlich; `"wert"` nur systemd, die Shell führt
  `$(…)` aus. Geschrieben wird über `konfig.wert_fuer_mcs_conf()` bzw.
  `mcs_conf_wert()` (`install.sh`); Python nimmt die Anführungszeichen ab.
- **`hmac.compare_digest` verweigert `str` mit Nicht-ASCII** (`TypeError`
  bei Umlauten): `.encode()` vergleichen.
- **`${X:-standard}` greift nicht bei einer ausdrücklichen `0`** (aus
  `MCS_BACKUP_BEHALTEN=0` wurde `tail -n +1`, ein Lauf leerte beide
  Backup-Platten): `0` heißt „aus“, Nichtzahlen fallen laut gemeldet auf den
  Standard (`zahl_aus_conf`). **Gelöscht wird nie auf Grundlage eines
  Wertes, dem das Skript nicht trauen kann.**
- **Ein Zwischenspeicher, den zwei Takte teilen, misst für keinen:** Die
  `/proc/stat`-Probe gehört je Aufrufer (`cpu_auslastung(aufrufer)`), mit
  Untergrenze einer Sekunde. Merksatz: **Wer einen Zustand zwischen Aufrufen
  aufhebt, muss aufschreiben, WESSEN Zustand es ist.**
- **Der Aufrüstweg kann weniger als die Frischinstallation:** Alles Neue
  (Einheit, `mcs.conf`-Schlüssel) braucht in `deploy.sh` eine eigene
  Abfrage, keine Sammelbedingung.
  - **DATEIEN stehen in `lib/dateien.sh`**; `install.sh` kopiert,
    `deploy.sh` vergleicht dieselbe Liste. Ergänzungen nur dort.
  - **Spalte drei zählt:** `nur-wenn-fehlt` (z. B. `plugins.txt`)
    überspringt `deploy.sh`, `neustart` wirkt erst nach Server-Neustart.
    `install.sh` ruft `deploy.sh` nicht auf.
  - **`neustart` gilt nur für `minecraft.service`;** für `mcs-admin` und
    `mcs-playerlog` (`log-muster.sh`) nennt `deploy.sh` eigene Hinweise.
- **`mcs update` ohne Zusatz holt den NEUESTEN Build;** `--festgelegt` den
  aus `versions.env` (so ruft es `install.sh`; neue Aufrufer von
  `paper-update.sh` wählen bewusst). Die Minecraft-Version nur mit
  `--minecraft`. Drei Dinge:
  - **Es schreibt `versions.env` in Installation UND Repository und
    committet nur diese Datei** (sonst dreht `./deploy.sh` den Build
    zurück), nicht bei offenen Änderungen daran (die gehören jemandem); nie
    Push. Ohne Git-Identität committet es als `PiCraft <picraft@localhost>`.
  - **„Verfügbar“ heißt STABIL** (nicht BETA), geprüft vor dem Backup.
  - **Die Oberfläche fragt PaperMC nicht selbst:** `paper-update.sh
    --pruefen`, dann Notiz `mc_server/paper.verfuegbar` (`admin/paper.py`);
    eine eigene Abfrage wäre der zweite Weg ohne die Stabil-Regel. Beim
    Seitenaufbau geht nichts nach außen (Lastenheft 5.7.2). Ob ein Build läuft, zeigt
    `paper.jar` gegen `ActiveEnterTimestamp`, nicht `paper.installiert`.
- **Die Kopien außer Haus (v1.4) löschen, daher mehr Vorsicht:**
  - **Die Cloud räumt nach ZAHL auf, nie nach Alter, nie per „sync“:**
    `sync` spiegelt ein Unglück (leerer Ordner → leere Cloud), „älter als
    30 Tage“ leert die Cloud, wenn die Backups ausbleiben, also genau dann,
    wenn man sie braucht. Nie auf weniger als der Pi hat (sonst lädt jeder
    Lauf nach).
  - **Auf dem Stick nur, was im eigenen Ordner liegt und `backup_*.tar.gz`
    heißt**, am Stick mit richtigem Namen. `tests/pruefung-kopien.sh` prüft
    vor allem, was NICHT verschwinden darf.
  - **Nur verschlüsselt außer Haus:** `cloud-kopie.sh` verweigert jedes
    rclone-Ziel ohne Typ `crypt` (RCON-Passwort im Archiv).
- **Die USB-Kopie ist die eine Ausnahme von „Dienste laufen nie als root“:**
  Nur Einhängen und LED als root, Dateizugriffe per `setpriv` als
  Server-Benutzer (liest root im Backup-Ordner, bringt ein Symlink auf
  `/etc/shadow` die Datei auf den Stick). `usb-kopie.sh` liegt unter `/usr/local/lib/picraft/`, in
  `lib/dateien.sh` in der eigenen Liste `mcs_systemdateien`; wer dort
  ergänzt, fragt, ob es als root laufen muss. Die `mcs.conf` bekommt ein
  root-Dienst nie als `EnvironmentFile=`, auch wenn alle anderen Einheiten es
  so machen: Sie gehört dem Benutzer (`BASH_ENV`, `LD_PRELOAD`,
  `MCS_USER=root`, ein LED-Name mit `../`). `usb-kopie.sh` liest drei Schlüssel selbst
  (`conf_lesen`), vertraut nur `MCS_USER`/`MCS_CONF` seiner Einheit, weist
  UID 0 ab, nutzt `env -i`.
- **Kopien löst `mcs_backup/.neuestes-backup` aus, nicht `OnSuccess=`**
  (Backups gibt es auch per `mcs backup`): Das Skript schreibt sie zuletzt;
  Ergänzungen davor.
- **`sed … datei | head` auf eine fehlende Datei reißt unter `set -e` und
  `pipefail` ab** (sed endet mit 2): solche Dateien mit `awk` lesen, nach
  Existenzprüfung.
- **Das Kartentor (v1.6) glaubt `X-Real-IP`, die Weboberfläche mit Absicht
  nicht:** Das Tor lauscht fest auf `127.0.0.1` (nur nginx fragt), bei der
  Oberfläche schriebe sich jeder die Bremse weg; nie eine einstellbare
  Bindeadresse. Es liegt in `kartentor/`, nicht in `admin/`: Seine Sandbox
  (`ProtectHome=tmpfs`) gibt nur diesen Ordner und den Serverordner zurück,
  damit es die `.env` der Oberfläche nicht sieht. `deploy.sh` (Block 3c)
  schaltet es als einzige neue Einheit nicht ein: Ohne öffentliche Karte
  bewacht es nichts.
- **Ein Vergleich direkt nach dem Schreiben liest den Arbeitsspeicher:** Die
  USB-Kopie liest mit `dd iflag=direct` zurück und vergleicht mit `cmp`.

## Trennung von Vorlage und Installation

Was der Installation gehört, wird nie überschrieben: `mcs.conf` (im Repo nur
`mcs.conf.beispiel`), `plugins.txt` (nur `.beispiel`) und in
`server.properties` `level-name`, `motd`, `server-port`,
`enable-command-block` (sonst stellte ein Ausrollen die Welt auf `world` um
oder schaltete Befehlsblöcke ab). Die ersten drei sagen, wo eine
Installation steht, der vierte, wie gespielt wird. Markiert sind sie in der
Vorlage mit `# PiCraft: instanzspezifisch` über dem Wert; `deploy.sh` liest
die Liste daraus und bricht ab, wenn es keine findet.

**Weicht eine Vorlage dauerhaft von der Installation ab, ist meist die
Vorlage falsch** (außer bei diesen Werten). **Tut die Vorlage mehr als die
Installation, ist das kein Beweis, dass sie es besser tut:** erst lesen,
warum die Installation weniger tat.

## Prüfen, bevor etwas abgegeben wird

```bash
make                   # Syntax, pyflakes, shellcheck, Vorlagen
bash tests/abnahme.sh  # volle Installation im ARM64-Container
```

**`make` prüft kein JavaScript** (es zählt nur `/*` gegen `*/`):
Skriptblöcke im Browser prüfen. Ohne `pyflakes` zählt `make` weniger als die
Action.

**Der Abnahmetest darf nie grün melden, wo er es nicht ist:**

- **Er endet mit dem Rückgabewert der Installationsläufe**, nicht des
  letzten `echo`. Merksatz: **Ein Fehler, den nur der Wiederholungslauf
  zeigt, findet nur ein Test, der auch beim zweiten Lauf rot wird.**
- **Grün kann heißen: nichts geprüft.** Die Python-Blöcke (`su … python3 -
  <<PYTEST`) gelten auch nach einer Ausnahme als bestanden: Ausgabe auf
  `Traceback` lesen; wer eine Signatur ändert, sucht auch ihre Attrappen.
- **Eine Inhaltsprüfung zählt nur, wenn eine Wache sie liest:** `Traceback`,
  `FEHLER` und `tests/muss-zeilen.py` (Zeilen `Wert (muss X sein|bleiben[,
  Nachsatz])`). Ein nacktes `… : True` liest keine Wache, Überschriften
  (`--- … ---`) werden nicht verglichen.

**`Done (` im Log heißt nicht, dass der Server läuft, geschweige bereit
ist:** Vor dem zweiten Start die alte `latest.log` wegräumen
(`tests/abnahme-im-container.sh`, `tests/messung-im-container.sh`), vor
RCON-Messungen auf eine Antwort warten (`rcon_bereit`). **Eine Messung ohne
Prüfung ihrer Voraussetzung ist keine Messung.**

**Der Container kann kein systemd:** Autostart, Neustart, Abstürze,
`enable`/`disable` nur auf echter Hardware (`PRUEFEN-AUF-DEM-PI.md`). Ein
zweiter Installationslauf darf nichts verändern.

## Was nicht ins Repository gehört

Öffentliches Repository für einen **fremden** Pi: keine echten Spielernamen,
UUIDs, IP-Adressen (auch LAN, Tailscale), kein Weltname, keine abweichenden
Portnummern, keine Token, auch nicht in Messbelegen und nicht in der
Historie.

Geheimnisse nie in `mcs.conf`, sondern in Dateien mit `chmod 600`:
`dns.env`, `ntfy.env`, `admin/.env`. Wer einen Editor für eine
Konfigurationsdatei baut, fragt vorher, ob dort ein Geheimnis stehen kann;
maßgeblich ist die Liste je Datei in `admin/konfig.py` (`DATEIEN` →
`"geheim"`) und deckt properties und YAML ab. Sie veraltet mit jeder
Minecraft-Version (seit 1.21.9 `management-server-secret`, vom Server
erzeugt, und `management-server-tls-keystore-password`): nach einem
Versionswechsel neue Schlüssel durchsehen. Ein geleertes
`management-server-secret` lässt Paper leer und startet trotzdem; wann es
eins erzeugt, ist nicht gemessen.

## Worauf es bei einer Prüfung ankommt

Nach Gewicht: ein Fehler oben ist teurer als drei unten:

1. **Datenverlust.** Alles, was Welt oder Backups berührt; die Backup-Platte
   ist im Zweifel die einzige Kopie. Ein Archiv muss fertig und geprüft
   sein, bevor die Rotation löscht; ein Abbruch darf kein gültig aussehendes
   Backup hinterlassen.
2. **Stiller Ausfall.** Die teuerste Fehlerklasse. Verdächtig: `|| true`,
   unterdrückte Ausgaben, `set -e` mit Pipes, herabgestufte Fehler.
3. **Zustand nach einem Abbruch.** Bleibt `save-off` gesetzt, eine halbe
   Datei liegen, ein Dienst in `failed`? Dafür gibt es `trap`.
4. **Sicherheit.** Besonders Rechte auf Dateien mit Geheimnissen, gesetzt
   *vor* dem Schreiben.
5. **Erst dann Lesbarkeit und Vereinfachung** (Leitsatz 4).

**Das Folgende ist bewusst so und kein Befund:**

- Bash, `screen` und Flask statt eines robusteren Stapels (Leitsatz 4).
- Das Passwort der Weboberfläche im Klartext in einer Datei mit `chmod 600`,
  nicht als Hash: Nachschlagbarkeit ging vor; Bedingung ist ein eigenes,
  nirgends sonst benutztes Passwort.
- `tar.gz` statt zstd, restic oder borg: ohne Spezialwerkzeug zu öffnen.
- Deutsche Bezeichner und Meldungen.
- Die Pixelschrift der Kachelwerte (`.kachel__wert`): im Lastenheft gewollt.
  Lesbarer: in `static/mcs.css` auf `--schrift-zahl` umstellen.
- Der offene, nur per Firewall gesperrte RCON-Port.
- Kein Docker, kein npm, kein CDN, kein Build-Schritt.

Wer einen dieser Punkte für einen Fehler hält, hat recht, für ein anderes
Projekt. Hier sind sie abgewogen und im Lastenheft begründet.

## Sicherheit

Die Weboberfläche ist so mächtig wie SSH: nur LAN oder Tailscale, nie ins
Internet. Dienste laufen nie als root, sudo-Regeln bleiben eng. Anmeldung
per Sitzungs-Cookie mit `SameSite=Lax` (kein HTTP Basic Auth) und
Ratenbegrenzung.

**`NoNewPrivileges` allein sperrt nichts ein:** Mit sudo ohne Passwort führt
jeder Prozess außerhalb der Sperre zu root (Code der Weboberfläche,
systemd-Benutzerbus). Daher schreibt `minecraft.service` nur im
Serverordner; Dateien darin, die ein anderer Dienst lädt oder ausführt
(`lib-konsole.sh`, Update-Skripte, `versions.env`), sind `ReadOnlyPaths`,
`/run/user` ist unsichtbar (`ProtectHome=read-only` reicht für den Bus
nicht). Merksatz: **Eine Sandbox ist nur so dicht wie der am wenigsten
eingesperrte Prozess, der Dateien aus ihr ausführt.** Wer im Serverordner
eine Datei ablegt, die `mcs`, Backup oder Oberfläche laden, trägt sie dort
ein.

**Erreichbarkeit von außen ist vom Pi selbst nicht prüfbar** (kein
NAT-Hairpinning, `lo` umgeht die Firewall): „von hier aus erreichbar“ ist
kein Beleg, „nicht feststellbar“ ist erlaubt.

**Ein Sicherheitsheader kann im Browser-Cache veralten**: Pl3xMap schickt
`ETag` und `Last-Modified`, aber kein `Cache-Control`; der Browser liefert
die Antwort samt alter `Content-Security-Policy` aus dem Zwischenspeicher.
Keine Anfrage im Protokoll = Zwischenspeicher, eine Anfrage = Header. Wer ihn ändert, macht die Antwort nicht
cachebar (`Cache-Control: no-store`) und hängt einen Stempel an die
eingebettete Adresse.
