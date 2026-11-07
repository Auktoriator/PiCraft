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
import secrets
import socket
from pathlib import Path

from flask import Blueprint, make_response, render_template

from einstellungen import MCS_DIR, MCS_SERVER_DIR, kv_lesen
from sicherheit import auth_required, nur_eigene_oberflaeche
from system import run_command

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


# ----------------------------------------------------------------------------
# Das Kartentor (seit 1.6)
# ----------------------------------------------------------------------------
# Das Tor selbst ist ein eigener Dienst (kartentor/kartentor.py) und laeuft
# getrennt von dieser Oberflaeche, weil es am Internet steht und sie nicht.
# Hier steht nur, was der Betreiber davon sieht: ob es laeuft, ob nginx es
# ueberhaupt fragt, und das Passwort zum Weitergeben.
KARTENTOR_ORDNER = f"{MCS_DIR}/kartentor"
KARTENTOR_ZUGANG = f"{KARTENTOR_ORDNER}/zugang.env"
KARTENTOR_DIENST = "mcs-kartentor.service"

# Ohne 0, O, 1, l und i: Das Passwort geht im Discord herum und wird auf
# Handys abgetippt. 16 Zeichen aus 31 sind knapp 80 Bit; bei fuenf Versuchen
# je Viertelstunde ist Durchprobieren damit aussichtslos.
_PASSWORTZEICHEN = "abcdefghjkmnpqrstuvwxyz23456789"


def _nginx_fragt_das_tor():
    """Ob eine nginx-Konfiguration das Tor fragt: True, False oder None
    (nicht feststellbar, etwa ohne nginx).

    Das ist der stille Ausfall, gegen den diese Zeile steht: Das Tor laeuft,
    die Seite sagt "laeuft", aber nginx fragt es nie — und die Karte ist so
    offen wie vorher. Gelesen wird die Konfiguration, nicht das Netz: Ob die
    Karte von aussen wirklich zu ist, laesst sich vom Pi selbst nicht pruefen
    (CLAUDE.md, Sicherheit). Das sagt die Seite auch.
    """
    gefunden = None
    for ordner in ("/etc/nginx/sites-enabled", "/etc/nginx/conf.d"):
        if not os.path.isdir(ordner):
            continue
        gefunden = gefunden or False
        try:
            for name in sorted(os.listdir(ordner)):
                text = Path(ordner, name).read_text(encoding="utf-8", errors="ignore")
                if re.search(r"^\s*auth_request\s+/kartentor/pruefen\s*;", text, re.M):
                    return True
        except OSError:
            return None
    return gefunden


def kartentor_zustand():
    """Alles nur gelesen. Ein systemctl-Aufruf je Seitenaufruf, nicht je Sekunde."""
    _, aktiv, _ = run_command(["systemctl", "is-active", KARTENTOR_DIENST], timeout=5)
    return {
        "ausgerollt": os.path.isfile(f"{KARTENTOR_ORDNER}/kartentor.py"),
        "aktiv": aktiv == "active",
        "nginx": _nginx_fragt_das_tor(),
        "passwort": kv_lesen(KARTENTOR_ZUGANG).get("KARTENTOR_PASSWORT", ""),
        "dienst": KARTENTOR_DIENST,
    }


def kartentor_passwort_erzeugen():
    """Schreibt ein neues Passwort samt neuem Schluessel.

    Erzeugt, nicht gewaehlt: Ein gemeinsames Passwort, das im Discord
    herumgeht, ist das erste, das jemand ausprobiert, wenn es sich jemand
    ausgedacht hat. Ein neuer Schluessel dazu, weil "neues Passwort" hier
    "alle raus" heissen soll — wer drin bleiben darf, bekommt es neu.
    """
    if not os.path.isdir(KARTENTOR_ORDNER):
        return "fehler", (f"{KARTENTOR_ORDNER} fehlt. Einmal „./deploy.sh“ im "
                          "Repository laufen lassen.")
    import konfig
    passwort = "-".join("".join(secrets.choice(_PASSWORTZEICHEN) for _ in range(4))
                        for _ in range(4))
    try:
        # Rechte schon beim Anlegen, nicht danach (CLAUDE.md, Sicherheit).
        konfig._schreiben(KARTENTOR_ZUGANG,
                          "# Zugang zum Kartentor. Geschrieben von der Weboberflaeche\n"
                          "# (Karte -> Kartentor). Gehoert dem Pi, nicht dem Repository.\n"
                          f"KARTENTOR_PASSWORT={passwort}\n"
                          f"KARTENTOR_SCHLUESSEL={secrets.token_hex(32)}\n", 0o600)
    except OSError as fehler:
        return "fehler", f"{KARTENTOR_ZUGANG} ließ sich nicht schreiben: {fehler}"
    return "gut", ("Neues Passwort erzeugt. Wer angemeldet war, muss sich neu "
                   "anmelden. Das Tor liest es bei der nächsten Anfrage, ein "
                   "Neustart ist nicht nötig.")


def _ohne_zwischenspeicher(html):
    # Die Seite enthaelt das Passwort der Karte. Es soll in keinem
    # Browser-Cache liegen bleiben, auch nicht nach dem Abmelden.
    antwort = make_response(html)
    antwort.headers["Cache-Control"] = "no-store"
    return antwort


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
    return _ohne_zwischenspeicher(render_template(
        "karte.html", karte=angaben, tor=kartentor_zustand(), meldung=None))


@karte.post("/karte/kartentor/passwort")
@auth_required
@nur_eigene_oberflaeche
def kartentor_passwort():
    meldung = kartentor_passwort_erzeugen()
    return _ohne_zwischenspeicher(render_template(
        "teile/kartentor.html", tor=kartentor_zustand(), meldung=meldung))
