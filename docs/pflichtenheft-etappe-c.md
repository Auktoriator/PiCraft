# Pflichtenheft Etappe C — Weboberfläche

**Grundlage:** `docs/lastenheft-minecraft-server.md`, Fassung 0.3 (bei
Abschluss der Etappe auf 0.5 fortgeschrieben),
Entscheidungen 4, 10, 12, 13, 14, Abschnitte 5.3 und 5.7, Korrektur K2
**Branch:** `etappe-c-weboberflaeche`
**Datum:** 28.08.2026
**Stand:** umgesetzt am 28.08.2026. Alle sieben Seiten stehen,
`make` und `tests/abnahme.sh` sind grün.
**Auf echter Hardware abgenommen am 29.08.2026** — mit vier Befunden an der
Oberfläche selbst, alle behoben: die Kartenseite las die Bindeadresse nicht
(toter Rahmen hinter einem Reverse-Proxy), die Spielzeit wurde am alten Ort
gesucht und blieb für jeden Spieler leer (Korrektur **K8**),
`install-admin.sh` meldete einen Ausweichport, den sie nicht verwendete,
und `MCS_ADMIN_SECRET` fehlte auf bestehenden Installationen. Was noch
offen ist — Handy-Ansicht, privates Fenster, Tailscale mit HTTPS,
Sieben-Tage-Kurven und Spielerverwaltung mit Zweitkonto —, steht in
`PRUEFEN-AUF-DEM-PI.md`.

> Ziel der Etappe: aus einer Seite werden sieben. Etappe B hat die Antworten
> (RCON), den Verlauf (Metriken) und die Struktur (zehn Module) geliefert;
> jetzt kommt das, was man tatsächlich sieht. Es ist das größte Arbeitspaket
> des Projekts, und es ist das erste, bei dem ein Fehler nicht auffällt, weil
> etwas nicht startet, sondern weil etwas *falsch aussieht*.

---

## 0. Was die Messung ergeben hat

Vor dem Entwurf standen sechs Annahmen im Raum, auf denen die
Konfigurations- und die Spielerseite aufbauen. Alle sechs wurden am
28.08.2026 in drei Durchgängen im ARM64-Container gegen **Paper 26.2 Build
119** gemessen. **Vier davon waren falsch.** Sie stehen hier zuerst, weil
sie den Entwurf verändert haben.

### K3 — Paper schreibt seine Konfigurationsdateien NICHT beim Herunterfahren neu

In `CLAUDE.md` und im Lastenheft (§5.7.3) steht:

> „Paper schreibt seine Konfigurationsdateien beim Herunterfahren neu. Wer
> eine YAML-Datei bei laufendem Server ändert, verliert die Änderung beim
> nächsten Neustart."

**Das stimmt so nicht.** Gemessen wurde jede der drei Möglichkeiten
einzeln — Marke setzen, Zustand wechseln, nachsehen:

| Was gemessen wurde | Ergebnis |
|---|---|
| `motd` und `view-distance` bei **laufendem** Server von Hand ändern, dann stoppen | beide Änderungen **überlebten** — beim Herunterfahren wird nichts überschrieben |
| Kommentar und `motd` bei **gestopptem** Server ändern, dann starten | Wert überlebte, **Kommentar weg**: 117 Zeilen mit 87 Kommentaren wurden zu 74 Zeilen mit 2 |
| `tab-spam-increment` in `paper-global.yml` und `monsters` in `bukkit.yml` bei **gestopptem** Server ändern, dann starten | beide Werte **überlebten**, Zeilen- und Kommentarzahl unverändert (148/14 bzw. 53/20) |
| dieselben YAML-Werte bei **laufendem** Server ändern, dann stoppen und starten | beide Werte **überlebten** beides |

Die tatsächliche Regel lautet:

| Datei | Wird neu geschrieben … | Was dabei passiert |
|---|---|---|
| `server.properties` | **beim Start** und **jedes Mal, wenn ein Befehl eine dort gespeicherte Einstellung ändert** | Kommentare werden entfernt, die Schlüssel alphabetisch sortiert, ein Kopf mit Zeitstempel gesetzt. Werte bleiben. |
| `bukkit.yml`, `spigot.yml`, `config/*.yml` | **beim Start** | Werte bleiben, die *eigenen* Kommentare der Datei bleiben. Nur fremde Kommentare fallen weg (eine eingefügte Zeile `# MESSMARKE-YAML` war nach dem Start verschwunden). |
| keine davon | beim Herunterfahren | — |

**Die Falle ist trotzdem echt, aber sie sieht anders aus.** Gemessen:

```
motd von Hand auf "MARKE-WAEHREND-LAUF" gesetzt   (Server läuft)
danach über RCON:  whitelist on
motd danach:       MARKE-VOR-START        ← die Handänderung ist weg
white-list danach: true                   ← der Befehl hat die Datei geschrieben
```

Ein einziger Befehl, der eine in `server.properties` gespeicherte
Einstellung ändert, lässt Paper die **ganze Datei aus dem Arbeitsspeicher
neu schreiben** — und überschreibt dabei alles, was inzwischen von außen
hineingeschrieben wurde. Das kann jederzeit passieren: Es reicht, dass ein
Operator im Spiel `/whitelist add` tippt.

**Daraus folgt für Etappe C:**

1. **`server.properties`** wird bei laufendem Server **nicht** direkt
   geschrieben. Vorgemerkt und beim nächsten Start angewendet — genau wie
   das Lastenheft es vorsieht, nur mit der richtigen Begründung.
2. **Die YAML-Dateien** dürfen bei laufendem Server geschrieben werden. Die
   Änderung wirkt beim nächsten Start; die Oberfläche sagt das dazu. Eine
   Vormerkung wäre hier ein Bauteil ohne Zweck.
3. Der Rohtext-Editor für `server.properties` muss ansagen, dass **eigene
   Kommentare den nächsten Start nicht überleben**. Sonst schreibt jemand
   sich eine Erklärung an eine Zeile und wundert sich.

Diese Korrektur gehört ins Lastenheft (§5.7.3) und in `CLAUDE.md`.

### K4 — Auf einer geteilten RCON-Verbindung reißt `whitelist add` die Verbindung ab

Zweimal unabhängig reproduziert, mit identischem Ergebnis an identischer
Stelle. Sechzehn Befehle über **eine** Verbindung:

```
op Steve             -> 'Made Steve a server operator'
whitelist add Steve  -> Der Server hat die Verbindung geschlossen.
kick Steve M         -> Broken pipe
ban Steve M          -> Broken pipe
...                     jeder weitere Befehl ebenso
```

Im Serverlog steht dazu **nichts** — keine Ausnahme, keine Warnung, nur
`Thread RCON Client shutting down`. Wer nur auf das Log schaut, findet den
Fehler nie.

Mit **je einer eigenen Verbindung** je Befehl läuft dieselbe Liste
vollständig durch, `whitelist add Steve` eingeschlossen
(`'Added Steve to the whitelist'`).

Die Ursache ist nicht abschließend geklärt. Fest steht, dass
`whitelist add` und `op` den Namen bei Mojang nachschlagen — die einzigen
Befehle der Spielerseite, bei denen der Server auf das Internet wartet.

**Daraus folgt:** Die Empfehlung im Lastenheft (§5.7.0, Regel 3), für
Schleifen `Rcon(...)` als Kontextmanager zu benutzen, gilt **nur für
Befehle, die den Rechner nicht verlassen**. Der Abnahmetest tut das mit 400
`ban-ip`-Befehlen auf einer Verbindung und läuft durch — das bleibt
richtig. Die Spielerseite dagegen benutzt **eine Verbindung je Klick**,
also `rcon.befehl()`, so wie es ohnehin gebaut ist.

### K5 — In `paper-global.yml` steht ein Geheimnis

Korrektur K2 verlangt, jeden neuen Editor vorher zu prüfen. Getan:

```
config/paper-global.yml, Zeile 119:      secret: ''
```

Das ist der Velocity-Proxy-Schlüssel. Er ist im Auslieferungszustand leer,
aber wer je einen Proxy einrichtet, hat dort ein Geheimnis stehen — in
einer Datei mit Rechten `644`, also für jeden auf dem Pi lesbar. In
`bukkit.yml`, `spigot.yml` und `paper-world-defaults.yml` steht nichts
Schützenswertes.

**Daraus folgt:** `GEHEIME_SCHLUESSEL` muss von einer Liste flacher
Schlüssel auf eine Liste **je Datei** erweitert werden. Und: Der
Expertenmodus-Editor bekommt eine ausdrückliche Liste der Dateien, die er
überhaupt öffnen darf — kein Pfad aus der Adresszeile.

### K6 — `install.sh` installiert vier Plugins, nicht eines

Lastenheft §5.8 sagt: „Mitinstalliert wird ausschließlich **Pl3xMap**".
Tatsächlich liegen nach der Installation vier Plugins da:

```
GSit.jar  Pl3xMap.jar  WorldEdit.jar  WorldGuard.jar
```

Sie standen alle in `server/plugins.txt`. Das war kein Fehler in der
Umsetzung, sondern eine Abweichung zwischen Lastenheft und Repository.

**Entschieden am 28.08.2026: auf Pl3xMap reduziert.** WorldEdit, WorldGuard
und GSit stehen jetzt auskommentiert in `server/plugins.txt.beispiel`, mit
Adresse und Prüfsumme zum Hineinkopieren; Chunky ist als vierter Vorschlag
dazugekommen. Ein fremder Pi bekommt damit nur noch, was das Lastenheft
verspricht. Umgesetzt zusammen mit E6 im ersten Commit dieser Etappe.

### Was sich bestätigt hat

- **Antwortformate für die Spielerseite** (jeweils wörtlich gemessen):

  ```
  list                 There are 0 of a max of 5 players online:
  whitelist list       There are 1 whitelisted player(s): Steve
  banlist players      There are 1 ban(s):Steve was banned by Rcon: Testgrund
  banlist ips          There are 1 ban(s):203.0.113.7 was banned by Rcon: Messung
  op Steve             Made Steve a server operator
  kick Steve M         No player was found        (bei Offline-Spielern)
  ```

  Zu beachten: Nach `ban(s):` folgt **kein Zeilenumbruch**. Wer die Antwort
  am Zeilenende zerlegt, bekommt einen einzigen Klumpen.

- **Die Spielzeit-Statistik heißt `minecraft.custom:minecraft.play_time`.**
  Gemessen, indem ein Scoreboard-Ziel mit diesem Kriterium angelegt wurde:
  angenommen. Der alte Name `play_one_minute` wird abgelehnt
  (`Unknown criterion`). Damit steht fest, welchen Schlüssel die
  Spielerseite in der Statistikdatei des Spielers sucht.

- **Spielerdaten liegen in fünf Dateien**, die Paper selbst schreibt:
  `usercache.json` (Name ↔ UUID, mit Ablaufdatum), `whitelist.json`,
  `ops.json` (mit `level` 1–4), `banned-players.json`, `banned-ips.json`.
  Die Statistiken und die Spielerstände in der Welt gibt es erst, **wenn zum
  ersten Mal jemand gespielt hat** — auf einem frischen Server fehlen sie.

  > **Nachgetragen am 29.08.2026 (Korrektur K8):** Hier stand
  > `<welt>/stats/` und `<welt>/playerdata/`. Seit der Formatumstellung
  > liegen beide unter `<welt>/players/` — `players/stats`,
  > `players/advancements` und `players/data`. Der Entwurf ging vom alten
  > Ort aus, und die Spielzeit blieb auf einer umgestellten Welt für jeden
  > Spieler leer. `spieler.py` prüft jetzt beide Orte.

- **Pl3xMap belegt Port 8080** (`internal-webserver: enabled: true, bind:
  0.0.0.0, port: 8080`), die Weboberfläche weicht auf 8081 aus. Befund B6
  ist damit auch im Betrieb bestätigt:

  ```
  LISTEN *:25565    Spielserver
  LISTEN *:25575    RCON   (auf ALLEN Karten — Korrektur K1)
  LISTEN *:8080     Pl3xMap
  ```

Die drei Messskripte werden als `tests/messung-paper-verhalten.sh` ins
Repository übernommen (Arbeitspaket C1). Eine Messung, die man nicht
wiederholen kann, ist beim nächsten Paper-Update wertlos.

---

## 1. Entscheidungen, die diese Etappe trifft

Die offenen Punkte O2, O3 und O5 aus dem Lastenheft, dazu fünf, die sich
beim Entwurf ergeben haben. **Alle acht sind am 28.08.2026 abgestimmt
worden**; sie stehen hier mitsamt ihrer Begründung, weil sonst in einem
halben Jahr niemand mehr weiß, warum es so und nicht anders aussieht.

### E1 — Reihenfolge der Reiter (Lastenheft O2)

```
Start · Spieler · Leistung · Karte · Backups · Konfiguration · Plugins
```

Die Regel dahinter, in einem Satz: **erst, was man ansieht, dann, was man
ändert — und je weiter rechts, desto mehr lässt sich kaputt machen.** Die
ersten vier Reiter beantworten Fragen, die drei letzten greifen ein.

Auf dem Handy passen sieben Reiter nicht nebeneinander. Sie stehen deshalb
in einer waagerecht schiebbaren Leiste, wobei der aktive Reiter immer in
den sichtbaren Bereich gerückt wird. Kein Klappmenü: Ein Menü, das man erst
öffnen muss, kostet bei jedem Wechsel einen Klick mehr, und gewechselt wird
oft.

### E2 — Die kuratierten Werte (Lastenheft O3)

Das Lastenheft nennt „rund 20". Es sind **19**, verteilt auf zwei Seiten —
und das ist die eigentliche Entscheidung: **Sichtweite, Simulationsdistanz
und Arbeitsspeicher stehen auf der Leistungsseite, nicht auf der
Konfigurationsseite.** Sie sind keine Spielregeln, sondern
Leistungsstellschrauben und gehören neben die Kurve, die zeigt, was sie
kosten. Das Lastenheft nennt sie an beiden Stellen (§5.7.4
Punkt 3 und Punkt 5); zweimal dieselbe Einstellung an zwei Orten ist eine
Fehlerquelle. Sie gehören dorthin, wo die Kurve daneben zeigt, was sie
kosten.

**Konfiguration → „Einstellungen" (15 Werte, alle aus `server.properties`):**

| Wert | Bedienelement | Anmerkung für den Text daneben |
|---|---|---|
| `gamemode` | Auswahl | Survival / Kreativ / Abenteuer / Zuschauer |
| `difficulty` | Auswahl | friedlich / einfach / normal / schwer |
| `hardcore` | Schalter | mit deutlicher Warnung |
| `pvp` | Schalter | |
| `spawn-monsters` | Schalter | |
| `spawn-protection` | Zahl 0–64 | 0 = kein Bauschutz um den Spawn |
| `allow-nether` | Schalter | |
| `allow-flight` | Schalter | verhindert falsche Rauswürfe, nicht Kreativflug |
| `enable-command-block` | Schalter | |
| `max-players` | Zahl 1–20 | über 10 wird abgeraten (Lastenheft §1.3) |
| `white-list` | Schalter | **Sonderfall, siehe E4** |
| `online-mode` | Schalter | Warnung: niemals abschalten, wenn der Port offen ist |
| `motd` | Text | mit Vorschau der §-Farbcodes |
| `server-port` | Zahl | mit Hinweis auf Router und Firewall |
| `pause-when-empty-seconds` | Zahl | Server pausiert, wenn niemand da ist |

**Leistung → „Einstellungen" (4 Werte):**

| Wert | Woher | Anmerkung |
|---|---|---|
| `view-distance` | `server.properties` | Sichtweite — kostet RAM und Netz |
| `simulation-distance` | `server.properties` | **der teure Wert** — (2·n+1)² getickte Chunks je Spieler |
| `MCS_HEAP` | **`mcs.conf`** | Empfehlung aus dem tatsächlich vorhandenen RAM abgeleitet |
| `entity-broadcast-range-percentage` | `server.properties` | nur anzeigen, mit Erklärung — nicht änderbar |

`MCS_HEAP` steht in einer anderen Datei mit anderen Regeln: Sie gehört dem
Pi, wird von Shell, Python und systemd gelesen, und eine Änderung wirkt
erst nach `mcs restart`. Die Seite sagt das dazu.

**Bewusst nicht kuratiert:** `sync-chunk-writes`,
`region-file-compression`, `network-compression-threshold`. Das sind am
2026-07-27 nachgemessene Werte (`docs/optimierung-2026-07-27.md`), und
CLAUDE.md sagt: Leistungsänderungen nur mit Messung. Sie bleiben dem
Expertenmodus vorbehalten.

**Ein gemessener Fallstrick für diese Seite:** `/difficulty peaceful` über
RCON hat die Weltschwierigkeit geändert, in `server.properties` stand
danach weiterhin `easy`. Datei und laufende Welt können also
auseinanderlaufen. Ob der Dateiwert beim nächsten Start wieder gewinnt, ist
**noch nicht gemessen** und wird in C4 nachgeholt, bevor die Seite den Wert
anzeigt.

### E3 — Schriften (Lastenheft O5)

| Wofür | Was |
|---|---|
| Fließtext, Beschriftungen | `system-ui`-Stapel — **keine Webfont**, null Bytes, auf jedem Gerät da |
| Messwerte, Protokolle, Editor | System-Monospace mit `tabular-nums` — Zahlen springen dann beim Aktualisieren nicht |
| Überschriften, große Zahlen | **eine** Pixelschrift, mitgeliefert als `woff2` |

Anforderungen an die Pixelschrift, in dieser Reihenfolge: SIL-OFL-Lizenz
(damit sie im öffentlichen Repository liegen darf), **Umlaute** (die
Überschrift „Übersicht" muss lesbar sein), unter 20 KB als `woff2`.
Kandidaten: *Silkscreen*, *Pixelify Sans*, *Jersey 10*. Welche es wird,
entscheidet sich beim Beschaffen an der Glyphenabdeckung — die Umlaute sind
das Ausschlusskriterium.

Die Datei kommt mit `OFL.txt` und einer Herkunftsnotiz samt Prüfsumme ins
Repository, wie bei `paper.jar` und den Plugins auch.

*Rückfallposition, falls keine passende Schrift zu finden ist:* gar keine
Webfont. Überschriften dann im Monospace-Stapel mit weitem Zeichenabstand.
Die eckigen Flächen und die Fase (§5.7.1) tragen den Minecraft-Bezug
ohnehin allein.

### E4 — Anmeldung: Sitzungs-Cookie statt HTTP Basic Auth

Lastenheft §5.3 verlangt das, und es ist überfällig: Basic Auth kennt kein
Abmelden und hängt die Zugangsdaten an jede Anfrage.

- **Cookie** mit `HttpOnly`, `SameSite=Lax`, Laufzeit 30 Tage, dazu ein
  Knopf „Abmelden". `Secure` nur, wenn `MCS_ADMIN_HTTPS=1` gesetzt ist —
  über eine reine HTTP-Verbindung im Heimnetz würde `Secure` die Anmeldung
  unmöglich machen.
- **Sitzungsschlüssel** (`MCS_ADMIN_SECRET`) erzeugt `install-admin.sh` in
  die `.env`. Fehlt er, erzeugt die App beim Start einen zufälligen und
  **sagt in der Oberfläche, dass jeder Neustart alle abmeldet** — melden,
  nicht verstecken.
- **Ratenbegrenzung**: fünf Fehlversuche je Adresse in fünfzehn Minuten,
  danach fünf Minuten Sperre. In einer Python-Struktur im Arbeitsspeicher,
  ohne Zusatzpaket. Steht ein Reverse-Proxy davor, sehen alle Anfragen
  gleich aus — das wird dokumentiert, nicht behoben.
- **Das Passwort bleibt Klartext in der `.env`** (Entscheidung 10). Daran
  ändert sich nichts.

**Der CSRF-Schutz muss dabei umgebaut werden.** Die heutige Prüfung
verlangt `Content-Type: application/json` — HTMX schickt aber
Formulardaten. Neu, drei Schichten:

1. `SameSite=Lax` auf dem Cookie: Der Browser schickt es bei einer
   fremdausgelösten POST-Anfrage gar nicht erst mit.
2. Ein Sitzungs-Token, das HTMX über `hx-headers` an jede schreibende
   Anfrage hängt.
3. Die Herkunftsprüfung (`Origin`/`Referer`) bleibt, wie sie ist.

### E5 — Aufteilung der Module

Etappe B hat sich bewusst gegen ein Python-Paket entschieden (flache Module
im selben Verzeichnis). Das bleibt so — ein Paket würde `WorkingDirectory`,
`ExecStart`, `mcs status` und beide Kopierskripte anfassen.

Neu kommen elf Module dazu, in zwei Schichten. Mit HTMX liefert eine Route
oft ein Stück HTML statt JSON; Routen und Seitenlogik gehören deshalb
zusammen, die *Daten*beschaffung aber nicht:

```
seite_start.py  seite_spieler.py  seite_leistung.py  seite_karte.py
seite_backups.py  seite_konfig.py  seite_plugins.py     ← Routen und Fragmente
spieler.py  konfig.py  backups.py  plugins.py            ← die Logik dahinter
```

`routen.py` behält `/api/status` und `/api/verlauf` (uPlot braucht JSON)
und gibt den Rest an die Seitenmodule ab. `*.py` bleibt als Kopiermuster
gültig — kein Skript muss geändert werden, wenn ein Modul dazukommt.

### E6 — `plugins.txt` gehört dem Pi

Die Plugin-Seite soll nach `plugins.txt` schreiben (Entscheidung 13). Diese
Datei wird heute aber von `deploy.sh` aus dem Repository auf den Pi
kopiert — **jedes Ausrollen würde die über die Oberfläche installierten
Plugins wieder wegwerfen.** Das ist Befund B2 in neuer Gestalt.

Vorschlag, genau wie bei `mcs.conf` gelöst:

- `server/plugins.txt` wird zu **`server/plugins.txt.beispiel`** — die
  Startliste für eine frische Installation.
- Die echte `plugins.txt` liegt auf dem Pi, `deploy.sh` **vergleicht** sie
  nur noch und meldet Abweichungen.
- Der Abnahmetest bekommt eine Prüfung dafür, wie schon für `mcs.conf`.

### E7 — Modrinth ist der einzige Weg nach außen

§5.7.2 sagt: „ein Verwaltungswerkzeug sollte keine Anfragen nach außen
stellen". Die Plugin-Suche braucht das aber.

Auflösung: **Die Oberfläche fragt von sich aus nie an.** Modrinth wird
ausschließlich auf einen ausdrücklichen Klick hin angesprochen (Suchen,
Versionen anzeigen, Installieren), und auf der Plugin-Seite steht, dass
dieser Klick eine Verbindung nach außen aufbaut. Alle übrigen sechs Seiten
funktionieren vollständig ohne Internet.

### E8 — Wiederherstellen aus der Oberfläche

Das Lastenheft will „mit einem Klick wiederherstellen oder löschen". Ein
Klick, der Weltdaten austauscht, braucht mehr Absicherung als ein Klick,
der einen Dienst startet:

1. Nur bei **gestopptem Server** — `mcs restore` verweigert sich sonst
   ohnehin, aber die Oberfläche soll den Knopf gar nicht erst anbieten.
2. Der Name des Backups muss **abgetippt** werden, nicht nur bestätigt.
3. Die bisherigen Weltordner werden umbenannt statt gelöscht — das tut
   `mcs restore` bereits.
4. `mcs restore` fragt heute im Terminal nach. Für die Oberfläche kommt ein
   Schalter `--ja` dazu, der die Rückfrage überspringt; die Rückfrage
   findet dann im Browser statt.

**Dazu kommt `mcs restore --probe`** (Lastenheft §5.4 Punkt 3): entpackt in
ein temporäres Verzeichnis und prüft, ohne irgendetwas anzufassen. Die
Backup-Seite braucht diesen Knopf — „wir haben Backups" wird damit zu „wir
haben geprüfte Backups". Das ist eine Erweiterung des Etappenumfangs um
etwa dreißig Zeilen Shell; ich halte sie für richtig hier, weil die Seite
sonst einen Knopf hat, hinter dem nichts steht.

---

## 2. Arbeitspakete

### C1 — Fundament und Startseite *(umgesetzt)*

Das ist das größte einzelne Paket. Es endet damit, dass `index.html`
gelöscht ist und die neue Oberfläche vollständig an ihrer Stelle steht —
**in einem Commit**, weil eine halb umgebaute Oberfläche niemandem nützt.

**Mitgelieferte Fremdteile**, alle lokal, alle mit Herkunft und Prüfsumme
in `admin_ui/static/HERKUNFT.md`:

| Was | Größe | Lizenz |
|---|---|---|
| `htmx.min.js` | ~48 KB | 0BSD |
| `uPlot.iife.min.js` + `uPlot.min.css` | ~45 KB | MIT |
| eine Pixelschrift als `woff2` | < 20 KB | SIL OFL (siehe E3) |

**Neue Struktur:**

```
admin_ui/
  static/
    HERKUNFT.md          Version, Datum, SHA256 je Datei
    mcs.css              das Farb- und Formsystem
    fremd/               htmx, uPlot, Schrift
  templates/
    basis.html           Grundgerüst: Kopf, Reiterleiste, Fuß
    anmeldung.html
    start.html
    teile/               HTMX-Fragmente (Kacheln, Listen, Meldungen)
```

**Gestaltung** (Lastenheft §5.7.1), als CSS-System und nicht als Sammlung
von Sonderfällen:

- **Keine abgerundete Ecke, nirgends.** `border-radius: 0` als
  Grundeinstellung, nicht als Ausnahme.
- **Die Fase**: helle Kante oben und links, dunkle unten und rechts. Eine
  CSS-Klasse, überall dieselbe. Bei gedrückten Knöpfen dreht sie sich um —
  das ist der Effekt, den Minecraft seit dreißig Jahren benutzt.
- **Materialfarben** als benannte Variablen: Erde, Gras, Stein,
  Inventarblau, Redstone, Bernstein. Dunkel als Standard, hell als
  `prefers-color-scheme`-Umschaltung.
- **Zwei Stellen, an denen es richtig Minecraft ist**, mehr nicht: der
  Spielerzähler als Herzenleiste, der „alles in Ordnung"-Balken im Grün der
  Erfahrungsleiste.
- **Keine Animation** außer dem Aufblitzen eines gerade aktualisierten
  Werts.

**Anmeldung** auf Sitzungs-Cookie umbauen (E4), Ratenbegrenzung,
CSRF-Umbau, `MCS_ADMIN_SECRET` in `install-admin.sh`.

**Startseite** (Lastenheft §5.7.4 Punkt 1). Leitfrage: *Was will ich in
fünf Sekunden vom Handy aus wissen?*

- Kacheln, anklickbar, jede führt auf die zuständige Seite: Serverzustand,
  Spieler online (Herzenleiste), TPS, letztes Backup, freier Plattenplatz,
  Temperatur.
- Ein Eingabefeld für Chat oder Befehl. **Neu gegenüber heute:** Befehle
  laufen über RCON und die **Antwort wird angezeigt**. Bisher verschwand
  sie im Log. Chat weiterhin mit `[WEB]`-Präfix.
- Eine **Ereignisleiste** mit den letzten fünf Vorgängen, gespeist aus
  `player_activity.log`, `actions.log` und dem Backup-Protokoll.
- Aktualisierung über HTMX, alle 5 Sekunden, nur die Kacheln — nicht die
  ganze Seite.

**Ausrollen anpassen:** `install-admin.sh` und `deploy.sh` kopieren heute
genau eine Datei `templates/index.html`. Sie müssen `templates/` und
`static/` **vollständig** übernehmen, sonst fehlt auf einem frisch
installierten Pi das halbe Werkzeug — der Fehler, vor dem Pflichtenheft B
schon einmal gewarnt hat.

**Messskripte übernehmen** als `tests/messung-paper-verhalten.sh`.

### C2 — Leistung *(umgesetzt)*

- CPU, RAM, Platte, Temperatur, Last, TPS, MSPT.
- Verlauf mit uPlot über **1 Stunde / 24 Stunden / 7 Tage**. Das Lastenheft
  nennt „1 Minute"; bei einem Messwert je Minute wäre das ein einzelner
  Punkt. Die kleinste Stufe ist deshalb eine Stunde, und der
  Augenblickswert steht ohnehin als Zahl daneben.
- Die vier Einstellungen aus E2, mit Empfehlung je nach vorhandenem RAM.
- Keine GPU-Anzeige (Lastenheft §5.7.4 Punkt 5).

**Abweichung bei der Umsetzung:** Die Vormerk-Mechanik war für C4 geplant.
Sie ist stattdessen hier entstanden, weil die Leistungsseite die erste ist,
die überhaupt etwas schreibt — Sichtweite und Simulationsdistanz stehen in
der `server.properties`, und für die gilt K3. `konfig.py` und der Block in
`start-minecraft.sh` sind damit gebaut und geprüft, bevor C4 die kuratierte
Einstellungsseite darauf aufsetzt. Eine halbe Seite mit einem Formular, das
noch nicht speichern kann, wäre die schlechtere Zwischenstufe gewesen.

**Was der Container-Test dabei gefunden hat** (und was ohne ihn erst auf dem
Pi aufgefallen wäre): `start-minecraft.sh` läuft unter `set -e`. Eine
vorgemerkte Datei, die sich nicht löschen ließ, ließ das `rm` fehlschlagen —
und **der Server startete gar nicht mehr**. Eine Einstellung, die nicht
ankommt, ist ärgerlich; ein Server, der deswegen nicht hochkommt, ist ein
Ausfall. Der Block ist jetzt gegen jeden Einzelfehlschlag abgesichert und
meldet, statt abzubrechen. Der Fall steht als eigener Prüfpunkt im
Abnahmetest (Abschnitt 6b).

### C3 — Spieler *(umgesetzt)*

- **Liste aller je verbundenen Spieler** aus `usercache.json`, angereichert
  aus `whitelist.json`, `ops.json`, `banned-players.json`.
- Online-Kennzeichnung und „seit wann" aus `protokoll.online_players()`;
  „zuletzt gesehen", erste Verbindung und letzte bekannte IP-Adresse aus
  `player_activity.log`.
- **Gespielte Gesamtzeit** aus `<welt>/stats/<uuid>.json`, Schlüssel
  `minecraft:custom` → `minecraft:play_time`, in Ticks (÷ 20 = Sekunden).
  Fehlt die Datei, steht dort ein Strich — kein Nullwert, der wie eine
  Messung aussieht.
- **Aktionen** über RCON, je Klick eine eigene Verbindung (K4): OP setzen
  und entziehen, Whitelist, kicken (mit Grund), sperren, entsperren.
- **`whitelist add` bekommt ein längeres Zeitlimit und eine eigene
  Fehlermeldung**, weil der Server dafür bei Mojang nachschlägt: ohne
  Internet schlägt es fehl, und das muss dastehen, statt als „RCON kaputt"
  zu erscheinen.
- Die Antwortformate aus §0 werden geparst — mit der Sonderbehandlung für
  `There are 1 ban(s):` ohne Zeilenumbruch.

**Abweichung bei der Umsetzung:** Gelesen wird ausschließlich aus den
Dateien, die Paper selbst schreibt (`usercache.json`, `whitelist.json`,
`ops.json`, `banned-players.json`, `<welt>/stats/<uuid>.json`) — nicht über
RCON. Das ist billiger, vollständiger (`ops.json` kennt die Stufe, die
Textantwort nicht) und funktioniert auch bei gestopptem Server. RCON wird
nur zum **Ändern** benutzt, weil Minecraft diese Listen im Arbeitsspeicher
hält: Eine Änderung an der Datei wäre beim nächsten Schreiben lautlos weg —
dieselbe Falle wie bei der `server.properties`.

Daraus folgt auch: **Ändern geht nur bei laufendem Server.** Die Seite sagt
das und zeigt die Liste trotzdem an.

Für „letzte bekannte IP-Adresse" fehlte die Grundlage:
`log_player_activity.sh` schrieb die Anmeldezeile mit Adresse gar nicht mit,
und im `latest.log` steht sie nur bis zum nächsten Serverstart. Die Zeile
ist dazugekommen, mit einem Hinweis darauf, dass es eine personenbezogene
Angabe ist und wie man sie abschaltet.

### C4 — Konfiguration *(umgesetzt)*

Das heikelste Paket. Die Vormerkung selbst steht schon (siehe C2); hier
kommt alles darauf.

**Ebene 1 „Einstellungen":** die 15 Werte aus E2 als richtige
Bedienelemente mit deutscher Erklärung und geprüften Wertebereichen.

**Ebene 2 „Expertenmodus":** Rohtext-Editor je Datei, aus einer **festen
Liste** (kein Pfad aus der Adresszeile): `server.properties`,
`bukkit.yml`, `spigot.yml`, `config/paper-global.yml`,
`config/paper-world-defaults.yml`. Prüfung beim Speichern (Properties:
`schlüssel=wert`; YAML: Einlesen mit dem Python-Modul), Sicherung der
Vorfassung, **Diff-Anzeige vor dem Übernehmen**.

**Schreibregeln, nach K3:**

| Lage | Was passiert |
|---|---|
| Server steht | direkt schreiben |
| Server läuft, YAML-Datei | direkt schreiben, dazu: „wirkt beim nächsten Neustart" |
| Server läuft, `server.properties` | **vormerken** |
| Server läuft, `white-list` | über `/whitelist on\|off` — wirkt sofort, und Paper schreibt die Datei selbst |

**Die Vormerkung** ist in C2 entstanden und steht: Unter
`<MCS_DIR>/vorgemerkt/` liegt die **vollständige neue Fassung** der Datei.
Kein Patch-Format, damit die Diff-Anzeige trivial bleibt und niemand ein
Format erfinden muss. `start-minecraft.sh` legt sie vor dem Start an ihren
Platz (Vorfassung beiseite) und räumt die Vormerkung weg. Der Dateiname
trägt den Pfad in sich (`config__paper-global.yml`), damit es keine zweite
Liste gibt, die mit `konfig.py` auseinanderlaufen könnte.

In C4 kommt die Anzeige dazu: „3 Änderungen warten auf den nächsten
Neustart" auf dieser Seite **und** auf der Startseite, mit Diff und einem
Knopf zum Verwerfen.

**Geheimnisse** (K5): `GEHEIME_SCHLUESSEL` wird zu einer Zuordnung je
Datei, `config/paper-global.yml` → `secret` kommt hinzu.

Auf dieselbe Seite gehören außerdem (Lastenheft §5.7.4 Punkt 3):
hochfahren, herunterfahren, neu starten, aktualisieren; die installierten
Paper- und Java-Versionen; welche Ports offen sind, wofür und warum.

**`mcs aus` bekommt hier keinen Knopf.** Es würde die Weboberfläche
mitabschalten, und ein Knopf, der die Seite unerreichbar macht, die ihn
zeigt, ist eine Falle. Erwähnt wird der Befehl, ausgelöst wird er im
Terminal.

**Nachgemessen** (Korrektur K7): Nein, er überschreibt sie nicht — er wird
beim Start ignoriert. `difficulty` wird deshalb vom Server erfragt und über
`/difficulty` geändert, nicht aus der Datei gelesen.

**Zwei weitere Dinge, die beim Bauen aufgefallen sind:**

- Fehlt ein Schlüssel in der `server.properties`, zeigte die Seite „aus" —
  auch bei `allow-nether`, dessen Minecraft-Vorgabe „an" ist. Jede
  Einstellung trägt jetzt ihren Standardwert und wird als solcher
  gekennzeichnet. Auf einem echten Server kommt das selten vor (Paper
  schreibt beim ersten Start alle Schlüssel), aber „selten" ist kein Grund,
  dann etwas Falsches anzuzeigen.
- Der YAML-Editor konnte ohne Parser nur auf Tabulatoren prüfen und hätte
  kaputtes YAML gespeichert — der Server wäre beim nächsten Start
  stehengeblieben. `install-admin.sh` installiert jetzt `python3-yaml`; fehlt
  es doch, sagt die Oberfläche beim Speichern deutlich, dass nicht wirklich
  geprüft wurde.

### C5 — Backups *(umgesetzt)*

- Liste der Backups aus Rotation und Dauerarchiv, mit Größe, Alter und
  Zustand.
- **Prüfen** über `mcs restore --probe` (E8, neu).
- **Wiederherstellen** mit der Absicherung aus E8.
- **Löschen** einzelner Archive.
- Zeitplan sehen und ändern: `OnCalendar` in `mcs-backup.timer`. Zu
  beachten — `deploy.sh` bewahrt die eingestellte Uhrzeit bereits, das darf
  nicht kaputtgehen.
- Aufbewahrungsregeln, Dauerarchiv, Zweitziel (`MCS_EXTERN_DIR`) als
  sichtbarer Schalter.
- Der letzte Fehlschlag aus `.letzter-fehler`, deutlich.

**Abweichung bei der Umsetzung:** Zeitplan und Aufbewahrungsregeln werden
nur **angezeigt**, nicht bearbeitet. Die Uhrzeit steht im systemd-Timer, die
Aufbewahrung in der `mcs.conf` — beides sind Werte, die man einmal einstellt
und dann jahrelang nicht mehr anfasst. Ein Formular dafür wäre ein
Bedienelement, das man nie benutzt, an einer Stelle, an der jeder
zusätzliche Knopf vom Wichtigen ablenkt. Die Seite sagt stattdessen, wo es
steht.

Das **Löschen** hat eine Regel dazubekommen, die nicht im Lastenheft stand:
Das neueste Backup lässt sich nicht löschen. Wer alle löscht, steht ohne da
und merkt es erst, wenn er eines braucht. Die Rotation räumt ohnehin von
selbst ab; der Knopf ist für den Sonderfall.

*Nicht in dieser Etappe:* die Benachrichtigung bei Fehlschlag. Sie steht im
Lastenheft unter Etappe D (offener Punkt O4, der Weg ist noch nicht
gewählt).

### C6 — Plugins *(umgesetzt)*

- Übersicht der installierten Plugins mit Version und Zustand, aus
  `plugins.txt` und dem tatsächlichen Inhalt von `plugins/`.
- Was auf dem Pi liegt, aber nicht in der Liste steht, wird **gemeldet, nie
  gelöscht** (Lastenheft §5.8).
- Suchen und installieren über die Modrinth-API (E7): Suche, Versionen,
  Prüfsummen, unterstützte Spielversion. Die Oberfläche schreibt nach
  `plugins.txt` (E6) und ruft `plugin-update.sh`.
- Aktivieren und deaktivieren durch Umbenennen `.jar` ↔ `.jar.disabled`.
- Konfiguration über den generischen YAML-Editor aus C4 — mit der
  Geheimnisprüfung aus K5 je Plugin-Datei.
- Die Empfehlungen aus §5.8 (Chunky, WorldEdit, WorldGuard, GSit) als
  Vorschläge — jede mit dem Grund, warum man sie wollen könnte.

**Beim Bauen nachgemessen:** Die Modrinth-Suche fand nichts, obwohl die
Versionsabfrage für dasselbe Plugin etwas lieferte. Ursache waren die
Suchfacetten:

```
categories:paper                          8 Treffer
project_type:mod                         15 Treffer
categories:paper + project_type:mod       0 Treffer   ← so war es
categories:paper + versions:26.2          3 Treffer   ← so ist es richtig
```

Die beiden schließen sich im Suchindex gegenseitig aus: Modrinth führt
Plugin-Projekte dort unter `project_type:plugin`, obwohl die Projektauskunft
desselben Plugins `project_type: mod` meldet. Wer sich auf die
Projektauskunft verlässt, baut eine Suche, die nie etwas findet — ohne
Fehlermeldung.

**Konfiguration von Plugins:** Der YAML-Editor aus C4 kennt nur die fünf
Dateien des Servers selbst. `plugins/<Name>/config.yml` mit aufzunehmen
hieße, die feste Dateiliste durch etwas Dynamisches zu ersetzen — und genau
diese feste Liste ist das, was einen Pfad aus der Adresszeile verhindert.
Die Plugin-Seite sagt deshalb, dass das derzeit über SSH geht. Nachzuholen,
wenn es jemand wirklich braucht.

### C7 — Weltkarte *(umgesetzt)*

- Pl3xMap als `iframe`, dazu „in neuem Tab öffnen".
- Der Port wird aus `plugins/Pl3xMap/config.yml` gelesen
  (`internal-webserver.port`), nicht geraten — gemessen steht dort 8080,
  und die Weboberfläche liegt dann auf 8081.
- **Ein Fallstrick, der benannt gehört:** Wird die Oberfläche über
  Tailscale mit HTTPS aufgerufen, blockiert der Browser einen `iframe`, der
  auf `http://` zeigt (gemischte Inhalte). Die Seite muss das erkennen und
  auf den direkten Link ausweichen, statt einen weißen Kasten zu zeigen.
- Ist Pl3xMap nicht installiert, sagt die Seite das und bietet die
  Installation an.

### C8 — Abnahme und Dokumentation *(umgesetzt)*

- **Container-Abnahmetest erweitern:** Alle sieben Seiten mit dem Flask-
  Testclient abrufen (Status 200, kein Fehler in der Vorlage), Anmeldung
  ohne Cookie abweisen, CSRF-Token prüfen, die Vormerkung einmal
  vollständig durchspielen (vormerken → starten → angekommen), das
  Verdecken der Geheimnisse für alle Dateien aus K5 prüfen, `plugins.txt`
  nach E6 wie `mcs.conf` behandeln.
- **`PRUEFEN-AUF-DEM-PI.md`** um die Punkte ergänzen, die nur echte
  Hardware zeigt: Darstellung auf dem Handy, Lesbarkeit im Dunkeln,
  Kartenanzeige über Tailscale, Reaktionszeit unter Last.
- **README**: Abschnitt „Admin-Weboberfläche" neu schreiben, die sieben
  Seiten beschreiben.
- **Lastenheft** auf Fassung 0.4: K3 bis K6 aufnehmen, O2, O3 und O5 als
  entschieden markieren.
- **`CLAUDE.md`**: die Falle „Paper schreibt beim Herunterfahren neu" durch
  die gemessene Fassung ersetzen (K3).

---

## 3. Reihenfolge

```
C1  Fundament + Startseite   (löst index.html ab — ein Commit)
     ↓
C2  Leistung                 (liest nur; Daten liegen aus Etappe B bereit)
     ↓
C3  Spieler                  (liest und schreibt über RCON)
     ↓
C4  Konfiguration            (schreibt Dateien — Vormerkung)
     ↓
C5  Backups                  (schreibt Weltdaten — höchstes Risiko)
     ↓
C6  Plugins                  (braucht Internet, braucht E6)
     ↓
C7  Weltkarte                (klein, hängt an nichts)
     ↓
C8  Abnahme und Dokumentation
```

Der Grundgedanke: **erst die Seiten, die nur lesen, dann die, die
schreiben, dann die, die Weltdaten anfassen.** Wer C5 vor C2 baut, riskiert
Datenverlust, um eine Kachel auszuprobieren.

Nach jedem Paket `make` und `tests/abnahme.sh`, committet wird nur, wenn
beides grün ist.

---

## 4. Abnahme der Etappe

1. `make` ohne Beanstandung, GitHub Actions grün.
2. Der Container-Abnahmetest läuft durch, einschließlich der neuen
   Prüfungen aus C8.
3. Alle sieben Seiten sind erreichbar und zeigen echte Werte — keine
   Platzhalter.
4. Ohne Anmeldung ist keine Seite und keine Schnittstelle erreichbar; nach
   fünf Fehlversuchen greift die Sperre; „Abmelden" funktioniert.
5. Eine Änderung an `server.properties` bei **laufendem** Server wird
   vorgemerkt, angezeigt und beim nächsten Start wirksam — nachgewiesen,
   nicht angenommen.
6. Eine Änderung an einer YAML-Datei bei laufendem Server ist nach dem
   nächsten Start da.
7. Das RCON-Passwort ist in keinem Editor im Klartext zu sehen, auch nicht
   der Velocity-Schlüssel aus `paper-global.yml`.
8. Die Spielerseite zeigt Whitelist, Sperrliste und OP-Stufen; kicken und
   sperren wirken; `whitelist add` ohne Internet ergibt eine verständliche
   Meldung.
9. Ein Backup lässt sich über die Oberfläche prüfen (`--probe`) und
   wiederherstellen; der Knopf fehlt bei laufendem Server.
10. Ein Plugin lässt sich über Modrinth suchen, installieren, deaktivieren
    und wieder aktivieren; `plugins.txt` überlebt ein `./deploy.sh`.
11. Die Oberfläche funktioniert **ohne Internetverbindung** vollständig —
    außer der Modrinth-Suche.
12. Auf dem Handy ist alles bedienbar, ohne waagerecht zu schieben (außer
    der Reiterleiste, die das absichtlich tut).
13. Auf dem Pi zu prüfen (nach `PRUEFEN-AUF-DEM-PI.md` übernehmen):
    Darstellung auf dem Handy, Karte über Tailscale, Reaktionszeit während
    fünf Spielern.

---

## 5. Was Etappe C nicht umfasst

Damit die Grenze klar ist:

- **DNS, Erreichbarkeitstest, playit.gg** — Etappe D.
- **Benachrichtigung bei Backup-Fehlschlag** — Etappe D, offener Punkt O4.
- **`unattended-upgrades`, Hardware- und Speichermedium-Erkennung** —
  Etappe D.
- **Aufräumen der obersten Repository-Ebene** (`lib/`, `admin_ui/` →
  `admin/`, Lastenheft §5.9) — bewusst nicht hier. Es verschiebt genau die
  Dateien, an denen diese Etappe arbeitet.
- **Formulare je Plugin** — Entscheidung 14, generischer YAML-Editor.
- **Die JVM-Optionen** — CLAUDE.md: nicht ohne Messung.

---

## 6. Die abgestimmten Antworten

Am 28.08.2026 entschieden:

| # | Frage | Antwort |
|---|---|---|
| K6 | Vier mitinstallierte Plugins oder nur Pl3xMap? | **nur Pl3xMap** — und das Lastenheft soll es auch so sagen |
| E1 | Reiterfolge | **wie vorgeschlagen** |
| E2 | 15 + 4 Werte, Sichtweite nur auf der Leistungsseite | **ja** — ein Wert an zwei Orten ist eine Fehlerquelle, und die beiden gehören neben die Kurve |
| E3 | Pixelschrift für Überschriften | **wird probiert.** Lässt sich später mit einer geänderten CSS-Variablen und einer gelöschten Datei zurücknehmen — der Rest der Gestaltung hängt nicht daran |
| E6 | `plugins.txt` dem Pi übergeben | **ja** |
| E8 | `mcs restore --probe` als Umfangserweiterung | **ja** |
