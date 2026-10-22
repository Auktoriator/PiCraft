#!/bin/bash
#
# cloud-kopie.sh — Legt die Backups verschlüsselt in einen Cloud-Speicher.
#
# Wozu: Der Pi, der USB-Stick und jede Zweitplatte stehen im selben Haus.
# Gegen Brand, Einbruch oder Überspannung hilft nur eine Kopie außer Haus.
#
# Verschlüsselt, und zwar zwingend: In jedem Archiv stehen das RCON-Passwort
# (server.properties) und die Whitelist mit Namen und UUIDs. Was das Haus
# verlässt, darf der Anbieter nicht lesen können. Deshalb nimmt das Skript
# nur ein rclone-Ziel vom Typ "crypt" an und verweigert jedes andere.
#
# Warum rclone und nicht restic oder borg: Das Lastenheft legt tar.gz fest,
# damit sich ein Backup ohne Spezialwerkzeug öffnen lässt. Daran ändert sich
# nichts — auf dem Pi, auf dem Stick und im Zweitziel bleibt es bei
# denselben tar.gz-Dateien. Nur die Kopie in der Cloud ist zusätzlich
# verschlüsselt, und rclone ist das eine Werkzeug, das sie hochlädt UND
# wieder entschlüsselt. Es läuft auf dem Pi, auf jedem Mac und unter Windows.
#
# Was hochgeladen wird:
#   taeglich/    jedes backup_*.tar.gz; in der Cloud bleiben die neuesten
#                MCS_CLOUD_BEHALTEN (Standard 30)
#   weltarchiv/  das Dauerarchiv, vollständig, und dort wird nie gelöscht
#
# Aufgeräumt wird NACH ZAHL — nicht durch Abgleich mit dem Pi und nicht nach
# Alter. Beides wäre gefährlich:
#   - Ein Abgleich ("rclone sync") spiegelt auch ein Unglück. Ist der
#     Backup-Ordner leer, wäre es danach auch die Cloud.
#   - "Älter als 30 Tage löschen" räumt die Cloud leer, wenn die Backups
#     ausbleiben, also genau dann, wenn man die alten braucht. Ausbleibende
#     Backups sind hier schon einmal zwei Monate lang niemandem aufgefallen.
# Nach Zahl heißt: Es bleiben immer die neuesten 30, was auch passiert.
#
# Gelesen wird die Cloud-Kopie einmal im Monat wirklich: herunterladen,
# entschlüsseln, als Archiv lesen (Abschnitt "Probe"). Ein Backup, das noch
# nie jemand zurückgeholt hat, ist eine Behauptung.
#
# Aufruf: durch mcs-cloud-kopie.service nach jedem Backup. Von Hand:
#   mcs cloud jetzt       dasselbe sofort
#   mcs cloud probe       das neueste Backup aus der Cloud holen und prüfen
#   mcs cloud einrichten  rclone einmalig verbinden (Assistent in tools/mcs)

set -euo pipefail

MCS_HOME="${HOME:-/home/$(id -un)}"
MCS_CONF="${MCS_CONF:-$MCS_HOME/mcs/mcs.conf}"
# shellcheck source=/dev/null
if [ -f "$MCS_CONF" ]; then . "$MCS_CONF"; fi

BACKUP_DIR="${MCS_BACKUP_DIR:-$MCS_HOME/mcs/mcs_backup}"
ARCHIV_DIR="${MCS_ARCHIV_DIR:-$MCS_HOME/mcs/weltarchiv}"
SERVER_PROPERTIES="${MCS_SERVER_PROPERTIES:-${MCS_SERVER_DIR:-$MCS_HOME/mcs/mc_server}/server.properties}"
BACKUP_LOG="$BACKUP_DIR/backup.log"
ZIEL="${MCS_CLOUD_ZIEL:-}"
STAND="$BACKUP_DIR/cloud-kopie.stand"
RCLONE_LOG="$BACKUP_DIR/.cloud-kopie.log"
PROBE_ALLE_TAGE=30

# Wie viele tägliche Backups in der Cloud bleiben. Eine unbrauchbare Angabe
# gilt als Standard, nicht als "alles löschen" (Befund 23.09.2026). Und nie
# weniger als auf dem Pi selbst: Sonst lüde jeder Lauf die lokal noch
# vorhandenen, in der Cloud gerade gelöschten Archive erneut hoch.
BEHALTEN="${MCS_CLOUD_BEHALTEN:-30}"
case "$BEHALTEN" in
  ''|*[!0-9]*) BEHALTEN=30 ;;
esac
LOKAL="${MCS_BACKUP_BEHALTEN:-10}"
case "$LOKAL" in
  ''|*[!0-9]*) LOKAL=10 ;;
esac
[ "$BEHALTEN" -ge "$LOKAL" ] || BEHALTEN="$LOKAL"
[ "$BEHALTEN" -ge 1 ] || BEHALTEN=30

protokoll() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') | Cloud-Kopie: $1" | tee -a "$BACKUP_LOG" || true
}

# Stand für "mcs cloud", "mcs status" und die Weboberfläche. Die Werte der
# letzten Probe werden übernommen, wenn dieser Lauf keine gemacht hat — sonst
# vergäße der Stand nach einem Tag, dass die Cloud je gelesen wurde.
#
# awk und kein "sed … | head": Beim ersten Lauf gibt es die Datei noch
# nicht, sed endet dann mit 2, und unter pipefail und "set -e" riss das
# Lesen eines ALTEN Werts den ganzen Lauf ab — ohne Stand, ohne Meldung.
# Gefunden am 22.10.2026 von tests/pruefung-kopien.sh, beim ersten Lauf.
alter_wert() {
  [ -f "$STAND" ] || return 0
  awk -v k="$1" 'index($0, k "=") == 1 { print substr($0, length(k) + 2); exit }' "$STAND"
}

#
# "zeit" und "epoch" sind der letzte Kopierlauf. Eine Probe von Hand
# ("--probe") lässt sie stehen: Sonst sähe eine Cloud, in die seit Tagen
# nichts mehr hochgeladen wurde, nach einer Probe wieder frisch aus.
NUR_PROBE=false

stand_schreiben() {   # stand_schreiben ok|fehler MELDUNG
  local ZEIT EPOCH PZ PE PM
  if [ "$NUR_PROBE" = true ]; then
    ZEIT=$(alter_wert zeit); EPOCH=$(alter_wert epoch)
  else
    ZEIT=$(date '+%Y-%m-%d %H:%M:%S'); EPOCH=$(date +%s)
  fi
  PZ="${PROBE_ZEIT:-$(alter_wert probe_zeit)}"
  PE="${PROBE_EPOCH:-$(alter_wert probe_epoch)}"
  PM="${PROBE_ERGEBNIS:-$(alter_wert probe_ergebnis)}"
  {
    echo "zeit=$ZEIT"
    echo "epoch=$EPOCH"
    echo "ergebnis=$1"
    echo "meldung=$(printf '%s' "$2" | tr -d '\n')"
    echo "ziel=$ZIEL"
    echo "taeglich=${ANZAHL_TAEGLICH:-$(alter_wert taeglich)}"
    echo "weltarchiv=${ANZAHL_ARCHIV:-$(alter_wert weltarchiv)}"
    echo "neuestes=${NEUESTES_WOLKE:-$(alter_wert neuestes)}"
    echo "probe_zeit=$PZ"
    echo "probe_epoch=$PE"
    echo "probe_ergebnis=$PM"
  } > "$STAND.neu" && mv "$STAND.neu" "$STAND"
}

fehler() {
  protokoll "WARNUNG: $1 — keine Kopie außer Haus!"
  stand_schreiben fehler "$1"
  exit 1
}

if [ -z "$ZIEL" ]; then
  echo "Cloud-Kopie ist nicht eingerichtet (MCS_CLOUD_ZIEL in mcs.conf ist leer). Einrichten: mcs cloud einrichten"
  exit 0
fi

command -v rclone >/dev/null 2>&1 \
  || fehler "rclone ist nicht installiert (sudo apt-get install rclone)"

# Nur verschlüsselte Ziele, siehe Kopf. "listremotes --long" nennt je Ziel
# den Typ, ohne die Zugangsdaten auszugeben.
REMOTE="${ZIEL%%:*}"
# "|| true": Scheitert rclone selbst (kaputte rclone.conf), endete die
# Zuweisung unter pipefail sonst still — die Prüfung darunter sagt es laut.
TYP=$(rclone listremotes --long 2>/dev/null | awk -v r="$REMOTE:" '$1 == r { print $2 }') || true
[ -n "$TYP" ] || fehler "rclone kennt kein Ziel \"$REMOTE\" (mcs cloud einrichten)"
[ "$TYP" = crypt ] || fehler "Das Ziel \"$REMOTE\" ist vom Typ \"$TYP\", nicht verschlüsselt. Die Archive enthalten das RCON-Passwort und die Whitelist; unverschlüsselt geht nichts aus dem Haus"

# Die beiden Ordner im Ziel. "mcs-cloud:" + "taeglich", nicht
# "mcs-cloud:/taeglich": Der Schrägstrich nach dem Doppelpunkt heißt bei
# manchen rclone-Zielen "von der Wurzel des Anbieters aus".
case "$ZIEL" in
  *:) ZIEL_TAEGLICH="${ZIEL}taeglich";   ZIEL_ARCHIV="${ZIEL}weltarchiv" ;;
  *)  ZIEL_TAEGLICH="${ZIEL%/}/taeglich"; ZIEL_ARCHIV="${ZIEL%/}/weltarchiv" ;;
esac

# Nur ein Lauf zugleich. Der erste Abgleich dauert Stunden — kommt in der
# Zeit das nächste Backup, holt es der nächste Lauf nach.
exec 9>"$BACKUP_DIR/.cloud-kopie.sperre"
if ! flock -n 9; then
  echo "Eine Cloud-Kopie läuft schon — dieser Aufruf endet ohne etwas zu tun."
  exit 0
fi

OPTS=(--retries 3 --low-level-retries 10 --contimeout 60s --timeout 5m)
# Ohne Grenze lädt rclone so schnell, wie die Leitung kann — und dieselbe
# Leitung braucht der Server für seine Spieler. Nachts ist das egal, beim
# ersten, stundenlangen Abgleich nicht. Siehe MCS_CLOUD_BWLIMIT in mcs.conf.
if [ -n "${MCS_CLOUD_BWLIMIT:-}" ]; then
  OPTS+=(--bwlimit "$MCS_CLOUD_BWLIMIT")
fi

# ----------------------------------------------------------------------------
# Probe: das neueste Backup aus der Cloud holen und als Archiv lesen
# ----------------------------------------------------------------------------
# Global, nicht "local": Die Falle beim Beenden muss die Variable noch sehen.
# Genau daran ist "mcs restore --probe" am 21.10.2026 gescheitert und ließ
# 732 MB im Arbeitsspeicher liegen.
PROBE_DIR=""
aufraeumen() { [ -z "$PROBE_DIR" ] || rm -rf "$PROBE_DIR"; }
trap aufraeumen EXIT

probe() {
  local DATEI LEVEL
  DATEI=$(rclone lsf "$ZIEL_TAEGLICH" --files-only --include 'backup_*.tar.gz' "${OPTS[@]}" 2>/dev/null \
          | sort | tail -n1)
  if [ -z "$DATEI" ]; then
    PROBE_ERGEBNIS="fehler: in der Cloud liegt kein Backup"
    return 1
  fi

  # Auf die Platte, nicht nach /tmp: Das ist auf dem Pi ein Teil des
  # Arbeitsspeichers, und ein Backup ist 750 MB groß.
  PROBE_DIR=$(mktemp -d "${MCS_PROBE_DIR:-/var/tmp}/mcs-cloud-probe.XXXXXX")
  echo "Probe: hole $DATEI aus der Cloud..."
  if ! rclone copyto "$ZIEL_TAEGLICH/$DATEI" "$PROBE_DIR/$DATEI" "${OPTS[@]}"; then
    PROBE_ERGEBNIS="fehler: $DATEI ließ sich nicht herunterladen"
    return 1
  fi
  if ! tar -tzf "$PROBE_DIR/$DATEI" >/dev/null 2>&1; then
    PROBE_ERGEBNIS="fehler: $DATEI aus der Cloud ist kein lesbares Archiv"
    return 1
  fi
  LEVEL=$(sed -n 's/^level-name=//p' "$SERVER_PROPERTIES" 2>/dev/null | head -n1)
  if [ -n "$LEVEL" ] && ! tar -tzf "$PROBE_DIR/$DATEI" "$LEVEL/level.dat" >/dev/null 2>&1; then
    PROBE_ERGEBNIS="fehler: in $DATEI aus der Cloud fehlt $LEVEL/level.dat"
    return 1
  fi
  if [ -f "$BACKUP_DIR/$DATEI" ] && ! cmp -s "$BACKUP_DIR/$DATEI" "$PROBE_DIR/$DATEI"; then
    PROBE_ERGEBNIS="fehler: $DATEI aus der Cloud weicht vom Original ab"
    return 1
  fi
  rm -rf "$PROBE_DIR"
  PROBE_DIR=""
  PROBE_ERGEBNIS="ok: $DATEI heruntergeladen, entschlüsselt und gelesen"
  return 0
}

probe_festhalten() {
  PROBE_ZEIT=$(date '+%Y-%m-%d %H:%M:%S')
  PROBE_EPOCH=$(date +%s)
}

if [ "${1:-}" = "--probe" ]; then
  NUR_PROBE=true
  if probe; then
    probe_festhalten
    protokoll "Probe bestanden — $PROBE_ERGEBNIS."
    stand_schreiben "$(alter_wert ergebnis)" "$(alter_wert meldung)"
    echo "$PROBE_ERGEBNIS"
    exit 0
  fi
  probe_festhalten
  protokoll "WARNUNG: Probe fehlgeschlagen — ${PROBE_ERGEBNIS#fehler: }."
  stand_schreiben fehler "Probe fehlgeschlagen: ${PROBE_ERGEBNIS#fehler: }"
  exit 1
fi

# ----------------------------------------------------------------------------
# 1) Hochladen
# ----------------------------------------------------------------------------
# "copy" lädt nur, was in der Cloud fehlt oder sich unterscheidet. Bricht ein
# Lauf ab, macht der nächste dort weiter. Die Muster lassen den Zwischennamen
# ".unfertig-backup_*" des Backup-Skripts aus — ein halbes Archiv geht nie
# hoch.
: > "$RCLONE_LOG"
START=$SECONDS
rclone copy "$BACKUP_DIR" "$ZIEL_TAEGLICH" --max-depth 1 --include 'backup_*.tar.gz' \
       "${OPTS[@]}" -v --log-file "$RCLONE_LOG" \
  || fehler "Hochladen der täglichen Backups fehlgeschlagen ($(grep -m1 ERROR "$RCLONE_LOG" | cut -c1-200))"

if [ -d "$ARCHIV_DIR" ]; then
  rclone copy "$ARCHIV_DIR" "$ZIEL_ARCHIV" --max-depth 1 --include '*.tar.gz' --include 'LIESMICH.md' \
         "${OPTS[@]}" -v --log-file "$RCLONE_LOG" \
    || fehler "Hochladen des Weltarchivs fehlgeschlagen ($(grep -m1 ERROR "$RCLONE_LOG" | cut -c1-200))"
fi
HOCHGELADEN=$(grep -c ': Copied (' "$RCLONE_LOG" || true)

# ----------------------------------------------------------------------------
# 2) Prüfen, dass das neueste wirklich angekommen ist
# ----------------------------------------------------------------------------
# cryptcheck verschlüsselt die Datei auf dem Pi noch einmal mit dem Schlüssel
# der Cloud-Kopie und vergleicht die Prüfsummen — ohne herunterzuladen.
NEUESTES=$(find "$BACKUP_DIR" -maxdepth 1 -type f -name 'backup_*.tar.gz' -printf '%f\n' | sort | tail -n1)
if [ -n "$NEUESTES" ]; then
  rclone cryptcheck "$BACKUP_DIR" "$ZIEL_TAEGLICH" --one-way --include "/$NEUESTES" \
         "${OPTS[@]}" --log-file "$RCLONE_LOG" \
    || fehler "$NEUESTES ist in der Cloud nicht identisch mit dem Original"
fi

# ----------------------------------------------------------------------------
# 3) Aufräumen nach Zahl
# ----------------------------------------------------------------------------
# Scheitert die Auflistung, bleibt die Liste leer, und es wird nichts
# gelöscht. Das ist die sichere Richtung — und sie fällt trotzdem auf, weil
# der Stand dann keine Zahl nennt.
mapfile -t WOLKE < <(rclone lsf "$ZIEL_TAEGLICH" --files-only --include 'backup_*.tar.gz' "${OPTS[@]}" | sort)
GELOESCHT=0
if [ "${#WOLKE[@]}" -gt "$BEHALTEN" ]; then
  for ((I = 0; I < ${#WOLKE[@]} - BEHALTEN; I++)); do
    if rclone deletefile "$ZIEL_TAEGLICH/${WOLKE[I]}" "${OPTS[@]}"; then
      GELOESCHT=$((GELOESCHT + 1))
    fi
  done
fi
ANZAHL_TAEGLICH=$(( ${#WOLKE[@]} - GELOESCHT ))
# Gelöscht wird von vorn (das älteste zuerst), das letzte bleibt das neueste.
NEUESTES_WOLKE=""
[ "${#WOLKE[@]}" -eq 0 ] || NEUESTES_WOLKE="${WOLKE[${#WOLKE[@]}-1]}"
# "|| true" in der Klammer: Gibt es den Ordner in der Cloud noch nicht (leeres
# Weltarchiv, frische Installation), endet lsf mit 3, und unter pipefail riss
# das den Lauf ab, OHNE Stand und ohne Meldung. Gefunden am 22.10.2026 beim
# Durchspielen von "mcs cloud einrichten" gegen einen leeren Ordner.
ANZAHL_ARCHIV=$( (rclone lsf "$ZIEL_ARCHIV" --files-only --include '*.tar.gz' "${OPTS[@]}" 2>/dev/null || true) \
                 | wc -l | tr -d ' ')

MELDUNG="$HOCHGELADEN Datei(en) hochgeladen in $(( (SECONDS - START) / 60 )) min; in der Cloud: $ANZAHL_TAEGLICH tägliche, $ANZAHL_ARCHIV im Weltarchiv"
[ "$GELOESCHT" -eq 0 ] || MELDUNG="$MELDUNG; $GELOESCHT alte gelöscht"
protokoll "$MELDUNG."

# ----------------------------------------------------------------------------
# 4) Einmal im Monat: die Probe
# ----------------------------------------------------------------------------
LETZTE_PROBE=$(alter_wert probe_epoch)
if [ -z "$LETZTE_PROBE" ] || [ $(( $(date +%s) - ${LETZTE_PROBE:-0} )) -gt $((PROBE_ALLE_TAGE * 86400)) ]; then
  if probe; then
    probe_festhalten
    protokoll "Probe bestanden — $PROBE_ERGEBNIS."
  else
    probe_festhalten
    protokoll "WARNUNG: Probe fehlgeschlagen — ${PROBE_ERGEBNIS#fehler: }."
    stand_schreiben fehler "Hochgeladen, aber die Probe ist fehlgeschlagen: ${PROBE_ERGEBNIS#fehler: }"
    exit 1
  fi
fi

stand_schreiben ok "$MELDUNG."
echo "$MELDUNG."
