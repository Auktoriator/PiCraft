#!/usr/bin/env python3
"""
kartentor.py — Die Anmeldung vor der oeffentlichen Weltkarte.

Pl3xMap zeigt jedem, der die Adresse kennt, live, wer gerade spielt, wo er
steht und wo gebaut wurde. Das Kartentor laesst nur hinein, wer einen Namen
von der Whitelist UND das gemeinsame Passwort kennt.

So greift es ein: nginx fragt vor JEDER Anfrage an die Karte bei
/kartentor/pruefen nach (auth_request). 204 heisst durchlassen, 401 heisst
zur Anmeldeseite. Die Karte selbst fliesst nie durch diesen Prozess, er
sieht nur die Frage "darf der?".

WARUM EIN EIGENER DIENST UND NICHT DIE WEBOBERFLAECHE
-----------------------------------------------------
Die Oberflaeche ist so maechtig wie ein SSH-Zugang und darf nie ins
Internet. Haengte die Anmeldung der Karte an ihr, stuende ihr Prozess mit
allen Endpunkten am Internet. Dieser hier kennt drei Wege, laeuft in einer
engen Sandbox (mcs-kartentor.service) und sieht die Zugangsdaten der
Oberflaeche nicht einmal.

WAS DER NAME TAUGT — UND WAS NICHT
----------------------------------
Der Name ist kein Geheimnis: Er steht in der Serverliste, auf der Karte, im
Discord. Die Sicherheit liegt im Passwort und in der Bremse weiter unten.
Die Whitelist hat einen anderen Zweck: Wer von ihr gestrichen wird,
verliert damit auch die Karte, und zwar bei der naechsten Anfrage, nicht
erst nach dreissig Tagen. Deshalb wird sie bei JEDER Pruefung gefragt,
nicht nur beim Anmelden.

Gelesen werden zwei Dateien, bei jeder Anfrage:
  zugang.env       Passwort und Schluessel. Schreibt die Weboberflaeche
                   (Karte -> Kartentor); die Datei gehoert dem Pi.
  whitelist.json   schreibt Paper.
Ein neues Passwort wirkt damit ohne Neustart dieses Dienstes.
"""

import hashlib
import hmac
import ipaddress
import json
import os
import re
import threading
import time

from flask import Flask, redirect, render_template, request
from itsdangerous import BadSignature, URLSafeTimedSerializer

ORDNER = os.path.dirname(os.path.abspath(__file__))
ZUGANG = os.getenv("KARTENTOR_ZUGANG", os.path.join(ORDNER, "zugang.env"))
WHITELIST = os.path.join(os.getenv("MCS_SERVER_DIR", os.path.expanduser("~/mcs/mc_server")),
                         "whitelist.json")
PORT = int(os.getenv("KARTENTOR_PORT", "8095"))

COOKIE = "kartentor"
GUELTIG = 30 * 24 * 3600      # wie die Weboberflaeche, und aus demselben Grund
NAME_MUSTER = re.compile(r"[A-Za-z0-9_]{3,16}")   # so sehen Minecraft-Namen aus

app = Flask(__name__, template_folder=ORDNER)


# ----------------------------------------------------------------------------
# Die beiden Dateien
# ----------------------------------------------------------------------------
# Beide werden bei JEDER Anfrage gelesen, ohne Zwischenspeicher. Sie sind
# winzig (eine Handvoll Zeilen); das Lesen ist klein neben dem, was Flask je
# Anfrage ohnehin tut. Ob das auf dem Pi stimmt, misst K-P5 in
# PRUEFEN-AUF-DEM-PI.md. Ein Zwischenspeicher nach Aenderungszeit haette
# dagegen eine Luecke: Auf vielen Dateisystemen springt diese Zeit nur im
# Takt des Kernels, zwei Schreibvorgaenge gleicher Groesse darin saehen
# gleich aus — und das Tor liesse jemanden hinein, den die Whitelist gerade
# gestrichen hat.
def zugang():
    """Passwort und Schluessel aus zugang.env. Fehlt die Datei: leer."""
    werte = {}
    try:
        with open(ZUGANG, encoding="utf-8") as datei:
            for zeile in datei:
                zeile = zeile.strip()
                if zeile and not zeile.startswith("#") and "=" in zeile:
                    schluessel, wert = zeile.split("=", 1)
                    werte[schluessel.strip()] = wert.strip().strip("'\"")
    except OSError:
        return {}
    return werte


def eingerichtet(werte):
    return bool(werte.get("KARTENTOR_PASSWORT") and werte.get("KARTENTOR_SCHLUESSEL"))


def whitelist_namen():
    """Die Namen auf der Whitelist, klein geschrieben, oder None, wenn sie
    sich nicht lesen laesst. None heisst: niemand kommt hinein."""
    try:
        with open(WHITELIST, encoding="utf-8") as datei:
            eintraege = json.load(datei)
        return frozenset(e["name"].lower() for e in eintraege
                         if isinstance(e, dict) and isinstance(e.get("name"), str))
    except (OSError, ValueError, TypeError):
        # Liest man, waehrend Paper schreibt, ist das JSON halb. Dann ist diese
        # eine Anfrage abgewiesen; die naechste findet die fertige Datei.
        return None


# ----------------------------------------------------------------------------
# Das Cookie
# ----------------------------------------------------------------------------
# Unterschrieben, nicht verschluesselt. Darin stehen der Name und eine Marke
# des Passworts: Ein neues Passwort macht jedes alte Cookie ungueltig, auch
# wenn jemand nur das Passwort von Hand aendert und den Schluessel stehen
# laesst. HMAC statt eines blossen Hashes, weil sich ein Hash des Passworts
# im Cookie offline durchprobieren liesse (dieselbe Ueberlegung wie
# _passwort_marke in admin/sicherheit.py).
def _marke(werte):
    return hmac.new(werte["KARTENTOR_SCHLUESSEL"].encode("utf-8"),
                    werte["KARTENTOR_PASSWORT"].encode("utf-8"),
                    hashlib.sha256).hexdigest()


def _siegel(werte):
    return URLSafeTimedSerializer(werte["KARTENTOR_SCHLUESSEL"], salt="kartentor")


def angemeldeter_name():
    """Der Name aus einem gueltigen Cookie, oder None."""
    werte = zugang()
    wert = request.cookies.get(COOKIE)
    if not wert or not eingerichtet(werte):
        return None
    try:
        inhalt = _siegel(werte).loads(wert, max_age=GUELTIG)
    except BadSignature:            # auch abgelaufen (SignatureExpired)
        return None
    if not isinstance(inhalt, dict):
        return None
    name, marke = inhalt.get("name"), inhalt.get("marke")
    if not isinstance(name, str) or not isinstance(marke, str):
        return None
    # Bytes, nicht str: compare_digest verweigert str mit Nicht-ASCII, und
    # das Cookie kommt von aussen (CLAUDE.md).
    if not hmac.compare_digest(marke.encode("utf-8"), _marke(werte).encode("utf-8")):
        return None
    namen = whitelist_namen()
    if namen is None or name.lower() not in namen:
        return None
    return name


# ----------------------------------------------------------------------------
# Die Bremse
# ----------------------------------------------------------------------------
# Dieselbe Regel wie fuer die Weboberflaeche (admin/sicherheit.py): fuenf
# Fehlversuche in fuenfzehn Minuten, dann fuenf Minuten Pause. Eine eigene
# Fassung, weil dieser Dienst den Ordner der Oberflaeche gar nicht sieht.
#
# Gezaehlt wird je Adresse, nie je Name. Eine Sperre je Name koennte jeder
# ausloesen: fuenfmal den Namen eines Mitspielers mit falschem Passwort, und
# der kommt nicht mehr auf die Karte.
#
# X-Real-IP wird hier GEGLAUBT — anders als in der Weboberflaeche, die den
# Kopf mit Absicht ignoriert. Der Unterschied: Dieser Dienst lauscht fest auf
# 127.0.0.1 (ganz unten), also fragt ihn nur, wer schon auf dem Pi ist, und
# das ist nginx. Wer das aendert, macht aus der Bremse eine, die sich jeder
# mit einer erfundenen Adresse wegschreibt.
VERSUCHE_ERLAUBT = 5
MERKDAUER = 15 * 60
SPERRE = 5 * 60

_versuche = {}            # Absender -> Zeitpunkte der Fehlversuche
_versuche_sperre = threading.Lock()


def _absender():
    """Die Adresse, unter der gezaehlt wird. Bei IPv6 das /64-Netz: Ein
    Anschluss hat davon Trillionen Adressen, und jede waere sonst ein neuer
    Anlauf mit fuenf frischen Versuchen."""
    adresse = request.headers.get("X-Real-IP") or request.remote_addr or "unbekannt"
    try:
        ip = ipaddress.ip_address(adresse)
    except ValueError:
        return adresse
    if ip.version == 6:
        return str(ipaddress.ip_network(f"{ip}/64", strict=False))
    return str(ip)


def gesperrt_fuer(absender):
    """Wie lange dieser Absender noch warten muss (Sekunden, 0 = frei)."""
    jetzt = time.monotonic()
    with _versuche_sperre:
        zeiten = [z for z in _versuche.get(absender, []) if jetzt - z < MERKDAUER]
        if zeiten:
            _versuche[absender] = zeiten
        else:
            _versuche.pop(absender, None)
        if len(zeiten) < VERSUCHE_ERLAUBT:
            return 0
        return max(0, int(SPERRE - (jetzt - zeiten[-1])))


def fehlversuch_merken(absender):
    jetzt = time.monotonic()
    with _versuche_sperre:
        # Am Internet kann jemand aus sehr vielen Netzen anklopfen. Ohne
        # Aufraeumen wuechse die Liste, bis MemoryMax den Dienst beendet.
        if len(_versuche) > 10000:
            for alt in [a for a, z in _versuche.items() if jetzt - z[-1] >= MERKDAUER]:
                del _versuche[alt]
        _versuche.setdefault(absender, []).append(jetzt)


def versuche_vergessen(absender):
    with _versuche_sperre:
        _versuche.pop(absender, None)


# ----------------------------------------------------------------------------
# Die drei Wege
# ----------------------------------------------------------------------------
@app.get("/kartentor/pruefen")
def pruefen():
    """Die Frage, die nginx vor jeder Anfrage an die Karte stellt."""
    return ("", 204) if angemeldeter_name() else ("", 401)


@app.route("/kartentor/anmelden", methods=["GET", "POST"])
def anmelden():
    werte = zugang()
    namen = whitelist_namen()
    name = (request.form.get("name") or "").strip()
    meldung, status = "", 200

    # Im Zweifel zu, und sagen, warum. Eine Anmeldeseite, die jedes Passwort
    # ablehnt, ohne zu sagen, dass gar keins eingerichtet ist, schickt die
    # Mitspieler zum Betreiber mit der falschen Frage.
    if not eingerichtet(werte):
        meldung, status = ("Das Kartentor ist noch nicht eingerichtet. Der Betreiber "
                           "erzeugt das Passwort in der Weboberfläche unter Karte."), 503
    elif namen is None:
        meldung, status = ("Die Whitelist des Servers lässt sich gerade nicht lesen. "
                           "Bitte in ein paar Minuten noch einmal versuchen."), 503
    elif request.method == "POST":
        absender = _absender()
        rest = gesperrt_fuer(absender)
        passwort = (request.form.get("passwort") or "").strip()
        if rest:
            meldung = (f"Zu viele Fehlversuche. Bitte {rest // 60 + 1} Minuten "
                       "warten und es dann noch einmal versuchen.")
        elif (NAME_MUSTER.fullmatch(name) and name.lower() in namen
              and hmac.compare_digest(passwort.encode("utf-8"),
                                      werte["KARTENTOR_PASSWORT"].encode("utf-8"))):
            versuche_vergessen(absender)
            print(f"Angemeldet: {name} ({absender})", flush=True)
            antwort = redirect("/")
            antwort.set_cookie(COOKIE, _siegel(werte).dumps({"name": name,
                                                              "marke": _marke(werte)}),
                               max_age=GUELTIG, secure=True, httponly=True,
                               samesite="Lax")
            return antwort
        else:
            fehlversuch_merken(absender)
            print(f"Fehlversuch: {name[:16]!r} ({absender})", flush=True)
            # Bewusst nicht sagen, WAS falsch war. Viel verraeten wuerde es
            # nicht (der Name ist kein Geheimnis), aber eine Meldung fuer
            # beides ist auch die einfachere.
            meldung = "Name oder Passwort stimmt nicht."

    return render_template(
        "anmelden.html", meldung=meldung, name=name,
        angemeldet=angemeldeter_name(),
        offen=status == 200,
        # Das Cookie traegt "Secure" und wird ueber http:// nicht gespeichert.
        # Ohne diesen Hinweis saehe das aus wie ein falsches Passwort, das
        # trotzdem angenommen wird.
        unverschluesselt=request.headers.get("X-Forwarded-Proto", "https") != "https",
    ), status


@app.post("/kartentor/abmelden")
def abmelden():
    # Ohne CSRF-Token, mit Absicht: Das Schlimmste, was eine fremde Seite
    # damit anrichten kann, ist ein Abmelden — und SameSite=Lax laesst das
    # Cookie bei einem fremden POST ohnehin nicht mitgehen.
    antwort = redirect("/kartentor/anmelden")
    antwort.delete_cookie(COOKIE, secure=True, httponly=True, samesite="Lax")
    return antwort


@app.after_request
def _kopfzeilen(antwort):
    # Die Seite ist klein und hat keine Skripte; das darf sie auch sagen.
    antwort.headers["Cache-Control"] = "no-store"
    antwort.headers["X-Frame-Options"] = "DENY"
    antwort.headers["Referrer-Policy"] = "same-origin"
    antwort.headers["Content-Security-Policy"] = (
        "default-src 'none'; style-src 'unsafe-inline'; form-action 'self'; "
        "frame-ancestors 'none'; base-uri 'none'")
    return antwort


if __name__ == "__main__":
    # 127.0.0.1 fest und ohne Einstellung: Davon haengt ab, dass X-Real-IP
    # stimmt (siehe "Die Bremse"). Vor dem Internet steht nginx.
    app.run(host="127.0.0.1", port=PORT, threaded=True)
