# Pflichtenheft Etappe A — Fundament

**Grundlage:** `docs/lastenheft-minecraft-server.md`, Fassung 0.2, Befunde B1–B7
**Branch:** `etappe-a-fundament`
**Datum:** 28.08.2026
**Stand:** umgesetzt am 28.08.2026, **auf echter Hardware abgenommen am
29.08.2026** (A-P1 bis A-P6 in `PRUEFEN-AUF-DEM-PI.md`). Dabei kamen vier
Befunde heraus, alle behoben: `deploy.sh` hängte geänderte
`[Install]`-Abschnitte nicht um (der Hauptschalter wäre nach dem nächsten
Neustart wirkungslos gewesen), der Backup-Timer wurde aktiviert, aber nicht
gestartet, `install.sh --standard` war ohne Terminal unbenutzbar
(`sudo -v`), und `server-port` fehlte in den `INSTANZ_SCHLUESSEL`.
A-P6 ist auf der Referenz-Installation nur eingeschränkt aussagekräftig:
Dort heißt der Benutzer zufällig tatsächlich `pi`, ein hartkodierter und
ein korrekt ermittelter Name sehen also gleich aus. Das prüft der
Container-Abnahmetest.

> Das Lastenheft sagt WAS. Dieses Dokument sagt WIE — auf Dateiebene.
> Ziel der Etappe: Das Repository ist auf einem **fremden** Pi mit **beliebigem
> Benutzernamen** lauffähig, enthält nichts Instanzspezifisches mehr und lässt
> sich vollständig abschalten.

---

## 0. Was die Bestandsaufnahme ergeben hat

Drei Erkenntnisse, die den Plan gegenüber dem Lastenheft verändern:

**0.1 — Die Git-Historie ist sauber.** 68 Commits geprüft: kein Token, kein
Schlüssel, kein Passwort. Der Commit `4339225` („DuckDNS: Token aus dem
versionierten Skript herausnehmen") hat die *Struktur* geändert — den Token in
eine `.env` ausgelagert — und keinen echten Wert entfernt. Auch alle drei
historischen Fassungen von `tools/duckdns.sh` sind wertfrei.
**Folge: B3 braucht keine Historien-Umschreibung.** Kein `filter-repo`, kein
Force-Push, kein Bruch für bestehende Klone. Nur ein Scrub im Arbeitsbaum.

**0.2 — B1 und B2 sind derselbe Fix.** Die `.service`-Dateien sind bereits
Vorlagen: `install.sh:267`, `install-admin.sh:153` und `deploy.sh:187` ersetzen
darin `/home/pi/mcs` → `${MC_DIR}` und `User=pi` → `User=${MCS_USER}`. Der
Mechanismus stimmt also schon. Er läuft nur ins Leere, weil seine Eingabewerte
aus `mcs.conf` kommen — und dort steht fest `pi` und `/home/pi/mcs`.
**Folge:** Es genügt, `mcs.conf` zur *erzeugten* Datei zu machen. Damit fallen
B1 und B2 gemeinsam.

**0.3 — `deploy.sh` überschreibt die Live-Konfiguration.** Zeile 131 kopiert
`$REPO_DIR/mcs.conf` nach `$MC_DIR/mcs.conf`. Heute fällt das nicht auf, weil
beide Fassungen gleich sind. Sobald `mcs.conf` benutzereigene Werte enthält,
verliert jeder `./deploy.sh`-Lauf die Einstellungen des Nutzers.

Der ursprünglich genannte Umfang „76 Vorkommen in 17 Dateien" relativiert sich
damit: 29 davon sind Rückfallwerte der Form `${MCS_X:-/home/pi/...}`, 24 stehen
im Container-Test (der bewusst einen Benutzer `pi` anlegt), 8 sind
`os.getenv`-Vorgaben. **Wirklich blockierend sind 13 Zeilen in `mcs.conf` und
die Vorgaben in `app.py`.**

---

## 1. Arbeitspakete

### A1 — VillagerTalk entfernen (Befund B7)

**Dateien:** `server/plugins.txt`

Der gesamte Kommentarblock zu VillagerTalk entfällt, einschließlich der
Erwähnung des systemd-Drop-ins `villagertalk-key.conf` und des
Groq-API-Schlüssels. Anschließend im ganzen Repository gegenprüfen:
`grep -ri villagertalk` und `grep -ri groq` müssen leer sein.

*Risiko: keins. Reiner Textlöschung.*

### A2 — Instanzdaten entfernen (Befund B3)

**Dateien:** `README.md`, `mcs.conf`, `server/server.properties`

| Was | Ist | Soll |
|---|---|---|
| Port im README-Kasten | 25570 | Kasten entfällt ersatzlos |
| Weltname im README-Kasten | instanzspezifisch | Kasten entfällt ersatzlos |
| `MCS_REPO_DIR` | `/home/pi/PiCraft` | wird in A3 erzeugt |
| `level-name` in der Vorlage | prüfen | `world` |
| `motd` in der Vorlage | prüfen | neutral |
| `server-port` in der Vorlage | prüfen | `25565` |

Keine Historien-Umschreibung (siehe 0.1).

*Risiko: gering. Die Vorlage `server/server.properties` wird bei bestehenden
Installationen ohnehin nie über die Live-Fassung kopiert.*

### A3 — `mcs.conf` wird erzeugt statt versioniert (Befunde B1 + B2)

Das Kernstück der Etappe.

**Neu:** `mcs.conf.beispiel` — dokumentierte Vorlage mit neutralen Werten
(`__MCS_USER__`, `__MCS_DIR__` als Platzhalter). Sie wird nie eingelesen,
sondern dient als Vorlage und Dokumentation.

**Entfällt aus der Versionierung:** `mcs.conf` (`git rm --cached`, Eintrag in
`.gitignore`). Auf bestehenden Installationen bleibt die Datei liegen.

**`install.sh`:**
1. Benutzer und Heimatverzeichnis ermitteln: `MCS_USER="$(id -un)"`,
   Basis `"$HOME"`. Nicht mehr aus `mcs.conf` lesen.
2. Installationsort erfragen, Vorschlag `$HOME/mcs`.
3. `mcs.conf` aus `mcs.conf.beispiel` erzeugen, Platzhalter ersetzen, nach
   `$MCS_DIR/mcs.conf` schreiben — **nur wenn sie dort noch nicht existiert.**
   Eine vorhandene Datei wird nie überschrieben; Abweichungen werden gemeldet.
4. `MCS_REPO_DIR` auf den tatsächlichen `$REPO_DIR` setzen.

**`deploy.sh`:** Zeile 131 entfällt. Statt die Konfiguration auszurollen, wird
sie nur noch **verglichen und gemeldet** — wie es mit `server.properties` schon
gehandhabt wird. Der Kommentarkopf ab Zeile 12 ist entsprechend zu berichtigen:
`mcs.conf` gehört ab jetzt dem Pi, nicht dem Repository.

**`admin_ui/app.py`:** Die `os.getenv`-Vorgaben mit `/home/pi/...` dürfen nicht
stillschweigend greifen. Fehlt `mcs.conf`, soll die Oberfläche das **melden**
statt auf ein Verzeichnis zu zeigen, das es nicht gibt. Die drei
Pfadnennungen in den Kommentaren (Zeilen 22, 47, 714) werden allgemein
formuliert.

*Risiko: mittel.* Bestehende Installationen müssen weiterlaufen. Absicherung:
Die erzeugte `mcs.conf` ist bei einem `pi`-Benutzer mit Standardpfaden
zeichengleich mit der bisherigen. Der Container-Test prüft genau das.

### A4 — `mcs an` / `mcs aus` (Befund B4)

Das lokale Skript auf dem Pi ist nicht mehr auffindbar und wird **nicht
nachgebaut, sondern ersetzt.** Die alte Lösung kommentierte eine Zeile in einer
fremden Crontab aus; die neue benutzt systemd so, wie es gedacht ist.

**Neue Dateien:**

| Datei | Zweck |
|---|---|
| `server/mcs.target` | bündelt alles. `[Install] WantedBy=multi-user.target` |
| `backup/mcs-backup.service` | `Type=oneshot`, ruft das Backup-Skript mit `nice -n 15` |
| `backup/mcs-backup.timer` | `OnCalendar=*-*-* 04:00:00`, `Persistent=true`, `RandomizedDelaySec=300` |

**Geändert:** In `minecraft.service`, `mcs-admin.service` und
`mcs-playerlog.service` je:
- `[Unit]` bekommt `PartOf=mcs.target` — damit ein Stopp des Targets
  durchschlägt.
- `[Install] WantedBy=` wird von `multi-user.target` auf **`mcs.target`**
  umgestellt. Bleiben sie an `multi-user.target` hängen, starten sie beim
  Booten trotz abgeschaltetem Target — genau der Fehler, den die Funktion
  vermeiden soll.

**Verhalten:**

| Befehl | Wirkung |
|---|---|
| `mcs an` | `systemctl enable --now mcs.target` |
| `mcs aus` | `systemctl disable --now mcs.target` |
| `mcs start\|stop\|restart` | unverändert nur `minecraft.service` |

**Drei Punkte, die leicht übersehen werden:**

1. **`mcs start` muss sich weigern**, solange das Target abgeschaltet ist —
   sonst umgeht man den Aus-Zustand versehentlich. Meldung statt stillem Start.
2. **Die Backup-Altersgrenze muss den Zustand kennen.** `mcs status` und die
   Weboberfläche prüfen `systemctl is-enabled mcs.target` und unterdrücken die
   48-Stunden-Warnung, wenn ausgeschaltet ist. (Offener Punkt aus dem
   Design-Dokument vom 2026-08-26, bis heute unerledigt.)
3. **Der alte Cronjob muss weg**, wenn der Timer kommt — sonst läuft das Backup
   zweimal. `install.sh` entfernt die Zeile mit `minecraft-backup.sh` aus der
   Crontab und meldet das.

*Risiko: mittel bis hoch.* Falsch gesetzte `[Install]`-Abschnitte führen dazu,
dass der Server nach einem Neustart nicht mehr hochkommt. Der Container-Test
muss einen Neustart-Zyklus abdecken.

### A5 — Portkonflikt 8080 (Befund B6)

**Dateien:** `install.sh` (Vorprüfung), `install-admin.sh`

Vor dem Einrichten der Weboberfläche prüfen, ob auf 8080 schon etwas lauscht
(`ss -ltn`). Wenn ja: melden, wer, und einen Ausweichport anbieten. Pl3xMap ist
der wahrscheinliche Kandidat und wird namentlich genannt.

*Risiko: gering.*

### A6 — GitHub Actions (Befund B5)

**Neu:** `.github/workflows/pruefung.yml`

Bei jedem Push und Pull Request: `make` (Shell-Syntax, Python-Syntax,
Konfigurationsformat, shellcheck). Der Container-Abnahmetest bleibt zunächst
manuell — er lädt Paper herunter und braucht mehrere Minuten.

*Risiko: keins.*

### A7 — CLAUDE.md (neu, nicht im Lastenheft)

Im Repository gibt es keine `CLAUDE.md`. Die Projektregeln — Deutsch,
laienverständliche Kommentare, `mcs.conf` als einzige Quelle, ein
Minecraft-Versionswechsel ist endgültig, `make` vor jedem Commit — stehen
nirgends maschinenlesbar. Eine knappe `CLAUDE.md` (unter 50 Zeilen) schließt
die Lücke.

*Risiko: keins.*

---

## 2. Reihenfolge

```
A1 ─┐
A2 ─┤ unabhängig, beliebige Reihenfolge
A6 ─┤
A7 ─┘
     ↓
A3   (Grundlage für alles Weitere: erzeugte mcs.conf)
     ↓
A4   (braucht die erzeugten Pfade aus A3)
     ↓
A5   (setzt auf der neuen Vorprüfung aus A3 auf)
```

---

## 3. Abnahme der Etappe — Ergebnis

Durchgeführt am 28.08.2026. Der Container-Abnahmetest lief in einem
ARM64-Debian-Container mit dem Benutzer **`mcstester`** — bewusst nicht `pi`.

| # | Kriterium | Ergebnis |
|---|---|---|
| 1 | `make` ohne Beanstandung | **ok** — Shell, Python, Konfigurationsformat, shellcheck |
| 2 | `grep -ri "villagertalk\|groq"` leer | **ok** |
| 3 | `mcs.conf` nicht versioniert | **ok** — wird jetzt von `make` dauerhaft geprüft |
| 4 | Container-Test mit fremdem Benutzer | **ok** — Server nach 21 s oben, `Done (11.096s)` |
| 5 | Zweiter Lauf lässt `mcs.conf` unangetastet | **ok** — 58 Weltdateien vorher wie nachher, Prüfmarke überlebt |
| 6 | `deploy.sh` überschreibt `mcs.conf` nicht | **ok** — eigener Wert `MCS_BACKUP_BEHALTEN=99` überlebt |
| 7 | `mcs aus` schaltet alles ab, überlebt Neustart | **offen** — braucht einen echten Pi (im Container läuft kein systemd als PID 1) |
| 8 | `mcs an` bringt alles zurück | **offen** — dito |
| 9 | Keine Backup-Warnung bei abgeschaltetem Target | **offen** — dito |
| 10 | Crontab ohne `minecraft-backup.sh` | **ok** — 0 Einträge |

Statisch geprüft, was der Container nicht ausführen kann: `systemd-analyze
verify` beanstandet keine der fünf Einheiten, und die Verdrahtung
(`PartOf=mcs.target` **und** `WantedBy=mcs.target` bei allen drei Diensten plus
Timer) ist im Testprotokoll sichtbar.

### Was der Test zusätzlich gefunden hat

Zwei Fehler, die nicht im ursprünglichen Plan standen:

**F1 — SIGPIPE beim Erzeugen des Admin-Passworts** (vorbestehend, in
`install-admin.sh`). Die Zeile
`PASSWORT="$(tr -dc 'A-Za-z0-9' </dev/urandom | head -c 20)"` scheitert, sobald
`head` die Pipe schließt, bevor `tr` fertig geschrieben hat: `tr` bekommt
SIGPIPE und endet mit 141, unter `set -o pipefail` gilt die ganze Pipeline als
gescheitert, und `set -e` bricht ab. Ob es passiert, hängt an der Zeitplanung —
mal läuft es durch, mal nicht. Genau die Sorte Fehler, die man ohne Test nie
findet.

Der Fehler war schon vorher da, aber unsichtbar: Die alte Fassung starb bereits
vorher an `mkdir /home/pi` (Befund B1). Erst der behobene B1 hat ihn freigelegt.
Behoben durch Lesen einer *endlichen* Menge (`head -c 512 /dev/urandom | tr …`)
und anschließendes Kürzen in der Shell.

**F2 — `MCS_USER="${MCS_USER:-pi}"` in `install-admin.sh`** (Rest von B1).
Beim direkten Aufruf von `./install-admin.sh` hätte das eine sudoers-Regel und
ein `User=` für einen Benutzer `pi` geschrieben, den es nicht gibt. Behoben.

Beides ist im Abnahmetest jetzt dauerhaft abgedeckt.

