#!/bin/bash
#
# pruefung-backup.sh — Rotation und Dauerarchiv gegen unbrauchbare Zahlen,
# seit dem 24.10.2026 auch das Online-Backup: Neustart mittendrin, Zweitziel
# auf derselben Platte, Dauerarchiv auf einer anderen, Nachricht bei Abbruch.
#
# Warum ein eigener Test: Am 23.09.2026 fiel auf, dass zahl_aus_conf seine
# Warnung in den Rueckgabewert schrieb. Aus "10" wurde "Datum | WARNUNG ... 10",
# die Rotation loeschte still nichts mehr, das Dauerarchiv fiel aus — und
# der Lauf meldete Erfolg. Kein bestehender Test ging diesen Pfad, und der
# Container-Abnahmetest laeuft nur von Hand.
#
# Laeuft in einem Wegwerfverzeichnis mit gestopptem "Server" und dauert unter
# einer Sekunde. Aufruf: make backup
#
# Braucht, was auch das Backup-Skript braucht: GNU-Werkzeuge (touch -d,
# find -printf) und flock — also Linux, wie der Pi. Hier stand "nur bash und
# tar"; auf einem Mac waere "make" damit dauerhaft rot gewesen (Zweitmeinung
# zu Durchgang 1). Fehlt etwas, wird LAUT uebersprungen, wie pyflakes im
# Makefile — ein gruenes "make" sagt dann weniger, und das steht da.

set -euo pipefail

PROBE="$(mktemp)"
if ! command -v flock >/dev/null 2>&1 || ! touch -d "-1 day" "$PROBE" 2>/dev/null \
   || ! find "$PROBE" -printf '' >/dev/null 2>&1; then
  rm -f "$PROBE"
  echo "== Backup: Rotation und Dauerarchiv =="
  echo "  !! UEBERSPRUNGEN — hier fehlen flock oder GNU touch/find (kein Linux?)."
  echo "     Das Backup-Skript braucht sie auch; geprueft wird auf dem Pi."
  exit 0
fi
rm -f "$PROBE"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"; [ -z "${ANDERS:-}" ] || rm -rf "$ANDERS"' EXIT

mkdir -p "$TMP/srv/welt" "$TMP/bak" "$TMP/arch"
echo x > "$TMP/srv/welt/level.dat"
echo "level-name=welt" > "$TMP/srv/server.properties"
cp "$REPO/server/lib-konsole.sh" "$TMP/srv/"

FEHLER=0
lauf() {   # lauf BEHALTEN ARCHIV_JEDES ALTE_BACKUPS
  rm -f "$TMP/bak/"* "$TMP/bak/.letzter-fehler" "$TMP/arch/"* "$TMP/arch/.laufzaehler"
  local I
  for ((I = 1; I <= $3; I++)); do
    touch -d "-$I day" "$TMP/bak/backup_alt$I.tar.gz"
  done
  cat > "$TMP/c.conf" <<ENDE
MCS_SERVER_DIR=$TMP/srv
MCS_BACKUP_DIR=$TMP/bak
MCS_ARCHIV_DIR=$TMP/arch
MCS_SCREEN_SESSION=pruefung-gibt-es-nicht
MCS_BACKUP_BEHALTEN=$1
MCS_ARCHIV_JEDES=$2
MCS_BENACHRICHTIGUNG=/gibt/es/nicht
ENDE
  MCS_CONF="$TMP/c.conf" bash "$REPO/backup/minecraft-backup.sh" >/dev/null 2>"$TMP/err" || {
    echo "  FEHLER: Backup-Lauf ($1/$2) endete mit Fehler:"; sed 's/^/    /' "$TMP/err"; FEHLER=1; }
  if grep -qE 'integer expression|value too great|syntax error' "$TMP/err"; then
    echo "  FEHLER: Rechenfehler im Lauf ($1/$2):"; sed 's/^/    /' "$TMP/err"; FEHLER=1
  fi
}

pruefe() {   # pruefe TEXT IST SOLL
  if [ "$2" = "$3" ]; then echo "  ok  $1 ($2)"; else echo "  FEHLER: $1 — ist $2, soll $3"; FEHLER=1; fi
}

echo "== Backup: Rotation und Dauerarchiv =="

# Keine Zahl: Es muss der STANDARD gelten (10 behalten, Dauerarchiv an).
lauf zehn elf 12
pruefe "keine Zahl -> Standard, Backups behalten" "$(ls "$TMP/bak/"backup_*.tar.gz | wc -l)" 10
pruefe "keine Zahl -> Standard, Dauerarchiv"      "$(ls "$TMP/arch/"*.tar.gz 2>/dev/null | wc -l)" 1

# 0 heisst "aus": nichts loeschen, kein Dauerarchiv.
lauf 0 0 12
pruefe "0 -> Rotation aus"      "$(ls "$TMP/bak/"backup_*.tar.gz | wc -l)" 13
pruefe "0 -> Dauerarchiv aus"   "$(ls "$TMP/arch/"*.tar.gz 2>/dev/null | wc -l)" 0

# ----------------------------------------------------------------------------
# Online-Backup (seit 24.10.2026): Ein falsches screen spielt den Server. Es
# nennt eine Sitzung und bestaetigt "save-all" im Log. Mit NEUSTART=1 bekommt
# die Sitzung dabei eine neue Kennung — als haette jemand waehrend des
# Backups "Neustart" gedrueckt.
# ----------------------------------------------------------------------------
mkdir -p "$TMP/bin" "$TMP/srv/logs"
cat > "$TMP/bin/screen" <<ENDE
#!/bin/bash
case "\$*" in
  *-ls*)      cat "$TMP/sitzung" ;;
  *save-all*) echo "[04:00:01 INFO]: Saved the game" >> "$TMP/srv/logs/latest.log"
              [ "\${NEUSTART:-0}" != 1 ] || printf '\t4712.pruefung\t(Detached)\n' > "$TMP/sitzung" ;;
esac
ENDE
printf '#!/bin/bash\necho "$1" >> "%s/meldungen"\n' "$TMP" > "$TMP/melder"
chmod +x "$TMP/bin/screen" "$TMP/melder"

online() {   # online NEUSTART(0|1) ARCHIV_DIR ARCHIV_JEDES [EXTERN_DIR]
  cat > "$TMP/c.conf" <<ENDE
MCS_SERVER_DIR=$TMP/srv
MCS_BACKUP_DIR=$TMP/bak
MCS_ARCHIV_DIR=$2
MCS_ARCHIV_JEDES=$3
MCS_EXTERN_DIR=${4:-}
MCS_SCREEN_SESSION=pruefung
MCS_BENACHRICHTIGUNG=$TMP/melder
ENDE
  printf '\t4711.pruefung\t(Detached)\n' > "$TMP/sitzung"
  : > "$TMP/srv/logs/latest.log"
  rm -f "$TMP/bak/"* "$TMP/bak/.letzter-fehler" "$TMP/meldungen"
  NEUSTART="$1" PATH="$TMP/bin:$PATH" MCS_CONF="$TMP/c.conf" \
    bash "$REPO/backup/minecraft-backup.sh" >/dev/null 2>&1
}

echo "== Backup: Online, Neustart, Zweitziel =="

online 0 "$TMP/arch" 0 && RC=0 || RC=$?
pruefe "Online-Backup gelingt (Gegenprobe)" "$RC $(ls "$TMP/bak/"backup_*.tar.gz 2>/dev/null | wc -l)" "0 1"

online 1 "$TMP/arch" 0 && RC=0 || RC=$?
pruefe "Neustart während des Backups: verworfen" "$RC $(ls "$TMP/bak/"backup_*.tar.gz 2>/dev/null | wc -l)" "1 0"
pruefe "Neustart während des Backups: Merkzettel" \
  "$(grep -c 'gestoppt oder gestartet' "$TMP/bak/.letzter-fehler" 2>/dev/null)" 1

# Ein Abbruch ohne eigenen Merkzettel muss trotzdem eine Nachricht schicken.
# Ausgeloest mit einem Dauerarchiv, das sich nicht anlegen laesst.
online 0 /proc/picraft-gibt-es-nicht 1 && RC=0 || RC=$?
pruefe "unerwarteter Abbruch: Nachricht verschickt" \
  "$RC $(grep -cx 'Backup fehlgeschlagen' "$TMP/meldungen" 2>/dev/null)" "1 1"

# Ein Zweitziel auf derselben Platte — etwa ein nicht eingehaengter
# Einhaengepunkt — bekommt keine "Zweitkopie".
mkdir -p "$TMP/extern"
online 0 "$TMP/arch" 0 "$TMP/extern" && RC=0 || RC=$?
pruefe "Zweitziel auf derselben Platte: keine Kopie" "$RC $(ls "$TMP/extern" | wc -l)" "0 0"
pruefe "Zweitziel auf derselben Platte: gemeldet" "$(grep -c 'derselben Platte' "$TMP/bak/backup.log")" 1

# Gegenprobe auf einem anderen Dateisystem: Ohne sie bestuende die Pruefung
# oben auch, wenn stat nichts liefert und JEDE Zweitkopie ausfiele. Zugleich
# der Weg ueber den Zwischennamen beim Dauerarchiv (dort scheitert ln).
if [ -d /dev/shm ] && [ "$(stat -c %d /dev/shm)" != "$(stat -c %d "$TMP")" ]; then
  ANDERS="$(mktemp -d -p /dev/shm)"
  mkdir -p "$ANDERS/extern"
  online 0 "$ANDERS/arch" 1 "$ANDERS/extern" && RC=0 || RC=$?
  pruefe "andere Platte: Zweitkopie angelegt" \
    "$RC $(ls "$ANDERS/extern/"backup_*.tar.gz 2>/dev/null | wc -l)" "0 1"
  pruefe "andere Platte: Dauerarchiv kopiert, kein Rest" \
    "$(ls "$ANDERS/arch/"backup_*.tar.gz 2>/dev/null | wc -l) $(find "$ANDERS/arch" -name '.unfertig-*' | wc -l)" "1 0"
else
  echo "  !! UEBERSPRUNGEN — kein zweites Dateisystem (/dev/shm) für die Gegenprobe."
  echo "     Zweitziel und Dauerarchiv auf anderer Platte sind hier UNGEPRUEFT."
fi

exit "$FEHLER"
