#!/bin/bash
#
# pruefung-backup.sh — Rotation und Dauerarchiv gegen unbrauchbare Zahlen.
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
trap 'rm -rf "$TMP"' EXIT

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

exit "$FEHLER"
