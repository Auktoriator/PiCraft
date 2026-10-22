#!/usr/bin/env python3
"""
seite_historie.py — Wer war wann online, wie lange, und was wurde gesagt.

Drei Blöcke: Spielzeit je Tag, die Sitzungen einzeln, und Chat/Befehle.
Ein Filter über alle drei, damit man einen Spieler durch die ganze Seite
verfolgen kann.

**Der Index wird beim Aufruf dieser Seite fortgeschrieben, nicht in einem
Takt.** Bei geschlossener Oberfläche kostet die Historie damit null
Rechenzeit — Leitsatz 1. Deshalb hat diese Seite auch kein
`hx-trigger="every …"`, anders als Startseite und Spielerliste: Die zeigen
einen Zustand, der sich unter der Hand ändert. Eine Historie ändert sich
nicht, während man sie ansieht.

Gemessen am 21.09.2026: Der erste Aufbau über 229 Serverprotokolle dauert
1,0 s, jeder weitere Aufruf 25 ms (nur `latest.log` wird neu gelesen) plus
19 ms für die Sitzungen. Den ersten, großen Durchlauf nimmt einem
`tools/historie-aufbauen.py` ab.
"""

from pathlib import Path

from flask import Blueprint, render_template, request

import historie as historiendaten
from einstellungen import (HISTORIE_DB, HISTORIE_TAGE, MINECRAFT_LOG,
                           PLAYER_ACTIVITY_LOG)
from sicherheit import auth_required
from status import protokoll_befund

historie = Blueprint("historie", __name__)

# Wie weit die Balken und Summen zurückreichen. 30 Tage beantworten die
# Frage, die man wirklich stellt ("wer war zuletzt viel da?"), ohne dass
# die Seite zu einer Jahresstatistik wird.
FENSTER_TAGE = 30


def _zeit_lesbar(sekunden):
    """Aus 9126 Sekunden wird "2 h 32 min"; aus None wird None.

    None heisst "wissen wir nicht" und muss als Strich durchkommen -- eine
    Null waere eine Aussage, und zwar eine falsche.
    """
    if sekunden is None:
        return None
    stunden, rest = divmod(int(sekunden), 3600)
    minuten = rest // 60
    return f"{stunden} h {minuten} min" if stunden else f"{minuten} min"


def _seitendaten():
    db = historiendaten.verbindung(HISTORIE_DB)
    historiendaten.aktualisieren(db, PLAYER_ACTIVITY_LOG,
                                 Path(MINECRAFT_LOG).parent)
    if HISTORIE_TAGE:
        historiendaten.aufraeumen(db, HISTORIE_TAGE)

    gewaehlt = (request.args.get("spieler") or "").strip() or None
    if gewaehlt and gewaehlt not in historiendaten.spielerliste(db):
        gewaehlt = None            # unbekannter Name -> Filter ignorieren

    sitzungen = historiendaten.sitzungen(db, spieler=gewaehlt, grenze=200)
    for s in sitzungen:
        s["dauer"] = _zeit_lesbar(s["sekunden"])

    je_spieler = historiendaten.summen_je_spieler(db, tage=FENSTER_TAGE)
    for s in je_spieler:
        s["dauer"] = _zeit_lesbar(s["sekunden"])

    # Balken je Tag. Die längste Tagessumme ist der Maßstab; ohne sie
    # müsste die Vorlage rechnen, und das kann Jinja nur umständlich.
    tage = {}
    for eintrag in historiendaten.summen_je_tag(db, tage=FENSTER_TAGE,
                                                spieler=gewaehlt):
        tage[eintrag["tag"]] = tage.get(eintrag["tag"], 0) + eintrag["sekunden"]
    hoechster = max(tage.values()) if tage else 0
    balken = [{"tag": tag,
               "sekunden": sek,
               "dauer": _zeit_lesbar(sek),
               "anteil": round(100 * sek / hoechster) if hoechster else 0}
              for tag, sek in sorted(tage.items())]

    von, bis = historiendaten.zeitraum(db)

    return {
        "gewaehlt": gewaehlt,
        "namen": historiendaten.spielerliste(db),
        "sitzungen": sitzungen,
        "je_spieler": je_spieler,
        "balken": balken,
        "fenster_tage": FENSTER_TAGE,
        "aeusserungen": historiendaten.aeusserungen(db, spieler=gewaehlt,
                                                    grenze=200),
        # Ab wann die Historie ueberhaupt etwas weiss. Gehoert sichtbar auf
        # die Seite: Die Spielzeit auf der Spielerseite kommt aus Papers
        # Statistikdateien und reicht weiter zurueck als jedes
        # Serverprotokoll (gemessen 545 h gegen 92 h). Ohne diese Angabe
        # sieht der Unterschied wie ein Fehler aus.
        "von": von,
        "bis": bis,
        # Wie viele Sitzungen im Fenster kein bekanntes Ende haben. Steht
        # neben den Summen -- ohne sie sieht eine unvollstaendige Summe
        # genauso aus wie eine vollstaendige.
        "ohne_ende": historiendaten.offene_sitzungen(db, tage=FENSTER_TAGE),
        "aufbewahrung_tage": HISTORIE_TAGE,
        # Derselbe Hinweis wie auf der Spielerseite: Fehlt dem Hauptbuch
        # die Vergangenheit, ist auch diese Seite unvollstaendig.
        "protokoll_befund": protokoll_befund(),
    }


@historie.get("/historie")
@auth_required
def index():
    return render_template("historie.html", **_seitendaten())


@historie.get("/teil/historienliste")
@auth_required
def teil_liste():
    return render_template("teile/historienliste.html", **_seitendaten())
