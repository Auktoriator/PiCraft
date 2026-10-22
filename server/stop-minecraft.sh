#!/bin/bash
#
# stop-minecraft.sh — Fährt den Paper-Server sauber herunter.
#
# Dieses Skript wird vom systemd-Dienst (minecraft.service) beim Stoppen
# aufgerufen. Es kündigt das Herunterfahren im Spiel an, schickt dann den
# "stop"-Befehl an die Server-Konsole (der Befehl speichert automatisch
# alle Welten) und wartet, bis der Server wirklich beendet ist.
#
# Wichtig: Hier gibt es keine starren langen Wartezeiten. Das Skript prüft
# jede Sekunde, ob der Server schon weg ist — ein normaler Stopp dauert
# dadurch meist nur 15–25 Sekunden statt fix über einer Minute.
#
# Reagiert der Server gar nicht mehr, gibt es zwei Stufen, bevor hart
# abgebrochen wird. Das ist der heikelste Moment im ganzen Setup: Wird
# Java mitten im Schreiben eines Chunks abgeschossen, kann die Welt
# Schaden nehmen.

set -uo pipefail

# Zentrale Einstellungen laden (Pfade und Namen stehen in mcs.conf).
# Fehlt die Datei, gelten die Standardwerte darunter.
# Wo liegt die Installation, wenn mcs.conf (noch) fehlt? Im Heimatverzeichnis
# des Benutzers, dem der Server gehört. Bis 2026-08-28 stand hier fest
# "/home/pi" — auf jedem Pi mit einem anderen Benutzernamen zeigte der
# Rückfallwert damit stumm ins Leere. Siehe CLAUDE.md.
MCS_HOME="${HOME:-/home/$(id -un)}"
MCS_CONF="${MCS_CONF:-$MCS_HOME/mcs/mcs.conf}"
# shellcheck source=/dev/null
if [ -f "$MCS_CONF" ]; then . "$MCS_CONF"; fi

# Der Sitzungsname steht in lib-konsole.sh (KONSOLE_SITZUNG) und wird von
# dort gelesen — hier stand bis 2026-08-26 eine zweite, inzwischen
# unbenutzte Kopie davon.

# Vorwarnzeit für Spieler (Sekunden).
VORWARNZEIT=10

# Wie lange auf das geordnete Ende gewartet wird, bevor die nächste Stufe
# kommt. 240 Sekunden statt der früheren 90: eine große Kreativwelt bei
# Sichtweite 16 braucht auf einem Pi, dessen Platte sich mit dem
# Time-Machine-Dienst teilt, spürbar länger. Die Frist in der
# systemd-Dienstdatei (TimeoutStopSec=300) ist darauf abgestimmt.
MAX_WARTEZEIT=240

# Zusätzliche Frist, nachdem Java das Signal SIGTERM bekommen hat.
SIGTERM_WARTEZEIT=30

# Der Umgang mit der Server-Konsole steht seit 2026-08-26 an einer einzigen
# Stelle: lib-konsole.sh, die neben diesem Skript liegt. Von dort kommen
# konsole_laeuft und konsole_senden.
# shellcheck source=lib-konsole.sh
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib-konsole.sh"

sitzung_laeuft() { konsole_laeuft; }
konsole() { konsole_senden "$1"; }

# Sucht den Java-Prozess des Servers. Wird gebraucht, um ihm im Notfall
# höflich SIGTERM zu schicken, statt gleich die ganze Sitzung abzuräumen.
java_pid() {
  pgrep -u "$(id -un)" -f 'java .*paper\.jar' 2>/dev/null | head -n1
}

# Wartet bis zu $1 Sekunden darauf, dass die Sitzung verschwindet.
# Rückgabe 0 = Server ist weg, 1 = Zeit abgelaufen.
warte_auf_ende() {
  local SEKUNDEN="$1" I
  for ((I = 0; I < SEKUNDEN; I++)); do
    if ! sitzung_laeuft; then
      return 0
    fi
    sleep 1
  done
  return 1
}

# ----------------------------------------------------------------------------
# Läuft überhaupt noch etwas?
# ----------------------------------------------------------------------------
if ! sitzung_laeuft; then
  echo "Keine laufende Server-Sitzung gefunden — nichts zu stoppen."
  exit 0
fi

# ----------------------------------------------------------------------------
# 1) Spieler vorwarnen — aber nur, wenn überhaupt jemand da ist
# ----------------------------------------------------------------------------
# Die Vorwarnung lief bisher immer, auch nachts um vier bei leerem Server.
# Jeder Neustart kostete dadurch zehn Sekunden ohne jeden Nutzen.
SPIELER_LOG="${MCS_MINECRAFT_LOG:-$MCS_HOME/mcs/mc_server/logs/latest.log}"
SPIELER_DA=false
if [ -f "$SPIELER_LOG" ]; then
  # Wer seit dem letzten Serverstart beigetreten und nicht wieder weg ist,
  # gilt als online. latest.log beginnt bei jedem Start leer.
  #
  # Gefuehrt wird eine MENGE von Namen, keine zwei Zaehler. Bis zum
  # 23.09.2026 stand hier "joined > (left + lost connection)" — aber Paper
  # schreibt fuer EINE Trennung BEIDE Zeilen (siehe CLAUDE.md; im Log des Pi
  # je Sitzung 1x joined, 1x left, 1x lost). Jeder Abgang zaehlte doppelt,
  # dazu jede an der Whitelist abgewiesene Anmeldung. Nach dem ersten
  # Besucher des Tages bekam damit jeder weitere Spieler beim Stoppen KEINE
  # Vorwarnung mehr. In der Menge schadet doppeltes Entfernen nicht.
  #
  # Die Muster kommen aus log-muster.sh — dieselben, die Spielerprotokoll und
  # Weboberflaeche benutzen, und verankert: Eine Chatzeile mit
  # "]: Alice joined the game" zaehlte sonst Alice mit. (Hier stand kurz eine
  # eigene awk-Kopie; die Zweitmeinung zu Durchgang 1 hat sie gefunden.)
  #
  # Anmeldung vom zweiten Geraet: Paper meldet ZUERST den neuen Beitritt und
  # wirft DANN die alte Verbindung hinaus (CLAUDE.md). Eine Abmeldung binnen
  # zwei Sekunden nach dem eigenen Beitritt gehoert deshalb zur alten
  # Verbindung und zaehlt nicht. Ein echter Abgang nach unter zwei Sekunden
  # gibt dafuer eine Vorwarnung zu viel — die sichere Richtung.
  MUSTER="${MCS_LOG_MUSTER:-${MCS_DIR:-$MCS_HOME/mcs}/log-muster.sh}"
  if [ -f "$MUSTER" ]; then
    # shellcheck source=../tools/log-muster.sh
    . "$MUSTER"
    declare -A ONLINE=() BEITRITT=()
    sekunden() { local h m s; IFS=: read -r h m s <<<"$1"; echo $((10#$h * 3600 + 10#$m * 60 + 10#$s)); }
    while IFS= read -r ZEILE; do
      # Beitritt und Verlassen tragen den Namen in Gruppe 3, "lost
      # connection" in Gruppe 2: Seit Paper 26.3 kann vor den ersten beiden
      # "System chat: " stehen (log-muster.sh). Vom 14. bis 21.10.2026 fand
      # dieser Block deshalb niemanden, und "mcs restart" warf Spieler ohne
      # Vorwarnung hinaus.
      if [[ "$ZEILE" =~ $MUSTER_BEITRITT ]]; then
        ONLINE["${BASH_REMATCH[3]}"]=1
        BEITRITT["${BASH_REMATCH[3]}"]=$(sekunden "${BASH_REMATCH[1]}")
        continue
      elif [[ "$ZEILE" =~ $MUSTER_VERLASSEN ]]; then
        NAME="${BASH_REMATCH[3]}"
      elif [[ "$ZEILE" =~ $MUSTER_VERBINDUNG_WEG ]]; then
        NAME="${BASH_REMATCH[2]}"
      else
        continue
      fi
      ABSTAND=$(( $(sekunden "${BASH_REMATCH[1]}") - ${BEITRITT[$NAME]:--99} ))
      # Negativ heisst: Mitternacht lag dazwischen (die Zeilen tragen nur
      # die Uhrzeit). Ohne diese Zeile galt ein Geraetewechsel um 23:59:59
      # mit Rauswurf um 00:00:00 als Abgang (Zweitmeinung zu Durchgang 2).
      [ "$ABSTAND" -lt 0 ] && ABSTAND=$((ABSTAND + 86400))
      if [ "$ABSTAND" -gt 2 ]; then
        unset "ONLINE[$NAME]"
      fi
    # Vorfilter: nur Zeilen, die ueberhaupt in Frage kommen. Die Schleife
    # prueft danach mit den verankerten Mustern; ohne Filter kostete sie am
    # groessten echten Log (6000 Zeilen) 1,5 s bei jedem Stoppen.
    done < <(grep -E 'joined the game|left the game|lost connection' "$SPIELER_LOG")
    [ "${#ONLINE[@]}" -gt 0 ] && SPIELER_DA=true
  else
    # Ohne Muster laesst sich nichts sagen — dann lieber warnen als nicht.
    SPIELER_DA=true
  fi
fi

if [ "$SPIELER_DA" = true ]; then
  echo "Kündige Herunterfahren an (${VORWARNZEIT} Sekunden Vorwarnung)..."
  konsole "say Der Server fährt in ${VORWARNZEIT} Sekunden herunter."
  sleep "$VORWARNZEIT"
else
  echo "Niemand online — Vorwarnung übersprungen."
fi

# ----------------------------------------------------------------------------
# 2) Server stoppen. Der "stop"-Befehl speichert alle Welten automatisch.
# ----------------------------------------------------------------------------
echo "Sende 'stop' an den Server..."
if ! konsole "stop"; then
  echo "Warnung: Der Befehl kam nicht bei der Server-Konsole an." >&2
  echo "Überspringe die Wartezeit und gehe direkt zum Signalweg." >&2
else
  if warte_auf_ende "$MAX_WARTEZEIT"; then
    echo "Minecraft-Server wurde sauber beendet."
    exit 0
  fi
  echo "Warnung: Server ist nach ${MAX_WARTEZEIT} Sekunden noch da." >&2
fi

# ----------------------------------------------------------------------------
# 3) Zweite Stufe: SIGTERM an den Java-Prozess
# ----------------------------------------------------------------------------
# Paper hat für dieses Signal einen eigenen "Aufräum-Haken": Es speichert
# die Welt und beendet sich geordnet. Das ist immer noch der freundliche
# Weg — anders als das Abräumen der Screen-Sitzung, das Java mitten im
# Schreiben treffen kann.
PID="$(java_pid)"
if [ -n "$PID" ]; then
  echo "Schicke SIGTERM an den Java-Prozess (PID $PID) — Paper speichert dabei." >&2
  kill -TERM "$PID" 2>/dev/null || true
  if warte_auf_ende "$SIGTERM_WARTEZEIT"; then
    echo "Minecraft-Server nach SIGTERM beendet (Welt wurde gespeichert)."
    exit 0
  fi
else
  echo "Kein Java-Prozess gefunden — überspringe den Signalweg." >&2
fi

# ----------------------------------------------------------------------------
# 4) Notbremse: Sitzung zwangsweise beenden
# ----------------------------------------------------------------------------
# Ab hier ist Datenverlust möglich. Deshalb endet das Skript mit einem
# Fehlercode: systemd markiert den Stopp dann als fehlgeschlagen, und in
# "mcs status" bzw. "journalctl -u minecraft.service" ist nachlesbar, dass
# hart abgebrochen wurde. Vorher meldete das Skript hier Erfolg, und
# niemand erfuhr je davon.
echo "FEHLER: Server reagiert auf nichts mehr — beende die Screen-Sitzung hart." >&2
echo "Die Welt wurde dabei möglicherweise nicht vollständig gespeichert." >&2
echo "Nach dem nächsten Start bitte prüfen, ob alles in Ordnung ist." >&2
konsole_abraeumen
exit 1
