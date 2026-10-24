#!/bin/bash
#
# pruefung-kopien.sh — USB-Kopie und Cloud-Kopie in einem Wegwerfverzeichnis.
#
# Warum ein eigener Test: Beide Kopien LÖSCHEN — auf dem Stick, um Platz zu
# schaffen, in der Cloud, um nach Zahl aufzuräumen. Das sind die Stellen,
# an denen ein Backup-Werkzeug Daten vernichtet, statt sie zu retten
# (Lehre aus MCS_BACKUP_BEHALTEN=0, 31.08.2026). Geprüft wird deshalb vor
# allem, was NICHT gelöscht werden darf: fremde Dateien auf dem Stick, das
# Weltarchiv in der Cloud, und alles, wenn der Backup-Ordner plötzlich leer
# ist.
#
# Die Cloud ist hier ein Ordner, verschlüsselt mit rclone crypt — dasselbe
# Verfahren wie gegen Google Drive, nur ohne Netz. Fehlt rclone, wird dieser
# Teil LAUT übersprungen (Leitsatz 5).
#
# Nicht hier, weil es root und ein Gerät braucht: Einhängen, LED, udev. Das
# steht in PRUEFEN-AUF-DEM-PI.md und wurde am 22.10.2026 mit Loop-Geräten
# (exFAT, FAT32) geprüft.
#
# Aufruf: make kopien

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

FEHLER=0
pruefe() {   # pruefe TEXT IST SOLL
  if [ "$2" = "$3" ]; then echo "  ok  $1 ($2)"; else echo "  FEHLER: $1 — ist $2, soll $3"; FEHLER=1; fi
}

# Echte kleine Archive: Die Probe der Cloud-Kopie liest sie mit tar und sucht
# die level.dat der Welt, deren Name NICHT "world" ist (CLAUDE.md).
mkdir -p "$TMP/srv/welt" "$TMP/bak" "$TMP/arch"
echo "level-name=welt" > "$TMP/srv/server.properties"
backup_anlegen() {   # backup_anlegen ZEITSTEMPEL [ORDNER]
  head -c 20000 /dev/urandom > "$TMP/srv/welt/level.dat"
  tar -czf "${2:-$TMP/bak}/backup_$1.tar.gz" -C "$TMP/srv" welt
}
for T in 2026-10-0{1,2,3,4,5}_04-00-00; do backup_anlegen "$T"; done
backup_anlegen 2026-09-01_04-00-00 "$TMP/arch"
backup_anlegen 2026-09-11_04-00-00 "$TMP/arch"
echo "Lies mich" > "$TMP/arch/LIESMICH.md"

# ============================================================================
echo "== USB-Kopie: Datei-Teil =="
# ============================================================================
STICK="$TMP/stick"
mkdir -p "$STICK/PiCraft-Backups" "$STICK/Urlaub"
echo "foto" > "$STICK/Urlaub/bild.jpg"
echo "eigene" > "$STICK/notiz.txt"
# Ein halbes Archiv vom letzten Mal, und eines unter dem Endnamen, das
# FREMD aussieht, aber im eigenen Ordner liegt: das darf die Rotation nehmen.
echo "halb" > "$STICK/PiCraft-Backups/.unfertig-backup_2026-09-30_04-00-00.tar.gz"
for T in 2026-09-2{1,2,3}_04-00-00; do echo alt > "$STICK/PiCraft-Backups/backup_$T.tar.gz"; done
# Ein Symlink, der wie das neueste Backup aussieht: Er darf nie kopiert
# werden (Kopf von usb-kopie.sh — sonst trüge root /etc/shadow auf den Stick).
ln -s "$TMP/srv/server.properties" "$TMP/bak/backup_2099-01-01_00-00-00.tar.gz"

usb() { MCS_BACKUP_DIR="$TMP/bak" MCS_USB_BEHALTEN="$1" MCS_USB_LED="" \
          bash "$REPO/backup/usb-kopie.sh" --verzeichnis "$STICK" >"$TMP/usb.out" 2>&1; }

usb 2 || { echo "  FEHLER: usb-kopie.sh endete mit Fehler:"; sed 's/^/    /' "$TMP/usb.out"; FEHLER=1; }
pruefe "das neueste echte Backup liegt auf dem Stick" \
  "$(find "$STICK/PiCraft-Backups/" -name 'backup_2026-10-05*' | wc -l | tr -d ' ')" 1
pruefe "identisch mit dem Original" \
  "$(cmp -s "$TMP/bak/backup_2026-10-05_04-00-00.tar.gz" "$STICK/PiCraft-Backups/backup_2026-10-05_04-00-00.tar.gz" && echo ja || echo nein)" ja
pruefe "der Symlink wurde nicht kopiert" "$(find "$STICK/PiCraft-Backups/" -name '*2099*' | wc -l | tr -d ' ')" 0
pruefe "es bleiben die neuesten 2" "$(ls "$STICK/PiCraft-Backups/"backup_*.tar.gz | wc -l | tr -d ' ')" 2
pruefe "das zweitneueste ist das jüngste alte" \
  "$(ls "$STICK/PiCraft-Backups/"backup_*.tar.gz | head -n1 | xargs basename)" "backup_2026-09-23_04-00-00.tar.gz"
pruefe "das halbe Archiv ist weg" "$(find "$STICK/PiCraft-Backups/" -name '.unfertig-*' | wc -l | tr -d ' ')" 0
pruefe "fremde Dateien unberührt" "$(cat "$STICK/Urlaub/bild.jpg") $(cat "$STICK/notiz.txt")" "foto eigene"
pruefe "LIESMICH.txt liegt dabei" "$([ -s "$STICK/PiCraft-Backups/LIESMICH.txt" ] && echo ja || echo nein)" ja
pruefe "die letzte Zeile ist das Ergebnis" "$(tail -n1 "$TMP/usb.out" | grep -c 'auf dem Stick')" 1

usb 2 || FEHLER=1
pruefe "zweiter Lauf: nichts neu kopiert" "$(grep -c 'liegt schon' "$TMP/usb.out")" 1
pruefe "zweiter Lauf: Bestand gleich" "$(ls "$STICK/PiCraft-Backups/"backup_*.tar.gz | wc -l | tr -d ' ')" 2

usb "keine-zahl" || FEHLER=1
pruefe "unbrauchbare Zahl gilt als Standard (3), nicht als 'alles löschen'" \
  "$(ls "$STICK/PiCraft-Backups/"backup_*.tar.gz | wc -l | tr -d ' ')" 2
rm -f "$TMP/bak/backup_2099-01-01_00-00-00.tar.gz"

# ============================================================================
echo "== Cloud-Kopie (rclone crypt gegen einen Ordner) =="
# ============================================================================
if ! command -v rclone >/dev/null 2>&1; then
  echo "  !! UEBERSPRUNGEN — rclone ist nicht installiert."
  echo "     Damit ist die Cloud-Kopie hier UNGEPRUEFT."
  echo "     Debian/Pi:  sudo apt-get install -y rclone"
  exit "$FEHLER"
fi

export RCLONE_CONFIG="$TMP/rclone.conf"
: > "$RCLONE_CONFIG"   # sonst meldet rclone "Config file not found"
rclone config create testcloud crypt remote="$TMP/wolke" filename_encryption=off \
       directory_name_encryption=false password=pruefung password2=salz \
       --obscure --non-interactive >/dev/null
rclone config create klartext local --non-interactive >/dev/null

cat > "$TMP/c.conf" <<ENDE
MCS_SERVER_PROPERTIES=$TMP/srv/server.properties
MCS_BACKUP_DIR=$TMP/bak
MCS_ARCHIV_DIR=$TMP/arch
MCS_CLOUD_ZIEL=testcloud:
MCS_CLOUD_BEHALTEN=3
MCS_BACKUP_BEHALTEN=5
ENDE
cloud() { MCS_CONF="$TMP/c.conf" MCS_PROBE_DIR="$TMP" bash "$REPO/backup/cloud-kopie.sh" "$@" >"$TMP/cloud.out" 2>&1; }
stand() { sed -n "s/^$1=//p" "$TMP/bak/cloud-kopie.stand"; }

cloud || { echo "  FEHLER: cloud-kopie.sh endete mit Fehler:"; sed 's/^/    /' "$TMP/cloud.out"; FEHLER=1; }
pruefe "Stand: ok" "$(stand ergebnis)" ok
# 3 verlangt, aber nie weniger als auf dem Pi (5) — sonst lüde jeder Lauf
# die zwei ältesten wieder hoch.
pruefe "täglich in der Cloud (nie weniger als lokal)" "$(stand taeglich)" 5
pruefe "Weltarchiv in der Cloud" "$(stand weltarchiv)" 2
pruefe "in der Cloud verschlüsselt (kein gzip lesbar)" \
  "$(gzip -t "$TMP/wolke/taeglich/backup_2026-10-05_04-00-00.tar.gz.bin" 2>/dev/null && echo lesbar || echo verschluesselt)" verschluesselt
pruefe "erste Probe gelaufen und bestanden" "$(stand probe_ergebnis | cut -d: -f1)" ok

cloud || FEHLER=1
pruefe "zweiter Lauf: nichts hochgeladen" "$(stand meldung | cut -d' ' -f1)" 0

# Rotation auf dem Pi: zwei neue, zwei alte weg. In der Cloud bleiben die
# neuesten fünf, und die zwei weggefallenen werden NICHT wieder hochgeladen.
backup_anlegen 2026-10-06_04-00-00; backup_anlegen 2026-10-07_04-00-00
rm -f "$TMP/bak/backup_2026-10-01_04-00-00.tar.gz" "$TMP/bak/backup_2026-10-02_04-00-00.tar.gz"
cloud || FEHLER=1
pruefe "nach der Rotation: zwei hochgeladen" "$(stand meldung | cut -d' ' -f1)" 2
pruefe "nach der Rotation: es bleiben 5" "$(stand taeglich)" 5
pruefe "nach der Rotation: das neueste" "$(stand neuestes)" "backup_2026-10-07_04-00-00.tar.gz"

# Rotation auf dem Pi aus (0): Die Cloud darf nichts löschen, sonst lädt
# jeder Lauf das Gelöschte wieder hoch (Befund vom 24.10.2026). Mit 3 statt
# 5 behalten hätte der alte Stand zwei gelöscht und beim zweiten Lauf zwei
# wieder hochgeladen.
sed -i -e "s#^MCS_BACKUP_BEHALTEN=.*#MCS_BACKUP_BEHALTEN=0#" "$TMP/c.conf"
backup_anlegen 2026-10-08_04-00-00
cloud || FEHLER=1
pruefe "Rotation aus: in der Cloud bleiben alle" "$(stand taeglich)" 6
cloud || FEHLER=1
pruefe "Rotation aus: zweiter Lauf lädt nichts neu hoch" "$(stand meldung | cut -d' ' -f1)" 0
# Zurück auf 5, damit die Fälle darunter denselben Ausgangsstand haben.
sed -i -e "s#^MCS_BACKUP_BEHALTEN=.*#MCS_BACKUP_BEHALTEN=5#" "$TMP/c.conf"
rm -f "$TMP/bak/backup_2026-10-03_04-00-00.tar.gz"
cloud || FEHLER=1
pruefe "Rotation wieder an: zurück auf 5" "$(stand taeglich)" 5

# Unglück auf dem Pi: Backup-Ordner leer. Die Cloud darf davon nichts merken.
mkdir -p "$TMP/leer"
sed -i "s#^MCS_BACKUP_DIR=.*#MCS_BACKUP_DIR=$TMP/leer#" "$TMP/c.conf"
cloud || true
pruefe "leerer Backup-Ordner löscht in der Cloud nichts" \
  "$(ls "$TMP/wolke/taeglich/" | wc -l | tr -d ' ')" 5
sed -i "s#^MCS_BACKUP_DIR=.*#MCS_BACKUP_DIR=$TMP/bak#" "$TMP/c.conf"

# Die Probe von Hand, mit Entschlüsseln und Vergleich gegen das Original.
cloud --probe || { echo "  FEHLER: Probe:"; sed 's/^/    /' "$TMP/cloud.out"; FEHLER=1; }
pruefe "Probe von Hand bestanden" "$(stand probe_ergebnis | cut -d: -f1)" ok
pruefe "Probe räumt hinter sich auf" "$(find "$TMP" -maxdepth 1 -name 'mcs-cloud-probe.*' | wc -l | tr -d ' ')" 0

# Ein Ziel ohne Verschlüsselung wird verweigert.
sed -i "s#^MCS_CLOUD_ZIEL=.*#MCS_CLOUD_ZIEL=klartext:$TMP/offen#" "$TMP/c.conf"
if cloud; then RC=0; else RC=$?; fi
pruefe "unverschlüsseltes Ziel verweigert (Rückgabewert)" "$RC" 1
pruefe "unverschlüsseltes Ziel: nichts hochgeladen" "$([ -e "$TMP/offen" ] && echo doch || echo nichts)" nichts
pruefe "unverschlüsseltes Ziel: Stand meldet es" "$(stand ergebnis)" fehler

# Frische Installation: leeres Weltarchiv, leere Cloud. Hier riss das Zählen
# der Archivstände den Lauf am 22.10.2026 still ab (lsf auf einen Ordner, den
# es in der Cloud noch nicht gab) — ohne Stand, ohne Meldung.
rclone config create frisch crypt remote="$TMP/wolke-frisch" filename_encryption=off \
       directory_name_encryption=false password=pruefung password2=salz \
       --obscure --non-interactive >/dev/null
mkdir -p "$TMP/arch-leer"
sed -i -e "s#^MCS_CLOUD_ZIEL=.*#MCS_CLOUD_ZIEL=frisch:#" \
       -e "s#^MCS_ARCHIV_DIR=.*#MCS_ARCHIV_DIR=$TMP/arch-leer#" "$TMP/c.conf"
if cloud; then RC=0; else RC=$?; fi
pruefe "leeres Weltarchiv: Lauf gelingt" "$RC" 0
pruefe "leeres Weltarchiv: Stand geschrieben" "$(stand ergebnis) $(stand weltarchiv)" "ok 0"

# Leeres Ziel heißt "aus": kein Fehler, kein Stand.
sed -i "s#^MCS_CLOUD_ZIEL=.*#MCS_CLOUD_ZIEL=#" "$TMP/c.conf"
cloud || FEHLER=1
pruefe "leeres Ziel = aus, ohne Fehler" "$(grep -c 'nicht eingerichtet' "$TMP/cloud.out")" 1

exit "$FEHLER"
