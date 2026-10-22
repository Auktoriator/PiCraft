#!/usr/bin/env python3
"""
einstellungen.py — Wo alles liegt und wie die Oberflaeche sich anmeldet.

Alle Pfade von Pi-MCS stehen an einer einzigen Stelle: in der mcs.conf der
Installation. Dieses Modul liest sie ein und stellt sie den uebrigen Modulen
als schlichte Namen zur Verfuegung. Wer wissen will, wo etwas hingehoert,
schaut hier — und nirgends sonst.
"""

import os
from pathlib import Path


# ----------------------------------------------------------------------------
# KEY=WERT lesen — einmal für alle
# ----------------------------------------------------------------------------
# Pi-MCS hat zwei Dateiformate, und beide sind dieselbe Schleife: mcs.conf
# (Shell/systemd) und server.properties (Minecraft). Bis zum 2026-09-02 stand
# diese Schleife VIERMAL im Programm — hier, in konfig.py, in version.py und
# in rcon.py. Vier Fassungen derselben Rechnung sind der sichere Weg zu vier
# Antworten, sobald jemand eine davon anfasst; genau diese Klasse Fehler
# steckte in Korrektur K8.
#
# Hier steht sie, weil dieses Modul das Blatt ist: Es importiert nichts
# Eigenes, also kann jedes andere Modul es einbinden, ohne einen Ring zu
# schliessen.
def kv_aus_text(text, anfuehrungszeichen=False):
    """Zerlegt KEY=WERT-Zeilen in ein dict. Leerzeilen und '#' werden übergangen.

    `anfuehrungszeichen=True` nimmt umschliessende Anfuehrungszeichen ab. Das
    ist fuer mcs.conf noetig (Werte mit Leerzeichen stehen dort seit
    2026-08-31 in einfachen Anfuehrungszeichen, siehe
    konfig.wert_fuer_mcs_conf) und fuer server.properties falsch — dort
    gehoert ein Anfuehrungszeichen zum Wert.
    """
    werte = {}
    for zeile in (text or "").splitlines():
        zeile = zeile.strip()
        if not zeile or zeile.startswith("#") or "=" not in zeile:
            continue
        schluessel, wert = zeile.split("=", 1)
        wert = wert.strip()
        if (anfuehrungszeichen and len(wert) >= 2
                and wert[0] == wert[-1] and wert[0] in "'\""):
            wert = wert[1:-1]
        werte[schluessel.strip()] = wert
    return werte


def kv_lesen(pfad, anfuehrungszeichen=False):
    """Dasselbe aus einer Datei. Fehlt sie, ist das Ergebnis leer, kein Fehler."""
    try:
        return kv_aus_text(
            Path(pfad).read_text(encoding="utf-8", errors="ignore"),
            anfuehrungszeichen)
    except OSError:
        return {}


# ----------------------------------------------------------------------------
# Zentrale Einstellungen laden
# ----------------------------------------------------------------------------
def lade_mcs_conf(pfad=None):
    """Liest die mcs.conf der Installation und legt die Werte in der Umgebung ab.

    Warum überhaupt? Alle Pfade von Pi-MCS stehen an einer einzigen Stelle
    (mcs.conf). Startet die Weboberfläche über systemd, hat der Dienst die
    Datei schon eingelesen. Ruft dagegen jemand `mcs status` im Terminal auf,
    läuft app.py ohne systemd — dann holt sich diese Funktion die Werte
    selbst.

    Bereits gesetzte Umgebungsvariablen bleiben unangetastet: die .env-Datei
    mit den Zugangsdaten hat also immer Vorrang.
    """
    standard = os.path.join(os.path.expanduser("~"), "mcs", "mcs.conf")
    pfad = pfad or os.getenv("MCS_CONF", standard)
    # Mit Anfuehrungszeichen-Behandlung: Shell und systemd nehmen sie von
    # sich aus ab, Python muss es nachmachen — sonst kaeme
    # "/media/pi/My Passport" einschliesslich der Anfuehrungszeichen an, und
    # keine Datei liesse sich unter diesem Namen oeffnen.
    #
    # Fehlt die Datei, liefert kv_lesen ein leeres dict und unten greifen die
    # Standardwerte. Die Oberflaeche laeuft trotzdem.
    for schluessel, wert in kv_lesen(pfad, anfuehrungszeichen=True).items():
        os.environ.setdefault(schluessel, wert)


lade_mcs_conf()


# ----------------------------------------------------------------------------
# Konfiguration
# ----------------------------------------------------------------------------
# Alle Pfade kommen aus mcs.conf und können über die .env-Datei übersteuert
# werden. Die Rückfallwerte darunter leiten sich vom Heimatverzeichnis des
# laufenden Benutzers ab — bis 2026-08-28 stand hier fest "/home/pi/...",
# was auf jedem Pi mit einem anderen Benutzernamen ins Leere zeigte.
MCS_DIR = os.getenv("MCS_DIR", os.path.join(os.path.expanduser("~"), "mcs"))

MCS_SERVICE = os.getenv("MCS_SERVICE_NAME", "minecraft.service")
MCS_SERVER_DIR = os.getenv("MCS_SERVER_DIR", f"{MCS_DIR}/mc_server")
BACKUP_DIR = os.getenv("MCS_BACKUP_DIR", f"{MCS_DIR}/mcs_backup")
BACKUP_SCRIPT = os.getenv("MCS_BACKUP_SCRIPT", f"{BACKUP_DIR}/minecraft-backup.sh")
UPDATE_SCRIPT = os.getenv("MCS_UPDATE_SCRIPT", f"{MCS_SERVER_DIR}/paper-update.sh")
PLAYER_ACTIVITY_LOG = os.getenv("MCS_PLAYER_ACTIVITY_LOG", f"{MCS_DIR}/player_activity.log")
MINECRAFT_LOG = os.getenv("MCS_MINECRAFT_LOG", f"{MCS_SERVER_DIR}/logs/latest.log")
SERVER_PROPERTIES = os.getenv("MCS_SERVER_PROPERTIES", f"{MCS_SERVER_DIR}/server.properties")
ACTION_LOG = os.getenv("MCS_ACTION_LOG", f"{MCS_DIR}/admin/actions.log")
# Die Spieler-Historie. Eigene Datei und NICHT metrik.db: eigene
# Aufbewahrungsfrist, und sie enthält Chat-Inhalte — also eigene Rechte
# (chmod 600, gesetzt von tools/historie-aufbauen.py und install.sh).
HISTORIE_DB = os.getenv("MCS_HISTORIE_DB", f"{MCS_DIR}/admin/historie.db")


def _zahl(name, standard):
    """Eine Zahl aus der Umgebung — mit ausdrücklicher Behandlung der 0.

    `${X:-standard}` greift NICHT bei einer ausdrücklichen `0`, und genau
    daran ist dieses Projekt schon einmal teuer hängengeblieben: Aus
    `MCS_BACKUP_BEHALTEN=0` wurde `tail -n +1`, also *jede* Zeile, und ein
    Lauf räumte beide Backup-Platten leer (31.08.2026). Seither heißt `0`
    überall ausdrücklich „aus", und was keine Zahl ist, fällt gemeldet auf
    den Standard zurück statt still zu einer Null zu werden.
    """
    wert = os.getenv(name)
    if wert is None or wert.strip() == "":
        return standard
    try:
        return int(wert.strip())
    except ValueError:
        print(f"Warnung: {name}={wert!r} ist keine Zahl — es gilt "
              f"{standard}.")
        return standard


# Wie lange die Historie aufbewahrt wird. 0 heißt ausdrücklich UNBEGRENZT.
#
# Voreinstellung unbegrenzt, weil Sitzungen winzig sind (eine Zeile je
# Besuch) und „wer war im letzten Sommer da" genau die Frage ist, wegen der
# man so eine Seite baut. Wer kürzer aufbewahren will, setzt eine Zahl.
HISTORIE_TAGE = _zahl("MCS_HISTORIE_TAGE", 0)
MCS_SCREEN_SESSION = os.getenv("MCS_SCREEN_SESSION", "minecraft_server")
ARCHIV_DIR = os.getenv("MCS_ARCHIV_DIR", f"{MCS_DIR}/weltarchiv")

# Ab wann ein Backup als "zu alt" gilt und gemeldet wird (Stunden).
BACKUP_WARN_HOURS = float(os.getenv("MCS_BACKUP_WARNUNG_STUNDEN", "48"))

# Zugangsdaten für die Weboberfläche (Anmeldung mit Sitzungs-Cookie, siehe
# sicherheit.py — bis 28.08.2026 stand hier noch "HTTP Basic Auth").
# Ohne gesetztes Passwort ist die Anmeldung AUS — die Oberfläche zeigt
# dann eine deutliche Warnung an.
ADMIN_USER = os.getenv("MCS_ADMIN_USER", "admin")
ADMIN_PASSWORD = os.getenv("MCS_ADMIN_PASSWORD", "")
AUTH_ENABLED = bool(ADMIN_PASSWORD)

# Dürfen über die Weboberfläche auch Pi-Neustart/-Herunterfahren ausgelöst
# werden? Nur aktiv, wenn MCS_ALLOW_HOST_POWER=1 in der .env steht UND die
# passenden sudo-Regeln einkommentiert wurden (siehe install-admin.sh).
ALLOW_HOST_POWER = os.getenv("MCS_ALLOW_HOST_POWER", "0") in {"1", "true", "TRUE", "yes", "YES"}
