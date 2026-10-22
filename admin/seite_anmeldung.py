#!/usr/bin/env python3
"""
seite_anmeldung.py — Anmelden und abmelden.

Eine eigene kleine Seite, weil sie als einzige OHNE Anmeldung erreichbar
sein muss. Die Regeln dahinter (Sitzungs-Cookie, Ratenbegrenzung, Token)
stehen in sicherheit.py; hier steht nur, was der Benutzer davon sieht.
"""

import re

from flask import (Blueprint, redirect, render_template, request, url_for)

from einstellungen import AUTH_ENABLED
from sicherheit import (abmelden, anmelden, csrf_token, fehlversuch_merken,
                        gesperrt_bis, ist_angemeldet, nur_eigene_oberflaeche,
                        versuche_vergessen, zugangsdaten_stimmen)

anmeldung = Blueprint("anmeldung", __name__)


def _absender():
    """Die Adresse, unter der die Fehlversuche gezählt werden."""
    return request.remote_addr or "unbekannt"


def _sicheres_ziel(pfad):
    """Wohin nach der Anmeldung weitergeleitet wird.

    Nur seiteneigene Pfade sind erlaubt. Ohne diese Prüfung könnte man
    jemandem einen Link schicken, der nach der Anmeldung auf eine fremde
    Seite führt — die dann täuschend echt nach PiCraft aussieht und noch
    einmal nach dem Passwort fragt.
    """
    # Nur Zeichen, die in den eigenen Pfaden vorkommen — eine Positivliste,
    # kein Ausschluss. Bis zum 23.09.2026 stand hier "beginnt mit /, aber
    # nicht mit //". Das liess "/<TAB>/fremd.example" durch; Werkzeug
    # entfernt den Tabulator selbst und schrieb "Location: //fremd.example"
    # — genau die Weiterleitung auf eine fremde Seite, vor der dieser
    # Kommentar warnt (nachgestellt). Ein Zeilenumbruch ergab einen
    # Serverfehler, ein Rueckwaertsschraegstrich rettete nur Werkzeugs
    # Kodierung. Die Ziele kommen aus request.path, also reicht das hier.
    if pfad and re.fullmatch(r"/(?!/)[A-Za-z0-9/_.\-]*", pfad):
        return pfad
    return url_for("start.index")


@anmeldung.route("/anmelden", methods=["GET", "POST"])
def formular():
    """Zeigt das Anmeldeformular und nimmt die Anmeldung entgegen."""
    weiter = _sicheres_ziel(request.values.get("weiter"))

    # Ohne gesetztes Passwort gibt es nichts anzumelden — dann würde die
    # Seite nur im Weg stehen. Die Warnung darüber steht in basis.html.
    if not AUTH_ENABLED or ist_angemeldet():
        return redirect(weiter)

    meldung = ""
    rest = gesperrt_bis(_absender())

    if request.method == "POST":
        if rest:
            meldung = (f"Zu viele Fehlversuche. Bitte {rest // 60 + 1} Minuten "
                       "warten und es dann noch einmal versuchen.")
        elif zugangsdaten_stimmen(request.form.get("benutzer"),
                                  request.form.get("passwort")):
            versuche_vergessen(_absender())
            anmelden()
            return redirect(weiter)
        else:
            fehlversuch_merken(_absender())
            rest = gesperrt_bis(_absender())
            # Bewusst nicht sagen, WELCHES von beidem falsch war. Sonst
            # ließe sich damit herausfinden, wie der Benutzer heißt.
            meldung = "Benutzer oder Passwort stimmt nicht."
            if rest:
                meldung += (" Das war der letzte Versuch für die nächsten "
                            f"{rest // 60 + 1} Minuten.")

    if rest and not meldung:
        meldung = (f"Gesperrt nach zu vielen Fehlversuchen. Noch "
                   f"{rest // 60 + 1} Minuten.")

    return render_template("anmeldung.html", meldung=meldung,
                           gesperrt=bool(rest), weiter=weiter,
                           csrf_token=csrf_token())


@anmeldung.post("/abmelden")
@nur_eigene_oberflaeche
def abmelden_route():
    abmelden()
    return redirect(url_for("anmeldung.formular"))
