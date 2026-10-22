#!/bin/bash
# Messung des Paper-Verhaltens. Läuft INNERHALB eines
# debian:trixie-slim-Containers (linux/arm64), gestartet von
# tests/messung-paper-verhalten.sh — dort steht auch, wozu das gut ist.
#
# Kein "set -e": Eine Messung soll bis zum Ende laufen und aufschreiben, was
# sie vorfindet, auch wenn ein Einzelwert nicht zu ermitteln ist. Ein
# abgebrochener Messlauf ist wertlos.
set -uo pipefail
export DEBIAN_FRONTEND=noninteractive

trenner() { echo; echo "################ $* ################"; }

# ----------------------------------------------------------------------------
# Aufbau (wie im Abnahmetest — siehe dort für die Begründungen)
# ----------------------------------------------------------------------------
apt-get update -qq >/dev/null
apt-get install -y -qq sudo cron curl ca-certificates procps screen systemd \
                      iproute2 >/dev/null 2>&1

TESTUSER="${TESTUSER:-mcstester}"
TESTHOME="/home/$TESTUSER"
useradd -m -u 1000 -s /bin/bash "$TESTUSER"
echo "$TESTUSER ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/$TESTUSER"
chmod 440 "/etc/sudoers.d/$TESTUSER"

# systemd läuft im Container nicht als PID 1 — ein Platzhalter meldet Erfolg.
cat > /usr/local/sbin/systemctl <<'STUB'
#!/bin/bash
case "${1:-}" in
  is-active) exit 3 ;;
  *) exit 0 ;;
esac
STUB
chmod +x /usr/local/sbin/systemctl
ln -sf /usr/local/sbin/systemctl /usr/bin/systemctl

cp -r /repo "$TESTHOME/PiCraft"
rm -rf "$TESTHOME/PiCraft/.git"
rm -f "$TESTHOME/PiCraft/mcs.conf"
chown -R "$TESTUSER:$TESTUSER" "$TESTHOME/PiCraft"

trenner "Installation"
su "$TESTUSER" -c "cd $TESTHOME/PiCraft && ./install.sh --standard" >/tmp/install.log 2>&1
echo "  Exitcode: $?"

SRV="$TESTHOME/mcs/mc_server"

# ----------------------------------------------------------------------------
# Server hoch- und runterfahren
# ----------------------------------------------------------------------------
hoch() {
  # Die latest.log des VORIGEN Laufs muss WEG, bevor gestartet wird.
  #
  # Sonst steht das "Done (" von damals noch darin, und die Schleife unten
  # meldet "oben nach 1s" — ohne dass irgendetwas gestartet waere. Gemessen
  # am 01.09.2026: Genau so liefen M9a und M9b gegen einen Server, den es zu
  # dem Zeitpunkt nicht gab. RCON antwortete mit "Connection refused", und
  # die Auswertungssaetze darunter haetten daraus beinahe einen Befund
  # gemacht ("ops.json wird beim Start nicht neu geschrieben") — gemessen war
  # in Wahrheit gar nichts.
  #
  # Vorher fiel es nicht auf, weil nach dem zweiten Start nichts mehr kam,
  # das einen LAUFENDEN Server gebraucht haette. Ein falsches "oben" war
  # folgenlos, solange niemand darauf baute.
  rm -f "$SRV/logs/latest.log"
  su "$TESTUSER" -c "cd $SRV && bash start-minecraft.sh" >/tmp/start.log 2>&1 &
  local i
  for i in $(seq 1 300); do
    if grep -q 'Done (' "$SRV/logs/latest.log" 2>/dev/null; then
      echo "  (oben nach ${i}s)"; return 0
    fi
    sleep 1
  done
  echo "  SERVER KAM NICHT HOCH — Messung abgebrochen"
  tail -20 "$SRV/logs/latest.log" 2>/dev/null | sed 's/^/    /'
  return 1
}

# Antwortet RCON wirklich? "Done (" im Log heisst, dass der Server oben ist;
# es heisst nicht, dass er schon Befehle annimmt. Wer misst, ohne das zu
# pruefen, schreibt eine Fehlermeldung als Messwert auf.
rcon_bereit() {
  local i
  for i in $(seq 1 60); do
    if su "$TESTUSER" -c "cd $SRV && MCS_SERVER_PROPERTIES=$SRV/server.properties \
        python3 -c \"
import sys; sys.path.insert(0, '$TESTHOME/mcs/admin')
import rcon
rcon.befehl('list', zeitlimit=5.0)
\"" >/dev/null 2>&1; then
      echo "  (RCON antwortet nach ${i}s)"; return 0
    fi
    sleep 1
  done
  echo "  RCON ANTWORTET NICHT — die folgende Messung ist NICHT gueltig."
  return 1
}

runter() {
  su "$TESTUSER" -c "cd $SRV && bash stop-minecraft.sh" >/tmp/stop.log 2>&1
  sleep 3
}

# Der erste Start ist ein Sonderfall: Paper legt die Welt an und normalisiert
# alle Konfigurationsdateien zum ersten Mal. Erst danach lässt sich messen,
# was ein GEWÖHNLICHER Start mit einer Datei macht.
trenner "Erster Start (Welt anlegen, Dateien einmal normalisieren)"
hoch || exit 1

WELT=$(sed -n 's/^level-name=//p' "$SRV/server.properties" | tail -n1)
echo "  Welt: $WELT"

# ----------------------------------------------------------------------------
trenner "M3/M6) RCON-Antworten und abreissende Verbindungen"
# ----------------------------------------------------------------------------
# Zwei Fragen auf einmal: Wie SEHEN die Antworten aus (die Spielerseite muss
# sie zerlegen), und ueberlebt eine geteilte Verbindung einen Fehlschlag?
#
# Am 28.08.2026 gemessen: "whitelist add <name>" beendet eine geteilte
# Verbindung, und jeder weitere Befehl darauf laeuft ins Leere. Im Serverlog
# steht dazu nichts. Mit einer eigenen Verbindung je Befehl tritt es nicht
# auf. Deshalb wird hier BEIDES durchgespielt.
LOGZEILE=$(wc -l < "$SRV/logs/latest.log")
su "$TESTUSER" -c "MCS_SERVER_PROPERTIES=$SRV/server.properties python3 - <<'PYTEST'
import sys
sys.path.insert(0, '$TESTHOME/mcs/admin')
import rcon

def einzeln(b):
    'Eine eigene Verbindung je Befehl — so, wie rcon.befehl() es macht.'
    try:
        a = rcon.befehl(b, zeitlimit=20.0)
    except Exception as fehler:
        a = '<<%s: %s>>' % (type(fehler).__name__, fehler)
    print('  %-58s -> %r' % (b, a[:220]))

print(' -- eigene Verbindung je Befehl --')
for b in ('list', 'whitelist list', 'banlist players', 'banlist ips',
          'quatschbefehl-den-es-nicht-gibt',
          'whitelist add Steve', 'whitelist list',
          'op Steve', 'deop Steve',
          'ban Steve Testgrund', 'banlist players', 'pardon Steve',
          'kick Steve Testgrund',
          'ban-ip 203.0.113.7 Messung', 'banlist ips', 'pardon-ip 203.0.113.7',
          'version'):
    einzeln(b)

# M2: Gibt es die Spielzeit-Statistik unter diesem Namen? Nimmt der Server
# das Kriterium an, existiert der Statistikschluessel wirklich. Der alte
# Name play_one_minute muss abgelehnt werden.
print(' -- M2: wie heisst die Spielzeit-Statistik? --')
einzeln('scoreboard objectives add mzeit minecraft.custom:minecraft.play_time Zeit')
einzeln('scoreboard objectives add mzeit2 minecraft.custom:minecraft.play_one_minute Zeit')

print(' -- dieselbe Reihenfolge auf EINER geteilten Verbindung --')
try:
    with rcon.Rcon(zeitlimit=30.0, **rcon.rcon_einstellungen()) as v:
        for b in ('list', 'list uuids', 'whitelist list', 'whitelist on',
                  'banlist players', 'banlist ips',
                  'ban-ip 203.0.113.7 Messung', 'banlist ips',
                  'pardon-ip 203.0.113.7', 'op Steve',
                  'whitelist add Steve', 'kick Steve M', 'ban Steve M',
                  'banlist players', 'pardon Steve', 'version'):
            try:
                a = v.befehl(b)
            except Exception as fehler:
                a = '<<%s: %s>>' % (type(fehler).__name__, fehler)
            print('  %-34s -> %r' % (b, a[:120]))
except Exception as fehler:
    print('  Verbindung selbst gescheitert:', type(fehler).__name__, fehler)
PYTEST" 2>&1

echo "--- was der Server dazu ins Log geschrieben hat ---"
tail -n +"$LOGZEILE" "$SRV/logs/latest.log" | grep -viE 'RCON (Listener|Client)' \
  | tail -12 | sed 's/^/  /'
echo "  (Wenn hier nichts steht, obwohl oben eine Verbindung abriss:"
echo "   genau das ist der Befund — der Server meldet es nicht.)"

# ----------------------------------------------------------------------------
trenner "M8) Schreibt ein LAUFENDER Server die server.properties neu?"
# ----------------------------------------------------------------------------
# Der entscheidende Punkt fuer die Konfigurationsseite: Von Hand eine Marke
# setzen, dann per Befehl eine Einstellung aendern, die in derselben Datei
# steht. Ueberlebt die Marke das nicht, darf die Oberflaeche bei laufendem
# Server nicht schreiben, sondern muss vormerken.
sed -i 's/^motd=.*/motd=MARKE-WAEHREND-LAUF/' "$SRV/server.properties"
echo "  motd von Hand gesetzt: $(sed -n 's/^motd=//p' "$SRV/server.properties")"
echo "  white-list vorher:     $(sed -n 's/^white-list=//p' "$SRV/server.properties")"
su "$TESTUSER" -c "MCS_SERVER_PROPERTIES=$SRV/server.properties python3 -c \"
import sys; sys.path.insert(0,'$TESTHOME/mcs/admin'); import rcon
print('  whitelist on ->', repr(rcon.befehl('whitelist on')))
print('  difficulty peaceful ->', repr(rcon.befehl('difficulty peaceful')))
\"" 2>&1
sleep 2
echo "  motd danach:           $(sed -n 's/^motd=//p' "$SRV/server.properties")"
echo "  white-list danach:     $(sed -n 's/^white-list=//p' "$SRV/server.properties")"
echo "  difficulty danach:     $(sed -n 's/^difficulty=//p' "$SRV/server.properties")"
echo "  (motd zurueckgesetzt = der Befehl hat die ganze Datei aus dem"
echo "   Arbeitsspeicher neu geschrieben. difficulty gehoert der WELT,"
echo "   nicht der Datei — deshalb aendert es sich hier nicht.)"

# ----------------------------------------------------------------------------
trenner "M5) Stehen Geheimnisse in den Konfigurationsdateien?"
# ----------------------------------------------------------------------------
# Regel aus Korrektur K2: Jeder neue Editor muss vorher geprueft werden.
for Y in "$SRV/bukkit.yml" "$SRV/spigot.yml" \
         "$SRV/config/paper-global.yml" "$SRV/config/paper-world-defaults.yml"; do
  [ -f "$Y" ] || continue
  echo "--- $(basename "$Y") (Rechte $(stat -c '%a' "$Y")) ---"
  grep -inE 'pass|secret|token|credential' "$Y" | head -5 | sed 's/^/  /' \
    || echo "  (keine Treffer)"
done

# ----------------------------------------------------------------------------
trenner "M4a) Marken setzen, waehrend der Server LAEUFT, dann stoppen"
# ----------------------------------------------------------------------------
sed -i 's/^view-distance=.*/view-distance=7/' "$SRV/server.properties"
sed -i 's/^\( *tab-spam-increment:\) .*/\1 7/' "$SRV/config/paper-global.yml"
sed -i 's/^\( *monsters:\) .*/\1 77/' "$SRV/bukkit.yml"
echo "  gesetzt: view-distance=7, tab-spam-increment=7, monsters=77"
runter
echo "--- nach dem Stoppen ---"
echo "  view-distance:         $(sed -n 's/^view-distance=//p' "$SRV/server.properties")"
grep -nE 'tab-spam-increment' "$SRV/config/paper-global.yml" | sed 's/^/  /'
grep -nE '^ *monsters:' "$SRV/bukkit.yml" | sed 's/^/  /'
echo "  (Stehen die Werte noch da, wird beim Herunterfahren NICHTS"
echo "   neu geschrieben — entgegen der alten Annahme.)"

# ----------------------------------------------------------------------------
trenner "M4b) Marken setzen, waehrend der Server STEHT, dann starten"
# ----------------------------------------------------------------------------
printf '# MESSMARKE-KOMMENTAR\n' >> "$SRV/server.properties"
sed -i 's/^motd=.*/motd=MARKE-VOR-START/' "$SRV/server.properties"
for Y in "$SRV/bukkit.yml" "$SRV/spigot.yml" \
         "$SRV/config/paper-global.yml" "$SRV/config/paper-world-defaults.yml"; do
  [ -f "$Y" ] && sed -i '1i # MESSMARKE-YAML' "$Y"
done
echo "  server.properties: $(wc -l < "$SRV/server.properties") Zeilen, davon $(grep -c '^#' "$SRV/server.properties") Kommentare"
echo "  paper-global.yml:  $(wc -l < "$SRV/config/paper-global.yml") Zeilen, davon $(grep -c '^ *#' "$SRV/config/paper-global.yml") Kommentare"

hoch || exit 1

echo "--- server.properties nach dem Start ---"
echo "  Zeilen:                $(wc -l < "$SRV/server.properties") / Kommentare: $(grep -c '^#' "$SRV/server.properties")"
echo "  eigener Kommentar:     $(grep -q 'MESSMARKE-KOMMENTAR' "$SRV/server.properties" && echo 'noch da' || echo 'WEG')"
echo "  motd (Wert):           $(sed -n 's/^motd=//p' "$SRV/server.properties")"
echo "  view-distance (Wert):  $(sed -n 's/^view-distance=//p' "$SRV/server.properties")"
echo "  erste drei Zeilen:"; head -3 "$SRV/server.properties" | sed 's/^/    /'
echo "--- YAML nach dem Start ---"
for Y in "$SRV/bukkit.yml" "$SRV/spigot.yml" \
         "$SRV/config/paper-global.yml" "$SRV/config/paper-world-defaults.yml"; do
  [ -f "$Y" ] || continue
  printf '  %-28s fremder Kommentar: %-8s Zeilen: %s\n' "$(basename "$Y")" \
    "$(head -1 "$Y" | grep -q 'MESSMARKE-YAML' && echo 'noch da' || echo 'WEG')" \
    "$(wc -l < "$Y")"
done
grep -nE 'tab-spam-increment' "$SRV/config/paper-global.yml" | sed 's/^/  eigener Wert: /'
grep -nE '^ *monsters:' "$SRV/bukkit.yml" | sed 's/^/  eigener Wert: /'

# ----------------------------------------------------------------------------
trenner "M9a) ops.json bei LAUFENDEM Server — wie kommt man an die Stufe?"
# ----------------------------------------------------------------------------
# Die drei Fragen aus Arbeitspaket W7 (Pflichtenheft v1.1). Sie sind
# ungemessen, und solange sie es sind, wird an ops.json NICHTS geschrieben.
#
#   1. Womit laesst sich die Stufe bei laufendem Server aendern, ohne dass
#      Paper die Aenderung beim naechsten Schreiben verwirft?
#   2. Wirkt eine Aenderung an ops.json sofort oder erst beim naechsten Start?
#   3. Verhaelt sich ops.json beim Start genauso wie server.properties?
#
# Die naheliegende Annahme war bei server.properties schon einmal genau
# falsch herum (Korrektur K3) — deshalb wird auch hier gemessen und nicht
# geschlossen.
echo "  op-permission-level: $(sed -n 's/^op-permission-level=//p' "$SRV/server.properties")"
if ! rcon_bereit; then
  echo "  M9a UEBERSPRUNGEN. Ohne laufenden Server ist hier nichts zu messen,"
  echo "  und ein Ergebnis, das aus Fehlermeldungen entsteht, waere schlimmer"
  echo "  als keines."
else
su "$TESTUSER" -c "MCS_SERVER_PROPERTIES=$SRV/server.properties python3 - <<'PYOPS'
import sys
sys.path.insert(0, '$TESTHOME/mcs/admin')
import rcon

def b(befehl):
    try:
        a = rcon.befehl(befehl, zeitlimit=20.0)
    except Exception as fehler:
        a = '<<%s: %s>>' % (type(fehler).__name__, fehler)
    print('  %-40s -> %r' % (befehl, a[:200]))

print(' -- Frage 1: nimmt \"op\" ueberhaupt eine Stufe entgegen? --')
b('deop Steve')
b('op Steve')
b('op Alex 2')
b('op Alex')
b('minecraft:op Alex 3')
PYOPS" 2>&1
sleep 2
echo "--- ops.json danach ---"
cat "$SRV/ops.json" 2>/dev/null | sed 's/^/  /'; echo

echo "--- Frage 2: Hand-Aenderung der Stufe bei laufendem Server ---"
python3 - "$SRV/ops.json" <<'PYEDIT'
import json, sys
p = sys.argv[1]
try:
    daten = json.load(open(p))
except Exception as f:
    print('  ops.json nicht lesbar:', f); raise SystemExit(0)
for e in daten:
    e['level'] = 2
json.dump(daten, open(p, 'w'), indent=2)
print('  alle Stufen von Hand auf 2 gesetzt')
PYEDIT
echo "  Stufen jetzt in der Datei: $(grep -o '"level" *: *[0-9]' "$SRV/ops.json" | tr '\n' ' ')"

# Jetzt ein Befehl, der ops.json WIRKLICH aendert. Bei server.properties war
# genau das der Ausloeser: Ein Nullvorgang genuegte nicht, die Aenderung
# musste echt sein.
su "$TESTUSER" -c "MCS_SERVER_PROPERTIES=$SRV/server.properties python3 -c \"
import sys; sys.path.insert(0,'$TESTHOME/mcs/admin'); import rcon
print('  op Notch ->', repr(rcon.befehl('op Notch', zeitlimit=20.0)))
\"" 2>&1
sleep 2
echo "  Stufen NACH dem Schreibvorgang: $(grep -o '"level" *: *[0-9]' "$SRV/ops.json" | tr '\n' ' ')"
echo "  (Stehen dort wieder 4en, hat Paper die Datei aus dem Arbeitsspeicher"
echo "   neu geschrieben und die Hand-Aenderung verworfen — dieselbe Falle"
echo "   wie bei server.properties. Stehen noch 2en da, ist es anders.)"
fi

# ----------------------------------------------------------------------------
trenner "M7) Pl3xMap und die belegten Ports"
# ----------------------------------------------------------------------------
if [ -f "$SRV/plugins/Pl3xMap/config.yml" ]; then
  grep -A2 -E 'internal-webserver|^ *enabled:|^ *bind:|^ *port:' \
    "$SRV/plugins/Pl3xMap/config.yml" 2>/dev/null | grep -vE '^\s*#' \
    | head -12 | sed 's/^/  /'
else
  echo "  Pl3xMap ist nicht installiert."
fi
echo "--- lauschende Ports ---"
ss -ltn 2>/dev/null | sed 's/^/  /'
echo "  (25565 Spielserver, 25575 RCON — auf ALLEN Karten, siehe K1 —,"
echo "   8080 Pl3xMap. Die Weboberflaeche weicht deshalb auf 8081 aus.)"

runter

# ----------------------------------------------------------------------------
trenner "M9b) ops.json bei STEHENDEM Server — ueberlebt eine Aenderung den Start?"
# ----------------------------------------------------------------------------
# Frage 3 aus W7. Bei server.properties war die Antwort ueberraschend: Beim
# Stoppen ueberlebte eine Handaenderung, beim STARTEN wurde sie verworfen.
# Ob ops.json sich genauso verhaelt, ist die eigentliche Frage — die
# naheliegende Annahme ("wie die anderen Dateien auch") ist genau die, die
# hier schon einmal falsch war.
python3 - "$SRV/ops.json" <<'PYEDIT'
import json, sys
p = sys.argv[1]
try:
    daten = json.load(open(p))
except Exception as f:
    print('  ops.json nicht lesbar:', f); raise SystemExit(0)
for e in daten:
    e['level'] = 3
json.dump(daten, open(p, 'w'), indent=2)
print('  bei STEHENDEM Server alle Stufen auf 3 gesetzt')
PYEDIT
echo "  Stufen vor dem Start:  $(grep -o '"level" *: *[0-9]' "$SRV/ops.json" | tr '\n' ' ')"
echo "  Zeilen vor dem Start:  $(wc -l < "$SRV/ops.json")"

hoch || exit 1
# Auch hier erst die Bereitschaft abwarten: "Done (" im Log sagt, dass der
# Server oben ist — ops.json schreibt er womoeglich erst danach. Wer zu
# frueh hinsieht, misst den Zustand VOR dem Schreiben und haelt ihn fuer
# das Ergebnis.
rcon_bereit || echo "  ACHTUNG: Der folgende Vergleich ist NICHT gueltig."
echo "--- direkt nach dem Start ---"
echo "  Stufen:                $(grep -o '"level" *: *[0-9]' "$SRV/ops.json" | tr '\n' ' ')"
echo "  Zeilen:                $(wc -l < "$SRV/ops.json")"
echo "  (Stehen die 3en noch da, wird ops.json beim Start NICHT neu"
echo "   geschrieben — anders als server.properties. Stehen dort wieder"
echo "   andere Werte, verhaelt es sich genauso.)"

echo "--- und hat der Server die 3 auch GELESEN? ---"
# Die entscheidende Frage, und sie ist mit der Zeile darueber NICHT
# beantwortet: Dass die Datei unveraendert blieb, heisst nur, dass niemand
# sie neu geschrieben hat. Ob im Arbeitsspeicher 3 oder 4 steht, sagt sie
# nicht.
#
# Herausfinden laesst es sich, indem man Paper ZWINGT, die Datei aus dem
# Arbeitsspeicher neu zu schreiben (ein "op" auf jemand Neues, siehe M9a).
# Was danach bei den ANDEREN Eintraegen steht, kommt aus dem Speicher.
su "$TESTUSER" -c "MCS_SERVER_PROPERTIES=$SRV/server.properties python3 -c \"
import sys; sys.path.insert(0,'$TESTHOME/mcs/admin'); import rcon
print('  op Herobrine ->', repr(rcon.befehl('op Herobrine', zeitlimit=20.0)))
\"" 2>&1
sleep 2
echo "  Stufen nach erzwungenem Neuschreiben: $(grep -o '"level" *: *[0-9]' "$SRV/ops.json" | tr '\n' ' ')"
echo "  (Stehen bei den ALTEN Eintraegen 3en, hat der Server die Datei beim"
echo "   Start gelesen — dann ist Schreiben bei GESTOPPTEM Server der Weg."
echo "   Stehen dort 4en, hat er die Handaenderung beim Start ignoriert und"
echo "   sie erst jetzt ueberschrieben.)"
runter
echo "--- nach dem Stoppen ---"
echo "  Stufen:                $(grep -o '"level" *: *[0-9]' "$SRV/ops.json" | tr '\n' ' ')"

# ----------------------------------------------------------------------------
trenner "M1) Spielerdateien"
# ----------------------------------------------------------------------------
# Grundlage der Spielerseite. Paper schreibt sie selbst; die Oberflaeche
# liest sie und aendert sie ueber RCON, nie direkt.
for J in usercache.json whitelist.json ops.json banned-players.json banned-ips.json; do
  echo "--- $J ---"
  if [ -f "$SRV/$J" ]; then
    head -c 400 "$SRV/$J" | sed 's/^/  /'; echo
  else
    echo "  (fehlt)"
  fi
done
echo "--- stats/ und playerdata/ ---"
ls "$SRV/$WELT/stats" "$SRV/$WELT/playerdata" 2>/dev/null | sed 's/^/  /' \
  || echo "  (gibt es erst, wenn zum ersten Mal jemand gespielt hat)"

trenner "FERTIG"
echo "Die Auswertung dieser Messung steht in"
echo "docs/pflichtenheft-etappe-c.md, Abschnitt 0."
