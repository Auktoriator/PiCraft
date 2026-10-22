#!/usr/bin/env python3
"""
netz.py — Erreichbarkeit von aussen.

Beantwortet die eine Frage, die eine Weboberflaeche im Heimnetz von sich
aus nicht beantworten kann: *Kommen meine Mitspieler ueberhaupt rein?*

DIE ARBEIT MACHT EIN SHELL-SKRIPT
---------------------------------
`tools/erreichbarkeit.sh` — und zwar dasselbe, das auch `install.sh` am
Ende aufruft und das hinter `mcs erreichbarkeit` steckt. Dieses Modul ruft
es mit `--json` auf und reicht das Ergebnis an die Vorlage weiter.

Warum nicht in Python nachbauen? Weil es dann zwei Fassungen derselben
Logik gaebe — eine fuer das Terminal, eine fuer den Browser — und die
beiden frueher oder spaeter verschiedene Antworten auf dieselbe Frage
geben. Genau diese Klasse Fehler steckte in Korrektur K8, nur an anderer
Stelle: Zwei Orte, an denen dasselbe gesucht wurde, und einer davon war
falsch.

NICHTS PASSIERT VON SELBST
--------------------------
Der Test verlaesst den Pi — anders laesst sich "bin ich von aussen
erreichbar" nicht beantworten. Gefragt werden checkipv4.dedyn.io /
checkipv6.dedyn.io (deSEC) und api.mcsrvstat.us.

Deshalb ruft die Seite beim Aufbau NICHTS nach aussen. Es braucht einen
Klick, und daneben steht, wer gefragt wird.
"""

import json
import os
import re

from einstellungen import MCS_DIR
from system import run_command

SKRIPT = os.getenv("MCS_ERREICHBARKEIT", f"{MCS_DIR}/erreichbarkeit.sh")


def _lauf(*parameter):
    """Ruft das Skript auf und gibt sein JSON zurueck — oder eine Erklaerung.

    Der Rueckgabewert des Skripts wird bewusst NICHT ausgewertet: 1 heisst
    dort "nicht erreichbar", und das ist eine Auskunft, kein Fehler. Ob
    etwas schiefging, steht daran, ob sich die Ausgabe lesen laesst.
    """
    if not os.path.isfile(SKRIPT):
        return {"fehler": f"{SKRIPT} fehlt. Einmal „./deploy.sh“ im "
                          "Repository laufen lassen."}

    # 90 Sekunden: Das Skript fragt bis zu drei Dienste im Internet, jeder
    # mit eigener Zeitgrenze. Ein zu knapper Wert bräche den Test genau
    # dann ab, wenn eine Leitung langsam ist — also im interessanten Fall.
    code, aus, fehler = run_command([SKRIPT, "--json", *parameter], timeout=90)
    try:
        return json.loads(aus)
    except (ValueError, TypeError):
        return {"fehler": (fehler or aus
                           or f"Der Test lieferte keine Antwort (Code {code}).")}


def lokal():
    """Was ohne jeden Zugriff nach aussen feststellbar ist."""
    return _lauf("--lokal")


def vollstaendig():
    """Der ganze Test, einschliesslich der Anfragen nach draussen."""
    return _lauf()


# ----------------------------------------------------------------------------
# Dauerhafter Name im Internet (DNS)
# ----------------------------------------------------------------------------
# Gehoert auf dieselbe Seite wie der Erreichbarkeitstest, und zwar direkt
# daneben: Der Test sagt, OB es geht, das DNS-Modul sorgt fuer den Namen,
# unter dem es geht. Wer das eine sucht, sucht kurz darauf das andere.
#
# Auch hier macht die Arbeit ein Shell-Skript (tools/dns-update.sh) — aus
# demselben Grund wie oben. Dieses Modul schreibt nur die Einstellungen und
# ruft das Skript auf.
DNS_SKRIPT = os.getenv("MCS_DNS_SKRIPT", f"{MCS_DIR}/dns-update.sh")

# Wo der Token liegt. NICHT in mcs.conf: Die wird von Shell, Python und
# systemd gelesen und hat entsprechend offene Rechte. Dasselbe Muster wie
# bei duckdns.env — und aus demselben Grund.
DNS_ENV = os.getenv("MCS_DNS_ENV", f"{MCS_DIR}/dns.env")

ANBIETER = {
    "": "aus",
    "desec": "deSEC",
    "duckdns": "DuckDNS",
}


def dns_zustand():
    """Was eingestellt ist, plus was zuletzt geschah."""
    if not os.path.isfile(DNS_SKRIPT):
        return {"fehler": f"{DNS_SKRIPT} fehlt. Einmal „./deploy.sh“ im "
                          "Repository laufen lassen.",
                "anbieter": "", "name": "", "zone": "", "token_da": False}
    code, aus, fehler = run_command([DNS_SKRIPT, "--json"], timeout=15)
    try:
        return json.loads(aus)
    except (ValueError, TypeError):
        return {"fehler": fehler or aus or f"Kein lesbarer Zustand (Code {code}).",
                "anbieter": "", "name": "", "zone": "", "token_da": False}


def dns_setzen(anbieter, name, zone, token):
    """Schreibt die DNS-Einstellungen — mcs.conf und dns.env getrennt."""
    import konfig
    anbieter = (anbieter or "").strip()
    name = (name or "").strip().lower().rstrip(".")
    zone = (zone or "").strip().lower().rstrip(".")
    token = (token or "").strip()

    if anbieter not in ANBIETER:
        return "fehler", "Unbekannter Anbieter."

    # Die Werte landen in mcs.conf, und die liest auch systemd. Ein
    # Leerzeichen oder ein Anfuehrungszeichen darin bringt beim naechsten
    # Dienststart Dateien zu Fall, die mit DNS nichts zu tun haben.
    for wert, was in ((name, "Der Name"), (zone, "Die Zone")):
        if wert and not re.fullmatch(r"[a-z0-9]([a-z0-9.-]{0,253}[a-z0-9])?", wert):
            return "fehler", (f"{was} darf nur Buchstaben, Ziffern, Punkt und "
                              "Bindestrich enthalten.")
    if anbieter and not name:
        return "fehler", "Ohne Namen geht es nicht — welcher Name soll auf diesen Server zeigen?"

    try:
        konfig.mcs_conf_setzen({"MCS_DNS_ANBIETER": anbieter,
                                "MCS_DNS_NAME": name,
                                "MCS_DNS_ZONE": zone})
    except ValueError as fehler:
        return "fehler", str(fehler)

    # Ein leeres Token-Feld heisst "nicht anfassen", nicht "loeschen": Das
    # Formular zeigt den Token nie an (er stuende sonst im Klartext im
    # Browser und in jedem Bildschirmfoto), also kaeme er bei jedem
    # Speichern leer zurueck — und wäre nach dem ersten Ändern eines
    # anderen Feldes weg.
    # Der Token landet in einer Datei, die dns-update.sh mit "." in die Shell
    # einbindet. Leerzeichen, Anfuehrungszeichen oder "$(" darin zerbraechen
    # den Updater oder fuehrten etwas aus. deSEC- und DuckDNS-Token bestehen
    # aus Buchstaben, Ziffern, "-" und "_" — mehr wird nicht angenommen.
    if token and not re.fullmatch(r"[A-Za-z0-9._-]+", token):
        return "fehler", ("Der Token darf nur Buchstaben, Ziffern, Punkt, "
                          "Binde- und Unterstrich enthalten.")
    if token:
        try:
            # Rechte VOR dem Schreiben, ueber konfig._schreiben: Der Dienst
            # laeuft mit UMask=0022 — bis zum 23.09.2026 lag der Token einer
            # NEU angelegten dns.env einen Moment lang weltlesbar auf der
            # Platte (siehe CLAUDE.md, "ob sie vor dem Schreiben gesetzt
            # werden").
            konfig._schreiben(DNS_ENV,
                              "# Zugangstoken für den DNS-Anbieter.\n"
                              "# Steht bewusst NICHT in mcs.conf: die wird von Shell,\n"
                              "# Python und systemd gelesen und ist entsprechend offen.\n"
                              f"MCS_DNS_TOKEN={token}\n", 0o600)
        except OSError as fehler:
            return "fehler", f"{DNS_ENV} ließ sich nicht schreiben: {fehler}"

    if not anbieter:
        return "gut", "DNS abgeschaltet. Der Name wird nicht mehr nachgeführt."
    return "gut", (f"Gespeichert. Der Timer meldet die Adresse ab jetzt alle "
                   f"fünf Minuten an {ANBIETER[anbieter]} — aber nur, wenn sie "
                   "sich geändert hat.")


def dns_melden():
    """Die Adresse sofort melden, ohne auf den Timer zu warten."""
    if not os.path.isfile(DNS_SKRIPT):
        return "fehler", f"{DNS_SKRIPT} fehlt."
    code, aus, fehler = run_command([DNS_SKRIPT, "--erzwingen"], timeout=60)
    if code == 0:
        return "gut", "Adresse gemeldet."
    return "fehler", fehler or aus or f"Fehlgeschlagen (Code {code})."


def dns_srv():
    """Den SRV-Eintrag anlegen (nur deSEC).

    Einmalig und auf Knopfdruck, nicht aus dem Timer: Der Eintrag aendert
    sich nicht, wenn sich die Adresse aendert.
    """
    if not os.path.isfile(DNS_SKRIPT):
        return "fehler", f"{DNS_SKRIPT} fehlt."
    code, aus, fehler = run_command([DNS_SKRIPT, "--srv"], timeout=60)
    if code == 0:
        return "gut", aus or "SRV-Eintrag gesetzt."
    # Den Text des Anbieters woertlich weitergeben. Eine eigene Deutung
    # waere hier geraten, und Raten hilft niemandem beim Beheben.
    return "fehler", fehler or aus or f"Fehlgeschlagen (Code {code})."
