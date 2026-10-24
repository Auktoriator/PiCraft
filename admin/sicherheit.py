#!/usr/bin/env python3
"""
sicherheit.py — Wer darf was.

Drei Schutzschichten fuer die Weboberflaeche:

  1. eine Anmeldung mit Sitzungs-Cookie,
  2. eine Ratenbegrenzung gegen das Durchprobieren von Passwoertern,
  3. eine Pruefung, dass eine schreibende Anfrage wirklich von dieser
     Oberflaeche kam und nicht von einer fremden Seite (CSRF).

Bis zum 28.08.2026 lief die Anmeldung ueber HTTP Basic Auth. Das hatte zwei
Nachteile, die sich nicht wegkonfigurieren lassen: Es gibt kein Abmelden —
der Browser haengt die Zugangsdaten an jede Anfrage, bis man ihn schliesst —
und es gibt keinen Ort, an dem man eine Ratenbegrenzung unterbringen
koennte, weil jede Anfrage ihre eigene Anmeldung ist.

Der Umbau steht im Lastenheft, Abschnitt 5.3.
"""

import hmac
import os
import secrets
import threading
import time
from functools import wraps
from urllib.parse import urlparse

from flask import (current_app, jsonify, redirect, request, session, url_for)

from einstellungen import ADMIN_PASSWORD, ADMIN_USER, AUTH_ENABLED

# ----------------------------------------------------------------------------
# Der Sitzungsschluessel
# ----------------------------------------------------------------------------
# Flask unterschreibt das Sitzungs-Cookie mit diesem Schluessel. Wer ihn
# kennt, kann sich ein Cookie bauen, das wie eine gueltige Anmeldung
# aussieht — er ist also genauso schuetzenswert wie das Passwort und steht
# deshalb in derselben .env mit chmod 600.
#
# Fehlt er, wird einer erzeugt. Das ist ausdruecklich KEIN stiller
# Rueckfall: Ein erzeugter Schluessel lebt nur, solange der Dienst laeuft,
# und jeder Neustart meldet alle ab. Das muss man wissen, deshalb sagt es
# die Oberflaeche (siehe SCHLUESSEL_ERZEUGT und basis.html).
SCHLUESSEL_ERZEUGT = False


def sitzungsschluessel():
    """Liefert den Schluessel fuer das Sitzungs-Cookie."""
    global SCHLUESSEL_ERZEUGT
    aus_umgebung = os.getenv("MCS_ADMIN_SECRET", "").strip()
    if aus_umgebung:
        return aus_umgebung
    SCHLUESSEL_ERZEUGT = True
    return secrets.token_hex(32)


# Ueber eine reine HTTP-Verbindung im Heimnetz wuerde ein Cookie mit dem
# Merkmal "Secure" gar nicht erst gesetzt — die Anmeldung waere unmoeglich.
# Wer die Oberflaeche hinter Tailscale Serve mit HTTPS betreibt, setzt
# MCS_ADMIN_HTTPS=1 in der .env und bekommt das Merkmal dazu.
HTTPS_AKTIV = os.getenv("MCS_ADMIN_HTTPS", "0") in {"1", "true", "TRUE", "yes", "YES"}

# Wie lange eine Anmeldung haelt. Dreissig Tage: Das ist ein Werkzeug fuer
# den eigenen Server im eigenen Netz, und wer sich alle zwei Stunden neu
# anmelden muss, waehlt irgendwann ein kuerzeres Passwort.
SITZUNG_TAGE = 30


def app_absichern(app):
    """Setzt die Sitzungseinstellungen an der Flask-Anwendung.

    Alles an einer Stelle, damit niemand die halbe Absicherung vergisst,
    wenn er einen zweiten Einstiegspunkt baut.
    """
    app.secret_key = sitzungsschluessel()
    app.config.update(
        SESSION_COOKIE_HTTPONLY=True,      # kein Zugriff aus JavaScript
        SESSION_COOKIE_SAMESITE="Lax",     # siehe nur_eigene_oberflaeche
        SESSION_COOKIE_SECURE=HTTPS_AKTIV,
        PERMANENT_SESSION_LIFETIME=SITZUNG_TAGE * 24 * 3600,
    )
    return app


# ----------------------------------------------------------------------------
# Ratenbegrenzung
# ----------------------------------------------------------------------------
# Ein Passwort laesst sich durchprobieren. Ohne Bremse schafft ein Skript
# im Heimnetz mehrere hundert Versuche je Sekunde; mit dieser Bremse sind
# es fuenf in fuenfzehn Minuten.
#
# Bewusst im Arbeitsspeicher und ohne Zusatzpaket: Ein Neustart des
# Dienstes setzt die Zaehler zurueck. Wer das ausnutzen will, muss den
# Dienst neu starten koennen — und wer das kann, braucht kein Passwort mehr.
#
# GRENZE: Steht ein Reverse-Proxy davor, sehen alle Anfragen aus wie die
# des Proxys, und eine Sperre traefe alle statt nur den Angreifer.
#
# Hier stand bis zum 30.08.2026 "Tailscale reicht die echte Adresse durch".
# Das stimmt nur zur Haelfte, und die falsche Haelfte ist ausgerechnet der
# Weg, den das Lastenheft empfiehlt:
#
#   Direkt ueber die Tailscale-Adresse (MCS_ADMIN_HOST=100.x.y.z)
#       -> die Anfrage kommt wirklich von der 100.x.y.z des Handys.
#          Die Bremse wirkt je Geraet. Richtig.
#   Ueber Tailscale Serve (Entscheidung 12, echtes HTTPS)
#       -> Serve ist ein Proxy AUF dem Pi. Alle Anfragen kommen von
#          127.0.0.1, und die Bremse trifft alle Geraete gemeinsam.
#
# Behoben wird das hier NICHT ueber X-Forwarded-For: Diesen Kopf darf man
# nur glauben, wenn sicher ist, dass ein vertrauenswuerdiger Proxy davor
# steht. Waere die Oberflaeche einmal direkt erreichbar, koennte sich jeder
# die Bremse mit einer erfundenen Adresse wegschreiben — aus einem Schutz
# wuerde eine Einladung. Bei einem einzigen Administrator ist die Folge
# ueberschaubar: Er sperrt sich selbst fuer fuenf Minuten aus. Steht im
# README, Abschnitt "Zugriff ueber Tailscale".
VERSUCHE_ERLAUBT = 5
MERKDAUER = 15 * 60      # so lange zaehlen Fehlversuche mit (Sekunden)
SPERRE = 5 * 60          # so lange bleibt gesperrt (Sekunden)

_versuche = {}           # Adresse -> Liste von Zeitpunkten
_versuche_sperre = threading.Lock()


def _jetzt():
    return time.monotonic()


def gesperrt_bis(adresse):
    """Wie lange diese Adresse noch gesperrt ist (Sekunden, 0 = frei)."""
    with _versuche_sperre:
        zeiten = [z for z in _versuche.get(adresse, []) if _jetzt() - z < MERKDAUER]
        _versuche[adresse] = zeiten
        if len(zeiten) < VERSUCHE_ERLAUBT:
            return 0
        # Gesperrt ab dem Zeitpunkt des letzten Fehlversuchs.
        rest = SPERRE - (_jetzt() - zeiten[-1])
        return max(0, int(rest))


def fehlversuch_merken(adresse):
    with _versuche_sperre:
        _versuche.setdefault(adresse, []).append(_jetzt())


def versuche_vergessen(adresse):
    """Nach erfolgreicher Anmeldung faengt die Zaehlung von vorn an."""
    with _versuche_sperre:
        _versuche.pop(adresse, None)


# ----------------------------------------------------------------------------
# Anmelden und abmelden
# ----------------------------------------------------------------------------
def zugangsdaten_stimmen(benutzer, passwort):
    """Prueft Benutzername und Passwort.

    hmac.compare_digest vergleicht immer gleich lang — ein Angreifer kann
    also nicht an der Antwortzeit ablesen, wie viele Zeichen des Passworts
    schon stimmen.

    Verglichen werden BYTES, nicht Zeichenketten. Auf str angewendet
    verweigert compare_digest jedes Zeichen ausserhalb von ASCII:

        TypeError: comparing strings with non-ASCII characters
                   is not supported

    Bis zum 2026-08-31 stand hier str. In einem durchweg deutschsprachigen
    Projekt, dessen Assistent ausdruecklich nach einem eigenen Passwort fragt
    und davon nur die LAENGE prueft, ist ein Umlaut das Naheliegende — und
    die Folge war eine dauerhafte Aussperrung: Der Aufrufer faengt nichts ab,
    also beantwortete die Anmeldeseite jeden Versuch mit einem Serverfehler
    statt mit einer Meldung. Kein Test hat es bemerkt, weil beide
    Testpasswoerter reines ASCII sind ("abnahmetest", "geheim").

    Nebenwirkung derselben Falle: Auch ein GETIPPTES Umlaut-Passwort flog
    hier heraus, bevor fehlversuch_merken() erreicht war — solche Versuche
    zaehlte die Ratenbegrenzung nicht mit.
    """
    return (hmac.compare_digest((benutzer or "").encode("utf-8"),
                                ADMIN_USER.encode("utf-8"))
            and hmac.compare_digest((passwort or "").encode("utf-8"),
                                    ADMIN_PASSWORD.encode("utf-8")))


def _passwort_marke():
    """Bindet die Anmeldung an das Passwort: Ein neues Passwort meldet alle ab.

    Bis zum 24.10.2026 stand in der Sitzung nur True. Ein verlorenes,
    angemeldetes Handy blieb damit bis zu dreissig Tage drin — auch nachdem
    das Passwort in der .env geaendert war.

    HMAC mit dem Sitzungsschluessel statt eines blossen Hashes: Das Cookie ist
    unterschrieben, aber nicht verschluesselt. Ein Hash des Passworts darin
    liesse sich offline durchprobieren.
    """
    return hmac.new(current_app.secret_key.encode("utf-8"),
                    ADMIN_PASSWORD.encode("utf-8"), "sha256").hexdigest()


def anmelden():
    """Merkt die Anmeldung in der Sitzung und legt ein CSRF-Token an."""
    session.clear()
    session.permanent = True
    session["angemeldet"] = _passwort_marke()
    session["token"] = secrets.token_urlsafe(32)


def abmelden():
    session.clear()


def ist_angemeldet():
    return session.get("angemeldet") == _passwort_marke()


def csrf_token():
    """Das Token dieser Sitzung (wird bei Bedarf angelegt).

    Auch ohne Anmeldung eines vergeben: Die Anmeldeseite selbst ist ein
    Formular und braucht schon eines.
    """
    if "token" not in session:
        session["token"] = secrets.token_urlsafe(32)
    return session["token"]


def _zur_anmeldung():
    """Die Antwort fuer eine Anfrage ohne Anmeldung.

    Bei einer HTMX-Anfrage waere eine Weiterleitung nutzlos — HTMX baute
    die Anmeldeseite mitten in die Kachel ein, die es gerade erneuern
    wollte. Deshalb bekommt HTMX einen Kopfeintrag, der den GANZEN Browser
    umleitet.
    """
    ziel = url_for("anmeldung.formular", weiter=request.path)
    if request.headers.get("HX-Request"):
        antwort = jsonify({"error": "Nicht angemeldet"})
        antwort.status_code = 401
        antwort.headers["HX-Redirect"] = ziel
        return antwort
    return redirect(ziel)


def auth_required(func):
    """Schuetzt eine Route: ohne Anmeldung geht es zur Anmeldeseite.

    Seit dem 2026-08-31 ist dieser Dekorator nicht mehr die einzige Schranke,
    sondern die zweite (siehe anmeldepflicht_erzwingen). Er bleibt, weil man
    an der Route selbst sehen soll, dass sie geschuetzt ist.
    """
    @wraps(func)
    def wrapper(*args, **kwargs):
        if not AUTH_ENABLED or ist_angemeldet():
            return func(*args, **kwargs)
        return _zur_anmeldung()

    return wrapper


# ----------------------------------------------------------------------------
# Der Engpass: angemeldet sein ist die Vorgabe, nicht die Ausnahme
# ----------------------------------------------------------------------------
# Bis zum 2026-08-31 hing die gesamte Absicherung daran, dass an JEDER Route
# ein @auth_required steht. Nachgesehen: Es stand ueberall, wo es hingehoert —
# es war also kein Loch offen. Aber die Vorgabe war falsch herum. Wer eine
# neue Route hinzufuegt und den Dekorator vergisst, oeffnet damit eine
# Oberflaeche, die die eigene Dokumentation "so maechtig wie ein SSH-Zugang"
# nennt. Ein Vergessen darf nicht die unsichere Seite treffen.
#
# Deshalb hier umgedreht: Ohne Anmeldung geht gar nichts, ausser was
# ausdruecklich in dieser Liste steht. Wer eine neue Route vergisst, sperrt
# sich selbst aus — das faellt sofort auf und richtet keinen Schaden an.
#
# Was offen bleibt und warum:
#   anmeldung.formular        die Anmeldeseite selbst. Sonst gaebe es keinen
#                             Weg hinein.
#   anmeldung.abmelden_route  Abmelden muss auch gehen, wenn die Sitzung
#                             schon abgelaufen ist. Traegt selbst
#                             nur_eigene_oberflaeche.
#   start.teil_kopfzustand    der Statuspunkt in der Kopfzeile. Er steht auf
#                             der Anmeldeseite und darf dort nichts
#                             verraten ausser "laeuft / laeuft nicht".
#   static                    CSS, Schrift, htmx. Ohne sie waere die
#                             Anmeldeseite unbenutzbar.
OFFENE_ENDPUNKTE = frozenset({
    "anmeldung.formular",
    "anmeldung.abmelden_route",
    "start.teil_kopfzustand",
    "static",
})


def anmeldepflicht_erzwingen(app):
    """Haengt den Engpass in die Anwendung."""
    @app.before_request
    def _anmeldung_pruefen():          # pragma: no cover - Flask ruft es auf
        if not AUTH_ENABLED or ist_angemeldet():
            return None
        if request.endpoint in OFFENE_ENDPUNKTE:
            return None
        # Ein unbekannter Endpunkt (404) darf ruhig als 404 enden — sonst
        # verriete die Weiterleitung, welche Pfade es gibt und welche nicht.
        if request.endpoint is None:
            return None
        return _zur_anmeldung()

    return app


# ----------------------------------------------------------------------------
# CSRF
# ----------------------------------------------------------------------------
def nur_eigene_oberflaeche(func):
    """Schuetzt schreibende Aufrufe davor, von fremden Seiten ausgeloest zu werden.

    Das Problem heisst CSRF: Ist man an der Oberflaeche angemeldet, haengt
    der Browser das Sitzungs-Cookie von sich aus an Anfragen an diese
    Adresse — auch an solche, die eine ganz andere, offene Seite ausgeloest
    hat. Ein einzeiliges Formular auf einer beliebigen Webseite haette
    sonst gereicht:

        <form method="post" action="http://<pi>:8080/api/action/stop_server">

    Drei Schichten verhindern das. Jede fuer sich wuerde in den meisten
    Faellen reichen; zusammen decken sie auch die Faelle ab, in denen eine
    davon nicht greift:

    1. SameSite=Lax am Cookie (siehe app_absichern). Der Browser schickt es
       bei einer fremdausgeloesten POST-Anfrage gar nicht erst mit — die
       Anfrage kommt also unangemeldet an. Das ist die staerkste Schicht,
       aber sie liegt beim Browser, nicht bei uns.
    2. Ein Token aus der Sitzung, das die Oberflaeche an jede schreibende
       Anfrage haengt (HTMX ueber hx-headers, Formulare als verstecktes
       Feld). Eine fremde Seite kann es nicht lesen.
    3. Die Herkunftspruefung: Kommt eine Origin- oder Referer-Angabe mit,
       muss sie zu dieser Oberflaeche gehoeren.

    Bis zum 28.08.2026 stand hier stattdessen die Bedingung
    "Content-Type: application/json" — ein Trick, der funktionierte, solange
    die Oberflaeche ihre Anfragen selbst mit JavaScript zusammenbaute. HTMX
    schickt Formulardaten, also musste er weg.
    """
    @wraps(func)
    def wrapper(*args, **kwargs):
        # Ohne Anmeldung gibt es auch keine Sitzung, die man missbrauchen
        # koennte — dann greift bereits auth_required.
        if AUTH_ENABLED:
            mitgeschickt = (request.headers.get("X-CSRF-Token")
                            or request.form.get("csrf_token")
                            or (request.get_json(silent=True) or {}).get("csrf_token"))
            erwartet = session.get("token")
            # Auch hier Bytes: Das eigene Token ist zwar immer ASCII, das
            # MITGESCHICKTE kommt aber von aussen. Mit str haette ein Token
            # voller Umlaute einen TypeError und damit einen Serverfehler
            # ausgeloest, wo eine saubere 403 hingehoert.
            if not erwartet or not mitgeschickt or not hmac.compare_digest(
                    str(mitgeschickt).encode("utf-8"),
                    str(erwartet).encode("utf-8")):
                return jsonify({
                    "error": "Diese Anfrage kam ohne gültigen Sitzungsnachweis "
                             "und wurde abgelehnt. Bitte die Seite neu laden "
                             "und noch einmal versuchen."
                }), 403

        herkunft = request.headers.get("Origin") or request.headers.get("Referer")
        if herkunft and urlparse(herkunft).netloc != request.host:
            return jsonify({
                "error": "Diese Anfrage kam von einer fremden Seite und wurde abgelehnt."
            }), 403

        return func(*args, **kwargs)

    return wrapper
