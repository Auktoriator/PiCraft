#!/usr/bin/env python3
"""
konsole.py — Mit dem Server sprechen.

Zwei Wege, mit Absicht nebeneinander:

  screen  schickt eine Zeile in die Serverkonsole. Schnell und einfach, aber
          ohne Rueckweg — man erfaehrt nicht, was der Server geantwortet hat.
  rcon    stellt eine Frage und bekommt eine Antwort (siehe rcon.py).

Ausserdem die Liste der erlaubten Aktionen: Nur was hier steht, kann die
Oberflaeche ueberhaupt ausloesen.
"""

from einstellungen import (ALLOW_HOST_POWER, BACKUP_DIR, BACKUP_SCRIPT,
                           MCS_SCREEN_SESSION, MCS_SERVER_DIR, MCS_SERVICE,
                           UPDATE_SCRIPT)
from system import run_command

# ----------------------------------------------------------------------------
# Aktionen (Buttons in der Oberfläche)
# ----------------------------------------------------------------------------
def action_command(action_name):
    """Übersetzt einen Aktionsnamen in den passenden Systembefehl.

    Nur die hier aufgeführten Aktionen sind überhaupt möglich — die
    Oberfläche kann also keine beliebigen Befehle auf dem Pi ausführen.

    - Dienststeuerung braucht Administratorrechte: dafür gibt es eng
      begrenzte sudo-Regeln (siehe install-admin.sh). Der volle Pfad
      /usr/bin/systemctl muss exakt zu diesen Regeln passen.
    - Backup und Update laufen bewusst OHNE root, als normaler Benutzer pi.
    """
    if action_name == "start_server":
        return {"mode": "sync", "cmd": ["sudo", "/usr/bin/systemctl", "start", MCS_SERVICE]}
    if action_name == "stop_server":
        return {"mode": "sync", "cmd": ["sudo", "/usr/bin/systemctl", "stop", MCS_SERVICE]}
    if action_name == "restart_server":
        return {"mode": "sync", "cmd": ["sudo", "/usr/bin/systemctl", "restart", MCS_SERVICE]}
    if action_name == "backup_now":
        return {"mode": "background", "cmd": ["/usr/bin/bash", BACKUP_SCRIPT], "cwd": BACKUP_DIR}
    if action_name == "update_paper":
        # Im Vordergrund, nicht im Hintergrund: Wer klickt, will wissen, was
        # herauskam. Ein Download von gut 60 MB dauerte am 03.10.2026 sechs
        # Sekunden; die Zeitgrenze deckt curls eigene (600 s) mit ab.
        # Ohne Zusatz holt das Skript den neuesten Build derselben
        # Minecraft-Version — einen Versionswechsel gibt es hier bewusst nicht.
        return {"mode": "sync", "cmd": ["/usr/bin/bash", UPDATE_SCRIPT],
                "cwd": MCS_SERVER_DIR, "timeout": 900, "protokoll": True}
    # Neustart und Herunterfahren des PI gibt es nur ueber die API
    # (POST /api/action/reboot_host), nicht als Knopf: Keine Vorlage rendert
    # sie, und das ist Absicht — ein Knopf, der den ganzen Pi ausschaltet,
    # gehoert nicht neben "Server neu starten", wo man ihn im Vorbeiklicken
    # trifft. Am 2026-08-31 nachgesehen, weil eine Pruefung sie fuer toten
    # Code hielt: Sie sind erreichbar, nur eben absichtlich unbequem. Der
    # README verspricht auch keinen Knopf, sondern nennt es "aktivierbar".
    if action_name == "reboot_host" and ALLOW_HOST_POWER:
        return {"mode": "sync", "cmd": ["sudo", "/usr/bin/systemctl", "reboot"]}
    if action_name == "shutdown_host" and ALLOW_HOST_POWER:
        return {"mode": "sync", "cmd": ["sudo", "/usr/bin/systemctl", "poweroff"]}
    return None


def sanitize_console_input(text):
    """Entschärft Eingaben für die Konsole (keine Zeilenumbrüche, max. 500 Zeichen)."""
    cleaned = (text or "").replace("\r", " ").replace("\n", " ").strip()
    return cleaned[:500]


def fuer_screen_escapen(text):
    """Entschärft Rückwärtsschrägstrich, ^ und $ für den screen-Befehl "stuff".

    Dieselben drei wie in server/lib-konsole.sh. screen deutet den
    Rückwärtsschrägstrich als Steuerzeichen: Ein "\\r" mitten in einer
    Chat-Nachricht entspräche einem Druck auf die Eingabetaste — alles danach
    landete als eigener Serverbefehl.
    """
    # Ebenso "^": screen liest "^M" als Wagenruecklauf — "say hallo^Mstop"
    # kam am 23.09.2026 als zwei Zeilen an, die zweite "stop". \^ ist das
    # woertliche Zeichen; es muss NACH der Verdopplung kommen.
    # Und "$": screen setzt $VAR/${VAR} aus der Umgebung der Sitzung ein —
    # der des Minecraft-Dienstes, samt Geheimnissen aus seinen Drop-ins.
    # "say ${…}" schickte sie an alle Spieler (23.09.2026, nachgestellt).
    return (text.replace("\\", "\\\\").replace("^", "\\^")
            .replace("$", "\\$"))


def send_to_minecraft_console(line):
    """Schickt eine Zeile an die Server-Konsole (über die screen-Sitzung)."""
    line = fuer_screen_escapen(line)
    cmd = ["screen", "-S", MCS_SCREEN_SESSION, "-p", "0", "-X", "stuff", f"{line}\r"]
    code, out, err = run_command(cmd, timeout=5)
    if code != 0:
        details = err or out or "unbekannter Fehler"
        return False, f"Senden an screen-Sitzung '{MCS_SCREEN_SESSION}' fehlgeschlagen: {details}"
    return True, "gesendet"
