#!/usr/bin/env python3
"""
system.py — Was der Pi ueber sich selbst weiss.

Auslastung, Speicher, Temperatur, Zustand der Dienste — und das Ausfuehren
von Befehlen, auf dem all das beruht. Nichts hier weiss etwas von Minecraft
oder von Flask; das ist Absicht.
"""

import os
import re
import shutil
import subprocess
import threading
import time
from collections import deque
from datetime import datetime
from pathlib import Path

from einstellungen import ACTION_LOG, MCS_SERVICE

# ----------------------------------------------------------------------------
# Hilfsfunktionen: Befehle ausführen
# ----------------------------------------------------------------------------
def run_command(cmd, timeout=20, cwd=None, eingabe=None, protokoll=None):
    """Führt einen Befehl aus und liefert (Rückgabecode, Ausgabe, Fehlertext).

    `eingabe` geht als Standardeingabe an den Befehl. Das braucht genau ein
    Fall: eine Datei mit `sudo tee` zu schreiben, für die der Benutzer keine
    Schreibrechte hat (das Drop-in des Backup-Timers). Der Parameter steht
    hier und nicht als zweite Ausführungsfunktion daneben — ein zweiter Weg,
    Befehle zu starten, wäre genau das Muster, das in CLAUDE.md dreimal als
    Fehlerquelle steht.

    `protokoll` (ein Aktionsname) schreibt Start, Ausgabe und Ergebnis ins
    Aktionsprotokoll, in derselben Form wie run_background. Gebraucht für das
    Paper-Update: Es läuft seit dem 03.10.2026 im Vordergrund, damit die
    Oberfläche das Ergebnis zeigen kann — vorher stand dort nur
    "Gestartet", und dass jeder Klick "nichts zu tun" ergab, sah niemand.
    """
    if protokoll:
        _protokoll_schreiben(f"\n[{_jetzt()}] START {protokoll}: {' '.join(cmd)}\n")
    try:
        proc = subprocess.run(cmd, capture_output=True, text=True,
                              timeout=timeout, cwd=cwd, input=eingabe)
        ergebnis = (proc.returncode, proc.stdout.strip(), proc.stderr.strip())
    except subprocess.TimeoutExpired:
        ergebnis = (124, "", f"Zeitüberschreitung nach {timeout}s: {' '.join(cmd)}")
    except FileNotFoundError:
        ergebnis = (127, "", f"Befehl nicht gefunden: {cmd[0]}")
    except Exception as exc:
        ergebnis = (1, "", str(exc))
    if protokoll:
        code, aus, fehler = ergebnis
        text = "\n".join(t for t in (aus, fehler) if t)
        _protokoll_schreiben((text + "\n" if text else "")
                             + f"[{_jetzt()}] ENDE {protokoll}: {code}\n")
    return ergebnis


def _jetzt():
    return datetime.now().isoformat(timespec="seconds")


def _protokoll_schreiben(text):
    """Hängt an das Aktionsprotokoll an. Scheitert das, scheitert nicht die Aktion."""
    try:
        Path(ACTION_LOG).parent.mkdir(parents=True, exist_ok=True)
        with open(ACTION_LOG, "a", encoding="utf-8") as datei:
            datei.write(text)
    except OSError:
        pass


def aktion_vermerken(protokoll, text):
    """Trägt eine Aktion ohne Befehl ins Aktionsprotokoll ein.

    Für Vorgänge, die Python selbst erledigt, etwa das Umbenennen beim
    Plugin-Umschalten. Bis zum 21.10.2026 standen sie nirgends. Deshalb ließ
    sich nicht mehr klären, wie GSit.jar verschwunden war (K7). Das Format ist
    das von run_command, damit die Startseite sie genauso findet.
    """
    jetzt = _jetzt()
    _protokoll_schreiben(f"\n[{jetzt}] START {protokoll}: {text}\n"
                         f"[{jetzt}] ENDE {protokoll}: 0\n")


def run_background(cmd, label, cwd=None):
    """Startet länger laufende Aktionen (das Backup) im Hintergrund.

    Die Weboberfläche muss nicht warten — die Ausgabe landet im
    Aktionsprotokoll (actions.log), damit nichts verloren geht.
    """
    Path(ACTION_LOG).parent.mkdir(parents=True, exist_ok=True)
    started = datetime.now().isoformat(timespec="seconds")
    with open(ACTION_LOG, "a", encoding="utf-8") as log_file:
        log_file.write(f"\n[{started}] START {label}: {' '.join(cmd)}\n")
        proc = subprocess.Popen(
            cmd,
            stdout=log_file,
            stderr=subprocess.STDOUT,
            cwd=cwd,
            start_new_session=True,
            text=True,
        )
    return proc.pid

# ----------------------------------------------------------------------------
# Hilfsfunktionen: Systemwerte auslesen
# ----------------------------------------------------------------------------
def read_last_lines(path, max_lines=200):
    """Liest die letzten Zeilen einer Datei (speicherschonend)."""
    if not Path(path).is_file():
        return []

    lines = deque(maxlen=max_lines)
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        for line in f:
            lines.append(line.rstrip("\n"))
    return list(lines)


# Kurzer Zwischenspeicher fuer den Dienstzustand.
#
# Der Zustandspunkt in der Kopfleiste steht in basis.html, also auf JEDER
# Seite, und erneuert sich alle 5 Sekunden. Jede dieser Abfragen startete bis
# zum 2026-08-31 ein eigenes "systemctl is-active" — je offenem Browserfenster,
# dauerhaft, auf einem Pi, dessen erster Leitsatz lautet, dass nichts drumherum
# dem Server Rechenzeit nehmen darf. Auf der Startseite kam der 5-Sekunden-Takt
# der Kacheln noch dazu.
#
# Zwei Sekunden sind kurz genug, dass niemand einen Unterschied sieht (der
# Punkt erneuert sich ohnehin nur alle 5 s), und lang genug, dass mehrere
# Fenster sich einen Aufruf teilen.
_DIENST_CACHE_SEKUNDEN = 2.0
_dienst_stand = {"zeit": 0.0, "wert": None}
_dienst_sperre = threading.Lock()


def service_state(frisch=False):
    """Zustand des Minecraft-Dienstes: active / inactive / failed / ...

    `frisch=True` umgeht den Zwischenspeicher. Das ist Pflicht ueberall, wo
    aus der Antwort eine SICHERHEITSENTSCHEIDUNG folgt — ob ein Backup
    zurueckgespielt werden darf, ob server.properties geschrieben werden
    darf. Zwei Sekunden alter Zustand ist fuer eine Anzeige belanglos und
    fuer solche Entscheidungen zu viel.
    """
    if not frisch:
        with _dienst_sperre:
            if (_dienst_stand["wert"] is not None
                    and (time.time() - _dienst_stand["zeit"]) < _DIENST_CACHE_SEKUNDEN):
                return _dienst_stand["wert"]

    _, out, _ = run_command(["systemctl", "is-active", MCS_SERVICE], timeout=5)
    wert = out or "unbekannt"
    with _dienst_sperre:
        _dienst_stand["zeit"] = time.time()
        _dienst_stand["wert"] = wert
    return wert


def service_uptime():
    """Wie lange der Server-Prozess schon läuft (z. B. '02:13:45')."""
    _, pid_out, _ = run_command(
        ["systemctl", "show", MCS_SERVICE, "--property=MainPID", "--value"], timeout=5
    )
    pid_str = pid_out.strip()
    if not pid_str.isdigit() or int(pid_str) <= 0:
        return "offline"
    _, up_out, _ = run_command(["ps", "-p", pid_str, "-o", "etime="], timeout=5)
    return up_out.strip() or "n/a"


# Die vorige /proc/stat-Probe — JE AUFRUFER eine.
#
# Bis zum 2026-09-01 gab es hier EINEN Zustand fuer ZWEI Aufrufer mit voellig
# verschiedenem Takt: den Metrik-Sammler (60 s) und die Kacheln der Startseite
# (5 s). Wer die Probe liest, setzt sie zurueck — bei geoeffneter Oberflaeche
# also zwoelfmal je Minute. Der Sammler mass danach nicht mehr seine Minute,
# sondern die Restspanne seit dem letzten Seitenaufruf, mitunter
# Millisekunden. Ueber eine so kurze Spanne ist die Auslastung beliebig.
#
# Gemessen am 2026-09-01 ueber 24 Stunden: 1434 Werte, 0,0 bis 93,6 Prozent,
# 394 Spruenge ueber 30 Punkte — bei durchgehend 20,0 TPS und hoechstens
# 18,5 ms je Tick. Dass es Rauschen war und keine Last, zeigte die Verteilung:
# die Ausschlaege lagen gleichmaessig ueber alle Tagesstunden. Echte Last
# haette ein Muster (das naechtliche Backup, die Timer der Widgets).
#
# Der Kommentar der Funktion verteidigte das geteilte Verhalten sogar
# ausdruecklich. Fuer die ANZEIGE stimmte der Satz auch; falsch war, dass der
# Sammler am selben Zustand hing. Es ist dasselbe Muster wie zweimal zuvor in
# CLAUDE.md: ein zweiter Weg zur selben Sache, der die Regel des ersten nicht
# kennt.
_cpu_proben = {}
_cpu_sperre = threading.Lock()

# Kuerzeste Spanne, ueber die eine Auslastung ueberhaupt eine Aussage ist.
#
# Getrennte Proben allein genuegen naemlich nicht: Zwei offene Browserfenster
# sind beide der Aufrufer "anzeige" und wuerden sich gegenseitig genau so
# zuruecksetzen. Unter einer Sekunde wird deshalb kein Wert erfunden.
CPU_MINDESTSPANNE = 1.0


def _cpu_probe():
    """Eine Momentaufnahme aus /proc/stat: (Summe aller Zaehler, Leerlauf)."""
    with open("/proc/stat", "r", encoding="utf-8") as f:
        parts = f.readline().split()[1:]
    werte = [int(x) for x in parts]
    return sum(werte), werte[3] + werte[4]


def cpu_auslastung(aufrufer="anzeige"):
    """CPU-Auslastung in Prozent. Liefert (wert, frisch).

    /proc/stat liefert Zaehler seit dem Systemstart, keine Momentanlast — man
    braucht also immer ZWEI Proben. Bis zum 2026-08-31 holte sich diese
    Funktion die zweite mit einem time.sleep(0.2) selbst: Bei jedem
    Cache-Fehlschlag blockierte damit ein Thread der Weboberflaeche eine
    Fuenftelsekunde lang, nur um Zeit vergehen zu lassen. Die vorige Probe
    aufzuheben kostet nichts und wartet nicht.

    `aufrufer` benennt, WESSEN vorige Probe gemeint ist. Jeder Takt bekommt
    seine eigene, damit keiner dem anderen die Spanne wegnimmt.

    `frisch` ist False, wenn die Spanne zu kurz fuer eine Aussage war. Dann
    steht im ersten Wert die vorige Messung — und die Oberflaeche sagt, dass
    es eine vorige ist. Eine Anzeige darf "nicht feststellbar" sagen; sie darf
    keine frische Zufallszahl behaupten (Leitsatz 5).

    Beim allerersten Aufruf gibt es noch keine Vorgaengerprobe. Dann wird
    einmal kurz gewartet, statt eine erfundene Null zu melden.
    """
    try:
        with _cpu_sperre:
            probe = _cpu_proben.get(aufrufer)

            # Zu kurze Spanne: Die Probe bleibt ausdruecklich LIEGEN. Wuerde
            # sie hier erneuert, waere der Schutz wirkungslos — der naechste
            # Aufruf haette wieder nur Millisekunden als Bezug.
            if probe is not None and (time.monotonic() - probe["zeit"]) < CPU_MINDESTSPANNE:
                return probe["wert"], False

            if probe is None:
                t1, i1 = _cpu_probe()
                time.sleep(0.2)
            else:
                t1, i1 = probe["total"], probe["idle"]

            t2, i2 = _cpu_probe()
            total_delta = t2 - t1
            idle_delta = i2 - i1
            if total_delta <= 0:
                # Die Zaehler sind nicht weitergelaufen. Darueber laesst sich
                # nichts sagen — also wird auch nichts behauptet.
                return (probe["wert"] if probe else 0.0), False

            wert = round(100.0 * (1.0 - (idle_delta / total_delta)), 1)
            _cpu_proben[aufrufer] = {"total": t2, "idle": i2,
                                     "zeit": time.monotonic(), "wert": wert}
            return wert, True
    except Exception:
        return 0.0, False


def memory_stats():
    """Arbeitsspeicher-Nutzung aus /proc/meminfo."""
    info = {}
    try:
        with open("/proc/meminfo", "r", encoding="utf-8") as f:
            for line in f:
                key, value = line.split(":", 1)
                info[key] = int(value.strip().split()[0])
    except Exception:
        return {"used_mb": 0, "total_mb": 0, "usage_percent": 0.0}

    total_kb = info.get("MemTotal", 0)
    available_kb = info.get("MemAvailable", 0)
    used_kb = max(total_kb - available_kb, 0)
    usage = (used_kb / total_kb * 100.0) if total_kb else 0.0
    return {
        "used_mb": round(used_kb / 1024, 1),
        "total_mb": round(total_kb / 1024, 1),
        "usage_percent": round(usage, 1),
    }


def disk_stats(path):
    """Festplatten-Belegung des Dateisystems, auf dem `path` liegt."""
    try:
        st = os.statvfs(path)
        total = st.f_frsize * st.f_blocks
        free = st.f_frsize * st.f_bavail
        used = total - free
        usage = (used / total * 100.0) if total else 0.0
        return {
            "used_gb": round(used / (1024 ** 3), 2),
            "total_gb": round(total / (1024 ** 3), 2),
            "usage_percent": round(usage, 1),
        }
    except Exception:
        return {"used_gb": 0.0, "total_gb": 0.0, "usage_percent": 0.0}


def pi_temperature_c():
    """CPU-Temperatur des Raspberry Pi in Grad Celsius."""
    # Bevorzugt das Pi-eigene Werkzeug vcgencmd, sonst die Kernel-Schnittstelle.
    if shutil.which("vcgencmd"):
        _, out, _ = run_command(["vcgencmd", "measure_temp"], timeout=5)
        match = re.search(r"temp=([0-9.]+)", out)
        if match:
            return float(match.group(1))

    temp_file = Path("/sys/class/thermal/thermal_zone0/temp")
    if temp_file.exists():
        try:
            raw = temp_file.read_text(encoding="utf-8").strip()
            return round(int(raw) / 1000.0, 1)
        except Exception:
            return None
    return None


def neustart_noetig():
    """Hat ein Systemupdate einen Neustart des Pi nötig gemacht?

    PiCraft richtet `unattended-upgrades` bewusst OHNE automatischen
    Neustart ein: Ein Server, der sich um sechs Uhr früh selbst neu
    startet, wirft Spieler heraus und kann mitten in einem
    Weltspeichervorgang stehen.

    Der Preis dafür ist, dass es jemand sagen muss — sonst läuft der Pi
    monatelang mit einem Kernel weiter, dessen Lücke längst geschlossen
    wäre. Debian legt in genau diesem Fall /run/reboot-required an; daneben
    steht in .pkgs, welche Pakete es waren.

    Gibt es die Datei nicht (der Normalfall, und auch auf jedem System
    ohne unattended-upgrades), ist die Antwort schlicht "nein".
    """
    # /var/run ist auf heutigen Systemen nur noch ein Verweis auf /run.
    # Beide Orte werden geprüft, weil ältere Anleitungen den alten nennen
    # und ein Verweis auch fehlen kann.
    for ort in ("/run/reboot-required", "/var/run/reboot-required"):
        if Path(ort).is_file():
            pakete = []
            try:
                pakete = sorted(set(
                    Path(ort + ".pkgs").read_text(encoding="utf-8",
                                                  errors="ignore").split()))
            except OSError:
                pass
            return {"noetig": True, "pakete": pakete}
    return {"noetig": False, "pakete": []}


def mcs_abgeschaltet():
    """Ist PiCraft als Ganzes abgeschaltet ("mcs aus")?

    Dann läuft auch der Backup-Timer nicht, und ein altes Backup ist kein
    Fehler, sondern die Folge einer Entscheidung. Ohne diese Unterscheidung
    meldete die Oberfläche nach zwei Tagen Sommerpause einen Backup-Ausfall,
    den es gar nicht gibt — und Alarm, der falsch liegt, wird nicht gelesen.

    Nur ein ausdrückliches "disabled" zählt: Auf einer älteren Installation
    ohne mcs.target liefert systemctl einen Fehler, und daraus darf keine
    Dauerwarnung werden.
    """
    code, out, _ = run_command(["systemctl", "is-enabled", "mcs.target"], timeout=5)
    return out.strip() == "disabled"

