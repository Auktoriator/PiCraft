#!/usr/bin/env python3
"""
seite_karte.py — Die Weltkarte (Pl3xMap) im Rahmen.

Pl3xMap bringt seinen eigenen Webserver mit. Diese Seite bettet ihn als
iframe ein und bietet daneben den Link zum Aufmachen in einem eigenen Tab.
Das ueberlebt jedes Pl3xMap-Update; ein Reverse-Proxy waere ein Bauteil mehr
fuer kaum Gewinn (Lastenheft 5.7.4, Punkt 7).

DER PORT WIRD GELESEN, NICHT GERATEN
------------------------------------
Er steht in `plugins/Pl3xMap/config.yml` unter `internal-webserver.port`.
Am 28.08.2026 im Container nachgesehen: standardmaessig 8080 -- dieselbe
Zahl, die auch die Weboberflaeche haette, weshalb `install-admin.sh` fuer
sie auf 8081 ausweicht (Befund B6). Wer den Kartenport verschoben hat, soll
hier trotzdem die richtige Karte sehen.

DIE FALLE MIT DEN GEMISCHTEN INHALTEN
-------------------------------------
Wird die Oberflaeche ueber Tailscale mit HTTPS aufgerufen, blockiert der
Browser einen iframe, der auf `http://` zeigt -- ohne Fehlermeldung, es
bleibt schlicht ein weisser Kasten. Deshalb entscheidet erst der Browser,
ob der Rahmen ueberhaupt gebaut wird: Er allein weiss, wie er die Seite
geladen hat. Passt es nicht, steht dort ein Hinweis und der direkte Link.
"""

import os
import re
import socket
from pathlib import Path

from flask import Blueprint, render_template

from einstellungen import MCS_SERVER_DIR
from sicherheit import auth_required

karte = Blueprint("karte", __name__)

KONFIG = f"{MCS_SERVER_DIR}/plugins/Pl3xMap/config.yml"


# Adressen, unter denen der Kartenserver nur vom Pi selbst zu erreichen ist.
NUR_LOKAL = {"127.0.0.1", "localhost", "::1", "0:0:0:0:0:0:0:1"}


def kartenport():
    """Port, Bindeadresse und Zustand des eingebauten Webservers von Pl3xMap.

    Gelesen wird mit einem schlichten Zeilenleser statt mit einem
    YAML-Parser: Gebraucht werden drei Werte aus einem bekannten Abschnitt,
    und so funktioniert es auch, wenn python3-yaml fehlt.

    `bind` wird seit dem 2026-08-29 mitgelesen. Ohne diesen Wert baute die
    Seite die Kartenadresse blind aus dem Namen, unter dem der Browser die
    Oberflaeche erreicht, plus diesem Port. Steht Pl3xMap aber auf
    `bind: 127.0.0.1` -- der uebliche Fall, sobald ein Reverse-Proxy davor
    haengt --, ist der Port von jedem anderen Geraet aus zu. Der Rahmen blieb
    dann leer und der Knopf "In neuem Tab oeffnen" fuehrte ins Nichts,
    ausgerechnet mit dem Hinweistext "dort funktioniert sie".
    """
    pfad = Path(KONFIG)
    leer = {"installiert": False, "port": None, "an": False, "nur_lokal": False,
            "web_adresse": ""}
    if not pfad.is_file():
        return leer

    im_abschnitt = False
    abschnitt_tiefe = 0
    port, an, bind = None, None, None
    web_adresse = ""
    try:
        for zeile in pfad.read_text(encoding="utf-8", errors="ignore").splitlines():
            tiefe = len(zeile) - len(zeile.lstrip(" \t"))
            # Die Adresse, unter der Pl3xMap sich selbst im Internet verortet.
            # Sie steht ausserhalb des internal-webserver-Abschnitts und ist
            # der EINZIGE Ort, an dem die oeffentliche Adresse ueberhaupt
            # aufgeschrieben ist — die Oberflaeche soll sie nicht raten und
            # auch nicht ein zweites Mal in mcs.conf gepflegt bekommen.
            treffer = re.match(r"""^\s*web-address:\s*['"]?([^'"\s]+)['"]?\s*$""",
                               zeile)
            if treffer and not im_abschnitt:
                web_adresse = treffer.group(1).rstrip("/")
                continue
            if re.match(r"^\s*internal-webserver:\s*$", zeile):
                im_abschnitt = True
                abschnitt_tiefe = tiefe
                continue
            if im_abschnitt:
                # Der Abschnitt endet bei der naechsten Zeile, die nicht
                # tiefer eingerueckt ist als "internal-webserver:" selbst.
                # Bis zum 21.10.2026 endete er erst an einer Zeile ganz
                # links — der Abschnitt steht aber eingerueckt unter
                # "settings:", und so las die Schleife in "performance:"
                # weiter: Das "enabled: true" von live-update ueberschrieb
                # den Schalter des Webservers. Ein abgeschalteter
                # Kartenserver hiesse hier "an".
                if (zeile.strip() and not zeile.lstrip().startswith("#")
                        and tiefe <= abschnitt_tiefe):
                    break
                treffer = re.match(r"^\s*port:\s*(\d+)\s*$", zeile)
                if treffer:
                    port = int(treffer.group(1))
                treffer = re.match(r"^\s*enabled:\s*(\w+)\s*$", zeile)
                if treffer:
                    an = treffer.group(1).lower() == "true"
                treffer = re.match(r"""^\s*bind:\s*['"]?([^'"\s]+)['"]?\s*$""", zeile)
                if treffer:
                    bind = treffer.group(1)
    except OSError:
        return leer

    return {"installiert": True, "port": port or 8080,
            "an": True if an is None else an,
            "bind": bind or "",
            "nur_lokal": bind in NUR_LOKAL if bind else False,
            "web_adresse": web_adresse}


def kartenserver_antwortet(port, bind):
    """Ob auf dem Kartenport ueberhaupt jemand annimmt — vom Pi selbst gefragt.

    Seit dem 21.10.2026. Vom 14. bis zum 21.10. stand Pl3xMap nach einem
    Update auf seinen Vorgaben, Port 8080 — dem Port DIESER Oberflaeche.
    Der Kartenserver kam gar nicht erst hoch (BindException), die Seite
    bettete sich selbst in den Rahmen ein, die oeffentliche Karte lieferte
    502, und nichts davon wurde gemeldet.

    Ein Verbindungsversuch auf dem eigenen Rechner kostet unter einer
    Millisekunde. Er sagt, ob dort etwas lauscht — ob die Karte von AUSSEN
    erreichbar ist, sagt er bewusst nicht (CLAUDE.md, Sicherheit).
    """
    ziel = bind if bind and bind not in ("0.0.0.0", "::", "*") else "127.0.0.1"
    try:
        with socket.create_connection((ziel, port), timeout=0.5):
            return True
    except OSError:
        return False


@karte.get("/karte")
@auth_required
def index():
    angaben = kartenport()
    if angaben["installiert"] and angaben["an"]:
        # Dieselbe Vorgabe wie app.py, damit beide denselben Port meinen.
        eigener = int(os.getenv("MCS_ADMIN_PORT", "8080"))
        angaben["eigener_port"] = angaben["port"] == eigener
        angaben["antwortet"] = (not angaben["eigener_port"]
                                and kartenserver_antwortet(angaben["port"],
                                                           angaben["bind"]))
    return render_template("karte.html", karte=angaben)
