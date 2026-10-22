#!/bin/bash
#
# benachrichtigung.sh — Eine Kurznachricht aufs Handy schicken (ntfy).
#
#   benachrichtigung.sh "Titel" "Text" [normal|hoch]
#   benachrichtigung.sh --test
#
# ----------------------------------------------------------------------------
# Warum es das gibt
# ----------------------------------------------------------------------------
# Vom 2026-05-18 bis zum 2026-07-27 kam über zwei Monate lang kein einziges
# Backup zustande, obwohl der Cronjob jede Nacht lief. Niemand hat es
# bemerkt. Das ist die teuerste Lehre der Projektgeschichte und der Grund
# für alles, was in diesem Projekt mit Backups zu tun hat.
#
# Seither meldet `mcs status` einen Fehlschlag, und die Weboberfläche zeigt
# ihn an. Beides ist besser als nichts — aber beides ist PASSIV: Es hilft
# nur dem, der von sich aus nachsieht. Genau daran hat es damals gefehlt.
#
# Diese Datei ist der aktive Teil.
#
# ----------------------------------------------------------------------------
# Warum ntfy und nicht Telegram oder E-Mail (Lastenheft O4)
# ----------------------------------------------------------------------------
# Weil die Frage lautet: Was muss jemand tun, der das Repository frisch
# installiert hat und in zwei Minuten fertig sein will?
#
#   ntfy       App installieren, Thema abonnieren.   Kein Konto.
#   Telegram   Konto, Bot bei BotFather anlegen, Chat-ID herausfinden.
#   E-Mail     Konto, SMTP-Server, Absender, Passwort, msmtp installieren.
#
# ----------------------------------------------------------------------------
# DER HAKEN, DEN MAN WISSEN MUSS
# ----------------------------------------------------------------------------
# Bei ntfy.sh ist der THEMENNAME das ganze Geheimnis. Es gibt kein Passwort.
# Wer den Namen errät oder mitliest, bekommt jede Nachricht mit — und kann
# selbst welche schicken.
#
# Deshalb: kein Name wie "mcs-backup", sondern einer mit einem Dutzend
# zufälliger Zeichen. Die Weboberfläche schlägt genau so einen vor.
#
# Wem das nicht reicht, betreibt ntfy selbst (MCS_NTFY_SERVER) und legt
# einen Zugangstoken in ntfy.env ab.
#
# ----------------------------------------------------------------------------
# Rückgabewerte — 78 ist kein Fehler
# ----------------------------------------------------------------------------
#    0   verschickt
#   78   nicht eingerichtet (kein Thema eingetragen)
#    1   Versand fehlgeschlagen
#
# Die 78 ist EX_CONFIG aus sysexits.h. Sie ist wichtig, weil das
# Backup-Skript diese Datei bei jedem Fehlschlag aufruft: "Es ist keine
# Benachrichtigung eingerichtet" darf dort nicht als zweiter Fehler
# ankommen und schon gar nicht das Backup-Protokoll vollschreiben.

set -uo pipefail

MCS_HOME="${HOME:-/home/$(id -un)}"
MCS_CONF="${MCS_CONF:-$MCS_HOME/mcs/mcs.conf}"
# shellcheck source=/dev/null
if [ -f "$MCS_CONF" ]; then . "$MCS_CONF"; fi

MC_DIR="${MCS_DIR:-$MCS_HOME/mcs}"
SERVER="${MCS_NTFY_SERVER:-https://ntfy.sh}"
THEMA="${MCS_NTFY_THEMA:-}"

# Der Token liegt NICHT in mcs.conf: Die wird von Shell, Python und systemd
# gelesen und hat entsprechend offene Rechte. Dasselbe Muster wie bei
# duckdns.env — und aus demselben Grund.
ZUGANG="${MCS_NTFY_ENV:-$MC_DIR/ntfy.env}"
if [ -f "$ZUGANG" ]; then
  # shellcheck source=/dev/null
  . "$ZUGANG"
fi
TOKEN="${MCS_NTFY_TOKEN:-}"

TEST=false
if [ "${1:-}" = "--test" ]; then TEST=true; fi

# ----------------------------------------------------------------------------
# Nicht eingerichtet? Dann still enden.
# ----------------------------------------------------------------------------
if [ -z "$THEMA" ]; then
  if [ "$TEST" = true ]; then
    echo "Es ist keine Benachrichtigung eingerichtet." >&2
    echo "" >&2
    echo "Einrichten in der Weboberfläche unter \"Backups\", oder von Hand:" >&2
    echo "  1. App \"ntfy\" installieren (Android, iOS) oder https://ntfy.sh im Browser" >&2
    echo "  2. Ein Thema abonnieren — einen langen, zufälligen Namen wählen:" >&2
    echo "       mcs-$(tr -dc 'a-z0-9' < /dev/urandom | head -c 12)" >&2
    echo "  3. Denselben Namen in $MCS_CONF eintragen:" >&2
    echo "       MCS_NTFY_THEMA=..." >&2
    echo "  4. Ausprobieren:  $0 --test" >&2
  fi
  exit 78
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "Fehler: curl fehlt — ohne das geht keine Benachrichtigung." >&2
  exit 1
fi

# ----------------------------------------------------------------------------
# Was verschickt wird
# ----------------------------------------------------------------------------
if [ "$TEST" = true ]; then
  TITEL="PiCraft Testnachricht"
  TEXT="Wenn du das liest, funktioniert die Benachrichtigung. Von $(hostname 2>/dev/null || echo 'diesem Pi'), $(date '+%d.%m.%Y %H:%M')."
  STUFE="normal"
else
  TITEL="${1:-PiCraft}"
  TEXT="${2:-}"
  STUFE="${3:-normal}"
fi

case "$STUFE" in
  hoch) PRIORITAET=4; SYMBOL="warning" ;;
  *)    PRIORITAET=3; SYMBOL="package" ;;
esac

# ----------------------------------------------------------------------------
# Warum als JSON und nicht über HTTP-Kopfzeilen
# ----------------------------------------------------------------------------
# ntfy kann den Titel auch in einer Kopfzeile "Title:" entgegennehmen. Das
# ist kürzer — und für dieses Projekt falsch: HTTP-Kopfzeilen sind nicht für
# UTF-8 gedacht. Ein Titel wie "Backup fehlgeschlagen: Platte voll (Prüfung
# abgebrochen)" käme dort verstümmelt an oder gar nicht.
#
# In diesem Projekt ist alles auf Deutsch. Umlaute sind hier keine
# Ausnahme, sondern der Normalfall — also der Weg, der sie verträgt.
json_text() {
  # jq ist eine Abhängigkeit des Projekts (install.sh installiert es für die
  # PaperMC-API). Fehlt es trotzdem, greift eine kleine Ersatzlösung: Sie
  # maskiert Rückwärtsschrägstriche, Anführungszeichen und Zeilenumbrüche —
  # mehr kommt in einer Fehlermeldung des Backup-Skripts nicht vor.
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$1" | jq -Rs .
  else
    printf '%s' "$1" \
      | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' \
      | awk 'BEGIN{printf "\""} {printf "%s%s", sep, $0; sep="\\n"} END{printf "\""}'
  fi
}

KOERPER=$(printf '{"topic":%s,"title":%s,"message":%s,"priority":%s,"tags":[%s]}' \
  "$(json_text "$THEMA")" "$(json_text "$TITEL")" "$(json_text "$TEXT")" \
  "$PRIORITAET" "$(json_text "$SYMBOL")")

# ----------------------------------------------------------------------------
# Verschicken
# ----------------------------------------------------------------------------
# --max-time 20: Eine Benachrichtigung darf das Backup nicht aufhalten. Ist
# das Netz weg, ist die Nachricht verloren — das ist hinnehmbar, ein
# haengendes naechtliches Backup nicht.
KOPFZEILEN=(-H "Content-Type: application/json")
[ -n "$TOKEN" ] && KOPFZEILEN+=(-H "Authorization: Bearer $TOKEN")

ANTWORT=$(curl -fsS --max-time 20 "${KOPFZEILEN[@]}" -d "$KOERPER" "$SERVER" 2>&1)
ERGEBNIS=$?

if [ "$ERGEBNIS" -ne 0 ]; then
  echo "Benachrichtigung fehlgeschlagen: ${ANTWORT:-keine Antwort von $SERVER}" >&2
  exit 1
fi

if [ "$TEST" = true ]; then
  echo "Testnachricht an Thema \"$THEMA\" auf $SERVER verschickt."
  echo "Kommt sie nicht an: Ist genau dieses Thema in der App abonniert?"
fi
exit 0
