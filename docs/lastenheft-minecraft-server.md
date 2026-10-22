# Lastenheft: PiCraft

**Projekt:** Umbau und Perfektionierung des Minecraft-Servers für den Raspberry Pi
**Auftraggeber:** Florian
**Version:** 0.9 — **alles in diesem Dokument ist umgesetzt**, und Etappe D
ist auf dem Pi ausgerollt und zum größten Teil abgenommen. Offen ist nur
noch, was sich ausschließlich mit fremdem Gerät, echten Mitspielern oder
über einen Neustart nachweisen lässt.
**Datum:** 30.08.2026

**Stand:** Etappe A (Fundament), B (Schnittstelle) und C (Weboberfläche) sind
umgesetzt und am 29.08.2026 auf dem Pi abgenommen. **Etappe D (Politur) ist
am 30.08.2026 umgesetzt, auf dem Pi ausgerollt und dort abgenommen, soweit
es ohne fremdes Gerät geht** — von elf Prüfpunkten sechs ganz und vier
teilweise. Dabei kamen zwei Befunde heraus (`deploy.sh` aktivierte neu
hinzugekommene systemd-Einheiten nicht; die Prüfanleitung zu D-P5 konnte
nicht aufgehen), beide behoben. Was noch aussteht, steht als D-P1 bis D-P11
in `PRUEFEN-AUF-DEM-PI.md`.

Von den Anforderungen in Abschnitt 5 ist damit keine mehr offen. Zwei
Punkte sind bewusst **anders** gelöst als hier zuerst gedacht; beide stehen
mit Begründung an Ort und Stelle (der Backup-Zeitplan in 5.7.4, die drei
dokumentierten statt automatisierten Sicherheitsschritte in 5.3). Sechs
Annahmen haben sich beim Messen als falsch erwiesen und stehen als
Korrekturen K1 bis K8 in Abschnitt 3.
Die Messungen im Verlauf haben sechs Annahmen widerlegt; sie stehen als
Korrekturen K3 bis K8 unten. Die jüngste, **K8**, stammt aus der Abnahme
selbst: Die Spielerstatistiken liegen nicht dort, wo dieses Dokument sie
vermutete. Was auf echter Hardware noch offen ist — alles, wofür ein
zweites Gerät, echte Spieler oder mehrere Tage Laufzeit nötig sind —,
steht in `PRUEFEN-AUF-DEM-PI.md`.

> Ein *Lastenheft* beschreibt das **WAS und WOZU**. Das **WIE** gehört ins
> *Pflichtenheft*, das je Etappe daraus abgeleitet wird.
>
> Was sich gegenüber Fassung 0.1 geändert hat: Die offenen Fragen sind
> beantwortet, die Entscheidungen stehen in Abschnitt 3, und die Anforderungen
> sind nach Etappen sortiert. Die Fassung 0.1 war eine Wunschliste; diese
> Fassung ist eine Arbeitsgrundlage.
>
> Was sich seither geändert hat, steht nicht als Umschrift im Text, sondern
> als **Korrektur K1 bis K8** unter Abschnitt 3. Das ist Absicht: Eine
> widerlegte Annahme spurlos zu überschreiben nimmt dem nächsten Leser
> genau die Information, die ihn vor derselben Annahme bewahrt hätte.

---

## 1. Ziel und Rahmen

### 1.1 Ziel

Eine leichtgewichtige All-in-one-Lösung für einen Minecraft-Server auf dem
Raspberry Pi, als öffentliches GitHub-Repository: herunterladen,
Installationsskript starten, vom Assistenten durch die wichtigsten
Einstellungen geführt werden — danach läuft ein Server, der sich über eine
Weboberfläche bedienen lässt.

Kern ist **PaperMC**. Dieses Projekt ersetzt Paper nicht und erweitert es nicht
funktional. Es legt eine durchdachte Installation, Verwaltung und Wartung
darum herum. Paper allein läuft schon sehr gut — hier kommt obendrauf, was
fehlt, damit daraus ein rundes Gesamterlebnis wird.

### 1.2 Leitsätze

Im Zweifel wird nach diesen Sätzen entschieden, in dieser Reihenfolge:

1. **Die Leistung des Minecraft-Servers hat Vorrang.** Nichts, was drumherum
   läuft, darf ihm spürbar Rechenzeit oder Speicher wegnehmen.
2. **Leichtgewichtig.** Keine Bauteile, die es nicht braucht.
3. **Einfach, aber ausgeklügelt.** Lieber einmal mehr nachgedacht, wie es rund
   wird, als es zu verkomplizieren.
4. **Lesbar für Pi-Anfänger.** Wer den Code aufmacht, soll ihn verstehen.
   Das ist ein Feature, kein Zufall.
5. **Ehrlich statt bequem.** Lieber melden, dass etwas nicht funktioniert, als
   es zu verstecken.
6. **Mit Liebe gemacht.** Minimalistisch, aber nicht lieblos.

### 1.3 Nicht-Ziele

- Keine professionelle oder kommerzielle Hosting-Lösung.
- Keine andere Plattform als der Raspberry Pi.
- Keine Minecraft-Inhalte: es geht um den Server, nicht ums Spiel.
- Kein Fork und kein Ersatz von Paper.
- Keine großen Spielerzahlen. Ausgelegt auf 5 gleichzeitig, maximal 10.
- Kein Docker (bereits begründet verworfen, siehe
  `docs/superpowers/specs/2026-08-26-picraft-optimierung-design.md`).

### 1.4 Rahmen

| | |
|---|---|
| Zielhardware | Raspberry Pi 5, 8 GB — muss auch mit 4 GB laufen |
| Betriebssystem | Raspberry Pi OS Lite, 64 Bit (arm64) |
| Speichermedium | **NVMe-SSD ist die klare Empfehlung.** Alle Leistungsaussagen gehen davon aus. Von SD-Karten wird ausdrücklich abgeraten. |
| Mitbenutzung | Der Pi teilt sich das Gerät gegebenenfalls mit anderen Diensten (z. B. Time Machine). Speicher und Festplatten-Zugriff sind nicht exklusiv. |
| Auslegung | 5 Spieler gleichzeitig, hohe Sichtweite, ruckelfrei |

### 1.5 Stakeholder

| Rolle | Wer |
|---|---|
| Entwickler | Florian |
| Nutzer heute | Florian und ~5 Mitspieler |
| Nutzer künftig | die Öffentlichkeit über GitHub |

---

## 2. Gesamteinschätzung des Ist-Standes

Der Ist-Stand ist besser als Fassung 0.1 vermuten ließ. Prüfsummen-gepinnte
Versionen, ein Online-Backup mit Warten auf die Speicher-Bestätigung und
anschließender Archivprüfung, CSRF-Schutz in der Weboberfläche, nachgemessene
JVM-Optionen mit dokumentierter Abweichung von den Standard-Aikar-Flags, ein
Makefile als Syntax-Gate. Die Kommentare erklären *warum*, nicht *was*.

**Deshalb: kein Neubau des Projekts.** Die Architektur — Bash, systemd, screen,
Flask — ist für dieses Ziel richtig. Umgebaut wird die Weboberfläche; alles
andere wird repariert, ergänzt und aufgeräumt.

---

## 3. Getroffene Entscheidungen

Diese Punkte sind entschieden und werden nicht neu aufgerollt.

| # | Thema | Entscheidung | Begründung |
|---|---|---|---|
| 1 | Architektur | Bash + systemd + Python/Flask bleiben. Kein Go, kein Docker, kein SPA-Framework. | Ein statisches Go-Binary spart ~25 MB RAM — auf 8 GB ist das Rauschen. Es kostet aber die Lesbarkeit, und die ist bei „für Anfänger geeignet" das Feature. |
| 2 | Sprache | Deutsch, überall: Code, Kommentare, Oberfläche, README. | Bleibt wie es ist. |
| 3 | Serverkonsole | **RCON kommt dazu**, `screen` bleibt. RCON wird durch die **Firewall** abgeschottet, nicht durch die Bindeadresse — siehe Korrektur unten. | `screen -X stuff` ist ein Briefkasten ohne Rückweg. Die geplante Spielerseite braucht Antworten (Whitelist, Banliste, OP-Level), nicht nur Befehle. `screen` bleibt für `mcs console` und als Vordergrundprozess für systemd. |
| 4 | Weboberfläche | **Neubau der Oberflächenschicht** auf Flask + Jinja + HTMX. Kein Build-Schritt, kein npm, kein CDN. | Von einer auf sieben Seiten bleibt vom bestehenden Template ohnehin nichts übrig. HTMX gibt das Gefühl einer modernen Oberfläche ohne Werkzeugkette. |
| 5 | Installationsweg | Klonen, dann `./install.sh`. **Kein `curl \| bash`.** | Drei Zeilen sind ein Copy-Paste-Block, das Repo wird ohnehin auf der Platte gebraucht — und `curl \| bash` schreckt genau die sicherheitsbewusste Zielgruppe ab. |
| 6 | Installationsort | Wird gefragt, Vorschlag `~/mcs`. Benutzer und Heimatverzeichnis werden ermittelt, nicht angenommen. | Der Benutzer `pi` existiert seit Raspberry Pi OS Bookworm nicht mehr. Siehe Befund B1. |
| 7 | Backup-Format | **`tar.gz` bleibt.** Kein zstd, auch nicht als Option. Kein restic, kein borg. | Ein Backup muss ohne Spezialwerkzeug zu öffnen sein. Das ist mehr wert als die eingesparte Rechenzeit. |
| 8 | Backup-Planung | Cronjob → **systemd-Timer**. | Nur so lässt sich das Backup gemeinsam mit allem anderen abschalten. Nebeneffekt: `Persistent=true` holt einen verpassten Lauf nach, wenn der Pi nachts aus war. |
| 9 | Betriebsschalter | Ein `mcs.target` bündelt alle Dienste. `mcs aus` deaktiviert es. | Echtes „alles aus", das den Neustart überlebt. Siehe Befund B4. |
| 10 | Passwort der Oberfläche | Bleibt **Klartext** in `.env` mit `chmod 600`. Kein Hash. | Nachschlagbarkeit ist dem Auftraggeber wichtiger. *Bedingung:* Es muss ein eigenes Passwort sein, das nirgendwo sonst verwendet wird — wer die Datei lesen kann, liest es im Klartext. Bei der Installation wird genau das gesagt. |
| 11 | DNS | **deSEC** ist die Empfehlung, DuckDNS bleibt möglich. Eingerichtet wird **nach** der Installation, in der Weboberfläche. | DNS ist keine Voraussetzung fürs Spielen und gehört nicht als Hürde vor die Installation. SRV-Records kann nur deSEC. |
| 12 | HTTPS | Über **Tailscale Serve**. Kein eigener Reverse-Proxy, kein selbstsigniertes Zertifikat. | Echtes Zertifikat ohne Browserwarnung, ohne zusätzliches Bauteil. Tailscale ist ohnehin im Einsatz. |
| 13 | Plugin-Quelle | **Modrinth-API.** Die Oberfläche installiert nicht selbst, sondern schreibt nach `plugins.txt` und ruft `plugin-update.sh` auf. Die `plugins.txt` gehört dabei **dem Pi**, nicht dem Repository — dort liegt nur `plugins.txt.beispiel` (ergänzt in Etappe C). | Prüfsummen kommen automatisch. Die Trennung von Vorlage und Liste ist dieselbe Lehre wie bei `mcs.conf` (Befund B2): Würde `deploy.sh` die Repo-Fassung weiter darüberkopieren, wäre jedes über die Oberfläche installierte Plugin beim nächsten Ausrollen wieder aus der Liste. |
| 14 | Plugin-Konfiguration | Ein generischer YAML-Editor mit Prüfung. **Keine Formulare je Plugin.** | Formulare je Plugin brechen bei jedem Plugin-Update und sind Wochenarbeit. |
| 15 | Vorgehen | Vier Etappen A–D. Alle werden umgesetzt, aber **einzeln und nacheinander**, jede für sich abnehmbar. | Siehe Abschnitt 6. |

---

### Korrekturen an getroffenen Entscheidungen

**K1 — RCON lässt sich nicht auf `127.0.0.1` beschränken** (28.08.2026,
gemessen zu Beginn von Etappe B).

Entscheidung 3 ging davon aus, RCON liesse sich per Konfiguration auf die
lokale Adresse festnageln. Ein Versuch mit Paper 26.2 Build 119 in einem
Container zeigt das Gegenteil:

```
[INFO]: RCON running on 0.0.0.0:25575
LISTEN  *:25575  users:(("java",...))
```

RCON bindet an **alle** Netzwerkkarten. Einen Schlüssel `rcon.ip` gibt es
nicht; Minecraft koppelt die RCON-Adresse an `server-ip`, und die muss leer
bleiben, damit der Spielserver überhaupt von aussen erreichbar ist.

**Daraus folgt:**

1. Die Abschottung übernimmt die **Firewall** — eine ausdrückliche
   Sperr-Regel für den RCON-Port, zusätzlich zur Grundregel
   „alles zu, ausser was erlaubt ist".
2. Die Firewall ist bisher **optional**. Für RCON ist sie das nicht mehr:
   Wer sie ablehnt, bekommt beim Installieren eine deutliche Warnung, dass
   der RCON-Port dann im lokalen Netz offen steht — und die Wahl, RCON
   wegzulassen.
3. Das Passwort muss stark sein (zufällig erzeugt, 24 Zeichen), weil der
   Port nicht durch die Bindeadresse geschützt ist.

Der Nutzen von RCON bleibt unverändert — die Spielerseite braucht Antworten,
nicht nur Befehle. Nur die Absicherung sieht anders aus als geplant.

**K2 — In der `server.properties` steht jetzt ein Geheimnis** (28.08.2026,
beim Abschluss von Etappe B).

Vor RCON enthielt die Datei nichts Schützenswertes. Mit `rcon.password` ändert
sich das an zwei Stellen:

1. Die Datei bekommt `chmod 600` — und zwar **bevor** das Passwort
   hineingeschrieben wird, nicht danach.
2. Der Konfigurations-Editor der Weboberfläche verdeckt den Wert
   (`rcon.password=********`) und setzt ihn beim Speichern wieder ein. Sonst
   liefe das Passwort über eine HTTP-Verbindung, stünde im Browser in einem
   Textfeld und landete in jedem Bildschirmfoto der Seite.

Für Etappe C gilt daraus die Regel: **Jeder neue Editor, der eine
Konfigurationsdatei anzeigt, muss vorher gefragt werden, ob dort ein
Geheimnis stehen kann.** Die Liste dafür ist `GEHEIME_SCHLUESSEL` in
`admin/routen.py` (bis zur Umbenennung in Etappe D: `admin_ui/`).

**K3 — Paper schreibt seine Konfigurationsdateien beim START neu, nicht beim
Herunterfahren** (28.08.2026, gemessen zu Beginn von Etappe C mit Paper 26.2
Build 119; wiederholbar mit `tests/messung-paper-verhalten.sh`).

Abschnitt 5.7.3 ging davon aus, eine Änderung an einer Konfigurationsdatei
bei laufendem Server gehe beim Herunterfahren verloren. Drei Durchgänge
zeigen etwas anderes:

| Was gemessen wurde | Ergebnis |
|---|---|
| `motd` und `view-distance` bei laufendem Server ändern, dann stoppen | beide Änderungen **überlebten** |
| YAML-Werte bei laufendem Server ändern, dann stoppen und starten | **überlebten beides** |
| Kommentar und Wert bei gestopptem Server ändern, dann starten | Wert überlebte, **Kommentar weg** (117 Zeilen mit 87 Kommentaren wurden zu 74 mit 2) |

Die Falle ist trotzdem echt, sie sieht nur anders aus. Gemessen: `motd` von
Hand gesetzt, danach ein `whitelist on` über RCON — und `motd` stand wieder
auf dem alten Wert. **Paper schreibt die ganze `server.properties` aus dem
Arbeitsspeicher neu, sobald ein Befehl eine dort gespeicherte Einstellung
ändert.** Das kann jederzeit passieren; es genügt, dass ein Operator im
Spiel `/whitelist add` tippt.

> **Präzisiert am 29.08.2026 bei der Abnahme auf dem Pi (C-P5):** Es genügt
> nicht, dass ein Befehl eine gespeicherte Einstellung *anfasst* — er muss
> sie **tatsächlich ändern**. Gemessen auf Paper 26.2 Build 119:
>
> ```
> whitelist on   auf bereits aktive Whitelist   -> Handänderung ÜBERLEBT
> whitelist off  (echte Änderung)               -> Handänderung WEG
> ```
>
> Ein Nullvorgang löst kein Neuschreiben aus. Praktisch wichtig für jeden,
> der die Falle nachstellen will: Mit `whitelist on` bei ohnehin aktiver
> Whitelist passiert **nichts**, und man hält die Falle für erfunden. Die
> Folgerungen unten ändern sich dadurch nicht — wer von außen schreibt, kann
> nicht wissen, ob der nächste Befehl ein Nullvorgang sein wird.

**Daraus folgt:**

1. `server.properties` wird bei laufendem Server **vorgemerkt**, nicht
   geschrieben — wie in 5.7.3 vorgesehen, aber aus dem richtigen Grund.
2. Die YAML-Dateien dürfen bei laufendem Server geschrieben werden. Die
   Änderung wirkt beim nächsten Start; die Oberfläche sagt das dazu.
3. Der Rohtext-Editor muss ansagen, dass eigene Kommentare in
   `server.properties` den nächsten Start nicht überleben.

**K4 — Auf einer geteilten RCON-Verbindung reißt `whitelist add` die
Verbindung ab** (28.08.2026, zweimal unabhängig reproduziert).

Sechzehn Befehle über eine Verbindung: Bei `whitelist add <name>` schließt
der Server sie, und jeder weitere Befehl derselben Verbindung läuft ins
Leere. Im Serverlog steht dazu **nichts**. Mit je einer eigenen Verbindung
läuft dieselbe Liste vollständig durch.

Die Empfehlung in 5.7.0 (Regel 3), für Schleifen `Rcon(...)` als
Kontextmanager zu benutzen, gilt damit **nur für Befehle, die den Rechner
nicht verlassen**. `whitelist add` und `op` schlagen den Namen bei Mojang
nach. Für die Spielerseite gilt: eine Verbindung je Klick, also
`rcon.befehl()`.

**K5 — In `config/paper-global.yml` steht ein Geheimnis** (28.08.2026).

Zeile 119: `secret: ''` — der Velocity-Proxy-Schlüssel. Im
Auslieferungszustand leer, aber die Datei hat Rechte `644`. Nach der Regel
aus K2 muss `GEHEIME_SCHLUESSEL` deshalb von einer flachen Liste auf eine
Liste **je Datei** erweitert werden. In `bukkit.yml`, `spigot.yml` und
`paper-world-defaults.yml` steht nichts Schützenswertes.

**K7 — `difficulty` in der `server.properties` wird beim Start ignoriert**
(28.08.2026, gemessen vor dem Bau der Konfigurationsseite).

Korrektur K3 hatte gezeigt, dass `/difficulty peaceful` die Datei nicht
ändert. Offen blieb, wer beim nächsten Start gewinnt. Gemessen:

```
Datei auf "hard" gesetzt (Server gestoppt), dann gestartet
  -> Server sagt: 'The difficulty is Easy'          die Datei wurde ignoriert
/difficulty peaceful, stoppen, starten (Datei sagt weiter "hard")
  -> Server sagt: 'The difficulty is Peaceful'      die Welt gewinnt wieder
```

**Die Schwierigkeit steht in der Welt, nicht in der Datei.** Der Eintrag in
der `server.properties` zählt nur, wenn eine Welt neu erzeugt wird; danach
wird er beim Start schlicht übergangen.

**Daraus folgt:** Die Einstellungsseite darf diesen Wert nicht aus der Datei
anzeigen — das wäre auf jeder gewachsenen Welt eine Falschaussage. Sie fragt
stattdessen den Server (`difficulty` liefert „The difficulty is Easy") und
ändert über `/difficulty <wert>`. Bei gestopptem Server ist der Wert nicht zu
ermitteln; dann sagt die Seite das.

Dasselbe Muster gilt für `white-list`: Dort schreibt der Befehl
`/whitelist on|off` die Datei zwar mit (gemessen in K3), aber auch hier ist
der laufende Server die Wahrheit.

**K6 — Es wurden vier Plugins mitinstalliert, nicht eines** (28.08.2026,
behoben am selben Tag).

Abschnitt 5.8 sagt „Mitinstalliert wird ausschließlich Pl3xMap". Tatsächlich
standen vier Plugins in `server/plugins.txt` und landeten bei jeder frischen
Installation auf dem Pi. Repository und Lastenheft sind jetzt wieder
einig: `plugins.txt.beispiel` enthält nur Pl3xMap, WorldEdit, WorldGuard,
GSit und Chunky stehen darin als auskommentierte Vorschläge.

**K8 — Die Spielerstatistiken liegen nicht in `<welt>/stats/`**
(29.08.2026, gefunden bei der Abnahme auf dem Pi, C-P7).

Abschnitt 5.7.4 nennt als Quelle für die Spielzeit
`<welt>/stats/<uuid>.json`. Auf einer Welt im aktuellen Format gibt es
diesen Ordner nicht. Minecraft sammelt die Spielerdateien seit der
Formatumstellung unter `<welt>/players/`:

```
MeineWelt/stats/            existiert NICHT
MeineWelt/players/stats/    12 Dateien      <- hier liegen sie
MeineWelt/players/advancements/
MeineWelt/players/data/                     <- früher: playerdata/
MeineWelt_oid/stats/        10 Dateien      <- Sicherung im ALTEN Format
```

Beide Formate kommen in freier Wildbahn vor: Eine Welt, die nie umgestellt
wurde, hat ihr `stats/` weiter obenauf. Die Prüfung muss deshalb **beide**
Orte kennen und darf keinen davon voraussetzen.

**Warum es niemandem auffiel:** Die Spielerseite zeigt einen Strich, wenn
keine Statistikdatei existiert — richtig so, denn „hat nie gespielt" und
„wissen wir nicht" sind zweierlei. Am falschen Ort zu suchen ergibt genau
dasselbe Bild. Der Fehler war damit unsichtbar, bis jemand nachrechnete:
Die Datei lag da, mit 539 Stunden darin.

**Daraus folgt:**

1. `spieler.py` fragt über `stats_ordner()` beide Orte ab, den neuen zuerst,
   und entscheidet anhand der **Datei**, nicht des Ordners — während einer
   Umstellung können beide existieren.
2. Testattrappen, die ein Weltformat nachbauen, bilden **beide** ab. Sonst
   prüft der Test womöglich genau den Zweig, den es auf einem echten Server
   nicht mehr gibt (dieselbe Lehre wie bei B7).

---

## 4. Befunde am Ist-Stand

Diese Punkte standen einer Veröffentlichung im Weg. **Alle sieben sind in
Etappe A behoben** (28.08.2026); sie bleiben hier stehen, weil sie erklären,
warum die Dinge heute so aussehen, wie sie aussehen.

**B1 — Der Benutzer `pi` existiert nicht mehr.**
Seit Raspberry Pi OS Bookworm (2022) legt der Imager keinen Benutzer `pi` mehr
an; jeder wählt seinen eigenen Namen. Im Projekt steckt `pi` fest in
`mcs.conf` (`MCS_USER=pi`, `/home/pi/mcs`), in `User=pi` beider
`.service`-Dateien und als Rückfallwert an 76 Stellen in 17 Dateien. Bei jedem
Nutzer, der nicht zufällig „pi" heißt, bricht die Installation.
*Der wichtigste Einzelbefund.*

**B2 — `mcs.conf` ist gleichzeitig Vorlage und Live-Konfiguration.**
Dieselbe Datei liegt im Repository und wird auf dem Pi bearbeitet. Beim
nächsten `git pull` kämpft Git mit den Einstellungen des Nutzers.

**B3 — Instanzdaten im künftig öffentlichen Repository.**
Port 25570, `MCS_REPO_DIR=/home/pi/PiCraft`, der Weltname im README. Es braucht
einen Durchgang, der alles Instanzspezifische entfernt — **einschließlich der
Git-Historie** (auf Token, Schlüssel und Passwörter prüfen).

**B4 — „Komplett aus" existiert, aber nur auf dem Pi.**
Ein `minecraft-modus ein|aus` gibt es tatsächlich: Es schaltet drei Dienste
plus den Backup-Cronjob, und der Server stand damit ab dem 2026-08-02 still.
Es liegt aber **ausschließlich lokal auf dem Pi und war nie Teil des
Repositories** — belegt ist es nur durch Erwähnungen im Design-Dokument vom
2026-08-26. Ein Klon dieses Repositories hat die Funktion also nicht.

Im Repository gibt es nur `mcs stop` (`systemctl stop`); beim nächsten Neustart
läuft der Server wieder. Das Backup hängt an einem **Cronjob**, und die alte
Lösung hat dessen Zeile auskommentiert — das funktioniert, ist aber ein
Eingriff von außen in eine fremde Datei.

Daraus folgt für Etappe A: Die Funktion wird **neu und sauber im Repository**
umgesetzt (`mcs.target`, Entscheidung 9) und löst das lokale Skript ab, statt
sich danebenzustellen.

**B5 — Keine automatische Prüfung.**
`tests/abnahme-im-container.sh` existiert und funktioniert, läuft aber nur,
wenn jemand daran denkt.

**B6 — Portkonflikt Weboberfläche / Karte.**
Pl3xMap bringt seinen eigenen Webserver mit und benutzt standardmäßig
ebenfalls Port **8080**. Die Installation muss das erkennen und auflösen.

**B7 — VillagerTalk gehört nicht hierher.**
Das Plugin ist ein eigenes Thema und hat mit diesem Server nichts zu tun. Es
darf **an keiner Stelle** auftauchen: nicht in der Installation, nicht in
`plugins.txt`, nicht in Kommentaren, nicht in der Dokumentation. Der Hinweis
auf den zugehörigen systemd-Drop-in und den API-Schlüssel muss ebenfalls weg.

---

## 5. Anforderungen

### 5.1 Installation

Der Ablauf bleibt: Repository klonen, `./install.sh` starten, Assistent
durchlaufen, fertig. Was dazukommt:

**Alles ermitteln, nichts annehmen.** Vor den Fragen prüft und meldet die
Installation:

- **Benutzer und Heimatverzeichnis** aus `$USER` / `$HOME` (Befund B1)
- **Pi-Modell** (`/proc/device-tree/model`) — bei Pi 3 oder Zero abraten,
  bei Pi 4 andere Vorgabewerte
- **64-Bit-System** (`getconf LONG_BIT` → `64`; nicht `uname -m` — das 32-Bit-Raspberry-Pi-OS läuft auf Pi 4/5 mit 64-Bit-Kernel und meldet dort `aarch64`)
- **Arbeitsspeicher** (`/proc/meminfo`) → daraus den Heap ableiten,
  nicht 8 GB voraussetzen
- **Speichermedium: SD-Karte oder SSD?** Der wichtigste Check überhaupt.
  Minecraft auf einer SD-Karte ist die häufigste Ursache für schlechte
  Leistung und für tote Karten. Eine deutliche Warnung an dieser Stelle ist
  mehr wert als jede JVM-Option.
- **Port 8080 frei?** (Befund B6)

**So allgemein wie möglich.** Die Installation darf nichts über die konkrete
Umgebung voraussetzen. Vorgabewerte sind neutral:

- Welt heißt **`world`**
- Port ist **25565**
- MOTD und Weltname sind allgemein, nicht persönlich
- keine instanzspezifischen Plugins
- keine Annahme über Router, Anschlussart oder Zeitzone

**Fragen im Assistenten.** Es wird nur gefragt, was wirklich eine Entscheidung
ist; alles andere bekommt einen begründeten Vorschlag, den die Eingabetaste
übernimmt. Neu hinzu kommen Benutzer/Passwort für die Weboberfläche (mit dem
Hinweis aus Entscheidung 10) und der Installationsort.

**Ports.** Zunächst werden die Standardports geöffnet; ändern lässt sich das
später in der Weboberfläche. Wie man einen Port im Router freigibt, steht ganz
oben im README beim Punkt Installation.

**Die Weboberfläche wird immer mitinstalliert**, außer man gibt beim Aufruf
ausdrücklich das Gegenteil an.

**Am Ende** zeigt die Installation die Adresse der Weboberfläche. Ab dort wird
alles Weitere dort konfiguriert.

### 5.2 Aufbau und Betrieb

**Zwei Bedienwege, gleichberechtigt:** die Weboberfläche als Hauptwerkzeug, und
`mcs …` im Terminal für alles, was man lieber tippt.

**Zwei Ebenen von „aus":**

| Befehl | Wirkung |
|---|---|
| `mcs stop` / `start` / `restart` | nur der Paper-Server. Backup, Weboberfläche und Autostart laufen weiter. |
| `mcs aus` / `mcs an` | **alles**: Server, Backup, Weboberfläche, Spielerprotokoll, DNS-Nachführung (seit Etappe D). Überlebt den Neustart des Pi. Für längere Pausen, etwa über den Sommer. |

Technisch über ein `mcs.target`, das alle Dienste einsammelt (Entscheidung 9).
Das Backup muss dafür von Cron auf einen systemd-Timer umziehen
(Entscheidung 8), sonst lässt es sich nicht mitschalten.

**Bei „aus" darf nichts fälschlich Alarm schlagen.** Die Altersgrenze für
Backups (`MCS_BACKUP_WARNUNG_STUNDEN`, 48 Stunden) muss an den Betriebszustand
gekoppelt sein — sonst meldet `mcs status` nach zwei Tagen Sommerpause einen
Backup-Ausfall, den es gar nicht gibt. Dieser Punkt stand schon im
Design-Dokument vom 2026-08-26 offen; **erledigt in Etappe A**
(`mcs_abgeschaltet()` in `admin/system.py`, geprüft als A-P2 auf dem Pi).

Keine hochkomplexen Skripte und Werkzeuge — alles setzt direkt auf der
Standard-Paper-Installation auf.

### 5.3 Sicherheit

| | Anforderung |
|---|---|
| Weboberfläche | Erreichbar **nur im lokalen Netz oder über Tailscale**. Nie direkt aus dem Internet. |
| Minecraft-Server | Aus dem Internet erreichbar, ohne Tailscale. |
| Weltkarte | Aus dem Internet erreichbar, ohne Tailscale. |
| Ports | Nur was gebraucht wird ist offen, SSH bleibt offen. Die Weboberfläche zeigt, welcher Port wofür offen ist. |
| RCON | Port per Firewall gesperrt (siehe Korrektur K1). Passwort bei der Installation erzeugt, nie im Repository. Ist die Firewall nicht aktiv, wird beim Installieren ausdrücklich gewarnt. |
| Dienste | Laufen nie als root. Die sudo-Regeln bleiben eng begrenzt. |
| Anmeldung | Sitzungs-Cookie statt HTTP Basic Auth — Basic Auth kennt kein Abmelden und hängt die Zugangsdaten an jede Anfrage. Ein Cookie mit `SameSite=Lax` löst zugleich den CSRF-Schutz sauberer als der bisherige Content-Type-Trick. |
| Anmeldeversuche | Einfache Ratenbegrenzung. |
| HTTPS | Über Tailscale Serve (Entscheidung 12). |
| Betriebssystem | `unattended-upgrades` einrichten — automatische Sicherheitsupdates. Ein Einzeiler mit der größten Wirkung pro Zeile im ganzen Projekt. |
| SSH | Anmeldung per Schlüssel statt Passwort wird **dokumentiert**, nicht erzwungen. |

*Bewusst in Kauf genommen:* Die öffentlich erreichbare Weltkarte ist ein
zweiter Webserver am Internet. Er liefert im Wesentlichen statische Kacheln,
das Risiko ist überschaubar — aber es ist nicht null.

**Umgesetzt bis Etappe D.** Drei dieser Zeilen sind ausdrücklich
*Dokumentation* und keine Automatik; sie stehen seit dem 30.08.2026 im
README, und zwar bewusst als Handgriff statt als Vorgabe:

| Zeile | Wo | Warum nicht automatisch |
|---|---|---|
| HTTPS über Tailscale Serve | README, „Zugriff über Tailscale" (beide Wege, drei Fallstricke) | Tailscale ist ein fremder Dienst mit eigener Anmeldung. Ihn einzurichten ist eine Entscheidung, kein Installationsschritt. |
| SSH per Schlüssel | README, „SSH: Anmeldung per Schlüssel statt Passwort" | Steht so in der Anforderung: *dokumentiert, nicht erzwungen*. Wer sich beim Abschalten des Passwort-Logins vertippt, kommt nur noch mit Tastatur am Pi weiter. |
| Weltkarte aus dem Internet | README, „Die Weltkarte öffentlich erreichbar machen" | Es öffnet einen Port ins Internet. Diese Entscheidung trifft der Betreiber, nicht das Installationsskript — sonst stünde nach `./install.sh` ungefragt ein zweiter Webserver offen. |

### 5.4 Backups

Der bestehende Mechanismus ist der stärkste Teil des Projekts und bleibt im
Kern erhalten: Online-Backup mit `save-off`, Warten auf die Bestätigung von
`save-all flush`, Packen, Prüfen des Archivs, `save-on`, Rotation, Dauerarchiv,
Fehler-Merkzettel.

Was dazukommt:

1. **Benachrichtigung bei Fehlschlag** (ntfy.sh, Telegram oder ähnlich,
   optional). Zwei Monate ohne Backup, ohne dass es jemandem auffiel — das ist
   die wichtigste Lehre aus der Projektgeschichte. Ein Statusfeld in der
   Oberfläche ist gut, aber passiv.
2. **systemd-Timer statt Cron** (Entscheidung 8).
3. **`mcs restore --probe`** — entpackt in ein temporäres Verzeichnis und
   prüft. Macht aus „wir haben Backups" ein „wir haben funktionierende
   Backups".
4. **Zweitziel auf einem anderen Datenträger** als Schalter in der Oberfläche
   sichtbar machen (die Möglichkeit besteht bereits, wird aber nicht genutzt).
5. **Archiv erst unter einem Zwischennamen packen, dann umbenennen.** Aufgefallen
   in Etappe A: Das Skript schreibt direkt nach `backup_<zeit>.tar.gz` und prüft
   das Archiv erst danach. Ein abgebrochener Lauf hinterlässt damit eine halbe
   Datei, die für die Rotation wie ein gültiges Backup aussieht — und im
   Zweifel ein echtes verdrängt.

Das Format bleibt `tar.gz` (Entscheidung 7).

### 5.5 Performance

Ziel: **5 Spieler, hohe Sichtweite, keine Ruckler.** Auf einem Pi 5 mit
NVMe-SSD erreichbar.

Zwei Hebel sind wichtiger als alle JVM-Optionen zusammen:

1. **Sichtweite und Simulationsdistanz trennen.** `view-distance` bestimmt, wie
   weit Spieler *sehen*; `simulation-distance`, wie weit die Welt tatsächlich
   *rechnet* — Mobs, Redstone, Wachstum. Die Kosten hängen fast ausschließlich
   an der zweiten Zahl. Etwa `view-distance=12` bei `simulation-distance=5`
   sieht weit aus und kostet einen Bruchteil. **Das ist die Antwort auf „hohe
   Sichtweite ohne Ruckler"** und muss Vorgabewert sein *und* auf der
   Einstellungsseite erklärt werden.
2. **Speichermedium** (siehe 1.4 und 5.1).

**Die JVM-Optionen werden nicht angefasst.** Die Herleitung in
`docs/optimierung-2026-07-27.md` ist sauber und nachgemessen, einschließlich
der begründeten Abweichung von den Standard-Aikar-Flags. Ohne neue Messung
wird daran nichts geändert.

Der Heap wird bei der Installation aus dem tatsächlichen Arbeitsspeicher
abgeleitet, nicht fest vorgegeben.

### 5.6 DNS und Erreichbarkeit

Damit Mitspieler den Server immer unter demselben Namen erreichen.

- **deSEC ist die Empfehlung** (Entscheidung 11): kostenlos, DNSSEC, von einem
  deutschen gemeinnützigen Verein betrieben. DuckDNS bleibt als Möglichkeit
  bestehen.
- **SRV-Record.** Mit einem `_minecraft._tcp`-Eintrag tippen Mitspieler
  `mc.beispiel.de` **ohne Portangabe**, auch wenn der Server auf einem anderen
  Port läuft. DuckDNS kann das nicht, deSEC schon.
- **Eingerichtet wird nach der Installation, in der Weboberfläche.** Anbieter
  wählen, Token eintragen, fertig.

**Der eigentliche Blocker heißt DS-Lite.** Ein großer Teil der deutschen
Anschlüsse (Kabel, viele Glasfaseranbieter) hat gar keine öffentliche
IPv4-Adresse. Eine Portfreigabe im Router ist dort schlicht unmöglich, und kein
DNS-Dienst der Welt ändert daran etwas. Für ein öffentliches Repository braucht
es dafür eine Antwort:

- **Erreichbarkeitstest** bei der Installation und in der Oberfläche — nicht
  nur „Port im Router freigeben", sondern konkret prüfen und benennen:
  *„Dein Port ist von außen nicht erreichbar, und zwar weil dein Anschluss
  DS-Lite benutzt."*
- **IPv6** als Weg für Mitspieler, die selbst IPv6 haben.
- **playit.gg** als dokumentierter Ausweg für alle anderen: Tunnel, kostenlos,
  ohne Portfreigabe.

### 5.7 Weboberfläche

Das größte Arbeitspaket. Neubau der Oberflächenschicht (Entscheidung 4).

**Umgesetzt am 28.08.2026.** Alle sieben Seiten stehen. Was dabei anders
gebaut wurde als hier beschrieben — und warum — steht im Pflichtenheft C;
die drei Messbefunde, die den Entwurf verändert haben, stehen oben als
Korrekturen K3, K4 und K7.

#### 5.7.0 Was Etappe C bereits vorfindet

Etappe B hat die Datenbasis gelegt. Wer die Oberfläche baut, muss das
Folgende nicht mehr selbst schaffen:

**Module in `admin/`** (flache Module, kein Paket — Begründung im
Pflichtenheft B):

| Modul | Was daraus zu holen ist |
|---|---|
| `einstellungen.py` | alle Pfade, `ADMIN_USER`, `AUTH_ENABLED`, `ALLOW_HOST_POWER` |
| `system.py` | `cpu_usage_percent`, `memory_stats`, `disk_stats`, `pi_temperature_c`, `service_state`, `service_uptime`, `run_command`, `run_background`, `read_last_lines`, `mcs_abgeschaltet` |
| `protokoll.py` | `online_players`, `chat_lines`, `activity_lines`, `error_lines` |
| `konsole.py` | `send_to_minecraft_console` (screen), `action_command` (Liste der erlaubten Aktionen), `sanitize_console_input` |
| `rcon.py` | `befehl(text)` → Antwort als Text, `verfuegbar()`, `RconFehler`, `RconAnmeldungFehlgeschlagen` |
| `metrik.py` | `verlauf(stunden, hoechstens)`, `anzahl()`, `tps_lesen`, `mspt_lesen`, `server_werte()` |
| `status.py` | `current_status()` — das komplette Statusbild, 3 s zwischengespeichert |
| `sicherheit.py` | `auth_required`, `nur_eigene_oberflaeche` (CSRF) |
| `routen.py` | die Blueprint `seiten`, dazu `GEHEIME_SCHLUESSEL` |

**Vorhandene Schnittstellen:**

```
GET  /                              Startseite (index.html)
GET  /api/status                    kompletter Status inkl. tps, mspt, rcon_verfuegbar
GET  /api/verlauf?stunden=N         Messwerte für die Kurven (max. 7 Tage)
GET  /api/logs/<typ>                chat | activity | error | service
GET  /api/server-properties         Inhalt, Geheimnisse verdeckt
POST /api/server-properties         speichern, Geheimnisse zurückgesetzt
POST /api/console                   Chat-Nachricht oder Befehl (über screen)
POST /api/action/<name>             start/stop/restart/backup_now/update_paper
```

**Was RCON jetzt beantworten kann** — die Grundlage der Spielerseite:
`list`, `whitelist list`, `banlist players`, `banlist ips`, `op`/`deop`,
`kick`, `ban`, `pardon`, `tps`, `mspt`. Mehrteilige Antworten über 4096 Byte
funktionieren (mit 16.201 Zeichen geprüft).

**Verlaufsdaten** liegen in `<Installationsort>/admin/metrik.db`, ein
Datensatz je Minute, sieben Tage: `zeit, cpu, ram, platte, temp, tps, mspt,
spieler`.

**Drei Regeln, die in Etappe C gelten:**

1. **Jeder neue Editor für eine Konfigurationsdatei** muss geprüft werden, ob
   dort ein Geheimnis stehen kann (Korrektur K2). Die Liste ist
   `GEHEIME_SCHLUESSEL` in `routen.py`.
2. **Konfiguration nur bei gestopptem Server schreiben** (siehe 5.7.3) — das
   gilt auch für `server.properties`, nicht nur für die YAML-Dateien.
3. **RCON sparsam benutzen.** Es läuft im Hauptthread des Servers. Eine
   Abfrage je Klick ist richtig, eine je Sekunde nicht. `rcon.befehl()` baut
   je Aufruf eine neue Verbindung auf; für Schleifen `Rcon(...)` als
   Kontextmanager benutzen — **aber nur für Befehle, die den Rechner nicht
   verlassen** (siehe Korrektur K4). `whitelist add` und `op` schlagen den
   Namen bei Mojang nach und reißen eine geteilte Verbindung ab.



#### 5.7.1 Gestaltung — Minecraft-Look, zeitlos

Gewollt ist Minecraft als **Herkunft, nicht als Kostüm**. Nicht altbacken,
nicht modisch, mit Herz.

**Ja:**

- **Eckig.** Keine abgerundeten Ecken, nirgends. Minecraft ist quadratisch —
  das ist das billigste und stärkste Erkennungsmerkmal.
- **Die Kante.** Flächen und Schaltflächen bekommen die typische Fase: helle
  Kante oben und links, dunkle unten und rechts. Zwei Zeilen CSS, sofort
  erkennbar — und sie altert nicht, denn sie steht in einer Tradition, die
  schon dreißig Jahre hält.
- **Materialfarben statt Texturen.** Erdiges Grün, warmes Braun, Steingrau und
  das tiefe Blauschwarz der Inventaransicht. Als richtiges Farbsystem angelegt,
  nicht als Kachelbild im Hintergrund.
- **Dunkel als Standard.** Die Inventar-Bildschirme sind dunkel, und abends auf
  dem Handy will man das ohnehin.
- **Zwei, drei Stellen, an denen es richtig Minecraft ist.** Der Spielerzähler
  als Herzenleiste, der „alles in Ordnung"-Balken im Grün der
  Erfahrungsleiste. Sparsam gesetzt hat das Charme; überall gesetzt wird es
  Kitsch.

**Nein:**

- **Keine Pixelschrift im Fließtext.** Auf dem Handy schlecht lesbar — und
  genau die Sorte „altbacken", die nicht gewollt ist. Pixelschrift höchstens
  für Überschriften und große Zahlen, alles andere eine ruhige, gut lesbare
  Grotesk.
- **Keine Erd- oder Steintexturen als Hintergrund.** Sie fressen Kontrast und
  machen Text schwer lesbar.
- Kein Glaseffekt, keine Verläufe, kein Neon, keine großen Eckenradien. Das
  sind die Moden, an denen man später das Baujahr abliest.
- Keine Animation über das Nötige hinaus. Minecrafts Oberfläche animiert nicht.

#### 5.7.2 Technik

- **Flask + Jinja + HTMX**, kein Build-Schritt, kein npm, kein Node auf dem Pi.
- **Alles wird lokal ausgeliefert, nichts von einem CDN.** Die Oberfläche muss
  auch ohne Internetverbindung funktionieren, und ein Verwaltungswerkzeug
  sollte keine Anfragen nach außen stellen.

  > **Präzisiert nach Etappe D.** Der zweite Halbsatz ist als *Vorgabe*
  > gemeint, nicht als Verbot: Drei Dinge, die das Projekt können soll,
  > lassen sich von innen grundsätzlich nicht beantworten — welche
  > Plugin-Version es gibt (Modrinth), welche öffentliche Adresse dieser
  > Anschluss hat und ob der Server von außen erreichbar ist. Dafür gilt
  > durchgehend:
  >
  > 1. **Beim Aufbau einer Seite geht nie etwas nach außen.** Es braucht
  >    einen Klick.
  > 2. **Daneben steht, wer gefragt wird** — mit Namen, und was er dabei
  >    erfährt.
  > 3. **Ohne Netz bleibt die Seite benutzbar** und sagt „nicht
  >    feststellbar" statt eines Fehlers.
  >
  > Betroffen sind die Plugin-Seite (Modrinth, Entscheidung 13) sowie auf
  > der Konfigurationsseite der Erreichbarkeitstest und das DNS-Modul
  > (Etappe D). Alles andere kommt weiterhin vom Pi selbst.
- **Graphen mit uPlot** (~40 KB) statt Chart.js — für Zeitreihen gebaut, um
  Größenordnungen schneller, wichtig auf dem Handy.
- **`app.py` wird ein Paket.** Ein Blueprint je Seite. Der Reiz von 891 Zeilen
  in einer Datei endet bei etwa 1.200.
- **Verlaufsdaten in SQLite** — Standardbibliothek, eine Datei, ein Datensatz
  pro Minute. Sieben Tage sind rund 10.000 Zeilen. Kein RRD, kein Prometheus,
  kein Grafana. Ein Hintergrundthread sammelt CPU, RAM, Temperatur, TPS und
  MSPT; TPS und MSPT kommen über RCON.
- **Auflösung: eine Minute.** Sekundengenaue Verläufe kosten das Sechzigfache
  und zeigen nichts, was man sehen will.

#### 5.7.3 Die Falle, die eingeplant werden muss

*Neu gefasst am 28.08.2026 nach der Messung zu Etappe C — siehe Korrektur K3.
Vorher stand hier, Paper schreibe seine Konfigurationsdateien beim
Herunterfahren neu. Das tut es nicht.*

**Paper schreibt `server.properties` neu, sobald ein Befehl eine dort
gespeicherte Einstellung ändert** — und zwar die ganze Datei, aus dem
Arbeitsspeicher. Jede Änderung, die inzwischen von außen hineingeschrieben
wurde, ist damit weg. Das kann jederzeit passieren: Es reicht, dass ein
Operator im Spiel `/whitelist add` tippt.

*Präzisiert am 29.08.2026 (C-P5): Der Befehl muss den Wert **tatsächlich
ändern**. Ein `/whitelist on` auf eine bereits aktive Whitelist ist ein
Nullvorgang und löst nichts aus — wer die Falle damit nachstellen will,
sieht nichts passieren und hält sie für erfunden.*

Daraus folgt für den Konfigurationsteil der Oberfläche:

| Lage | Regel |
|---|---|
| Server steht | direkt schreiben |
| Server läuft, `server.properties` | **vormerken** und beim nächsten Start anwenden |
| Server läuft, YAML-Datei | direkt schreiben — gemessen unbedenklich; die Änderung wirkt beim nächsten Start |
| Server läuft, `white-list` | über `/whitelist on\|off` — wirkt sofort, und Paper schreibt die Datei selbst |

Vorgemerkte Änderungen werden sichtbar angezeigt („3 Änderungen warten auf
den nächsten Neustart"), nicht versteckt.

**Zusätzlich:** Beim Start entfernt Paper alle Kommentare aus
`server.properties` (gemessen: 87 Kommentarzeilen wurden zu 2) und sortiert
die Schlüssel alphabetisch. Der Rohtext-Editor muss das ansagen — sonst
schreibt jemand sich eine Erklärung an eine Zeile und wundert sich.

#### 5.7.4 Seiten

Reihenfolge der Reiter: **entschieden**, siehe O2 in Abschnitt 8 — Start ·
Spieler · Leistung · Karte · Backups · Konfiguration · Plugins. Die
Nummerierung hier unten ist die ursprüngliche und sagt nichts über die
Reihenfolge in der Oberfläche.

**1 — Startseite.**
Kacheln, anklickbar, mit den wichtigsten Werten auf den ersten Blick. Die
Leitfrage: *Was will ich in fünf Sekunden vom Handy aus wissen?*
Server läuft, wer ist online, TPS, letztes Backup, freier Plattenplatz,
Temperatur. Dazu ein Eingabefeld für Chat-Nachricht oder Befehl. Und eine
**Ereignisleiste** mit den letzten fünf relevanten Vorgängen (Spieler
beigetreten, Backup fertig, Server neu gestartet). Alles Weitere ist eine Seite
tiefer richtig aufgehoben.

**2 — Spieler.**
Alle Spieler, die je auf dem Server waren, mit Online-Kennzeichnung. Bei
Online-Spielern: seit wann. Bei allen anderen: wann zuletzt.
Rechte sehen und ändern (OP, Berechtigungsstufe). Whitelist und Sperrliste
sehen und verwalten. Mit einem Klick kicken (mit Grundangabe) und sperren.
*Ergänzung:* gespielte Gesamtzeit, erste Verbindung, letzte bekannte
IP-Adresse — hilfreich, wenn jemand Ärger macht.

**3 — Konfiguration.**
Zwei Ebenen, weil eine nicht reicht:

- **Ebene 1 „Einstellungen":** die rund 20 Werte, die wirklich zählen, als
  richtige Bedienelemente mit deutscher Erklärung und sicheren Wertebereichen
  — Spielmodus, Schwierigkeit, PvP, Sichtweite, Simulationsdistanz,
  Spielerzahl, MOTD, Whitelist, Spawn-Schutz.
- **Ebene 2 „Expertenmodus":** Rohtext-Editor je Datei
  (`server.properties`, `bukkit.yml`, `spigot.yml`, `paper-global.yml`,
  `paper-world-defaults.yml`) mit Prüfung beim Speichern, automatischer
  Sicherung der Vorfassung und Diff-Anzeige vor dem Übernehmen.

Formulare für jeden Schlüssel jeder Datei wären Wochenarbeit und brächen bei
jedem Paper-Update — `paper-world-defaults.yml` allein hat 341 Zeilen. Die
kuratierte Liste plus ehrlicher Rohzugriff ist das richtige Verhältnis.

Auf dieselbe Seite gehören: hochfahren, herunterfahren, neu starten,
aktualisieren; welche Paper- und Java-Version installiert sind; welche Ports
offen sind, wofür und warum; alles Weitere zur Sicherheit.

**4 — Backups.**
Zeitplan sehen und ändern. Wie viele Backups es gibt und welche. Mit einem
Klick wiederherstellen oder löschen. Aufbewahrungsregeln, Dauerarchiv,
Zweitziel auf anderem Datenträger, Benachrichtigung bei Fehlschlag.

> **Abweichung, entschieden in Etappe C:** Der Zeitplan wird *gezeigt, aber
> nicht in der Oberfläche geändert.* Er steht in `mcs-backup.timer` unter
> `/etc/systemd/system/`; ihn von dort aus zu schreiben hiesse, der
> Oberfläche `systemctl edit` und `daemon-reload` zu erlauben — eine
> deutlich weitere sudo-Regel als alles, was sie sonst darf, und das für
> einen Wert, den man einmal einstellt und dann jahrelang nicht mehr
> anfasst. Die Seite nennt stattdessen den Befehl. Dieselbe Abwägung wie
> beim DNS-Timer (Pflichtenheft D, Entscheidung E13).

**5 — Leistung.**
CPU, RAM, Festplatte, Temperatur, Last, TPS und MSPT. Verlauf als Graph über
**1 Minute / 1 Stunde / 24 Stunden**.
Dazu Einstellungen: Arbeitsspeicher mit Empfehlung je nach vorhandenem RAM und
geplanter Spielerzahl, Sichtweite, Simulationsdistanz — über Auswahlfelder,
kein Expertenwerkzeug.
*Keine GPU-Anzeige:* Die VideoCore-GPU des Pi tut für einen Minecraft-Server
nichts. Die Kachel wäre Dekoration.

**6 — Plugins.**
Übersicht der installierten Plugins mit Version und Zustand.
Suchen und installieren über die Modrinth-API — die liefert Suche, Versionen,
Prüfsummen und, entscheidend, welche Spielversion ein Plugin unterstützt. Die
Oberfläche schreibt nach `plugins.txt` und ruft `plugin-update.sh`
(Entscheidung 13).
Aktivieren und deaktivieren durch Umbenennen `.jar` ↔ `.jar.disabled`,
Neustart nötig — simpel und ehrlich.
Konfiguration über den generischen YAML-Editor (Entscheidung 14).

**7 — Weltkarte.**
Pl3xMap als iframe eingebettet, plus „in neuem Tab öffnen". Das überlebt jedes
Pl3xMap-Update; ein Reverse-Proxy wäre ein Bauteil mehr für kaum Gewinn.
Portkonflikt beachten (Befund B6).

### 5.8 Plugins

Mitinstalliert wird ausschließlich **Pl3xMap** für die Karte. Bis zum
28.08.2026 waren es tatsächlich vier (Korrektur K6); seither stimmt das
Repository wieder mit diesem Satz überein.

Die Liste `plugins.txt` gehört **dem Pi** (Entscheidung 13). Im Repository
liegt nur `server/plugins.txt.beispiel`; `install.sh` legt daraus einmalig
die echte Datei an, `deploy.sh` fasst sie danach nicht mehr an.

**Empfohlen, aber nicht mitinstalliert** — auskommentiert in der Vorlage und
als Vorschlag auf der Plugin-Seite:

- **Chunky** — Gelände zu erzeugen ist mit Abstand das Teuerste, was ein Server
  tut; deshalb ruckelt es genau dann, wenn jemand in unerforschtes Gebiet
  läuft. Einmal über Nacht einen Radius vorgenerieren, und das Problem ist
  praktisch weg. Einmalig benutzt, große Wirkung.
- **WorldEdit / WorldGuard** — für Bauen und Schutzbereiche.

GSit stand hier bis zum 21.10.2026 als vierter Vorschlag. Es ist auf
Wunsch des Betreibers gestrichen und wird weder empfohlen noch angeboten.

Gelöscht wird nie etwas automatisch. Ein Plugin, das auf dem Pi liegt, aber
nicht in der Liste steht, wird nur gemeldet.

### 5.9 Repository und Veröffentlichung

- Aufräumen der obersten Ebene: Bibliotheken nach `lib/`, `admin_ui/` →
  `admin/`. **Erledigt am 30.08.2026 (Etappe D, Paket D7).** Auf dem Pi
  ändert sich dadurch nichts — dort hiess das Verzeichnis der Oberfläche
  seit jeher `admin`; umbenannt wurde nur die Quelle im Repository, womit
  die Namen endlich übereinstimmen.
- `mcs.conf.beispiel` im Repository, `mcs.conf` auf dem Pi und in `.gitignore`
  (Befund B2).
- Scrub aller Instanzdaten, einschließlich Git-Historie (Befunde B3, B7).
- **GitHub Actions**: `make` + shellcheck + Container-Abnahmetest bei jedem
  Push (Befund B5). Billig und für ein öffentliches Repository ein
  Glaubwürdigkeitsgewinn.
- README: Alles, was für die Erstinstallation zählt, steht ganz oben —
  einschließlich Portfreigabe im Router und DNS.

---

## 6. Etappen

Alle vier werden umgesetzt, aber nacheinander. Jede ist für sich abnehmbar.

| Etappe | Inhalt | Stand |
|---|---|---|
| **A — Fundament** | Befunde B1–B7: `pi`-Annahme raus, `mcs.conf.beispiel`, Instanzdaten-Scrub, VillagerTalk entfernen, `mcs.target` + systemd-Timer (löst das lokale `minecraft-modus` ab), Portkonflikt, GitHub Actions | **fertig** (28.08.2026) — Commits `c0ae8f8`, `49eb44d` |
| **B — Schnittstelle** | RCON, Metrik-Sammler + SQLite, `app.py` → Paket | **fertig** (28.08.2026) — Commits `c130f90`, `0622f01`, `397a37b` |
| **C — Weboberfläche** | Die sieben Seiten, Gestaltung, HTMX, Graphen, Plugin- und Konfigurationsverwaltung | **fertig** (28.08.2026) — Pflichtenheft in `docs/pflichtenheft-etappe-c.md` |
| **D — Politur** | DNS-Modul, Erreichbarkeitstest, Benachrichtigungen, Erkennung von Hardware und Speichermedium, `unattended-upgrades`, README | **umgesetzt** (30.08.2026) — Pflichtenheft in `docs/pflichtenheft-etappe-d.md`. Am selben Tag auf dem Pi ausgerollt und abgenommen, soweit ohne fremdes Gerät möglich: D-P1, D-P3, D-P6 ganz, D-P5/D-P7/D-P8/D-P9/D-P11 im prüfbaren Teil. Offen: D-P2 (SD-Karte), D-P4 (Zustellung aufs Handy), D-P10 (Tailscale vom Handy) |

Damit sind alle vier Etappen umgesetzt. **Was bleibt, ist Abnahme, nicht
Umsetzung:** die Prüfpunkte in `PRUEFEN-AUF-DEM-PI.md`, für die es echte
Hardware, einen echten Anschluss und echte Mitspieler braucht.

Je Etappe wird ein Pflichtenheft abgeleitet, bevor umgesetzt wird.

---

## 7. Abnahmekriterien

**Je Etappe:**

| | Stand |
|---|---|
| `make` läuft ohne Beanstandung, GitHub Actions ist grün | ✅ für A–D |
| Der Container-Abnahmetest läuft durch | ✅ für A–D, zuletzt am 30.08.2026 ohne eine einzige Beanstandung |
| Ein zweiter Lauf der Installation verändert nichts und bricht nichts | ✅ beide Läufe mit Rückgabewert 0 |
| Was die Etappe versprochen hat, ist nachweislich da | ✅ für A–D |

**Für das Gesamtprojekt:**

| | Stand |
|---|---|
| Frische Installation mit **beliebigem Benutzernamen** ergibt einen laufenden Server | ✅ Der Abnahmetest installiert bewusst als `mcstester`, nicht als `pi` |
| `mcs aus` schaltet wirklich alles ab und überlebt den Neustart | ✅ auf dem Pi geprüft (A-P1). Der neue DNS-Timer hängt seit dem 30.08.2026 richtig (`WantedBy`/`PartOf` = `mcs.target`, nachgemessen mit `systemctl show`) — dass ihn ein echter Neustart unten lässt, steht noch aus (D-P9) |
| Ein Backup lässt sich wiederherstellen — geprüft, nicht angenommen | ✅ auf dem Pi geprüft (C-P10) |
| **Alles in diesem Dokument ist umgesetzt, alle offenen Punkte sind geklärt** | ✅ Abschnitt 8 enthält keinen offenen Punkt mehr |
| Fünf Spieler spielen gleichzeitig mit hoher Sichtweite ohne Ruckler (TPS bleibt bei 20) | ⬜ **das letzte offene Kriterium** — braucht fünf echte Spieler gleichzeitig (P-D/P-E in `PRUEFEN-AUF-DEM-PI.md`) |

Was zum Abschluss noch fehlt, braucht also keine Zeile Code mehr, sondern
echte Hardware, einen echten Anschluss und echte Mitspieler. Die Liste
dafür ist `PRUEFEN-AUF-DEM-PI.md`.

---

## 8. Offene Punkte

| # | Punkt | Status |
|---|---|---|
| O1 | Aktuellste stabile Versionen von Paper, Java und Plugins zum Umsetzungszeitpunkt | **erledigt durch Automatik**: Die Plugin-Seite fragt Modrinth selbst ab, `mcs update --pruefen` fragt PaperMC, und Java kommt bei der Installation aus Debian bzw. Adoptium. Eine Momentaufnahme in diesem Dokument wäre am Tag der Veröffentlichung wieder falsch. Fest bleibt nur die *Minecraft*-Version in `versions.env` — aus gutem Grund (ein Wechsel ist endgültig). |
| O2 | Reihenfolge der Reiter in der Weboberfläche | **entschieden** (28.08.2026): Start · Spieler · Leistung · Karte · Backups · Konfiguration · Plugins. Erst, was man ansieht, dann, was man ändert — und je weiter rechts, desto mehr lässt sich kaputt machen. |
| O3 | Welche 20 Werte genau auf die kuratierte Einstellungsseite kommen | **entschieden** (28.08.2026): 15 auf der Konfigurationsseite, 4 auf der Leistungsseite. Sichtweite, Simulationsdistanz und Heap stehen **nur** auf der Leistungsseite — dort, wo die Kurve daneben zeigt, was sie kosten. Liste im Pflichtenheft C, Entscheidung E2. |
| O4 | Benachrichtigungsweg bei Backup-Fehlschlag (ntfy.sh, Telegram, anderes) | **entschieden** (30.08.2026): **ntfy**. Kein Konto, kein Bot, kein SMTP — zwei Schritte statt fünf. Der Haken (bei ntfy.sh ist der Themenname das ganze Geheimnis) wird überall dazugesagt, wo man ein Thema einträgt. Begründung im Pflichtenheft D, Entscheidung E9. |
| O5 | Konkrete Wahl der Schriftarten für den Minecraft-Look | **entschieden** (28.08.2026): Fließtext im System-Stapel ohne Webfont, Messwerte im System-Monospace, Überschriften in einer mitgelieferten Pixelschrift unter SIL-OFL. Einzelheiten im Pflichtenheft C, Entscheidung E3. |
| O6 | Was das lokale `minecraft-modus`-Skript auf dem Pi genau tut (welche drei Dienste, wie es den Cronjob schaltet) | **geklärt und erledigt** (29.08.2026, A-P4): Es lag als `/usr/local/bin/minecraft-modus`, schaltete drei Dienste und kommentierte die Backup-Zeile in der Crontab aus. Ersetzt durch `mcs an` / `mcs aus` über `mcs.target` — und dem alten Skript überlegen: Es hätte eine Crontab-Zeile abgeschaltet, die es seit dem Umstieg auf den Timer gar nicht mehr gibt, und den Timer weiterlaufen lassen. Nach geprüfter Verweisfreiheit gelöscht. |

**Damit ist kein Punkt in diesem Abschnitt mehr offen.** Was noch aussteht,
sind Prüfungen auf echter Hardware, keine Entscheidungen — siehe
`PRUEFEN-AUF-DEM-PI.md`.
