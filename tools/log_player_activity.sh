#!/bin/bash
#
# log_player_activity.sh — Führt ein dauerhaftes Logbuch der Spieleraktivität.
#
# Das normale Server-Log (latest.log) wird bei jedem Neustart geleert.
# Dieses Skript liest es live mit und schreibt alle Beitritte, Austritte
# und Verbindungsabbrüche in eine eigene, dauerhafte Datei:
#
#   ~/mcs/player_activity.log
#
# So lässt sich jederzeit nachvollziehen, wer wann auf dem Server war —
# auch über Neustarts hinweg. Das Admin-Web-UI zeigt diese Datei an.
#
# Läuft als eigener systemd-Dienst (mcs-playerlog.service) dauerhaft im
# Hintergrund. `tail -F` wartet automatisch, falls das Server-Log gerade
# (noch) nicht existiert, und folgt ihm auch nach einer Log-Rotation.

set -u

# ----------------------------------------------------------------------------
# Einstellungen
# ----------------------------------------------------------------------------
# Zentrale Einstellungen laden (Pfade stehen in mcs.conf).
# Wo liegt die Installation, wenn mcs.conf (noch) fehlt? Im Heimatverzeichnis
# des Benutzers, dem der Server gehört. Bis 2026-08-28 stand hier fest
# "/home/pi" — auf jedem Pi mit einem anderen Benutzernamen zeigte der
# Rückfallwert damit stumm ins Leere. Siehe CLAUDE.md.
MCS_HOME="${HOME:-/home/$(id -un)}"
MCS_CONF="${MCS_CONF:-$MCS_HOME/mcs/mcs.conf}"
# shellcheck source=/dev/null
if [ -f "$MCS_CONF" ]; then . "$MCS_CONF"; fi

SERVER_LOG="${MCS_MINECRAFT_LOG:-$MCS_HOME/mcs/mc_server/logs/latest.log}"
AKTIVITAETS_LOG="${MCS_PLAYER_ACTIVITY_LOG:-$MCS_HOME/mcs/player_activity.log}"

# ----------------------------------------------------------------------------
# Suchmuster laden
# ----------------------------------------------------------------------------
# Die Muster stehen zentral in log-muster.sh — dieselbe Datei liest auch
# die Weboberfläche. Vorher gab es zwei getrennte Listen, die bei einer
# Formatänderung von Paper auseinanderlaufen konnten.
SKRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MUSTER_DATEI="${MCS_LOG_MUSTER:-$SKRIPT_DIR/log-muster.sh}"

if [ ! -f "$MUSTER_DATEI" ]; then
  echo "Fehler: Suchmuster-Datei $MUSTER_DATEI fehlt." >&2
  echo "Bitte ./deploy.sh im Repo-Verzeichnis ausführen." >&2
  exit 1
fi
# shellcheck source=log-muster.sh
. "$MUSTER_DATEI"

# ----------------------------------------------------------------------------
# Schreibt einen Eintrag mit aktuellem Datum ins Aktivitätslog.
# ----------------------------------------------------------------------------
eintrag() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') | $1" >> "$AKTIVITAETS_LOG"
}

# Logdatei beim allerersten Start mit Überschrift anlegen.
if [ ! -f "$AKTIVITAETS_LOG" ]; then
  {
    echo "Spieler-Aktivitätslog (Pi-MCS)"
    echo "------------------------------"
  } > "$AKTIVITAETS_LOG"
fi

# Nur der Serverbenutzer darf das Hauptbuch lesen: Es enthält die
# IP-Adressen und UUIDs der Mitspieler. Bis zum 21.10.2026 bekam es die
# Rechte der umask, also rw-rw-r--. Auf dem Pi dieses Projekts war das
# folgenlos, weil das Heimatverzeichnis 700 ist. Auf einem Pi mit 755
# hätte aber jeder Benutzer mitlesen können. Hier und nicht nur bei der
# Neuanlage, damit eine bestehende Datei beim nächsten Dienststart ebenfalls
# enger wird. Scheitern darf es: Mitschreiben ist wichtiger.
chmod 600 "$AKTIVITAETS_LOG" 2>/dev/null || true

# ----------------------------------------------------------------------------
# Live-Verarbeitung des Server-Logs
# ----------------------------------------------------------------------------
# "-n 0": nur, was AB JETZT dazukommt. Ohne das las tail beim Start die
# letzten zehn Zeilen noch einmal, und eintrag() stempelt mit der
# aktuellen Uhrzeit, nicht mit der aus dem Log. Jeder Neustart dieses
# Dienstes (mcs an, Neustart des Pi, Restart=always) schrieb damit die
# letzten Beitritte und Austritte ein zweites Mal ins Hauptbuch — datiert
# auf den Neustart (am 23.09.2026 nachgestellt). "Zuletzt gesehen" wurde so
# zur Uhrzeit des Neustarts, und es entstanden Sitzungen, die es nie gab.
# Legt der Server beim Start ein neues latest.log an, liest -F die neue
# Datei trotzdem von ihrer ersten Zeile an (ebenfalls nachgestellt).
tail -n 0 -F "$SERVER_LOG" 2>/dev/null | while IFS= read -r ZEILE; do

  # Anmeldung: Der Server meldet die eindeutige Spieler-ID (UUID).
  if [[ "$ZEILE" =~ $MUSTER_UUID ]]; then
    eintrag "Spieler ${BASH_REMATCH[2]} meldet sich an (UUID: ${BASH_REMATCH[3]})"
    continue
  fi

  # Anmeldung mit Adresse. Sie ist die einzige Zeile, in der die
  # IP-Adresse steht. (Hier stand, sie komme VOR "joined the game". Das
  # galt bis Paper 26.2; seit 26.3 kommt sie danach. Für dieses Skript ist
  # die Reihenfolge gleichgültig, jede Zeile wird für sich ausgewertet.)
  #
  # Warum sie mitgeschrieben wird: Die Spielerseite der Weboberflaeche zeigt
  # die zuletzt bekannte Adresse an — hilfreich, wenn jemand Aerger macht
  # (Lastenheft 5.7.4). Im latest.log steht sie zwar auch, aber das wird bei
  # jedem Serverstart geleert; nach einem Neustart waere die Angabe weg.
  #
  # Das ist eine personenbezogene Angabe. Sie bleibt auf dem Pi, in einer
  # Datei, die nur dem Serverbenutzer gehoert, und wird nirgendwohin
  # gesendet. Wer das nicht will, kommentiert diesen Block aus — die
  # Weboberflaeche zeigt dann einen Strich statt einer Adresse.
  if [[ "$ZEILE" =~ $MUSTER_ANMELDUNG ]]; then
    eintrag "${BASH_REMATCH[2]} meldet sich an von ${BASH_REMATCH[3]}"
    continue
  fi

  # Spieler ist der Welt beigetreten. Der Name steht hier in Gruppe 3, nicht
  # in 2 — seit Paper 26.3 kann "System chat: " davorstehen (log-muster.sh).
  if [[ "$ZEILE" =~ $MUSTER_BEITRITT ]]; then
    eintrag "${BASH_REMATCH[3]} ist dem Spiel beigetreten"
    continue
  fi

  # Verbindung verloren (Spieler hat das Spiel beendet, Netzproblem, ...).
  if [[ "$ZEILE" =~ $MUSTER_VERBINDUNG_WEG ]]; then
    eintrag "${BASH_REMATCH[2]} hat die Verbindung verloren (Grund: ${BASH_REMATCH[3]})"
    continue
  fi

  # Spieler hat das Spiel regulär verlassen (Name in Gruppe 3, wie oben).
  if [[ "$ZEILE" =~ $MUSTER_VERLASSEN ]]; then
    eintrag "${BASH_REMATCH[3]} hat das Spiel verlassen"
    continue
  fi

  # Verbindung vom Server abgelehnt (z. B. nicht auf der Whitelist).
  if [[ "$ZEILE" =~ $MUSTER_ABGELEHNT ]]; then
    eintrag "Verbindung von ${BASH_REMATCH[2]} [${BASH_REMATCH[3]}] abgelehnt: ${BASH_REMATCH[4]}"
    continue
  fi

done
