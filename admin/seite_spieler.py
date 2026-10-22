#!/usr/bin/env python3
"""
seite_spieler.py — Wer war hier, und was darf er.

Die Seite zeigt jeden, der je auf dem Server war, und laesst Rechte,
Whitelist und Sperren aendern. Die Angaben holt spieler.py aus den Dateien,
die Paper selbst schreibt; geaendert wird ueber RCON.

Warum eine Liste und keine Kacheln: Bei fuenf bis zehn Spielern will man
vergleichen ("wer war zuletzt da?", "wer ist Operator?"), und dafuer ist
eine Tabelle das richtige Werkzeug. Auf dem Telefon wird daraus eine
Kartenliste -- dieselben Angaben, untereinander.
"""

from flask import Blueprint, render_template, request

import rcon
import spieler as spielerdaten
from sicherheit import auth_required, nur_eigene_oberflaeche
from status import muster_befund, protokoll_befund
from system import service_state

spieler = Blueprint("spieler", __name__)


def _seitendaten():
    liste = spielerdaten.alle()
    return {
        "spieler": liste,
        "zahlen": spielerdaten.zaehlung(liste),
        "whitelist_aktiv": spielerdaten.whitelist_aktiv(),
        # Aendern geht nur bei laufendem Server: Minecraft haelt Whitelist,
        # Rechte und Sperren im Arbeitsspeicher und schreibt die Dateien
        # selbst. Eine Aenderung an der Datei waere beim naechsten
        # Schreiben lautlos wieder weg -- dieselbe Falle wie bei der
        # server.properties (Korrektur K3).
        "aenderbar": service_state() == "active" and rcon.verfuegbar(),
        "server_laeuft": service_state() == "active",
        "rcon_da": rcon.verfuegbar(),
        # Genau andersherum als alles darueber, und das ist kein Versehen:
        # ops.json wird beim START gelesen und ueberlebt ihn, bei laufendem
        # Server dagegen aus dem Arbeitsspeicher ueberschrieben (M9,
        # 01.09.2026). Die Stufe ist deshalb die einzige Aenderung dieser
        # Seite, die einen STEHENDEN Server braucht.
        "stufe_aenderbar": service_state() != "active",
        # Fehlt dem Spielerprotokoll die Vergangenheit, steht in der Spalte
        # "zuletzt gesehen" fuer jeden Spieler "nicht aufgezeichnet" -- und
        # das sieht aus wie eine Aussage, ist aber eine Luecke. Genau hier
        # hat der Fehler vom September zwei Wochen lang still gestanden,
        # also gehoert der Hinweis auch genau hierhin und nicht nur in eine
        # Statusantwort, die niemand liest.
        #
        # Ueber status.protokoll_befund() und nicht direkt ueber
        # protokollpruefung: Der Befund ist dort lange zwischengespeichert,
        # und ein zweiter Weg zur selben Frage ist in diesem Projekt
        # mehrfach die Fehlerquelle gewesen.
        "protokoll_befund": protokoll_befund(),
        # Und hier steht „niemand online“, wenn die Muster die Beitritte
        # nicht mehr erkennen (Paper 26.3, 14.–21.10.2026).
        "muster_befund": muster_befund(),
    }


@spieler.get("/spieler")
@auth_required
def index():
    return render_template("spieler.html", **_seitendaten())


@spieler.get("/teil/spielerliste")
@auth_required
def teil_liste():
    return render_template("teile/spielerliste.html", meldung=None, **_seitendaten())


@spieler.post("/spieler/aktion")
@auth_required
@nur_eigene_oberflaeche
def aktion():
    """Eine Aktion ausführen und die Liste frisch zurückgeben.

    Antwort ist die ganze Liste und nicht nur eine Meldung: Nach einem
    „op" muss die Zeile daneben sofort anders aussehen. Zwei Dinge
    getrennt zu aktualisieren hiesse, dass sie kurz auseinanderlaufen —
    und genau in diesem Moment schaut jemand hin.
    """
    art, text = spielerdaten.aktion(
        (request.form.get("name") or "").strip(),
        (request.form.get("was") or "").strip(),
        request.form.get("grund") or "",
        request.form.get("stufe"))

    return render_template("teile/spielerliste.html",
                           meldung=(art, text), **_seitendaten())
