#!/bin/bash
#
# plugin-update.sh — Hält die Plugins mit der plugins.txt im Einklang.
#
# Bisher waren Plugins der einzige Teil des Servers, den das Repository gar
# nicht kannte. Ein Klon auf einem frischen Pi ergab deshalb einen anderen
# Server als den, der zu Hause läuft.
#
# Aufruf (als Benutzer pi):
#   ./plugin-update.sh              zeigt Soll und Ist im Vergleich
#   ./plugin-update.sh --laden      lädt fehlende Plugins herunter
#   ./plugin-update.sh --erfassen   schreibt die installierten Plugins in
#                                   plugins.txt (einmalig zum Befüllen)
#
# GELÖSCHT WIRD NIE ETWAS. Ein Plugin, das auf dem Pi liegt, aber nicht in
# der Liste steht, wird nur gemeldet — in den Plugin-Ordnern stecken
# Einstellungen und Datenbanken, die niemand versehentlich verlieren soll.

set -euo pipefail

# Wo liegt die Installation, wenn mcs.conf (noch) fehlt? Im Heimatverzeichnis
# des Benutzers, dem der Server gehört. Bis 2026-08-28 stand hier fest
# "/home/pi" — auf jedem Pi mit einem anderen Benutzernamen zeigte der
# Rückfallwert damit stumm ins Leere. Siehe CLAUDE.md.
MCS_HOME="${HOME:-/home/$(id -un)}"
MCS_CONF="${MCS_CONF:-$MCS_HOME/mcs/mcs.conf}"
# shellcheck source=/dev/null
if [ -f "$MCS_CONF" ]; then . "$MCS_CONF"; fi

MC_SERVER_DIR="${MC_SERVER_DIR:-${MCS_SERVER_DIR:-$MCS_HOME/mcs/mc_server}}"
PLUGIN_DIR="$MC_SERVER_DIR/plugins"

SKRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LISTE="${MCS_PLUGIN_LISTE:-$SKRIPT_DIR/plugins.txt}"

UA="Pi-MCS/2.1 plugin-update (privater Raspberry-Pi-Server)"

MODUS="zeigen"
case "${1:-}" in
  --laden)    MODUS="laden" ;;
  --erfassen) MODUS="erfassen" ;;
  "")         MODUS="zeigen" ;;
  *)
    echo "Unbekannter Parameter: $1" >&2
    echo "Erlaubt: --laden | --erfassen | (ohne Parameter)" >&2
    exit 1
    ;;
esac

mkdir -p "$PLUGIN_DIR"

# ----------------------------------------------------------------------------
# Name und Version aus einer Plugin-Datei lesen
# ----------------------------------------------------------------------------
# Jedes Bukkit-/Paper-Plugin enthält eine plugin.yml mit "name:" und
# "version:". unzip -p gibt eine Datei aus dem Archiv aus, ohne es zu
# entpacken. Klappt das nicht, wird der Dateiname als Ersatz genommen.
plugin_kennung() {
  local JAR="$1" NAME="" VERSION="" YML=""
  if command -v unzip >/dev/null 2>&1; then
    YML=$(unzip -p "$JAR" plugin.yml 2>/dev/null || unzip -p "$JAR" paper-plugin.yml 2>/dev/null || true)
  fi
  if [ -n "$YML" ]; then
    NAME=$(printf '%s\n' "$YML" | sed -n "s/^name:[[:space:]]*['\"]\\{0,1\\}\\([^'\"]*\\)['\"]\\{0,1\\}[[:space:]]*$/\\1/p" | head -n1)
    VERSION=$(printf '%s\n' "$YML" | sed -n "s/^version:[[:space:]]*['\"]\\{0,1\\}\\([^'\"]*\\)['\"]\\{0,1\\}[[:space:]]*$/\\1/p" | head -n1)
  fi
  [ -n "$NAME" ] || NAME="$(basename "$JAR" .jar)"
  [ -n "$VERSION" ] || VERSION="unbekannt"
  printf '%s|%s\n' "$NAME" "$VERSION"
}

# ----------------------------------------------------------------------------
# --erfassen: den Ist-Zustand in plugins.txt schreiben
# ----------------------------------------------------------------------------
if [ "$MODUS" = "erfassen" ]; then
  if ! command -v unzip >/dev/null 2>&1; then
    echo "Hinweis: 'unzip' ist nicht installiert — Name und Version werden aus"
    echo "den Dateinamen abgeleitet. Genauer wird es mit: sudo apt install unzip"
    echo ""
  fi

  ANZAHL=0
  {
    echo "# Erfasst am $(date '+%Y-%m-%d %H:%M:%S') aus $PLUGIN_DIR"
    echo "# Die Spalte 'url' muss von Hand nachgetragen werden — woher eine"
    echo "# Datei ursprünglich kam, lässt sich hier nicht ermitteln. Ohne URL"
    echo "# kann das Plugin auf einem frischen Pi nicht geladen werden."
    echo "#"
    echo "# name|version|url|sha256"
    for JAR in "$PLUGIN_DIR"/*.jar; do
      [ -f "$JAR" ] || continue
      SHA=$(sha256sum "$JAR" | cut -d' ' -f1)
      # Steht genau diese Datei (gleiche Pruefsumme) schon in der Liste,
      # bleibt ihre Zeile, wie sie ist — samt URL. Bis zum 23.09.2026 wurde
      # jede Zeile neu abgeleitet, mit leerer URL: Wer der Empfehlung weiter
      # unten folgte ("mit --erfassen aufnehmen"), verlor die Download-
      # Adressen ALLER gepflegten Plugins, auf dem Pi fuenf Stueck, ohne
      # Sicherung.
      ALT=""
      [ -f "$LISTE" ] && ALT=$(awk -F'|' -v s="$SHA" \
        '!/^[[:space:]]*#/ && $4 == s { print; exit }' "$LISTE")
      if [ -n "$ALT" ]; then
        echo "$ALT"
      else
        # Name aus der plugin.yml — wie bei einer Installation ueber die
        # Oberflaeche (admin/plugins.py), die danach "<Name>.jar" ablegt und
        # Soll und Ist nach diesem Namen zuordnet. Hier stand am 23.09.2026
        # kurz der Dateiname; die Oberflaeche haette ein so erfasstes Plugin
        # dann doppelt gezeigt ("fehlt" und "zusaetzlich"). Eine Datei, die
        # von Hand anders benannt wurde (etwa "plugin-1.0.jar"), meldet der
        # Abgleich unten weiterhin laut — umbenennen hilft.
        echo "$(plugin_kennung "$JAR")||${SHA}"
      fi
      ANZAHL=$((ANZAHL + 1))
    done
  } > "$LISTE.neu"

  if [ "$ANZAHL" -eq 0 ]; then
    echo "Keine Plugins in $PLUGIN_DIR gefunden — nichts zu erfassen."
    rm -f "$LISTE.neu"
    exit 0
  fi

  # Mit Zeitstempel: Eine einzige ".vorher" ueberschrieb der ZWEITE Lauf mit
  # der schon ausgeduennten Liste — die Kommentare und auskommentierten
  # Vorschlaege des Originals waren dann ohne Sicherung weg (Zweitmeinung zu
  # Durchgang 1).
  SICHERUNG=""
  if [ -f "$LISTE" ]; then
    SICHERUNG="$LISTE.vorher-$(date +%Y%m%d-%H%M%S)"
    cp -p "$LISTE" "$SICHERUNG"
    # Die fuenf neuesten bleiben, wie bei konfig.sicherung_anlegen — sonst
    # haeuften sie sich mit jedem Lauf (Zweitmeinung zu Durchgang 2). Der
    # Zeitstempel sortiert sich als Text richtig.
    find "$(dirname "$LISTE")" -maxdepth 1 -name "$(basename "$LISTE").vorher-*" \
      | sort -r | tail -n +6 | while IFS= read -r ALT; do rm -f "$ALT"; done
  fi
  mv "$LISTE.neu" "$LISTE"
  echo "$ANZAHL Plugin(s) nach $LISTE geschrieben."
  [ -n "$SICHERUNG" ] && echo "Die bisherige Liste liegt als $SICHERUNG daneben."
  # Nicht "ins Repo übernehmen": plugins.txt gehört seit Etappe C dem Pi
  # (lib/dateien.sh, "nur-wenn-fehlt"). Im Repo liegt nur die .beispiel.
  echo "Wo die Spalte 'url' leer ist, bitte ergänzen — ohne sie kann das"
  echo "Plugin auf einem frischen Pi nicht geladen werden."
  exit 0
fi

# ----------------------------------------------------------------------------
# Soll-Liste einlesen
# ----------------------------------------------------------------------------
if [ ! -f "$LISTE" ]; then
  echo "Hinweis: $LISTE gibt es nicht — es werden keine Plugins verwaltet."
  exit 0
fi

FEHLEND=0
VORHANDEN=0
FEHLER=0

while IFS='|' read -r NAME VERSION URL SHA256; do
  # Kommentare und Leerzeilen überspringen.
  case "${NAME:-}" in ''|\#*) continue ;; esac
  [ -n "${SHA256:-}" ] || { echo "  ! $NAME: keine Prüfsumme in der Liste — übersprungen"; FEHLER=$((FEHLER + 1)); continue; }

  ZIEL="$PLUGIN_DIR/${NAME}.jar"

  if [ -f "$ZIEL" ] && [ "$(sha256sum "$ZIEL" | cut -d' ' -f1)" = "$SHA256" ]; then
    echo "  ok  $NAME $VERSION"
    VORHANDEN=$((VORHANDEN + 1))
    continue
  fi

  if [ "$MODUS" = "zeigen" ]; then
    if [ -f "$ZIEL" ]; then
      echo "  ?   $NAME: installierte Datei weicht von der Liste ab"
    else
      echo "  --  $NAME $VERSION fehlt"
    fi
    FEHLEND=$((FEHLEND + 1))
    continue
  fi

  # --laden
  if [ -z "${URL:-}" ]; then
    echo "  ! $NAME: keine URL hinterlegt — bitte in $LISTE nachtragen"
    FEHLER=$((FEHLER + 1))
    continue
  fi

  echo "  Lade $NAME $VERSION ..."
  TMP="$PLUGIN_DIR/.${NAME}.download"
  if ! curl -fsSL --max-time 300 --retry 3 -H "User-Agent: $UA" -o "$TMP" "$URL"; then
    echo "  ! $NAME: Download fehlgeschlagen"
    rm -f "$TMP"
    FEHLER=$((FEHLER + 1))
    continue
  fi

  IST=$(sha256sum "$TMP" | cut -d' ' -f1)
  if [ "$IST" != "$SHA256" ]; then
    echo "  ! $NAME: Prüfsumme stimmt nicht — Datei wird verworfen"
    echo "      erwartet: $SHA256"
    echo "      erhalten: $IST"
    rm -f "$TMP"
    FEHLER=$((FEHLER + 1))
    continue
  fi

  # Eine bestehende Datei zur Sicherheit aufheben statt überschreiben.
  [ -f "$ZIEL" ] && mv -f "$ZIEL" "$ZIEL.vorher"
  mv "$TMP" "$ZIEL"
  echo "  ok  $NAME $VERSION installiert"
  VORHANDEN=$((VORHANDEN + 1))
done < "$LISTE"

# ----------------------------------------------------------------------------
# Plugins melden, die auf dem Pi liegen, aber nicht in der Liste stehen
# ----------------------------------------------------------------------------
for JAR in "$PLUGIN_DIR"/*.jar; do
  [ -f "$JAR" ] || continue
  BASIS="$(basename "$JAR" .jar)"
  if ! { grep -v '^[[:space:]]*#' "$LISTE" | cut -d'|' -f1 | grep -qx "$BASIS"; }; then
    echo "  +   $BASIS liegt auf dem Pi, steht aber nicht in $LISTE"
    echo "      (wird NICHT gelöscht — bei Bedarf mit --erfassen aufnehmen)"
  fi
done

echo ""
echo "$VORHANDEN passend, $FEHLEND fehlend/abweichend, $FEHLER Fehler."
if [ "$FEHLEND" -gt 0 ] && [ "$MODUS" = "zeigen" ]; then
  echo "Fehlende Plugins laden mit: mcs plugins --laden"
fi
[ "$FEHLER" -eq 0 ]
