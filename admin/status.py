#!/usr/bin/env python3
"""
status.py — Das Gesamtbild.

Setzt aus den Einzelwerten (System, Protokoll, Server) ein Statusbild
zusammen und haelt es kurz vor. Die Oberflaeche fragt alle fuenf Sekunden;
ohne Zwischenspeicher kostete jedes geoeffnete Browserfenster drei
Unterprozesse pro Abfrage.
"""

import glob
import os
import threading
import time
from datetime import datetime
from pathlib import Path

import protokollpruefung
from einstellungen import (ALLOW_HOST_POWER, AUTH_ENABLED, BACKUP_DIR,
                           BACKUP_WARN_HOURS, MCS_SERVER_DIR, MINECRAFT_LOG,
                           PLAYER_ACTIVITY_LOG, SERVER_PROPERTIES)
from protokoll import JOIN_RE, online_players
from system import (cpu_auslastung, disk_stats, mcs_abgeschaltet,
                    memory_stats, neustart_noetig, pi_temperature_c,
                    service_state, service_uptime)

try:
    import metrik
    import rcon
except ImportError:  # pragma: no cover
    metrik = None
    rcon = None

def last_backup_info():
    """Informationen zum neuesten Backup-Archiv — inklusive Bewertung.

    Wichtig ist nicht nur, DASS es ein Backup gibt, sondern wie alt es ist.
    Vom 2026-05-18 bis zum 2026-07-27 kam über zwei Monate lang kein Backup
    zustande, obwohl der Cronjob jede Nacht lief — niemand hat es bemerkt,
    weil das Alter nirgends bewertet wurde. Deshalb liefert diese Funktion
    zusätzlich `age_hours`, `stale` und den letzten Fehlertext.
    """
    # Nur die vom Backup-Skript erzeugten Archive zählen. Eine von Hand
    # abgelegte Datei soll den Alterswert nicht beschönigen.
    backups = sorted(glob.glob(f"{BACKUP_DIR}/backup_*.tar.gz"),
                     key=os.path.getmtime, reverse=True)

    # Was das Backup-Skript beim letzten Fehlschlag hinterlassen hat.
    fehler_text = ""
    fehler_datei = Path(BACKUP_DIR) / ".letzter-fehler"
    if fehler_datei.is_file():
        try:
            fehler_text = fehler_datei.read_text(encoding="utf-8", errors="ignore").strip()
        except OSError:
            fehler_text = "(Fehlerdatei nicht lesbar)"

    # Ist Pi-MCS abgeschaltet, läuft der Backup-Timer nicht — dann ist ein
    # altes oder fehlendes Backup erwartetes Verhalten, keine Störung.
    abgeschaltet = mcs_abgeschaltet()

    if not backups:
        return {"exists": False, "stale": not abgeschaltet, "error": fehler_text,
                "mcs_aus": abgeschaltet, "warn_after_hours": BACKUP_WARN_HOURS}

    backup = backups[0]
    stat = os.stat(backup)
    age_hours = round((time.time() - stat.st_mtime) / 3600.0, 1)
    return {
        "exists": True,
        "file": os.path.basename(backup),
        "path": backup,
        "size_mb": round(stat.st_size / (1024 * 1024), 2),
        "mtime": datetime.fromtimestamp(stat.st_mtime).isoformat(timespec="seconds"),
        "age_hours": age_hours,
        "stale": (age_hours > BACKUP_WARN_HOURS) and not abgeschaltet,
        "mcs_aus": abgeschaltet,
        "warn_after_hours": BACKUP_WARN_HOURS,
        "error": fehler_text,
        "count": len(backups),
    }



# Kurzzeit-Zwischenspeicher für die Statuswerte.
_status_stand = {"zeit": 0.0, "werte": None}
_status_sperre = threading.Lock()

# Wie lange ein einmal ermittelter Status wiederverwendet wird (Sekunden).
# Die Oberfläche fragt alle 5 Sekunden — mit drei Sekunden Gültigkeit
# kostet ein zweites geöffnetes Browserfenster praktisch nichts mehr.
# Jeder Aufruf startet sonst drei Unterprozesse (systemctl, systemctl, ps)
# und misst 0,2 Sekunden lang die CPU-Auslastung.
STATUS_CACHE_SEKUNDEN = 3.0


def current_status(erzwingen=False, aufrufer="anzeige"):
    """Sammelt alle Statuswerte für die Übersicht ein (kurz zwischengespeichert).

    `aufrufer` wird bis zur CPU-Messung durchgereicht. Er muss hier stehen und
    nicht in metrik.py, weil der Sammler seine Werte über genau diese Funktion
    holt — beide Takte laufen durch dasselbe Nadelöhr, und genau daran hing
    der Messfehler (siehe `system.cpu_auslastung`).
    """
    with _status_sperre:
        if (not erzwingen and _status_stand["werte"] is not None
                and (time.time() - _status_stand["zeit"]) < STATUS_CACHE_SEKUNDEN):
            return _status_stand["werte"]

        werte = _status_erheben(aufrufer)
        _status_stand["zeit"] = time.time()
        _status_stand["werte"] = werte
        return werte


def max_players():
    """Wie viele Spieler laut server.properties zugelassen sind.

    Die Oberfläche zeigt "2 / 5" und füllt danach ihre Anzeige. Ohne
    diesen Wert müsste sie eine Zahl raten — und läge falsch, sobald
    jemand max-players ändert. Ist die Datei nicht lesbar, wird der
    Minecraft-Standard 20 gemeldet.
    """
    try:
        for zeile in Path(SERVER_PROPERTIES).read_text(
            encoding="utf-8", errors="ignore"
        ).splitlines():
            if zeile.startswith("max-players="):
                return int(zeile.split("=", 1)[1].strip())
    except (OSError, ValueError):
        pass
    return 20


# Eigener, LANGER Zwischenspeicher für den Protokoll-Wächter.
#
# Warum nicht einfach im 3-Sekunden-Takt der übrigen Statuswerte mitlaufen:
# Die Prüfung listet den logs-Ordner (auf einer gewachsenen Installation
# mehrere hundert Einträge) und öffnet das Hauptbuch. Das ist je Aufruf
# wenig, aber zwanzigmal in der Minute ist es Rechenzeit, die dem Server
# gehört (Leitsatz 1). Und es lohnt nicht: Der Befund ändert sich nur,
# wenn jemand rotiert oder nachträgt — höchstens einmal am Tag.
PROTOKOLL_CACHE_SEKUNDEN = 300.0
_protokoll_stand = {"zeit": 0.0, "befund": None, "gefuellt": False}
_protokoll_sperre = threading.Lock()


def protokoll_befund(erzwingen=False):
    """Der Wächter-Befund, lange zwischengespeichert. None = nichts zu melden."""
    with _protokoll_sperre:
        jetzt = time.time()
        if (not erzwingen and _protokoll_stand["gefuellt"]
                and (jetzt - _protokoll_stand["zeit"]) < PROTOKOLL_CACHE_SEKUNDEN):
            return _protokoll_stand["befund"]

        # Ein Fehler in der Prüfung darf die ganze Statusseite nicht
        # mitreissen: Sie ist eine Zusatzangabe, kein Kernwert.
        try:
            befund = protokollpruefung.protokoll_lueckenhaft(
                PLAYER_ACTIVITY_LOG, Path(MINECRAFT_LOG).parent)
        except Exception:  # pragma: no cover
            befund = None

        _protokoll_stand.update({"zeit": jetzt, "befund": befund,
                                 "gefuellt": True})
        return befund


# Der zweite Wächter braucht keinen langen Zwischenspeicher: Er liest nur,
# was seit dem letzten Aufruf an latest.log dazukam (siehe
# protokollpruefung.beitritte_unerkannt). Die Sperre, weil die Oberfläche
# mehrere Anfragen gleichzeitig bedient und der Lesestand einer ist.
_muster_sperre = threading.Lock()


def muster_befund():
    """Erkennen die Logmuster die Beitritte noch? None = nichts zu melden."""
    with _muster_sperre:
        try:
            return protokollpruefung.beitritte_unerkannt(MINECRAFT_LOG, JOIN_RE)
        except Exception:  # pragma: no cover
            return None


def _status_erheben(aufrufer="anzeige"):
    """Ermittelt die Statuswerte wirklich (ohne Zwischenspeicher)."""
    cpu_wert, cpu_frisch = cpu_auslastung(aufrufer)
    mem = memory_stats()
    disk = disk_stats(MCS_SERVER_DIR)
    players = online_players()
    load1, load5, load15 = os.getloadavg()

    # TPS und MSPT kommen vom Server selbst, ueber RCON. Sie fehlen still,
    # wenn RCON nicht eingerichtet ist oder der Server gerade nicht laeuft —
    # der Rest der Uebersicht soll deswegen nicht ausfallen.
    tps_wert = mspt_wert = None
    if metrik is not None:
        tps_wert, mspt_wert = metrik.server_werte()

    return {
        "timestamp": datetime.now().isoformat(timespec="seconds"),
        "service_state": service_state(),
        "service_uptime": service_uptime(),
        "cpu_usage_percent": cpu_wert,
        # False heisst: Die Messspanne war zu kurz: was hier steht, ist der
        # vorige Wert. Die Oberflaeche macht das sichtbar, statt ihn als
        # frisch auszugeben.
        "cpu_frisch": cpu_frisch,
        "cpu_temp_c": pi_temperature_c(),
        "mem_used_mb": mem["used_mb"],
        "mem_total_mb": mem["total_mb"],
        "mem_usage_percent": mem["usage_percent"],
        "disk_used_gb": disk["used_gb"],
        "disk_total_gb": disk["total_gb"],
        "disk_usage_percent": disk["usage_percent"],
        "loadavg_1m": round(load1, 2),
        "loadavg_5m": round(load5, 2),
        "loadavg_15m": round(load15, 2),
        "players_online": players,
        "players_count": len(players),
        "max_players": max_players(),
        "last_backup": last_backup_info(),
        "neustart": neustart_noetig(),
        "tps": tps_wert,
        "mspt": mspt_wert,
        "rcon_verfuegbar": bool(rcon and rcon.verfuegbar()),
        "auth_enabled": AUTH_ENABLED,
        "allow_host_power": ALLOW_HOST_POWER,
        # None = nichts zu melden. Sonst fehlt dem Spielerprotokoll die
        # Vergangenheit, und "zuletzt gesehen" ist unvollständig —
        # der Fehler, der im September zwei Wochen lang still blieb.
        "protokoll_befund": protokoll_befund(),
        # None = nichts zu melden. Sonst melden sich Spieler an, aber kein
        # Beitritt wird erkannt — der stille Ausfall vom 14. bis 21.10.2026.
        "muster_befund": muster_befund(),
    }

