#!/usr/bin/env python3
"""
backups.py — Welche Backups es gibt, und was man mit ihnen tun kann.

Der Backup-Mechanismus selbst ist der staerkste Teil des Projekts und wird
hier nicht angefasst: Online-Backup mit `save-off`, Warten auf die
Bestaetigung von `save-all flush`, Packen, Pruefen des Archivs, `save-on`,
Rotation, Dauerarchiv, Fehler-Merkzettel. Dieses Modul liest nur, was dabei
entsteht, und ruft die vorhandenen Werkzeuge auf.

Zwei Dinge, die dabei mit Bedacht gebaut sind:

**Wiederherstellen ist die gefaehrlichste Handlung der ganzen Oberflaeche.**
Sie tauscht Weltdaten aus. Deshalb: nur bei gestopptem Server, und der Name
des Archivs muss abgetippt werden -- ein Klick auf "ja" passiert zu leicht.
`mcs restore` legt die bisherigen Weltordner ausserdem beiseite statt sie
zu loeschen; wer sich vertut, kann zurueck.

**Loeschen ist endgueltig.** Ein Backup zu loeschen, das man morgen braucht,
merkt man erst morgen. Deshalb wird auch hier der Name verlangt, und das
neueste Backup laesst sich gar nicht loeschen.
"""

import os
import re
import time
from pathlib import Path

from einstellungen import ARCHIV_DIR, BACKUP_DIR, BACKUP_WARN_HOURS, MCS_DIR
from system import mcs_abgeschaltet, run_command, service_state

# Nur was das Backup-Skript selbst erzeugt. Eine von Hand abgelegte Datei
# soll weder in der Rotation noch in dieser Liste als Backup gelten.
_NAME = re.compile(r"^backup_.*\.tar\.gz$")


def _eintrag(pfad, herkunft):
    stat = pfad.stat()
    alter = (time.time() - stat.st_mtime) / 3600.0
    return {
        "name": pfad.name,
        "pfad": str(pfad),
        "mtime": stat.st_mtime,
        "herkunft": herkunft,
        "groesse_mb": round(stat.st_size / (1024 * 1024), 1),
        "zeit": time.strftime("%d.%m.%Y %H:%M", time.localtime(stat.st_mtime)),
        "alter_stunden": round(alter, 1),
        "alter_text": (f"vor {alter:.0f} h" if alter >= 1
                       else f"vor {alter * 60:.0f} min"),
    }


def liste():
    """Alle Backups, neueste zuerst — aus Rotation und Dauerarchiv.

    Das Dauerarchiv ist kein zweiter Satz Dateien: Das Backup-Skript legt
    dort Hardlinks an. Zwei Einträge können also auf dieselben Daten
    zeigen, und beide zusammen belegen nur einmal Platz. Deshalb steht die
    Herkunft dabei — sonst wundert man sich über die Summe.
    """
    gefunden = []
    for verzeichnis, herkunft in ((BACKUP_DIR, "Rotation"),
                                  (ARCHIV_DIR, "Dauerarchiv")):
        ordner = Path(verzeichnis)
        if not ordner.is_dir():
            continue
        for datei in ordner.iterdir():
            if datei.is_file() and _NAME.match(datei.name):
                try:
                    gefunden.append(_eintrag(datei, herkunft))
                except OSError:
                    continue
    # Neueste zuerst, nach der exakten Aenderungszeit. Hier standen zwei
    # Sortierlaeufe: nach "zeit" als TEXT ("30.09." galt als neuer als
    # "01.10.") und danach nach dem auf 0,1 h gerundeten Alter. Einer
    # genuegt. Hardlinks (Rotation + Dauerarchiv) haben dieselbe Zeit und
    # bleiben dank stabiler Sortierung in der Reihenfolge Rotation zuerst —
    # _finden() und der Schutz des neuesten Backups haengen daran.
    gefunden.sort(key=lambda e: e["mtime"], reverse=True)
    return gefunden


def zustand(eintraege):
    """Das Gesamtbild: gibt es Backups, sind sie frisch, ging etwas schief?"""
    fehler = ""
    merkzettel = Path(BACKUP_DIR) / ".letzter-fehler"
    if merkzettel.is_file():
        try:
            fehler = merkzettel.read_text(encoding="utf-8", errors="ignore").strip()
        except OSError:
            fehler = "(Der Fehler-Merkzettel ist nicht lesbar.)"

    abgeschaltet = mcs_abgeschaltet()
    neuestes = eintraege[0] if eintraege else None
    zu_alt = bool(neuestes) and neuestes["alter_stunden"] > BACKUP_WARN_HOURS

    return {
        "anzahl": len(eintraege),
        "neuestes": neuestes,
        "zu_alt": zu_alt and not abgeschaltet,
        "keines": not eintraege and not abgeschaltet,
        "abgeschaltet": abgeschaltet,
        "grenze": BACKUP_WARN_HOURS,
        "fehler": fehler,
        "gesamt_mb": round(sum(e["groesse_mb"] for e in eintraege
                               if e["herkunft"] == "Rotation"), 1),
    }


# ----------------------------------------------------------------------------
# Die Uhrzeit des Backup-Timers
# ----------------------------------------------------------------------------
# Sie steht in mcs-backup.timer und laesst sich nur dort aendern: OnCalendar
# liest systemd nicht aus einer EnvironmentFile, die mcs.conf scheidet also
# aus.
#
# Geaendert wird trotzdem NICHT die Einheitendatei, sondern ein Drop-in:
# deploy.sh ersetzt die Einheit beim naechsten Ausrollen, und die
# eingestellte Zeit waere stillschweigend wieder 04:00. Genau dieses Muster —
# eine Einstellung, die ein Ausrollen unbemerkt zurueckstellt — ist der Grund
# fuer den ganzen Abschnitt "Trennung von Vorlage und Installation" in
# CLAUDE.md. Das Drop-in gehoert der Installation, die Einheit der Vorlage.
ZEIT_DROPIN_DIR = "/etc/systemd/system/mcs-backup.timer.d"
ZEIT_DROPIN = f"{ZEIT_DROPIN_DIR}/zeit.conf"

_ONCALENDAR = re.compile(r"OnCalendar=(.*?)\s*(?:;|\})")


def uhrzeit_lesen():
    """Die Zeitangabe, die WIRKLICH gilt.

    Gefragt wird systemd, nicht die Datei — dieselbe Regel wie bei
    `systemctl show … -p WantedBy`: Die Einheitendatei ist eine Behauptung,
    die Auskunft von systemd ist der Zustand. Und nur sie kennt das Drop-in.

    Erst wenn systemd nicht antwortet (im Container ist `systemctl` ein
    Platzhalter), werden die Dateien gelesen — Drop-in zuerst, weil es die
    Einheit uebersteuert.
    """
    code, aus, _ = run_command(
        ["systemctl", "show", "mcs-backup.timer",
         "--property=TimersCalendar", "--value"], timeout=5)
    if code == 0:
        treffer = _ONCALENDAR.search(aus or "")
        if treffer:
            return treffer.group(1).strip()

    for pfad in (ZEIT_DROPIN, "/etc/systemd/system/mcs-backup.timer"):
        gefunden = ""
        try:
            for zeile in Path(pfad).read_text(encoding="utf-8",
                                              errors="ignore").splitlines():
                if zeile.startswith("OnCalendar="):
                    gefunden = zeile.split("=", 1)[1].strip()
        except OSError:
            continue
        if gefunden:
            return gefunden
    return ""


def uhrzeit_setzen(wert):
    """Setzt die Backup-Uhrzeit als Drop-in. Liefert (art, meldung)."""
    wert = (wert or "").strip()
    if not wert:
        return "fehler", "Es wurde keine Uhrzeit angegeben."

    # PRUEFEN, BEVOR etwas geschrieben wird — und zwar von systemd selbst.
    # Eine unsinnige Eingabe darf den Timer nicht kaputtmachen: Ein Drop-in
    # mit einem ungueltigen OnCalendar laesst die ganze Einheit scheitern,
    # und dann faellt das Backup aus. Lautlos, denn wer schaut nach einem
    # Timer, den er gerade erst eingestellt hat?
    #
    # Und die Pruefung selbst muss dicht sein (Sicherheitspruefung
    # 22.10.2026): "--help" ist fuer systemd-analyze keine Zeitangabe,
    # sondern eine Option — es endete mit 0, die Pruefung galt als bestanden,
    # und "OnCalendar=--help" legte den Timer still. Deshalb: nichts, was mit
    # "-" beginnt, keine Steuerzeichen (ein Zeilenumbruch schriebe eine
    # zweite Zeile ins Drop-in), "--" vor den Wert, und bestanden ist nur,
    # wozu systemd eine Normalform nennt.
    if wert.startswith("-") or any(ord(z) < 32 or ord(z) == 127 for z in wert):
        return "fehler", (
            f"„{wert}“ ist keine Zeitangabe. Es wurde nichts geändert. "
            "Beispiele: „04:00“, „*-*-* 03:30:00“, „Mon..Fri 05:00“.")
    code, aus, fehler = run_command(["systemd-analyze", "calendar", "--", wert], timeout=5)
    if code == 0 and "Normalized form:" not in aus:
        code = 1
    if code != 0:
        return "fehler", (
            f"„{wert}“ versteht systemd nicht: "
            f"{(fehler or aus or '').splitlines()[0] if (fehler or aus) else 'ungültig'}. "
            "Es wurde nichts geändert. Beispiele: „04:00“, "
            "„*-*-* 03:30:00“, „Mon..Fri 05:00“.")

    inhalt = (
        "# Von der PiCraft-Weboberflaeche geschrieben.\n"
        "#\n"
        "# Diese Datei gehoert der INSTALLATION, die Einheit daneben der\n"
        "# Vorlage. Ein ./deploy.sh ersetzt die Einheit und fasst dieses\n"
        "# Drop-in nicht an — sonst stuende die Uhrzeit danach wieder auf\n"
        "# 04:00, ohne dass es jemandem auffiele.\n"
        "[Timer]\n"
        "# Leeren Wert voranstellen: OnCalendar ist eine LISTE. Ohne diese\n"
        "# Zeile kaeme die neue Zeit zur alten hinzu, statt sie zu ersetzen —\n"
        "# das Backup liefe dann zweimal taeglich.\n"
        "OnCalendar=\n"
        f"OnCalendar={wert}\n")

    schritte = [
        (["sudo", "/usr/bin/mkdir", "-p", ZEIT_DROPIN_DIR], None),
        (["sudo", "/usr/bin/tee", ZEIT_DROPIN], inhalt),
        (["sudo", "/usr/bin/systemctl", "daemon-reload"], None),
        # daemon-reload allein genuegt nicht: Ein laufender Timer behaelt
        # seinen berechneten Termin, bis er neu gestartet wird.
        (["sudo", "/usr/bin/systemctl", "restart", "mcs-backup.timer"], None),
    ]
    for befehl, eingabe in schritte:
        code, aus, fehler = run_command(befehl, timeout=15, eingabe=eingabe)
        if code != 0:
            return "fehler", (
                f"„{' '.join(befehl[1:])}“ ist fehlgeschlagen: "
                f"{fehler or aus or f'Rückgabewert {code}'}. "
                "Möglicherweise fehlen die sudo-Regeln — dann hilft "
                "./install-admin.sh erneut auszuführen.")

    # Ob es gewirkt hat, sagt systemd — nicht die Datei, die wir gerade
    # selbst geschrieben haben.
    code, naechster, _ = run_command(
        ["systemctl", "show", "mcs-backup.timer",
         "--property=NextElapseUSecRealtime", "--value"], timeout=5)
    jetzt_gueltig = uhrzeit_lesen()
    if jetzt_gueltig != wert:
        return "warnung", (
            f"Geschrieben, aber systemd meldet weiterhin „{jetzt_gueltig}“. "
            f"Bitte nachsehen: systemctl cat mcs-backup.timer")

    naechster = naechster.strip() if code == 0 else ""
    return "gut", (f"Backup läuft künftig „{wert}“."
                   + (f" Nächster Lauf: {naechster}." if naechster else ""))


def einstellungen():
    """Zeitplan und Aufbewahrung — aus Timer und mcs.conf."""
    import konfig
    conf = konfig.mcs_conf_lesen()

    uhrzeit = uhrzeit_lesen()

    # Wann der Timer das nächste Mal läuft — die ehrlichste Auskunft, denn
    # sie kommt von systemd selbst und nicht aus unserer Auslegung der
    # Zeitangabe.
    naechster = ""
    code, aus, _ = run_command(
        ["systemctl", "show", "mcs-backup.timer",
         "--property=NextElapseUSecRealtime", "--value"], timeout=5)
    if code == 0 and aus.strip():
        naechster = aus.strip()

    return {
        "uhrzeit": uhrzeit,
        "naechster": naechster,
        "behalten": conf.get("MCS_BACKUP_BEHALTEN", "10"),
        "archiv_jedes": conf.get("MCS_ARCHIV_JEDES", "10"),
        "warnung_stunden": conf.get("MCS_BACKUP_WARNUNG_STUNDEN", "48"),
        "extern": conf.get("MCS_EXTERN_DIR", ""),
        "extern_da": bool(conf.get("MCS_EXTERN_DIR")) and
                     os.path.isdir(conf.get("MCS_EXTERN_DIR", "")),
        "archiv_dir": ARCHIV_DIR,
        "backup_dir": BACKUP_DIR,
    }


# ----------------------------------------------------------------------------
# Kopien auf den USB-Stick und in die Cloud (seit v1.4)
# ----------------------------------------------------------------------------
# Beide Kopien schreiben nach jedem Lauf eine kleine Datei mit
# Schluessel=Wert (backup/usb-kopie.sh, backup/cloud-kopie.sh). Gelesen wird
# nur sie: Die Oberflaeche fragt weder den Stick noch die Cloud selbst. Das
# ginge beim Seitenaufbau nach aussen (Lastenheft 5.7.2), dauerte, und es
# waere der zweite Weg zur selben Auskunft, der die Regeln des ersten nicht
# kennt.
USB_STAND = "/var/lib/picraft/usb-kopie.stand"
CLOUD_STAND = os.path.join(BACKUP_DIR, "cloud-kopie.stand")


def _stand_lesen(pfad):
    werte = {}
    try:
        with open(pfad, encoding="utf-8", errors="replace") as datei:
            for zeile in datei:
                schluessel, gleich, wert = zeile.rstrip("\n").partition("=")
                if gleich:
                    werte[schluessel] = wert
    except OSError:
        return None
    try:
        werte["alter_stunden"] = round((time.time() - int(werte.get("epoch", ""))) / 3600, 1)
    except ValueError:
        werte["alter_stunden"] = None
    return werte


def kopien():
    """Stand der USB- und der Cloud-Kopie, mit dem, was daran auffaellt.

    Die USB-Kopie veraltet nicht: Ein Stick, der in der Schublade liegt, ist
    kein Fehler. Gemeldet wird nur ein FEHLGESCHLAGENER letzter Versuch.

    Die Cloud-Kopie dagegen laeuft nach jedem Backup. Ist sie eingerichtet
    und aelter als die Backup-Warngrenze, ist das ein Ausfall — ausser
    PiCraft ist abgeschaltet (dann entstehen keine Backups) oder der erste,
    stundenlange Abgleich laeuft noch.
    """
    import konfig
    conf = konfig.mcs_conf_lesen()
    usb = _stand_lesen(USB_STAND)
    cloud = _stand_lesen(CLOUD_STAND)
    ziel = conf.get("MCS_CLOUD_ZIEL", "")

    _, aus, _ = run_command(["systemctl", "is-active", "mcs-cloud-kopie.service"], timeout=5)
    cloud_laeuft = aus.strip() in ("activating", "active", "reloading")
    alter = (cloud or {}).get("alter_stunden")
    cloud_zu_alt = (bool(ziel) and not mcs_abgeschaltet() and not cloud_laeuft
                    and (alter is None or alter > BACKUP_WARN_HOURS))

    return {
        "usb_name": conf.get("MCS_USB_NAME", "") or "MCS-BACKUP",
        "usb": usb,
        "usb_fehler": bool(usb) and usb.get("ergebnis") == "fehler",
        "cloud_ziel": ziel,
        "cloud": cloud,
        "cloud_laeuft": cloud_laeuft,
        "cloud_fehler": bool(ziel) and bool(cloud) and cloud.get("ergebnis") == "fehler",
        "cloud_zu_alt": cloud_zu_alt,
        "grenze": BACKUP_WARN_HOURS,
    }


# ----------------------------------------------------------------------------
# Handlungen
# ----------------------------------------------------------------------------
def _finden(name):
    """Den vollen Pfad zu einem Archiv — oder None.

    Der Name kommt aus dem Browser, also wird er geprüft und nicht
    zusammengebaut: Nur ein Eintrag, der wirklich in der Liste steht,
    zählt. Damit ist auch „../../etc/passwd" erledigt, ohne dass irgendwo
    eine Pfadprüfung von Hand stehen müsste.
    """
    for eintrag in liste():
        if eintrag["name"] == name:
            return eintrag
    return None


def pruefen(name):
    """`mcs restore --probe`: liest das Archiv ganz und packt es probeweise aus.

    Gefahrlos auch bei laufendem Server — es wird nichts angefasst.
    """
    eintrag = _finden(name)
    if eintrag is None:
        return "fehler", "Dieses Backup gibt es nicht."

    code, aus, fehler = run_command(
        ["mcs", "restore", eintrag["pfad"], "--probe"], timeout=1800)
    text = (aus or "") + (("\n" + fehler) if fehler else "")
    if code == 0:
        return "gut", text or "Das Backup ist in Ordnung."
    return "fehler", text or f"Die Prüfung ist fehlgeschlagen (Rückgabewert {code})."


def wiederherstellen(name, bestaetigung, alles=False):
    """Spielt ein Backup zurück. Die gefährlichste Handlung der Oberfläche.

    Drei Bedingungen, alle drei nötig:

    1. Das Archiv muss in der Liste stehen.
    2. Der Server muss **gestoppt** sein. Weltdaten unter einem laufenden
       Server auszutauschen macht die Welt kaputt; `mcs restore` verweigert
       sich ohnehin, aber die Oberfläche soll gar nicht erst so weit
       kommen.
    3. Der Name muss **abgetippt** sein. Ein Klick auf „ja" passiert zu
       leicht — und was hier passiert, lässt sich nicht mit einem zweiten
       Klick zurücknehmen.
    """
    eintrag = _finden(name)
    if eintrag is None:
        return "fehler", "Dieses Backup gibt es nicht."
    if (bestaetigung or "").strip() != name:
        return "fehler", ("Zur Sicherheit muss der Name des Backups genau "
                          f"abgetippt werden: {name}")
    # frisch=True: Hier haengt eine Sicherheitsentscheidung dran — Weltdaten
    # unter einem laufenden Server auszutauschen macht die Welt kaputt. Ein
    # zwei Sekunden alter Zustand ist dafuer zu viel.
    if service_state(frisch=True) == "active":
        return "fehler", ("Der Server läuft. Weltdaten dürfen nicht unter "
                          "einem laufenden Server ausgetauscht werden — erst "
                          "stoppen.")

    befehl = ["mcs", "restore", eintrag["pfad"], "--ja"]
    if alles:
        befehl.append("--alles")

    # Kein Hintergrundlauf: Wer wiederherstellt, will wissen, ob es geklappt
    # hat, und nicht in einem Protokoll nachsehen. Eine halbe Stunde
    # Zeitlimit reicht auch für eine große Welt auf einer NVMe.
    code, aus, fehler = run_command(befehl, timeout=1800)
    text = (aus or "") + (("\n" + fehler) if fehler else "")
    if code == 0:
        return "gut", (text + "\n\nDie bisherigen Weltordner liegen als "
                       "*.vor-restore-* daneben. Erst löschen, wenn der "
                       "Server läuft und alles gut aussieht.")
    return "fehler", text or f"Fehlgeschlagen (Rückgabewert {code})."


def loeschen(name, bestaetigung):
    """Löscht ein Archiv. Endgültig.

    Das **neueste** Backup lässt sich nicht löschen. Wer alle löscht, steht
    ohne da — und merkt es erst, wenn er eines braucht. Die Rotation räumt
    alte Backups ohnehin von selbst ab; dieser Knopf ist für den Sonderfall,
    nicht für den Alltag.
    """
    eintrag = _finden(name)
    if eintrag is None:
        return "fehler", "Dieses Backup gibt es nicht."
    if (bestaetigung or "").strip() != name:
        return "fehler", ("Zur Sicherheit muss der Name des Backups genau "
                          f"abgetippt werden: {name}")

    alle = liste()
    if alle and alle[0]["name"] == name:
        return "fehler", ("Das neueste Backup lässt sich nicht löschen. Erst "
                          "ein neues anlegen, dann geht es.")

    try:
        os.remove(eintrag["pfad"])
    except OSError as fehler:
        return "fehler", f"Löschen fehlgeschlagen: {fehler}"
    return "gut", f"{name} wurde gelöscht."


def zweitziel_setzen(pfad):
    """Setzt MCS_EXTERN_DIR — das zweite Backup-Ziel auf anderer Platte.

    Der Sinn ist eine Kopie auf einem ANDEREN Datenträger: Eine defekte
    NVMe nimmt alles mit, was auf ihr liegt, egal wie viele Kopien es sind.
    Deshalb wird geprüft, ob der Pfad überhaupt existiert — ein Tippfehler
    hieße, dass die Zweitkopie monatelang stillschweigend ausbleibt.
    """
    import konfig
    pfad = (pfad or "").strip()
    if pfad and not os.path.isdir(pfad):
        return "fehler", (f"„{pfad}“ ist kein Verzeichnis. Ist der Datenträger "
                          "eingehängt? Ohne gültiges Ziel bliebe die "
                          "Zweitkopie stillschweigend aus.")
    try:
        konfig.mcs_conf_setzen({"MCS_EXTERN_DIR": pfad})
    except ValueError as fehler:
        return "fehler", str(fehler)
    if not pfad:
        return "gut", "Zweitziel abgeschaltet."
    return "gut", (f"Zweitziel auf {pfad} gesetzt. Es wird ab dem nächsten "
                   "Backup-Lauf mitbeschrieben.")


# ----------------------------------------------------------------------------
# Benachrichtigung bei Fehlschlag
# ----------------------------------------------------------------------------
# Das Statusfeld auf dieser Seite ist gut, aber PASSIV: Es hilft nur dem, der
# von sich aus nachsieht. Vom 2026-05-18 bis zum 2026-07-27 hat genau das
# gefehlt — zwei Monate ohne Backup, unbemerkt.
#
# Die Arbeit macht tools/benachrichtigung.sh; hier stehen nur die
# Einstellungen und der Testknopf.
def benachrichtigung():
    """Was gerade eingestellt ist — plus ein Vorschlag für ein sicheres Thema."""
    import konfig
    conf = konfig.mcs_conf_lesen()
    thema = conf.get("MCS_NTFY_THEMA", "")
    return {
        "thema": thema,
        "an": bool(thema),
        "server": conf.get("MCS_NTFY_SERVER", "https://ntfy.sh"),
        "vorschlag": _themenvorschlag(),
        "skript_da": os.path.isfile(f"{MCS_DIR}/benachrichtigung.sh"),
    }


def _themenvorschlag():
    """Ein Themenname, den niemand errät.

    Bei ntfy.sh ist der Themenname das ganze Geheimnis — es gibt kein
    Passwort. Wer ihn kennt, liest mit und kann selbst Nachrichten
    schicken. Ein Vorschlag wie „mcs-backup“ wäre deshalb keine
    Bequemlichkeit, sondern eine Falle: Er sieht nach einer Vorgabe aus,
    die man übernehmen darf.

    `secrets` statt `random`: Der Unterschied kostet hier nichts und ist
    genau der zwischen „schwer zu raten“ und „vorhersagbar“.
    """
    import secrets
    import string
    zeichen = string.ascii_lowercase + string.digits
    return "mcs-" + "".join(secrets.choice(zeichen) for _ in range(12))


def benachrichtigung_setzen(thema, server=""):
    import konfig
    thema = (thema or "").strip()
    server = (server or "").strip() or "https://ntfy.sh"

    # ntfy-Themen dürfen Buchstaben, Ziffern, Unterstrich und Bindestrich
    # enthalten. Streng geprüft wird, weil der Wert in eine mcs.conf-Zeile
    # geschrieben wird, die Shell UND systemd einlesen: Ein Leerzeichen oder
    # ein Anführungszeichen darin bringt beim nächsten Dienststart Dateien
    # zu Fall, die mit Benachrichtigungen nichts zu tun haben.
    if thema and not re.fullmatch(r"[A-Za-z0-9_-]{1,64}", thema):
        return "fehler", ("Ein Thema darf nur Buchstaben, Ziffern, "
                          "Bindestrich und Unterstrich enthalten (höchstens 64).")
    if not re.fullmatch(r"https?://[A-Za-z0-9._:/-]{1,200}", server):
        return "fehler", "Die Serveradresse muss mit http:// oder https:// beginnen."

    try:
        konfig.mcs_conf_setzen({"MCS_NTFY_THEMA": thema,
                                "MCS_NTFY_SERVER": server})
    except ValueError as fehler:
        return "fehler", str(fehler)

    if not thema:
        return "gut", ("Benachrichtigung abgeschaltet. Ein Fehlschlag steht "
                       "dann nur noch hier und in „mcs status“.")
    return "gut", ("Gespeichert. Jetzt bitte eine Testnachricht schicken — "
                   "eine Benachrichtigung, die man nie ausprobiert hat, "
                   "ist keine.")


def benachrichtigung_testen():
    """Schickt eine Testnachricht und sagt ehrlich, was dabei herauskam."""
    skript = f"{MCS_DIR}/benachrichtigung.sh"
    if not os.path.isfile(skript):
        return "fehler", (f"{skript} fehlt. Einmal „./deploy.sh“ im "
                          "Repository laufen lassen.")
    code, aus, fehler = run_command([skript, "--test"], timeout=30)
    if code == 0:
        return "gut", (aus or "Verschickt.") + " Kommt nichts an, ist meist " \
                      "ein anderes Thema in der App abonniert."
    # 78 ist EX_CONFIG: nicht eingerichtet. Das ist kein Fehler des Systems,
    # sondern eine fehlende Angabe — und die Meldung soll das auch sagen.
    if code == 78:
        return "warnung", "Es ist kein Thema eingetragen — oben eines setzen."
    return "fehler", (fehler or aus or f"Fehlgeschlagen (Code {code}).")


def protokoll(zeilen=60):
    """Die letzten Zeilen aus backup.log."""
    from system import read_last_lines
    return read_last_lines(f"{BACKUP_DIR}/backup.log", max_lines=zeilen)


def platz():
    """Wie viel Platz auf der Backup-Platte noch frei ist."""
    from system import disk_stats
    return disk_stats(BACKUP_DIR if os.path.isdir(BACKUP_DIR) else MCS_DIR)
