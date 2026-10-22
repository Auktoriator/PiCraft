#!/bin/bash
#
# start-minecraft.sh — Startet den Paper-Server in einer Screen-Sitzung.
#
# Dieses Skript wird vom systemd-Dienst (minecraft.service) aufgerufen,
# nicht von Hand. Es startet Java mit abgestimmten Einstellungen für den
# Raspberry Pi 5 (8 GB RAM) und legt den Server in eine "Screen"-Sitzung.
#
# Was ist Screen? Ein Programm, das eine Art unsichtbares Terminal-Fenster
# bereitstellt. Der Minecraft-Server läuft darin weiter, auch wenn niemand
# angemeldet ist. Man kann sich jederzeit mit `mcs console` "hineinschauen"
# und Befehle direkt in die Server-Konsole tippen.

set -euo pipefail

# ----------------------------------------------------------------------------
# Einstellungen
# ----------------------------------------------------------------------------
# Alle Pfade und Namen stehen zentral in ~/mcs/mcs.conf. Fehlt die
# Datei (z. B. während der allerersten Installation), gelten die
# Standardwerte darunter — das Skript läuft also auch ohne sie.
# Zum Testen lässt sich mit MCS_CONF=/pfad/zur/datei eine andere
# Konfiguration vorgeben.
# Wo liegt die Installation, wenn mcs.conf (noch) fehlt? Im Heimatverzeichnis
# des Benutzers, dem der Server gehört. Bis 2026-08-28 stand hier fest
# "/home/pi" — auf jedem Pi mit einem anderen Benutzernamen zeigte der
# Rückfallwert damit stumm ins Leere. Siehe CLAUDE.md.
MCS_HOME="${HOME:-/home/$(id -un)}"
MCS_CONF="${MCS_CONF:-$MCS_HOME/mcs/mcs.conf}"
# shellcheck source=/dev/null
if [ -f "$MCS_CONF" ]; then . "$MCS_CONF"; fi

# Verzeichnis, in dem paper.jar und die Welten liegen.
MC_SERVER_DIR="${MCS_SERVER_DIR:-$MCS_HOME/mcs/mc_server}"

# Wie viel Arbeitsspeicher der Server bekommt.
# Der Pi 5 hat 8 GB: 3 GB für Minecraft, der Rest bleibt für das
# Betriebssystem, den Time-Machine-Dienst, das Admin-Tool und den
# Festplatten-Cache.
# 2026-07-27 von 4 G auf 3 G gesenkt: gemessen liegt das Live-Set nach
# der Garbage Collection bei 0.7–1.3 GB, mit 4 G blieben dem System
# unter Last nur noch ~1.4 GB statt der geforderten 2 GB.
# -Xms = Startgröße, -Xmx = Maximalgröße. Beide gleich zu setzen ist
# Standard bei Minecraft-Servern: so muss Java den Speicher nie
# nachträglich vergrößern, was Ruckler vermeidet.
MC_HEAP_GROESSE="${MCS_HEAP:-3G}"

# Name der Screen-Sitzung. Muss überall gleich sein
# (stop-minecraft.sh, Backup, mcs-CLI, Admin-Tool) — deshalb steht der
# Name in mcs.conf und nicht mehr in jedem Skript einzeln.
SCREEN_SITZUNG="${MCS_SCREEN_SESSION:-minecraft_server}"

# Welche Java-Version gebraucht wird, steht in versions.env (liegt neben
# diesem Skript).
SKRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=versions.env
if [ -f "$SKRIPT_DIR/versions.env" ]; then . "$SKRIPT_DIR/versions.env"; fi
JAVA_MIN="${MCS_JAVA_MIN:-21}"

# ----------------------------------------------------------------------------
# Java finden
# ----------------------------------------------------------------------------

# Zuerst im normalen Suchpfad schauen, dann als Ausweichlösung bei SDKMAN
# (falls Java darüber installiert wurde).
JAVA_BIN="$(command -v java 2>/dev/null || true)"
if [ -z "$JAVA_BIN" ] && [ -x "$MCS_HOME/.sdkman/candidates/java/current/bin/java" ]; then
  JAVA_BIN="$MCS_HOME/.sdkman/candidates/java/current/bin/java"
fi

if [ -z "$JAVA_BIN" ]; then
  echo "Fehler: Kein Java gefunden. Bitte zuerst Java installieren (siehe README)." >&2
  exit 1
fi

# Hauptversion ermitteln, z. B. "25" aus 'openjdk version "25.0.1"'.
# Sie entscheidet gleich darüber, welche Optimierungen mitgegeben werden
# dürfen — eine Option, die das installierte Java nicht kennt, lässt die
# JVM nicht etwa weg, sondern verweigert den Start komplett.
JAVA_MAJOR="$("$JAVA_BIN" -version 2>&1 | sed -nE 's/.*version "([0-9]+).*/\1/p' | head -n1)"

if [ -z "$JAVA_MAJOR" ]; then
  echo "Warnung: Java-Version von $JAVA_BIN nicht erkennbar — starte vorsichtshalber" >&2
  echo "ohne die zusätzlichen Speicheroptimierungen." >&2
  JAVA_MAJOR=0
elif [ "$JAVA_MAJOR" -lt "$JAVA_MIN" ]; then
  echo "Fehler: Installiert ist Java $JAVA_MAJOR, gebraucht wird mindestens Java $JAVA_MIN." >&2
  echo "Der Minecraft-Server würde damit nicht starten." >&2
  echo "Abhilfe: Betriebssystem aktualisieren oder Java von Adoptium installieren" >&2
  echo "(siehe README, Abschnitt Java), danach: mcs restart" >&2
  exit 1
fi

cd "$MC_SERVER_DIR" || {
  echo "Fehler: Konnte nicht in das Verzeichnis $MC_SERVER_DIR wechseln." >&2
  exit 1
}

if [ ! -f "paper.jar" ]; then
  echo "Fehler: $MC_SERVER_DIR/paper.jar fehlt. Bitte mcs update --festgelegt ausführen." >&2
  exit 1
fi

# Das Log-Verzeichnis muss existieren, BEVOR Java startet: die JVM schreibt
# ihr GC-Protokoll (siehe -Xlog weiter unten) nach logs/gc.log und legt
# dafür kein Verzeichnis an. Fehlt es, startet die JVM überhaupt nicht —
# und bei einer frischen Installation gibt es logs/ noch nicht, weil erst
# der Server selbst es anlegen würde.
mkdir -p logs

# ----------------------------------------------------------------------------
# Vorgemerkte Konfigurationsänderungen anwenden
# ----------------------------------------------------------------------------
# Warum es das gibt (Korrektur K3 im Lastenheft, am 28.08.2026 nachgemessen
# mit Paper 26.2 Build 119):
#
# Paper schreibt die server.properties neu, sobald ein Befehl eine dort
# gespeicherte Einstellung ändert — und zwar die GANZE Datei, aus dem
# Arbeitsspeicher. Ein "/whitelist add" eines Operators im Spiel genügt.
# Wer bei laufendem Server in diese Datei schreibt, verliert seine Änderung
# also möglicherweise, ohne dass jemand etwas merkt.
#
# Die Weboberfläche schreibt deshalb bei laufendem Server nicht direkt,
# sondern legt die vollständige neue Fassung hier ab. Dieser Block schiebt
# sie an ihren Platz — im einzigen Augenblick, in dem das gefahrlos ist:
# der Server ist noch nicht gestartet, und niemand hält die Datei im
# Arbeitsspeicher.
#
# Der Dateiname trägt den Pfad in sich: aus "config__paper-global.yml" wird
# "config/paper-global.yml". So gibt es keine zweite Liste, die mit der in
# admin/konfig.py auseinanderlaufen könnte.
VORGEMERKT_DIR="${MCS_VORGEMERKT_DIR:-${MCS_DIR:-$MCS_HOME/mcs}/vorgemerkt}"

# NICHTS in diesem Block darf den Serverstart verhindern.
#
# Das Skript läuft unter "set -e": Ein Befehl, der fehlschlägt, beendet es
# sofort. Genau das ist beim ersten Container-Lauf am 28.08.2026 passiert —
# eine Vormerkung, die einem anderen Benutzer gehörte, ließ sich nicht
# löschen, das `rm` scheiterte, und der Server startete GAR NICHT MEHR.
#
# Eine Einstellung, die nicht ankommt, ist ärgerlich. Ein Server, der wegen
# einer Einstellung nicht hochkommt, ist ein Ausfall. Deshalb ist jeder
# Schritt hier einzeln abgesichert und meldet nur, statt abzubrechen.
vorgemerktes_anwenden() {
  local VORMERKUNG ZIEL_REL ZIEL SICHERUNG

  [ -d "$VORGEMERKT_DIR" ] || return 0

  for VORMERKUNG in "$VORGEMERKT_DIR"/*; do
    [ -f "$VORMERKUNG" ] || continue

    ZIEL_REL="$(basename "$VORMERKUNG")"
    ZIEL_REL="${ZIEL_REL//__//}"
    ZIEL="$MC_SERVER_DIR/$ZIEL_REL"

    if [ ! -f "$ZIEL" ]; then
      echo "Vorgemerkt: $ZIEL_REL — Zieldatei fehlt, übersprungen." >&2
      continue
    fi

    # Die bisherige Fassung bleibt daneben liegen. Eine vorgemerkte
    # Änderung ist eine Änderung wie jede andere: Wer sie zurücknehmen
    # will, soll das können, ohne ein Backup auszupacken.
    SICHERUNG="${ZIEL}.vor-vormerkung-$(date +%Y%m%d-%H%M%S)"
    if ! cp -p "$ZIEL" "$SICHERUNG"; then
      echo "Vorgemerkt: $ZIEL_REL — Sicherungskopie fehlgeschlagen, nicht angewendet." >&2
      continue
    fi

    if ! cp "$VORMERKUNG" "$ZIEL"; then
      echo "Vorgemerkte Änderung an $ZIEL_REL FEHLGESCHLAGEN — sie bleibt liegen." >&2
      continue
    fi

    if rm -f "$VORMERKUNG"; then
      echo "Vorgemerkte Änderung angewendet: $ZIEL_REL"
    else
      # Angewendet, aber nicht weggeräumt: Beim nächsten Start käme sie
      # ein zweites Mal. Das ist harmlos (dieselbe Fassung), muss aber
      # gesagt werden — sonst wundert sich jemand, warum eine später von
      # Hand geänderte Einstellung immer wieder zurückspringt.
      echo "Vorgemerkte Änderung an $ZIEL_REL angewendet, ließ sich aber nicht" >&2
      echo "  löschen: $VORMERKUNG — bitte von Hand entfernen." >&2
    fi
  done
}

vorgemerktes_anwenden || echo "Vorgemerkte Änderungen übersprungen (siehe oben)." >&2

# ----------------------------------------------------------------------------
# Java-Optimierungen ("Aikar-Flags")
# ----------------------------------------------------------------------------
# Das sind die in der Minecraft-Community etablierten Einstellungen für die
# Java-Speicherverwaltung (Garbage Collector). Sie sorgen dafür, dass das
# Aufräumen des Speichers in vielen kleinen, kurzen Schritten passiert statt
# in seltenen langen Pausen — das verhindert spürbare Lags im Spiel.
# Quelle: https://docs.papermc.io/paper/aikars-flags
#
# Abweichung von den Original-Aikar-Flags (2026-07-27, gemessen):
#   -XX:+AlwaysPreTouch ist bewusst ENTFERNT. Es hat auf diesem Pi
#   4.4 GB RSS belegt, obwohl nur 354 MB Heap in Benutzung waren —
#   der Rest landete im zram-Swap. Der Arbeitsspeicher wird hier mit
#   dem Time-Machine-Dienst geteilt und ist als Page-Cache besser
#   angelegt. Details: docs/optimierung-2026-07-27.md im Repository.
# shellcheck disable=SC2054
# (Die Prüfsoftware hält die Kommas im -Xlog-Wert für Trennzeichen der
#  Liste. Sie gehören zur Option, deshalb ist die Warnung hier abgeschaltet.)
JAVA_FLAGS=(
  -Xms"$MC_HEAP_GROESSE"
  -Xmx"$MC_HEAP_GROESSE"
  -XX:+UseG1GC
  -XX:+ParallelRefProcEnabled
  -XX:MaxGCPauseMillis=200
  -XX:+UnlockExperimentalVMOptions
  -XX:+DisableExplicitGC
  # G1 gibt ungenutzten Heap sonst nie ans System zurueck (Default 0).
  # Alle 5 Minuten im Leerlauf aufraeumen und Regionen freigeben.
  -XX:G1PeriodicGCInterval=300000
  # GC-Protokoll, damit sich Pausen spaeter nachvollziehen lassen.
  # Rotierend, max. 5 x 5 MB — kostet praktisch nichts.
  -Xlog:gc*:file=logs/gc.log:time,uptime,level,tags:filecount=5,filesize=5M
  -XX:G1NewSizePercent=30
  -XX:G1MaxNewSizePercent=40
  -XX:G1HeapRegionSize=8M
  -XX:G1ReservePercent=20
  -XX:G1HeapWastePercent=5
  -XX:G1MixedGCCountTarget=4
  -XX:InitiatingHeapOccupancyPercent=15
  -XX:G1MixedGCLiveThresholdPercent=90
  -XX:G1RSetUpdatingPauseTimePercent=5
  -XX:SurvivorRatio=32
  -XX:+PerfDisableSharedMem
  -XX:MaxTenuringThreshold=1
  -Dusing.aikars.flags=https://mcflags.emc.gs
  -Daikars.new.flags=true
)

# -XX:+UseCompactObjectHeaders: 8 statt 12 Byte Objektkopf. Weniger
# Heap-Druck und bessere Cache-Ausnutzung auf dem Cortex-A76.
#
# Diese Option gibt es erst ab Java 24. Auf älterem Java verweigert die JVM
# mit "Unrecognized VM option" den Start — und weil systemd den Dienst nach
# zehn Sekunden neu startet, hätte man eine Endlosschleife statt einer
# Fehlermeldung. Deshalb wird sie nur angehängt, wenn das installierte Java
# sie auch kennt.
if [ "$JAVA_MAJOR" -ge 24 ]; then
  JAVA_FLAGS+=(-XX:+UseCompactObjectHeaders)
else
  echo "Hinweis: Java $JAVA_MAJOR kennt -XX:+UseCompactObjectHeaders noch nicht"
  echo "(gibt es ab Java 24) — der Server startet ohne diese Optimierung."
fi

# ----------------------------------------------------------------------------
# Start
# ----------------------------------------------------------------------------
# screen-Optionen:
#   -D -m  = Sitzung starten und im Vordergrund bleiben (kein Verdoppeln des
#            Prozesses). So kann systemd den Server direkt überwachen und
#            merkt sofort, wenn er abstürzt — ganz ohne PID-Dateien.
#   -S     = Name der Sitzung.
# `exec` ersetzt dieses Skript durch screen, damit systemd den
# Server-Prozess selbst als Hauptprozess sieht.
echo "Starte Minecraft-Server (Heap: $MC_HEAP_GROESSE, Screen-Sitzung: $SCREEN_SITZUNG)..."
# Der Startbefehl steht in lib-konsole.sh, damit der Umgang mit der Konsole
# an einer einzigen Stelle definiert ist (siehe dort).
# shellcheck source=lib-konsole.sh
. "$SKRIPT_DIR/lib-konsole.sh"

# Vor dem Start aufräumen: Stirbt Java hart, bleibt der Sockel der alten
# Sitzung als "(Dead ???)" liegen, und `Restart=always` startet die nächste
# daneben. Nach ein paar Abstürzen stehen mehrere Sitzungen gleichen Namens
# in `screen -ls`, und die Auswahl für `-X stuff` wird mehrdeutig. Der
# Serverstart ist der richtige Moment dafür: Hier ist sicher keine lebende
# Sitzung offen, die man versehentlich abräumen könnte.
konsole_abraeumen

konsole_starten "$JAVA_BIN" "${JAVA_FLAGS[@]}" -jar paper.jar nogui
