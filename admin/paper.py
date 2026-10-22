#!/usr/bin/env python3
"""
paper.py — Welcher Paper-Build daliegt, und ob es einen neueren gibt.

Die Oberflaeche fragt PaperMC nicht selbst. Sie ruft dasselbe Skript wie
das Terminal (`paper-update.sh`, dort als `mcs update`) und liest danach
die zwei Notizen, die es schreibt:

    paper.installiert   was als paper.jar daliegt (version, build, sha256)
    paper.verfuegbar    was `--pruefen` zuletzt bei PaperMC gesehen hat

Damit gibt es eine Wahrheit und nicht zwei: Der Knopf zeigt genau das, was
`mcs update --pruefen` im Terminal sagt. Ein eigener API-Aufruf hier waere
der zweite Weg zur selben Sache, der die Regeln des ersten nicht kennt —
etwa, dass "verfuegbar" einen STABILEN Build meint (am 03.10.2026 hatte
26.3 bei PaperMC 143 Builds, alle Beta).

Nach aussen geht nur das Nachsehen, und nur auf Klick (Lastenheft 5.7.2).
Einen Wechsel der Minecraft-Version gibt es hier mit Absicht nicht: Er
wandelt die Welt endgueltig um und gehoert ins Terminal, wo man vorher
die Plugins prueft.
"""

from datetime import datetime
from pathlib import Path

from einstellungen import MCS_SERVER_DIR, MCS_SERVICE, UPDATE_SCRIPT, kv_lesen
from konsole import action_command
from system import run_command, service_state

INSTALLIERT = Path(MCS_SERVER_DIR) / "paper.installiert"
VERFUEGBAR = Path(MCS_SERVER_DIR) / "paper.verfuegbar"
JAR = Path(MCS_SERVER_DIR) / "paper.jar"


def _zahl(text):
    try:
        return int(text)
    except (TypeError, ValueError):
        return None


def _liste(text):
    return [v for v in (text or "").split(",") if v]


def _zeitpunkt(text):
    """ISO-Zeit aus der Notiz als "03.10.2026, 11:21" — oder leer."""
    try:
        return datetime.fromisoformat(text).strftime("%d.%m.%Y, %H:%M")
    except (TypeError, ValueError):
        return ""


def _laeuft_seit():
    """Seit wann der Minecraft-Dienst laeuft (Unix-Zeit), oder None."""
    code, aus, _ = run_command(["systemctl", "show", MCS_SERVICE, "-p",
                                "ActiveEnterTimestamp", "--timestamp=unix",
                                "--value"], timeout=5)
    if code == 0 and aus.startswith("@"):
        return _zahl(aus[1:])
    return None


def _neustart_noetig():
    """Liegt eine paper.jar da, die juenger ist als der laufende Server?

    Ein Update tauscht die Datei bei laufendem Server — Java haelt die alte
    offen und merkt nichts. Ohne diesen Hinweis stuende in der Oberflaeche
    der neue Build, waehrend der alte laeuft, und zwar bis zum naechsten
    Neustart, der vielleicht erst in Wochen kommt.
    """
    if service_state() != "active":
        return False
    seit = _laeuft_seit()
    try:
        return seit is not None and JAR.stat().st_mtime > seit
    except OSError:
        return False


def stand():
    """Alles, was die Tafel "Paper" zeigt — ohne Anfrage nach aussen."""
    installiert = kv_lesen(INSTALLIERT)
    notiz = kv_lesen(VERFUEGBAR)
    version = installiert.get("version") or ""
    build = _zahl(installiert.get("build"))

    # Eine Notiz zu einer anderen Minecraft-Version (geschrieben vor einem
    # Wechsel) beantwortet die Frage nicht mehr. Lieber "noch nicht
    # nachgesehen" als eine Antwort zur falschen Version.
    gilt = bool(notiz.get("geprueft")) and notiz.get("version") == version
    neuester = _zahl(notiz.get("neuester_build")) if gilt else None

    return {
        "version": version,
        "build": build,
        "geprueft": _zeitpunkt(notiz.get("geprueft")) if gilt else "",
        "neuester_build": neuester,
        "neuer_build": neuester if (neuester and build and neuester > build) else None,
        "neuere_stabil": _liste(notiz.get("neuere_stabil")) if gilt else [],
        "neuere_beta": _liste(notiz.get("neuere_beta")) if gilt else [],
        "neustart_noetig": _neustart_noetig(),
    }


def nachsehen():
    """Bei PaperMC nachsehen lassen. Liefert eine Meldung oder None.

    None heisst: hat geklappt, das Ergebnis steht jetzt in der Notiz und
    damit in stand(). Ohne Netz sagt die Tafel "nicht feststellbar" und
    zeigt weiter den letzten bekannten Stand — mit seinem Datum.
    """
    code, aus, fehler = run_command(["/usr/bin/bash", UPDATE_SCRIPT, "--pruefen"],
                                    timeout=180, cwd=MCS_SERVER_DIR)
    if code == 0:
        return None
    letzte = (fehler or aus or "").strip().splitlines()
    grund = f" ({letzte[-1]})" if letzte else ""
    return ("fehler", "PaperMC war nicht zu erreichen — ob es Neues gibt, ist "
                      f"gerade nicht feststellbar{grund}.")


def aktualisieren():
    """Neuesten Build derselben Minecraft-Version installieren.

    Liefert (meldung, ausgabe). Ob sich etwas getan hat, sagt der
    Merkzettel vorher und nachher — nicht das Lesen der Skriptausgabe, die
    sich beim naechsten Umformulieren stillschweigend aendern wuerde.
    """
    vorher = _zahl(kv_lesen(INSTALLIERT).get("build"))
    aktion = action_command("update_paper")
    code, aus, fehler = run_command(aktion["cmd"], timeout=aktion["timeout"],
                                    cwd=aktion["cwd"], protokoll="update_paper")
    nachher = _zahl(kv_lesen(INSTALLIERT).get("build"))
    ausgabe = "\n".join(t for t in (aus, fehler) if t)

    if code != 0:
        return (("fehler", "Das Update ist fehlgeschlagen. Woran, steht in der "
                           "Ausgabe darunter."), ausgabe)
    if nachher != vorher:
        return (("gut", f"Build {nachher} ist installiert. Wirksam wird er mit dem "
                        "nächsten Neustart; die bisherige Datei liegt als "
                        "paper.jar.vorher daneben."), ausgabe)
    return (("gut", "Nichts zu tun — der neueste stabile Build ist schon "
                    "installiert."), ausgabe)
