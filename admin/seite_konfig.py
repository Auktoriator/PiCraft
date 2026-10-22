#!/usr/bin/env python3
"""
seite_konfig.py — Einstellungen, Expertenmodus und das Drumherum.

Zwei Ebenen, weil eine nicht reicht (Lastenheft 5.7.4):

  1. **Einstellungen** — die fuenfzehn Werte, die wirklich zaehlen, als
     richtige Bedienelemente mit deutscher Erklaerung und geprueften
     Wertebereichen.
  2. **Expertenmodus** — Rohtext je Datei, aus einer festen Liste, mit
     Pruefung beim Speichern und gesicherter Vorfassung.

Formulare fuer jeden Schluessel jeder Datei waeren Wochenarbeit und braechen
bei jedem Paper-Update -- `paper-world-defaults.yml` allein hat 341 Zeilen.
Die kuratierte Liste plus ehrlicher Rohzugriff ist das richtige Verhaeltnis.

Auf derselben Seite: hochfahren, herunterfahren, neu starten; welche
Paper- und Java-Version laufen und ob es einen neueren Paper-Build gibt
(paper.py); welche Ports offen sind und wofuer.

**Kein Knopf fuer `mcs aus`.** Er wuerde die Weboberflaeche mitabschalten,
und ein Knopf, der die Seite unerreichbar macht, die ihn zeigt, ist eine
Falle. Erwaehnt wird der Befehl, ausgeloest wird er im Terminal.
"""

from flask import Blueprint, render_template, request

import konfig
import netz
import paper
from einstellungen import ALLOW_HOST_POWER
from konsole import action_command
from sicherheit import auth_required, nur_eigene_oberflaeche
from system import run_background, run_command, service_state

konfiguration = Blueprint("konfiguration", __name__)


def _seitendaten(meldungen=None):
    return {
        "einstellungen": konfig.einstellungen_lesen(),
        "dateien": konfig.DATEIEN,
        "vorgemerkt": konfig.vorgemerkte(),
        "versionen": konfig.versionen(),
        "ports": konfig.offene_ports(),
        "laeuft": service_state() == "active",
        "allow_host_power": ALLOW_HOST_POWER,
        "meldungen": meldungen or [],
    }


@konfiguration.get("/konfiguration")
@auth_required
def index():
    return render_template("konfiguration.html", **_seitendaten())


@konfiguration.post("/konfiguration/einstellungen")
@auth_required
@nur_eigene_oberflaeche
def einstellungen_speichern():
    """Speichert die kuratierten Werte — aber nur die, die sich geändert haben.

    Warum der Vergleich? Das Formular schickt immer alle fünfzehn Werte
    mit. Sie alle zu schreiben hiesse: bei laufendem Server fünfzehn
    Vormerkungen für eine geänderte Zahl, und die Meldung „15 Änderungen
    warten“ wäre schlicht falsch.
    """
    vorher = {e["schluessel"]: e for e in konfig.einstellungen_lesen()}
    meldungen = []

    for eintrag in konfig.EINSTELLUNGEN:
        schluessel = eintrag["schluessel"]
        alt = vorher.get(schluessel, {})

        # Gesperrte Felder werden nicht geschrieben — auch nicht, wenn sie
        # jemand von Hand mitschickt.
        #
        # Ein "disabled" Kaestchen schickt naemlich GAR NICHTS mit, und das
        # ist ununterscheidbar von "nicht angehakt". Bis zum 2026-08-31 las
        # die Schleife daraus "aus": Stand die Whitelist auf true und war der
        # Schalter gesperrt (Server aus, also keine RCON-Auskunft), galt jedes
        # Speichern der Seite als Aenderung auf false — und erzeugte eine
        # Warnung ueber etwas, das der Benutzer nie angefasst hatte. Geschadet
        # hat es nie, weil konfig.py den Wert bei gestopptem Server ohnehin
        # nicht setzt; geglaubt hat man die Meldung trotzdem.
        if alt.get("gesperrt"):
            continue

        if eintrag["art"] == "schalter":
            # Ein nicht angehakter Schalter schickt gar nichts mit — das
            # ist genau der Fall "aus" und kein fehlender Wert.
            neu = "true" if request.form.get(schluessel) else "false"
            if neu == ("true" if alt.get("an") else "false"):
                continue
        else:
            if schluessel not in request.form:
                continue
            neu = request.form.get(schluessel)
            if str(neu).strip() == str(alt.get("wert", "")).strip():
                continue

        meldungen.append(konfig.einstellung_setzen(schluessel, neu))

    if not meldungen:
        meldungen.append(("warnung", "Es war nichts geändert."))

    return render_template("teile/konfigeinstellungen.html",
                           **_seitendaten(meldungen))


@konfiguration.get("/konfiguration/datei/<name>")
@auth_required
def datei_zeigen(name):
    """Eine Datei im Expertenmodus öffnen."""
    info = konfig.datei_info(name)
    inhalt = konfig.datei_lesen(name)
    if info is None or inhalt is None:
        return render_template("teile/konfigdatei.html", name=name, info=None,
                               inhalt="", meldung=("fehler",
                               "Diese Datei gibt es nicht oder sie lässt sich "
                               "nicht lesen."), **_seitendaten())
    return render_template("teile/konfigdatei.html", name=name, info=info,
                           inhalt=inhalt, meldung=None, **_seitendaten())


@konfiguration.post("/konfiguration/datei/<name>")
@auth_required
@nur_eigene_oberflaeche
def datei_speichern(name):
    art, text = konfig.datei_schreiben(name, request.form.get("inhalt") or "")
    info = konfig.datei_info(name)
    # Nach dem Speichern das zurückgeben, was jetzt WIRKLICH dasteht —
    # einschließlich der wieder verdeckten Geheimnisse und einer etwaigen
    # Vormerkung. Wer das Textfeld unverändert stehen ließe, zeigte einen
    # Stand, den es so vielleicht gar nicht gibt.
    inhalt = konfig.vormerkung(name) or konfig.datei_lesen(name) or ""
    if info:
        inhalt = konfig._geheim_verdecken(inhalt, info["art"], info["geheim"])
    return render_template("teile/konfigdatei.html", name=name, info=info,
                           inhalt=inhalt, meldung=(art, text),
                           **_seitendaten())


@konfiguration.post("/konfiguration/vormerkung/verwerfen")
@auth_required
@nur_eigene_oberflaeche
def vormerkung_verwerfen():
    name = request.form.get("name") or ""
    if konfig.datei_info(name) is None:
        meldung = ("fehler", "Diese Datei gibt es nicht.")
    elif konfig.vormerkung_verwerfen(name):
        meldung = ("gut", f"Die vorgemerkte Änderung an {name} wurde verworfen.")
    else:
        meldung = ("warnung", f"Für {name} war nichts vorgemerkt.")
    return render_template("teile/konfigeinstellungen.html",
                           **_seitendaten([meldung]))


# ----------------------------------------------------------------------------
# Paper: welcher Build, gibt es einen neueren, und aktualisieren
# ----------------------------------------------------------------------------
# Dasselbe Muster wie die Erreichbarkeit darunter: Beim Aufbau nur, was der
# Pi weiss (die Notizen des Update-Skripts). Nach außen erst auf Klick.
def _paperdaten(meldung=None, ausgabe=""):
    return {"paper": paper.stand(), "meldung": meldung, "ausgabe": ausgabe}


@konfiguration.get("/teil/paper")
@auth_required
def teil_paper():
    return render_template("teile/paperstand.html", **_paperdaten())


@konfiguration.post("/konfiguration/paper/nachsehen")
@auth_required
@nur_eigene_oberflaeche
def paper_nachsehen():
    return render_template("teile/paperstand.html",
                           **_paperdaten(paper.nachsehen()))


@konfiguration.post("/konfiguration/paper/aktualisieren")
@auth_required
@nur_eigene_oberflaeche
def paper_aktualisieren():
    meldung, ausgabe = paper.aktualisieren()
    return render_template("teile/paperstand.html",
                           **_paperdaten(meldung, ausgabe))


# ----------------------------------------------------------------------------
# Erreichbarkeit von außen
# ----------------------------------------------------------------------------
# Zwei getrennte Endpunkte, und das ist der ganze Punkt: Beim Aufbau der
# Seite wird NUR das gezeigt, was der Pi über sich selbst weiß. Wer den Test
# nach draußen will, klickt — und liest daneben, wer gefragt wird.
@konfiguration.get("/teil/erreichbarkeit")
@auth_required
def teil_erreichbarkeit():
    return render_template("teile/erreichbarkeit.html", netzbild=netz.lokal())


@konfiguration.post("/konfiguration/erreichbarkeit")
@auth_required
@nur_eigene_oberflaeche
def erreichbarkeit_pruefen():
    return render_template("teile/erreichbarkeit.html",
                           netzbild=netz.vollstaendig())


# ----------------------------------------------------------------------------
# Dauerhafter Name im Internet
# ----------------------------------------------------------------------------
# Steht direkt beim Erreichbarkeitstest: Der Test sagt, OB es geht, das
# DNS-Modul sorgt für den Namen, unter dem es geht.
def _dnsdaten(meldung=None):
    return {"dns": netz.dns_zustand(), "anbieter": netz.ANBIETER,
            "meldung": meldung}


@konfiguration.get("/teil/dns")
@auth_required
def teil_dns():
    return render_template("teile/dns.html", **_dnsdaten())


@konfiguration.post("/konfiguration/dns")
@auth_required
@nur_eigene_oberflaeche
def dns_speichern():
    art, text = netz.dns_setzen(request.form.get("anbieter") or "",
                                request.form.get("name") or "",
                                request.form.get("zone") or "",
                                request.form.get("token") or "")
    return render_template("teile/dns.html", **_dnsdaten((art, text)))


@konfiguration.post("/konfiguration/dns/melden")
@auth_required
@nur_eigene_oberflaeche
def dns_melden():
    art, text = netz.dns_melden()
    return render_template("teile/dns.html", **_dnsdaten((art, text)))


@konfiguration.post("/konfiguration/dns/srv")
@auth_required
@nur_eigene_oberflaeche
def dns_srv():
    art, text = netz.dns_srv()
    return render_template("teile/dns.html", **_dnsdaten((art, text)))


@konfiguration.post("/konfiguration/aktion/<name>")
@auth_required
@nur_eigene_oberflaeche
def aktion(name):
    """Starten, stoppen, neu starten, aktualisieren."""
    beschreibung = action_command(name)
    if beschreibung is None:
        meldung = ("fehler", "Diese Aktion gibt es nicht oder sie ist nicht erlaubt.")
    elif beschreibung["mode"] == "background":
        run_background(beschreibung["cmd"], name, cwd=beschreibung.get("cwd"))
        meldung = ("gut", "Gestartet. Das läuft im Hintergrund weiter — "
                          "der Verlauf steht im Aktionsprotokoll.")
    else:
        code, aus, fehler = run_command(
            beschreibung["cmd"], timeout=beschreibung.get("timeout", 180),
            cwd=beschreibung.get("cwd"),
            protokoll=name if beschreibung.get("protokoll") else None)
        meldung = (("gut", "Erledigt.") if code == 0
                   else ("fehler", fehler or aus or f"Fehlgeschlagen ({code})."))

    return render_template("teile/konfigeinstellungen.html",
                           **_seitendaten([meldung]))
