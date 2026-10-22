# Pflichtenheft Etappe D — Politur

**Grundlage:** `docs/lastenheft-minecraft-server.md`, Fassung 0.6,
Abschnitte 5.1, 5.3, 5.4, 5.6, 5.9, Entscheidungen 11 und 12, offener
Punkt O4
**Branch:** `etappe-d-politur`
**Datum:** 30.08.2026
**Stand:** D1 bis D7 umgesetzt am 30.08.2026, im Container abgenommen
(`tests/abnahme.sh` ohne Beanstandung, beide Installationsläufe mit
Rückgabewert 0). Was nur auf echter Hardware und an einem echten Anschluss
nachweisbar ist, steht als **D-P1 bis D-P9** in `PRUEFEN-AUF-DEM-PI.md`.

> Ziel der Etappe: Aus einem Server, der auf **diesem** Pi läuft, wird ein
> Projekt, das auf **einem beliebigen** Pi ankommt. Etappe D fügt keine
> Seite und keine Funktion hinzu, die man sich beim Spielen wünscht —
> sie schließt die Lücken, die man erst bemerkt, wenn man das Repository
> jemand anderem in die Hand drückt.
>
> Drei davon sind ernst: Wer auf einer SD-Karte installiert, bekommt es
> heute nicht gesagt. Wer einen DS-Lite-Anschluss hat, kann den Port
> freigeben, so oft er will, und wird nie erfahren, warum niemand
> hereinkommt. Und ein fehlgeschlagenes Backup ist weiterhin nur dann
> sichtbar, wenn man von sich aus nachsieht — genau der Zustand, der
> 2026 zwei Monate lang unbemerkt blieb.

---

## 0. Was diese Etappe voraussetzt und was sie nicht messen kann

Etappe C konnte fast alles im Container messen. Etappe D kann das an drei
Stellen grundsätzlich nicht, und das ist keine Nachlässigkeit, sondern die
Natur der Sache:

| Was | Warum der Container es nicht zeigt |
|---|---|
| SD-Karte oder SSD | Ein Container sieht das Dateisystem des Wirts. Die Erkennung lässt sich nur auf echter Hardware bestätigen. |
| DS-Lite, Portfreigabe, öffentliche Adresse | Hängt am Anschluss, nicht am Rechner. |
| deSEC und DuckDNS | Brauchen ein echtes Konto und einen echten Token. |
| `unattended-upgrades` | Braucht ein echtes Debian mit systemd als PID 1. |

**Daraus folgt für den Bau:** Jede dieser Stellen muss so gebaut sein, dass
sie *ohne* das jeweilige Gegenüber sauber und ehrlich ausgeht — also nicht
abstürzt, nicht schweigt und nicht rät, sondern sagt: „Das lässt sich hier
nicht feststellen." Die zugehörigen Prüfpunkte kommen in
`PRUEFEN-AUF-DEM-PI.md`.

---

## 1. Entscheidungen, die diese Etappe trifft

### E9 — Benachrichtigungsweg: **ntfy** (Lastenheft O4)

Der offene Punkt O4 fragt nach dem Weg für die Benachrichtigung bei
Backup-Fehlschlag. Entschieden: **ntfy** (`https://ntfy.sh`, oder eine
eigene Instanz).

| | ntfy | Telegram | E-Mail |
|---|---|---|---|
| Konto nötig | **nein** | ja | ja |
| Einrichtung | Themenname ausdenken, App abonnieren | Bot bei BotFather anlegen, Chat-ID herausfinden | SMTP-Server, Absender, Passwort |
| Senden | ein `curl` | ein `curl` | `msmtp` o. ä. installieren |
| Selbst betreibbar | ja | nein | ja |
| Zeilen Code | ~15 | ~15 | ~60 plus Paket |

ntfy gewinnt bei genau der Frage, die hier zählt: Was muss jemand tun, der
das Repository frisch installiert hat und in zwei Minuten fertig sein will?
Bei ntfy sind es zwei Schritte (App installieren, Thema abonnieren), bei
Telegram fünf, bei E-Mail mehr.

**Der Haken, der dazugesagt werden muss:** Bei `ntfy.sh` ist der
**Themenname das ganze Geheimnis**. Wer ihn errät, liest mit. Deshalb
schlägt die Oberfläche keinen Namen wie `mcs-backup` vor, sondern einen mit
zwölf zufälligen Zeichen, und schreibt genau diesen Satz daneben.

### E10 — Der Erreichbarkeitstest ist **ein Skript**, keine zwei Umsetzungen

`tools/erreichbarkeit.sh` beantwortet die Frage einmal, für alle drei
Aufrufer: `install.sh` am Ende, `mcs erreichbarkeit` im Terminal und die
Weboberfläche über `--json`.

Die Alternative — die Logik in Bash für die Installation und ein zweites
Mal in Python für die Oberfläche — wäre der sichere Weg zu zwei Antworten
auf dieselbe Frage. Genau das ist bei `stats/` (Korrektur K8) schon einmal
schiefgegangen, nur an anderer Stelle.

### E11 — Der Test nennt **Ursachen, nicht Vermutungen**

Der Lastenheft-Satz lautet: *„Dein Port ist von außen nicht erreichbar, und
zwar weil dein Anschluss DS-Lite benutzt."* Das ist der Anspruch. Er lässt
sich zu großen Teilen einlösen, aber nicht vollständig, und die Lücke wird
benannt statt überspielt:

| Beobachtung | Aussage |
|---|---|
| Von außen gar keine IPv4-Adresse zu bekommen, aber globales IPv6 vorhanden | **gesichert**: Der Anschluss hat keine öffentliche IPv4. Keine Portfreigabe der Welt hilft. |
| Öffentliche IPv4 liegt in `100.64.0.0/10` | **gesichert**: Anbieter-NAT (CGNAT). Portfreigabe wirkungslos. |
| IPv6 von außen erreichbar, IPv4 nicht | **starkes Indiz** für DS-Lite — und zugleich die praktisch wichtigste Aussage: Mitspieler mit IPv6 kommen bereits herein. |
| IPv4 sieht öffentlich aus, ist aber zu | **nicht entscheidbar** aus der Ferne: fehlende Portfreigabe *oder* DS-Lite (dort meldet der Echo-Dienst die Adresse des Anbieter-Gateways, und die sieht öffentlich aus). Der Test sagt beide Möglichkeiten und **wo im Router man sie unterscheidet**. |

Ehrlich statt bequem (Leitsatz 5): Ein Test, der in Fall 4 „DS-Lite" behauptet,
liegt in der Mehrzahl der Fälle falsch und schickt Leute auf die Suche nach
einem Problem, das sie nicht haben.

### E12 — Zwei fremde Dienste, beide benannt, beide nur auf Knopfdruck

Der Test verlässt den Pi. Das ist unvermeidbar — „bin ich von außen
erreichbar" lässt sich von innen nicht beantworten. Also:

| Dienst | Wofür | Was er erfährt |
|---|---|---|
| `checkipv4.dedyn.io` / `checkipv6.dedyn.io` | die eigene öffentliche Adresse | dass jemand von dieser Adresse gefragt hat |
| `api.mcsrvstat.us` | verbindet sich von außen mit dem Server | Adresse und Port des Servers, MOTD, Spielerzahl |

Die Echo-Dienste sind die von **deSEC** — also von dem Anbieter, den das
Lastenheft ohnehin empfiehlt (Entscheidung 11). Ein Dienst weniger im Spiel.

`api.mcsrvstat.us` beantwortet nicht „ist Port 25565 offen", sondern „läuft
dort ein Minecraft-Server, mit dem ich sprechen kann" — die Frage, die
eigentlich interessiert. Nebenbei prüft er den SRV-Eintrag mit.

**Nie automatisch.** Die Seite ruft beim Aufbau nichts nach außen; es
braucht einen Klick, und daneben steht, wer gefragt wird.

### E13 — DNS: der Timer läuft immer, das Skript schweigt, wenn nichts eingerichtet ist

`mcs-dns.timer` gehört wie alles andere zu `mcs.target` und wird bei der
Installation mit aktiviert. Ist kein Anbieter eingetragen, endet
`dns-update.sh` sofort mit Status 0 und ohne Ausgabe.

Der Grund ist praktisch: Sonst müsste die Weboberfläche einen Timer
aktivieren können, also `systemctl enable` dürfen — eine sudo-Regel mehr,
und zwar eine weite. So schreibt die Oberfläche nur zwei Dateien im eigenen
Verzeichnis, und die sudo-Regeln bleiben, wo sie sind.

### E14 — Der DNS-Token liegt **nicht** in `mcs.conf`

`mcs.conf` wird von Shell, Python *und* systemd gelesen und hat entsprechend
offene Rechte. Ein API-Token gehört dort nicht hinein. Er kommt nach
`<Installationsort>/dns.env` mit `chmod 600` — dasselbe Muster, das
`duckdns.env` seit 2026-08-28 benutzt, und aus demselben Grund.

In `mcs.conf` stehen nur Anbieter, Name und ob ein SRV-Eintrag gewünscht ist.

### E15 — Für Pi 4 andere Vorschläge, und dazugesagt, dass sie **geschätzt** sind

Das Lastenheft verlangt „bei Pi 4 andere Vorgabewerte" (5.1). Gemessen ist
aber nur der Pi 5 (`docs/optimierung-2026-07-27.md`), und Leitsatz „nur mit
Messung" gilt.

Aufgelöst wird das so: Die **gemessenen** Werte bleiben die Vorgabe für den
Pi 5. Für den Pi 4 schlägt der Assistent Sichtweite 10 statt 16 und
Simulationsdistanz 6 statt 10 vor — und schreibt in denselben Absatz, dass
diese Zahlen aus dem Leistungsunterschied abgeleitet und **nicht auf einem
Pi 4 nachgemessen** sind. Wer es besser weiß, hebt sie an.

Für Pi 3 und Zero gibt es keine Vorgabewerte, sondern eine Warnung — und
die Installation läuft trotzdem weiter, wenn man es will.

---

## 2. Arbeitspakete

### D1 — Hardware und Speichermedium erkennen

**Neu:** `lib/hardware.sh` — eingebunden von `install.sh` und von
`tools/mcs`.

Ermittelt und meldet **vor** den Fragen des Assistenten (Lastenheft 5.1):

| Prüfung | Quelle | Folge |
|---|---|---|
| Pi-Modell | `/proc/device-tree/model` | Pi 5: nichts. Pi 4: andere Vorschläge (E15). Pi 3/Zero: Warnung. Kein Pi: nur melden. |
| 64-Bit | `uname -m` = `aarch64` | 32-Bit: deutliche Warnung — Java-Heap über 3 GB ist dort nicht möglich. |
| Arbeitsspeicher | `/proc/meminfo` | Heap-Empfehlung (bleibt bei drei Achteln, gemessen 2026-07-27). |
| **Speichermedium** | `findmnt` → `lsblk -no pkname` → `/sys/block/…` | SD-Karte: **die deutlichste Warnung im ganzen Projekt**. |
| Port der Oberfläche | `ss -ltn` | bleibt in `install-admin.sh` (Befund B6), wird hier nur mitgemeldet. |

**Zum Speichermedium, weil hier das Naheliegende falsch ist:**

- `/sys/block/<gerät>/queue/rotational` unterscheidet zuverlässig HDD von
  SSD — **aber nicht über USB**. Viele USB-SATA-Brücken reichen die Angabe
  nicht durch und melden pauschal `1`. Eine SSD im USB-Gehäuse — auf dem Pi
  der Normalfall — würde damit als Festplatte gemeldet. Also: über USB wird
  **nicht** behauptet, was dahinter steckt.
- `mmcblk*` heißt nicht automatisch SD-Karte. Auf Compute-Modulen ist
  derselbe Gerätename der fest verlötete eMMC-Speicher, und der ist deutlich
  besser als eine SD-Karte. Unterschieden wird über
  `/sys/block/<gerät>/device/type` (`SD` gegen `MMC`).
- Geprüft wird das Dateisystem, auf dem das **Serververzeichnis** liegt —
  und zusätzlich das des Backup-Verzeichnisses, falls es ein anderes ist.

**Auch als `mcs hardware`**, damit man es nach der Installation
nachschlagen kann, ohne sie zu wiederholen.

### D2 — `unattended-upgrades`

**`install.sh`**, neue Frage im Assistenten (Vorschlag: ja).

Was passiert bei „ja":

1. `unattended-upgrades` installieren.
2. `/etc/apt/apt.conf.d/20auto-upgrades` schreiben — ausgeschrieben und
   kommentiert, nicht über `dpkg-reconfigure`, damit man nachlesen kann,
   was eingestellt ist.
3. **Kein automatischer Neustart.** Ein Server, der sich um sechs Uhr
   früh selbst neu startet, während jemand baut, ist schlimmer als ein
   Kernel-Update, das eine Woche wartet. Stattdessen legt
   `unattended-upgrades` bei Bedarf `/var/run/reboot-required` an — und
   **das** meldet die Startseite der Oberfläche.

Das ist der Einzeiler mit der größten Wirkung pro Zeile im Projekt
(Lastenheft 5.3) — aber nur, wenn er nicht mitten im Spiel neu startet.

### D3 — Benachrichtigung bei Backup-Fehlschlag

**Neu:** `tools/benachrichtigung.sh`

```
benachrichtigung.sh "Titel" "Text" [normal|hoch]
benachrichtigung.sh --test
```

- Einstellungen aus `mcs.conf`: `MCS_NTFY_SERVER`, `MCS_NTFY_THEMA`
  (leer = aus). Ein optionaler Zugangstoken für eigene Instanzen liegt in
  `ntfy.env` (`chmod 600`), nicht in `mcs.conf` (siehe E14).
- Ist nichts eingetragen, endet das Skript mit **Status 78** (`EX_CONFIG`)
  und ohne Ausgabe. Die Aufrufer werten das als „nicht eingerichtet", nicht
  als Fehler.

**Eingehängt wird an genau zwei Stellen in `backup/minecraft-backup.sh`:**

1. `fehler_merken()` — es ging schief.
2. Dort, wo `.letzter-fehler` nach einem geprüften Archiv gelöscht wird —
   **Entwarnung**. Ohne diese zweite Nachricht weiß man nie, ob ein
   gemeldetes Problem noch besteht. Sie wird nur geschickt, wenn vorher
   wirklich ein Merkzettel dalag; sonst käme jede Nacht eine Nachricht.

**Bedienung:** auf der Backupseite (Lastenheft 5.7.4, Seite 4), mit
Themenvorschlag, dem Satz über den Themennamen und einem Knopf
„Testnachricht senden". Der Knopf ist wichtiger, als er aussieht: Eine
Benachrichtigung, die man nie ausprobiert hat, ist keine.

### D4 — Erreichbarkeitstest

**Neu:** `tools/erreichbarkeit.sh` (siehe E10, E11, E12)

Ermittelt der Reihe nach, jeweils ohne den nächsten Schritt vorauszusetzen:

1. **Läuft der Server überhaupt?** (`systemctl is-active`) — wenn nicht,
   endet der Test hier. Alles andere wäre eine Fehlersuche am falschen Ort.
2. **Lauscht lokal etwas auf dem Spielport?** (`ss -ltn`)
3. **Lokale Adressen** (LAN-IPv4, globales IPv6) — `ip addr`, ohne Netz.
4. **Öffentliche IPv4 und IPv6** — die beiden `checkip`-Dienste von deSEC.
5. **Von außen erreichbar?** — `api.mcsrvstat.us`, **getrennt für IPv4 und
   IPv6**. Getrennt, weil genau die Differenz die Aussage trägt (E11).
6. **Urteil** mit Begründung und konkreten nächsten Schritten.

Ausgabe wahlweise als Text (`install.sh`, `mcs erreichbarkeit`) oder als
JSON (`--json`, für die Oberfläche). Ohne Netz oder ohne `curl` liefert er
ein vollständiges Ergebnis mit „nicht feststellbar" statt eines Fehlers.

**Aufrufer:**

- `install.sh`, am Ende, nach der Zusammenfassung.
- `mcs erreichbarkeit`
- Weboberfläche, Konfigurationsseite, Abschnitt „Von außen erreichbar" —
  auf Knopfdruck.

### D5 — DNS-Modul

**Neu:** `tools/dns-update.sh`, `server/mcs-dns.service`,
`server/mcs-dns.timer`
**Entfällt:** `tools/duckdns.sh` (geht in `dns-update.sh` auf)

| Anbieter | A/AAAA | SRV | Warum |
|---|---|---|---|
| **deSEC** | ja | **ja** | Empfehlung (Entscheidung 11): kostenlos, DNSSEC, deutscher gemeinnütziger Verein, echte REST-API |
| DuckDNS | ja | nein | bleibt möglich, kann keine SRV-Einträge |

- **Beide Adressfamilien.** Das Skript ermittelt öffentliche IPv4 *und*
  IPv6 und meldet beide. Bei DS-Lite ist der AAAA-Eintrag der einzige, der
  etwas nützt — ihn wegzulassen wäre ausgerechnet dort fatal, wo es darauf
  ankommt. Fehlt eine der beiden, wird der zugehörige Eintrag **gelöscht**
  statt stehen gelassen: Ein veralteter AAAA-Eintrag lässt Mitspieler in
  einen Verbindungsversuch laufen, der erst nach Zeitüberschreitung
  aufgibt.
- **SRV-Eintrag** (`_minecraft._tcp`) über die deSEC-REST-API, einmalig auf
  Knopfdruck, nicht aus dem Timer. Damit tippen Mitspieler
  `mc.beispiel.de` ohne Portangabe.
- **Kein Aufruf ohne Not:** Hat sich die Adresse seit dem letzten Lauf
  nicht geändert, wird nichts gesendet (Merkdatei). Anbieter mögen das,
  und es hält das Protokoll lesbar.

**Bedienung:** Konfigurationsseite, direkt beim Erreichbarkeitstest — die
beiden gehören zusammen: Der Test sagt, ob es geht, das DNS-Modul sorgt für
den Namen, unter dem es geht.

### D6 — README und Dokumentation

- **Ganz oben** (Lastenheft 5.9 und 5.1): Portfreigabe im Router und DNS.
  Heute steht dort beides nicht — wer die Anleitung von oben nach unten
  liest, hat am Ende einen laufenden Server, den niemand erreicht.
- Neue Abschnitte: Erreichbarkeit und DS-Lite, DNS einrichten,
  Benachrichtigungen, Speichermedium, automatische Sicherheitsupdates.
- `PRUEFEN-AUF-DEM-PI.md`: die Prüfpunkte D-P1 ff. für alles, was hier
  grundsätzlich nur auf echter Hardware und an einem echten Anschluss
  nachweisbar ist (siehe Abschnitt 0).
- `CLAUDE.md`: die neuen Fallen dazu.

### D7 — Aufräumen der obersten Ebene (Lastenheft 5.9)

Der letzte offene Punkt aus 5.9. Rein mechanisch, deshalb **zuletzt und in
einem eigenen Commit** — sonst versteckt sich die inhaltliche Arbeit der
Etappe in einer Umbenennung.

| Von | Nach |
|---|---|
| `lib/assistent.sh`, `lib/fragen.sh`, `lib/hardware.sh` | `lib/` |
| `admin/` | `admin/` |

**Auf dem Pi ändert sich dadurch nichts:** Dort heißt das Verzeichnis der
Oberfläche seit jeher `admin` (`MCS_ADMIN_DIR=<Basis>/admin`). Umbenannt
wird nur die Quelle im Repository — womit die Namen endlich übereinstimmen.

Mitzuziehen: `Makefile`, `install.sh`, `install-admin.sh`, `deploy.sh`,
`tests/abnahme-im-container.sh`, `tests/oberflaeche-ansehen.sh`, README
(Verzeichnisstruktur), Lastenheft.

**Die Pflichtenhefte A, B und C bleiben unangetastet.** Dort steht weiter
`admin_ui/` — und das ist richtig so: Sie beschreiben, wie es zu ihrer Zeit
war. Ein Dokument nachträglich so umzuschreiben, als hätte es nie anders
ausgesehen, ist dieselbe Sorte Geschichtsklitterung wie eine spurlos
überschriebene Annahme (siehe die Korrekturen K1 bis K8 im Lastenheft).

### D8 — Was beim Durchsehen noch aufgefallen ist

Nicht geplant, aber beim Abarbeiten der Etappe zutage getreten. Alles drei
sind offene Zeilen aus dem Lastenheft, die frühere Etappen übersehen haben —
und Etappe D ist die letzte, in der sie noch geschlossen werden können.

| | Was | Woher |
|---|---|---|
| a | **Das Archiv trägt seinen Namen erst nach der Prüfung.** `tar` schrieb direkt nach `backup_<zeit>.tar.gz`. Ein harter Abbruch (Stromausfall, OOM-Killer) hinterliess eine halbe Datei, die für die Rotation wie ein gültiges Backup aussah und in `mcs status` als „Backup von heute Nacht" gemeldet wurde. Also ein Backup, das es nicht gibt, das aber ein echtes verdrängt und dabei Entwarnung gibt. | Lastenheft 5.4, Punkt 5 |
| b | **Port 8080 wird in der Vorprüfung gemeldet**, nicht erst in Schritt 6. Wer den Konflikt erst dort erfährt, hat die Entscheidung über die Weboberfläche längst getroffen. | Lastenheft 5.1 |
| c | **Der Assistent versprach „vier erprobte Plugins".** Seit Korrektur K6 wird genau eines mitinstalliert. | Korrektur K6 |

Punkt (a) ist der gewichtigste: Er sitzt in dem Teilsystem, dessen Versagen
die teuerste Lehre dieses Projekts war — und er hätte dieselbe Sorte
stillen Ausfall erzeugt.

### D9 — Was Etappe D6 an Dokumentation übersehen hatte

Aufgefallen an einer Frage, die das README nicht beantwortet: *Wie komme ich
mit dem Handy über Tailscale auf die Oberfläche?* Die Antwort steht seit
Fassung 0.2 als Entscheidung 12 im Lastenheft — im README stand dazu kein
einziger Satz, nur ein Nebensatz über den dabei blockierten Kartenrahmen.

Beim Nachsehen kamen zwei weitere Zeilen aus Lastenheft 5.3 dazu, die
ebenfalls nirgends standen. Alle drei sind ausdrücklich *Dokumentation* und
keine Automatik — das ist keine Bequemlichkeit, sondern in jedem der drei
Fälle die richtige Grenze:

| Neuer Abschnitt im README | Warum kein Installationsschritt |
|---|---|
| **Zugriff über Tailscale** — beide Wege (direkte Tailscale-Adresse und Tailscale Serve), mit den drei Fallstricken | Tailscale ist ein fremder Dienst mit eigener Anmeldung. Ihn einzurichten ist eine Entscheidung. |
| **SSH per Schlüssel** | Steht so in der Anforderung: *dokumentiert, nicht erzwungen*. Wer sich beim Abschalten des Passwort-Logins vertippt, kommt nur noch mit Tastatur am Pi weiter. |
| **Weltkarte öffentlich erreichbar machen** | Es öffnet einen Port ins Internet. Nach `./install.sh` soll nicht ungefragt ein zweiter Webserver offenstehen. |

**Dazu eine Korrektur im Code.** Der Kommentar zur Ratenbegrenzung in
`admin/sicherheit.py` behauptete, Tailscale reiche die echte Adresse durch.
Das stimmt nur zur Hälfte — und die falsche Hälfte ist ausgerechnet der Weg,
den Entscheidung 12 empfiehlt:

| Weg | Was die Bremse sieht |
|---|---|
| direkt über die Tailscale-Adresse | die echte `100.x.y.z` des Handys — die Bremse wirkt je Gerät |
| über **Tailscale Serve** | `127.0.0.1`, denn Serve ist ein Proxy *auf dem Pi* — die Bremse trifft alle Geräte gemeinsam |

Behoben wird das **nicht** über `X-Forwarded-For`: Diesen Kopf darf man nur
glauben, wenn sicher ist, dass ein vertrauenswürdiger Proxy davorsteht. Wäre
die Oberfläche einmal direkt erreichbar, könnte sich jeder die Bremse mit
einer erfundenen Adresse wegschreiben — aus einem Schutz würde eine
Einladung. Bei einem einzigen Administrator ist die Folge überschaubar: Er
sperrt sich selbst für fünf Minuten aus. Das steht jetzt so im Kommentar und
im README.

### D10 — Die letzten drei Zeilen aus Lastenheft 5.1

Beim abschließenden Abgleich von Abschnitt 5 gegen den Code gefunden: drei
Sätze, die seit Fassung 0.2 dort stehen und nie umgesetzt wurden. Alle drei
in der Installation, alle drei klein — aber „alles in diesem Dokument ist
umgesetzt" ist ein Abnahmekriterium, und drei nicht umgesetzte Sätze sind
drei nicht umgesetzte Sätze.

| | Anforderung | Vorher | Jetzt |
|---|---|---|---|
| a | „Die Weboberfläche wird immer mitinstalliert, außer man gibt beim Aufruf ausdrücklich das Gegenteil an." | Nur die Frage im Assistenten. Wer `--standard` benutzte oder skriptete, hatte **keine** Möglichkeit, sie abzuwählen — der Schnellmodus nimmt überall die Empfehlung, und die lautet „ja". | `--ohne-oberflaeche`, und der Parameter schlägt jede Antwort. |
| b | „…und der Installationsort" (auch Entscheidung 6: *wird gefragt, Vorschlag `~/mcs`*) | Gar nicht gefragt; nur über die Umgebungsvariable `MCS_DIR` zu beeinflussen. | Erste Frage des Assistenten. |
| c | „Neu hinzu kommen Benutzer/Passwort für die Weboberfläche (mit dem Hinweis aus Entscheidung 10)" | Ein zufälliges wurde erzeugt und am Ende angezeigt. | Wird gefragt, Eingabetaste erzeugt weiterhin ein zufälliges — mit dem Hinweis aus Entscheidung 10 daneben. |

**Zu (b), weil die Reihenfolge hier zählt:** Die Frage steht **vor** der
Vorprüfung, nicht im Fragenblock. Die Vorprüfung misst den freien Platz auf
dem Zielverzeichnis; käme die Frage danach, prüfte sie den falschen
Datenträger — und das ist genau der Fall, der die Frage wertvoll macht: Wer
gerade die Warnung vor der SD-Karte gelesen hat (D1), will jetzt auf seine
SSD ausweichen. Gefragt wird nur, wenn es noch keine Installation gibt;
sonst wäre die Frage eine Falle, denn die Pfade einer bestehenden stehen in
ihrer `mcs.conf`.

**Zu (c):** Ein selbst gewähltes Passwort wird am Ende **nicht** noch einmal
ausgegeben. Der Nutzer kennt es; im Terminalverlauf hat es nichts verloren.
Weitergereicht wird es über die Umgebung, nicht als Aufrufparameter —
Parameter stehen in der Prozessliste, die jeder Benutzer des Systems lesen
kann.

---

## 3. Reihenfolge

Jedes Paket ist für sich lauffähig und wird einzeln committet.

1. **D1** Hardware — steht allein, betrifft nur die Installation.
2. **D2** `unattended-upgrades` — kleinster Eingriff, gleiche Baustelle wie D1.
3. **D3** Benachrichtigung — braucht nichts von D1/D2, schließt aber die
   älteste offene Wunde des Projekts. Deshalb früh.
4. **D4** Erreichbarkeitstest — liefert die Bausteine (öffentliche
   Adressen), die D5 braucht.
5. **D5** DNS — baut auf D4 auf.
6. **D6** Dokumentation — beschreibt, was D1–D5 gebaut haben.
7. **D7** Aufräumen — zuletzt, damit alles davor in seinen alten Pfaden
   committet ist und der Umzug ein eigener, lesbarer Schritt bleibt.
8. **D8** war nicht geplant und ist deshalb dort eingeflossen, wo es
   hingehörte: (a) und (c) beim jeweiligen Teilsystem, (b) bei D1.
9. **D9** kam nach D6 dazu — die Lücke fiel erst an einer Frage auf, die
   das README nicht beantworten konnte. Das ist der ehrlichste Prüfstein
   für Dokumentation, den es gibt.
10. **D10** zuletzt: der zeilenweise Abgleich von Lastenheft-Abschnitt 5
    gegen den Code. Drei Sätze waren nie umgesetzt — und keiner davon wäre
    im Betrieb je aufgefallen, weil an ihrer Stelle etwas Vernünftiges
    stand. Ein Abgleich findet so etwas, Benutzen nicht.

---

## 4. Abnahme der Etappe

**Im Repository:**

- `make` ohne Beanstandung, GitHub Actions grün.
- Container-Abnahmetest läuft durch, ergänzt um die neuen Punkte.
- Zweiter Lauf der Installation verändert nichts und bricht nichts.

**Was nur auf dem Pi geht** (kommt als D-P1 ff. in `PRUEFEN-AUF-DEM-PI.md`):

| # | Prüfung |
|---|---|
| D-P1 | `mcs hardware` nennt Modell, Arbeitsspeicher und Speichermedium richtig. |
| D-P2 | Auf einer SD-Karte erscheint die Warnung — notfalls mit einer SD-Karte im Slot nachgestellt. |
| D-P3 | `unattended-upgrades` ist eingerichtet und hat gelaufen (`/var/log/unattended-upgrades/`). |
| D-P4 | Eine Testnachricht kommt auf dem Handy an. |
| D-P5 | Ein absichtlich herbeigeführter Backup-Fehlschlag löst eine Nachricht aus — und der nächste erfolgreiche Lauf die Entwarnung. |
| D-P6 | `mcs erreichbarkeit` liefert an einem echten Anschluss ein Urteil, das stimmt. |
| D-P7 | DNS-Eintrag bei deSEC wird gesetzt und nach einem Adresswechsel nachgeführt. |
| D-P8 | SRV-Eintrag angelegt; ein Mitspieler verbindet sich ohne Portangabe. |
| D-P9 | Nach `mcs aus` läuft auch der DNS-Timer nicht mehr. |

Der Container prüft inzwischen die Abschnitte 5z (Zwischenname beim
Packen), 5a (eine tote Benachrichtigung kostet nie das Backup), 10b
(Einordnung des Anschlusses an nachgestellten Fällen), 10c (DNS-Adressen
und SRV-Eintrag mit einer curl-Attrappe) und 11 (Einordnung des
Datenträgers an einem nachgebauten `/sys`-Baum, alle acht Fälle).

**Für das Gesamtprojekt** (Lastenheft 7) bleibt danach offen, was mehrere
Tage Laufzeit oder fünf echte Spieler braucht.

---

## 5. Was Etappe D nicht umfasst

- **Kein playit.gg-Modul.** Es wird dokumentiert (Lastenheft 5.6), nicht
  mitinstalliert. Ein Tunnel-Dienst mit eigenem Agenten wäre ein Bauteil
  mehr, das dauerhaft mitläuft — und er hilft nur der Minderheit, bei der
  auch IPv6 nicht reicht.
- **Keine Benachrichtigung außer bei Backups.** „Server abgestürzt",
  „Platte voll", „Spieler beigetreten" sind naheliegend und alle drei ein
  eigener Wachhund. Der Backup-Fehlschlag ist der Fall mit belegter
  Vorgeschichte; der Rest wartet auf einen echten Bedarf.
- **Kein Tailscale-Modul.** Entscheidung 12 gilt, HTTPS läuft über
  Tailscale Serve — aber Tailscale einzurichten ist dokumentiert, nicht
  automatisiert. Es ist ein fremder Dienst mit eigenem Anmeldeverfahren.
