#!/usr/bin/env python3
"""
seite_backups.py — Backups sehen, pruefen, zurueckspielen.

Die wichtigste Lehre aus der Projektgeschichte steht im Lastenheft: Vom
2026-05-18 bis zum 2026-07-27 kam ueber zwei Monate kein Backup zustande,
obwohl der Cronjob jede Nacht lief -- und niemand hat es bemerkt. Diese
Seite ist die Antwort darauf. Sie sagt als Erstes, ob es ein aktuelles
Backup gibt, und erst danach, was man damit tun kann.

Die drei Handlungen sind sehr unterschiedlich gefaehrlich, und die Seite
behandelt sie auch so:

    Pruefen            gefahrlos, auch bei laufendem Server
    Wiederherstellen   tauscht Weltdaten aus -- Server muss stehen,
                       Name muss abgetippt werden
    Loeschen           endgueltig -- Name muss abgetippt werden, und das
                       neueste Backup geht gar nicht
"""

from flask import Blueprint, render_template, request

import backups as backupdaten
from konsole import action_command
from sicherheit import auth_required, nur_eigene_oberflaeche
from system import run_background, service_state

backup_seite = Blueprint("backups", __name__)


def _seitendaten(meldung=None):
    eintraege = backupdaten.liste()
    return {
        "backups": eintraege,
        "zustand": backupdaten.zustand(eintraege),
        "einstellungen": backupdaten.einstellungen(),
        "benachrichtigung": backupdaten.benachrichtigung(),
        "kopien": backupdaten.kopien(),
        "platz": backupdaten.platz(),
        "protokoll": backupdaten.protokoll(),
        "laeuft": service_state() == "active",
        "meldung": meldung,
    }


@backup_seite.get("/backups")
@auth_required
def index():
    return render_template("backups.html", **_seitendaten())


@backup_seite.get("/teil/backupliste")
@auth_required
def teil_liste():
    return render_template("teile/backupliste.html", **_seitendaten())


@backup_seite.post("/backups/jetzt")
@auth_required
@nur_eigene_oberflaeche
def jetzt():
    """Ein Backup von Hand anstoßen.

    Im Hintergrund: Ein Backup einer gewachsenen Welt dauert Minuten, und
    die Oberfläche soll währenddessen bedienbar bleiben. Was dabei
    herauskommt, steht danach im Protokoll weiter unten.
    """
    beschreibung = action_command("backup_now")
    if beschreibung is None:
        return render_template("teile/backupliste.html",
                               **_seitendaten(("fehler", "Backup ist nicht eingerichtet.")))
    run_background(beschreibung["cmd"], "backup_now", cwd=beschreibung.get("cwd"))
    return render_template("teile/backupliste.html", **_seitendaten(
        ("gut", "Backup gestartet. Das dauert je nach Weltgröße einige "
                "Minuten und läuft im Hintergrund weiter — der Verlauf steht "
                "unten im Protokoll.")))


@backup_seite.post("/backups/pruefen")
@auth_required
@nur_eigene_oberflaeche
def pruefen():
    art, text = backupdaten.pruefen(request.form.get("name") or "")
    return render_template("teile/backupliste.html", **_seitendaten((art, text)))


@backup_seite.post("/backups/wiederherstellen")
@auth_required
@nur_eigene_oberflaeche
def wiederherstellen():
    art, text = backupdaten.wiederherstellen(
        request.form.get("name") or "",
        request.form.get("bestaetigung") or "",
        alles=bool(request.form.get("alles")))
    return render_template("teile/backupliste.html", **_seitendaten((art, text)))


@backup_seite.post("/backups/loeschen")
@auth_required
@nur_eigene_oberflaeche
def loeschen():
    art, text = backupdaten.loeschen(request.form.get("name") or "",
                                     request.form.get("bestaetigung") or "")
    return render_template("teile/backupliste.html", **_seitendaten((art, text)))


@backup_seite.post("/backups/benachrichtigung")
@auth_required
@nur_eigene_oberflaeche
def benachrichtigung_speichern():
    art, text = backupdaten.benachrichtigung_setzen(
        request.form.get("thema") or "", request.form.get("server") or "")
    return render_template("teile/backupliste.html", **_seitendaten((art, text)))


@backup_seite.post("/backups/benachrichtigung/test")
@auth_required
@nur_eigene_oberflaeche
def benachrichtigung_test():
    """Der wichtigste Knopf auf dieser Seite.

    Eine Benachrichtigung, die nie ausprobiert wurde, ist keine — man
    erfährt sonst erst beim ersten echten Fehlschlag, dass die Kette nicht
    steht. Und dann ist es der Fehlschlag, den man gerade nicht mitbekommt.
    """
    art, text = backupdaten.benachrichtigung_testen()
    return render_template("teile/backupliste.html", **_seitendaten((art, text)))


@backup_seite.post("/backups/uhrzeit")
@auth_required
@nur_eigene_oberflaeche
def uhrzeit():
    """Die Backup-Uhrzeit ändern.

    Sie landet als Drop-in in /etc/systemd/system/mcs-backup.timer.d/ —
    nicht in der Einheit selbst, die gehört der Vorlage und würde beim
    nächsten ./deploy.sh ersetzt. Das ist der einzige Endpunkt der
    Oberfläche, der außerhalb von ~/mcs schreibt.
    """
    art, text = backupdaten.uhrzeit_setzen(request.form.get("uhrzeit") or "")
    return render_template("teile/backupliste.html", **_seitendaten((art, text)))


@backup_seite.post("/backups/zweitziel")
@auth_required
@nur_eigene_oberflaeche
def zweitziel():
    art, text = backupdaten.zweitziel_setzen(request.form.get("pfad") or "")
    return render_template("teile/backupliste.html", **_seitendaten((art, text)))
