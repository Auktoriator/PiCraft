#!/bin/bash
#
# install.sh — Richtet den kompletten Minecraft-Server auf dem Raspberry Pi ein.
#
# Was dieses Skript macht (in dieser Reihenfolge):
#   0. Vorab prüfen: Benutzer, sudo-Rechte, Internet, freier Platz
#   1. Verzeichnisse unter ~/mcs anlegen und alle Skripte dorthin kopieren
#   2. Benötigte Programme installieren (Java, screen, jq, curl, unzip)
#   3. Die in server/versions.env festgelegte Paper-Version herunterladen
#      (nur, wenn noch keine da ist — mit Prüfsummen-Kontrolle)
#   4. Server konfigurieren (EULA, server.properties-Vorlage)
#   5. systemd-Dienste einrichten (Autostart bei jedem Booten)
#   6. Tägliches Backup um 4 Uhr nachts und Protokoll-Rotation einrichten
#   7. Den Server starten
#
# Aufruf als Benutzer "pi" (NICHT mit sudo davor — das Skript fragt selbst
# nach dem Passwort, wenn es Administratorrechte braucht):
#
#   ./install.sh
#
# Das Skript kann gefahrlos mehrfach ausgeführt werden. Bestehende Welten,
# Einstellungen und Backups werden dabei nicht angetastet, und die
# Minecraft-Version bleibt unverändert — Aktualisieren ist bewusst Sache
# von "mcs update".
#
# Zum Ausrollen von Änderungen an den Skripten reicht das kleinere
# ./deploy.sh: es kopiert nur Dateien und fasst weder Pakete noch
# Serverdateien an.

# -E sorgt dafür, dass die ERR-Falle weiter unten auch INNERHALB von
# Funktionen greift. Ohne dieses Flag gilt sie nur auf oberster Ebene —
# und da passiert hier fast nichts.
set -Eeuo pipefail

# ----------------------------------------------------------------------------
# Globale Pfade
# ----------------------------------------------------------------------------
# Verzeichnis dieses Repos (Quelle der Dateien)
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Wer installiert, und wohin? Beides wird ERMITTELT, nicht angenommen.
#
# Bis 2026-08-28 stand hier "pi" aus der Repo-Fassung von mcs.conf, und die
# Vorprüfung brach ab, sobald jemand anders hieß. Seit Raspberry Pi OS
# Bookworm (2022) legt der Imager aber gar keinen Benutzer "pi" mehr an —
# jeder wählt beim Schreiben der Karte seinen eigenen Namen. Für alle, die
# das Standardimage benutzen, war die Installation damit unbrauchbar.
MCS_USER="$(id -un)"
MCS_HOME="${HOME:-/home/$MCS_USER}"
MC_DIR="${MCS_DIR:-$MCS_HOME/mcs}"

# Eine bereits erzeugte mcs.conf auf dem PI hat Vorrang: dort stehen die
# Werte, mit denen der Server wirklich läuft. Im Repository liegt nur noch
# die Vorlage mcs.conf.beispiel — sie wird nie eingelesen.
MCS_CONF="${MCS_CONF:-$MC_DIR/mcs.conf}"
# shellcheck source=/dev/null
if [ -f "$MCS_CONF" ]; then . "$MCS_CONF"; fi

# Welche Versionen installiert werden (Java, Paper) — siehe server/versions.env.
# shellcheck source=server/versions.env
if [ -f "$REPO_DIR/server/versions.env" ]; then . "$REPO_DIR/server/versions.env"; fi
JAVA_MIN="${MCS_JAVA_MIN:-21}"
JAVA_EMPFOHLEN="${MCS_JAVA_EMPFOHLEN:-25}"

# Zielstruktur auf dem Pi. Gab es schon eine mcs.conf, hat sie diese Werte
# oben bereits gesetzt; sonst gelten die ermittelten.
MCS_USER="${MCS_USER:-$(id -un)}"
MC_DIR="${MCS_DIR:-$MCS_HOME/mcs}"                            # Hauptverzeichnis
MC_SERVER_DIR="${MCS_SERVER_DIR:-$MC_DIR/mc_server}"          # Server (paper.jar, Welten, Konfiguration)
MC_BACKUP_DIR="${MCS_BACKUP_DIR:-$MC_DIR/mcs_backup}"         # Backups + Backup-Skript
SERVICE_DIR="/etc/systemd/system"                             # systemd-Dienste

# ----------------------------------------------------------------------------
# Aufrufparameter
# ----------------------------------------------------------------------------
ASSISTENT_STANDARD=false

# Die Weboberfläche wird IMMER mitinstalliert, ausser man sagt beim Aufruf
# ausdrücklich das Gegenteil (Lastenheft 5.1). Der Assistent fragt zwar auch
# danach — aber nur, wenn jemand da ist, der antworten kann. Wer skriptet
# oder "--standard" benutzt, hatte bis 2026-08-30 keine Möglichkeit, sie
# abzuwählen: Der Schnellmodus nimmt überall die Empfehlung, und die lautet
# "ja".
OHNE_OBERFLAECHE=false

while [ $# -gt 0 ]; do
  case "$1" in
    --standard|--schnell|-y)
      # Alle Empfehlungen übernehmen, nichts fragen. Braucht der
      # Container-Abnahmetest, der ohne Terminal läuft.
      ASSISTENT_STANDARD=true
      ;;
    --ohne-oberflaeche|--ohne-weboberflaeche)
      OHNE_OBERFLAECHE=true
      ;;
    -h|--hilfe|--help)
      cat <<'ENDE'
install.sh — PiCraft installieren

  ./install.sh                     Geführte Installation mit Fragen
  ./install.sh --standard          Ohne Rückfragen, überall die Empfehlung
  ./install.sh --ohne-oberflaeche  Weboberfläche NICHT mitinstallieren
  ./install.sh --hilfe             Diese Übersicht

Die geführte Fassung erklärt jede Einstellung und schlägt einen Wert vor;
die Eingabetaste übernimmt ihn. Verändert wird erst nach der
Zusammenfassung etwas — bis dahin ist Abbrechen folgenlos.
ENDE
      exit 0
      ;;
    *)
      echo "Unbekannter Parameter: $1" >&2
      echo "Erlaubt: --standard | --ohne-oberflaeche | --hilfe" >&2
      exit 1
      ;;
  esac
  shift
done

# ----------------------------------------------------------------------------
# Kein Terminal da? Dann fragen wir nicht — aber greifen auch nicht durch.
# ----------------------------------------------------------------------------
# Ohne Terminal (Pipe, Cronjob, CI, `./install.sh < /dev/null`) kann niemand
# antworten. Bis 2026-08-26 schaltete das Skript dann einfach in den
# Schnellmodus — und der nimmt ÜBERALL die Empfehlung, also auch
# "Firewall einrichten: ja".
#
# Auf einem Homeserver ist das ein Desaster: ufw hätte mit
# "default deny incoming" alles zugemacht und nur SSH und den
# Minecraft-Port offen gelassen. Auf genau diesem Pi wären damit der
# Time-Machine-Dienst (445), Home Assistant (8123) und das ganze Dashboard
# ausgesperrt gewesen — durch einen Aufruf, den niemand als Eingriff gelesen
# hätte.
#
# Deshalb zwei getrennte Dinge:
#   --standard          ausdrücklich gewollt: alle Empfehlungen, ja heißt ja
#   kein Terminal       vorsichtig: der Server wird eingerichtet, aber es
#                       wird NICHTS am übrigen System verändert
ASSISTENT_VORSICHTIG=false
if [ ! -t 0 ] && [ "$ASSISTENT_STANDARD" = false ]; then
  ASSISTENT_STANDARD=true
  ASSISTENT_VORSICHTIG=true
fi

export ASSISTENT_STANDARD ASSISTENT_VORSICHTIG OHNE_OBERFLAECHE
# shellcheck source=lib/assistent.sh
. "$REPO_DIR/lib/assistent.sh"
# lib/hardware.sh MUSS vor lib/fragen.sh kommen: Die Fragen leiten ihre
# Vorschläge aus dem ab, was dort über das Gerät ermittelt wird.
# shellcheck source=lib/hardware.sh
. "$REPO_DIR/lib/hardware.sh"
# shellcheck source=lib/fragen.sh
. "$REPO_DIR/lib/fragen.sh"
# Welche Dateien auf den Pi gehoeren — dieselbe Liste, die deploy.sh benutzt.
# shellcheck source=lib/dateien.sh
. "$REPO_DIR/lib/dateien.sh"

# ----------------------------------------------------------------------------
# Abbruch verständlich machen
# ----------------------------------------------------------------------------
# Bricht das Skript mittendrin ab, soll man sehen, WO. Vorher stand da nur
# eine Fehlermeldung des jeweiligen Programms, und man musste raten, wie
# weit die Installation gekommen war.
SCHRITT="Vorbereitung"

bei_fehler() {
  echo "" >&2
  echo "================================================================" >&2
  echo " ABBRUCH im Schritt: $SCHRITT" >&2
  echo "================================================================" >&2
  echo "Die Installation ist unvollständig. Die Ursache steht in den" >&2
  echo "Zeilen darüber." >&2
  echo "" >&2
  echo "Nach dem Beheben einfach erneut starten:  ./install.sh" >&2
  echo "Bereits erledigte Schritte werden dabei übersprungen, bestehende" >&2
  echo "Welten und Einstellungen nicht angetastet." >&2
  exit 1
}
trap bei_fehler ERR

# ----------------------------------------------------------------------------
# setze_zeile DATEI SCHLUESSEL WERT — einen Wert in einer .properties/.env-Datei
# ----------------------------------------------------------------------------
# Ersetzt die Zeile "SCHLUESSEL=..." oder hängt sie an, wenn es sie nicht gibt.
#
# Bewusst OHNE sed: In einer sed-Ersetzung ist "&" der GESAMTE TREFFER und "|"
# beendet den Ausdruck. Ein Weltname "meine&welt" ergab damit
#     level-name=meinelevel-name=worldwelt
# und ein "|" darin brach sed ganz ab — mitten in der Installation, mit halb
# geschriebener server.properties. Die Schleife hier kennt keine Metazeichen:
# Sie vergleicht Präfixe und schreibt Werte wörtlich.
#
# Die Temporärdatei liegt NEBEN der Zieldatei, nicht in /tmp. Zwei Gründe:
# ein "mv" über Dateisystemgrenzen ist ein Kopiervorgang und damit nicht
# atomar (eine Unterbrechung ließe eine abgeschnittene server.properties
# zurück), und die Rechte der Zieldatei bleiben so erhalten — mktemp legt
# mit 0600 an, was aus einer 0644-Datei eine für andere unlesbare machen
# würde.
setze_zeile() {
  local ZIEL="$1" SCHLUESSEL="$2" WERT="$3" ZEILE TMP GEFUNDEN=false
  TMP="$(mktemp "$(dirname "$ZIEL")/.$(basename "$ZIEL").XXXXXX")"

  # Rechte und Eigentümer der Zieldatei übernehmen, bevor sie ersetzt wird.
  if [ -f "$ZIEL" ]; then
    chmod --reference="$ZIEL" "$TMP" 2>/dev/null || chmod 0644 "$TMP"
  else
    chmod 0644 "$TMP"
  fi

  while IFS= read -r ZEILE || [ -n "$ZEILE" ]; do
    if [ "${ZEILE%%=*}" = "$SCHLUESSEL" ] && [ "${ZEILE#*=}" != "$ZEILE" ]; then
      printf '%s=%s\n' "$SCHLUESSEL" "$WERT" >> "$TMP"
      GEFUNDEN=true
    else
      printf '%s\n' "$ZEILE" >> "$TMP"
    fi
  done < "$ZIEL"

  [ "$GEFUNDEN" = true ] || printf '%s=%s\n' "$SCHLUESSEL" "$WERT" >> "$TMP"
  mv "$TMP" "$ZIEL"
}

# Einen Wert so aufbereiten, dass ihn alle drei Leser der mcs.conf gleich
# verstehen: die Shell (`. mcs.conf`), systemd (`EnvironmentFile=`) und Python.
#
# Nur fuer die mcs.conf, NICHT fuer server.properties -- Paper liest seine
# Werte roh und bekaeme die Anfuehrungszeichen als Teil des Wertes.
#
# Ein Einhaengepunkt wie "/media/pi/My Passport" zerlegte die Shell bisher in
# zwei Woerter und versuchte das zweite auszufuehren ("Passport: command not
# found", 127). Unter "set -euo pipefail" starb daran jedes Backup, und zwar
# in der Source-Zeile -- also vor jedem trap und jedem Merkzettel: lautlos.
#
# Am 2026-08-31 gemessen, weil das Naheliegende hier falsch ist:
#   'wert'  Shell und systemd nehmen es beide woertlich.        richtig
#   "wert"  systemd nimmt es woertlich, die Shell aber nicht:
#           MCS_X="/pfad/$(id -un)" fuehrt beim Einlesen id aus.
mcs_conf_wert() {
  case "$1" in
    *"'"*|*$'\n'*)
      echo "Fehler: Der Wert darf weder ein einfaches Anführungszeichen noch" >&2
      echo "        einen Zeilenumbruch enthalten: $1" >&2
      return 1 ;;
  esac
  # Harmlose Werte bleiben nackt -- das haelt die Datei lesbar.
  case "$1" in
    *[!A-Za-z0-9_./:@%+,=-]*) printf "'%s'" "$1" ;;
    *)                        printf '%s' "$1" ;;
  esac
}

# ----------------------------------------------------------------------------
# pfad_ist_schlicht PFAD — nur Zeichen, die jeder Leser unverändert nimmt
# ----------------------------------------------------------------------------
# Der Installationsort landet an drei Stellen, die ihn alle ohne Quoting
# weiterreichen: nackt in der mcs.conf (MCS_DIR=__BASIS__), per sed mit "#"
# als Trennzeichen in die systemd-Einheiten, und dort als Pfad, in dem "%"
# ein Platzhalter ist. Ein Leerzeichen — "/mnt/Meine SSD" — zerlegte die
# Shell beim Einlesen der mcs.conf in zwei Wörter (am 23.09.2026 gemessen:
# "SSD/mcs/...: No such file or directory", MCS_DIR leer). Dieselbe Falle
# wie beim Backup-Ziel, siehe mcs_conf_wert — nur dass hier jedes Skript
# daran stirbt, nicht bloss das Backup. Also gar nicht erst annehmen.
pfad_ist_schlicht() {
  case "$1" in
    *[!A-Za-z0-9_./+-]*) return 1 ;;
  esac
}

# ----------------------------------------------------------------------------
# Vorab-Prüfungen
# ----------------------------------------------------------------------------
# Lieber hier abbrechen als mitten in Schritt 3 — dann steht das System
# noch genau so da wie vorher.
vorpruefung() {
  SCHRITT="Vorab-Prüfungen"
  echo ""
  echo "===== 0/7: Vorab-Prüfungen ====="

  # a) Nicht als root starten. Das Skript fragt selbst nach dem Passwort,
  #    wenn es Administratorrechte braucht — läuft es komplett als root,
  #    gehören anschließend alle Dateien root statt dem spielenden Benutzer.
  if [ "$(id -u)" -eq 0 ]; then
    echo "Fehler: Bitte NICHT mit sudo starten." >&2
    echo "Einfach './install.sh' als der Benutzer, dem der Server gehören soll." >&2
    exit 1
  fi

  #    Gibt es hier schon eine Installation, muss sie zum angemeldeten
  #    Benutzer passen — sonst schreibt die Installation Dateien, die der
  #    Dienst später nicht lesen kann.
  if [ "$MCS_USER" != "$(id -un)" ]; then
    echo "Fehler: Die vorhandene Installation in $MC_DIR gehört dem Benutzer '$MCS_USER'," >&2
    echo "angemeldet bist du aber als '$(id -un)'." >&2
    echo "Entweder als '$MCS_USER' anmelden — oder MCS_USER in" >&2
    echo "$MC_DIR/mcs.conf anpassen und die Dateirechte mitziehen." >&2
    exit 1
  fi

  # b) Liegt der Git-Checkout versehentlich IM Zielverzeichnis? Dann würde
  #    das Skript Dateien auf sich selbst kopieren und mittendrin abbrechen.
  case "$REPO_DIR/" in
    "$MC_DIR"/*)
      echo "Fehler: Dieses Repository liegt unter $MC_DIR." >&2
      echo "Der Git-Checkout und die laufende Installation müssen in getrennten" >&2
      echo "Ordnern liegen — sonst kopiert die Installation Dateien auf sich selbst." >&2
      echo "Empfehlung: Repository nach ~/PiCraft verschieben." >&2
      exit 1
      ;;
  esac

  #    Und beide Orte dürfen nur schlichte Zeichen enthalten (siehe
  #    pfad_ist_schlicht). Geprüft wird HIER und nicht nur bei der Frage
  #    nach dem Ort: MCS_DIR aus der Umgebung und --standard fragen nicht.
  local ORT
  for ORT in "$MC_DIR" "$REPO_DIR"; do
    if ! pfad_ist_schlicht "$ORT"; then
      echo "Fehler: Der Pfad '$ORT' enthält Leerzeichen oder Sonderzeichen." >&2
      echo "Erlaubt sind Buchstaben ohne Umlaute, Ziffern und . _ - + /" >&2
      echo "Die Pfade stehen ungeschützt in mcs.conf und den systemd-Diensten." >&2
      exit 1
    fi
  done

  # c) Darf dieser Benutzer überhaupt sudo? Ohne sudo kann das Skript keine
  #    Programme installieren und keine Dienste einrichten — das fiel früher
  #    erst mitten in Schritt 1 auf, mit halb fertiger Installation.
  #
  #    Hier stand bis 2026-08-29 ein blosses "sudo -v". Das ist genau der
  #    falsche Befehl: -v frischt den Zeitstempel der Passworteingabe auf und
  #    verlangt dafuer ein Terminal -- auch dann, wenn der Benutzer
  #    "NOPASSWD: ALL" hat und es gar kein Passwort zu pruefen gibt. Auf dem
  #    Pi (Regel 010_pi-nopasswd) brach "./install.sh --standard" deshalb
  #    sofort ab:
  #
  #      sudo: a terminal is required to read the password
  #      Fehler: 'pi' darf kein sudo ausfuehren
  #
  #    Ausgerechnet der Modus fuer Skripte und Tests war damit unbenutzbar,
  #    und die Meldung zeigte in die falsche Richtung: Sie behauptete ein
  #    fehlendes Recht, wo nur ein fehlendes Terminal war.
  #
  #    Richtig ist die Fallunterscheidung: Erst passwortlos versuchen (-n
  #    fragt nie nach). Klappt das nicht, kann trotzdem alles in Ordnung
  #    sein -- der Benutzer darf sudo, nur eben mit Passwort. Das laesst sich
  #    aber nur mit Terminal klaeren.
  if ! sudo -n true 2>/dev/null; then
    if [ -t 0 ]; then
      # Terminal da: nachfragen ist erlaubt.
      if ! sudo -v; then
        echo "Fehler: '$MCS_USER' darf kein sudo ausführen (oder das Passwort war falsch)." >&2
        echo "Ohne Administratorrechte lassen sich weder Programme installieren" >&2
        echo "noch Dienste einrichten." >&2
        exit 1
      fi
    else
      echo "Fehler: sudo verlangt hier ein Passwort, aber es gibt kein Terminal," >&2
      echo "über das danach gefragt werden könnte." >&2
      echo "" >&2
      echo "Entweder das Skript in einem Terminal starten, oder vorher einmal" >&2
      echo "'sudo -v' ausführen, damit die Berechtigung noch gültig ist." >&2
      exit 1
    fi
  fi

  # d) Ist das Internet erreichbar? Ohne Netz gibt es weder Pakete noch Paper.
  if ! curl -fsS --max-time 15 -o /dev/null https://fill.papermc.io/v3/projects/paper; then
    echo "Fehler: Die PaperMC-Server sind nicht erreichbar." >&2
    echo "Bitte Netzwerkverbindung prüfen und erneut starten." >&2
    exit 1
  fi

  # e) Genug Platz? Server, Welt und zehn Backups brauchen Luft.
  #    Gemessen wird das Dateisystem, auf dem die Installation landet.
  local PRUEF_PFAD="$MC_DIR"
  while [ ! -d "$PRUEF_PFAD" ] && [ "$PRUEF_PFAD" != "/" ]; do
    PRUEF_PFAD="$(dirname "$PRUEF_PFAD")"
  done
  local FREI_GB
  FREI_GB=$(df -BG --output=avail "$PRUEF_PFAD" 2>/dev/null | tail -n1 | tr -dc '0-9')
  if [ -n "$FREI_GB" ] && [ "$FREI_GB" -lt 5 ]; then
    echo "Fehler: Auf $PRUEF_PFAD sind nur ${FREI_GB} GB frei." >&2
    echo "Für Server, Welt und Backups sollten mindestens 5 GB verfügbar sein." >&2
    exit 1
  fi

  echo "Benutzer, Speicherplatz, sudo-Rechte und Internetverbindung sind in Ordnung."

  # f) Was für ein Gerät ist das hier, und worauf soll der Server laufen?
  #
  #    Das Lastenheft (5.1) verlangt: "Alles ermitteln, nichts annehmen."
  #    Der wichtigste Punkt darin ist das Speichermedium — eine SD-Karte
  #    kostet mehr Leistung als jede Einstellung dieses Assistenten
  #    zurückholen kann, und sie geht am Ende kaputt.
  #
  #    Kein Abbruch: Was hier steht, ist eine Auskunft, keine Bedingung.
  #    Wer auf einer SD-Karte installieren will, darf das — er soll es nur
  #    vorher gelesen haben (Leitsatz 5, "ehrlich statt bequem").
  echo ""
  hardware_bericht "$MC_DIR" "$MC_BACKUP_DIR"

  # g) Ist Port 8080 frei? (Befund B6, Lastenheft 5.1)
  #
  #    Ausgewichen wird erst in install-admin.sh, und dort steht es auch
  #    ausführlich. Gemeldet gehört es aber HIER: Das Lastenheft verlangt,
  #    dass vor den Fragen steht, was die Installation über die Umgebung
  #    weiss. Wer erst in Schritt 6 erfährt, dass ein anderer Dienst den
  #    Port belegt, hat die Entscheidung über die Weboberfläche längst
  #    getroffen.
  #
  #    8080 ist ausgerechnet auch die Voreinstellung von Pl3xMap, dem
  #    Kartenplugin dieses Projekts.
  if command -v ss >/dev/null 2>&1; then
    if ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE '[:.]8080$'; then
      local BELEGER
      BELEGER=$(ss -ltnp 2>/dev/null | awk '/[:.]8080 / {print $NF}' \
                | grep -oE '"[^"]+"' | head -n1 | tr -d '"') || BELEGER=""
      printf '  %sPort 8080 ist belegt%s%s. Die Weboberfläche weicht dann auf\n' \
        "${F_GELB:-}" "${BELEGER:+ (von $BELEGER)}" "${F_AUS:-}"
      printf '  den nächsten freien Port aus und sagt am Ende, welcher es ist.\n\n'
    fi
  fi

  #    Anhalten nur, wenn es etwas zu bedenken gab UND jemand da ist, der
  #    zustimmen könnte. Ohne Terminal (CI, Container-Abnahmetest) liefe
  #    eine Rückfrage ins Leere und würde die Installation aufhängen.
  if [ "${HARDWARE_BEDENKEN:-false}" = true ] && [ -t 0 ] \
     && [ "$ASSISTENT_STANDARD" != true ]; then
    printf '  Weiter mit der Eingabetaste, abbrechen mit Strg+C. '
    read -r _ || true
    echo ""
  fi
}

# ----------------------------------------------------------------------------
# Hilfsfunktion: eine systemd-Dienstdatei installieren
# ----------------------------------------------------------------------------
# Die Dienstdateien im Repo enthalten die Standardpfade im Klartext — so kann
# man sie lesen, ohne Platzhalter im Kopf auflösen zu müssen. Wer in mcs.conf
# andere Pfade einträgt, bekommt sie hier automatisch eingesetzt. Bei den
# Standardwerten ändert sed nichts.
dienst_installieren() {
  local QUELLE="$1"
  local ZIEL
  ZIEL="$SERVICE_DIR/$(basename "$QUELLE")"

  # Environment=MCS_USER: die USB-Kopie läuft als root und liest den
  # Benutzer deshalb nicht aus der mcs.conf, sondern aus ihrer Einheit.
  sed -e "s#/home/pi/mcs#${MC_DIR}#g" \
      -e "s#^User=pi\$#User=${MCS_USER}#" \
      -e "s#^Group=pi\$#Group=${MCS_USER}#" \
      -e "s#^Environment=MCS_USER=pi\$#Environment=MCS_USER=${MCS_USER}#" \
      "$QUELLE" | sudo tee "$ZIEL" >/dev/null
  sudo chmod 644 "$ZIEL"
}

# ----------------------------------------------------------------------------
# 1) Verzeichnisse anlegen und Dateien kopieren
# ----------------------------------------------------------------------------
verzeichnisse_einrichten() {
  echo ""
  echo "===== 1/7: Verzeichnisse anlegen und Skripte kopieren ====="
  SCHRITT="Verzeichnisse und Skripte"

  # Das Dauerarchiv wurde bisher nie angelegt — dadurch hat das
  # Backup-Skript es auf jeder frischen Installation stillschweigend
  # übersprungen, und der Schutz vor der Rotation war wirkungslos.
  mkdir -p "$MC_SERVER_DIR" "$MC_BACKUP_DIR" "${MCS_ARCHIV_DIR:-$MC_DIR/weltarchiv}"

  # Die zentralen Einstellungen. Diese Datei gehört seit 2026-08-28 dem PI,
  # nicht mehr dem Repository: Sie wird einmal aus mcs.conf.beispiel erzeugt
  # und danach nie wieder überschrieben.
  #
  # Warum die Umstellung? Vorher lag dieselbe Datei im Repo UND auf dem Pi.
  # Jede Installation kopierte die Repo-Fassung darüber und rettete dabei
  # genau zwei Werte (Heap und Zweitziel) — alles andere, was jemand
  # eingetragen hatte, fiel stillschweigend zurück. Und ein frischer Klon
  # brachte die Pfade eines fremden Rechners mit, samt eines Benutzers "pi",
  # den es seit Bookworm gar nicht mehr gibt.
  #
  # Jetzt gilt: Ist sie da, bleibt sie. Punkt. Das macht einen zweiten
  # Installationslauf endlich wirklich folgenlos.
  if [ -f "$MC_DIR/mcs.conf" ]; then
    echo "mcs.conf ist vorhanden und bleibt unangetastet."
    echo "  Werte ändern:  nano $MC_DIR/mcs.conf     (danach: mcs restart)"
  else
    # Die Platzhalter der Vorlage durch die ermittelten Werte ersetzen.
    # Als Trennzeichen dient '#', weil in Pfaden Schrägstriche vorkommen.
    sed -e "s#__BENUTZER__#${MCS_USER}#g" \
        -e "s#__BASIS__#${MC_DIR}#g" \
        -e "s#__REPO__#${REPO_DIR}#g" \
        "$REPO_DIR/mcs.conf.beispiel" > "$MC_DIR/mcs.conf"
    echo "mcs.conf erzeugt (Benutzer: $MCS_USER, Ort: $MC_DIR)."
  fi

  # Die Dateien der Installation. WELCHE es sind, steht in lib/dateien.sh —
  # in derselben Liste, aus der auch deploy.sh ausrollt. Dort stehen auch die
  # Begruendungen je Datei (warum versions.env dem Repo gehoert, warum
  # plugins.txt dem Pi, warum hardware.sh flach liegt).
  mcs_dateiliste
  for EINTRAG in "${MCS_DATEIEN[@]}"; do
    IFS='|' read -r QUELLE ZIEL MODUS <<<"$EINTRAG"

    # Eine Vorlage wird nur angelegt, wenn sie fehlt — ab dem ersten Start
    # gehoert die Datei dem Pi.
    if [ "$MODUS" = "nur-wenn-fehlt" ] && [ -f "$ZIEL" ]; then
      continue
    fi

    # Eine fehlende Quelle ist ein Grund zum Melden, aber keiner, eine
    # Installation abzubrechen (die VERSION fehlt etwa in manchem Tarball).
    # Ausdruecklich als "if": Hier gilt "set -e", und eine fehlgeschlagene
    # &&-Kette beendet das Skript.
    if [ ! -f "$QUELLE" ]; then
      echo "  ! fehlt im Repo: ${QUELLE#"$REPO_DIR"/}"
      continue
    fi

    mkdir -p "$(dirname "$ZIEL")"
    cp "$QUELLE" "$ZIEL"
    case "$ZIEL" in *.sh) chmod +x "$ZIEL" ;; esac
  done

  # duckdns.sh gibt es seit Etappe D nicht mehr im Repository: Es ist in
  # dns-update.sh aufgegangen, das beide Anbieter kann und zusätzlich
  # IPv6 und SRV-Einträge beherrscht.
  #
  # GELÖSCHT WIRD DIE ALTE DATEI ABER NICHT. Wer sie benutzt hat, hat dafür
  # einen Cronjob eingerichtet — und ein Cronjob, dessen Skript auf einmal
  # weg ist, scheitert jede fünf Minuten still vor sich hin. Statt dessen
  # wird gesagt, was zu tun ist. Entscheiden darf das der Nutzer.
  if [ -f "$MC_DIR/duckdns.sh" ]; then
    echo ""
    echo "Hinweis: $MC_DIR/duckdns.sh stammt aus einer früheren Fassung."
    echo "  Ersetzt durch dns-update.sh — dasselbe für DuckDNS, dazu deSEC,"
    echo "  IPv6 und SRV-Einträge, und es läuft über einen systemd-Timer"
    echo "  statt über Cron (geht damit bei 'mcs aus' mit aus)."
    echo "  Einrichten in der Weboberfläche unter \"Konfiguration\"."
    if crontab -l 2>/dev/null | grep -Fq "duckdns.sh"; then
      echo "  ACHTUNG: In deiner Crontab steht noch ein Eintrag dafür."
      echo "  Er läuft weiter. Entfernen mit:  crontab -e"
    fi
    echo "  Die alte Datei wird nicht angetastet."
    echo ""
  fi

  # Was root gehört: das Verwaltungswerkzeug "mcs" (systemweit verfügbar),
  # die USB-Kopie und ihre udev-Regel. Die Liste steht in lib/dateien.sh,
  # dieselbe wie in deploy.sh.
  local EINTRAG QUELLE ZIEL RECHTE
  mcs_systemdateien
  for EINTRAG in "${MCS_SYSTEMDATEIEN[@]}"; do
    IFS='|' read -r QUELLE ZIEL RECHTE <<<"$EINTRAG"
    sudo mkdir -p "$(dirname "$ZIEL")"
    mcs_systemdatei_inhalt "$QUELLE" | sudo tee "$ZIEL" >/dev/null
    sudo chmod "$RECHTE" "$ZIEL"
  done
  # Im Container gibt es kein laufendes udev; dort ist das kein Fehler.
  sudo udevadm control --reload 2>/dev/null || true

  # Überreste älterer Versionen dieses Setups entfernen (falls vorhanden)
  rm -f "$MC_DIR/startmcs.sh" "$MC_DIR/stopmcs.sh" "$MC_DIR/statusmcs.sh" \
        "$MC_SERVER_DIR/paperupdate.sh" "$MC_SERVER_DIR/minecraft.pid"

  echo "Verzeichnisse und Skripte sind eingerichtet."
}

# ----------------------------------------------------------------------------
# 2) Software installieren
# ----------------------------------------------------------------------------
# Ermittelt die Hauptversion des gerade erreichbaren Java (z. B. "25").
# Gibt nichts aus, wenn gar kein Java installiert ist.
java_hauptversion() {
  command -v java >/dev/null 2>&1 || return 0
  java -version 2>&1 | sed -nE 's/.*version "([0-9]+).*/\1/p' | head -n1
}

# Richtet die Paketquelle von Adoptium ein. Die Debian-Quellen führen nur
# ältere Java-Versionen; Adoptium (das Projekt hinter Temurin) liefert
# aktuelle Fassungen auch für ARM64, also für den Pi.
adoptium_quelle_einrichten() {
  echo "Richte die Adoptium-Paketquelle ein (aktuelles Java für ARM64)..."
  sudo apt-get install -y wget apt-transport-https gnupg
  wget -qO- https://packages.adoptium.net/artifactory/api/gpg/key/public \
    | sudo tee /etc/apt/trusted.gpg.d/adoptium.asc >/dev/null
  local CODENAME
  CODENAME=$(. /etc/os-release && echo "${VERSION_CODENAME:-}")
  if [ -z "$CODENAME" ]; then
    echo "Hinweis: Debian-Ausgabename nicht erkannt — Adoptium wird übersprungen."
    return 1
  fi
  echo "deb https://packages.adoptium.net/artifactory/deb ${CODENAME} main" \
    | sudo tee /etc/apt/sources.list.d/adoptium.list >/dev/null
  sudo apt-get update
}

software_installieren() {
  echo ""
  echo "===== 2/7: Software installieren (Java, screen, jq, curl) ====="
  SCHRITT="Software installieren"

  sudo apt-get update

  # screen    = unsichtbares Terminal für die Server-Konsole
  # jq        = liest die Antworten der PaperMC-Download-API
  # curl      = lädt Dateien aus dem Internet
  # unzip     = liest Name und Version aus Plugin-Dateien
  # logrotate = hält die Protokolldateien klein (Schritt 6)
  sudo apt-get install -y screen jq curl unzip logrotate

  # --- Java -----------------------------------------------------------------
  # Gebraucht werden zwei Zahlen aus server/versions.env:
  #   JAVA_MIN        darunter startet der Server gar nicht
  #   JAVA_EMPFOHLEN  bringt zusätzlich -XX:+UseCompactObjectHeaders mit
  #
  # Reihenfolge: erst die empfohlene Version aus den Debian-Quellen, dann
  # über Adoptium, dann die Mindestversion aus den Debian-Quellen.
  echo "Suche Java $JAVA_EMPFOHLEN (Mindestversion: $JAVA_MIN)..."

  if [ "$(java_hauptversion)" = "$JAVA_EMPFOHLEN" ]; then
    echo "Java $JAVA_EMPFOHLEN ist bereits installiert."
  elif sudo apt-get install -y "openjdk-${JAVA_EMPFOHLEN}-jre-headless"; then
    echo "Java $JAVA_EMPFOHLEN aus den Debian-Quellen installiert."
  elif adoptium_quelle_einrichten && sudo apt-get install -y "temurin-${JAVA_EMPFOHLEN}-jre"; then
    echo "Java $JAVA_EMPFOHLEN von Adoptium installiert."
  else
    echo ""
    echo "Hinweis: Java $JAVA_EMPFOHLEN war nicht zu bekommen."
    echo "Versuche die Mindestversion $JAVA_MIN — der Server läuft damit,"
    echo "verzichtet aber auf eine Speicheroptimierung (siehe README)."
    sudo apt-get install -y "openjdk-${JAVA_MIN}-jre-headless" \
      || sudo apt-get install -y default-jre-headless \
      || true
  fi

  # Kontrolle: Ist das installierte Java gut genug? Früher hat das Skript
  # hier nur gewarnt und weitergemacht — der Server startete anschließend
  # nie, und niemand wusste warum. Jetzt bricht die Installation ab.
  local JAVA_MAJOR
  JAVA_MAJOR="$(java_hauptversion)"

  if [ -z "$JAVA_MAJOR" ]; then
    echo ""
    echo "FEHLER: Es ist überhaupt kein Java installiert."
    echo "Ohne Java kann der Minecraft-Server nicht laufen."
    echo "Bitte von Hand nachholen, z. B.:"
    echo "  sudo apt-get install -y openjdk-${JAVA_MIN}-jre-headless"
    exit 1
  fi

  if [ "$JAVA_MAJOR" -lt "$JAVA_MIN" ]; then
    echo ""
    echo "FEHLER: Installiert ist Java $JAVA_MAJOR, gebraucht wird mindestens"
    echo "Java $JAVA_MIN. Der Server würde damit nicht starten."
    echo ""
    echo "Meist liegt es an einer älteren Raspberry-Pi-OS-Ausgabe. Zwei Wege:"
    echo "  a) Betriebssystem aktualisieren, dann ./install.sh erneut starten"
    echo "  b) Java von Adoptium installieren:"
    echo "     https://adoptium.net/de/installation/linux/"
    exit 1
  fi

  if [ "$JAVA_MAJOR" -lt "$JAVA_EMPFOHLEN" ]; then
    echo ""
    echo "Hinweis: Installiert ist Java $JAVA_MAJOR, empfohlen wäre $JAVA_EMPFOHLEN."
    echo "Der Server läuft — die Option -XX:+UseCompactObjectHeaders wird beim"
    echo "Start automatisch weggelassen, weil es sie erst ab Java 24 gibt."
    echo ""
  else
    echo "Java $JAVA_MAJOR ist installiert — passt."
  fi

  echo "Software ist installiert."
}

# ----------------------------------------------------------------------------
# 3) PaperMC herunterladen
# ----------------------------------------------------------------------------
paper_herunterladen() {
  echo ""
  echo "===== 3/7: PaperMC herunterladen ====="
  SCHRITT="PaperMC herunterladen"

  # Nur laden, wenn noch keine Serverdatei da ist.
  #
  # Früher lief hier bei JEDEM Durchlauf ein Update. Wer install.sh erneut
  # ausführte, um eine Skriptänderung auszurollen, konnte damit ungewollt
  # die Minecraft-Version anheben — und die wandelt beim nächsten Start die
  # Welt endgültig um. Aktualisiert wird deshalb nur noch bewusst:
  #   mcs update
  if [ -f "$MC_SERVER_DIR/paper.jar" ]; then
    echo "paper.jar ist bereits vorhanden — bleibt unangetastet."
    echo "Nach einer neueren Version schauen: mcs update --pruefen"
    return 0
  fi

  # Das Update-Skript erledigt alles: festgelegte Version laden, Prüfsumme.
  # --festgelegt, nicht der Standard: Eine Erstinstallation nimmt genau den
  # Build aus versions.env, damit zwei Installationen desselben Stands
  # gleich sind. "mcs update" ohne Zusatz holt dagegen den neuesten Build.
  bash "$MC_SERVER_DIR/paper-update.sh" --festgelegt

  # Die Plugins gehören genauso zum Server wie die paper.jar — ohne sie fehlt
  # einer frischen Installation zum Beispiel die Karte. plugin-update.sh lädt
  # nur, was in plugins.txt steht, und prüft jede Datei gegen ihre Prüfsumme.
  #
  # Ein Fehlschlag bricht die Installation NICHT ab: der Server läuft auch ohne
  # Plugins, und ein einzelner nicht erreichbarer Download soll nicht die ganze
  # Einrichtung kosten. Nachholen lässt es sich jederzeit mit "mcs plugins".
  if [ -s "$MC_SERVER_DIR/plugins.txt" ] \
     && grep -qvE '^\s*(#|$)' "$MC_SERVER_DIR/plugins.txt"; then
    echo ""
    echo "Plugins aus plugins.txt laden..."
    if ! bash "$MC_SERVER_DIR/plugin-update.sh" --laden; then
      echo "Hinweis: Mindestens ein Plugin konnte nicht geladen werden."
      echo "Die Installation läuft weiter. Später nachholen mit: mcs plugins --laden"
    fi
  fi
}

# ----------------------------------------------------------------------------
# 4) Server konfigurieren
# ----------------------------------------------------------------------------
server_konfigurieren() {
  echo ""
  echo "===== 4/7: Minecraft-Server konfigurieren ====="
  SCHRITT="Server konfigurieren"

  # Minecraft-Nutzungsbedingungen (EULA) akzeptieren — ohne diese Datei
  # startet der Server nicht. Nachzulesen: https://aka.ms/MinecraftEULA
  if [ ! -f "$MC_SERVER_DIR/eula.txt" ]; then
    {
      echo "# Mit eula=true werden die Minecraft-Nutzungsbedingungen akzeptiert"
      echo "# (https://aka.ms/MinecraftEULA)"
      echo "eula=true"
    } > "$MC_SERVER_DIR/eula.txt"
    echo "EULA akzeptiert (eula.txt angelegt)."
  fi

  # Voreingestellte server.properties nur kopieren, wenn noch keine existiert —
  # eine bestehende Konfiguration wird niemals überschrieben.
  # Ob die Datei neu angelegt wurde, entscheidet später darüber, ob die
  # Auswahl des Assistenten angewendet werden darf (siehe auswahl_anwenden).
  if [ ! -f "$MC_SERVER_DIR/server.properties" ]; then
    cp "$REPO_DIR/server/server.properties" "$MC_SERVER_DIR/server.properties"
    SERVER_PROPERTIES_WAR_NEU=true
    echo "server.properties-Vorlage installiert."
  else
    SERVER_PROPERTIES_WAR_NEU=false
    echo "Bestehende server.properties gefunden — bleibt unverändert."
  fi

  # Paper-Konfiguration (Chunk-Pipeline, Spawn-Limits, Aktivierungsradien).
  # Diese vier Dateien tragen den Großteil der am 2026-07-27 gemessenen
  # Leistungsgewinne; ohne sie ergibt eine Neuinstallation einen Server im
  # Auslieferungszustand. Begründung je Wert:
  # docs/optimierung-2026-07-27.md
  #
  # Wie bei server.properties gilt: eine bereits vorhandene Datei wird
  # niemals überschrieben — sonst gingen bei jedem Update die von Hand
  # gepflegten Einstellungen dieser Instanz verloren.
  mkdir -p "$MC_SERVER_DIR/config"
  for REL in config/paper-global.yml config/paper-world-defaults.yml \
             spigot.yml bukkit.yml; do
    if [ ! -f "$MC_SERVER_DIR/$REL" ]; then
      cp "$REPO_DIR/server/$REL" "$MC_SERVER_DIR/$REL"
      echo "Paper-Konfiguration installiert: $REL"
    else
      echo "Bestehende $REL gefunden — bleibt unverändert."
    fi
  done
}

# ----------------------------------------------------------------------------
# RCON einrichten (Fernsteuerung fuer die Weboberflaeche)
# ----------------------------------------------------------------------------
# Wozu? Ueber die screen-Sitzung kann man dem Server nur etwas SAGEN, nicht ihn
# etwas FRAGEN. Die Weboberflaeche braucht aber Antworten: Wer steht auf der
# Whitelist, welches Berechtigungslevel hat jemand, wie hoch sind die TPS.
# Genau dafuer gibt es RCON.
#
# ACHTUNG, am 2026-08-28 nachgemessen: RCON lauscht auf ALLEN Netzwerkkarten
# (der Server meldet "RCON running on 0.0.0.0:25575"). Einen Schluessel
# rcon.ip gibt es nicht. Abgeschottet wird der Port deshalb von der Firewall,
# nicht von der Bindeadresse -- siehe firewall_einrichten weiter unten.
rcon_einrichten() {
  SCHRITT="RCON"
  echo ""
  echo "===== RCON einrichten (Fernsteuerung fuer die Weboberflaeche) ====="

  local DATEI="$MC_SERVER_DIR/server.properties"
  if [ ! -f "$DATEI" ]; then
    echo "Keine server.properties vorhanden — uebersprungen."
    return 0
  fi

  # Laeuft der Server gerade, darf hier NICHT geschrieben werden: Paper haelt
  # die Einstellungen im Speicher und schreibt die ganze Datei daraus neu,
  # sobald ein Befehl eine dort gespeicherte Einstellung aendert -- es genuegt,
  # dass ein Operator im Spiel "/whitelist add" tippt. Eine Aenderung von
  # aussen kann also JEDERZEIT verschwinden, nicht erst beim naechsten Stopp,
  # und lautlos: auf der Platte steht sie ja erst mal richtig drin.
  #
  # Hier stand frueher "schreibt die Datei beim Herunterfahren neu". Das ist
  # am 28.08.2026 gegen Paper 26.2 Build 119 nachgemessen worden und stimmt
  # nicht: Beim Herunterfahren ueberlebte die Handaenderung, beim Start wurde
  # sie verworfen (Korrektur K3, wiederholbar mit
  # tests/messung-paper-verhalten.sh). Die Regel "nur bei gestopptem Server"
  # bleibt richtig -- nur die Begruendung war es nicht.
  if sudo systemctl is-active --quiet "${MCS_SERVICE_NAME:-minecraft.service}"; then
    echo "Der Server laeuft gerade. RCON wird deshalb NICHT eingerichtet:"
    echo "Paper haelt die server.properties im Speicher und schreibt sie von"
    echo "dort neu, sobald ein Befehl eine gespeicherte Einstellung aendert."
    echo ""
    echo "Nachholen, wenn es gerade passt:"
    echo "    mcs stop && ./install.sh --standard"
    return 0
  fi

  # Ein vorhandenes Passwort bleibt. Es neu zu wuerfeln wuerde die
  # Weboberflaeche bei jedem Installationslauf aussperren.
  local PW
  PW=$(sed -n 's/^rcon\.password=//p' "$DATEI" | tail -n1)
  if [ -z "$PW" ]; then
    # Endliche Menge lesen statt "tr | head" -- sonst SIGPIPE, siehe
    # install-admin.sh.
    PW="$(head -c 512 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9')"
    PW="${PW:0:24}"
    if [ "${#PW}" -lt 24 ]; then
      echo "Warnung: Kein Zufallspasswort erzeugbar — RCON bleibt aus."
      return 0
    fi
    echo "Neues RCON-Passwort erzeugt (24 Zeichen)."
  else
    echo "Vorhandenes RCON-Passwort beibehalten."
  fi

  # Rechte ZUERST. setze_zeile uebernimmt die Rechte der Zieldatei auf seine
  # Zwischendatei — stuenden sie noch auf 644, laege das Passwort ab der
  # naechsten Zeile fuer einen Moment weltlesbar auf der Platte. Kurz, aber
  # vermeidbar: einfach vorher zumachen.
  chmod 600 "$DATEI"

  setze_zeile "$DATEI" enable-rcon          true
  setze_zeile "$DATEI" rcon.port            "${MCS_RCON_PORT:-25575}"
  setze_zeile "$DATEI" rcon.password        "$PW"
  # Ohne das schreibt der Server JEDEN Befehl der Weboberflaeche in den Chat
  # aller Operatoren. Ein Klick auf "Backup jetzt" waere dann eine oeffentliche
  # Durchsage.
  setze_zeile "$DATEI" broadcast-rcon-to-ops false

  echo "RCON aktiv auf Port ${MCS_RCON_PORT:-25575} (nur ueber die Firewall abgeschottet)."
}


# ----------------------------------------------------------------------------
# 5) systemd-Dienste einrichten
# ----------------------------------------------------------------------------
dienste_einrichten() {
  echo ""
  echo "===== 5/7: systemd-Dienste einrichten (Autostart) ====="
  SCHRITT="systemd-Dienste einrichten"

  # Zuerst der Hauptschalter. Die Dienste darunter tragen
  # "WantedBy=mcs.target" — ohne das Target ließen sie sich gar nicht
  # aktivieren, systemd fände das Ziel des Verweises nicht.
  dienst_installieren "$REPO_DIR/server/mcs.target"
  dienst_installieren "$REPO_DIR/server/minecraft.service"
  dienst_installieren "$REPO_DIR/tools/mcs-playerlog.service"
  # Der DNS-Timer wird IMMER eingerichtet, auch ohne eingestellten Anbieter.
  # dns-update.sh endet dann sofort und schweigt. Der Grund steht in
  # server/mcs-dns.service; kurz: Sonst müsste die Weboberfläche
  # "systemctl enable" dürfen, und das wäre eine weite sudo-Regel für
  # einen Komfortgewinn.
  dienst_installieren "$REPO_DIR/server/mcs-dns.service"
  dienst_installieren "$REPO_DIR/server/mcs-dns.timer"

  sudo systemctl daemon-reload

  # Reihenfolge: erst das Target aktivieren (damit es beim Booten hochkommt),
  # dann die Dienste (die legen dadurch ihre Verweise in mcs.target.wants an).
  sudo systemctl enable mcs.target
  sudo systemctl enable minecraft.service mcs-playerlog.service

  # Wie beim Backup-Timer: Ist PiCraft gerade abgeschaltet ("mcs aus"), wird
  # aktiviert, aber nicht gestartet — sonst nähme dieser Lauf dem Nutzer
  # seine Entscheidung ab.
  if [ "$(systemctl is-enabled mcs.target 2>/dev/null)" = "disabled" ]; then
    sudo systemctl enable mcs-dns.timer
  else
    sudo systemctl enable --now mcs-dns.timer
  fi

  echo "Dienste eingerichtet — der Server startet ab jetzt bei jedem Booten automatisch."
  echo "Alles zusammen abschalten (überlebt den Neustart):  mcs aus"
}

# ----------------------------------------------------------------------------
# 6) Tägliches Backup einplanen
# ----------------------------------------------------------------------------
# Sorgt dafür, dass die Protokolldateien nicht unbegrenzt wachsen.
#
# Betroffen sind zwei Dateien: das Backup-Logbuch und das
# Aktionsprotokoll der Weboberfläche. Auf einem Server, der jahrelang
# läuft, summiert sich das.
#
# Bis zum 23.09.2026 standen hier noch duckdns.log und cron.log. Beide
# schreibt seit dem Umstieg auf systemd-Timer niemand mehr (duckdns.sh ist
# in dns-update.sh aufgegangen, das Backup läuft nicht mehr über Cron) —
# "missingok" hat die toten Einträge nur verdeckt. dns.log braucht keine
# Regel: dns-update.sh kürzt es selbst auf 200 Zeilen.
#
# (Das GC-Protokoll der JVM braucht keine Regel: die begrenzt sich mit
#  filecount/filesize selbst, siehe start-minecraft.sh.)
logrotate_einrichten() {
  if ! command -v logrotate >/dev/null 2>&1; then
    echo "Hinweis: logrotate ist nicht installiert — Protokolle wachsen unbegrenzt."
    echo "         Nachholen mit: sudo apt-get install -y logrotate"
    return 0
  fi

  # "copytruncate" kopiert die Datei und leert das Original, statt sie
  # umzubenennen. Das ist hier nötig, weil Programme die Dateien offen
  # halten und nach einem Umbenennen ins Leere weiterschreiben würden.
  #
  # Warum player_activity.log hier NICHT steht (Befund 21.09.2026):
  # Es ist ein Hauptbuch, kein Protokoll. Die Weboberfläche liest es als
  # GANZES, um "zuletzt gesehen" zu beantworten — eine Rotation schneidet
  # ihr genau diese Antwort weg. Auf der Beispielinstallation stand die
  # Live-Datei nach der Rotation auf 0 Byte, und die Spielerseite meldete
  # für Spieler mit dreistelligen Stundenzahlen "nicht aufgezeichnet".
  # Still, zwei Wochen lang: "keine Daten" sieht dort genauso aus wie
  # "war noch nie da".
  #
  # Die Größe trägt das Gegenargument nicht: gemessen 139 KB in einem
  # halben Jahr. Merksatz: Bevor eine Datei in eine Rotationsregel kommt,
  # fragen, ob irgendwer ihre Vergangenheit liest.
  sudo tee /etc/logrotate.d/picraft >/dev/null <<EOF
# Von PiCraft angelegt (install.sh). Änderungen gehen beim nächsten
# Installationslauf verloren.
# player_activity.log gehört hier NICHT hinein (Hauptbuch).
# Die Weboberfläche liest es als Ganzes; eine Rotation schneidet ihr
# genau die Antwort auf "zuletzt gesehen" weg (Befund 21.09.2026).
${MC_BACKUP_DIR}/backup.log
${MCS_ADMIN_DIR:-$MC_DIR/admin}/actions.log
{
    weekly
    rotate 8
    compress
    delaycompress
    missingok
    notifempty
    copytruncate
    su ${MCS_USER} ${MCS_USER}
}
EOF
  sudo chmod 644 /etc/logrotate.d/picraft
  echo "Protokoll-Rotation eingerichtet (wöchentlich, 8 Wochen Aufbewahrung)."
}

backup_einplanen() {
  local STUNDE
  STUNDE=$(printf '%02d' "${WAHL_BACKUP_STUNDE:-4}")
  echo ""
  echo "===== 6/7: Tägliches Backup einplanen (${STUNDE}:00 Uhr) ====="
  SCHRITT="Backup einplanen"

  # Seit 2026-08-28 ein systemd-Timer statt eines Cronjobs. Die Begründung
  # steht ausführlich in backup/mcs-backup.timer; kurz: Nur ein Timer lässt
  # sich gemeinsam mit allen anderen Diensten abschalten ("mcs aus"), und er
  # holt einen verpassten Lauf nach. Ein Cronjob kann beides nicht.

  # Eine bereits eingestellte Uhrzeit gewinnt — wer sie geändert hat, soll sie
  # nicht bei jedem Installationslauf zurückgesetzt bekommen. Genauso hat es
  # der alte Cronjob schon gehalten.
  #
  # Seit v1.1 steht sie in einem DROP-IN und nicht mehr in der Einheit (E20):
  # Die Einheit gehört der Vorlage, und ./deploy.sh ersetzt sie — die
  # eingestellte Zeit stünde danach stillschweigend wieder auf 04:00. Gesucht
  # wird deshalb zuerst im Drop-in und nur ersatzweise noch in der alten
  # Einheit, damit eine Installation von vor v1.1 ihre Zeit behält.
  local ZEIT_DROPIN_DIR="$SERVICE_DIR/mcs-backup.timer.d"
  local ZEIT_DROPIN="$ZEIT_DROPIN_DIR/zeit.conf"

  # Aus der ALTEN Einheit (vor v1.1) die dort eingetragene Stunde holen,
  # damit sie beim Umstieg nicht verlorengeht.
  local BESTEHENDE=""
  if [ -f "$SERVICE_DIR/mcs-backup.timer" ]; then
    BESTEHENDE=$(sed -n 's#^OnCalendar=\*-\*-\* \([0-9][0-9]\):.*#\1#p' \
                   "$SERVICE_DIR/mcs-backup.timer" | tail -n1) || BESTEHENDE=""
  fi

  dienst_installieren "$REPO_DIR/backup/mcs-backup.service"
  dienst_installieren "$REPO_DIR/backup/mcs-backup.timer"
  # Die Kopien auf den USB-Stick und in die Cloud (seit v1.4). Sie werden
  # IMMER eingerichtet, wie der DNS-Timer: Steckt kein Stick und ist keine
  # Cloud eingetragen, endet jeder Lauf sofort und still. Wer später einen
  # Stick einsteckt oder "mcs cloud einrichten" aufruft, muss dann nichts
  # mehr aktivieren.
  dienst_installieren "$REPO_DIR/backup/mcs-usb-kopie.service"
  dienst_installieren "$REPO_DIR/backup/mcs-usb-kopie.path"
  dienst_installieren "$REPO_DIR/backup/mcs-cloud-kopie.service"
  dienst_installieren "$REPO_DIR/backup/mcs-cloud-kopie.path"

  # Ausserhalb der Verzweigung deklariert: Die Abschlussmeldung unten braucht
  # den Wert in BEIDEN Faellen, und unter "set -u" ist eine nur im else-Zweig
  # gesetzte Variable ein Abbruch. Genau das ist am 01.09.2026 passiert — der
  # ERSTE Installationslauf ging durch (else-Zweig), erst der zweite fiel
  # darueber. Ein Fehler, den nur der Wiederholungslauf zeigt.
  local ZEITPLAN
  if [ -f "$ZEIT_DROPIN" ]; then
    # Gibt es das Drop-in schon, wird es NICHT ANGEFASST — auch nicht, um die
    # Stunde des Assistenten einzutragen. Es gehört der Installation.
    #
    # Und der Grund ist nicht bloß Ordnung: Die Weboberfläche lässt jede
    # Kalenderangabe zu, die systemd versteht — "Mon..Fri 05:00" zum
    # Beispiel. Ein Versuch, daraus eine Stunde herauszulesen, ginge leer
    # aus, und ein zweiter Installationslauf hätte den Zeitplan
    # stillschweigend auf 04:00 zurückgestellt. Genau diese Sorte
    # Rückstellung soll das Drop-in ja gerade verhindern.
    ZEITPLAN=$(sed -n 's#^OnCalendar=\(..*\)#\1#p' "$ZEIT_DROPIN" | tail -n1)
    echo "Eingestellt bleibt: $ZEITPLAN"
    echo "  (aus $ZEIT_DROPIN — gehört dieser Installation und wird nicht überschrieben)"
    echo "  Ändern in der Weboberfläche unter \"Backups\"."
  else
    local ZIEL="$STUNDE"
    if [ -n "$BESTEHENDE" ] && [ "$BESTEHENDE" != "$STUNDE" ]; then
      ZIEL="$BESTEHENDE"
      echo "Hinweis: Gewählt war ${STUNDE}:00 Uhr, übernommen wird die bereits"
      echo "         eingetragene Zeit ${BESTEHENDE}:00 Uhr."
    fi

    # Das Drop-in, nicht die Einheit. "OnCalendar=" leer voran, weil systemd
    # den Schlüssel als LISTE führt: Ohne diese Zeile käme die neue Zeit zur
    # Vorgabe der Einheit hinzu, statt sie zu ersetzen — das Backup liefe dann
    # zweimal täglich, einmal davon zu einer Zeit, die niemand eingestellt hat.
    sudo mkdir -p "$ZEIT_DROPIN_DIR"
    {
      echo "# Von install.sh geschrieben. Diese Datei gehört der INSTALLATION,"
      echo "# die Einheit daneben der Vorlage — ./deploy.sh fasst sie nicht an."
      echo "# Ändern in der Weboberfläche unter \"Backups\"."
      echo "[Timer]"
      echo "OnCalendar="
      echo "OnCalendar=*-*-* ${ZIEL}:00:00"
    } | sudo tee "$ZEIT_DROPIN" >/dev/null
    ZEITPLAN="*-*-* ${ZIEL}:00:00"
  fi

  sudo systemctl daemon-reload

  # "enable" allein legt nur den Verweis an -- der Timer laeuft davon noch
  # nicht. Genau das passierte am 2026-08-29 auf dem Pi: Der Cronjob wurde
  # unten entfernt, der Timer war "enabled", aber "inactive (dead)" mit
  # "Trigger: n/a". Zwischen Installationslauf und naechstem Neustart lief
  # damit UEBERHAUPT KEIN Backup -- und weil beide Zustaende fuer sich
  # plausibel aussehen ("enabled" hier, "kein Cronjob" dort), faellt so etwas
  # erst auf, wenn man das Backup braucht. "Persistent=true" hilft dabei
  # nicht: Es holt verpasste Laeufe nach, aber auch das erst, wenn der Timer
  # laeuft.
  #
  # Ist PiCraft gerade abgeschaltet ("mcs aus"), wird NICHT gestartet -- sonst
  # naehme dieser Lauf dem Nutzer seine Entscheidung ab. "mcs an" holt es nach.
  if [ "$(systemctl is-enabled mcs.target 2>/dev/null)" = "disabled" ]; then
    sudo systemctl enable mcs-backup.timer
    echo "Backup-Timer eingerichtet, aber nicht gestartet: PiCraft ist"
    echo "abgeschaltet (mcs aus). Mit 'mcs an' läuft er wieder mit."
  else
    sudo systemctl enable --now mcs-backup.timer
  fi
  # Die beiden Wächter hängen an multi-user.target, nicht an mcs.target: Sie
  # warten nur auf ein neues Backup, und das entsteht ohne Server nicht.
  sudo systemctl enable --now mcs-usb-kopie.path mcs-cloud-kopie.path

  # Den alten Cronjob entfernen. Ohne das liefe das Backup zweimal — einmal
  # über Cron, einmal über den Timer. Zwei gleichzeitige tar-Läufe auf
  # denselben Weltdateien, und die Rotation räumte doppelt so schnell ab.
  #
  # Das "|| true" ist nötig: Bleibt nach dem Filtern keine Zeile übrig, liefert
  # grep den Rückgabewert 1 — unter "set -Eeuo pipefail" risse das die
  # Installation ab, ausgerechnet beim Aufräumen.
  local AKTUELLE_CRONTAB
  AKTUELLE_CRONTAB=$(crontab -l 2>/dev/null || true)
  if printf '%s\n' "$AKTUELLE_CRONTAB" | grep -Fq "minecraft-backup.sh"; then
    printf '%s\n' "$AKTUELLE_CRONTAB" \
      | { grep -Fv "minecraft-backup.sh" || true; } \
      | crontab -
    echo "Alter Backup-Cronjob entfernt — das übernimmt jetzt mcs-backup.timer."
  fi

  echo "Backup-Timer eingerichtet (${ZEITPLAN})."
  echo "Nächster Termin sehen:  systemctl list-timers mcs-backup.timer"

  logrotate_einrichten
}

# ----------------------------------------------------------------------------
# 7) Server starten
# ----------------------------------------------------------------------------
server_starten() {
  echo ""
  echo "===== 7/7: Minecraft-Server starten ====="
  SCHRITT="Server starten"

  sudo systemctl restart mcs-playerlog.service

  if sudo systemctl is-active --quiet minecraft.service; then
    # Re-Installation auf laufendem Server: nicht einfach neu starten,
    # das würde die Spieler rauswerfen. Nur Hinweis geben.
    echo "Der Server läuft bereits und bleibt ungestört."
    echo "Damit aktualisierte Skripte/Einstellungen greifen, bei Gelegenheit: mcs restart"
  else
    sudo systemctl start minecraft.service
    echo "Startbefehl abgesetzt — der erste Start dauert ein paar Minuten,"
    echo "weil der Server die Welt neu erzeugt. Live zuschauen mit: mcs log"
  fi
}

# ----------------------------------------------------------------------------
# Die Antworten des Assistenten in die Konfiguration schreiben
# ----------------------------------------------------------------------------
# Läuft NACH server_konfigurieren, weil dort erst die Vorlage kopiert wird.
#
# Eine bestehende server.properties wird auch hier nicht angetastet: Wer neu
# installiert, bekommt seine Auswahl; wer eine laufende Instanz behält,
# behält seine Einstellungen. Sonst wäre ein erneuter Lauf von install.sh
# nicht mehr gefahrlos — und genau das ist er bisher.
auswahl_anwenden() {
  SCHRITT="Auswahl übernehmen"
  local DATEI="$MC_SERVER_DIR/server.properties"

  if [ "${SERVER_PROPERTIES_WAR_NEU:-false}" != true ]; then
    echo "Bestehende server.properties — die Auswahl wird nicht angewendet."
    return 0
  fi


  setze_zeile "$DATEI" level-name          "$WAHL_WELTNAME"
  setze_zeile "$DATEI" gamemode            "$WAHL_MODUS"
  setze_zeile "$DATEI" difficulty          "$WAHL_SCHWIERIGKEIT"
  setze_zeile "$DATEI" view-distance       "$WAHL_SICHTWEITE"
  setze_zeile "$DATEI" simulation-distance "$WAHL_SIMULATION"
  setze_zeile "$DATEI" max-players         "$WAHL_MAXSPIELER"
  setze_zeile "$DATEI" server-port         "$WAHL_PORT"
  [ "$WAHL_WHITELIST" = true ] && { setze_zeile "$DATEI" white-list true; setze_zeile "$DATEI" enforce-whitelist true; } \
                               || { setze_zeile "$DATEI" white-list false; setze_zeile "$DATEI" enforce-whitelist false; }
  # Hier stand bis zum 02.09.2026 ein "spawn-monsters" je nach Spielmodus.
  # Paper 26.2 kennt den Schlüssel nicht mehr (am 02.09. an einer von Paper
  # selbst geschriebenen server.properties nachgemessen: spawn-monsters,
  # spawn-animals und spawn-npcs fehlen alle drei). Die Zeile schrieb also
  # einen Wert, den Paper beim ersten Start wieder entfernt hat. Ob Monster
  # erscheinen, entscheidet die Schwierigkeit — die steht eine Zeile weiter
  # oben und wird vom Assistenten ohnehin abgefragt.

  echo "server.properties auf die getroffene Auswahl gesetzt."

  # Heap und zweiter Backup-Ort gehören in mcs.conf — von dort lesen alle
  # Skripte und der systemd-Dienst.
  local CONF_ZIEL="$MC_DIR/mcs.conf"
  if [ -f "$CONF_ZIEL" ]; then
    # Dieselbe metazeichensichere Schleife, nur für die andere Datei. Ein
    # Backup-Pfad wie /mnt/platte&2 hätte mit sed dasselbe Problem gemacht.
    setze_zeile "$CONF_ZIEL" MCS_HEAP "${WAHL_HEAP}G"
    # Ueber mcs_conf_wert, weil der Pfad vom Benutzer kommt und Leerzeichen
    # enthalten darf (siehe dort).
    if [ -n "$WAHL_EXTERN" ]; then
      setze_zeile "$CONF_ZIEL" MCS_EXTERN_DIR "$(mcs_conf_wert "$WAHL_EXTERN")"
    fi
    echo "mcs.conf gesetzt (Heap ${WAHL_HEAP}G${WAHL_EXTERN:+, Zweitziel $WAHL_EXTERN})."
  fi
}


# ----------------------------------------------------------------------------
# Plugins — vor dem Serverstart, weil Paper sie nur beim Start lädt
# ----------------------------------------------------------------------------
plugins_laden() {
  [ "${WAHL_PLUGINS:-false}" = true ] || return 0
  [ -x "$MC_SERVER_DIR/plugin-update.sh" ] || return 0
  SCHRITT="Plugins"
  echo ""
  echo "===== Plugins laden ====="
  # Schlägt der Download fehl (kein Netz, Modrinth nicht erreichbar), soll das
  # die Installation nicht abbrechen: Der Server läuft auch ohne Plugins, und
  # nachholen geht jederzeit mit "mcs plugins --laden".
  if ! "$MC_SERVER_DIR/plugin-update.sh" --laden; then
    echo "Warnung: Nicht alle Plugins konnten geladen werden."
    echo "Später nachholen mit:  mcs plugins --laden, danach mcs restart"
    PLUGINS_UNVOLLSTAENDIG=true
  fi
}

# ----------------------------------------------------------------------------
# Weboberfläche — vor der Firewall, damit deren Port offen bleiben kann
# ----------------------------------------------------------------------------
admin_oberflaeche_einrichten() {
  [ "${WAHL_ADMIN:-false}" = true ] || return 0
  [ -x "$REPO_DIR/install-admin.sh" ] || return 0
  SCHRITT="Weboberfläche"
  echo ""
  echo "===== Weboberfläche einrichten ====="
  # Den Ort der erzeugten mcs.conf weiterreichen: install-admin.sh sucht sonst
  # unter ~/mcs und läge daneben, sobald jemand woanders installiert hat.
  # Ein im Assistenten gewaehltes Passwort wird durchgereicht. Ist keines
  # gewaehlt, bleibt die Variable leer und install-admin.sh erzeugt wie
  # bisher ein zufaelliges. Ueber die Umgebung und nicht als Parameter:
  # Aufrufparameter stehen in der Prozessliste, die jeder Benutzer des
  # Systems lesen kann.
  if ! MCS_CONF="$MC_DIR/mcs.conf" \
       MCS_ADMIN_PASSWORT_WUNSCH="${WAHL_ADMIN_PASSWORT:-}" \
       "$REPO_DIR/install-admin.sh"; then
    echo "Warnung: Die Weboberfläche ließ sich nicht einrichten."
    echo "Später nachholen mit:  ./install-admin.sh"
    # Zurücksetzen, damit der Abschlussbildschirm nicht auf ein Passwort
    # verweist, das nie angezeigt wurde, und die Firewall keinen Port für
    # einen Dienst öffnet, den es nicht gibt.
    WAHL_ADMIN=false
  fi
}

# ----------------------------------------------------------------------------
# Automatische Sicherheitsupdates
# ----------------------------------------------------------------------------
# Das Lastenheft (5.3) nennt es "den Einzeiler mit der größten Wirkung pro
# Zeile im ganzen Projekt". Der Server ist aus dem Internet erreichbar; ohne
# Sicherheitsupdates ist er das auch noch in zwei Jahren, mit allen Lücken,
# die bis dahin bekannt geworden sind.
#
# ZWEI DINGE, DIE HIER BEWUSST NICHT PASSIEREN:
#
# 1. Kein automatischer Neustart. unattended-upgrades kann das
#    (Automatic-Reboot), und es ist verlockend — ein Kernel-Update wirkt
#    schliesslich erst danach. Aber ein Minecraft-Server, der sich um
#    sechs Uhr früh selbst neu startet, wirft Spieler heraus und kann
#    mitten in einem Weltspeichervorgang stehen. Stattdessen legt das
#    System /var/run/reboot-required an, und die Startseite der
#    Weboberfläche meldet es. Entschieden wird von Hand.
#
# 2. Kein dpkg-reconfigure. Es täte dasselbe, aber die Einstellung stünde
#    danach in einer Datei, die niemand aufmacht. Hier wird sie
#    ausgeschrieben und kommentiert — wer wissen will, was eingestellt ist,
#    liest eine Datei mit fünf Zeilen.
#
# Schlägt etwas fehl, bricht die Installation NICHT ab: Der Server läuft
# auch ohne, und Nachholen ist ein Befehl.
sicherheitsupdates_einrichten() {
  [ "${WAHL_UPDATES:-false}" = true ] || return 0
  SCHRITT="Sicherheitsupdates"
  echo ""
  echo "===== Automatische Sicherheitsupdates ====="

  local KONFIG="/etc/apt/apt.conf.d/20auto-upgrades"

  if ! dpkg -s unattended-upgrades >/dev/null 2>&1; then
    if ! sudo apt-get install -y -qq unattended-upgrades >/dev/null 2>&1; then
      echo "Warnung: unattended-upgrades liess sich nicht installieren."
      echo "Später nachholen mit:  sudo apt-get install -y unattended-upgrades"
      return 0
    fi
    echo "unattended-upgrades installiert."
  else
    echo "unattended-upgrades ist bereits installiert."
  fi

  # Eine bestehende Einstellung wird NICHT überschrieben. Wer sie von Hand
  # gesetzt hat, hat sich etwas dabei gedacht — und diese Datei gehört dem
  # System, nicht PiCraft.
  if [ -f "$KONFIG" ] \
     && grep -q '^APT::Periodic::Unattended-Upgrade *"1"' "$KONFIG" 2>/dev/null; then
    echo "Bereits eingerichtet ($KONFIG) — bleibt unverändert."
  else
    sudo tee "$KONFIG" >/dev/null <<'ENDE'
// 20auto-upgrades — von PiCraft eingerichtet.
//
// Zeile 1: Jeden Tag die Paketlisten aktualisieren.
// Zeile 2: Jeden Tag die Sicherheitsaktualisierungen einspielen.
//
// WAS HIER BEWUSST FEHLT: Unattended-Upgrade::Automatic-Reboot.
// Ohne diesen Eintrag startet der Pi sich NIE von selbst neu. Ist nach
// einem Kernel-Update ein Neustart nötig, legt das System die Datei
// /var/run/reboot-required an; die Weboberfläche meldet das auf der
// Startseite. Neu gestartet wird dann von Hand, wenn niemand spielt:
//
//     mcs stop && sudo reboot
//
// Welche Quellen eingespielt werden (nur Sicherheit, nicht alles), steht
// in /etc/apt/apt.conf.d/50unattended-upgrades und bleibt bei den
// Debian-Vorgaben.
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
ENDE
    sudo chmod 644 "$KONFIG"
    echo "Eingerichtet: tägliche Sicherheitsupdates, ohne automatischen Neustart."
  fi
  echo "Nachsehen, was gelaufen ist:  sudo cat /var/log/unattended-upgrades/unattended-upgrades.log"
}

# ----------------------------------------------------------------------------
# Firewall — nur wenn ausdrücklich gewünscht
# ----------------------------------------------------------------------------
firewall_einrichten() {
  if [ "${WAHL_FIREWALL:-false}" != true ]; then
    # Ohne Firewall ist der RCON-Port das einzige, was zwischen dem lokalen
    # Netz und einer vollstaendigen Fernsteuerung des Servers steht -- und
    # RCON laesst sich nicht auf die lokale Adresse beschraenken (gemessen
    # 2026-08-28: "RCON running on 0.0.0.0"). Das muss gesagt werden, sonst
    # verlaesst sich jemand auf eine Abschottung, die es nicht gibt.
    if [ -f "$MC_SERVER_DIR/server.properties" ] \
       && grep -q '^enable-rcon=true' "$MC_SERVER_DIR/server.properties" 2>/dev/null; then
      local R_PORT
      R_PORT=$(sed -n 's/^rcon\.port=//p' "$MC_SERVER_DIR/server.properties" | tail -n1)
      echo ""
      echo "${F_GELB:-}Hinweis zur Sicherheit:${F_AUS:-} Die Firewall bleibt aus, RCON ist aber an."
      echo "RCON lauscht auf allen Netzwerkkarten (Port ${R_PORT:-25575}) — es laesst sich"
      echo "nicht auf die lokale Adresse beschraenken. Wer im Heimnetz das Passwort"
      echo "aus der server.properties liest, kann den Server fernsteuern."
      echo ""
      echo "Empfohlen — den Port sperren:"
      echo "    sudo ufw deny ${R_PORT:-25575}/tcp"
      echo "Oder RCON abschalten (dann fehlen der Weboberflaeche Spielerliste"
      echo "und TPS-Anzeige) — bei GESTOPPTEM Server in der server.properties"
      echo "enable-rcon auf false setzen, danach: mcs start"
    fi
    return 0
  fi
  SCHRITT="Firewall"
  echo ""
  echo "===== Firewall einrichten ====="

  # Welcher Port wird wirklich gebraucht? Bei einer Neuinstallation ist das
  # die Antwort aus dem Assistenten. Bei einer bestehenden Installation
  # wurde diese Antwort aber gar nicht angewendet (auswahl_anwenden steigt
  # dann aus) — dort zählt, worauf der Server TATSÄCHLICH lauscht. Sonst
  # öffnet die Firewall den falschen Port und schließt den richtigen.
  # Jede Ermittlung hier ist mit "|| true" abgesichert: Unter
  # "set -Eeuo pipefail" reisst sonst ein fehlender sshd oder eine fehlende
  # server.properties die ganze Installation ab — die Firewall ist aber
  # Zubehoer und darf das nie. (Genau so ist der Container-Abnahmetest
  # schon einmal gescheitert.)
  local PORT="${WAHL_PORT:-25565}"
  local ECHTER_PORT=""
  if [ -f "$MC_SERVER_DIR/server.properties" ]; then
    ECHTER_PORT=$(sed -n 's/^server-port=//p' "$MC_SERVER_DIR/server.properties" 2>/dev/null | tail -n1) || true
  fi
  if [ -n "$ECHTER_PORT" ] && [ "$ECHTER_PORT" != "$PORT" ]; then
    echo "Hinweis: Der Server lauscht auf Port $ECHTER_PORT (nicht $PORT)."
    echo "Die Firewall-Regel richtet sich danach."
    PORT="$ECHTER_PORT"
  fi

  # Den SSH-Port ebenfalls auslesen statt 22 anzunehmen. Läuft sshd
  # woanders, würde "default deny incoming" die laufende Sitzung kappen —
  # genau der Selbstausschluss, den diese Funktion verhindern soll.
  local SSH_PORT=""
  if command -v sshd >/dev/null 2>&1; then
    SSH_PORT=$(sudo sshd -T 2>/dev/null | awk '/^port /{print $2; exit}') || SSH_PORT=""
  fi
  if [ -z "$SSH_PORT" ] && [ -f /etc/ssh/sshd_config ]; then
    SSH_PORT=$(awk '/^[Pp]ort[[:space:]]+[0-9]+/{print $2; exit}' /etc/ssh/sshd_config 2>/dev/null) || SSH_PORT=""
  fi
  if [ -z "$SSH_PORT" ]; then
    echo ""
    echo "Der SSH-Port ließ sich nicht ermitteln. Die Firewall wird NICHT"
    echo "aktiviert — bei einem falsch geratenen Port würde diese Sitzung"
    echo "sofort abreißen und der Pi wäre nur noch am Gerät erreichbar."
    echo "Von Hand einrichten (mit dem richtigen SSH-Port):"
    echo "    sudo ufw allow <ssh-port>/tcp && sudo ufw allow ${PORT}/tcp"
    echo "    sudo ufw default deny incoming && sudo ufw enable"
    return 0
  fi

  # Die Firewall ist Zubehör, kein Teil des Servers. Schlägt sie fehl, DARF
  # das die Installation nicht abbrechen — der Server läuft auch ohne, und
  # nachholen kann man es jederzeit.
  #
  # Dass das wichtig ist, hat der Container-Abnahmetest gezeigt: Dort kann
  # ufw die Kernel-Regeln gar nicht setzen (dem Container fehlen die
  # Netzwerk-Rechte). Ohne diese Absicherung riss der fehlgeschlagene
  # ufw-Aufruf über `set -Eeuo pipefail` die komplette Installation mit.
  fehlschlag() {
    echo ""
    echo "Hinweis: Die Firewall konnte nicht eingerichtet werden ($1)."
    echo "Der Server läuft trotzdem. Nachholen mit:"
    echo "    sudo ufw allow ${SSH_PORT}/tcp"
    echo "    sudo ufw allow ${PORT}/tcp"
    echo "    sudo ufw default deny incoming && sudo ufw enable"
    return 0
  }

  if ! command -v ufw >/dev/null 2>&1; then
    sudo apt-get install -y ufw >/dev/null 2>&1 || { fehlschlag "ufw nicht installierbar"; return 0; }
  fi

  # SSH ZUERST erlauben. Andernfalls sperrt "default deny" eine laufende
  # SSH-Sitzung aus, und der Pi wäre nur noch mit Tastatur und Monitor
  # erreichbar — der klassische Weg, sich selbst auszuschließen.
  sudo ufw allow "${SSH_PORT}/tcp"  >/dev/null 2>&1 || { fehlschlag "Regel für SSH"; return 0; }
  sudo ufw allow "${PORT}/tcp"      >/dev/null 2>&1 || { fehlschlag "Regel für Minecraft"; return 0; }

  # Auf welchem Port lauscht die Weboberfläche wirklich? install-admin.sh
  # weicht auf 8081 aus, wenn 8080 schon belegt ist (typischerweise von
  # Pl3xMap). Stünde hier fest 8080, öffnete die Firewall den falschen Port
  # und ließe den richtigen zu — dieselbe Klasse Fehler wie beim Minecraft-Port
  # weiter oben.
  local ADMIN_PORT=8080
  if [ -f "$MC_DIR/admin/.env" ]; then
    local AUS_ENV
    AUS_ENV=$(sed -n 's/^MCS_ADMIN_PORT=//p' "$MC_DIR/admin/.env" 2>/dev/null | tail -n1) || AUS_ENV=""
    [ -n "$AUS_ENV" ] && ADMIN_PORT="$AUS_ENV"
  fi

  # Die Weboberfläche ist bewusst NUR im lokalen Netz
  # erlaubt — wer ihr Passwort kennt, kann über die Konsole praktisch alles
  # auf diesem Gerät tun (siehe README, Abschnitt Sicherheit).
  if [ "${WAHL_ADMIN:-false}" = true ]; then
    local LAN=""
    LAN=$(ip -4 route show default 2>/dev/null | awk '{print $3}' | head -n1) || LAN=""
    if [ -n "$LAN" ]; then
      LAN="${LAN%.*}.0/24"
      sudo ufw allow from "$LAN" to any port "$ADMIN_PORT" proto tcp >/dev/null 2>&1 \
        && echo "Weboberfläche ($ADMIN_PORT) für das lokale Netz $LAN freigegeben."
    fi
  fi

  # RCON ausdruecklich sperren. Die Grundregel "alles zu, ausser was erlaubt
  # ist" wuerde das ohnehin erledigen -- aber nur solange sie gilt. Wer sie
  # spaeter lockert, soll nicht versehentlich eine Fernsteuerung mit
  # oeffnen. Eine eigene Regel ueberlebt das und macht die Absicht sichtbar.
  if [ -f "$MC_SERVER_DIR/server.properties" ]; then
    local RCON_PORT=""
    RCON_PORT=$(sed -n 's/^rcon\.port=//p' "$MC_SERVER_DIR/server.properties" 2>/dev/null | tail -n1) || RCON_PORT=""
    if [ -n "$RCON_PORT" ] && grep -q '^enable-rcon=true' "$MC_SERVER_DIR/server.properties" 2>/dev/null; then
      sudo ufw deny "${RCON_PORT}/tcp" >/dev/null 2>&1 \
        && echo "RCON-Port ($RCON_PORT) gesperrt — erreichbar nur noch vom Pi selbst."
    fi
  fi

  # Ist die Firewall schon aktiv, wird sie nicht neu aufgesetzt: Bestehende
  # Regeln bleiben erhalten, es kommen nur die beiden oben hinzu. Der
  # Warnhinweis darunter wäre dann falsch — und Angst vor einem Schritt zu
  # machen, der gar nichts kaputt macht, ist genauso schlecht wie zu
  # schweigen, wenn es gefährlich wird.
  #
  # Genau "Status: active", mit LC_ALL=C: Ein blosses grep auf "active"
  # traf bis zum 23.09.2026 auch "Status: inactive" — die Warnung darunter
  # entfiel also genau dann, wenn die Grundregel gleich alles sperrt.
  if sudo LC_ALL=C ufw status 2>/dev/null | head -n1 | grep -qx 'Status: active'; then
    echo ""
    echo "Die Firewall ist bereits aktiv. Bestehende Regeln bleiben erhalten —"
    echo "es kommen nur die Regeln für SSH ($SSH_PORT) und Minecraft ($PORT) dazu."
    echo ""
  else
    echo ""
    echo "ACHTUNG: Gleich wird alles gesperrt, was nicht ausdrücklich erlaubt ist."
    echo "Laufen auf diesem Gerät weitere Dienste (Dateifreigaben, Smart Home,"
    echo "ein Dashboard), sind sie danach von außen NICHT mehr erreichbar."
    echo "Ihre Ports müssen von Hand ergänzt werden:  sudo ufw allow <port>/tcp"
    echo ""
  fi

  sudo ufw default deny incoming    >/dev/null 2>&1 || { fehlschlag "Grundregel eingehend"; return 0; }
  sudo ufw default allow outgoing   >/dev/null 2>&1 || { fehlschlag "Grundregel ausgehend"; return 0; }
  sudo ufw --force enable           >/dev/null 2>&1 || { fehlschlag "Aktivieren"; return 0; }

  echo "Firewall aktiv: SSH ($SSH_PORT) und Minecraft ($PORT) offen, sonst nichts."
}


# ----------------------------------------------------------------------------
# Ablauf
# ----------------------------------------------------------------------------
assistent_kopf

# ----------------------------------------------------------------------------
# Wohin? (Entscheidung 6, Lastenheft 5.1)
# ----------------------------------------------------------------------------
# Diese eine Frage steht VOR der Vorprüfung, und zwar aus zwei Gründen:
#
#   1. Die Vorprüfung misst den freien Platz auf dem Zielverzeichnis. Fragte
#      man danach, prüfte sie den falschen Datenträger — und genau das ist
#      der Fall, der die Frage überhaupt wertvoll macht: Wer die Warnung vor
#      der SD-Karte gelesen hat, will jetzt auf seine SSD ausweichen.
#   2. Der Assistent verändert nichts. Diese Frage auch nicht — sie legt nur
#      fest, worüber die folgenden Fragen reden.
#
# Gefragt wird NUR, wenn es hier noch keine Installation gibt. Läge schon
# eine, wäre die Frage eine Falle: Ihre Pfade stehen in ihrer mcs.conf, und
# ein anderer Ort machte aus einer Aktualisierung eine zweite Installation
# neben der ersten.
installationsort_erfragen() {
  [ -f "$MCS_CONF" ] && return 0
  [ "$ASSISTENT_STANDARD" = true ] && return 0

  assistent_abschnitt "Installationsort"
  assistent_text \
    "Hierhin kommen Server, Welten, Backups und Einstellungen." \
    "" \
    "Der Vorschlag liegt im Heimatverzeichnis. Wer eine SSD an anderer" \
    "Stelle eingehängt hat, trägt sie hier ein — das ist die wirksamste" \
    "Einzelentscheidung dieses Assistenten (siehe die Auskunft oben)."
  # Nachfragen in einer SCHLEIFE, nicht durch Selbstaufruf: Genauso macht es
  # die Frage nach dem Weltnamen weiter unten, und eine Funktion, die sich
  # bei jeder Fehleingabe selbst aufruft, ist beim Lesen ein Stolperstein
  # ohne Gegenwert.
  local WAHL_ORT
  while true; do
    frage_text WAHL_ORT "$MC_DIR" "Installationsort"
    [ -z "$WAHL_ORT" ] && return 0

    # Eine Tilde ist im Textfeld nicht aufgelöst worden — hier nachholen,
    # sonst entstünde ein Verzeichnis, das buchstäblich "~" heisst. Genau
    # das tippt aber jeder Zweite ein, weil es überall sonst funktioniert.
    #
    # Die Prüfung meldet hier SC2088 ("Tilde does not expand in quotes").
    # Das ist der Sinn der Zeile: Die Tilde ist EINGABE, kein Pfad, den wir
    # benutzen wollen — sie steht in einem case-MUSTER und wird gerade
    # durch das Heimatverzeichnis ersetzt. (Ein Kommentar darf hier auch
    # nicht mit dem Wort der Prüfung beginnen: Er würde selbst als
    # Direktive gelesen.)
    # shellcheck disable=SC2088
    case "$WAHL_ORT" in "~"|"~/"*) WAHL_ORT="$MCS_HOME${WAHL_ORT#\~}" ;; esac

    case "$WAHL_ORT" in
      /*) pfad_ist_schlicht "$WAHL_ORT" && break ;;
    esac
    # Ohne Terminal käme hier sonst eine Endlosschleife: read liefert nichts
    # mehr, frage_text nimmt die Vorgabe, und die ist bereits geprüft.
    [ "$ASSISTENT_STANDARD" = true ] && return 0
    printf '    %sBitte einen vollständigen Pfad angeben — mit / am Anfang,%s\n' \
      "$F_GELB" "$F_AUS"
    printf '    %sohne Leerzeichen, Umlaute und Sonderzeichen.%s\n' \
      "$F_GELB" "$F_AUS"
  done
  WAHL_ORT="${WAHL_ORT%/}"

  MC_DIR="$WAHL_ORT"
  MCS_CONF="$MC_DIR/mcs.conf"
  # Liegt am neuen Ort bereits eine Installation, gilt DEREN Konfiguration.
  # shellcheck source=/dev/null
  if [ -f "$MCS_CONF" ]; then . "$MCS_CONF"; fi
  # Die abgeleiteten Pfade neu bilden — sie hingen am alten MC_DIR.
  MC_DIR="${MCS_DIR:-$MC_DIR}"
  MC_SERVER_DIR="${MCS_SERVER_DIR:-$MC_DIR/mc_server}"
  MC_BACKUP_DIR="${MCS_BACKUP_DIR:-$MC_DIR/mcs_backup}"
}
installationsort_erfragen

# Erst prüfen, ob überhaupt installiert werden kann — dann fragen. Sonst
# beantwortet jemand zehn Fragen und erfährt danach, dass die Platte voll ist.
vorpruefung

# Gibt es hier schon eine Installation? Das muss VOR der Bestätigung gesagt
# werden, nicht danach: Eine bestehende server.properties wird nie
# überschrieben — Spielmodus, Port, Sichtweite und Weltname aus dem
# Assistenten haben dann keine Wirkung. Bis 2026-08-26 bestätigte der Nutzer
# elf Werte und erfuhr erst hinterher in einer Zeile, dass sie verworfen
# wurden.
if [ -f "$MC_SERVER_DIR/server.properties" ]; then
  BESTEHENDE_INSTALLATION=true
else
  BESTEHENDE_INSTALLATION=false
fi

assistent_fragen_stellen

if [ "$BESTEHENDE_INSTALLATION" = true ]; then
  echo ""
  echo "  ────────────────────────────────────────────────────────────"
  echo "  Hier läuft bereits eine Installation."
  echo ""
  echo "  Die bestehende server.properties bleibt unangetastet — sie ist"
  echo "  die Fassung, mit der wirklich gespielt wird. Spielmodus,"
  echo "  Schwierigkeit, Sichtweite, Spielerzahl, Port und Weltname aus"
  echo "  den Fragen oben werden deshalb NICHT angewendet."
  echo ""
  echo "  Angewendet werden: aktualisierte Skripte und Dienste, sowie auf"
  echo "  Wunsch Plugins, Weboberfläche und Firewall."
  echo ""
  echo "  Einzelne Werte ändern:  mcs config-diff   bzw. direkt in"
  echo "  $MC_SERVER_DIR/server.properties"
fi

if ! assistent_auswahl_anzeigen; then
  echo ""
  echo "Abgebrochen. Es wurde nichts verändert."
  exit 0
fi

# Die Reihenfolge ist nicht beliebig:
#
#   plugins_laden VOR server_starten   Paper lädt Plugins ausschließlich beim
#                                      Start. Lief das Laden danach, lagen
#                                      vier frische Jars im Ordner und keines
#                                      war aktiv — ohne jeden Hinweis darauf.
#
#   admin VOR firewall                 Erst dort steht fest, auf welchem Port
#                                      die Weboberfläche wirklich lauscht.
#                                      Stand die Firewall vorher, machte sie
#                                      den Port zu, und der Abschlussbildschirm
#                                      verwies auf eine Oberfläche, die nicht
#                                      erreichbar war.
#
#   firewall ZULETZT vor dem Start     Sie ist der Eingriff mit der größten
#                                      Wirkung aufs übrige System.
verzeichnisse_einrichten
software_installieren
paper_herunterladen
server_konfigurieren
auswahl_anwenden
rcon_einrichten
dienste_einrichten
backup_einplanen
plugins_laden
admin_oberflaeche_einrichten
sicherheitsupdates_einrichten
firewall_einrichten
server_starten

# ----------------------------------------------------------------------------
# Kommt überhaupt jemand rein? (Lastenheft 5.6)
# ----------------------------------------------------------------------------
# Ohne diesen Schritt endet die Installation mit "Port im Router freigeben" —
# und wer einen DS-Lite-Anschluss hat, gibt ihn frei, prüft die Firewall,
# wechselt den DNS-Anbieter und sucht wochenlang einen Fehler, den es auf
# seinem Pi gar nicht gibt.
#
# DAS ZEITPROBLEM: Der Serverstart läuft im Hintergrund weiter, und der
# erste erzeugt minutenlang die Welt. Ein Test von außen käme währenddessen
# zurück mit "nicht erreichbar" — richtig gemessen und trotzdem
# irreführend, weil der Server einfach noch nicht so weit ist.
#
# Deshalb wird kurz gewartet, bis der Port wirklich lauscht. Kommt er nicht
# rechtzeitig, wird das gesagt statt geraten. Die Auskunft über den
# ANSCHLUSS (DS-Lite, Anbieter-NAT) liefert das Skript ohnehin auch dann —
# und die ist an dieser Stelle die wichtigere.
erreichbarkeit_pruefen() {
  local SKRIPT="$MC_DIR/erreichbarkeit.sh"
  [ -x "$SKRIPT" ] || return 0
  SCHRITT="Erreichbarkeit"
  echo ""
  echo "===== Erreichbarkeit von außen ====="
  echo "Dafür werden zwei Dienste im Internet gefragt: checkipv4.dedyn.io"
  echo "(deSEC, die eigene öffentliche Adresse) und api.mcsrvstat.us"
  echo "(verbindet sich von außen mit dem Server)."
  echo ""

  local PORT_JETZT="${ABSCHLUSS_PORT:-25565}"
  if command -v ss >/dev/null 2>&1; then
    local WARTEN=0
    while [ "$WARTEN" -lt 60 ]; do
      if ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${PORT_JETZT}\$"; then
        break
      fi
      sleep 3
      WARTEN=$((WARTEN + 3))
    done
    if [ "$WARTEN" -ge 60 ]; then
      echo "Der Server ist nach einer Minute noch nicht so weit — beim ersten"
      echo "Start erzeugt er die Welt, das dauert. Was am ANSCHLUSS liegt,"
      echo "steht trotzdem unten; den vollständigen Test später wiederholen:"
      echo "  mcs erreichbarkeit"
      echo ""
    fi
  fi

  # Rückgabewert 1 heisst "nicht erreichbar" — das ist eine Auskunft, kein
  # Fehler der Installation. Ohne das "|| true" schlüge hier die ERR-Falle zu
  # und die Installation meldete einen Abbruch, obwohl alles steht.
  "$SKRIPT" || true
}

# --- Abschluss ---------------------------------------------------------------
# Welcher Port gilt wirklich? Bei einer bestehenden Installation wurde die
# Antwort aus dem Assistenten nicht angewendet — dann zählt, was in der
# server.properties steht. Sonst hätte der Abschluss hier den Router auf
# einen Port geschickt, auf dem gar nichts lauscht.
ABSCHLUSS_PORT="${WAHL_PORT:-25565}"
if [ -f "$MC_SERVER_DIR/server.properties" ]; then
  ECHTER=$(sed -n 's/^server-port=//p' "$MC_SERVER_DIR/server.properties" 2>/dev/null | tail -n1) || ECHTER=""
  [ -n "$ECHTER" ] && ABSCHLUSS_PORT="$ECHTER"
fi

# Erst hier, nicht direkt nach server_starten: Der Test wartet auf genau
# diesen Port, und welcher es ist, steht erst in den Zeilen darüber fest.
# Davor haette er auf 25565 gewartet — also bei jedem abweichenden Port eine
# Minute lang auf etwas, das dort nie lauschen wird.
erreichbarkeit_pruefen

NAECHSTE=()
if [ "${WAHL_WHITELIST:-true}" = true ]; then
  NAECHSTE+=(
    "Spieler einladen    mcs cmd \"whitelist add SPIELERNAME\""
    "${F_LEISE}Die Whitelist ist aktiv — ohne Eintrag kommt niemand rein.${F_AUS}"
    ""
  )
fi
if [ "${PLUGINS_UNVOLLSTAENDIG:-false}" = true ]; then
  NAECHSTE+=(
    "${F_GELB}Nicht alle Plugins konnten geladen werden.${F_AUS}"
    "Nachholen           mcs plugins --laden, danach mcs restart"
    ""
  )
fi
NAECHSTE+=(
  "Läuft alles?        mcs status"
  "Zusehen             mcs log"
  "Pause machen        mcs aus   (schaltet wirklich alles ab, auch nach Neustart)"
  "Alle Befehle        mcs hilfe"
  ""
  "Von außen erreichbar machen: Port ${ABSCHLUSS_PORT}/TCP im Router auf"
  "diesen Pi weiterleiten. Mehr dazu im README, Abschnitt Sicherheit."
)
if [ "${WAHL_ADMIN:-false}" = true ]; then
  NAECHSTE+=(
    ""
    "Die Weboberfläche hat beim Einrichten ein Passwort angezeigt."
    "Es steht in: $MC_DIR/admin/.env"
  )
fi

# Ganz am Ende, nach allem anderen: Welcher Stand hier wirklich fertig
# eingerichtet wurde. Bricht die Installation vorher ab, entsteht diese
# Datei nicht — und die Weboberfläche sagt dann "Stand nicht feststellbar"
# statt eine Zahl zu behaupten, für die niemand geradestehen kann.
STAND="$(head -n1 "$REPO_DIR/VERSION" 2>/dev/null | tr -d '[:space:]' || true)"
if [ -n "$STAND" ]; then
  {
    echo "# Von install.sh geschrieben. Welcher Stand hier zuletzt"
    echo "# VOLLSTAENDIG eingerichtet wurde — nicht, was im Repo steht."
    echo "MCS_STAND=$STAND"
    echo "MCS_STAND_ZEIT=$(date '+%Y-%m-%d %H:%M:%S')"
    echo "MCS_STAND_WOMIT=install.sh"
  } > "$MC_DIR/ausgerollt"
fi

assistent_ende "${NAECHSTE[@]}"
