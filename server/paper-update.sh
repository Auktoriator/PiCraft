#!/bin/bash
#
# paper-update.sh — Hält Paper aktuell, ohne die Welt aufs Spiel zu setzen.
#
# Es gibt zwei Sorten Update, und sie sind grundverschieden:
#
#   Neuer BUILD derselben Minecraft-Version (z. B. 26.2 Build 119 -> 129):
#     reine Fehlerkorrekturen, die Welt bleibt, wie sie ist. Der Rückweg ist
#     ein Austausch der paper.jar. Das sollte man regelmäßig machen —
#     sobald der Server aus dem Internet erreichbar ist, auch wegen
#     Sicherheitskorrekturen.
#
#   Neue MINECRAFT-Version (z. B. 26.2 -> 26.3):
#     wandelt beim nächsten Start die Weltdateien um, und das ist ENDGÜLTIG —
#     die alte Serverversion kann die umgewandelte Welt nicht mehr öffnen.
#     Deshalb passiert das nur mit --minecraft, nie nebenbei, und nie ohne
#     Backup vorher.
#
# Aufruf (als Benutzer pi, kein sudo nötig; meist über "mcs update"):
#   ./paper-update.sh                     neuesten stabilen Build derselben
#                                         Minecraft-Version installieren
#   ./paper-update.sh --pruefen           nur nachsehen, was es Neues gibt
#   ./paper-update.sh --minecraft 26.3    auf eine andere Version wechseln
#                                         (legt vorher ein Backup an)
#   ./paper-update.sh --festgelegt        genau den Build aus versions.env
#                                         installieren (Erstinstallation)
#
# Was danach festgelegt ist, schreibt das Skript selbst in versions.env —
# in die Installation UND ins Repository, dort mit einem Commit. Niemand
# muss eine Prüfsumme von Hand abtippen.
#
# Wirksam wird ein neuer Build erst mit dem nächsten Neustart: mcs restart

set -euo pipefail

# ----------------------------------------------------------------------------
# Einstellungen
# ----------------------------------------------------------------------------

# Zentrale Pfade.
# Wo liegt die Installation, wenn mcs.conf (noch) fehlt? Im Heimatverzeichnis
# des Benutzers, dem der Server gehört. Bis 2026-08-28 stand hier fest
# "/home/pi" — auf jedem Pi mit einem anderen Benutzernamen zeigte der
# Rückfallwert damit stumm ins Leere. Siehe CLAUDE.md.
MCS_HOME="${HOME:-/home/$(id -un)}"
MCS_CONF="${MCS_CONF:-$MCS_HOME/mcs/mcs.conf}"
# shellcheck source=/dev/null
if [ -f "$MCS_CONF" ]; then . "$MCS_CONF"; fi

# Zielverzeichnis. MC_SERVER_DIR aus der Umgebung hat Vorrang (so ruft es
# das Installationsskript auf), danach der Wert aus mcs.conf.
MC_SERVER_DIR="${MC_SERVER_DIR:-${MCS_SERVER_DIR:-$MCS_HOME/mcs/mc_server}}"

# Die Versionsvorgaben liegen neben diesem Skript (in der Installation) oder
# im Repo unter server/. Beides wird berücksichtigt.
SKRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSIONS_DATEI="${MCS_VERSIONS_DATEI:-$SKRIPT_DIR/versions.env}"
# shellcheck source=versions.env
if [ -f "$VERSIONS_DATEI" ]; then . "$VERSIONS_DATEI"; fi

# Merkzettel: welche Version gerade wirklich installiert ist. Ohne ihn
# könnte das Skript nicht erkennen, ob ein Versionswechsel bevorsteht.
ZUSTAND_DATEI="$MC_SERVER_DIR/paper.installiert"

# Was "--pruefen" zuletzt bei PaperMC gesehen hat. Die Weboberfläche liest
# es, statt beim Aufbau der Seite selbst nach außen zu fragen (Lastenheft
# 5.7.2: nach außen nur auf Klick). Eine Notiz, keine Vorgabe.
VERFUEGBAR_DATEI="$MC_SERVER_DIR/paper.verfuegbar"

# Die PaperMC-API verlangt einen aussagekräftigen "User-Agent"
# (eine Art Absenderkennung), sonst lehnt sie Anfragen ab.
API="https://fill.papermc.io/v3"
UA="PiCraft/2.1 paper-update (privater Raspberry-Pi-Server)"

# Kleine Hilfsfunktion: API-Abfrage mit Kennung, Zeitlimit und Fehlerabbruch.
# -L folgt Umleitungen, --retry überbrückt kurze Netzaussetzer.
api_abfrage() {
  curl -fsSL --max-time 30 --retry 3 --retry-delay 2 -H "User-Agent: $UA" "$1"
}

# Der neueste STABILE Build einer Minecraft-Version als JSON, oder "null".
#
# "Stabil" ist keine Formsache: Am 03.10.2026 gab es für 26.3 bereits 143
# Builds, aber jeder einzelne im Kanal BETA. Die alte Prüfung nannte 26.3
# trotzdem "verfügbar" — und "mcs update --minecraft 26.3" wäre dann mit
# "noch kein stabiler Build" gescheitert.
neuester_stabiler_build() {
  api_abfrage "$API/projects/paper/versions/$1/builds" \
    | jq '[.[] | select(.channel == "STABLE")] | max_by(.id)'
}

# Ist Version $1 neuer als Version $2? (26.10 ist neuer als 26.9 — sort -V
# weiß das, ein Textvergleich nicht.)
ist_neuer() {
  [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)" = "$1" ]
}

# ----------------------------------------------------------------------------
# Aufrufparameter auswerten
# ----------------------------------------------------------------------------
MODUS=build
NEUE_VERSION=""
OHNE_BACKUP=false

while [ $# -gt 0 ]; do
  case "$1" in
    --pruefen)
      MODUS=pruefen
      ;;
    --festgelegt)
      MODUS=festgelegt
      ;;
    --minecraft)
      shift
      NEUE_VERSION="${1:-}"
      MODUS=minecraft
      if [ -z "$NEUE_VERSION" ]; then
        echo "Fehler: --minecraft braucht eine Version, z. B. --minecraft 26.3" >&2
        exit 1
      fi
      ;;
    --ohne-backup)
      # Nur für den Fall, dass gerade eben schon von Hand gesichert wurde.
      OHNE_BACKUP=true
      ;;
    -h|--hilfe|--help)
      sed -n '2,32p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unbekannter Parameter: $1" >&2
      echo "Erlaubt: --pruefen | --festgelegt | --minecraft <version> | --ohne-backup" >&2
      exit 1
      ;;
  esac
  shift
done

cd "$MC_SERVER_DIR" || {
  echo "Fehler: Verzeichnis $MC_SERVER_DIR nicht gefunden." >&2
  exit 1
}

# Nur ein Lauf zur selben Zeit. Zwei gleichzeitige — ein Klick in der
# Oberfläche, während im Terminal "mcs update" läuft — schrieben in dieselbe
# paper.jar.download, und die Aufräumfalle des einen löschte den Download
# des anderen. Das Nachsehen schreibt nur eine Notiz und braucht die Sperre
# nicht.
if [ "$MODUS" != pruefen ] && command -v flock >/dev/null 2>&1; then
  exec 9>"$MC_SERVER_DIR/.paper-update.sperre"
  if ! flock -n 9; then
    echo "Fehler: Gerade läuft schon ein Paper-Update. Bitte warten, bis es fertig ist." >&2
    exit 1
  fi
fi

# ----------------------------------------------------------------------------
# 1) Was ist installiert, was ist festgelegt?
# ----------------------------------------------------------------------------
INSTALLIERTE_VERSION=""
INSTALLIERTER_BUILD=""
if [ -f "$ZUSTAND_DATEI" ]; then
  INSTALLIERTE_VERSION=$(sed -n 's/^version=//p' "$ZUSTAND_DATEI" | tail -n1)
  INSTALLIERTER_BUILD=$(sed -n 's/^build=//p' "$ZUSTAND_DATEI" | tail -n1)
fi

ZIEL_VERSION="${MCS_MINECRAFT_VERSION:-}"
ZIEL_BUILD="${MCS_PAPER_BUILD:-}"
ZIEL_SHA256="${MCS_PAPER_SHA256:-}"

if [ -z "$ZIEL_VERSION" ] || [ -z "$ZIEL_BUILD" ]; then
  echo "Fehler: In $VERSIONS_DATEI fehlen MCS_MINECRAFT_VERSION oder MCS_PAPER_BUILD." >&2
  exit 1
fi

# ----------------------------------------------------------------------------
# 2) Nur nachsehen, was es Neues gibt
# ----------------------------------------------------------------------------
if [ "$MODUS" = pruefen ]; then
  # Verglichen wird mit dem, was LÄUFT, nicht mit dem, was festgelegt ist —
  # bis zum 03.10.2026 hieß es hier "installiert", gemeint war aber die
  # Vorgabe. Meist ist beides dasselbe; wenn nicht, ist das Installierte
  # die ehrliche Antwort.
  BASIS_BUILD="${INSTALLIERTER_BUILD:-$ZIEL_BUILD}"
  echo "Installiert:  Paper ${INSTALLIERTE_VERSION:-unbekannt}${INSTALLIERTER_BUILD:+ Build $INSTALLIERTER_BUILD}"
  echo "Festgelegt:   Paper $ZIEL_VERSION Build $ZIEL_BUILD (versions.env)"
  echo ""

  NEUESTER=$(neuester_stabiler_build "$ZIEL_VERSION" | jq -r '.id // empty')
  if [ -z "$NEUESTER" ]; then
    echo "Für Minecraft $ZIEL_VERSION meldet PaperMC keinen stabilen Build."
  elif [ "$NEUESTER" -gt "$BASIS_BUILD" ]; then
    echo "Neuer Build für Minecraft $ZIEL_VERSION: $NEUESTER (installiert: $BASIS_BUILD)."
    echo "Nur Fehlerkorrekturen — die Welt wird dabei nicht umgewandelt."
    echo "Übernehmen mit:  mcs update     (wirksam nach: mcs restart)"
  else
    echo "Build $BASIS_BUILD ist der neueste stabile für Minecraft $ZIEL_VERSION."
  fi

  # Neuere Minecraft-Versionen: nur echte Versionsnummern (keine -rc/-pre),
  # nur wirklich NEUERE — bis zum 03.10.2026 standen hier 26.1.2 und 26.1.1
  # als "neuer" neben 26.2, weil einfach die ersten Einträge der Liste
  # genommen wurden —, und getrennt danach, ob es schon einen stabilen
  # Build gibt. Höchstens fünf werden nachgefragt; mehr als eine oder zwei
  # liegen in der Praxis nie vor einem.
  KANDIDATEN=$(api_abfrage "$API/projects/paper" \
    | jq -r '[.versions[][]] | map(select(test("^[0-9]+(\\.[0-9]+)+$")))[]' \
    | sort -V -r)
  STABIL=()
  BETA=()
  while read -r V; do
    [ -n "$V" ] || continue
    ist_neuer "$V" "$ZIEL_VERSION" || break     # absteigend sortiert: Rest ist älter
    [ $((${#STABIL[@]} + ${#BETA[@]})) -lt 5 ] || break
    if [ "$(neuester_stabiler_build "$V")" != "null" ]; then
      STABIL=("$V" "${STABIL[@]}")
    else
      BETA=("$V" "${BETA[@]}")
    fi
  done <<<"$KANDIDATEN"

  if [ ${#STABIL[@]} -gt 0 ]; then
    echo ""
    echo "Neuere Minecraft-Version mit stabilem Paper: ${STABIL[*]}"
    echo "ACHTUNG: Ein Wechsel wandelt die Welt endgültig um; zurück geht es nur"
    echo "über ein Backup. Vorher nachsehen, ob alle Plugins dafür erschienen sind:"
    echo "  mcs update --minecraft ${STABIL[${#STABIL[@]}-1]}"
  fi
  if [ ${#BETA[@]} -gt 0 ]; then
    echo ""
    echo "In Vorbereitung: Minecraft ${BETA[*]} — bei PaperMC bisher nur Beta-Builds."
    echo "Ein Wechsel geht erst, wenn PaperMC einen stabilen Build freigibt."
  fi

  # Notiz für die Weboberfläche. Erst vollständig schreiben, dann an ihren
  # Platz legen: Eine halb geschriebene Notiz sähe aus wie "nichts Neues".
  # Scheitert das, war das Nachsehen trotzdem erfolgreich — deshalb nur ein
  # Hinweis, kein Fehler.
  if {
       echo "# Was 'mcs update --pruefen' zuletzt bei PaperMC gesehen hat."
       echo "# Nur eine Notiz fuer die Weboberflaeche, keine Vorgabe."
       echo "geprueft=$(date -Iseconds)"
       echo "version=$ZIEL_VERSION"
       echo "neuester_build=$NEUESTER"
       echo "neuere_stabil=$(IFS=,; echo "${STABIL[*]}")"
       echo "neuere_beta=$(IFS=,; echo "${BETA[*]}")"
     } > "$VERFUEGBAR_DATEI.neu" 2>/dev/null; then
    mv -f "$VERFUEGBAR_DATEI.neu" "$VERFUEGBAR_DATEI"
  else
    rm -f "$VERFUEGBAR_DATEI.neu"
    echo "Hinweis: $VERFUEGBAR_DATEI ließ sich nicht schreiben." >&2
  fi
  exit 0
fi

# ----------------------------------------------------------------------------
# 3) Versionswechsel? Dann Sicherheitsnetz spannen
# ----------------------------------------------------------------------------
# Rückschritt auf eine ältere Minecraft-Version ist keine Option: eine
# bereits umgewandelte Welt lässt sich damit nicht mehr öffnen.
rueckschritt_pruefen() {
  local ZIEL="$1"
  [ -n "$INSTALLIERTE_VERSION" ] || return 0
  [ "$ZIEL" != "$INSTALLIERTE_VERSION" ] || return 0

  local AELTESTE
  AELTESTE=$(printf '%s\n%s\n' "$ZIEL" "$INSTALLIERTE_VERSION" | sort -V | head -n1)
  if [ "$AELTESTE" = "$ZIEL" ]; then
    echo "Fehler: $ZIEL ist ÄLTER als die installierte Version $INSTALLIERTE_VERSION." >&2
    echo "Ein Rückschritt ist nicht möglich — die Welt wurde bereits umgewandelt." >&2
    echo "Der einzige Weg zurück führt über ein Backup von vor dem Wechsel:" >&2
    echo "  mcs restore" >&2
    exit 1
  fi
}

if [ "$MODUS" = minecraft ]; then
  rueckschritt_pruefen "$NEUE_VERSION"

  # Erst fragen, ob es überhaupt einen stabilen Build gibt — und zwar VOR
  # dem Backup. Sonst wartete man Minuten auf eine Sicherung, nur um dann
  # zu lesen, dass der Wechsel gar nicht geht.
  BUILD_INFO=$(neuester_stabiler_build "$NEUE_VERSION")
  if [ -z "$BUILD_INFO" ] || [ "$BUILD_INFO" = "null" ]; then
    echo "Fehler: Für Minecraft $NEUE_VERSION gibt es noch keinen stabilen Build." >&2
    echo "Nachsehen, was es gibt: mcs update --pruefen" >&2
    exit 1
  fi

  echo "=========================================================="
  echo " Wechsel der Minecraft-Version"
  echo "   von: ${INSTALLIERTE_VERSION:-unbekannt}"
  echo "   nach: $NEUE_VERSION"
  echo "=========================================================="
  echo "Beim nächsten Start wandelt der Server die Weltdateien in das neue"
  echo "Format um. Das lässt sich nicht rückgängig machen."
  echo ""

  if [ "$OHNE_BACKUP" = true ]; then
    echo "Hinweis: --ohne-backup gesetzt, es wird KEIN Backup angelegt."
  else
    BACKUP_SKRIPT="${MCS_BACKUP_SCRIPT:-$MCS_HOME/mcs/mcs_backup/minecraft-backup.sh}"
    if [ ! -x "$BACKUP_SKRIPT" ] && [ ! -f "$BACKUP_SKRIPT" ]; then
      echo "Fehler: Backup-Skript $BACKUP_SKRIPT nicht gefunden." >&2
      echo "Ohne Backup wird nicht gewechselt. Notfalls: --ohne-backup" >&2
      exit 1
    fi
    echo "Lege zuerst ein Backup an (das kann ein paar Minuten dauern)..."
    if ! bash "$BACKUP_SKRIPT"; then
      echo "Fehler: Das Backup ist fehlgeschlagen — der Versionswechsel wird abgebrochen." >&2
      exit 1
    fi
    echo "Backup fertig."
    echo ""
  fi

  ZIEL_VERSION="$NEUE_VERSION"
  ZIEL_BUILD=$(echo "$BUILD_INFO" | jq -r '.id')
  ZIEL_SHA256=$(echo "$BUILD_INFO" | jq -r '.downloads["server:default"].checksums.sha256')

elif [ -n "$INSTALLIERTE_VERSION" ] && [ "$INSTALLIERTE_VERSION" != "$ZIEL_VERSION" ]; then
  # Die Vorgabe unterscheidet sich von dem, was läuft — das ist genau der
  # Fall, der früher still passierte. Hier wird er gemeldet statt
  # ausgeführt. Gilt für den Build-Weg genauso: Er bleibt IMMER in der
  # Minecraft-Version, die schon läuft.
  # Wäre es ein Rückschritt, sagt rueckschritt_pruefen das deutlicher.
  rueckschritt_pruefen "$ZIEL_VERSION"

  echo "Achtung: In $VERSIONS_DATEI steht Minecraft $ZIEL_VERSION," >&2
  echo "installiert ist aber $INSTALLIERTE_VERSION." >&2
  echo "" >&2
  echo "Ein Wechsel der Minecraft-Version wandelt die Welt endgültig um und" >&2
  echo "passiert deshalb nicht nebenbei. Bewusst wechseln mit:" >&2
  echo "  mcs update --minecraft $ZIEL_VERSION" >&2
  echo "" >&2
  echo "Oder versions.env wieder auf $INSTALLIERTE_VERSION zurücksetzen." >&2
  exit 1

elif [ "$MODUS" = build ]; then
  # Der Normalfall: neuester stabiler Build DERSELBEN Minecraft-Version.
  # Nummer und Prüfsumme kommen von PaperMC, nicht vom Menschen — bis zum
  # 03.10.2026 mussten beide von Hand in versions.env, und der Knopf in der
  # Oberfläche installierte nur, was dort schon stand. Er meldete deshalb
  # bei jedem Klick "nichts zu tun".
  BUILD_INFO=$(neuester_stabiler_build "$ZIEL_VERSION")
  NEUESTER=$(echo "$BUILD_INFO" | jq -r '.id // empty')
  if [ -z "$NEUESTER" ]; then
    echo "Fehler: Für Minecraft $ZIEL_VERSION meldet PaperMC keinen stabilen Build." >&2
    exit 1
  fi
  if [ "$NEUESTER" -gt "$ZIEL_BUILD" ]; then
    # Angesagt wird gegenüber dem, was LÄUFT. Liegt nur die Vorgabe zurück
    # (ein Ausrollen hat eine ältere versions.env gebracht), ist der Build
    # schon da, und Schritt 5 zieht nur die Vorgabe nach.
    if [ "$NEUESTER" -gt "${INSTALLIERTER_BUILD:-$ZIEL_BUILD}" ]; then
      echo "Neuer Build für Minecraft $ZIEL_VERSION: ${INSTALLIERTER_BUILD:-$ZIEL_BUILD} -> $NEUESTER"
      echo "(nur Fehlerkorrekturen, die Welt bleibt unverändert)"
    fi
    ZIEL_BUILD="$NEUESTER"
    ZIEL_SHA256=$(echo "$BUILD_INFO" | jq -r '.downloads["server:default"].checksums.sha256')
  fi
fi

# ----------------------------------------------------------------------------
# Vorgabe nachziehen: versions.env in der Installation UND im Repository
# ----------------------------------------------------------------------------
# versions.env gehört dem Repository (lib/dateien.sh), und ./deploy.sh rollt
# sie von dort aus. Bis zum 23.09.2026 wurde nur die Kopie auf dem Pi
# geändert, dazu "bitte committen" — für eine Datei, die in gar keinem
# Repository liegt. Das nächste Ausrollen stellte die alte Version zurück.
#
# Seit dem 03.10.2026 wird im Repository auch gleich committet, und zwar
# NUR diese eine Datei. Hatte sie dort schon vorher offene Änderungen, wird
# nicht committet: Die gehören jemandem, und ein Commit mit der Nachricht
# "Paper-Build" darf sie nicht ungefragt mitnehmen.
vorgaben_nachziehen() {
  local ZIELE=("$VERSIONS_DATEI") REPO_DATEI="" GIT_OK=false VORHER_SAUBER=false DATEI

  if [ -n "${MCS_REPO_DIR:-}" ] && [ -f "$MCS_REPO_DIR/server/versions.env" ]; then
    REPO_DATEI="$MCS_REPO_DIR/server/versions.env"
    # Läuft dieses Skript direkt aus dem Checkout, sind beide dieselbe Datei.
    [ "$REPO_DATEI" -ef "$VERSIONS_DATEI" ] || ZIELE+=("$REPO_DATEI")
    if command -v git >/dev/null 2>&1 \
       && git -C "$MCS_REPO_DIR" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
      GIT_OK=true
      if git -C "$MCS_REPO_DIR" diff --quiet HEAD -- server/versions.env 2>/dev/null; then
        VORHER_SAUBER=true
      fi
    fi
  fi

  for DATEI in "${ZIELE[@]}"; do
    if [ ! -w "$DATEI" ]; then
      echo "Hinweis: $DATEI ist nicht beschreibbar und bleibt, wie sie ist." >&2
      continue
    fi
    sed -i \
      -e "s/^MCS_MINECRAFT_VERSION=.*/MCS_MINECRAFT_VERSION=$ZIEL_VERSION/" \
      -e "s/^MCS_PAPER_BUILD=.*/MCS_PAPER_BUILD=$ZIEL_BUILD/" \
      -e "s/^MCS_PAPER_SHA256=.*/MCS_PAPER_SHA256=$ZIEL_SHA256/" \
      "$DATEI"
  done

  if [ -z "$REPO_DATEI" ]; then
    # Ohne Repository nur dann warnen, wenn sich wirklich etwas geändert hat.
    if [ "${MCS_PAPER_BUILD:-}" != "$ZIEL_BUILD" ] || [ "${MCS_MINECRAFT_VERSION:-}" != "$ZIEL_VERSION" ]; then
      echo "ACHTUNG: Das Repository wurde nicht gefunden (MCS_REPO_DIR). Dort" >&2
      echo "server/versions.env von Hand auf $ZIEL_VERSION / Build $ZIEL_BUILD setzen —" >&2
      echo "sonst stellt das nächste ./deploy.sh die alte Version zurück." >&2
    fi
    return 0
  fi

  [ "$GIT_OK" = true ] || return 0
  # Nichts geändert? Dann auch nichts zu committen.
  if git -C "$MCS_REPO_DIR" diff --quiet HEAD -- server/versions.env 2>/dev/null; then
    return 0
  fi

  local NACHRICHT="Paper $ZIEL_VERSION Build $ZIEL_BUILD festgelegt (mcs update)"
  if [ "$VORHER_SAUBER" != true ]; then
    echo "Hinweis: server/versions.env hatte im Repository schon vorher offene" >&2
    echo "Änderungen — deshalb kein automatischer Commit. Von Hand:" >&2
    echo "  cd $MCS_REPO_DIR && git commit -m '$NACHRICHT' server/versions.env" >&2
    return 0
  fi
  # Ohne eingerichtete Git-Identität scheiterte der Commit mit einem
  # Bildschirm voll "Please tell me who you are" — auf einem frisch
  # geklonten Pi der Normalfall (am 03.10.2026 im Wegwerfklon gesehen; auf
  # dem Entwicklungs-Pi steht sie nur in der Repo-Konfiguration). Dann
  # zeichnet das Werkzeug selbst, und so steht es auch im Log.
  local IDENTITAET=()
  if [ -z "$(git -C "$MCS_REPO_DIR" config user.email 2>/dev/null || true)" ]; then
    IDENTITAET=(-c user.name=PiCraft -c user.email=picraft@localhost)
  fi
  if git -C "$MCS_REPO_DIR" "${IDENTITAET[@]}" commit -q -m "$NACHRICHT" -- server/versions.env; then
    local ZWEIG
    ZWEIG=$(git -C "$MCS_REPO_DIR" branch --show-current 2>/dev/null || true)
    echo "Im Repository festgehalten: $NACHRICHT"
    echo "  (Zweig ${ZWEIG:-ohne Namen}, Commit $(git -C "$MCS_REPO_DIR" rev-parse --short HEAD))"
    echo "  Hochladen, wenn gewünscht:  git -C $MCS_REPO_DIR push"
  else
    echo "Hinweis: Der Commit im Repository ist fehlgeschlagen (siehe oben)." >&2
    echo "Die Datei ist geändert, aber nicht committet. Von Hand:" >&2
    echo "  cd $MCS_REPO_DIR && git commit -m '$NACHRICHT' server/versions.env" >&2
  fi
}

# ----------------------------------------------------------------------------
# 4) Build-Daten holen und gegen die festgelegte Prüfsumme halten
# ----------------------------------------------------------------------------
echo "Ziel: Paper $ZIEL_VERSION Build $ZIEL_BUILD"

BUILD_JSON=$(api_abfrage "$API/projects/paper/versions/$ZIEL_VERSION/builds" \
  | jq --argjson b "$ZIEL_BUILD" '[.[] | select(.id == $b)] | first')

if [ -z "$BUILD_JSON" ] || [ "$BUILD_JSON" = "null" ]; then
  echo "Fehler: Build $ZIEL_BUILD von Minecraft $ZIEL_VERSION ist bei PaperMC nicht (mehr) zu finden." >&2
  exit 1
fi

DATEINAME=$(echo "$BUILD_JSON" | jq -r '.downloads["server:default"].name')
DOWNLOAD_URL=$(echo "$BUILD_JSON" | jq -r '.downloads["server:default"].url')
SHA256_API=$(echo "$BUILD_JSON" | jq -r '.downloads["server:default"].checksums.sha256')

if [ -z "$ZIEL_SHA256" ]; then
  # Keine Prüfsumme hinterlegt (alte versions.env ohne die Zeile).
  ZIEL_SHA256="$SHA256_API"
elif [ "$ZIEL_SHA256" != "$SHA256_API" ]; then
  echo "Fehler: Die Prüfsumme aus $VERSIONS_DATEI passt nicht zu der, die" >&2
  echo "PaperMC für Build $ZIEL_BUILD nennt. Das darf nicht vorkommen." >&2
  echo "  hinterlegt: $ZIEL_SHA256" >&2
  echo "  von PaperMC: $SHA256_API" >&2
  echo "Bitte von Hand prüfen, bevor irgendetwas installiert wird." >&2
  exit 1
fi

# ----------------------------------------------------------------------------
# 5) Schon aktuell?
# ----------------------------------------------------------------------------
if [ -f "paper.jar" ]; then
  SHA256_IST=$(sha256sum paper.jar | cut -d' ' -f1)
  if [ "$SHA256_IST" = "$ZIEL_SHA256" ]; then
    if [ "$MODUS" = build ]; then
      echo "Build $ZIEL_BUILD ist der neueste stabile und schon installiert — nichts zu tun."
    else
      echo "paper.jar ist bereits genau dieser Build — nichts zu tun."
    fi
    # Merkzettel nachziehen, falls er fehlt (bestehende Installationen).
    printf 'version=%s\nbuild=%s\nsha256=%s\n' \
      "$ZIEL_VERSION" "$ZIEL_BUILD" "$ZIEL_SHA256" > "$ZUSTAND_DATEI"
    # Und die Vorgabe, falls sie hinter dem Installierten zurückliegt —
    # etwa weil ein Ausrollen eine ältere versions.env zurückgebracht hat.
    vorgaben_nachziehen
    exit 0
  fi
fi

# ----------------------------------------------------------------------------
# 6) Herunterladen und Prüfsumme kontrollieren
# ----------------------------------------------------------------------------
# Erst in eine temporäre Datei laden. Die echte paper.jar wird erst
# ersetzt, wenn der Download vollständig und korrekt ist.
TMP_DATEI="paper.jar.download"
trap 'rm -f "$TMP_DATEI"' EXIT

# Fortschrittsbalken nur im Terminal. Die Weboberfläche zeigt die Ausgabe
# nach dem Lauf an, und dort stünden sonst ein paar hundert Zeichen
# Balkenreste (am 03.10.2026 so gesehen).
FORTSCHRITT=(-sS)
[ -t 2 ] && FORTSCHRITT=()
echo "Lade $DATEINAME herunter..."
curl -fL "${FORTSCHRITT[@]}" --max-time 600 --retry 3 --retry-delay 2 \
  -H "User-Agent: $UA" -o "$TMP_DATEI" "$DOWNLOAD_URL"

echo "Prüfe SHA256-Prüfsumme..."
SHA256_NEU=$(sha256sum "$TMP_DATEI" | cut -d' ' -f1)
if [ "$SHA256_NEU" != "$ZIEL_SHA256" ]; then
  echo "Fehler: Prüfsumme stimmt nicht (Download beschädigt?). Breche ab." >&2
  echo "  erwartet: $ZIEL_SHA256" >&2
  echo "  erhalten: $SHA256_NEU" >&2
  exit 1
fi

# ----------------------------------------------------------------------------
# 7) Alte Datei sichern, neue aktivieren
# ----------------------------------------------------------------------------
# Auch bei laufendem Server unbedenklich: Java hält die alte Datei offen,
# mv tauscht nur den Namen. Wirksam wird der neue Build beim nächsten Start.
VORHER_DA=false
if [ -f "paper.jar" ]; then
  mv -f paper.jar paper.jar.vorher
  VORHER_DA=true
  echo "Bisherige Version als paper.jar.vorher gesichert."
fi
mv "$TMP_DATEI" paper.jar
trap - EXIT

# Merkzettel schreiben: ab jetzt weiß das Skript, was läuft.
printf 'version=%s\nbuild=%s\nsha256=%s\n' \
  "$ZIEL_VERSION" "$ZIEL_BUILD" "$ZIEL_SHA256" > "$ZUSTAND_DATEI"

vorgaben_nachziehen

echo ""
echo "Fertig: Paper $ZIEL_VERSION Build $ZIEL_BUILD installiert."
if [ "$VORHER_DA" = true ]; then
  echo "Wirksam wird er mit dem nächsten Neustart:  mcs restart"
fi
if [ "$MODUS" = minecraft ]; then
  echo ""
  echo "WICHTIG: Beim nächsten Start wandelt der Server die Welt um."
  echo "Das Backup von eben liegt in ${MCS_BACKUP_DIR:-$MCS_HOME/mcs/mcs_backup}."
fi
