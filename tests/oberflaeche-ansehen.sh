#!/bin/bash
#
# oberflaeche-ansehen.sh — Die Weboberfläche ansehen, ohne einen Pi.
#
# Warum es das gibt: Die Dateien unter admin/templates/ sind
# Jinja-VORLAGEN, keine fertigen HTML-Seiten. Wer eine davon im Browser
# öffnet, sieht `{% extends %}` und leere Platzhalter — die Werte setzt
# erst Flask ein. Um die Oberfläche wirklich anzusehen, braucht es also
# einen laufenden Server.
#
# Auf dem Pi ist das der Dienst mcs-admin.service. Auf dem
# Entwicklerrechner gibt es weder Pi noch Minecraft-Server — und genau
# dort will man beim Bauen einer Seite nachsehen, ob sie gut aussieht.
#
# Dieses Skript legt deshalb eine ATTRAPPEN-Installation in einem
# temporären Verzeichnis an: ein paar Spieler, ein Backup, zwei Tage
# Messwerte mit einem Ruckler drin. Damit sehen die Seiten aus wie im
# Betrieb, ohne dass irgendetwas Echtes läuft.
#
# Aufruf aus dem Repo-Verzeichnis:
#   ./tests/oberflaeche-ansehen.sh
#
# Danach im Browser:  http://127.0.0.1:8099
#   Benutzer: admin     Passwort: geheim
#
# Beenden mit Strg+C. Das Verzeichnis wird dabei nicht gelöscht — beim
# nächsten Aufruf ist alles wieder da, einschließlich der Messwerte.
#
# WICHTIG: Das ist ein Ansichtsexemplar, kein Test. Es startet keinen
# Minecraft-Server, es gibt kein RCON, und der Dienstzustand ist
# "unbekannt", weil auf einem Mac kein systemctl läuft. Was hier gut
# aussieht, muss auf dem Pi noch einmal angesehen werden — siehe
# PRUEFEN-AUF-DEM-PI.md.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ATTRAPPE="${MCS_ANSICHT_DIR:-${TMPDIR:-/tmp}/picraft-ansicht}"
PORT="${MCS_ANSICHT_PORT:-8099}"

echo "===== PiCraft Oberfläche ansehen ====="
echo "Attrappen-Installation: $ATTRAPPE"
echo ""

# ----------------------------------------------------------------------------
# 1) Flask besorgen
# ----------------------------------------------------------------------------
# Auf dem Pi installiert install-admin.sh python3-flask aus den
# Paketquellen. Auf einem Entwicklerrechner ist es meist nicht da, und
# systemweit installieren will man dafür nichts — also eine eigene kleine
# Umgebung daneben.
VENV="$ATTRAPPE/.venv"
if [ ! -x "$VENV/bin/python" ]; then
  echo "== Flask-Umgebung anlegen (einmalig) =="
  mkdir -p "$ATTRAPPE"
  python3 -m venv "$VENV"
  "$VENV/bin/pip" install --quiet --upgrade pip
  # PyYAML wie auf dem Pi (dort python3-yaml): Ohne echten Parser kann der
  # Expertenmodus kaputtes YAML nicht erkennen, und dann prueft man hier
  # etwas anderes als im Betrieb.
  "$VENV/bin/pip" install --quiet flask pyyaml
fi
echo "Flask: $("$VENV/bin/python" -c 'import flask; print(flask.__version__)')"

# ----------------------------------------------------------------------------
# 2) Attrappen-Installation anlegen
# ----------------------------------------------------------------------------
# Nur, wenn sie noch nicht existiert: Wer beim Bauen einer Seite etwas
# ausprobiert hat, soll es beim nächsten Aufruf wiederfinden.
if [ ! -f "$ATTRAPPE/mcs.conf" ]; then
  echo "== Attrappen-Daten anlegen =="
  mkdir -p "$ATTRAPPE/mc_server/logs" "$ATTRAPPE/mc_server/world/stats" \
           "$ATTRAPPE/mc_server/world/players/stats" \
           "$ATTRAPPE/mc_server/config" "$ATTRAPPE/mcs_backup" "$ATTRAPPE/admin"

  cat > "$ATTRAPPE/mcs.conf" <<CONF
MCS_USER=$(id -un)
MCS_DIR=$ATTRAPPE
MCS_SERVER_DIR=$ATTRAPPE/mc_server
MCS_BACKUP_DIR=$ATTRAPPE/mcs_backup
MCS_ADMIN_DIR=$ATTRAPPE/admin
MCS_PLAYER_ACTIVITY_LOG=$ATTRAPPE/player_activity.log
MCS_MINECRAFT_LOG=$ATTRAPPE/mc_server/logs/latest.log
MCS_SERVER_PROPERTIES=$ATTRAPPE/mc_server/server.properties
MCS_ACTION_LOG=$ATTRAPPE/admin/actions.log
MCS_METRIK_DB=$ATTRAPPE/admin/metrik.db
CONF

  # Eine server.properties wie nach dem ersten Start: ohne Kommentare,
  # alphabetisch — so, wie Paper sie hinterlässt (Korrektur K3).
  #
  # Vollstaendig, nicht nur die interessanten Zeilen: Paper schreibt beim
  # ersten Start ALLE Schluessel hinein. Eine luecken hafte Attrappe fuehrt
  # sonst zu Fehlern, die es im Betrieb gar nicht gibt — beim Bauen der
  # Konfigurationsseite zeigte sie deswegen kurzzeitig "Nether: aus".
  cat > "$ATTRAPPE/mc_server/server.properties" <<'PROPS'
#Minecraft server properties
#Fri Aug 28 15:40:58 UTC 2026
allow-flight=true
allow-nether=true
difficulty=easy
enable-command-block=false
enable-rcon=false
entity-broadcast-range-percentage=85
gamemode=survival
hardcore=false
level-name=world
max-players=5
motd=Ein PiCraft Server
network-compression-threshold=256
online-mode=true
pause-when-empty-seconds=300
pvp=true
region-file-compression=lz4
server-port=25565
simulation-distance=10
spawn-protection=0
sync-chunk-writes=false
view-distance=16
white-list=true
PROPS

  # Zwei YAML-Dateien fuer den Expertenmodus. paper-global.yml enthaelt
  # absichtlich den Velocity-Schluessel: An ihm sieht man, ob das Verdecken
  # von Geheimnissen wirkt (Korrektur K5).
  cat > "$ATTRAPPE/mc_server/bukkit.yml" <<'YML'
settings:
  allow-end: true
spawn-limits:
  monsters: 70
  animals: 10
  water-animals: 5
  ambient: 15
YML
  cat > "$ATTRAPPE/mc_server/config/paper-global.yml" <<'YML'
_version: 29
chunk-system:
  io-threads: -1
  worker-threads: -1
spam-limiter:
  incoming-packet-threshold: 300
  tab-spam-increment: 1
  tab-spam-limit: 500
proxies:
  velocity:
    enabled: false
    online-mode: false
    secret: 'nur-eine-attrappe'
YML

  # Ein Backup von vor zwei Stunden.
  dd if=/dev/zero of="$ATTRAPPE/mcs_backup/backup_ansicht.tar.gz" \
     bs=1024 count=3072 status=none
  cat > "$ATTRAPPE/mcs_backup/backup.log" <<'LOG'
2026-08-28 04:00:01 | Server läuft — starte Online-Backup (ohne Unterbrechung für Spieler).
2026-08-28 04:02:47 | Backup geprüft und in Ordnung: backup_ansicht.tar.gz (3G, 166s, Inhalt: world world_nether)
LOG

  cat > "$ATTRAPPE/player_activity.log" <<'LOG'
Spieler-Aktivitätslog (PiCraft)
------------------------------
2026-08-26 18:02:11 | Milo meldet sich an von 192.168.1.77:52001
2026-08-26 18:02:12 | Milo ist dem Spiel beigetreten
2026-08-28 15:41:01 | Kaya meldet sich an von 192.168.1.44:51234
2026-08-28 15:41:03 | Kaya ist dem Spiel beigetreten
2026-08-28 16:02:54 | Jonas meldet sich an von 192.168.1.51:49888
2026-08-28 16:02:55 | Jonas ist dem Spiel beigetreten
2026-08-28 16:18:40 | Jonas hat das Spiel verlassen
LOG

  # Aus diesem Log liest die Oberfläche, wer gerade online ist: wer
  # "joined" hat und noch nicht "left" ist.
  cat > "$ATTRAPPE/mc_server/logs/latest.log" <<'LOG'
[15:40:58] [Server thread/INFO]: Done (9.499s)! For help, type "help"
[15:41:02] [User Authenticator #1/INFO]: UUID of player Kaya is 8667ba71-b85a-4004-af54-457a9734eed7
[15:41:03] [Server thread/INFO]: Kaya joined the game
[16:02:55] [Server thread/INFO]: Jonas joined the game
[16:18:40] [Server thread/INFO]: Jonas left the game
LOG

  cat > "$ATTRAPPE/admin/actions.log" <<'LOG'

[2026-08-28T15:12:04] START backup_now: /usr/bin/bash backup.sh
LOG

  # Die Tafel "Paper" auf der Konfigurationsseite: ein installierter Build
  # und eine Notiz, wie sie "mcs update --pruefen" schreibt -- mit einem
  # neueren Build und einer Version in Vorbereitung, damit alle Zweige der
  # Tafel zu sehen sind. Der Knopf selbst ruft ins Leere (kein Skript in
  # der Attrappe) und zeigt dann die Fehlermeldung.
  printf 'version=26.2\nbuild=119\nsha256=0\n' > "$ATTRAPPE/mc_server/paper.installiert"
  cat > "$ATTRAPPE/mc_server/paper.verfuegbar" <<'NOTIZ'
geprueft=2026-08-28T15:00:00+02:00
version=26.2
neuester_build=129
neuere_stabil=
neuere_beta=26.3
NOTIZ

  # Die vier Dateien, aus denen die Spielerseite liest.
  cat > "$ATTRAPPE/mc_server/usercache.json" <<'JSON'
[{"uuid":"8667ba71-b85a-4004-af54-457a9734eed7","name":"Kaya","expiresOn":"2026-09-28 13:48:46 +0000"},
 {"uuid":"11111111-2222-3333-4444-555555555555","name":"Jonas","expiresOn":"2026-09-28 13:48:46 +0000"},
 {"uuid":"99999999-8888-7777-6666-555555555555","name":"Milo","expiresOn":"2026-09-28 13:48:46 +0000"}]
JSON
  cat > "$ATTRAPPE/mc_server/whitelist.json" <<'JSON'
[{"uuid":"8667ba71-b85a-4004-af54-457a9734eed7","name":"Kaya"},
 {"uuid":"11111111-2222-3333-4444-555555555555","name":"Jonas"}]
JSON
  cat > "$ATTRAPPE/mc_server/ops.json" <<'JSON'
[{"uuid":"8667ba71-b85a-4004-af54-457a9734eed7","name":"Kaya","level":4,"bypassesPlayerLimit":false}]
JSON
  cat > "$ATTRAPPE/mc_server/banned-players.json" <<'JSON'
[{"uuid":"99999999-8888-7777-6666-555555555555","name":"Milo","created":"2026-08-20 21:03:11 +0000","source":"Kaya","expires":"forever","reason":"Hat den Bahnhof gesprengt"}]
JSON
  # Zwei Weltformate, mit Absicht: Seit der Formatumstellung liegen die
  # Statistiken unter <welt>/players/stats/, davor lagen sie in
  # <welt>/stats/. Lag hier nur eines von beidem, prüfte der Test genau den
  # Zweig nicht, der auf dem Pi wirklich benutzt wird — am 29.08.2026 fiel
  # deshalb auf, dass die Spielzeit dort immer leer blieb (C-P7).
  echo '{"stats":{"minecraft:custom":{"minecraft:play_time":1834200}},"DataVersion":4082}' \
    > "$ATTRAPPE/mc_server/world/players/stats/8667ba71-b85a-4004-af54-457a9734eed7.json"
  echo '{"stats":{"minecraft:custom":{"minecraft:play_time":216000}},"DataVersion":4082}' \
    > "$ATTRAPPE/mc_server/world/stats/11111111-2222-3333-4444-555555555555.json"
fi

# ----------------------------------------------------------------------------
# 3) Messwerte für die Kurven
# ----------------------------------------------------------------------------
# Zwei Tage mit einem plausiblen Tagesverlauf: abends mehr Spieler, dadurch
# mehr Last und höhere Temperatur — und ein Ruckler, damit die TPS-Kurve
# etwas zu zeigen hat. Ohne den sähe man eine gerade Linie bei 20 und
# wüsste nicht, ob die Kurve überhaupt funktioniert.
if [ ! -f "$ATTRAPPE/admin/metrik.db" ]; then
  echo "== Messwerte erzeugen =="
  ( cd "$REPO_DIR/admin" && MCS_METRIK_DB="$ATTRAPPE/admin/metrik.db" \
    "$VENV/bin/python" - ) <<'PY'
import math, sys, time
sys.path.insert(0, ".")
import metrik

jetzt = time.time()
for i in range(2 * 24 * 60):
    t = jetzt - i * 60
    stunde = time.localtime(t).tm_hour
    abend = 1.0 if 17 <= stunde <= 23 else 0.2
    spieler = int(abend * 4) + (1 if 19 <= stunde <= 22 else 0)
    cpu, tps, mspt = 12 + 40 * abend + 6 * math.sin(i / 25.0), 20.0, 3.0 + 8 * abend
    if 700 < i < 730:                      # der Ruckler von gestern Abend
        tps, mspt, cpu = 14.8, 46.0, 92.0
    metrik.schreiben({"cpu": round(cpu, 1), "ram": round(38 + 14 * abend, 1),
                      "platte": 78.0, "temp": round(48 + 14 * abend, 1),
                      "tps": tps, "mspt": round(mspt, 1), "spieler": spieler},
                     zeitpunkt=t)
print("  %d Messwerte angelegt." % metrik.anzahl())
PY
fi

# ----------------------------------------------------------------------------
# 4) Starten
# ----------------------------------------------------------------------------
echo ""
echo "================================================================"
echo "  http://127.0.0.1:$PORT"
echo ""
echo "  Benutzer: admin"
echo "  Passwort: geheim"
echo ""
echo "  Beenden: Strg+C"
echo "================================================================"
echo ""

cd "$REPO_DIR/admin"
export MCS_CONF="$ATTRAPPE/mcs.conf"
export MCS_ADMIN_USER=admin
export MCS_ADMIN_PASSWORD=geheim
export MCS_ADMIN_SECRET=nur-zum-ansehen-nicht-geheim
exec "$VENV/bin/python" app.py --host 127.0.0.1 --port "$PORT"
