#!/bin/bash
#
# messung-paper-verhalten.sh — Nachmessen, wie Paper sich wirklich verhält.
#
# Warum es dieses Skript gibt: Am 28.08.2026, zu Beginn von Etappe C, standen
# sechs Annahmen im Raum, auf denen die Konfigurations- und die Spielerseite
# der Weboberfläche aufbauen. Vier davon waren falsch — darunter eine, die
# in CLAUDE.md und im Lastenheft als Merksatz stand:
#
#   "Paper schreibt seine Konfigurationsdateien beim Herunterfahren neu."
#
# Es schreibt sie beim START neu. Wer sich auf den alten Satz verlassen
# hätte, hätte eine Vormerk-Mechanik für Dateien gebaut, die keine braucht,
# und die eine, die sie braucht, ungeschützt gelassen.
#
# Die Ergebnisse stehen in docs/pflichtenheft-etappe-c.md, Abschnitt 0, und
# als Korrekturen K3 bis K6 im Lastenheft. Dieses Skript ist dazu da, sie
# beim nächsten Paper-Update zu wiederholen — eine Messung, die man nicht
# wiederholen kann, ist ein Jahr später nur noch eine Behauptung.
#
# Was gemessen wird:
#   M1  Welche Spielerdateien legt Paper an, und was steht drin?
#   M2  Wie heißt die Spielzeit-Statistik in dieser Version?
#   M3  Wie sehen die RCON-Antworten für die Spielerseite aus?
#   M4  Wann werden server.properties und die YAML-Dateien neu geschrieben —
#       beim Start, beim Stoppen, oder wenn ein Befehl etwas ändert?
#   M5  Stehen in den YAML-Dateien Geheimnisse? (Regel aus Korrektur K2)
#   M6  Reißen fehlschlagende Befehle die RCON-Verbindung ab?
#   M7  Auf welchem Port läuft Pl3xMap?
#   M8  Schreibt ein LAUFENDER Server die server.properties neu?
#   M9  ops.json: Lässt sich die Operator-Stufe setzen, und verhält sich die
#       Datei beim Start wie die server.properties? (Fragen aus v1.1/W7 —
#       solange sie unbeantwortet sind, wird an ops.json nichts geschrieben.)
#
# M8 und M9 fehlten bis zum 01.09.2026 in dieser Aufzählung, obwohl M8 im
# Skript längst gemessen wurde. Eine Übersicht, die weniger nennt als das
# Skript tut, schickt den nächsten Leser an der Messung vorbei.
#
# Voraussetzung: Docker mit ARM64-Unterstützung, wie beim Abnahmetest.
#
# Aufruf aus dem Repo-Verzeichnis:
#   ./tests/messung-paper-verhalten.sh
#
# Dauer: etwa fünfzehn Minuten — der Server wird VIERMAL gestartet, weil sich
# "beim Start" und "beim Stoppen" anders nicht auseinanderhalten lassen, und
# M9b denselben Vergleich für ops.json braucht.
#
# Dieses Skript ist eine MESSUNG, kein Test: Es meldet keinen Fehlschlag,
# sondern schreibt auf, was es vorfindet. Was daraus folgt, entscheidet ein
# Mensch.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if ! command -v docker >/dev/null 2>&1; then
  echo "Fehler: docker ist nicht installiert." >&2
  exit 1
fi

if ! docker info >/dev/null 2>&1; then
  echo "Fehler: Der Docker-Dienst läuft nicht." >&2
  echo "Auf dem Mac: Docker Desktop starten." >&2
  exit 1
fi

echo "Messe Paper-Verhalten in einem ARM64-Debian-Container..."
echo "(Das dauert etwa fünfzehn Minuten — der Server startet viermal.)"
echo ""

docker run --rm --platform linux/arm64 \
  -v "$REPO_DIR:/repo:ro" \
  -v "$REPO_DIR/tests/messung-im-container.sh:/messung.sh:ro" \
  --memory=4g \
  debian:trixie-slim bash /messung.sh
