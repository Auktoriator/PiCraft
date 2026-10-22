# Pflichtenheft Etappe B — Schnittstelle

**Grundlage:** `docs/lastenheft-minecraft-server.md`, Fassung 0.2,
Entscheidungen 3 und 4, Korrektur K1
**Branch:** `etappe-b-schnittstelle`
**Datum:** 28.08.2026
**Stand:** umgesetzt am 28.08.2026, **auf echter Hardware abgenommen am
29.08.2026** (B-P2 bis B-P4 in `PRUEFEN-AUF-DEM-PI.md`). Korrektur K1 hat
sich dabei auf echter Hardware bestätigt: `ss -ltn` zeigt `*:25575`, RCON
bindet also wirklich an alle Netzwerkkarten, und die ausdrückliche
`DENY`-Regel steht für v4 und v6.
**Offen bleibt B-P1** — der Zugriffsversuch von einem zweiten Gerät. Und
die Reihenfolge der Prüfliste ist an dieser Stelle umgekehrt, wenn RCON auf
der Zielmaschine noch gar nicht eingerichtet ist: dann erst B-P2, dann
B-P1. Sonst misst man einen Port, den es nicht gibt.

> Ziel der Etappe: die **Datenbasis**, ohne die die neue Weboberfläche nicht
> gebaut werden kann. Sichtbar ändert sich dabei fast nichts — das ist
> Absicht. Etappe B liefert Antworten (RCON), Verlauf (Metriken) und Struktur
> (Paket), Etappe C baut darauf die Oberfläche.

---

## 0. Was die Messung ergeben hat

**RCON bindet an `0.0.0.0`, nicht an `127.0.0.1`** (Korrektur K1 im
Lastenheft). Gemessen mit Paper 26.2 Build 119 in einem ARM64-Container:

```
[INFO]: RCON running on 0.0.0.0:25575
LISTEN  *:25575  users:(("java",...))
```

Einen Schlüssel `rcon.ip` gibt es nicht. Die Abschottung muss deshalb die
Firewall leisten. Das verschiebt Arbeit von B1 nach B2 und macht die Firewall
von einer Annehmlichkeit zu einem Sicherheitsbestandteil.

---

## 1. Arbeitspakete

### B1 — RCON-Client (ohne Fremdbibliothek)

**Neu:** `admin/rcon.py` (rund 130 Zeilen)

Das Protokoll ist bewusst klein: längenpräfixierte Pakete, Typ 3 =
Anmelden, Typ 2 = Befehl, Typ 0 = Antwort. Eine Fremdbibliothek dafür
einzubinden wäre mehr Abhängigkeit als Gewinn.

Zu beachten:

- **Antworten über 4096 Byte kommen in mehreren Paketen.** Wer nur eines
  liest, bekommt bei `whitelist list` mit vielen Namen eine abgeschnittene
  Antwort — und merkt es nicht. Gelöst über ein Folgepaket mit ungültigem Typ,
  dessen Echo das Ende markiert (das übliche Verfahren).
- **Zeitüberschreitung auf jeder Leseoperation**, sonst hängt die
  Weboberfläche, wenn der Server gerade nicht antwortet.
- **Ein fehlgeschlagenes Anmelden ist nicht von einem Netzfehler zu
  unterscheiden**, wenn man nur auf Ausnahmen schaut: Der Server schliesst
  bei falschem Passwort einfach die Verbindung. Das muss als solches gemeldet
  werden.
- **Nur eine Verbindung zur Zeit.** RCON läuft im Hauptthread des Servers;
  parallele Aufrufe aus mehreren Browserfenstern würden ihn ausbremsen.
  Also eine Sperre und eine kurz gehaltene Verbindung.

### B2 — RCON einrichten und absichern

**`install.sh` / `server/server.properties`:**

| Schlüssel | Wert |
|---|---|
| `enable-rcon` | `true` |
| `rcon.port` | `25575` |
| `rcon.password` | zufällig, 24 Zeichen, bei der Installation erzeugt |
| `broadcast-rcon-to-ops` | `false` — sonst sieht jeder OP im Chat jeden Befehl der Weboberfläche |

Das Passwort steht zwangsläufig in `server.properties` (Minecraft liest es
nur von dort). Die Datei bekommt deshalb `chmod 600`.

**Firewall (`firewall_einrichten`):**

- ausdrückliche Sperr-Regel für den RCON-Port
- **Wird die Firewall abgelehnt, deutlich warnen** und anbieten, RCON
  wegzulassen. Ohne Firewall steht der Port im lokalen Netz offen.

**`mcs`:** ein Unterbefehl `mcs rcon <befehl>`, der die Antwort **anzeigt** —
im Unterschied zu `mcs cmd`, das nur sendet.

### B3 — Metrik-Sammler mit SQLite

**Neu:** `admin/metrik.py`, Datenbank unter `<Installationsort>/admin/metrik.db`

```
messwerte(
  zeit      INTEGER PRIMARY KEY,   -- Unixzeit, volle Minute
  cpu       REAL,   -- Prozent
  ram       REAL,   -- Prozent
  platte    REAL,   -- Prozent
  temp      REAL,   -- Grad Celsius
  tps       REAL,   -- vom Server, über RCON
  mspt      REAL,   -- dito
  spieler   INTEGER
)
```

- **Ein Datensatz je Minute.** Sekundengenau kostet das Sechzigfache und zeigt
  nichts, was man sehen will.
- **Aufbewahrung sieben Tage** (rund 10.000 Zeilen). Ältere Zeilen räumt der
  Sammler beim Schreiben ab.
- **Läuft als Hintergrundthread der Weboberfläche.** Ist PiCraft abgeschaltet,
  gibt es keine Messwerte — das ist richtig so, nicht ein Fehler.
- **`PRAGMA journal_mode=WAL`**, damit Lesen und Schreiben sich nicht
  gegenseitig blockieren.
- **Schreibt nur, wenn der Server läuft** — sonst füllt sich die Datenbank
  über Monate mit Nullzeilen.

Zu beachten: SQLite-Verbindungen sind nicht threadsicher. Je Thread eine
eigene Verbindung, nicht eine geteilte.

### B4 — `app.py` wird ein Paket

Aus einer Datei mit 900 Zeilen wird `admin/` mit klaren Zuständigkeiten:

```
admin/
  __init__.py      App-Fabrik, Konfiguration einlesen
  einstellungen.py Pfade und Werte aus mcs.conf / .env
  system.py        CPU, RAM, Platte, Temperatur, Dienstzustand
  konsole.py       screen (senden) und RCON (fragen)
  protokoll.py     Logdateien lesen und filtern
  metrik.py        Sammler und Abfragen (B3)
  rcon.py          Protokoll (B1)
  routen/
    __init__.py
    status.py      /api/status
    aktionen.py    /api/action/*
    konfig.py      /api/server-properties
  templates/
    index.html     unverändert aus dieser Etappe
```

**Die Oberfläche selbst ändert sich in dieser Etappe nicht.** `index.html`
wird übernommen wie sie ist; sie kommt erst in Etappe C dran. Wer B und C
vermischt, kann hinterher nicht mehr sagen, woher ein Fehler kommt.

**Abweichung bei der Umsetzung (28.08.2026):** Statt eines echten
Python-Pakets mit `__init__.py` und `routen/`-Unterpaket sind es **flache
Module im selben Verzeichnis** geworden, mit einem Flask-Blueprint für die
Routen. Der Grund: Ein Paket hätte `WorkingDirectory`, `ExecStart` im
systemd-Dienst, den Aufruf aus `mcs status` und beide Kopierskripte geändert —
für ein Werkzeug aus zehn Dateien ist das mehr Umbau als Gewinn. `rcon.py` und
`metrik.py` hatten das flache Muster ohnehin schon etabliert.

Ergebnis:

```
admin_ui/
  app.py            Einstieg: Flask aufsetzen, Sammler starten, --summary
  einstellungen.py  Pfade und Zugangsdaten (liest mcs.conf)
  system.py         CPU, RAM, Platte, Temperatur, Dienste, Befehle
  protokoll.py      Server-Log: Spieler online, Chat, Fehler
  konsole.py        an den Server senden, Liste der erlaubten Aktionen
  rcon.py           den Server fragen (B1)
  metrik.py         Verlaufsdaten (B3)
  status.py         das Gesamtbild + Zwischenspeicher
  sicherheit.py     Anmeldung und Herkunftsprüfung
  routen.py         die URL-Pfade (Blueprint)
  templates/index.html
```

**`install-admin.sh` und `deploy.sh`** kopieren jetzt `*.py` statt einer
Aufzählung — sonst wird beim nächsten Modul eines vergessen, und der Fehler
zeigt sich erst auf einem frisch installierten Pi. Der systemd-Dienst bleibt
unverändert.

`app.py --summary` (von `mcs status` benutzt) funktioniert weiter.

---

## 2. Reihenfolge

```
B1  RCON-Client          (eigenständig, für sich testbar)
     ↓
B2  RCON einrichten      (braucht B1)
     ↓
B3  Metrik-Sammler       (braucht B2 für TPS/MSPT)
     ↓
B4  Paketstruktur        (zuletzt — sonst verschiebt jeder Schritt Dateien,
                          die gerade erst entstanden sind)
```

---

## 3. Abnahme der Etappe

1. `make` ohne Beanstandung, GitHub Actions grün.
2. Der Container-Abnahmetest läuft weiterhin durch.
3. `mcs rcon list` liefert eine **Antwort**, nicht nur eine Bestätigung.
4. Eine Antwort über 4096 Byte kommt vollständig an (mit vielen
   Whitelist-Einträgen prüfen).
5. Falsches RCON-Passwort ergibt eine verständliche Meldung, keine Ausnahme.
6. `ss -ltn` zeigt den RCON-Port; `ufw status` zeigt die Sperr-Regel dafür.
7. Nach einer Stunde Laufzeit enthält `metrik.db` rund 60 Zeilen mit
   plausiblen Werten für CPU, RAM, TPS.
8. Die Datenbank wächst nicht über sieben Tage hinaus.
9. `mcs status` und die Weboberfläche funktionieren wie vorher — gleiche
   Werte, gleiches Aussehen.
10. Auf dem Pi zu prüfen (nach `PRUEFEN-AUF-DEM-PI.md` übernehmen):
    RCON von einem anderen Gerät im Netz **nicht** erreichbar.
