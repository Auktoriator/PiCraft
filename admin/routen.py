#!/usr/bin/env python3
"""
routen.py — Die JSON-Schnittstellen der Weboberflaeche.

Hier steht ausschliesslich, welcher Pfad welche Funktion aufruft und was
zurueckkommt. Gerechnet wird nichts: Die Werte holen sich die Routen aus
status.py, system.py, protokoll.py und konsole.py.

Seit Etappe C (28.08.2026) stehen die SEITEN nicht mehr hier, sondern je
Seite in einem eigenen Modul "seite_<name>.py". Was hier bleibt, sind die
Pfade unter /api/ — sie liefern JSON und keine Oberflaeche:

    /api/status              das komplette Statusbild
    /api/verlauf             Messwerte fuer die Kurven (uPlot braucht JSON)
    /api/logs/<typ>          Protokollansichten
    /api/console             an den Server senden
    /api/action/<name>       Start, Stop, Backup, Update

Sie bleiben erhalten, weil sich damit auch von aussen etwas abfragen laesst
(ein eigenes Skript, ein Statusanzeiger im Netzwerk) und weil die
Verlaufskurven ohnehin JSON brauchen. Die Oberflaeche selbst benutzt
daneben Endpunkte, die HTML-Stuecke liefern — HTMX schreibt die Antwort
unveraendert in die Seite, und dafuer ist HTML das richtige Format.

Bis zum 2026-08-31 stand hier auch "/api/server-properties" zum Lesen und
Schreiben. Der Endpunkt stammte aus der Zeit vor Etappe C und war seither von
keiner Seite mehr benutzt — aber weiterhin erreichbar, und er schrieb an allem
vorbei, was konfig.py fuer dieselbe Datei tut: ohne muss_vorgemerkt_werden()
(Paper haette die Aenderung bei laufendem Server lautlos verworfen, Korrektur
K3), ohne pruefen() (eine Zeile ohne "=" liess sich speichern, danach startete
Paper nicht mehr) und ohne vormerkung_verwerfen() (eine liegengebliebene
Vormerkung ueberschrieb den Schreibvorgang beim naechsten Start wieder).

Ersatzlos entfernt, samt der eigenen Geheimnis-Behandlung, die er mitbrachte:
Die Konfigurationsseite kann all das besser, und die maszgebliche Liste der
geheimen Schluessel steht seit Etappe C je Datei in konfig.py (DATEIEN ->
"geheim"). Zwei Listen waeren eine zu viel.

Warum ein "Blueprint" und nicht direkt das Flask-Objekt? Weil app.py die
Routen einbinden muss und die Routen sonst app.py kennen muessten — ein
Ring, den Python beim Importieren nicht aufloesen kann. Ein Blueprint ist
eine Sammlung von Routen ohne eigene Anwendung; app.py haengt sie ein.
"""

from flask import Blueprint, jsonify, request

from einstellungen import MCS_SERVICE, MINECRAFT_LOG, PLAYER_ACTIVITY_LOG
from konsole import (action_command, sanitize_console_input,
                     send_to_minecraft_console)
from protokoll import activity_lines, chat_lines, error_lines
from sicherheit import auth_required, nur_eigene_oberflaeche
from status import current_status
from system import (read_last_lines, run_background, run_command,
                    service_state)

try:
    import metrik
except ImportError:  # pragma: no cover
    metrik = None

seiten = Blueprint("seiten", __name__)


# ----------------------------------------------------------------------------
# Statuswerte
# ----------------------------------------------------------------------------
@seiten.get("/api/status")
@auth_required
def api_status():
    """Alle Statuswerte als JSON (wird alle 5 Sekunden abgefragt)."""
    return jsonify(current_status())


@seiten.get("/api/verlauf")
@auth_required
def api_verlauf():
    """Messwerte der letzten Stunden — Grundlage der Kurven in der Oberflaeche."""
    if metrik is None:
        return jsonify({"error": "Verlaufsdaten sind nicht eingerichtet.",
                        "punkte": []}), 503
    try:
        stunden = float(request.args.get("stunden", "24"))
    except ValueError:
        stunden = 24.0
    # Nach oben begrenzen: Aufbewahrt werden ohnehin nur sieben Tage, und
    # eine unbegrenzte Zahl aus der Adresszeile soll keine Abfrage ueber die
    # ganze Datenbank ausloesen koennen.
    stunden = max(0.016, min(stunden, 24.0 * 7))
    return jsonify({"stunden": stunden, "punkte": metrik.verlauf(stunden=stunden)})


@seiten.get("/api/logs/<log_type>")
@auth_required
def api_logs(log_type):
    """Liefert die gewünschte Log-Ansicht als Liste von Zeilen."""
    if log_type == "errors":
        lines = error_lines(max_lines=200)
    elif log_type == "activity":
        lines = activity_lines(max_lines=300)
        if not lines:
            # Falls das aktuelle Log leer ist (z. B. direkt nach einem
            # Neustart): das dauerhafte Aktivitätslog anzeigen.
            lines = read_last_lines(PLAYER_ACTIVITY_LOG, max_lines=200)
    elif log_type == "chat":
        lines = chat_lines(max_lines=200)
    elif log_type == "service":
        _, out, err = run_command(["journalctl", "-u", MCS_SERVICE, "-n", "200", "--no-pager"], timeout=10)
        text = out if out else err
        lines = text.splitlines()
    elif log_type == "latest":
        lines = read_last_lines(MINECRAFT_LOG, max_lines=200)
    else:
        return jsonify({"error": "Unbekannter Log-Typ"}), 400
    return jsonify({"log_type": log_type, "lines": lines})


@seiten.post("/api/console")
@auth_required
@nur_eigene_oberflaeche
def api_console():
    """Chat-Nachricht oder Minecraft-Befehl an die Server-Konsole senden."""
    payload = request.get_json(silent=True) or {}
    mode = (payload.get("mode") or "").strip().lower()
    message = sanitize_console_input(payload.get("message"))

    if mode not in {"chat", "command"}:
        return jsonify({"error": "mode muss 'chat' oder 'command' sein"}), 400
    if not message:
        return jsonify({"error": "Nachricht ist leer"}), 400
    if service_state() != "active":
        return jsonify({"error": "Der Minecraft-Server läuft gerade nicht"}), 409

    if mode == "chat":
        # Chat-Nachrichten bekommen ein [WEB]-Präfix, damit die Spieler
        # sehen, dass sie aus der Weboberfläche kommen.
        line = f"say [WEB] {message}"
    else:
        line = message if message.startswith("/") else f"/{message}"

    ok, detail = send_to_minecraft_console(line)
    if not ok:
        return jsonify({"ok": False, "error": detail}), 500

    return jsonify({"ok": True, "mode": mode, "sent": line})


@seiten.post("/api/action/<action_name>")
@auth_required
@nur_eigene_oberflaeche
def api_action(action_name):
    """Eine der erlaubten Aktionen ausführen (Start, Stop, Backup, ...)."""
    action = action_command(action_name)
    if action is None:
        return jsonify({"error": "Aktion unbekannt oder nicht erlaubt"}), 400

    if action["mode"] == "background":
        pid = run_background(action["cmd"], action_name, cwd=action.get("cwd"))
        return jsonify({"ok": True, "started": True, "pid": pid, "action": action_name})

    code, out, err = run_command(action["cmd"], timeout=action.get("timeout", 180),
                                 cwd=action.get("cwd"),
                                 protokoll=action_name if action.get("protokoll") else None)
    return jsonify(
        {
            "ok": code == 0,
            "action": action_name,
            "returncode": code,
            "stdout": out,
            "stderr": err,
        }
    )

