#!/bin/bash
#
# abnahme.sh — Installiert Pi-MCS von null in einer wegwerfbaren Umgebung.
#
# Warum? Damit man vor einer echten Neuinstallation auf dem Pi sehen kann,
# ob das Repository in seinem aktuellen Stand überhaupt einen laufenden
# Server ergibt. Getestet wird in einem ARM64-Debian-Container — also auf
# derselben Prozessorarchitektur wie der Pi 5 und mit denselben Paketen.
#
# Was der Test durchspielt:
#   1. ./install.sh von null
#   2. Ergebnis prüfen (Verzeichnisse, Prüfsumme der paper.jar, Cronjob,
#      logrotate)
#   3. die systemd-Dienstdateien mit systemd-analyze verify
#   4. den Server WIRKLICH starten und auf "Done (...)" warten
#   5. ein Online-Backup anlegen
#   6. sauber stoppen
#   7. ./install.sh ein zweites Mal
#   8. prüfen, dass dabei nichts verloren ging
#
# Voraussetzung: Docker mit ARM64-Unterstützung (auf einem Mac mit
# Apple-Chip von Haus aus, auf dem Pi selbst ebenfalls).
#
# Aufruf aus dem Repo-Verzeichnis:
#   ./tests/abnahme.sh
#
# Dauer: etwa vier Minuten (Paketinstallation, Java, 60 MB PaperMC,
# Welterzeugung). Der Container wird danach restlos verworfen — auf dem
# eigenen Rechner bleibt nichts zurück.
#
# GRENZE DES TESTS: Im Container läuft kein systemd als PID 1. Die Aufrufe
# von systemctl werden protokolliert statt ausgeführt; die Dienstdateien
# selbst prüft dafür systemd-analyze verify. Autostart beim Booten und das
# Verhalten bei einem Absturz lassen sich so nicht nachstellen — das bleibt
# dem echten Pi vorbehalten.

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

echo "Starte Abnahmetest in einem ARM64-Debian-Container..."
echo "(Das dauert etwa vier Minuten.)"
echo ""

# Das Protokoll wird mitgeschrieben, weil der Rueckgabewert allein nicht
# reicht: Die Pruefbloecke im Container laufen als "su ... python3 - <<PYTEST".
# Stirbt einer mit einer Ausnahme, steht der Traceback zwar in der Ausgabe,
# aber der Lauf gilt weiter als bestanden. Genau so waren am 01.09.2026 zwei
# Bloecke ueber zwei Etappen hinweg tot -- und der Test meldete Erfolg.
#
# Die Wache steht hier und nicht in jedem Block: eine Stelle, die alle
# kuenftigen Bloecke mit abdeckt, auch die, an die heute niemand denkt.
PROTOKOLL="$(mktemp)"
trap 'rm -f "$PROTOKOLL"' EXIT

set +e
docker run --rm --platform linux/arm64 \
  -v "$REPO_DIR:/repo:ro" \
  -v "$REPO_DIR/tests/abnahme-im-container.sh:/abnahme.sh:ro" \
  --memory=4g \
  debian:trixie-slim bash /abnahme.sh | tee "$PROTOKOLL"
RUECKGABE=${PIPESTATUS[0]}
set -e

if grep -q 'Traceback (most recent call last)' "$PROTOKOLL"; then
  echo "" >&2
  echo "FEHLGESCHLAGEN: Im Protokoll steht ein Traceback." >&2
  echo "Ein Pruefblock ist mit einer Ausnahme gestorben und hat damit NICHTS" >&2
  echo "geprueft — unabhaengig davon, was der Lauf sonst gemeldet hat." >&2
  exit 1
fi

# Zweite Wache, nach demselben Gedanken wie die erste (22.09.2026).
#
# Der Container schreibt seine Inhaltspruefungen als TEXT: "zweiter Lauf
# aendert nichts: NEIN - FEHLER", "Passwort im Klartext ausgeliefert: JA -
# FEHLER" und rund zwei Dutzend weitere. Keine davon hat den Rueckgabewert
# je beeinflusst — sie fielen nur auf, wenn jemand das Protokoll las.
#
# Am 21.09.2026 kam mit FEHLER_GEFUNDEN ein Weg dazu, an einer
# Inhaltspruefung zu scheitern; benutzt hat ihn aber nur die neu
# hinzugekommene Pruefung. Die vorhandenen blieben Zierde. Diese Wache
# deckt sie alle ab, auch die, an die heute niemand denkt — und sie steht
# an EINER Stelle, damit die naechste Pruefung nicht wieder daran denken
# muss.
#
# Beim Einbau gegen einen gruenen Lauf gegengeprueft: null Treffer.
if grep -qE 'NEIN - FEHLER|DOCH - FEHLER|FEHLT - FEHLER|JA - FEHLER|NICHT erkannt - FEHLER|FEHLER - |^ *FEHLER[: ]' "$PROTOKOLL"; then
  echo "" >&2
  echo "FEHLGESCHLAGEN: Eine Inhaltspruefung im Protokoll meldet einen Befund." >&2
  echo "" >&2
  grep -nE 'NEIN - FEHLER|DOCH - FEHLER|FEHLT - FEHLER|JA - FEHLER|NICHT erkannt - FEHLER|FEHLER - |^ *FEHLER[: ]' \
    "$PROTOKOLL" | sed 's/^/  /' >&2
  exit 1
fi

# Dritte Wache (23.09.2026): die rund fuenfzig Zeilen "Wert (muss X sein)".
# Die zweite sucht nur das Wort FEHLER, und das steht in diesen Zeilen
# nicht — "Treffer in mcs.conf: 1 (muss 0 sein)" blieb gruen. Die
# Auswertung steht in einer eigenen Datei, damit sie ohne Container
# pruefbar ist; was sie nicht vergleichen kann, gibt sie aus statt es
# durchzuwinken.
echo ""
if ! python3 "$REPO_DIR/tests/muss-zeilen.py" "$PROTOKOLL"; then
  echo "" >&2
  echo "FEHLGESCHLAGEN: Mindestens ein Wert weicht von seinem \"muss\" ab." >&2
  exit 1
fi

exit "$RUECKGABE"
