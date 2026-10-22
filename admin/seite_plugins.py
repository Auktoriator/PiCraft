#!/usr/bin/env python3
"""
seite_plugins.py — Plugins sehen, ein- und ausschalten, neue installieren.

Die Logik steht in plugins.py; hier steht, was man davon sieht und in
welcher Reihenfolge:

  1. **Was da ist.** Soll und Ist nebeneinander, mit dem Hinweis auf alles,
     was zusaetzlich herumliegt -- geloescht wird davon nie etwas.
  2. **Vorschlaege.** Vier Plugins mit der Begruendung, warum man sie
     wollen koennte.
  3. **Suche.** Der einzige Knopf der ganzen Oberflaeche, der eine
     Verbindung nach aussen aufbaut. Das steht auch daneben.
"""

from flask import Blueprint, render_template, request

import plugins as plugindaten
from sicherheit import auth_required, nur_eigene_oberflaeche
from system import service_state

plugin_seite = Blueprint("plugins", __name__)


def _seitendaten(meldung=None, treffer=None, suchtext="",
                 fassungen=None, projekt=""):
    return {
        "uebersicht": plugindaten.uebersicht(),
        "vorschlaege": plugindaten.VORSCHLAEGE,
        "spielversion": plugindaten.spielversion(),
        "laeuft": service_state() == "active",
        "meldung": meldung,
        "treffer": treffer,
        "suchtext": suchtext,
        "fassungen": fassungen,
        "projekt": projekt,
    }


@plugin_seite.get("/plugins")
@auth_required
def index():
    return render_template("plugins.html", **_seitendaten())


@plugin_seite.post("/plugins/umschalten")
@auth_required
@nur_eigene_oberflaeche
def umschalten():
    art, text = plugindaten.umschalten(request.form.get("datei") or "")
    return render_template("teile/pluginliste.html", **_seitendaten((art, text)))


@plugin_seite.post("/plugins/abgleich")
@auth_required
@nur_eigene_oberflaeche
def abgleich():
    art, text = plugindaten.abgleich()
    return render_template("teile/pluginliste.html", **_seitendaten((art, text)))


@plugin_seite.post("/plugins/suchen")
@auth_required
@nur_eigene_oberflaeche
def suchen():
    """Die Modrinth-Suche — der einzige Weg nach außen."""
    text = request.form.get("suche") or ""
    treffer, fehler = plugindaten.suchen(text)
    meldung = ("warnung", fehler) if fehler else None
    return render_template("teile/pluginsuche.html",
                           **_seitendaten(meldung, treffer, text))


@plugin_seite.post("/plugins/fassungen")
@auth_required
@nur_eigene_oberflaeche
def fassungen():
    projekt = request.form.get("projekt") or ""
    liste, fehler = plugindaten.versionen(projekt)
    meldung = ("warnung", fehler) if fehler else None
    return render_template("teile/pluginfassungen.html",
                           **_seitendaten(meldung, fassungen=liste, projekt=projekt))


@plugin_seite.post("/plugins/installieren")
@auth_required
@nur_eigene_oberflaeche
def installieren():
    art, text = plugindaten.installieren(request.form.get("projekt") or "",
                                         request.form.get("fassung") or "")
    return render_template("teile/pluginliste.html", **_seitendaten((art, text)))
