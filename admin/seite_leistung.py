#!/usr/bin/env python3
"""
seite_leistung.py — Wie es dem Pi geht, und woran man drehen kann.

Zwei Haelften:

  1. **Der Verlauf.** Die Frage, die man wirklich stellt, lautet nicht "wie
     ist die Auslastung gerade", sondern "gestern Abend hat es geruckelt --
     was war da los?". Die Messwerte dafuer sammelt metrik.py seit Etappe B
     im Minutentakt; hier werden sie gezeichnet.

  2. **Die vier Stellschrauben**, die wirklich etwas bewirken: Sichtweite,
     Simulationsdistanz und Arbeitsspeicher. Sie stehen hier und nicht auf
     der Konfigurationsseite -- sie sind keine Spielregeln, sondern
     Leistungsstellschrauben, und sie gehoeren neben die Kurve, die zeigt,
     was sie kosten. (Lastenheft O3, entschieden am 28.08.2026.)

Keine GPU-Anzeige: Die VideoCore-GPU des Pi tut fuer einen Minecraft-Server
nichts. Die Kachel waere Dekoration.
"""

import re

from flask import Blueprint, render_template, request

import konfig
from einstellungen import MCS_SERVER_DIR
from sicherheit import auth_required, nur_eigene_oberflaeche
from status import current_status
from system import memory_stats

try:
    import metrik
except ImportError:  # pragma: no cover
    metrik = None

leistung = Blueprint("leistung", __name__)


# ----------------------------------------------------------------------------
# Die Zeitraeume der Kurven
# ----------------------------------------------------------------------------
# Das Lastenheft nennt "1 Minute / 1 Stunde / 24 Stunden". Eine Minute ist
# bei einem Messwert je Minute genau ein Punkt -- daraus laesst sich keine
# Kurve zeichnen. Die kleinste sinnvolle Stufe ist eine Stunde; der
# Augenblickswert steht ohnehin als Zahl daneben.
#
# Sieben Tage kommen dazu, weil genau so lange aufbewahrt wird und die
# Frage "war das schon letzte Woche so?" sonst unbeantwortbar bliebe.
ZEITRAEUME = [
    {"schluessel": "1h", "stunden": 1, "titel": "1 Stunde"},
    {"schluessel": "24h", "stunden": 24, "titel": "24 Stunden"},
    {"schluessel": "7t", "stunden": 24 * 7, "titel": "7 Tage"},
]


def zeitraum(schluessel):
    for eintrag in ZEITRAEUME:
        if eintrag["schluessel"] == schluessel:
            return eintrag
    return ZEITRAEUME[1]


# ----------------------------------------------------------------------------
# Empfehlungen
# ----------------------------------------------------------------------------
def heap_empfehlung(gesamt_mb):
    """Wie viel Arbeitsspeicher der Server bekommen sollte.

    Die Faustregel dahinter: Der Pi braucht selbst etwas, und der Rest ist
    als Dateizwischenspeicher besser angelegt als im Java-Heap. Ein zu
    grosser Heap macht einen Server nicht schneller, sondern seine
    Aufräumpausen länger — und genau die spürt man im Spiel.

    Nachgemessen am 2026-07-27 auf einem Pi 5 mit 8 GB und fünf Spielern:
    3 GB Heap, davon rund 354 MB tatsächlich in Benutzung
    (docs/optimierung-2026-07-27.md). Die Werte hier sind daraus
    hochgerechnet, nicht geraten — und deshalb eher knapp als grosszügig.
    """
    gb = gesamt_mb / 1024.0
    if gb < 2.5:
        return "1G", "Sehr wenig Arbeitsspeicher — mehr als ein Gigabyte bleibt nicht übrig."
    if gb < 5:
        return "2G", "Bei 4 GB im Gerät sind 2 GB für den Server ein guter Schnitt."
    if gb < 9:
        return "3G", ("Bei 8 GB im Gerät: 3 GB. Am 2026-07-27 nachgemessen — "
                      "davon waren unter Last von fünf Spielern nur rund "
                      "350 MB wirklich in Benutzung.")
    return "4G", "Viel Arbeitsspeicher vorhanden. Mehr als 4 GB bringt einem kleinen Server nichts."


def sicht_empfehlung(sicht, simulation):
    """Bewertet das Verhältnis der beiden Distanzen.

    Das ist der wichtigste Hebel des ganzen Projekts (Lastenheft 5.5), und
    er wird fast immer falsch verstanden: `view-distance` bestimmt, wie weit
    Spieler SEHEN, `simulation-distance`, wie weit die Welt tatsächlich
    RECHNET. Die Kosten hängen fast nur an der zweiten Zahl — sie geht
    quadratisch ein: bei 10 sind es (2·10+1)² = 441 voll getickte Chunks je
    Spieler, bei 5 nur 121.
    """
    if simulation > sicht:
        return ("warnung", "Die Simulationsdistanz ist größer als die Sichtweite. "
                           "Das kostet Rechenzeit für Bereiche, die niemand sieht.")
    if simulation >= 10:
        return ("warnung", f"Simulationsdistanz {simulation} bedeutet "
                           f"{(2 * simulation + 1) ** 2} voll gerechnete Chunks je Spieler. "
                           "Wer Ruckler hat, dreht zuerst hier herunter.")
    if sicht - simulation >= 4:
        return ("gut", "Gutes Verhältnis: sieht weit aus, kostet wenig.")
    return ("", "")


def _einstellungen():
    """Der aktuelle Stand der vier Stellschrauben."""
    werte = konfig.properties_lesen(f"{MCS_SERVER_DIR}/server.properties")
    conf = konfig.mcs_conf_lesen()
    speicher = memory_stats()

    def zahl(schluessel, ersatz):
        try:
            return int(werte.get(schluessel, ersatz))
        except (TypeError, ValueError):
            return ersatz

    sicht = zahl("view-distance", 10)
    simulation = zahl("simulation-distance", 10)
    empfehlung_heap, heap_grund = heap_empfehlung(speicher["total_mb"])
    art, hinweis = sicht_empfehlung(sicht, simulation)

    return {
        "sicht": sicht,
        "simulation": simulation,
        "chunks": (2 * simulation + 1) ** 2,
        "heap": conf.get("MCS_HEAP", "?"),
        "heap_empfehlung": empfehlung_heap,
        "heap_grund": heap_grund,
        "ram_gesamt_gb": round(speicher["total_mb"] / 1024.0, 1),
        "broadcast": zahl("entity-broadcast-range-percentage", 100),
        "hinweis_art": art,
        "hinweis": hinweis,
        "vorgemerkt": konfig.vormerkung("server.properties") is not None,
    }


# ----------------------------------------------------------------------------
# Seite und Teile
# ----------------------------------------------------------------------------
@leistung.get("/leistung")
@auth_required
def index():
    gewaehlt = zeitraum(request.args.get("zeitraum", "24h"))
    return render_template("leistung.html",
                           status=current_status(),
                           zeitraeume=ZEITRAEUME,
                           gewaehlt=gewaehlt,
                           einstellungen=_einstellungen(),
                           verlauf_da=metrik is not None)


@leistung.get("/teil/leistungswerte")
@auth_required
def teil_werte():
    """Die Zahlenreihe über den Kurven, alle fünf Sekunden erneuert."""
    return render_template("teile/leistungswerte.html", status=current_status())


@leistung.post("/leistung/einstellungen")
@auth_required
@nur_eigene_oberflaeche
def speichern():
    """Sichtweite, Simulationsdistanz und Heap ändern."""
    meldungen = []

    # --- die beiden Distanzen (server.properties) ---
    aenderungen = {}
    for feld, schluessel, kleinste, groesste in (
            ("sicht", "view-distance", 2, 32),
            ("simulation", "simulation-distance", 2, 32)):
        roh = request.form.get(feld)
        if roh is None:
            continue
        try:
            wert = int(roh)
        except ValueError:
            meldungen.append(("fehler", f"„{roh}“ ist keine Zahl."))
            continue
        if not kleinste <= wert <= groesste:
            meldungen.append(("fehler",
                              f"{schluessel} muss zwischen {kleinste} und "
                              f"{groesste} liegen."))
            continue
        aenderungen[schluessel] = str(wert)

    if aenderungen:
        try:
            ergebnis = konfig.properties_setzen("server.properties", aenderungen)
        except ValueError as fehler:
            meldungen.append(("fehler", str(fehler)))
        else:
            if ergebnis["vorgemerkt"]:
                meldungen.append((
                    "warnung",
                    "Vorgemerkt. Der Server läuft gerade, und Paper würde die "
                    "Änderung überschreiben — sie wird beim nächsten Neustart "
                    "angewendet."))
            else:
                meldungen.append(("gut", "Gespeichert. Wirkt beim nächsten Start."))

    # --- der Heap (mcs.conf) ---
    heap = (request.form.get("heap") or "").strip().upper()
    if heap:
        # Absichtlich eng: Nur Ganzzahl plus G oder M. Der Wert landet in
        # der Startzeile der JVM, und dort hat nichts zu suchen, was nicht
        # genau so aussieht.
        #
        # Die Form allein reicht aber nicht. Bis zum 2026-08-31 gingen „0G“
        # und „999G“ gleichermassen durch: start-minecraft.sh baute daraus
        # "-Xms0G -Xmx0G" (die JVM startet nicht) oder "-Xmx999G" (der Pi
        # geht ins OOM). Beim Speichern erschien nichts — der Fehler kam erst
        # beim naechsten Start als roher Java-Fehler, auf dem Restart=always
        # dann kreiste. Der Installations-Assistent klemmt denselben Wert
        # laengst zwischen 1 GB und Arbeitsspeicher minus 1 GB; das Formular
        # tat es nicht. Wieder dieselbe Regel auf zwei Wegen, einmal fehlend.
        _GRENZE_MB = (512, 63 * 1024)
        heap_mb = None
        # Ziffern, dann genau ein G oder M. Hier stand "alle G und M
        # entfernen, dann Ziffern?" — "3MG" und "1G2G" bestanden das, und
        # int() warf danach einen Serverfehler (23.09.2026, nachgestellt).
        # [0-9] statt \d: \d trifft auch "３" (vollbreit), int() nimmt es an,
        # und die JVM bekaeme "-Xmx３G" (Zweitmeinung zu Durchgang 1).
        treffer = re.fullmatch(r"([0-9]+)([GM])", heap)
        if treffer:
            zahl = int(treffer.group(1))
            heap_mb = zahl * 1024 if treffer.group(2) == "G" else zahl

        if heap_mb is None:
            meldungen.append(("fehler",
                              "Der Arbeitsspeicher muss wie „3G“ oder „2048M“ aussehen."))
        elif not _GRENZE_MB[0] <= heap_mb <= _GRENZE_MB[1]:
            meldungen.append(("fehler",
                              f"„{heap}“ liegt ausserhalb des Sinnvollen. Erlaubt ist "
                              "512M bis 63G — darunter startet die JVM nicht, darüber "
                              "hat kein Raspberry Pi so viel Speicher."))
        else:
            try:
                konfig.mcs_conf_setzen({"MCS_HEAP": heap})
            except ValueError as fehler:
                meldungen.append(("fehler", str(fehler)))
            else:
                meldungen.append((
                    "warnung",
                    f"Arbeitsspeicher auf {heap} gesetzt. Das steht in der "
                    "mcs.conf und wirkt erst nach einem Neustart des Servers."))

    if not meldungen:
        meldungen.append(("warnung", "Es war nichts zu ändern."))

    return render_template("teile/leistungsantwort.html",
                           meldungen=meldungen,
                           einstellungen=_einstellungen())
