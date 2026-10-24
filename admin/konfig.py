#!/usr/bin/env python3
"""
konfig.py — Konfigurationsdateien lesen und schreiben.

Das klingt einfacher, als es ist. Der Grund steht in Korrektur K3 des
Lastenhefts, gemessen am 28.08.2026 mit Paper 26.2 Build 119:

    Paper schreibt die server.properties neu, sobald ein Befehl eine dort
    gespeicherte Einstellung aendert -- und zwar die GANZE Datei, aus dem
    Arbeitsspeicher.

Gemessen sah das so aus: motd von Hand auf einen Merkwert gesetzt, danach
ein "whitelist on" ueber RCON geschickt, und motd stand wieder auf dem
alten Wert. Ein Operator, der im Spiel "/whitelist add" tippt, loest
dasselbe aus. Wer bei laufendem Server in diese Datei schreibt, kann seine
Aenderung also jederzeit verlieren -- ohne Fehlermeldung, ohne Hinweis.

Fuer die YAML-Dateien gilt das NICHT. Auch das ist gemessen: Werte, die bei
laufendem Server geaendert wurden, ueberlebten Stopp und Start. Paper
schreibt sie zwar beim Start neu, behaelt dabei aber Werte und die eigenen
Kommentare der Datei.

Daraus die drei Regeln dieses Moduls:

    Server steht                  -> direkt schreiben
    Server laeuft, YAML           -> direkt schreiben, wirkt beim naechsten Start
    Server laeuft, .properties    -> VORMERKEN

Vorgemerkt wird die vollstaendige neue Fassung der Datei, nicht ein
Unterschied. Kein selbst erfundenes Patch-Format, keine Zusammenfuehrung
zweier Staende -- start-minecraft.sh muss sie nur an ihren Platz schieben,
und die Anzeige des Unterschieds ist ein Zweizeiler.
"""

import os
import re
import shutil
import time
from pathlib import Path

from einstellungen import (MCS_DIR, MCS_SERVER_DIR, SERVER_PROPERTIES,
                           kv_aus_text, kv_lesen)
from system import service_state

# ----------------------------------------------------------------------------
# Welche Dateien ueberhaupt angefasst werden duerfen
# ----------------------------------------------------------------------------
# Eine feste Liste, kein Pfad aus der Adresszeile. Sonst liesse sich mit
# "../../.ssh/authorized_keys" jede Datei des Benutzers oeffnen, der den
# Server betreibt.
#
# "geheim" zaehlt die Schluessel auf, deren Werte nie im Klartext an den
# Browser gehen. Die Regel dazu steht in Korrektur K2 des Lastenhefts: Jeder
# neue Editor muss vorher geprueft werden, ob dort ein Geheimnis stehen
# kann. Fuer diese fuenf Dateien ist das am 28.08.2026 getan worden --
# gefunden wurden das RCON-Passwort und der Velocity-Schluessel in
# paper-global.yml (Korrektur K5).
DATEIEN = {
    "server.properties": {
        "pfad": lambda: SERVER_PROPERTIES,
        "art": "properties",
        # Die beiden management-server-Schluessel kamen mit Minecraft
        # 1.21.9, also NACH der Pruefung vom 28.08. -- bis zum 21.10.2026
        # zeigte der Editor das 40-stellige Geheimnis im Klartext. Merksatz:
        # Die Liste gilt fuer eine Minecraft-Version, nicht fuer immer.
        "geheim": ("rcon.password", "management-server-secret",
                   "management-server-tls-keystore-password"),
        "titel": "server.properties",
        "hinweis": ("Paper schreibt diese Datei beim Start neu und entfernt "
                    "dabei alle Kommentare. Eigene Notizen darin überleben "
                    "den nächsten Neustart nicht."),
    },
    "bukkit.yml": {
        "pfad": lambda: f"{MCS_SERVER_DIR}/bukkit.yml",
        "art": "yaml",
        "geheim": (),
        "titel": "bukkit.yml",
        "hinweis": "Spawn-Limits und Tickraten für Kreaturen.",
    },
    "spigot.yml": {
        "pfad": lambda: f"{MCS_SERVER_DIR}/spigot.yml",
        "art": "yaml",
        "geheim": (),
        "titel": "spigot.yml",
        "hinweis": "Aktivierungsradien, Zusammenlegen von Gegenständen.",
    },
    "paper-global.yml": {
        "pfad": lambda: f"{MCS_SERVER_DIR}/config/paper-global.yml",
        "art": "yaml",
        # Gemessen am 28.08.2026, Zeile 119: "secret: ''" -- der
        # Velocity-Proxy-Schluessel. Im Auslieferungszustand leer, aber wer
        # je einen Proxy einrichtet, hat dort ein Geheimnis stehen.
        "geheim": ("secret",),
        "titel": "paper-global.yml",
        "hinweis": "Chunk-Pipeline, Netzwerk, Proxy-Einstellungen.",
    },
    "paper-world-defaults.yml": {
        "pfad": lambda: f"{MCS_SERVER_DIR}/config/paper-world-defaults.yml",
        "art": "yaml",
        "geheim": (),
        "titel": "paper-world-defaults.yml",
        # Hier stand "341 Zeilen". Gemessen am 23.09.2026: Vorlage 344, die von
        # Paper geschriebene Live-Datei 323 -- keine der beiden. Eine Zahl, die
        # jede Kommentarzeile in der Vorlage verschiebt, gehoert nicht hierher.
        "hinweis": "Über 300 Zeilen Feinjustierung je Welt. Hier nur ändern, "
                   "was man nachgeschlagen hat.",
    },
}

PLATZHALTER = "********"


def datei_info(name):
    """Die Beschreibung einer erlaubten Datei — oder None."""
    return DATEIEN.get(name)


def datei_pfad(name):
    info = DATEIEN.get(name)
    return info["pfad"]() if info else None


# ----------------------------------------------------------------------------
# Die kuratierte Einstellungsliste
# ----------------------------------------------------------------------------
# Lastenheft O3, entschieden am 28.08.2026: fuenfzehn Werte hier, vier auf
# der Leistungsseite. Nicht mehr -- `paper-world-defaults.yml` allein hat
# 341 Zeilen, und ein Formular je Schluessel je Datei waere Wochenarbeit,
# die bei jedem Paper-Update bricht. Wer mehr will, nimmt den
# Expertenmodus.
#
# Jeder Eintrag traegt seine eigene Erklaerung. Das ist der eigentliche
# Zweck dieser Seite: Nicht "difficulty: [easy]", sondern der Satz daneben,
# der sagt, was passiert, wenn man daran dreht.
#
# `weg` sagt, WIE geschrieben wird:
#   "datei"  in die server.properties (ggf. vorgemerkt, siehe K3)
#   "rcon"   ueber einen Serverbefehl -- fuer Werte, bei denen die Datei
#            nicht die Wahrheit ist. Siehe difficulty und white-list.
EINSTELLUNGEN = [
    {
        "schluessel": "difficulty", "standard": "easy", "titel": "Schwierigkeit", "art": "auswahl",
        "weg": "rcon", "befehl": "difficulty {wert}", "frage": "difficulty",
        "optionen": [("peaceful", "friedlich — keine Monster"),
                     ("easy", "einfach"),
                     ("normal", "normal"),
                     ("hard", "schwer")],
        "erklaerung": (
            "Wie gefährlich die Welt ist. <strong>Dieser Wert steht in der "
            "Welt, nicht in der server.properties</strong> — der Eintrag dort "
            "zählt nur, wenn eine Welt neu erzeugt wird. Am 28.08.2026 "
            "nachgemessen: Die Datei auf „hard“ zu setzen und den Server neu "
            "zu starten ändert gar nichts. Deshalb geht diese Einstellung "
            "über einen Serverbefehl und wirkt sofort."),
    },
    {
        "schluessel": "gamemode", "standard": "survival", "titel": "Spielmodus für neue Spieler",
        "art": "auswahl", "weg": "datei",
        "optionen": [("survival", "Survival — sammeln, bauen, überleben"),
                     ("creative", "Kreativ — alles verfügbar, fliegen"),
                     ("adventure", "Abenteuer — nur mit passendem Werkzeug abbauen"),
                     ("spectator", "Zuschauer — nur zusehen")],
        "erklaerung": ("Womit jemand startet, der zum ersten Mal verbindet. "
                       "Wer schon einmal da war, behält seinen Modus."),
    },
    {
        "schluessel": "pvp", "standard": "true", "titel": "Spieler gegen Spieler", "art": "schalter",
        "weg": "datei",
        "erklaerung": "Ob Spieler einander Schaden zufügen können.",
    },
    # "Monster erscheinen" (spawn-monsters) stand hier bis zum 02.09.2026 und
    # ist entfernt worden, weil Paper 26.2 den Schluessel nicht mehr kennt:
    # Der Schalter haette geschrieben, Paper haette den Wert beim naechsten
    # Start weggeworfen, und die Oberflaeche haette ihn beim naechsten Aufruf
    # wieder als "aus" angezeigt — ein Schalter, der etwas behauptet, was er
    # nicht weiss. Genau der Anlass fuer v1.1. Wer keine Monster will, stellt
    # die Schwierigkeit auf "friedlich"; das ist heute der Weg dorthin.
    {
        "schluessel": "hardcore", "standard": "false", "titel": "Hardcore", "art": "schalter",
        "weg": "datei", "warnung": True,
        "erklaerung": ("<strong>Vorsicht.</strong> Wer stirbt, ist dauerhaft "
                       "gesperrt und kommt nicht wieder auf den Server. Das "
                       "lässt sich nur von Hand rückgängig machen."),
    },
    {
        "schluessel": "allow-nether", "standard": "true", "titel": "Nether erreichbar",
        "art": "schalter", "weg": "datei",
        "erklaerung": ("Ob Portale in den Nether führen. Aus spart etwas "
                       "Speicher und Plattenplatz."),
    },
    {
        "schluessel": "allow-flight", "standard": "false", "titel": "Fliegen erlauben",
        "art": "schalter", "weg": "datei",
        "erklaerung": ("Verhindert, dass Spieler mit Elytren oder auf einem "
                       "schnellen Server fälschlich hinausgeworfen werden. "
                       "Das ist <em>keine</em> Erlaubnis zum Kreativflug."),
    },
    {
        "schluessel": "enable-command-block", "standard": "false", "titel": "Kommandoblöcke",
        "art": "schalter", "weg": "datei",
        "erklaerung": ("Ob Kommandoblöcke funktionieren. Sie können viel — "
                       "auch viel Rechenzeit verbrauchen."),
    },
    {
        "schluessel": "op-permission-level", "standard": "4", "titel": "Stufe für neue Operatoren",
        "art": "zahl", "weg": "datei", "min": 1, "max": 4,
        "erklaerung": (
            "Welche Stufe jemand bekommt, den man zum Operator macht. "
            "1 darf den Bauschutz umgehen, 2 zusätzlich Spielbefehle wie "
            "<code>/gamemode</code> und Kommandoblöcke, 3 zusätzlich Spieler "
            "hinauswerfen und sperren, 4 alles — auch <code>/stop</code>. "
            "<strong>Dieser Wert gilt nur für neue Operatoren.</strong> Wer "
            "schon einer ist, behält seine Stufe; die ändert man auf der "
            "Spielerseite, und zwar nur bei gestopptem Server."),
    },
    {
        "schluessel": "spawn-protection", "standard": "16", "titel": "Bauschutz um den Spawn",
        "art": "zahl", "weg": "datei", "min": 0, "max": 64, "einheit": "Blöcke",
        "erklaerung": ("In diesem Umkreis um den Startpunkt dürfen nur "
                       "Operatoren bauen. 0 schaltet den Schutz ab."),
    },
    {
        "schluessel": "max-players", "standard": "20", "titel": "Höchstzahl Spieler",
        "art": "zahl", "weg": "datei", "min": 1, "max": 20,
        "erklaerung": ("Dieses Projekt ist auf fünf gleichzeitige Spieler "
                       "ausgelegt, höchstens zehn. Mehr schafft ein Pi nicht "
                       "ruckelfrei."),
    },
    {
        "schluessel": "white-list", "standard": "false", "titel": "Whitelist", "art": "schalter",
        "weg": "rcon", "befehl": "whitelist {an_aus}",
        "erklaerung": ("Nur eingeladene Spieler dürfen verbinden. "
                       "<strong>Pflicht, wenn der Port ins Internet "
                       "freigegeben ist.</strong> Wer darauf steht, steht auf "
                       "der Spielerseite. Dieser Schalter wirkt sofort — der "
                       "Server schreibt die Datei dabei selbst."),
    },
    {
        "schluessel": "online-mode", "standard": "true", "titel": "Echtheitsprüfung bei Mojang",
        "art": "schalter", "weg": "datei", "warnung": True,
        "erklaerung": ("<strong>Niemals abschalten, wenn der Server aus dem "
                       "Internet erreichbar ist.</strong> Ohne diese Prüfung "
                       "kann sich jeder mit einem beliebigen Namen anmelden — "
                       "auch mit deinem."),
    },
    {
        "schluessel": "motd", "standard": "A Minecraft Server", "titel": "Begrüßungstext", "art": "text",
        "weg": "datei", "laenge": 59,
        "erklaerung": ("Was in der Serverliste unter dem Namen steht. "
                       "§-Codes färben: <code>§2</code> dunkelgrün, "
                       "<code>§l</code> fett, <code>§r</code> zurücksetzen."),
    },
    {
        "schluessel": "server-port", "standard": "25565", "titel": "Port des Spielservers",
        "art": "zahl", "weg": "datei", "min": 1024, "max": 65535,
        "erklaerung": ("Nur ändern, wenn es einen Grund gibt. Danach müssen "
                       "die Freigabe im Router und die Firewall-Regel "
                       "nachgezogen werden, sonst kommt niemand mehr herein."),
    },
    {
        "schluessel": "pause-when-empty-seconds", "standard": "60", "titel": "Pause, wenn leer",
        "art": "zahl", "weg": "datei", "min": 0, "max": 3600, "einheit": "Sekunden",
        "erklaerung": ("Nach so vielen Sekunden ohne Spieler hält der Server "
                       "die Welt an. Spart Strom und Rechenzeit; beim nächsten "
                       "Verbinden geht es sofort weiter. 0 schaltet es ab."),
    },
]

WAHR = {"true", "1", "yes", "on"}


def einstellung(schluessel):
    for e in EINSTELLUNGEN:
        if e["schluessel"] == schluessel:
            return e
    return None


# ----------------------------------------------------------------------------
# Vormerkungen
# ----------------------------------------------------------------------------
def vormerk_verzeichnis():
    return os.getenv("MCS_VORGEMERKT_DIR", f"{MCS_DIR}/vorgemerkt")


def _vormerk_datei(name):
    """Wo die vorgemerkte Fassung einer Datei liegt.

    Der Dateiname traegt den Pfad in sich: aus "config/paper-global.yml"
    wird "config__paper-global.yml". So braucht start-minecraft.sh keine
    zweite Liste, die mit dieser hier auseinanderlaufen koennte -- es
    macht die Ersetzung schlicht rueckwaerts.
    """
    return os.path.join(vormerk_verzeichnis(), name.replace("/", "__"))


def server_laeuft():
    # frisch=True: Von dieser Antwort haengt ab, ob server.properties
    # geschrieben oder vorgemerkt wird (Korrektur K3). Ein veralteter Wert
    # hiesse hier, bei laufendem Server zu schreiben — und die Aenderung
    # verschwaende lautlos.
    return service_state(frisch=True) == "active"


def muss_vorgemerkt_werden(name):
    """Darf jetzt direkt geschrieben werden, oder muss vorgemerkt werden?

    Nur die .properties-Dateien und nur bei laufendem Server. Fuer YAML
    waere eine Vormerkung ein Bauteil ohne Zweck -- siehe Kopfkommentar.
    """
    info = DATEIEN.get(name)
    return bool(info) and info["art"] == "properties" and server_laeuft()


def _schreiben(pfad, inhalt, rechte):
    """Schreibt eine Datei, die ihre Rechte SCHON BEIM ANLEGEN traegt.

    write_text() legt mit der umask an — beim Dienst mcs-admin 0022, also
    weltlesbar — und ein chmod danach laesst immer eine Luecke. Hier steht
    oft das RCON-Passwort drin (server.properties). Dieselbe Vorkehrung wie
    in historie.verbindung() und netz.dns_setzen().
    """
    fd = os.open(pfad, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, rechte)
    with os.fdopen(fd, "w", encoding="utf-8") as datei:
        datei.write(inhalt)
    # Lag die Datei schon da (etwa eine Leiche von frueher), hat os.open ihre
    # alten Rechte gelassen.
    os.chmod(pfad, rechte)


def vormerken(name, inhalt):
    """Legt die vollstaendige neue Fassung fuer den naechsten Start ab.

    Mit 0600: Eine vorgemerkte server.properties enthaelt das RCON-Passwort
    und bleibt liegen, bis der Server das naechste Mal startet — unter
    Umstaenden Tage. Bis zum 23.09.2026 lag sie dort mit 0644 (gemessen).
    start-minecraft.sh kopiert sie per cp in die bestehende Zieldatei, deren
    Rechte dabei erhalten bleiben.
    """
    os.makedirs(vormerk_verzeichnis(), mode=0o700, exist_ok=True)
    _schreiben(_vormerk_datei(name), inhalt, 0o600)


def vormerkung(name):
    """Der vorgemerkte Inhalt — oder None."""
    pfad = Path(_vormerk_datei(name))
    if not pfad.is_file():
        return None
    try:
        return pfad.read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return None


def _geltender_stand(name):
    """Was beim naechsten Start gilt: die Vormerkung, sonst die Datei.

    Darauf wird weitergearbeitet, nicht auf der Datei: Sonst ginge eine
    Aenderung verloren, sobald eine zweite sie nicht sieht. Die Einstellungs-
    seite tat das seit Etappe C, der Expertenmodus bis zum 24.10.2026 nicht —
    er zeigte die Datei, und sein Speichern ueberschrieb die Vormerkung.
    Wirft OSError, wenn keins von beiden lesbar ist.
    """
    vorgemerkt = vormerkung(name)
    if vorgemerkt is not None:
        return vorgemerkt
    return Path(datei_pfad(name)).read_text(encoding="utf-8", errors="ignore")


def vormerkung_verwerfen(name):
    try:
        os.remove(_vormerk_datei(name))
        return True
    except OSError:
        return False


def vorgemerkte():
    """Alle Vormerkungen, als Liste von (name, unterschiede).

    Die Oberflaeche zeigt damit "3 Änderungen warten auf den nächsten
    Neustart" — und zwar sichtbar, nicht versteckt. Das verlangt das
    Lastenheft in 5.7.3 ausdruecklich.
    """
    verzeichnis = Path(vormerk_verzeichnis())
    if not verzeichnis.is_dir():
        return []

    ergebnis = []
    for datei in sorted(verzeichnis.iterdir()):
        if not datei.is_file():
            continue
        name = datei.name.replace("__", "/")
        if name not in DATEIEN:
            # Etwas, das nicht in der Liste steht — nicht anfassen, aber
            # auch nicht verschweigen.
            ergebnis.append({"name": name, "unbekannt": True, "zeilen": []})
            continue
        ergebnis.append({
            "name": name,
            "unbekannt": False,
            "zeilen": unterschiede(name),
        })
    return ergebnis


def unterschiede(name):
    """Was die Vormerkung gegenueber der jetzigen Datei aendert.

    Absichtlich kein voller Diff mit Zusammenhang: Bei einer Datei aus
    Schluessel-Wert-Zeilen ist "diese drei Werte werden anders" die
    Auskunft, die man braucht.
    """
    neu = vormerkung(name)
    if neu is None:
        return []
    info = DATEIEN.get(name)
    if not info or info["art"] != "properties":
        return []

    alt_werte = properties_lesen(info["pfad"]())
    neu_werte = properties_aus_text(neu)

    zeilen = []
    for schluessel in sorted(set(alt_werte) | set(neu_werte)):
        vorher = alt_werte.get(schluessel)
        nachher = neu_werte.get(schluessel)
        if vorher == nachher:
            continue
        if schluessel in info["geheim"]:
            vorher = nachher = PLATZHALTER
        zeilen.append({"schluessel": schluessel,
                       "vorher": vorher, "nachher": nachher})
    return zeilen


# ----------------------------------------------------------------------------
# properties-Dateien
# ----------------------------------------------------------------------------
# Eine properties-Datei ist KEY=WERT, und die Schleife dafuer steht seit dem
# 2026-09-02 nur noch einmal im Programm (einstellungen.kv_aus_text). Die
# beiden Namen hier bleiben: Sie sagen am Aufrufort, WELCHES Format gemeint
# ist, und vier Aufrufer sowie der Abnahmetest benutzen sie.
#
# Ohne Anfuehrungszeichen-Behandlung, anders als bei mcs.conf: In einer
# server.properties gehoert ein Anfuehrungszeichen zum Wert.
properties_aus_text = kv_aus_text
properties_lesen = kv_lesen


def _properties_ersetzen(text, aenderungen):
    """Setzt Werte in einer properties-Datei, ohne den Rest anzufassen.

    Zeilenweise und nicht ueber ein neu geschriebenes dict: Die Datei
    enthaelt Schluessel, die diese Oberflaeche gar nicht kennt (Paper
    ergaenzt bei jedem Versionswechsel welche). Wer sie aus einem dict neu
    schreibt, wirft alles weg, was er nicht kennt.
    """
    offen = dict(aenderungen)
    zeilen = []
    for zeile in text.splitlines(keepends=True):
        nackt = zeile.strip()
        if nackt and not nackt.startswith("#") and "=" in nackt:
            schluessel = nackt.split("=", 1)[0].strip()
            if schluessel in offen:
                ende = "\n" if zeile.endswith("\n") else ""
                zeile = f"{schluessel}={offen.pop(schluessel)}{ende}"
        zeilen.append(zeile)

    # Was es noch gar nicht gab, kommt ans Ende.
    if offen:
        if zeilen and not zeilen[-1].endswith("\n"):
            zeilen.append("\n")
        for schluessel, wert in offen.items():
            zeilen.append(f"{schluessel}={wert}\n")
    return "".join(zeilen)


def datei_ersetzen(pfad, inhalt):
    """Schreibt eine Datei so, dass es sie nie halb gibt.

    Ein `write_text()` kuerzt die Zieldatei zuerst auf null und schreibt dann.
    Faellt in diesem Moment der Strom aus oder holt der OOM-Killer den
    mcs-admin-Dienst, bleibt eine abgeschnittene Datei liegen: Paper liest
    beim naechsten Start alles bis zur Bruchstelle und verliert den Rest
    lautlos -- oder startet gar nicht mehr.

    Stattdessen daneben schreiben und umbenennen. os.replace ist innerhalb
    desselben Dateisystems atomar: Wer zusieht, sieht entweder den alten oder
    den neuen Inhalt, nie etwas dazwischen. Genau dieselbe Vorkehrung wie der
    Zwischenname ".unfertig-backup_*" in minecraft-backup.sh und wie
    mktemp + mv in setze_zeile() (install.sh) -- hier hatte sie gefehlt.

    Die Rechte der Zieldatei werden uebernommen: server.properties steht auf
    600, weil das RCON-Passwort darin steht. Eine frische Temp-Datei haette
    die Rechte der umask, und das Passwort laege weltlesbar. (Bis zum
    23.09.2026 wurde erst geschrieben und DANN chmod gesetzt — genau diese
    Luecke, nur kuerzer. Jetzt traegt die Temp-Datei die Rechte ab dem
    Anlegen, siehe _schreiben.)
    """
    ziel = Path(pfad)
    temp = ziel.with_name(f".{ziel.name}.neu-{os.getpid()}")
    try:
        rechte = ziel.stat().st_mode & 0o777
    except OSError:
        rechte = 0o600
    try:
        _schreiben(temp, inhalt, rechte)
        os.replace(temp, ziel)
    except OSError:
        try:
            temp.unlink()
        except OSError:
            pass
        raise
    return str(ziel)


def sicherung_anlegen(pfad, hoechstens=5):
    """Legt eine Sicherungskopie mit Zeitstempel an und raeumt alte ab."""
    ziel = f"{pfad}.bak-{time.strftime('%Y%m%d-%H%M%S')}"
    try:
        shutil.copy2(pfad, ziel)
    except OSError:
        return None
    kopien = sorted(Path(pfad).parent.glob(Path(pfad).name + ".bak-*"),
                    reverse=True)
    for alt in kopien[hoechstens:]:
        try:
            alt.unlink()
        except OSError:
            pass
    return ziel


def properties_setzen(name, aenderungen):
    """Setzt Werte in einer properties-Datei — direkt oder vorgemerkt.

    Liefert ein dict mit `vorgemerkt` (bool) und `datei`. Der Aufrufer
    muss dem Benutzer sagen, was davon passiert ist — eine Aenderung, die
    erst beim naechsten Neustart wirkt, aber wie sofort erledigt aussieht,
    ist genau die Sorte Halbwahrheit, die spaeter Zeit kostet.
    """
    info = DATEIEN.get(name)
    if not info or info["art"] != "properties":
        raise ValueError(f"{name} ist keine bearbeitbare properties-Datei.")

    pfad = info["pfad"]()

    try:
        grundlage = _geltender_stand(name)
    except OSError as fehler:
        raise ValueError(f"{pfad} lässt sich nicht lesen: {fehler}") from fehler

    neu = _properties_ersetzen(grundlage, aenderungen)

    if muss_vorgemerkt_werden(name):
        vormerken(name, neu)
        return {"vorgemerkt": True, "datei": pfad}

    sicherung_anlegen(pfad)
    datei_ersetzen(pfad, neu)
    # Eine Vormerkung, die jetzt ohnehin geschrieben wurde, waere doppelt.
    vormerkung_verwerfen(name)
    return {"vorgemerkt": False, "datei": pfad}


# ----------------------------------------------------------------------------
# mcs.conf
# ----------------------------------------------------------------------------
# Die zentralen Einstellungen des Pi. Sie gehoeren NICHT Paper, also gilt
# die Vormerk-Regel hier nicht -- wohl aber eine andere: Gelesen wird die
# Datei beim Start der Dienste, eine Aenderung wirkt also erst nach
# "mcs restart".
#
# Format: reine KEY=WERT-Zeilen ohne Leerzeichen um das Gleichheitszeichen,
# weil Shell, Python UND systemd sie lesen muessen (siehe mcs.conf.beispiel).
_MCS_CONF_ZEILE = re.compile(r"^([A-Za-z_][A-Za-z0-9_]*)=(.*)$")

# Werte, die ohne Anfuehrungszeichen auskommen: alles, was keine Sonderbedeutung
# fuer die Shell hat. Alles andere wird in EINFACHE Anfuehrungszeichen gesetzt.
_HARMLOSER_WERT = re.compile(r"^[A-Za-z0-9_./:@%+,=-]*$")


def mcs_conf_pfad():
    return os.getenv("MCS_CONF", f"{MCS_DIR}/mcs.conf")


def _wert_entkleiden(wert):
    """Nimmt die Anfuehrungszeichen wieder ab, die mcs_conf_setzen setzt.

    Shell und systemd tun das von sich aus; Python muss es nachmachen, sonst
    kaeme der Pfad hier mit Anfuehrungszeichen an und keine Datei liesse sich
    oeffnen.
    """
    if len(wert) >= 2 and wert[0] == wert[-1] and wert[0] in "'\"":
        return wert[1:-1]
    return wert


def wert_fuer_mcs_conf(wert):
    """Bereitet einen Wert so auf, dass ihn alle drei Leser gleich verstehen.

    Die mcs.conf wird von der Shell (`. mcs.conf`), von systemd
    (`EnvironmentFile=`, sechs Einheiten) und von Python gelesen. Ein Wert mit
    Leerzeichen -- etwa der voellig gewoehnliche Einhaengepunkt
    "/media/pi/My Passport" -- zerlegte die Shell bisher in zwei Woerter und
    versuchte das zweite als Befehl auszufuehren:

        MCS_EXTERN_DIR=/media/pi/My Passport
        -> "Passport: command not found", Rueckgabewert 127

    Unter "set -euo pipefail" starb daran JEDES Backup, und zwar in der
    Source-Zeile ganz oben -- vor dem EXIT-trap, vor fehler_merken und vor dem
    Merkzettel. Also vollkommen lautlos. Ausgeloest wurde es durch einen Klick
    im Feld "Zweitziel" dieser Oberflaeche.

    Gemessen am 2026-08-31, weil die naheliegende Loesung die falsche ist:

        'wert'   Shell nimmt es woertlich, systemd auch.          richtig
        "wert"   systemd nimmt es woertlich, die Shell aber NICHT:
                 MCS_X="/pfad/$(id -un)" fuehrt beim Einlesen id aus.
                 Aus der Reparatur wuerde eine Befehlsausfuehrung
                 ueber ein Webformular.

    Deshalb einfache Anfuehrungszeichen. Ein einfaches Anfuehrungszeichen IM
    Wert laesst sich darin nicht unterbringen (bash und systemd escapen
    unterschiedlich), ebenso wenig ein Zeilenumbruch -- beides wird abgelehnt
    statt halb richtig geschrieben.
    """
    wert = str(wert)
    if "\n" in wert or "\r" in wert:
        raise ValueError("Ein Wert darf keinen Zeilenumbruch enthalten.")
    if "'" in wert:
        raise ValueError(
            "Ein Wert darf kein einfaches Anführungszeichen (') enthalten — "
            "Shell und systemd lesen es unterschiedlich.")
    if _HARMLOSER_WERT.match(wert):
        return wert
    return "'" + wert + "'"


def mcs_conf_lesen():
    werte = {}
    try:
        for zeile in Path(mcs_conf_pfad()).read_text(
                encoding="utf-8", errors="ignore").splitlines():
            treffer = _MCS_CONF_ZEILE.match(zeile.strip())
            if treffer:
                werte[treffer.group(1)] = _wert_entkleiden(treffer.group(2))
    except OSError:
        pass
    return werte


def mcs_conf_setzen(aenderungen):
    """Setzt Werte in der mcs.conf. Wirkt erst nach `mcs restart`."""
    pfad = mcs_conf_pfad()
    try:
        text = Path(pfad).read_text(encoding="utf-8", errors="ignore")
    except OSError as fehler:
        raise ValueError(f"{pfad} lässt sich nicht lesen: {fehler}") from fehler

    # Erst ALLE Werte pruefen, dann schreiben. Sonst stuende nach einer
    # abgelehnten Aenderung die Haelfte schon in der Datei.
    offen = {s: wert_fuer_mcs_conf(w) for s, w in aenderungen.items()}

    zeilen = []
    for zeile in text.splitlines(keepends=True):
        treffer = _MCS_CONF_ZEILE.match(zeile.strip())
        if treffer and treffer.group(1) in offen:
            ende = "\n" if zeile.endswith("\n") else ""
            zeilen.append(f"{treffer.group(1)}={offen.pop(treffer.group(1))}{ende}")
        else:
            zeilen.append(zeile)
    if offen:
        if zeilen and not zeilen[-1].endswith("\n"):
            zeilen.append("\n")
        for schluessel, wert in offen.items():
            zeilen.append(f"{schluessel}={wert}\n")

    sicherung_anlegen(pfad)
    datei_ersetzen(pfad, "".join(zeilen))
    return pfad


# ----------------------------------------------------------------------------
# Die kuratierten Werte lesen
# ----------------------------------------------------------------------------
def _rcon():
    """rcon nur bei Bedarf laden.

    konfig.py wird auch von `mcs status` benutzt; ein fehlgeschlagener
    Import soll dort nichts kaputt machen.
    """
    try:
        import rcon
        return rcon
    except ImportError:  # pragma: no cover
        return None


def _difficulty_vom_server():
    """Was der Server über die Weltschwierigkeit sagt.

    Gemessen am 28.08.2026 (Korrektur K7): Der Wert in der
    server.properties zählt nur beim ERZEUGEN einer Welt. Danach steht die
    Schwierigkeit in der Welt selbst, und die Datei wird beim Start
    schlicht ignoriert -- "difficulty=hard" hineinzuschreiben und neu zu
    starten ändert gar nichts.

    Deshalb wird hier gefragt statt gelesen. Antwortformat:
    'The difficulty is Easy'.
    """
    rcon = _rcon()
    if rcon is None or not rcon.verfuegbar() or service_state() != "active":
        return None
    try:
        antwort = rcon.befehl("difficulty")
    except Exception:
        return None
    treffer = re.search(r"difficulty is (\w+)", antwort or "", re.IGNORECASE)
    return treffer.group(1).lower() if treffer else None


def einstellungen_lesen():
    """Der aktuelle Stand aller kuratierten Werte, fertig für die Anzeige."""
    werte = properties_lesen(SERVER_PROPERTIES)
    # Eine Vormerkung ist der Stand, der GELTEN WIRD. Sie zu verschweigen
    # hiesse, jemandem den alten Wert zu zeigen, den er gerade geändert hat.
    vorgemerkt_text = vormerkung("server.properties")
    vorgemerkt = properties_aus_text(vorgemerkt_text) if vorgemerkt_text else {}

    laeuft = server_laeuft()
    schwierigkeit = _difficulty_vom_server()

    ergebnis = []
    for e in EINSTELLUNGEN:
        schluessel = e["schluessel"]

        standard = e.get("standard", "")

        if schluessel == "difficulty":
            wert = schwierigkeit or werte.get(schluessel) or standard
            quelle = "server" if schwierigkeit else (
                "datei" if schluessel in werte else "standard")
        elif schluessel in vorgemerkt:
            wert, quelle = vorgemerkt[schluessel], "vorgemerkt"
        elif schluessel in werte:
            wert, quelle = werte[schluessel], "datei"
        else:
            # Fehlt der Schluessel, gilt Minecrafts Vorgabe -- NICHT "leer"
            # und schon gar nicht "aus". Aufgefallen am 28.08.2026: Ohne
            # diesen Zweig zeigte die Seite fuer allow-nether "aus", obwohl
            # der Nether in Wirklichkeit offen ist.
            #
            # Auf einem echten Server kommt das selten vor -- Paper schreibt
            # beim ersten Start alle Schluessel hinein. Aber "selten" ist
            # kein Grund, in dem Fall etwas Falsches anzuzeigen.
            wert, quelle = standard, "standard"

        eintrag = dict(e)
        eintrag["wert"] = wert
        eintrag["an"] = str(wert).lower() in WAHR
        eintrag["quelle"] = quelle
        # Ein Wert, den man ohne laufenden Server gar nicht setzen kann.
        eintrag["gesperrt"] = e["weg"] == "rcon" and not laeuft
        ergebnis.append(eintrag)
    return ergebnis


def einstellung_setzen(schluessel, roh):
    """Setzt einen kuratierten Wert. Liefert (art, meldung).

    Gibt absichtlich je Wert einzeln Auskunft: "gespeichert",
    "vorgemerkt" und "sofort wirksam" sind drei verschiedene Dinge, und
    wer sie zusammenfasst, erzählt zwei Dritteln der Fälle eine
    Halbwahrheit.
    """
    e = einstellung(schluessel)
    if e is None:
        return "fehler", f"„{schluessel}“ steht nicht in der Liste."

    # --- Wert prüfen ---
    if e["art"] == "schalter":
        wert = "true" if str(roh).lower() in WAHR else "false"
    elif e["art"] == "zahl":
        try:
            zahl = int(str(roh).strip())
        except (TypeError, ValueError):
            return "fehler", f"{e['titel']}: „{roh}“ ist keine Zahl."
        if not e["min"] <= zahl <= e["max"]:
            return "fehler", (f"{e['titel']} muss zwischen {e['min']} und "
                              f"{e['max']} liegen.")
        wert = str(zahl)
    elif e["art"] == "auswahl":
        erlaubt = [o[0] for o in e["optionen"]]
        wert = str(roh).strip().lower()
        if wert not in erlaubt:
            return "fehler", f"{e['titel']}: „{roh}“ ist keine der Möglichkeiten."
    else:  # text
        # Keine Zeilenumbrüche: Die Datei ist zeilenbasiert, ein Umbruch
        # im motd zerschnitte sie.
        wert = (str(roh) or "").replace("\r", " ").replace("\n", " ").strip()
        wert = wert[:e.get("laenge", 200)]

    # --- Schreiben ---
    if e["weg"] == "rcon":
        rcon = _rcon()
        if rcon is None or not rcon.verfuegbar() or not server_laeuft():
            return "warnung", (
                f"{e['titel']} lässt sich nur bei laufendem Server ändern — "
                "dieser Wert steht nicht in der Datei, sondern im Server.")
        befehl = e["befehl"].format(
            wert=wert, an_aus="on" if wert == "true" else "off")
        try:
            antwort = rcon.befehl(befehl, zeitlimit=10.0)
        except Exception as fehler:
            return "fehler", f"{e['titel']}: {fehler}"
        return "gut", f"{e['titel']}: {antwort or 'gesetzt'} — sofort wirksam."

    try:
        ergebnis = properties_setzen("server.properties", {schluessel: wert})
    except ValueError as fehler:
        return "fehler", str(fehler)

    if ergebnis["vorgemerkt"]:
        return "warnung", (f"{e['titel']} vorgemerkt — der Server läuft, und "
                           "Paper würde die Änderung überschreiben. Sie wird "
                           "beim nächsten Neustart angewendet.")
    return "gut", f"{e['titel']} gespeichert. Wirkt beim nächsten Start."


# ----------------------------------------------------------------------------
# Der Expertenmodus: ganze Dateien
# ----------------------------------------------------------------------------
def _geheim_verdecken(text, art, schluessel):
    """Ersetzt geheime Werte durch den Platzhalter.

    Zwei Schreibweisen, weil zwei Dateiformate:
        properties:  rcon.password=geheim
        yaml:            secret: 'geheim'
    """
    if not schluessel:
        return text
    zeilen = []
    for zeile in text.splitlines(keepends=True):
        ende = "\n" if zeile.endswith("\n") else ""
        for name in schluessel:
            # Leere Werte bleiben leer: Sterne vor einem leeren Feld sagen
            # "hier ist etwas gesetzt", und das wäre gelogen.
            if (art == "properties" and zeile.startswith(name + "=")
                    and zeile[len(name) + 1:].strip()):
                zeile = f"{name}={PLATZHALTER}{ende}"
                break
            if art == "yaml":
                treffer = re.match(rf"^(\s*){re.escape(name)}:\s*(.*)$", zeile.rstrip("\n"))
                # Nur echte Werte verdecken. Ein Schluessel, unter dem ein
                # Block haengt (also ohne Wert dahinter), ist kein Geheimnis.
                if treffer and treffer.group(2).strip():
                    zeile = f"{treffer.group(1)}{name}: '{PLATZHALTER}'{ende}"
                    break
        zeilen.append(zeile)
    return "".join(zeilen)


def _geheim_zuruecksetzen(neu, alt, art, schluessel):
    """Setzt beim Speichern die echten Werte wieder ein.

    Nur dort, wo noch der Platzhalter steht. Wer wirklich etwas anderes
    eingetragen hat, behält es — sonst ließe sich ein Passwort nie ändern.
    """
    if not schluessel:
        return neu

    def alter_wert(name):
        for zeile in alt.splitlines():
            if art == "properties" and zeile.startswith(name + "="):
                return zeile[len(name) + 1:]
            if art == "yaml":
                treffer = re.match(rf"^\s*{re.escape(name)}:\s*(.*)$", zeile)
                if treffer:
                    return treffer.group(1)
        return None

    zeilen = []
    for zeile in neu.splitlines(keepends=True):
        ende = "\n" if zeile.endswith("\n") else ""
        for name in schluessel:
            if art == "properties" and zeile.strip() == f"{name}={PLATZHALTER}":
                echt = alter_wert(name)
                if echt is not None:
                    zeile = f"{name}={echt}{ende}"
                break
            if art == "yaml":
                treffer = re.match(rf"^(\s*){re.escape(name)}:\s*['\"]?{re.escape(PLATZHALTER)}['\"]?\s*$",
                                   zeile.rstrip("\n"))
                if treffer:
                    echt = alter_wert(name)
                    if echt is not None:
                        zeile = f"{treffer.group(1)}{name}: {echt}{ende}"
                    break
        zeilen.append(zeile)
    return "".join(zeilen)


def datei_lesen(name):
    """Den Inhalt einer erlaubten Datei zum Bearbeiten holen."""
    info = DATEIEN.get(name)
    if not info:
        return None
    try:
        roh = _geltender_stand(name)
    except OSError:
        return None
    return _geheim_verdecken(roh, info["art"], info["geheim"])


def pruefen(text, art):
    """Prüft, ob der Text als Datei dieses Formats durchgeht.

    Liefert (ok, meldung). Der Sinn ist nicht Vollständigkeit, sondern zu
    verhindern, dass der Server wegen eines Tippfehlers nicht mehr startet
    — und das ist der wahrscheinlichste Schaden, den dieser Editor
    anrichten kann.
    """
    if art == "properties":
        for nummer, zeile in enumerate(text.splitlines(), 1):
            nackt = zeile.strip()
            if not nackt or nackt.startswith("#"):
                continue
            if "=" not in nackt:
                return False, (f"Zeile {nummer} ist weder Kommentar noch "
                               f"„schlüssel=wert“: {nackt[:60]}")
        return True, ""

    # YAML. Mit einem echten Parser, wenn es einen gibt.
    try:
        import yaml
    except ImportError:
        # Ohne PyYAML wenigstens die haeufigste Bruchstelle abfangen und
        # ehrlich sagen, dass mehr nicht geprueft wurde. Ein Tabulator in
        # der Einrueckung ist in YAML verboten und laesst den Server beim
        # Start mit einer unverstaendlichen Meldung stehenbleiben.
        for nummer, zeile in enumerate(text.splitlines(), 1):
            if zeile.startswith("\t") or re.match(r"^ *\t", zeile):
                return False, (f"Zeile {nummer} fängt mit einem Tabulator an. "
                               "YAML erlaubt zum Einrücken nur Leerzeichen.")
        return True, ("ACHTUNG: Es ist kein YAML-Parser installiert, geprüft "
                      "wurde nur auf Tabulatoren. Ein anderer Formatfehler "
                      "fällt erst beim nächsten Serverstart auf — und dann "
                      "startet der Server nicht. Die Vorfassung liegt als "
                      ".bak-… daneben. Abhilfe: "
                      "sudo apt-get install -y python3-yaml")
    try:
        yaml.safe_load(text)
    except yaml.YAMLError as fehler:
        return False, f"Das ist kein gültiges YAML: {fehler}"
    return True, ""


def datei_schreiben(name, neuer_text):
    """Speichert eine ganze Datei. Liefert (art, meldung).

    Der Ablauf ist überall derselbe: prüfen, Geheimnisse zurücksetzen,
    Vorfassung sichern, schreiben — oder vormerken, wenn der Server läuft
    und es die server.properties ist.
    """
    info = DATEIEN.get(name)
    if not info:
        return "fehler", "Diese Datei darf hier nicht bearbeitet werden."

    ok, meldung = pruefen(neuer_text, info["art"])
    if not ok:
        return "fehler", meldung

    pfad = info["pfad"]()
    try:
        alt = _geltender_stand(name)
    except OSError as fehler:
        return "fehler", f"{pfad} lässt sich nicht lesen: {fehler}"

    inhalt = _geheim_zuruecksetzen(neuer_text, alt, info["art"], info["geheim"])

    if muss_vorgemerkt_werden(name):
        vormerken(name, inhalt)
        return "warnung", ("Vorgemerkt. Der Server läuft, und Paper würde die "
                           "Änderung überschreiben — sie wird beim nächsten "
                           "Neustart angewendet." + (f" {meldung}" if meldung else ""))

    sicherung = sicherung_anlegen(pfad)
    datei_ersetzen(pfad, inhalt)
    vormerkung_verwerfen(name)
    wirkung = ("Wirkt beim nächsten Start."
               if info["art"] == "yaml" or not server_laeuft() else "")
    hinweis = f" {meldung}" if meldung else ""
    return "gut", (f"Gespeichert. Die Vorfassung liegt als "
                   f"{Path(sicherung).name if sicherung else '(keine Kopie)'} "
                   f"daneben. {wirkung}{hinweis}")


# ----------------------------------------------------------------------------
# Was sonst noch auf die Seite gehört
# ----------------------------------------------------------------------------
def versionen():
    """Welche Paper- und Java-Version installiert sind."""
    stand = {"paper": "unbekannt", "build": "", "java": "unbekannt"}

    merkzettel = Path(MCS_SERVER_DIR) / "paper.installiert"
    try:
        for zeile in merkzettel.read_text(encoding="utf-8", errors="ignore").splitlines():
            if zeile.startswith("version="):
                stand["paper"] = zeile.split("=", 1)[1].strip()
            elif zeile.startswith("build="):
                stand["build"] = zeile.split("=", 1)[1].strip()
    except OSError:
        pass

    from system import run_command
    code, aus, fehler = run_command(["java", "-version"], timeout=10)
    text = fehler or aus          # java meldet die Version auf stderr
    treffer = re.search(r'version "?([0-9][^"\s]*)', text or "")
    if code == 0 and treffer:
        stand["java"] = treffer.group(1)
    return stand


# Aus `ss -ltnp`: users:(("python3",pid=265947,fd=4)) — gebraucht wird der
# erste Name in Anfuehrungszeichen.
_SS_PROZESS = re.compile(r'\(\("([^"]+)"')


def _prozessname(feld):
    """Der Prozessname aus dem letzten Feld einer `ss -ltnp`-Zeile.

    Leer, wenn dort nichts steht — und das heisst nicht "kein Prozess",
    sondern "nicht unser Prozess": `ss` nennt ihn nur, wenn der Socket dem
    fragenden Benutzer gehoert. Die Oberflaeche laeuft als unprivilegierter
    Benutzer, nginx und sshd laufen als root.
    """
    treffer = _SS_PROZESS.search(feld or "")
    return treffer.group(1) if treffer else ""


def _dynamische_adressen():
    """Adressen, die dieser Rechner nicht selbst gewaehlt hat (DHCP).

    Liefert eine Menge von Adressen, oder None, wenn `ip` nicht zu sprechen
    war — dann wird nichts behauptet statt geraten.

    `ip -o addr` markiert eine per DHCP bezogene Adresse mit dem Wort
    "dynamic":

        2: eth0  inet 192.168.1.44/24 brd ... scope global dynamic ... eth0

    Fehlt es, wurde die Adresse fest vergeben. Der Unterschied ist der
    zwischen "laeuft" und "laeuft bis zum naechsten Neustart": Ein Dienst,
    der fest an eine geliehene Adresse gebunden ist, kann nach einem
    Adresswechsel nicht mehr binden und stirbt beim Systemstart — bevor
    irgendetwas davon in einer Weboberflaeche sichtbar waere.
    """
    from system import run_command
    code, aus, _ = run_command(["ip", "-o", "addr"], timeout=5)
    if code != 0:
        return None

    dynamisch = set()
    for zeile in (aus or "").splitlines():
        felder = zeile.split()
        if "dynamic" not in felder:
            continue
        for i, feld in enumerate(felder):
            if feld in ("inet", "inet6") and i + 1 < len(felder):
                dynamisch.add(felder[i + 1].split("/")[0])
                break
    return dynamisch


def _ist_rueckschleife(host):
    """127.0.0.0/8 oder ::1 — die Adresse, die es immer gibt."""
    return host.startswith("127.") or host in ("::1", "localhost")


def _host_aus_adresse(adresse):
    """Die nackte Adresse aus einem "Adresse:Port" von `ss`.

    Zwei Schreibweisen sind dabei zu vereinheitlichen, sonst vergleicht man
    gegen `ip addr` ins Leere:

        192.168.1.44:8091              -> 192.168.1.44
        [::ffff:192.168.1.44]:8090     -> 192.168.1.44

    Die zweite ist eine IPv4-Adresse in IPv6-Schreibweise. Java benutzt sie
    von sich aus, und gemessen am 2026-09-01 lauschte genau so der
    Kartenserver — dieselbe geliehene Adresse wie die drei Nachbarn, nur
    anders geschrieben. Ohne diese Zeile bliebe ausgerechnet er unmarkiert.
    """
    host = adresse.rsplit(":", 1)[0].strip("[]")
    if host.lower().startswith("::ffff:"):
        host = host[7:]
    return host


def offene_ports():
    """Welche Ports lauschen, und wofür.

    Die Zuordnung kommt aus der eigenen Konfiguration, nicht aus einer
    Namenstabelle: Wer den Spielserver auf einen anderen Port gelegt hat,
    soll ihn hier trotzdem richtig beschriftet sehen.

    Eine feste Liste weiterer Ports gibt es bewusst nicht — sie waere
    instanzspezifisch und auf einem fremden Pi falsch. Was ein unbekannter
    Port stattdessen bekommt, ist das, was sich WISSEN laesst: der
    Prozessname aus `ss -ltnp`, soweit er ohne sudo lesbar ist. Ist er es
    nicht, steht dort "von einem anderen Benutzer" — weniger Auskunft, aber
    keine falsche. Eine sudo-Regel dafuer wird ausdruecklich nicht
    eingerichtet: Die Oberflaeche ist ohnehin so maechtig wie ein
    SSH-Zugang, und jede weitere Ausnahme macht diesen Satz wahrer.
    """
    from system import run_command
    werte = properties_lesen(SERVER_PROPERTIES)

    def zahl(schluessel, ersatz):
        try:
            return int(werte.get(schluessel, ersatz))
        except (TypeError, ValueError):
            return ersatz

    bekannt = {
        zahl("server-port", 25565): ("Minecraft", "muss im Router freigegeben sein"),
        zahl("rcon.port", 25575): ("RCON", "MUSS von der Firewall gesperrt sein"),
        22: ("SSH", "Fernwartung"),
    }
    try:
        bekannt[int(os.getenv("MCS_ADMIN_PORT", "8080"))] = (
            "Weboberfläche", "nur im Heimnetz oder über Tailscale")
    except ValueError:
        pass

    # "-p" haengt nur eine sechste Spalte an; die Adresse steht weiterhin an
    # Position 3. Ein zweiter ss-Aufruf waere ein zweiter Unterprozess fuer
    # dieselbe Auskunft (Leitsatz 1).
    code, aus, _ = run_command(["ss", "-ltnp"], timeout=5)
    if code != 0:
        return []

    dynamisch = _dynamische_adressen()

    gefunden = []
    for zeile in (aus or "").splitlines()[1:]:
        felder = zeile.split()
        if len(felder) < 4:
            continue
        adresse = felder[3]
        try:
            port = int(adresse.rsplit(":", 1)[1])
        except (IndexError, ValueError):
            continue
        wofuer, hinweis = bekannt.get(port, ("", ""))
        # "*" oder "0.0.0.0" heisst: auf allen Netzwerkkarten erreichbar.
        ueberall = adresse.startswith(("*", "0.0.0.0", "[::]"))

        # Fest an eine geliehene Adresse gebunden? Die Rueckschleife zaehlt
        # nicht: 127.0.0.1 gibt es immer, daran zu binden ist eine
        # Entscheidung und keine Zeitbombe.
        host = _host_aus_adresse(adresse)
        fluechtig = bool(not ueberall
                         and not _ist_rueckschleife(host)
                         and dynamisch is not None
                         and host in dynamisch)

        gefunden.append({"port": port, "adresse": adresse, "wofuer": wofuer,
                         "hinweis": hinweis, "ueberall": ueberall,
                         "prozess": _prozessname(felder[5] if len(felder) > 5 else ""),
                         "fluechtig": fluechtig})
    gefunden.sort(key=lambda e: e["port"])
    return gefunden
