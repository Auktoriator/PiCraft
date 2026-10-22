#!/usr/bin/env python3
"""
seite_start.py — Die Startseite.

Leitfrage (Lastenheft 5.7.4): *Was will ich in fuenf Sekunden vom Handy aus
wissen?* Daraus folgt alles Weitere:

  - Ein Balken ganz oben, der sagt, ob etwas zu tun ist.
  - Sechs Kacheln mit den Werten, nach denen man sonst suchen wuerde.
  - Ein Eingabefeld fuer Chat oder Befehl.
  - Die letzten fuenf Vorgaenge.

Alles andere ist eine Seite tiefer richtig aufgehoben. Der schwerste Teil
einer Startseite ist, was NICHT darauf steht.

Die Kacheln erneuern sich ueber HTMX alle fuenf Sekunden. Sie holen dafuer
nur ihr eigenes Stueck HTML, nicht die ganze Seite — deshalb bleibt eine
halb getippte Chat-Nachricht im Eingabefeld stehen.
"""

from flask import Blueprint, render_template, request

import rcon
from einstellungen import ALLOW_HOST_POWER, AUTH_ENABLED, MCS_SERVICE
from konsole import (action_command, sanitize_console_input,
                     send_to_minecraft_console)
from protokoll import letzte_ereignisse
from sicherheit import auth_required, nur_eigene_oberflaeche
from status import current_status
from system import run_background, run_command, service_state

start = Blueprint("start", __name__)


# ----------------------------------------------------------------------------
# Das Gesamtbild
# ----------------------------------------------------------------------------
# Der Balken oben auf der Seite ist eine Prüfliste, kein Gefühl. Sieben
# Fragen, die man sonst einzeln nachsehen müsste; der Balken ist voll, wenn
# alle mit Ja beantwortet sind. (Hier stand „fünf“ — es waren schon sechs,
# bevor am 21.10.2026 die siebte dazukam.)
#
# Warum eine Prüfliste und keine berechnete "Gesundheit" in Prozent? Weil
# eine Zahl wie "82 %" niemandem sagt, was zu tun ist. Die Liste sagt es.
def gesamtbild(status):
    """Fasst den Zustand in Prüfpunkte zusammen (für die Erfahrungsleiste)."""
    backup = status["last_backup"]
    tps = status.get("tps")
    temp = status.get("cpu_temp_c")
    neustart = status.get("neustart") or {}

    if backup.get("mcs_aus"):
        # Nach "mcs aus" ist ausgeschaltet der SOLL-Zustand. Ein roter
        # Balken wäre hier schlicht falsch — und Alarm, der falsch liegt,
        # wird bald gar nicht mehr gelesen.
        return {"anteil": 100, "art": "aus",
                "titel": "Pi-MCS ist abgeschaltet",
                "punkte": [{"text": "Eingeschaltet wird mit „mcs an“ im Terminal.",
                            "problem": "", "ok": True}]}

    # Jeder Punkt hat ZWEI Texte: einen für den erfüllten Fall und einen
    # für den nicht erfüllten. Angezeigt wird nur der zweite.
    #
    # Warum der Aufwand? Weil die kurze Fassung — ein Häkchen oder Kreuz vor
    # dem immer gleichen Satz — beim ersten Hinsehen falsch gelesen wurde:
    # "✗ Server läuft" sieht aus wie die Behauptung, er liefe. Ein Kreuz
    # kehrt einen Satz eben nicht um; das muss der Satz selbst tun.
    punkte = [
        {"text": "Server läuft",
         "problem": "Der Server läuft nicht.",
         "ok": status["service_state"] == "active"},
        {"text": "Backup ist aktuell",
         "problem": ("Der letzte Backup-Lauf ist fehlgeschlagen."
                     if backup.get("error") else
                     "Es gibt kein Backup." if not backup.get("exists") else
                     f"Das neueste Backup ist {backup.get('age_hours', 0):.0f} Stunden alt."),
         "ok": not backup.get("stale") and not backup.get("error")},
        # Kein TPS-Wert ist kein Fehlschlag: Der Server kann gerade aus
        # sein, oder RCON ist nicht eingerichtet. Nur ein GEMESSENER
        # schlechter Wert zählt.
        {"text": "Keine Ruckler (TPS)",
         "problem": f"Der Server schafft nur {tps:.1f} von 20 Ticks je Sekunde."
                    if tps is not None else "",
         "ok": tps is None or tps >= 19.0},
        {"text": "Platte hat Luft",
         "problem": f"Die Festplatte ist zu {status['disk_usage_percent']:.0f} % voll.",
         "ok": status["disk_usage_percent"] < 90.0},
        {"text": "Temperatur in Ordnung",
         "problem": f"Der Pi ist {temp:.0f} °C warm und drosselt vermutlich."
                    if temp is not None else "",
         "ok": temp is None or temp < 80.0},
        # Die Gegenleistung dafür, dass unattended-upgrades den Pi NICHT von
        # selbst neu startet (siehe install.sh, sicherheitsupdates_einrichten):
        # Irgendjemand muss es sagen. Sonst läuft der Pi monatelang mit einem
        # Kernel weiter, dessen Lücke längst geschlossen wäre — und der
        # Verzicht auf den automatischen Neustart wäre vom Schutz zur
        # Nachlässigkeit geworden.
        #
        # Es ist bewusst nur ein "warnung", kein "fehler": Nichts ist kaputt,
        # es ist etwas zu tun. Der Unterschied entscheidet darüber, ob der
        # Balken beim nächsten Mal noch gelesen wird.
        {"text": "Kein Neustart offen",
         "problem": ("Ein Systemupdate wartet auf einen Neustart des Pi"
                     + (f" ({', '.join(neustart['pakete'][:3])}"
                        + (", …" if len(neustart["pakete"]) > 3 else "") + ")"
                        if neustart.get("pakete") else "")
                     + " — bei Gelegenheit: mcs stop && sudo reboot"),
         "ok": not neustart.get("noetig")},
        # Seit dem 21.10.2026: Eine Woche lang zählte die Oberfläche 0
        # Spieler, weil Paper 26.3 das Logformat geändert hatte, und dieser
        # Balken stand auf „Alles in Ordnung“. Die Kachel darunter sagte
        # „niemand online“, und das klang nach einer Auskunft.
        {"text": "Spieler werden erkannt",
         "problem": (status.get("muster_befund") or {}).get("kurz", ""),
         "ok": not status.get("muster_befund")},
    ]

    erfuellt = sum(1 for p in punkte if p["ok"])
    anteil = int(round(100.0 * erfuellt / len(punkte)))

    if status["service_state"] != "active" or backup.get("stale") or backup.get("error"):
        art = "fehler"
    elif erfuellt < len(punkte):
        art = "warnung"
    else:
        art = "gut"

    offen = len(punkte) - erfuellt
    if art == "gut":
        titel = "Alles in Ordnung"
    elif offen == 1:
        titel = f"Ein Punkt von {len(punkte)} braucht Aufmerksamkeit"
    else:
        titel = f"{offen} von {len(punkte)} Punkten brauchen Aufmerksamkeit"
    return {"anteil": anteil, "art": art, "titel": titel, "punkte": punkte}


# Wie lange ein Tick dauern darf, bevor der Server ins Stocken gerät. Paper
# rechnet mit 20 Ticks je Sekunde, also 50 ms Budget je Tick.
TICKBUDGET_MS = 50.0


def leerlauf_urteil(status):
    """Arbeitet der Spielserver gerade, oder läuft er leer?

    Der Zweck ist eine Antwort, kein Schmuck: Wer auf der Startseite eine
    hohe CPU-Zahl sieht, will als Nächstes wissen, ob sie vom Spielserver
    kommt. Diese Auskunft stand bisher nur auf der Leistungsseite.

    Gemessen wird nichts Neues — Spielerzahl und Tickdauer liegen bereits
    vor. Der Sammler holt TPS und mspt ohnehin über RCON, und eine eigene
    Abfrage dafür verbietet Leitsatz 1: eine Abfrage je Klick ist richtig,
    eine je Sekunde nicht.

    Liefert (urteil, erläuterung, art).
    """
    mspt = status.get("mspt")
    spieler = status.get("players_count", 0)

    if mspt is None:
        # Kein Messwert heisst nicht "leer" — es heisst, dass wir es nicht
        # wissen. Genau diese Unterscheidung ist der Anlass dieser Etappe.
        return "nicht feststellbar", "RCON antwortet nicht", ""

    anteil = mspt / TICKBUDGET_MS
    erklaerung = (f"{mspt:.1f} von {TICKBUDGET_MS:.0f} ms je Tick, "
                  f"{spieler} Spieler")

    # Kein Spieler UND fast keine Tickdauer: Dann rechnet der Server nur an
    # sich selbst. Eine hohe CPU-Last kommt dann von etwas anderem.
    if spieler == 0 and anteil < 0.2:
        return "läuft leer", erklaerung, ""
    if anteil < 0.4:
        return "arbeitet wenig", erklaerung, ""
    if anteil < 0.8:
        return "arbeitet", erklaerung, ""
    return "am Anschlag", erklaerung, "warnung"


def _kachelwerte(status):
    """Bereitet die Werte so auf, wie die Kacheln sie brauchen.

    Gerechnet wird hier und nicht in der Vorlage: Eine Jinja-Vorlage mit
    Fallunterscheidungen ist schwerer zu lesen als eine Funktion, und man
    kann sie nicht mit dem Testclient prüfen.
    """
    backup = status["last_backup"]

    if backup.get("mcs_aus"):
        backup_text, backup_art = "abgeschaltet", ""
    elif not backup.get("exists"):
        backup_text, backup_art = "keins", "fehler"
    else:
        stunden = backup["age_hours"]
        backup_text = (f"vor {stunden:.0f} h" if stunden >= 1
                       else f"vor {stunden * 60:.0f} min")
        backup_art = "fehler" if backup.get("stale") or backup.get("error") else ""

    temp = status.get("cpu_temp_c")
    tps = status.get("tps")
    urteil, urteil_text, urteil_art = leerlauf_urteil(status)

    return {
        "dienst": {
            # "unbekannt" liefert system.service_state, wenn systemctl gar
            # nicht antwortet — auf dem Pi heisst das: etwas stimmt mit
            # systemd nicht. Das als rohes Wort anzuzeigen hilft niemandem.
            "wert": {"active": "läuft", "inactive": "aus",
                     "failed": "Fehler",
                     "unbekannt": "unklar"}.get(status["service_state"],
                                                status["service_state"]),
            "zusatz": status["service_uptime"] if status["service_state"] == "active" else "",
            "art": "" if status["service_state"] == "active" else "fehler",
        },
        "spieler": {
            "wert": status["players_count"],
            "von": status["max_players"],
            "namen": status["players_online"],
            # Über zehn Herzen liest niemand mehr ab — dann nur die Zahl.
            "herzen": status["max_players"] <= 10,
        },
        "tps": {
            "wert": f"{tps:.1f}" if tps is not None else "–",
            "einheit": "/ 20" if tps is not None else "",
            # Die Tickdauer stand hier schon; neu ist, dass sie gegen das
            # Budget gestellt und in ein Urteil uebersetzt wird.
            "zusatz": urteil_text,
            "urteil": urteil,
            "urteil_art": urteil_art,
            "art": "" if tps is None or tps >= 19.0 else "warnung",
        },
        "backup": {"wert": backup_text, "art": backup_art,
                   "zusatz": backup.get("file", "")},
        "platte": {
            "wert": f"{status['disk_usage_percent']:.0f}",
            "zusatz": f"{status['disk_used_gb']:.0f} von {status['disk_total_gb']:.0f} GB",
            "art": "fehler" if status["disk_usage_percent"] >= 90 else
                   ("warnung" if status["disk_usage_percent"] >= 80 else ""),
        },
        "temperatur": {
            "wert": f"{temp:.0f}" if temp is not None else "–",
            # Ohne Messwert auch keine Einheit: "– °C" sieht aus wie ein
            # kaputter Wert, "–" allein sagt ehrlich "wissen wir nicht".
            "einheit": "°C" if temp is not None else "",
            "art": "fehler" if temp and temp >= 80 else
                   ("warnung" if temp and temp >= 70 else ""),
        },
    }


# ----------------------------------------------------------------------------
# Die Seite und ihre Teile
# ----------------------------------------------------------------------------
@start.get("/")
@auth_required
def index():
    status = current_status()
    return render_template("start.html",
                           status=status,
                           bild=gesamtbild(status),
                           kacheln=_kachelwerte(status),
                           ereignisse=letzte_ereignisse(),
                           allow_host_power=ALLOW_HOST_POWER)


@start.get("/teil/kacheln")
@auth_required
def teil_kacheln():
    """Nur die Kacheln — das Stück, das sich alle fünf Sekunden erneuert."""
    status = current_status()
    return render_template("teile/kacheln.html",
                           status=status,
                           bild=gesamtbild(status),
                           kacheln=_kachelwerte(status))


@start.get("/teil/ereignisse")
@auth_required
def teil_ereignisse():
    """Die letzten Vorgänge. Erneuert sich seltener — sie ändern sich selten."""
    return render_template("teile/ereignisse.html", ereignisse=letzte_ereignisse())


@start.get("/teil/kopfzustand")
def teil_kopfzustand():
    """Der Zustandspunkt in der Kopfleiste.

    Bewusst OHNE auth_required: Der Punkt steht auf jeder Seite, auch auf
    einer, von der man gerade abgemeldet wurde. Eine 401-Antwort mit
    HX-Redirect ergäbe dann eine Umleitungsschleife. Verraten wird dabei
    nichts, was nicht ohnehin jeder sehen kann, der den Spielserver
    anpingt: ob er läuft.
    """
    zustand = service_state()
    klasse = {"active": "punkt--laeuft", "failed": "punkt--fehler"}.get(zustand, "punkt--aus")
    beschreibung = {"active": "Server läuft", "failed": "Server meldet einen Fehler"}.get(
        zustand, "Server ist aus")
    return (f'<span class="punkt {klasse}" title="{beschreibung}"></span>'
            f'<span class="nur-vorlesen">{beschreibung}</span>')


# ----------------------------------------------------------------------------
# Die Konsole
# ----------------------------------------------------------------------------
# Neu gegenüber der alten Oberfläche: Ein Befehl wird über RCON geschickt,
# und die ANTWORT steht danach da. Bisher ging alles über screen — ein
# Briefkasten ohne Rückweg; wer wissen wollte, was der Server gesagt hat,
# musste ins Log schauen.
#
# Chat-Nachrichten gehen weiter über screen: "say" hat keine Antwort, und
# so bleibt ein Weg offen, der auch ohne eingerichtetes RCON funktioniert.
@start.post("/konsole")
@auth_required
@nur_eigene_oberflaeche
def konsole():
    art = (request.form.get("art") or "").strip().lower()
    text = sanitize_console_input(request.form.get("text"))

    if art not in {"chat", "befehl"}:
        return _antwort("Unbekannte Art — erwartet wird „chat“ oder „befehl“.", "fehler")
    if not text:
        return _antwort("Es war nichts eingegeben.", "warnung")
    if service_state() != "active":
        return _antwort("Der Server läuft gerade nicht.", "warnung")

    if art == "chat":
        ok, meldung = send_to_minecraft_console(f"say [WEB] {text}")
        if not ok:
            return _antwort(meldung, "fehler")
        return _antwort(f"An alle gesendet: {text}", "gut")

    # Befehl: über RCON, damit die Antwort sichtbar wird.
    befehl = text[1:] if text.startswith("/") else text
    if not rcon.verfuegbar():
        # Ohne RCON bleibt der alte Weg — dann eben ohne Antwort. Das ist
        # ehrlicher, als den Knopf abzuschalten.
        ok, meldung = send_to_minecraft_console(f"/{befehl}")
        if not ok:
            return _antwort(meldung, "fehler")
        return _antwort("Gesendet. Ohne RCON gibt es dazu keine Antwort — "
                        "einzusehen im Server-Log.", "warnung")

    try:
        antwort = rcon.befehl(befehl)
    except rcon.RconAnmeldungFehlgeschlagen as fehler:
        return _antwort(str(fehler), "fehler")
    except rcon.RconFehler as fehler:
        return _antwort(str(fehler), "fehler")

    return _antwort(antwort or "(Der Server hat nichts geantwortet.)", "gut")


def _antwort(text, art):
    return render_template("teile/konsolenantwort.html", text=text, art=art)


# ----------------------------------------------------------------------------
# Aktionen (Starten, Stoppen, Backup)
# ----------------------------------------------------------------------------
# Es gibt dieselben Aktionen auch unter /api/action/<name> als JSON. Diese
# Route hier liefert stattdessen ein Stück HTML — HTMX schreibt die Antwort
# unverändert in die Seite, und rohes JSON zwischen zwei Knöpfen sähe aus
# wie ein Fehler.
#
# Welche Aktionen es überhaupt gibt, entscheidet weiterhin
# konsole.action_command: Nur was dort steht, ist möglich. Diese Route
# fügt keine einzige neue Möglichkeit hinzu, sie zeigt das Ergebnis nur
# anders an.
@start.post("/aktion/<name>")
@auth_required
@nur_eigene_oberflaeche
def aktion(name):
    beschreibung = action_command(name)
    if beschreibung is None:
        return _antwort("Diese Aktion gibt es nicht oder sie ist nicht erlaubt.", "fehler")

    if beschreibung["mode"] == "background":
        run_background(beschreibung["cmd"], name, cwd=beschreibung.get("cwd"))
        return _antwort("Gestartet. Das läuft im Hintergrund weiter — "
                        "was dabei herauskommt, steht gleich unter "
                        "„Zuletzt passiert“.", "gut")

    code, aus, fehler = run_command(beschreibung["cmd"], timeout=180,
                                    cwd=beschreibung.get("cwd"))
    if code == 0:
        return _antwort("Erledigt.", "gut")
    return _antwort(fehler or aus or f"Fehlgeschlagen (Rückgabewert {code}).", "fehler")


# Damit die Vorlagen nicht jedes Mal danach fragen müssen.
@start.app_context_processor
def _gemeinsame_werte():
    from sicherheit import SCHLUESSEL_ERZEUGT, csrf_token
    from version import stand
    return {
        "csrf_token": csrf_token(),
        "auth_enabled": AUTH_ENABLED,
        "schluessel_erzeugt": SCHLUESSEL_ERZEUGT and AUTH_ENABLED,
        "dienst_name": MCS_SERVICE,
        # Nicht die Version der Vorlage, sondern die der Installation —
        # die Begruendung steht im Kopf von version.py.
        "stand": stand(),
    }
