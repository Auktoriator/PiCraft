#!/usr/bin/env python3
"""
app.py — Einstieg in die PiCraft Weboberflaeche.

Eine kleine Verwaltungsoberflaeche fuer den Minecraft-Server, erreichbar im
Heimnetz. Sie zeigt Serverzustand, Spieler, Systemwerte und Protokolle,
erlaubt Start/Stop/Neustart, Backup und Update, nimmt Chat-Nachrichten und
Serverbefehle entgegen und laesst die server.properties bearbeiten.

Diese Datei selbst tut nur dreierlei: Flask aufsetzen, den Verlaufssammler
starten, und mit "--summary" dieselbe Uebersicht als Text ausgeben (das
benutzt `mcs status`). Alles andere liegt daneben:

    einstellungen.py    Pfade und Zugangsdaten
    system.py           CPU, RAM, Platte, Temperatur, Dienste, Befehle
    protokoll.py        Server-Log: Spieler, Chat, Fehler, Ereignisse
    konsole.py          an den Server senden, erlaubte Aktionen
    rcon.py             den Server fragen und eine Antwort bekommen
    metrik.py           Verlaufsdaten sammeln und abfragen
    status.py           das Gesamtbild zusammensetzen
    sicherheit.py       Anmeldung, Ratenbegrenzung, CSRF
    routen.py           die JSON-Schnittstellen (/api/...)
    konfig.py           Konfigurationsdateien lesen, schreiben, vormerken
    spieler.py          Spielerdaten aus den Dateien, die Paper schreibt
    backups.py          Archive auflisten, pruefen, wiederherstellen
    plugins.py          Soll, Ist und Modrinth
    netz.py             Erreichbarkeit von aussen und der DNS-Name
    seite_anmeldung.py  anmelden und abmelden
    seite_start.py      die Startseite
    seite_spieler.py    wer war hier, und was darf er
    seite_konfig.py     Einstellungen und Expertenmodus
    seite_backups.py    Backups sehen, pruefen, zurueckspielen
    seite_plugins.py    Plugins und die Modrinth-Suche
    seite_karte.py      die Weltkarte im Rahmen
    seite_leistung.py   Kurven und Stellschrauben

Bis 2026-08-28 stand all das in dieser einen Datei. Bei 980 Zeilen war der
Punkt erreicht, an dem man zum Lesen einer Funktion durch drei Bildschirme
scrollt, die nichts mit ihr zu tun haben.

Je Seite der Oberflaeche gibt es ein Modul "seite_<name>.py". Es enthaelt
sowohl die Route der Seite als auch die kleinen Endpunkte fuer die Stuecke,
die HTMX nachlaedt — die gehoeren zusammen, weil sie dieselbe Seite
bedienen. Was mehr ist als Anzeigen (Spielerdaten, Konfigurationsdateien,
Backups, Plugins), steht in eigenen Modulen daneben.

Laeuft als systemd-Dienst mcs-admin.service.
"""

import argparse
import os
import sys
from pathlib import Path

from flask import Flask

from einstellungen import AUTH_ENABLED, BACKUP_DIR, lade_mcs_conf

# Die Werte aus mcs.conf muessen in der Umgebung stehen, BEVOR die uebrigen
# Module ihre Pfade daraus ableiten. Deshalb steht dieser Aufruf ganz oben —
# einstellungen.py erledigt ihn beim Import bereits selbst, hier steht er
# nur zur Sicherheit fuer den Fall eines anderen Einstiegs.
lade_mcs_conf()

from routen import seiten                    # noqa: E402  (erst nach lade_mcs_conf)
from seite_anmeldung import anmeldung        # noqa: E402
from seite_backups import backup_seite       # noqa: E402
from seite_historie import historie          # noqa: E402
from seite_karte import karte                # noqa: E402
from seite_konfig import konfiguration       # noqa: E402
from seite_leistung import leistung          # noqa: E402
from seite_plugins import plugin_seite       # noqa: E402
from seite_spieler import spieler            # noqa: E402
from seite_start import start                # noqa: E402
from sicherheit import (anmeldepflicht_erzwingen,  # noqa: E402
                        app_absichern)
from status import current_status            # noqa: E402
from system import service_state             # noqa: E402

try:
    import metrik                  # noqa: E402
except ImportError:  # pragma: no cover
    metrik = None


# Vorlagen und statische Dateien liegen neben dieser Datei. Die Pfade
# ausdruecklich zu setzen ist noetig, weil app.py nicht als Paket geladen
# wird — Flask wuerde sonst relativ zum Arbeitsverzeichnis suchen, und das
# ist bei einem systemd-Dienst nicht zwangslaeufig dasselbe.
_HIER = Path(__file__).parent
app = Flask(__name__,
            template_folder=str(_HIER / "templates"),
            static_folder=str(_HIER / "static"),
            static_url_path="/static")

# Sitzungs-Cookie, Ablaufzeit, Schutzmerkmale — alles an einer Stelle.
app_absichern(app)

# Eine Blueprint je Seite, dazu die JSON-Schnittstellen.
app.register_blueprint(seiten)
app.register_blueprint(anmeldung)
app.register_blueprint(start)
app.register_blueprint(leistung)
app.register_blueprint(spieler)
app.register_blueprint(historie)
app.register_blueprint(konfiguration)
app.register_blueprint(backup_seite)
app.register_blueprint(plugin_seite)
app.register_blueprint(karte)

# ERST NACH den Blueprints: Der Engpass prueft request.endpoint, und den gibt
# es nur fuer Routen, die schon eingehaengt sind. Ohne Anmeldung geht ab hier
# nichts mehr ausser sicherheit.OFFENE_ENDPUNKTE.
anmeldepflicht_erzwingen(app)


def print_summary():
    """Status als Text im Terminal ausgeben (für `mcs status`).

    Rückgabewert: 0 = alles in Ordnung, 1 = es gibt etwas zu tun (derzeit:
    das Backup ist zu alt oder zuletzt fehlgeschlagen, oder die
    Spielerzählung erkennt keine Beitritte). So kann `mcs status`
    das weiterreichen und man merkt es auch in einem Skript.
    """
    status = current_status()
    backup = status["last_backup"]
    backup_text = "keins"
    if backup.get("exists"):
        backup_text = (f"{backup['file']} (vor {backup['age_hours']} h, "
                       f"{backup['size_mb']} MB, {backup['count']} Stück vorhanden)")

    print("=== PiCraft Statusübersicht ===")
    if backup.get("mcs_aus"):
        print("Betrieb:          ABGESCHALTET (mcs aus) — kein Backup, keine Dienste")
    print(f"Zeitpunkt:        {status['timestamp']}")
    print(f"Dienst:           {status['service_state']}")
    print(f"Server läuft seit: {status['service_uptime']}")
    print(f"Spieler online:   {status['players_count']} -> {', '.join(status['players_online']) or '-'}")
    print(f"CPU-Auslastung:   {status['cpu_usage_percent']} %")
    print(f"CPU-Temperatur:   {status['cpu_temp_c']} °C")
    print(f"RAM:              {status['mem_used_mb']} / {status['mem_total_mb']} MB ({status['mem_usage_percent']} %)")
    print(f"Festplatte:       {status['disk_used_gb']} / {status['disk_total_gb']} GB ({status['disk_usage_percent']} %)")
    print(f"Last (1/5/15min): {status['loadavg_1m']} / {status['loadavg_5m']} / {status['loadavg_15m']}")
    print(f"Letztes Backup:   {backup_text}")

    # Die Kopien ausser Haus, je eine Zeile. Hier und nicht nur auf der
    # Backup-Seite, weil "mcs status" die Stelle ist, an der man nachsieht —
    # und eine Cloud-Kopie, die seit Tagen nichts mehr hochlaedt, ist
    # derselbe stille Ausfall wie ein Backup, das ausbleibt.
    import backups as backupdaten
    kopien = backupdaten.kopien()
    usb = kopien["usb"]
    if usb:
        print(f"USB-Kopie:        {usb.get('ergebnis')}, {usb.get('zeit')} — {usb.get('meldung')}")
    else:
        print(f"USB-Kopie:        noch nie (Stick mit dem Namen {kopien['usb_name']} einstecken)")
    cloud = kopien["cloud"]
    if not kopien["cloud_ziel"]:
        print("Cloud-Kopie:      nicht eingerichtet (mcs cloud einrichten)")
    elif kopien["cloud_laeuft"]:
        print("Cloud-Kopie:      läuft gerade (mcs cloud)")
    elif cloud:
        print(f"Cloud-Kopie:      {cloud.get('ergebnis')}, {cloud.get('zeit')} — {cloud.get('meldung')}")
    else:
        print("Cloud-Kopie:      eingerichtet, aber noch kein Lauf abgeschlossen")

    # Das Backup ist der Punkt, an dem Stillschweigen am teuersten ist —
    # deshalb steht die Warnung deutlich am Ende und nicht in einer Zeile
    # zwischen CPU-Temperatur und Festplatte.
    probleme = 0
    if backup.get("stale"):
        grenze = backup.get("warn_after_hours", 48)
        print("")
        print("  !!! ACHTUNG: BACKUP ---------------------------------------")
        if not backup.get("exists"):
            print("  Es gibt überhaupt kein Backup.")
        else:
            print(f"  Das neueste Backup ist {backup['age_hours']} Stunden alt")
            print(f"  (gemeldet wird ab {grenze} Stunden).")
        print(f"  Prüfen mit:  cat {BACKUP_DIR}/backup.log")
        print("  Sofort eines anlegen:  mcs backup")
        print("  -----------------------------------------------------------")
        probleme = 1

    # Zählt die Oberfläche falsch, zählt `mcs status` genauso falsch — die
    # Zeile „Spieler online: 0“ oben ist dann keine Auskunft. Vom 14. bis
    # 21.10.2026 stand sie so da, während zwei spielten.
    muster = status.get("muster_befund")
    if muster:
        print("")
        print("  !!! ACHTUNG: SPIELERZÄHLUNG -------------------------------")
        print(f"  {muster['zeugen']} Beitritte im Serverprotokoll, aber keiner wird erkannt.")
        print("  Die Spielerzahl oben stimmt deshalb nicht. Vermutlich hat")
        print("  Paper das Logformat geändert: tools/log-muster.sh prüfen.")
        print("  -----------------------------------------------------------")
        probleme = 1

    # Ein offener Neustart ist kein Fehler, aber eine Aufgabe — und `mcs
    # status` ist die Stelle, an der man nach Aufgaben sucht. Die Meldung
    # zählt nicht als Problem (kein Rückgabewert 1): Sonst meldete jedes
    # Skript, das den Rückgabewert auswertet, wochenlang einen Ausfall,
    # während in Wahrheit nur ein Kernel-Update wartet.
    neustart = status.get("neustart") or {}
    if neustart.get("noetig"):
        print("")
        print("  Hinweis: Ein Systemupdate wartet auf einen Neustart des Pi.")
        if neustart.get("pakete"):
            print(f"  Betroffen: {', '.join(neustart['pakete'])}")
        print("  Bei Gelegenheit, wenn niemand spielt:  mcs stop && sudo reboot")

    if kopien["cloud_fehler"] or kopien["cloud_zu_alt"]:
        print("")
        print("  !!! ACHTUNG: CLOUD-KOPIE ----------------------------------")
        if kopien["cloud_fehler"]:
            print(f"  Der letzte Lauf ist fehlgeschlagen: {cloud.get('meldung')}")
        else:
            print(f"  Seit mehr als {kopien['grenze']} Stunden keine Kopie außer Haus.")
        print("  Nachsehen:  mcs cloud    und    journalctl -u mcs-cloud-kopie")
        print("  -----------------------------------------------------------")
        probleme = 1

    if kopien["usb_fehler"]:
        print("")
        print("  !!! ACHTUNG: USB-KOPIE ------------------------------------")
        print(f"  Der letzte Versuch ist fehlgeschlagen: {usb.get('meldung')}")
        print("  Nachsehen:  mcs usb")
        print("  -----------------------------------------------------------")
        probleme = 1

    if backup.get("error"):
        print("")
        print("  !!! Letzter Backup-Fehlschlag:")
        print(f"  {backup['error']}")
        print("  (Diese Meldung verschwindet, sobald wieder ein geprüftes")
        print("   Backup zustande kommt.)")
        probleme = 1

    return probleme


def main():
    parser = argparse.ArgumentParser(description="PiCraft Admin-Tool")
    parser.add_argument("--summary", action="store_true",
                        help="Statusübersicht im Terminal ausgeben und beenden.")
    # Standardmäßig nur über den Pi selbst erreichbar. Wer die Oberfläche
    # im Heimnetz braucht, trägt in der .env die Adresse des Pi ein
    # (oder 0.0.0.0) — dann aber bitte mit Passwort und Firewall-Regel,
    # siehe README, Abschnitt Sicherheit.
    parser.add_argument("--host", default=os.getenv("MCS_ADMIN_HOST", "127.0.0.1"))
    parser.add_argument("--port", type=int, default=int(os.getenv("MCS_ADMIN_PORT", "8080")))
    args = parser.parse_args()

    if args.summary:
        # Rückgabewert weiterreichen: 1 bedeutet "es gibt etwas zu tun".
        raise SystemExit(print_summary())

    # Ohne Passwort nur auf dem Pi selbst. Die Oberflaeche ist so maechtig
    # wie ein SSH-Zugang, und AUTH_ENABLED haengt allein daran, dass
    # MCS_ADMIN_PASSWORD gesetzt ist. Eine geleerte Zeile oder ein
    # Tippfehler im Namen (MCS_ADMIN_PASSWORT) zusammen mit
    # MCS_ADMIN_HOST=0.0.0.0 oeffnete bis zum 23.09.2026 die Konsole fuer das
    # ganze Heimnetz — gewarnt wurde nur auf der Seite selbst, also dem, der
    # sie schon offen vor sich hatte. Lieber nicht starten: systemd gibt
    # nach fuenf Versuchen auf, und "mcs status" zeigt den Dienst als
    # ausgefallen.
    if not AUTH_ENABLED and args.host not in {"127.0.0.1", "::1", "localhost"}:
        print(f"Fehler: Kein Passwort gesetzt (MCS_ADMIN_PASSWORD), aber die "
              f"Oberflaeche soll auf {args.host} lauschen.", file=sys.stderr)
        print("Ohne Passwort startet sie nur auf 127.0.0.1. Passwort in der "
              ".env eintragen oder MCS_ADMIN_HOST=127.0.0.1 setzen.",
              file=sys.stderr)
        raise SystemExit(1)

    # Den Verlaufssammler mitstarten. Er laeuft nur, solange die
    # Weboberflaeche laeuft — und die gehoert zu mcs.target. Nach "mcs aus"
    # gibt es also keine Messwerte, was richtig ist: Dann laeuft ja auch
    # nichts, worueber sich etwas messen liesse.
    if metrik is not None:
        def messwerte():
            # EIN Statusabruf je Minute. Er enthaelt bereits TPS und MSPT,
            # die dabei ueber RCON geholt wurden — deshalb werden sie hier
            # mitgegeben statt den Server ein zweites Mal zu fragen.
            #
            # aufrufer="sammler": Die CPU-Messung braucht je Takt eine eigene
            # Probe. Teilte sie sich eine mit den Kacheln der Startseite,
            # maesse der Sammler nicht seine Minute, sondern die Restspanne
            # seit dem letzten Seitenaufruf (siehe system.cpu_auslastung).
            s = current_status(erzwingen=True, aufrufer="sammler")
            return {
                # War die Spanne zu kurz fuer eine Aussage, wird KEIN Wert
                # eingetragen. Ein NULL in der Kurve ist eine Luecke, die man
                # sieht; eine erfundene Zahl ist eine, die man glaubt.
                "cpu": s["cpu_usage_percent"] if s["cpu_frisch"] else None,
                "ram": s["mem_usage_percent"],
                "platte": s["disk_usage_percent"],
                "temp": s["cpu_temp_c"],
                "spieler": s["players_count"],
                "tps": s["tps"],
                "mspt": s["mspt"],
            }

        metrik.sammler_starten(
            werte_holen=messwerte,
            laeuft_pruefen=lambda: service_state() == "active",
        )

    # threaded=True: mehrere Browser-Anfragen gleichzeitig erlauben,
    # damit die Oberfläche flüssig bleibt.
    app.run(host=args.host, port=args.port, debug=False, threaded=True)


if __name__ == "__main__":
    main()
