#!/bin/bash
#
# minecraft-backup.sh — Sichert Welten und Konfiguration im laufenden Betrieb.
#
# Früher musste der Server für jedes Backup gestoppt werden (alle Spieler
# flogen raus). Dieses Skript macht stattdessen ein "Online-Backup":
#
#   1. "save-off"        → Server hört kurz auf, die Welt auf die SSD zu
#                          schreiben (damit sich während des Kopierens
#                          nichts ändert)
#   2. "save-all flush"  → alles, was noch im Speicher ist, wird einmal
#                          komplett auf die SSD geschrieben; das Skript
#                          WARTET auf die Bestätigung im Server-Log
#   3. tar               → Welten + Konfigurationsdateien werden in ein
#                          komprimiertes Archiv gepackt
#   4. Prüfung           → das Archiv wird einmal probeweise gelesen
#   5. "save-on"         → Server speichert wieder normal weiter
#
# Die Spieler merken davon nichts. Läuft der Server gerade nicht, wird
# einfach direkt gesichert. Alte Backups werden automatisch aufgeräumt
# (Rotation), damit die SSD nie vollläuft.
#
# Aufruf: per Cronjob (täglich 4 Uhr), über das Admin-Web-UI
#         oder von Hand mit `mcs backup` — immer als Benutzer pi.

set -euo pipefail

# ----------------------------------------------------------------------------
# Einstellungen
# ----------------------------------------------------------------------------
# Zentrale Einstellungen laden (Pfade und Namen stehen in mcs.conf).
# Wo liegt die Installation, wenn mcs.conf (noch) fehlt? Im Heimatverzeichnis
# des Benutzers, dem der Server gehört. Bis 2026-08-28 stand hier fest
# "/home/pi" — auf jedem Pi mit einem anderen Benutzernamen zeigte der
# Rückfallwert damit stumm ins Leere. Siehe CLAUDE.md.
MCS_HOME="${HOME:-/home/$(id -un)}"
MCS_CONF="${MCS_CONF:-$MCS_HOME/mcs/mcs.conf}"
# shellcheck source=/dev/null
if [ -f "$MCS_CONF" ]; then . "$MCS_CONF"; fi

MC_SERVER_DIR="${MCS_SERVER_DIR:-$MCS_HOME/mcs/mc_server}"
BACKUP_DIR="${MCS_BACKUP_DIR:-$MCS_HOME/mcs/mcs_backup}"
BACKUP_LOG="$BACKUP_DIR/backup.log"

# Muss mit start-minecraft.sh übereinstimmen — kommt deshalb aus mcs.conf.
# Der Sitzungsname steht in lib-konsole.sh (KONSOLE_SITZUNG) und wird von
# dort gelesen — hier stand bis 2026-08-26 eine zweite, inzwischen
# unbenutzte Kopie davon.

# Wie viele Backups aufgehoben werden (ältere werden gelöscht).
# 10 tägliche Backups ≈ eineinhalb Wochen Sicherheit.
ANZAHL_BEHALTEN="${MCS_BACKUP_BEHALTEN:-10}"

# Höchstwartezeit auf die Bestätigung von "save-all flush" (Sekunden).
FLUSH_MAX_WARTEZEIT=120

# Server-Log — daraus wird die Speicher-Bestätigung gelesen.
SERVER_LOG="${MCS_MINECRAFT_LOG:-$MC_SERVER_DIR/logs/latest.log}"

ZEITSTEMPEL=$(date +"%Y-%m-%d_%H-%M-%S")
BACKUP_DATEI="$BACKUP_DIR/backup_$ZEITSTEMPEL.tar.gz"

# ----------------------------------------------------------------------------
# Gepackt wird unter einem ZWISCHENNAMEN, umbenannt wird erst nach der Prüfung
# ----------------------------------------------------------------------------
# Bis 2026-08-30 schrieb tar direkt nach backup_<zeit>.tar.gz, und geprüft
# wurde erst danach. Bei einem sauberen Fehler räumt das Skript selbst auf —
# aber ein harter Abbruch (Stromausfall, OOM-Killer, kill -9) lässt keine
# Gelegenheit dazu. Zurück bleibt eine halbe Datei, die
#
#   - für die Rotation wie ein gültiges Backup aussieht und ein echtes
#     verdrängt (sie behält nur die zehn neuesten),
#   - und die `mcs status` als "Backup von heute Nacht" meldet.
#
# Also ein Backup, das es nicht gibt, das aber ein vorhandenes vernichtet
# und dabei Entwarnung gibt. Steht so im Lastenheft (5.4, Punkt 5).
#
# Der Zwischenname beginnt mit einem Punkt und passt damit auf KEINES der
# Muster, mit denen anderswo gesucht wird ('backup_*.tar.gz' in der
# Rotation, in `mcs restore` und in status.py). Ein bloßes Anhängen von
# ".unfertig" täte es auch — der Punkt hält die Datei zusätzlich aus dem
# gewöhnlichen `ls` heraus.
ROHDATEI="$BACKUP_DIR/.unfertig-backup_$ZEITSTEMPEL.tar.gz"

# ----------------------------------------------------------------------------
# Hilfsfunktionen
# ----------------------------------------------------------------------------

# Schreibt eine Meldung auf den Bildschirm UND ins Backup-Logbuch.
# Das "|| true" entkoppelt beides: Wenn das Logbuch mal nicht beschreibbar
# ist, soll deswegen nicht die ganze Sicherung abbrechen.
protokoll() {
  echo "$(date '+%Y-%m-%d %H:%M:%S') | $1" | tee -a "$BACKUP_LOG" || true
}

# Benachrichtigung aufs Handy — der aktive Teil der Backup-Lehre.
#
# Ein Merkzettel und ein Statusfeld helfen nur dem, der von sich aus
# nachsieht. Genau daran hat es zwei Monate lang gefehlt. Deshalb geht bei
# jedem Fehlschlag zusätzlich eine Nachricht raus (tools/benachrichtigung.sh).
#
# Das steht hier oben und nicht bei fehler_merken(), weil der FRUEHESTE
# Ausfall gleich darunter kommt: die fehlende lib-konsole.sh. Stuende die
# Funktion weiter unten, waere ausgerechnet der Fall stumm, um dessen
# Klasse es hier geht.
BENACHRICHTIGUNG="${MCS_BENACHRICHTIGUNG:-${MCS_DIR:-$MCS_HOME/mcs}/benachrichtigung.sh}"

# Drei Vorkehrungen stecken in dieser einen Zeile, und alle drei sind nötig:
#
#   [ -x ... ]         Auf einer Installation von vor Etappe D gibt es die
#                      Datei nicht. Das darf kein Fehler sein.
#   >/dev/null 2>&1    Ist keine Benachrichtigung eingerichtet, endet das
#                      Skript mit 78 und schweigt — aber ein Netzfehler
#                      hätte sonst das Backup-Protokoll vollgeschrieben.
#   || true            Unter "set -e" würde ein misslungener Versand das
#                      Backup abbrechen. Eine Nachricht, die nicht ankommt,
#                      darf niemals das Backup kosten, das sie melden soll.
benachrichtigen() {
  [ -x "$BENACHRICHTIGUNG" ] || return 0
  "$BENACHRICHTIGUNG" "$1" "$2" "${3:-normal}" >/dev/null 2>&1 || true
}

# Der Umgang mit der Server-Konsole steht seit 2026-08-26 an einer einzigen
# Stelle: lib-konsole.sh im Serververzeichnis. Wichtig fuer dieses Skript:
# Die dortige Fassung escapt Rueckwaertsschraegstriche, die hiesige tat es
# nicht. Aufgefallen ist das nie, weil hier nur feste Woerter gesendet
# werden ("save-off", "save-all") - eine Falle fuer den ersten variablen Text.
# shellcheck source=../server/lib-konsole.sh
# Fehlt die Bibliothek, darf das nicht stumm passieren. Unter "set -e" wuerde
# das Skript hier sterben - und zwar BEVOR fehler_merken definiert ist, also
# ohne .letzter-fehler zu schreiben. Genau diese Klasse von lautlosem Ausfall
# hat vom 2026-05-18 bis 2026-07-27 zwei Monate lang kein Backup erzeugt,
# ohne dass es jemandem auffiel.
KONSOLE_LIB="${MCS_SERVER_DIR:-$MCS_HOME/mcs/mc_server}/lib-konsole.sh"
if [ ! -f "$KONSOLE_LIB" ]; then
  echo "$(date '+%Y-%m-%d %H:%M:%S') | FEHLER: $KONSOLE_LIB fehlt — Backup abgebrochen." \
    | tee -a "${MCS_BACKUP_DIR:-$MCS_HOME/mcs/mcs_backup}/backup.log" >&2
  echo "lib-konsole.sh fehlt ($KONSOLE_LIB)" \
    > "${MCS_BACKUP_DIR:-$MCS_HOME/mcs/mcs_backup}/.letzter-fehler" 2>/dev/null || true
  benachrichtigen "Backup fehlgeschlagen" \
    "Die Installation ist unvollständig: $KONSOLE_LIB fehlt. Beheben mit ./deploy.sh" hoch
  exit 1
fi
# shellcheck source=../server/lib-konsole.sh
. "$KONSOLE_LIB"

# Merkzettel für den letzten Fehlschlag.
#
# Warum? Vom 2026-05-18 bis zum 2026-07-27 kam über zwei Monate lang kein
# einziges Backup zustande, obwohl der Cronjob jede Nacht lief. Niemand hat
# es bemerkt, weil ein Fehlschlag nirgends sichtbar wurde. Diese Datei wird
# von `mcs status` und der Weboberfläche ausgelesen und gemeldet.
FEHLER_DATEI="$BACKUP_DIR/.letzter-fehler"

fehler_merken() {
  mkdir -p "$BACKUP_DIR"
  printf '%s | %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" > "$FEHLER_DATEI" || true
  protokoll "FEHLER: $1"
  benachrichtigen "Backup fehlgeschlagen" "$1" hoch
}

# ----------------------------------------------------------------------------
# Zahlenwerte aus der mcs.conf pruefen, BEVOR sie etwas loeschen koennen
# ----------------------------------------------------------------------------
# "${MCS_BACKUP_BEHALTEN:-10}" greift nur bei UNGESETZT oder leer. Eine
# ausdrueckliche 0 -- die naheliegende Schreibweise fuer "keine Rotation" --
# lief bis zum 2026-08-31 durch bis "tail -n +$((0+1))", und das ist JEDE
# Zeile: Ein einziger naechtlicher Lauf raeumte beide Platten leer, das eben
# erzeugte Archiv eingeschlossen. Uebrig blieben nur die Hardlinks im
# Dauerarchiv -- und auch die nur, falls es je gegriffen hatte.
#
# MCS_ARCHIV_JEDES=0 war die zweite Haelfte desselben Fehlers: eine Division
# durch null. Unter "set -euo pipefail" starb das Skript daran NACH einem
# gelungenen, geprueften und bereits umbenannten Backup. Der EXIT-trap sah
# einen Fehler und schrieb "unerwartet abgebrochen" -- also ein dauerhafter
# Falschalarm auf genau dem Signal, dem man vertrauen soll.
#
# Seither gilt: 0 heisst ausdruecklich "aus". Was keine Zahl ist, faellt auf
# den Standard zurueck und wird laut gemeldet. Geloescht wird nie auf
# Grundlage eines Wertes, dem dieses Skript nicht trauen kann.
#
# Die Warnung geht nach stderr (">&2"). protokoll() schreibt per tee auch auf
# die Standardausgabe, und die Funktion wird als $(zahl_aus_conf ...)
# aufgerufen: Bis zum 23.09.2026 landete die Warnung dadurch IN der Zahl.
# Aus "10" wurde "2026-09-23 ... | WARNUNG ... 10", jede Rechnung damit
# scheiterte — die Rotation loeschte still gar nichts mehr, das Dauerarchiv
# fiel aus, und der Lauf meldete Erfolg. Die Meldung behauptete dabei
# "es gilt der Standard", gegolten hat keiner (nachgestellt).
zahl_aus_conf() {
  local NAME="$1" WERT="$2" STANDARD="$3"
  case "$WERT" in
    ''|*[!0-9]*)
      protokoll "WARNUNG: $NAME ist keine Zahl (»$WERT«) — es gilt der Standard $STANDARD." >&2
      benachrichtigen "Backup: Einstellung unbrauchbar" \
        "$NAME steht in der mcs.conf auf »$WERT«. Das ist keine Zahl; es gilt $STANDARD." hoch
      printf '%s' "$STANDARD" ;;
    *)
      printf '%s' "$WERT" ;;
  esac
}

ANZAHL_BEHALTEN=$(zahl_aus_conf MCS_BACKUP_BEHALTEN "$ANZAHL_BEHALTEN" 10)

# Failsafe: Egal was passiert (auch bei einem Fehler mittendrin) —
# das automatische Speichern des Servers wird am Ende wieder eingeschaltet.
SPEICHERN_DEAKTIVIERT=false
aufraeumen() {
  local RC=$?
  if [ "$SPEICHERN_DEAKTIVIERT" = true ] && konsole_laeuft; then
    konsole_senden "save-on"
  fi
  # Die eigene halbfertige Datei geht mit. Bei einem harten Abbruch kommt
  # diese Falle nicht mehr zum Zug — dafür der Kehraus weiter unten.
  rm -f "$ROHDATEI"
  # Ein Abbruch an einer Stelle, die keinen eigenen Merkzettel schreibt
  # (z. B. Platte voll mitten im Packen), soll trotzdem auffallen.
  if [ "$RC" -ne 0 ] && [ ! -f "$FEHLER_DATEI" ]; then
    printf '%s | Backup unerwartet abgebrochen (Exitcode %s), siehe backup.log\n' \
      "$(date '+%Y-%m-%d %H:%M:%S')" "$RC" > "$FEHLER_DATEI" || true
    # Bis zum 24.10.2026 nur der Merkzettel: Die Nachricht blieb aus, und der
    # naechste gute Lauf meldete "wieder in Ordnung" fuer einen Fehler, von
    # dem niemand wusste.
    benachrichtigen "Backup fehlgeschlagen" "Unerwartet abgebrochen (Exitcode $RC), siehe backup.log" hoch
  fi
}
trap aufraeumen EXIT

# ----------------------------------------------------------------------------
# 1) Zusammenstellen, was gesichert wird
# ----------------------------------------------------------------------------
mkdir -p "$BACKUP_DIR"

# Immer nur EIN Lauf zur Zeit. Ein zweiter wartet, bis der erste fertig ist.
#
# Bis zum 23.09.2026 gab es keine Sperre, obwohl zwei Wege zugleich laufen
# koennen (der Timer nachts, und jemand klickt "Backup jetzt" oder startet
# "mcs update --minecraft"). Dann schickt der zweite Lauf "save-all flush",
# und Paper schreibt Regionsdateien, WAEHREND der erste sie packt; der erste
# schaltet mit "save-on" das Speichern wieder ein, waehrend der zweite noch
# packt. Beide Archive koennen einen halb geschriebenen Weltstand enthalten
# und bestehen trotzdem die Pruefung — die liest nur das Archiv, nicht die
# Welt darin.
#
# Warten statt ueberspringen: Wer ein Backup verlangt, bekommt eines, das
# NACH seinem Aufruf entstanden ist — "mcs update --minecraft" verlaesst
# sich genau darauf. Die Sperre gibt der Kernel beim Prozessende frei, auch
# nach kill -9; eine liegengebliebene Sperrdatei sperrt nichts.
exec 9>"$BACKUP_DIR/.backup.sperre"
if ! flock -n 9; then
  protokoll "Ein anderes Backup läuft gerade — warte, bis es fertig ist."
  # Waehrend des Wartens gehoert diesem Lauf KEINE Rohdatei. Sein Name kann
  # derselbe sein wie der des laufenden (Start in derselben Sekunde), und
  # die EXIT-Falle loescht ROHDATEI. Bis zum 23.09.2026 stand er hier schon
  # fest: Ein abgebrochener Wartender (Strg+C bei "mcs backup") loeschte dem
  # laufenden Backup die unfertige Datei, und das scheiterte mit "Archiv
  # laesst sich nicht lesen" (nachgestellt). Gefunden von der Zweitmeinung.
  ROHDATEI=""
  flock 9
  # Der Name soll sagen, wann DIESER Weltstand entstand, nicht wann der
  # Aufruf kam. (Denselben Namen wie der vorige Lauf bekaeme er nur, wenn
  # der in derselben Sekunde fertig wuerde, in der er begann — bei einer
  # echten Welt dauert das Packen Sekunden bis Minuten.)
  ZEITSTEMPEL=$(date +"%Y-%m-%d_%H-%M-%S")
  BACKUP_DATEI="$BACKUP_DIR/backup_$ZEITSTEMPEL.tar.gz"
  ROHDATEI="$BACKUP_DIR/.unfertig-backup_$ZEITSTEMPEL.tar.gz"
fi

# Halbfertige Dateien aus einem harten Abbruch wegräumen — alle.
#
# Bis zum 23.09.2026 nur solche, die älter als ein Tag sind, mit der
# Begründung, ein zweiter Lauf könne gleichzeitig packen. Seit der Sperre
# oben geht das nicht mehr: Wer hier ankommt, ist der einzige Lauf, und
# jede Rohdatei ist eine Leiche — bei einer Welt von einem Gigabyte ein
# Gigabyte, das sonst bis zu einen Tag liegen blieb. (Auf dem Zweitziel
# bleibt die Frist, siehe dort: Diese Platte kann ein anderer Rechner
# mitbenutzen, und für den gilt unsere Sperre nicht.)
find "$BACKUP_DIR" -maxdepth 1 -name '.unfertig-backup_*.tar.gz' \
     -delete 2>/dev/null || true

# Den Namen der Hauptwelt aus server.properties lesen (Standard: "world").
LEVEL_NAME="world"
if [ -f "$MC_SERVER_DIR/server.properties" ]; then
  GELESEN=$(grep -E '^level-name=' "$MC_SERVER_DIR/server.properties" | tail -n1 | cut -d= -f2- || true)
  [ -n "$GELESEN" ] && LEVEL_NAME="$GELESEN"
fi

# Welten (Oberwelt, Nether, Ende) + alles, was man zum Wiederherstellen
# braucht: Server-Einstellungen, Whitelist, Operatoren, Bann-Listen,
# Paper-Konfiguration und ggf. Plugins. Die paper.jar selbst wird nicht
# gesichert — die lädt paper-update.sh jederzeit frisch herunter.
# paper.installiert kommt mit: darin steht, WELCHE Version zu diesen
# Weltdaten gehört. Ohne diese Angabe wüsste man beim Wiederherstellen
# nicht, mit welcher Serverversion die Welt zuletzt lief.
SICHERN=()
for EINTRAG in \
  "$LEVEL_NAME" "${LEVEL_NAME}_nether" "${LEVEL_NAME}_the_end" \
  server.properties whitelist.json ops.json \
  banned-players.json banned-ips.json \
  bukkit.yml spigot.yml config plugins \
  paper.installiert versions.env plugins.txt
do
  if [ -e "$MC_SERVER_DIR/$EINTRAG" ]; then
    SICHERN+=("$EINTRAG")
  fi
done

# Falls die Welt anders heißt als erwartet: alle Ordner mit einer
# level.dat-Datei gelten als Welt und werden mitgesichert.
if [ ! -e "$MC_SERVER_DIR/$LEVEL_NAME" ]; then
  for D in "$MC_SERVER_DIR"/*/; do
    if [ -f "${D}level.dat" ]; then
      SICHERN+=("$(basename "$D")")
    fi
  done
fi

if [ "${#SICHERN[@]}" -eq 0 ]; then
  fehler_merken "Nichts zu sichern gefunden (keine Welt in $MC_SERVER_DIR)."
  exit 1
fi

# ----------------------------------------------------------------------------
# 2) Server in den Backup-Modus versetzen (nur wenn er läuft)
# ----------------------------------------------------------------------------
# Die Sitzung merken: Nach dem Packen muss es noch dieselbe sein (Abschnitt 3).
SITZUNG_VORHER=$(konsole_pid)
if [ -n "$SITZUNG_VORHER" ]; then
  protokoll "Server läuft — starte Online-Backup (ohne Unterbrechung für Spieler)."
  konsole_senden "say Backup wird erstellt..."
  konsole_senden "save-off"
  SPEICHERN_DEAKTIVIERT=true

  # Merken, wie lang das Log gerade ist. Alles, was ab jetzt dazukommt,
  # gehört zu diesem Speichervorgang.
  ZEILEN_VORHER=0
  if [ -f "$SERVER_LOG" ]; then
    ZEILEN_VORHER=$(wc -l < "$SERVER_LOG")
  fi

  konsole_senden "save-all flush"

  # Auf die Bestätigung warten, statt blind eine feste Zeit zu schlafen.
  #
  # Vorher stand hier "sleep 15" — eine geratene Zahl. Dauerte das
  # Speichern unter Last länger (nächtliches Time-Machine-Backup, große
  # Kreativwelt), packte tar halbgeschriebene Region-Dateien ein. Das
  # Backup sah gut aus und hätte im Ernstfall eine beschädigte Welt
  # zurückgebracht, ohne dass es irgendwo aufgefallen wäre.
  BESTAETIGT=false
  if [ -f "$SERVER_LOG" ]; then
    for ((I = 0; I < FLUSH_MAX_WARTEZEIT; I++)); do
      if tail -n +"$((ZEILEN_VORHER + 1))" "$SERVER_LOG" 2>/dev/null \
         | grep -qE 'Saved the game|Saved the world'; then
        BESTAETIGT=true
        protokoll "Speichern bestätigt nach ${I}s — beginne mit dem Kopieren."
        break
      fi
      sleep 1
    done
  fi

  if [ "$BESTAETIGT" = false ]; then
    # Kein Beweis, dass fertig gespeichert wurde. Das Backup trotzdem zu
    # machen ist besser als gar keines — aber es wird deutlich vermerkt.
    protokoll "WARNUNG: Keine Speicher-Bestätigung innerhalb von ${FLUSH_MAX_WARTEZEIT}s im Server-Log gefunden."
    protokoll "WARNUNG: Das Archiv könnte einen halb geschriebenen Weltstand enthalten."
  fi
else
  protokoll "Server ist gestoppt — sichere direkt."
fi

# ----------------------------------------------------------------------------
# 3) Archiv erstellen
# ----------------------------------------------------------------------------
# -C sorgt dafür, dass im Archiv nur relative Pfade landen
# (z. B. "world/..." statt "~/mcs/mc_server/world/...").
#
# nice/ionice: Das Packen ist die rechenintensivste Stelle im ganzen
# Setup und läuft nachts um vier — also genau dann, wenn typischerweise
# auch der Time-Machine-Dienst arbeitet. Mit niedriger Priorität dauert
# das Backup notfalls etwas länger, bremst dafür aber nichts anderes aus.
START_SEKUNDEN=$SECONDS

NETT=()
if command -v nice   >/dev/null 2>&1; then NETT+=(nice -n 15);  fi
if command -v ionice >/dev/null 2>&1; then NETT+=(ionice -c3); fi

# tar unterscheidet zwei Sorten von Problemen:
#   Status 1 = "eine Datei hat sich beim Lesen geändert" — eine Warnung.
#              Das Archiv ist vollständig und verwendbar.
#   Status 2 = echter Fehler (Platte voll, Rechte, defektes Ziel).
#
# Ohne diese Unterscheidung beendet "set -e" das Skript schon bei der
# Warnung — und zwar bevor das Archiv fertig protokolliert, ins
# Dauerarchiv gelegt und die Rotation ausgeführt wurde.
#
# Genau das ist hier passiert: Pl3xMap schreibt laufend Kartenkacheln
# unter plugins/Pl3xMap/web/tiles/, und die liegen im Sicherungsumfang.
# Seit dem 2026-05-18 ist deshalb kein einziges Backup mehr zustande
# gekommen, obwohl der Cronjob jede Nacht lief (gefunden 2026-07-27).
set +e
"${NETT[@]}" tar -czf "$ROHDATEI" -C "$MC_SERVER_DIR" "${SICHERN[@]}"
TAR_STATUS=$?
set -e
DAUER=$((SECONDS - START_SEKUNDEN))

if [ "$TAR_STATUS" -ge 2 ]; then
  fehler_merken "tar ist mit Status $TAR_STATUS abgebrochen — kein brauchbares Backup."
  rm -f "$ROHDATEI"
  exit 1
elif [ "$TAR_STATUS" -eq 1 ]; then
  protokoll "Hinweis: Dateien haben sich während des Sicherns geändert (tar-Status 1). Das Archiv ist vollständig; betroffen sind in aller Regel die Live-Kacheln von Pl3xMap, die sich jederzeit neu rendern lassen."
fi

# Wurde der Server waehrend des Packens gestoppt, neu gestartet oder
# gestartet, hat er in die Welt geschrieben (ein Stopp speichert, ein Start
# legt Dateien an) — und tar meldet das nur als Status 1, den die Zeilen
# darueber als harmlos durchlassen. "Backup jetzt" und gleich danach
# "Neustart" in der Oberflaeche genuegte dafuer (Befund einer Codepruefung
# am 24.10.2026, auf dem Pi nicht nachgestellt).
if [ "$(konsole_pid)" != "$SITZUNG_VORHER" ]; then
  fehler_merken "Der Server wurde während des Backups gestoppt oder gestartet — das Archiv wurde verworfen. Noch einmal: mcs backup"
  rm -f "$ROHDATEI"
  exit 1
fi

# ----------------------------------------------------------------------------
# 4) Normales Speichern wieder einschalten
# ----------------------------------------------------------------------------
if [ "$SPEICHERN_DEAKTIVIERT" = true ] && konsole_laeuft; then
  konsole_senden "save-on"
  SPEICHERN_DEAKTIVIERT=false
  konsole_senden "say Backup fertig."
fi

# ----------------------------------------------------------------------------
# 5) Archiv einmal probeweise lesen
# ----------------------------------------------------------------------------
# Ein Backup, das noch nie jemand gelesen hat, ist kein Backup. Der Test
# kostet ein paar Sekunden und würde ein abgeschnittenes oder beschädigtes
# Archiv sofort auffallen lassen — statt erst im Ernstfall.
protokoll "Prüfe das Archiv (einmal komplett lesen)..."
if ! "${NETT[@]}" tar -tzf "$ROHDATEI" > /dev/null 2>&1; then
  fehler_merken "Das erzeugte Archiv lässt sich nicht lesen — es wurde verworfen."
  rm -f "$ROHDATEI"
  exit 1
fi

# Zusätzlich gezielt nachsehen, ob die Hauptwelt wirklich drin ist. Ein
# lesbares Archiv ohne level.dat wäre technisch heil und trotzdem wertlos.
if [ -e "$MC_SERVER_DIR/$LEVEL_NAME/level.dat" ]; then
  if ! tar -tzf "$ROHDATEI" "$LEVEL_NAME/level.dat" > /dev/null 2>&1; then
    fehler_merken "Im Archiv fehlt $LEVEL_NAME/level.dat — es wurde verworfen."
    rm -f "$ROHDATEI"
    exit 1
  fi
fi

# ----------------------------------------------------------------------------
# 5b) Erst JETZT bekommt das Archiv seinen richtigen Namen
# ----------------------------------------------------------------------------
# Ab hier ist geprüft, dass die Datei lesbar ist und die Welt enthält. Damit
# ist sie ein Backup — vorher war sie nur eine Datei.
#
# Das Umbenennen im selben Verzeichnis ist atomar: Für jeden, der zusieht
# (die Rotation, `mcs restore`, die Weboberfläche), gibt es das Archiv
# entweder vollständig oder gar nicht. Einen Zwischenzustand kann niemand
# beobachten.
if ! mv "$ROHDATEI" "$BACKUP_DATEI"; then
  fehler_merken "Das geprüfte Archiv ließ sich nicht umbenennen ($ROHDATEI)."
  exit 1
fi

# Ab hier steht ein geprüftes, lesbares Archiv bereit — ein etwaiger
# Merkzettel vom letzten Fehlschlag darf weg.
#
# Und wenn dort wirklich einer lag: Entwarnung geben. Ohne diese zweite
# Nachricht weiß niemand, ob ein gemeldetes Problem noch besteht — man
# bekäme eine Warnung und danach für immer Stille, und Stille bedeutet in
# diesem Projekt schon einmal zwei Monate ohne Backup.
#
# Die Abfrage auf die Datei ist der Unterschied zwischen einer Entwarnung
# und einer nächtlichen Erfolgsmeldung. Letztere liest nach einer Woche
# niemand mehr, und dann fällt auch die Warnung nicht mehr auf.
if [ -f "$FEHLER_DATEI" ]; then
  benachrichtigen "Backup wieder in Ordnung" \
    "Der Fehlschlag von zuvor ist behoben: $(basename "$BACKUP_DATEI") ist geprüft und lesbar."
fi
rm -f "$FEHLER_DATEI"

GROESSE=$(du -h "$BACKUP_DATEI" | cut -f1)
protokoll "Backup geprüft und in Ordnung: $(basename "$BACKUP_DATEI") ($GROESSE, ${DAUER}s, Inhalt: ${SICHERN[*]})"

# ----------------------------------------------------------------------------
# 6) Dauerarchiv: jedes N-te Backup bleibt für immer liegen
# ----------------------------------------------------------------------------
# Die Rotation weiter unten löscht alles außer den neuesten
# $ANZAHL_BEHALTEN Archiven — auch Weltstände, die man vielleicht noch
# gebraucht hätte. Deshalb wandert jeder N-te Lauf zusätzlich ins
# Dauerarchiv, das von der Rotation nicht angefasst wird (sie räumt nur
# in $BACKUP_DIR auf).
#
# Gesichert wird per Hardlink: dieselben Datenblöcke, zweiter Name.
# Das kostet zunächst keinen zusätzlichen Platz. Löscht die Rotation
# später das Original, bleiben die Daten über den Archiv-Namen erhalten.
# Liegt das Archiv auf einer anderen Platte, wird automatisch kopiert.
ARCHIV_DIR="${MCS_ARCHIV_DIR:-$MCS_HOME/mcs/weltarchiv}"
ARCHIV_JEDES=$(zahl_aus_conf MCS_ARCHIV_JEDES "${MCS_ARCHIV_JEDES:-10}" 10)

# 0 heisst "Dauerarchiv aus" -- und nicht mehr "Division durch null", siehe
# zahl_aus_conf weiter oben.
if [ "$ARCHIV_JEDES" -eq 0 ]; then
  protokoll "Hinweis: Dauerarchiv ist ausgeschaltet (MCS_ARCHIV_JEDES=0)."
elif [ -n "$ARCHIV_DIR" ]; then
  # Verzeichnis selbst anlegen. Vorher wurde nur geprüft, ob es existiert —
  # und weil install.sh es nie angelegt hat, wurde das Dauerarchiv auf
  # jeder frischen Installation stillschweigend übersprungen.
  mkdir -p "$ARCHIV_DIR"

  ZAEHLER_DATEI="$ARCHIV_DIR/.laufzaehler"
  ZAEHLER=$(cat "$ZAEHLER_DATEI" 2>/dev/null || echo 0)
  ZAEHLER=$((ZAEHLER + 1))
  echo "$ZAEHLER" > "$ZAEHLER_DATEI"

  if [ $(( (ZAEHLER - 1) % ARCHIV_JEDES )) -eq 0 ]; then
    ARCHIV_ZIEL="$ARCHIV_DIR/$(basename "$BACKUP_DATEI")"
    if ln "$BACKUP_DATEI" "$ARCHIV_ZIEL" 2>/dev/null; then
      protokoll "Dauerarchiv: Lauf $ZAEHLER als Hardlink gesichert → $(basename "$ARCHIV_ZIEL")"
    else
      # Andere Platte: ueber einen Zwischennamen, wie beim Zweitziel in
      # Abschnitt 7. Bis zum 24.10.2026 schrieb cp direkt auf den Endnamen —
      # eine volle oder abgezogene Platte hinterliess ein halbes Archiv, das
      # als Dauerarchiv-Stand galt und in die Cloud ging, wo nie geloescht wird.
      ARCHIV_ROH="$ARCHIV_DIR/.unfertig-$(basename "$BACKUP_DATEI")"
      find "$ARCHIV_DIR" -maxdepth 1 -name '.unfertig-backup_*.tar.gz' -delete 2>/dev/null || true
      if cp -a "$BACKUP_DATEI" "$ARCHIV_ROH" && "${NETT[@]}" tar -tzf "$ARCHIV_ROH" >/dev/null 2>&1 \
         && mv "$ARCHIV_ROH" "$ARCHIV_ZIEL"; then
        protokoll "Dauerarchiv: Lauf $ZAEHLER kopiert und geprüft → $(basename "$ARCHIV_ZIEL")"
      else
        rm -f "$ARCHIV_ROH"
        protokoll "WARNUNG: Dauerarchiv: Lauf $ZAEHLER ließ sich nicht nach $ARCHIV_DIR kopieren — dieser Stand fehlt dort."
        benachrichtigen "Backup: Dauerarchiv unvollständig" \
          "Lauf $ZAEHLER ließ sich nicht nach $ARCHIV_DIR kopieren. Das Backup selbst ist in Ordnung." hoch
      fi
    fi
    protokoll "Dauerarchiv: $(find "$ARCHIV_DIR" -maxdepth 1 -name '*.tar.gz' | wc -l | tr -d ' ') Stände, $(du -sh "$ARCHIV_DIR" | cut -f1) belegt."
  else
    NOCH=$(( ARCHIV_JEDES - ((ZAEHLER - 1) % ARCHIV_JEDES) ))
    protokoll "Dauerarchiv: Lauf $ZAEHLER — nächste Sicherung in $NOCH Lauf/Läufen."
  fi
else
  protokoll "Hinweis: Dauerarchiv ist ausgeschaltet (MCS_ARCHIV_DIR leer)."
fi

# ----------------------------------------------------------------------------
# 7) Zweites Ziel auf einem anderen Datenträger
# ----------------------------------------------------------------------------
# Bis hierher liegen Backup, Dauerarchiv und Welt auf DERSELBEN SSD. Geht
# die kaputt, ist alles auf einmal weg — dann war die ganze Mühe umsonst.
# MCS_EXTERN_DIR zeigt deshalb idealerweise auf einen anderen Datenträger,
# zum Beispiel auf die Platte des Time-Machine-Dienstes.
EXTERN_DIR="${MCS_EXTERN_DIR:-}"

if [ -n "$EXTERN_DIR" ]; then
  # Auch das Geraet vergleichen: Ein nicht eingehaengter Einhaengepunkt ist ein
  # leerer Ordner auf der SSD. Bis zum 24.10.2026 landete die "Zweitkopie" dann
  # neben dem Original und wurde als "abgelegt und geprueft" gemeldet.
  if [ -d "$EXTERN_DIR" ] && [ "$(stat -c %d "$EXTERN_DIR")" != "$(stat -c %d "$BACKUP_DIR")" ]; then
    # Auch hier ueber einen Zwischennamen, aus demselben Grund wie oben in
    # Abschnitt 5b -- bis zum 2026-08-31 fehlte er ausgerechnet auf der Platte,
    # die den Ausfall der NVMe ueberleben soll.
    #
    # Laeuft das Ziel voll, bricht cp mit ENOSPC ab und laesst eine
    # ABGESCHNITTENE Datei liegen. Unter dem Endnamen sah die aus wie ein
    # gueltiges Backup: Die Rotation weiter unten zaehlte sie mit und
    # verdraengte dafuer ein echtes Archiv. Ein Backup, das es nicht gibt,
    # loeschte also eines, das es gab.
    EXTERN_ROH="$EXTERN_DIR/.unfertig-$(basename "$BACKUP_DATEI")"
    EXTERN_ZIEL="$EXTERN_DIR/$(basename "$BACKUP_DATEI")"

    # Leichen aelter als ein Tag wegraeumen. Hier — anders als oben — mit
    # Frist: Die Sperre gilt nur fuer diesen Rechner, das Zweitziel kann ein
    # anderer mitbenutzen, dessen frische Rohdatei gerade entsteht.
    find "$EXTERN_DIR" -maxdepth 1 -name '.unfertig-backup_*.tar.gz' -mtime +0 \
         -delete 2>/dev/null || true

    # Der Grund des Scheiterns gehoert ins Protokoll. Vorher verschluckte ihn
    # "2>/dev/null", und die Meldung riet stattdessen ("Platte voll? Rechte?").
    CP_FEHLER=""
    if CP_FEHLER=$(cp -a "$BACKUP_DATEI" "$EXTERN_ROH" 2>&1); then
      if "${NETT[@]}" tar -tzf "$EXTERN_ROH" > /dev/null 2>&1 && mv "$EXTERN_ROH" "$EXTERN_ZIEL"; then
        protokoll "Zweitkopie abgelegt und geprüft: $EXTERN_ZIEL"
        # Auch dort aufräumen, damit der zweite Datenträger nicht vollläuft.
        if [ "$ANZAHL_BEHALTEN" -eq 0 ]; then
          protokoll "Zweitkopie: Rotation ausgeschaltet — es wird nichts gelöscht."
        else
          EXTERN_GELOESCHT=0
          while IFS= read -r ALT; do
            rm -f "$ALT" && EXTERN_GELOESCHT=$((EXTERN_GELOESCHT + 1))
          done < <(find "$EXTERN_DIR" -maxdepth 1 -name 'backup_*.tar.gz' -printf '%T@ %p\n' 2>/dev/null \
                   | sort -rn | tail -n +"$((ANZAHL_BEHALTEN + 1))" | cut -d' ' -f2-)
          if [ "$EXTERN_GELOESCHT" -gt 0 ]; then
            protokoll "Zweitkopie: $EXTERN_GELOESCHT alte(s) Archiv(e) gelöscht."
          fi
        fi
      else
        rm -f "$EXTERN_ROH"
        protokoll "WARNUNG: Die Zweitkopie nach $EXTERN_DIR war nicht lesbar und wurde verworfen — keine Zweitkopie!"
      fi
    else
      rm -f "$EXTERN_ROH"
      protokoll "WARNUNG: Zweitkopie nach $EXTERN_DIR fehlgeschlagen: ${CP_FEHLER:-Grund unbekannt}"
    fi
  else
    # Das ist kein Schönheitsfehler: Wenn der zweite Datenträger nicht da
    # ist, gibt es die Sicherung außer Haus nicht — und das soll auffallen.
    protokoll "WARNUNG: Zweitziel $EXTERN_DIR fehlt oder liegt auf derselben Platte wie die Backups (nicht eingehängt?) — keine Zweitkopie!"
  fi
fi

# ----------------------------------------------------------------------------
# 8) Rotation: alte Backups löschen
# ----------------------------------------------------------------------------
# Nur die vom Skript selbst erzeugten Archive (backup_*.tar.gz) werden
# rotiert. Vorher traf es jede .tar.gz-Datei im Verzeichnis — auch eine,
# die man dort bewusst abgelegt hatte, etwa als Handsicherung vor einem
# Versionswechsel. Nach zehn Nächten war sie weg, genau dann, wenn man
# sie gebraucht hätte.
# 0 heisst "Rotation aus". Vorher hiess es "loesche alles", siehe zahl_aus_conf.
if [ "$ANZAHL_BEHALTEN" -eq 0 ]; then
  protokoll "Hinweis: Rotation ist ausgeschaltet (MCS_BACKUP_BEHALTEN=0) — es wird nichts gelöscht."
else
  GELOESCHT=0
  while IFS= read -r ALTES_BACKUP; do
    rm -f "$ALTES_BACKUP"
    GELOESCHT=$((GELOESCHT + 1))
  done < <(find "$BACKUP_DIR" -maxdepth 1 -name 'backup_*.tar.gz' -printf '%T@ %p\n' 2>/dev/null \
           | sort -rn | tail -n +"$((ANZAHL_BEHALTEN + 1))" | cut -d' ' -f2-)

  if [ "$GELOESCHT" -gt 0 ]; then
    protokoll "Rotation: $GELOESCHT alte(s) Backup(s) gelöscht (behalte die neuesten $ANZAHL_BEHALTEN)."
  fi
fi

# ----------------------------------------------------------------------------
# 9) Bescheid geben: ein neues, geprüftes Backup liegt bereit
# ----------------------------------------------------------------------------
# Darauf warten die Kopien auf den USB-Stick und in die Cloud
# (mcs-usb-kopie.path, mcs-cloud-kopie.path). Eine Datei statt OnSuccess= in
# mcs-backup.service, weil ein Backup auf drei Wegen entsteht — Timer,
# "mcs backup", Knopf in der Weboberfläche — und nur der erste über systemd
# läuft. Ganz am Ende, damit keine Kopie mit der Rotation um dieselben
# Dateien konkurriert. Der Inhalt ist nur zum Nachlesen; ausgelöst wird
# durch das Schreiben selbst.
# Scheitert das Schreiben, ist das Backup trotzdem gut — aber die Kopien
# blieben aus, ohne dass es jemand merkt. Also ins Protokoll damit.
if ! basename "$BACKUP_DATEI" > "$BACKUP_DIR/.neuestes-backup"; then
  protokoll "WARNUNG: $BACKUP_DIR/.neuestes-backup ließ sich nicht schreiben — USB- und Cloud-Kopie werden diesmal nicht angestoßen."
fi
