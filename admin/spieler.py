#!/usr/bin/env python3
"""
spieler.py — Wer war hier, wer darf was.

Die Angaben stehen an fuenf verschiedenen Stellen, und das ist kein
Versehen: Paper schreibt sie selbst, jede fuer ihren Zweck.

    usercache.json          Name <-> UUID, mit Ablaufdatum
    whitelist.json          wer ueberhaupt herein darf
    ops.json                wer Operator ist, mit Stufe 1 bis 4
    banned-players.json     wer gesperrt ist, von wem und warum
    <welt>/players/stats/<uuid>.json  wie lange jemand gespielt hat
                            (auf einer Welt im alten Format: <welt>/stats/)

Dazu das dauerhafte Spielerprotokoll (player_activity.log) fuer "wann
zuletzt gesehen" und "von welcher Adresse".

GELESEN wird aus diesen Dateien, GEAENDERT wird ueber RCON. Das ist keine
Willkuer, sondern folgt aus derselben Messung wie Korrektur K3: Paper haelt
diese Listen im Arbeitsspeicher und schreibt die Dateien selbst. Wer
whitelist.json bei laufendem Server von Hand aendert, verliert die Aenderung
beim naechsten Mal, wenn Paper die Datei schreibt -- lautlos.

Und je Aenderung eine eigene RCON-Verbindung (Korrektur K4): Auf einer
geteilten Verbindung reisst "whitelist add" sie ab, weil der Server dafuer
den Namen bei Mojang nachschlaegt. Genau das tut rcon.befehl() ohnehin.
"""

import json
import re
from datetime import datetime
from pathlib import Path

import konfig
import rcon
from einstellungen import MCS_SERVER_DIR, PLAYER_ACTIVITY_LOG, SERVER_PROPERTIES
from protokoll import online_players
from system import read_last_lines, service_state

# ----------------------------------------------------------------------------
# Die Dateien, die Paper schreibt
# ----------------------------------------------------------------------------
def _json_liste(name):
    """Liest eine der JSON-Listen. Fehlt sie, ist sie eben leer.

    Auf einem frisch installierten Server gibt es diese Dateien noch nicht
    -- Paper legt sie erst an, wenn zum ersten Mal etwas darin steht. Das
    ist kein Fehler und darf die Seite nicht scheitern lassen.
    """
    pfad = Path(MCS_SERVER_DIR) / name
    try:
        inhalt = json.loads(pfad.read_text(encoding="utf-8", errors="ignore"))
    except (OSError, ValueError):
        return []
    return inhalt if isinstance(inhalt, list) else []


def weltname():
    """Wie der Weltordner heisst.

    NICHT raten: Der Name steht in `level-name` und weicht auf einer
    gewachsenen Installation regelmaessig ab. Ordner "world*" daneben
    koennen Altbestand sein.
    """
    try:
        for zeile in Path(SERVER_PROPERTIES).read_text(
                encoding="utf-8", errors="ignore").splitlines():
            if zeile.startswith("level-name="):
                name = zeile.split("=", 1)[1].strip()
                if name:
                    return name
    except OSError:
        pass
    return "world"


def stats_ordner():
    """Wo die Statistikdateien liegen -- neuer Ort zuerst.

    Das haengt am Weltformat, nicht an PiCraft: Frueher lagen die
    Spielerdateien direkt in `<welt>/stats/`. Seit der Formatumstellung
    sammelt Minecraft sie unter `<welt>/players/` (stats, advancements und
    playerdata beisammen). Auf diesem Pi ist die Welt im April 2026
    umgestellt worden -- daneben liegt `MeineWelt_oid` als Sicherung im alten
    Format, und die hat ihr `stats/` noch obenauf.

    Beide Orte werden geprueft, damit PiCraft auf einer umgestellten Welt
    genauso arbeitet wie auf einer alten. Zurueck kommt eine Liste, nicht
    ein einzelner Ordner: Waehrend einer Umstellung koennen beide da sein,
    und dann entscheidet die Datei, nicht der Ordner.
    """
    welt = Path(MCS_SERVER_DIR) / weltname()
    return [ordner for ordner in (welt / "players" / "stats", welt / "stats")
            if ordner.is_dir()]


def statistikdatei(uuid):
    """Die Statistikdatei zu einer UUID, oder None.

    Sie ist der Beweis, dass jemand wirklich einmal gespielt hat: Paper legt
    sie an, sobald ein Spieler die Welt betritt, und loescht sie nie wieder.
    Fehlt sie, war der Betreffende nachweislich noch nie da — und nur dann
    darf die Oberflaeche das auch behaupten.
    """
    if not uuid:
        return None
    for ordner in stats_ordner():
        pfad = ordner / f"{uuid}.json"
        if pfad.is_file():
            return pfad
    return None


def spielzeit_sekunden(uuid):
    """Wie lange jemand insgesamt gespielt hat.

    Die Statistik heisst `minecraft:play_time` und steht in Ticks. Am
    28.08.2026 nachgemessen, indem der Server das Scoreboard-Kriterium
    `minecraft.custom:minecraft.play_time` angenommen hat -- der aeltere
    Name `play_one_minute` wird mit "Unknown criterion" abgelehnt.

    Zwanzig Ticks sind eine Sekunde. Die Datei gibt es erst, wenn jemand
    wirklich gespielt hat; auf einem frischen Server fehlt der ganze
    Ordner. Dann steht in der Oberflaeche ein Strich und keine Null --
    "wissen wir nicht" ist etwas anderes als "null Minuten".
    """
    pfad = statistikdatei(uuid)
    if pfad is None:
        return None
    try:
        daten = json.loads(pfad.read_text(encoding="utf-8", errors="ignore"))
    except (OSError, ValueError):
        return None
    ticks = (daten.get("stats", {})
                  .get("minecraft:custom", {})
                  .get("minecraft:play_time"))
    return int(ticks / 20) if isinstance(ticks, (int, float)) else None


def zeit_lesbar(sekunden):
    """Aus 9126 Sekunden wird "2 h 32 min"."""
    if sekunden is None:
        return None
    stunden, rest = divmod(int(sekunden), 3600)
    minuten = rest // 60
    if stunden:
        return f"{stunden} h {minuten} min"
    return f"{minuten} min"


# ----------------------------------------------------------------------------
# Das Spielerprotokoll
# ----------------------------------------------------------------------------
# Zeilen sehen so aus:
#   2026-08-28 15:41:03 | Kaya ist dem Spiel beigetreten
#   2026-08-28 15:41:02 | Kaya meldet sich an von 192.168.1.44:51234
_PROTOKOLL = re.compile(r"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) \| (.+)$")
_ANMELDUNG = re.compile(r"^([A-Za-z0-9_]{1,16}) meldet sich an von ([^\s]+)$")
_NAME_VORN = re.compile(r"^([A-Za-z0-9_]{1,16}) (ist dem Spiel|hat das Spiel|hat die Verbindung)")


def protokoll_auswerten(hoechstens=20000):
    """Zieht je Spieler zusammen, was im Protokoll ueber ihn steht.

    Liefert (stand, beginn):
      stand  {name: {"zuerst": datetime, "zuletzt": datetime, "adresse": str}}
      beginn der frueheste Zeitpunkt, ueber den hier ueberhaupt etwas
             bekannt ist (None, wenn das Protokoll leer ist)

    `beginn` ist der Punkt, ab dem eine Aussage moeglich ist — und genau
    deshalb wird er mitgeliefert. Steht ueber jemanden nichts im Protokoll,
    heisst das nicht "war nie da", sondern "seit `beginn` nicht gesehen".
    Bis zum 01.09.2026 hat die Oberflaeche daraus das Gegenteil gemacht und
    "war noch nie da" ueber jemanden mit ueber 500 Stunden Spielzeit
    geschrieben.

    Es ist ausdruecklich der Beginn des PROTOKOLLS, nicht der Tag der
    Installation: Nur das Protokoll weiss, ab wann es etwas weiss. Und es
    ist der Beginn des gelesenen FENSTERS, nicht der der Datei — ueber
    Zeilen, die gar nicht gelesen wurden, laesst sich nichts sagen.

    `hoechstens` begrenzt, wie weit zurueckgelesen wird. Das Protokoll
    waechst ueber Jahre; die ganze Datei bei jedem Seitenaufruf zu lesen
    waere dieselbe unnoetige Leserei, die in Etappe A schon einmal
    aufgefallen ist. Zwanzigtausend Zeilen sind bei fuenf Spielern viele
    Monate.
    """
    stand = {}
    beginn = None
    for zeile in read_last_lines(PLAYER_ACTIVITY_LOG, max_lines=hoechstens):
        treffer = _PROTOKOLL.match(zeile)
        if not treffer:
            continue
        try:
            zeit = datetime.strptime(treffer.group(1), "%Y-%m-%d %H:%M:%S")
        except ValueError:
            continue
        text = treffer.group(2)

        # Jede datierte Zeile zaehlt fuer den Beginn, auch eine, deren Text
        # keinem Spielermuster entspricht: Das Protokoll reicht ab hier
        # zurueck, unabhaengig davon, was drinsteht.
        beginn = zeit if beginn is None else min(beginn, zeit)

        anmeldung = _ANMELDUNG.match(text)
        if anmeldung:
            name, adresse = anmeldung.group(1), anmeldung.group(2)
            # Der Port hinter dem Doppelpunkt wechselt bei jeder Verbindung
            # und sagt nichts aus.
            adresse = adresse.rsplit(":", 1)[0] if ":" in adresse else adresse
        else:
            vorn = _NAME_VORN.match(text)
            if not vorn:
                continue
            name, adresse = vorn.group(1), None

        eintrag = stand.setdefault(name, {"zuerst": zeit, "zuletzt": zeit,
                                          "adresse": None})
        eintrag["zuerst"] = min(eintrag["zuerst"], zeit)
        eintrag["zuletzt"] = max(eintrag["zuletzt"], zeit)
        if adresse:
            eintrag["adresse"] = adresse
    return stand, beginn


# ----------------------------------------------------------------------------
# Das Gesamtbild
# ----------------------------------------------------------------------------
def alle():
    """Alle Spieler, die je hier waren — mit allem, was ueber sie bekannt ist.

    Online zuerst, danach nach letztem Besuch sortiert. Wer gerade da ist,
    ist die Person, wegen der man die Seite geoeffnet hat.
    """
    cache = {e.get("name"): e.get("uuid")
             for e in _json_liste("usercache.json") if e.get("name")}
    whitelist = {e.get("name") for e in _json_liste("whitelist.json")}
    ops = {e.get("name"): e.get("level", 4) for e in _json_liste("ops.json")}
    sperren = {e.get("name"): {"grund": e.get("reason") or "",
                               "von": e.get("source") or ""}
               for e in _json_liste("banned-players.json")}
    protokoll, protokoll_beginn = protokoll_auswerten()
    jetzt_online = set(online_players())

    # Alle Namen zusammentragen, aus welcher Quelle auch immer. Wer auf der
    # Whitelist steht, aber noch nie da war, gehoert genauso auf die Liste
    # wie jemand, der nur im Protokoll auftaucht.
    namen = set(cache) | whitelist | set(ops) | set(sperren) | set(protokoll) | jetzt_online

    liste = []
    for name in namen:
        uuid = cache.get(name)
        eintrag = protokoll.get(name, {})
        sekunden = spielzeit_sekunden(uuid) if uuid else None

        # DREI Zustaende, nicht zwei. Der mittlere ist der, der bis zum
        # 01.09.2026 fehlte — und der Grund, warum die Anzeige falsch war:
        # Ohne ihn wurde "kein Protokolleintrag" zu "war noch nie da",
        # obwohl das Protokoll erst seit mcs-playerlog existiert und alles
        # davor schlicht nicht aufgezeichnet ist.
        #
        # Die Statistikdatei entscheidet: Paper legt sie an, sobald jemand
        # die Welt betritt, und loescht sie nie. Fehlt sie, ist "war noch
        # nie da" eine belegte Aussage; ist sie da, ist sie nachweislich
        # falsch.
        if eintrag.get("zuletzt"):
            gesehen = "bekannt"
        elif statistikdatei(uuid) is not None:
            gesehen = "nicht_aufgezeichnet"
        else:
            gesehen = "nie"

        liste.append({
            "name": name,
            "uuid": uuid,
            "online": name in jetzt_online,
            "whitelist": name in whitelist,
            "op": name in ops,
            "op_stufe": ops.get(name),
            "gesperrt": name in sperren,
            "sperrgrund": sperren.get(name, {}).get("grund", ""),
            "zuerst": eintrag.get("zuerst"),
            "zuletzt": eintrag.get("zuletzt"),
            "gesehen": gesehen,
            # Ab wann das Protokoll ueberhaupt etwas weiss. Nur damit laesst
            # sich der mittlere Zustand ueberhaupt formulieren.
            "protokoll_beginn": protokoll_beginn,
            "adresse": eintrag.get("adresse"),
            "spielzeit": zeit_lesbar(sekunden),
        })

    # Online zuerst, dann die zuletzt Gesehenen, dann die, ueber die es
    # keine Aufzeichnung gibt — und ganz unten, wer nachweislich nie da war.
    _RANG = {"bekannt": 1, "nicht_aufgezeichnet": 2, "nie": 3}

    def schluessel(e):
        return (0 if e["online"] else _RANG[e["gesehen"]],
                -(e["zuletzt"].timestamp() if e["zuletzt"] else 0),
                e["name"].lower())

    liste.sort(key=schluessel)
    return liste


def zaehlung(liste):
    return {
        "gesamt": len(liste),
        "online": sum(1 for e in liste if e["online"]),
        "whitelist": sum(1 for e in liste if e["whitelist"]),
        "ops": sum(1 for e in liste if e["op"]),
        "gesperrt": sum(1 for e in liste if e["gesperrt"]),
    }


def whitelist_aktiv():
    """Ob die Whitelist ueberhaupt eingeschaltet ist.

    Ohne diese Angabe waere die Liste irrefuehrend: Steht "white-list=false"
    in der server.properties, darf jeder herein, egal wer auf der Liste
    steht.
    """
    try:
        for zeile in Path(SERVER_PROPERTIES).read_text(
                encoding="utf-8", errors="ignore").splitlines():
            if zeile.startswith("white-list="):
                return zeile.split("=", 1)[1].strip().lower() == "true"
    except OSError:
        pass
    return False


# ----------------------------------------------------------------------------
# Aenderungen
# ----------------------------------------------------------------------------
# Nur diese Befehle, und nur mit einem geprueften Namen. Eine freie
# Eingabe waere eine Einladung, ueber die Spielerseite beliebige
# Serverbefehle abzusetzen -- dafuer gibt es das Konsolenfeld auf der
# Startseite, wo man wenigstens sieht, was man tut.
AKTIONEN = {
    "op":              ("op {name}",              "{name} ist jetzt Operator."),
    "deop":            ("deop {name}",            "{name} ist kein Operator mehr."),
    "whitelist_dazu":  ("whitelist add {name}",   "{name} steht jetzt auf der Whitelist."),
    "whitelist_weg":   ("whitelist remove {name}", "{name} steht nicht mehr auf der Whitelist."),
    "kick":            ("kick {name} {grund}",    "{name} wurde hinausgeworfen."),
    "ban":             ("ban {name} {grund}",     "{name} ist gesperrt."),
    "entsperren":      ("pardon {name}",          "{name} ist wieder zugelassen."),
}

# Minecraft-Namen: 1 bis 16 Zeichen, Buchstaben, Ziffern, Unterstrich.
_NAME_ERLAUBT = re.compile(r"^[A-Za-z0-9_]{1,16}$")


def name_pruefen(name):
    return bool(name) and bool(_NAME_ERLAUBT.match(name))


def grund_saeubern(text):
    """Ein Grund darf Text sein, aber keine zweite Befehlszeile."""
    sauber = (text or "").replace("\r", " ").replace("\n", " ").strip()
    return sauber[:100] or "Kein Grund angegeben"


def _erklaerung(antwort, was):
    """Was die englische Serverantwort fuer den Benutzer bedeutet.

    Die rohe Antwort wird nicht ersetzt — sie ist die ehrlichste Auskunft,
    und wer sie nachschlagen will, soll sie woertlich sehen. Ergaenzt wird
    nur, was sie NICHT sagt.

    Anlass war ein gemeldeter Fehlschlag mit "That player does not exist".
    Das war kein Programmfehler: Der Server schlaegt den Namen bei Mojang
    nach (der Server laeuft mit online-mode=true) und reicht die Antwort
    korrekt durch. Was fehlte, war die Erklaerung — dass der Name dort
    nicht existiert, dass ein Tippfehler die haeufigste Ursache ist, und
    dass Bedrock-Namen hier grundsaetzlich nicht funktionieren.
    """
    text = (antwort or "").lower()

    if "does not exist" in text or "no player" in text:
        if was in ("whitelist_dazu", "op"):
            return ("\n\nDas heißt: Mojang kennt diesen Namen nicht. Der Server "
                    "läuft mit online-mode=true und schlägt jeden Namen dort "
                    "nach, bevor er ihn einträgt — anwesend sein muss dafür "
                    "niemand. Häufigste Ursachen: ein Tippfehler (Groß- und "
                    "Kleinschreibung ist egal, alles andere nicht), ein "
                    "inzwischen geänderter Name, oder ein Bedrock-Konto — "
                    "Bedrock-Namen gibt es bei Mojang nicht und sie "
                    "funktionieren hier grundsätzlich nicht.")
        return ("\n\nDas heißt: Der Server kennt niemanden mit diesem Namen. "
                "Für Hinauswerfen und Sperren muss der Spieler online sein.")

    if "already" in text:
        return "\n\nDas heißt: Es war schon so. Es wurde nichts geändert."

    return ""


def stufe_setzen(name, stufe):
    """Setzt die Operator-Stufe in ops.json. Liefert (art, meldung).

    Nur bei GESTOPPTEM Server — und das ist keine Vorsicht, sondern die
    Messung vom 01.09.2026 (M9 in tests/messung-im-container.sh). ops.json
    verhaelt sich beim Start genau UMGEKEHRT zur server.properties:

                      | server.properties | ops.json
        beim Stoppen  | ueberlebt         | ueberlebt
        beim START    | wird verworfen    | wird GELESEN und ueberlebt
        im Betrieb    | wird verworfen    | wird verworfen

    Daraus folgt beides: Bei gestopptem Server ist die Datei der richtige
    und einzige Weg. Bei laufendem Server ist sie der falsche — Paper haelt
    die Liste im Arbeitsspeicher und schreibt sie beim naechsten op oder
    deop vollstaendig neu; die Aenderung waere lautlos wieder weg.

    Einen RCON-Weg gibt es nicht: "op <name> <stufe>" kennt der Server
    nicht ("Incorrect argument for command"), auch nicht als "minecraft:op".
    "op <name>" vergibt immer op-permission-level.
    """
    if not name_pruefen(name):
        return "fehler", "Das ist kein gültiger Minecraft-Name."
    try:
        # Ueber den Umweg str(), weil int(2.5) stillschweigend 2 ergibt.
        # Aus dem Formular kommt zwar immer Text, aber eine Stufe, die sich
        # beim Setzen unbemerkt aendert, waere genau die Sorte Fehler, die
        # hier niemand mehr sucht.
        stufe = int(str(stufe).strip())
    except (TypeError, ValueError):
        return "fehler", "Die Stufe muss eine ganze Zahl von 1 bis 4 sein."
    if not 1 <= stufe <= 4:
        return "fehler", "Die Stufe muss zwischen 1 und 4 liegen."

    # frisch=True aus demselben Grund wie konfig.server_laeuft(): Von dieser
    # Antwort haengt ab, OB geschrieben wird. Ein veralteter Wert hiesse
    # hier, bei laufendem Server zu schreiben.
    if service_state(frisch=True) == "active":
        return "fehler", (
            "Der Server läuft. Die Stufe lässt sich nur bei gestopptem Server "
            "ändern: Minecraft hält die Operatorliste im Arbeitsspeicher und "
            "schreibt ops.json beim nächsten „op“ oder „deop“ vollständig neu "
            "— eine Änderung an der Datei wäre dann lautlos wieder weg. Einen "
            "Serverbefehl für die Stufe gibt es nicht.")

    eintraege = _json_liste("ops.json")
    for eintrag in eintraege:
        if eintrag.get("name") == name:
            if eintrag.get("level") == stufe:
                return "warnung", f"{name} hat bereits Stufe {stufe}. Es wurde nichts geändert."
            eintrag["level"] = stufe
            break
    else:
        return "fehler", (
            f"{name} steht nicht in der Operatorliste. Erst zum Operator "
            "machen — das geht nur bei laufendem Server, weil es über RCON "
            "läuft. Danach den Server stoppen und die Stufe setzen.")

    pfad = str(Path(MCS_SERVER_DIR) / "ops.json")
    konfig.sicherung_anlegen(pfad)
    try:
        # Dieselbe Vorkehrung wie fuer die server.properties: daneben
        # schreiben und umbenennen. Eine halb geschriebene ops.json waere
        # kein Schoenheitsfehler -- Paper liest sie beim Start, und wer
        # dann nicht mehr darin steht, ist kein Operator mehr.
        konfig.datei_ersetzen(pfad, json.dumps(eintraege, indent=2) + "\n")
    except OSError as fehler:
        return "fehler", f"ops.json ließ sich nicht schreiben: {fehler}"

    return "gut", (f"{name} hat jetzt Stufe {stufe}. Der Server liest ops.json "
                   "beim Start — die Stufe gilt also ab dem nächsten Start.")


def aktion(name, was, grund="", stufe=None):
    """Fuehrt eine der erlaubten Aktionen aus. Liefert (art, meldung).

    `art` ist "gut", "warnung" oder "fehler" — die Oberflaeche faerbt
    danach ein.
    """
    # Die Stufe ist die eine Aenderung, die NICHT ueber RCON geht und nicht
    # bei laufendem Server -- sie faehrt hier trotzdem mit, weil es fuer die
    # Oberflaeche dieselbe Zeile, dasselbe Formular und dieselbe Meldung ist.
    if was == "stufe":
        return stufe_setzen(name, stufe)

    if not name_pruefen(name):
        return "fehler", "Das ist kein gültiger Minecraft-Name."
    if was not in AKTIONEN:
        return "fehler", "Diese Aktion gibt es nicht."

    vorlage, erfolg = AKTIONEN[was]
    befehl = vorlage.format(name=name, grund=grund_saeubern(grund))

    if not rcon.verfuegbar():
        return "fehler", ("RCON ist nicht eingerichtet. Whitelist, Rechte und "
                          "Sperren hält der Server im Arbeitsspeicher — ohne "
                          "RCON lassen sie sich nicht ändern.")

    try:
        # "whitelist add" und "op" schlagen den Namen bei Mojang nach. Das
        # kann dauern, und ohne Internet schlaegt es fehl -- deshalb mehr
        # Zeit als sonst und eine eigene Meldung dafuer.
        antwort = rcon.befehl(befehl, zeitlimit=15.0)
    except rcon.RconAnmeldungFehlgeschlagen as fehler:
        return "fehler", str(fehler)
    except rcon.RconFehler as fehler:
        if was in ("whitelist_dazu", "op"):
            return "fehler", (
                f"Der Server hat nicht geantwortet: {fehler} — für diesen "
                "Befehl schlägt er den Namen bei Mojang nach. Ohne "
                "Internetverbindung geht das nicht.")
        return "fehler", str(fehler)

    # Der Server antwortet auf Deutsch nicht; seine Meldung ist trotzdem
    # die ehrlichste Auskunft. Wenn sie nach einem Fehlschlag aussieht,
    # wird sie durchgereicht statt durch ein erfundenes "erledigt" ersetzt.
    verdaechtig = ("No player", "does not exist", "Unknown", "already",
                   "is not", "Nothing changed", "not whitelisted")
    if any(wort.lower() in (antwort or "").lower() for wort in verdaechtig):
        return "warnung", (antwort or "Der Server hat nichts geantwortet.") + _erklaerung(antwort, was)

    return "gut", erfolg.format(name=name) + (f" ({antwort})" if antwort else "")

