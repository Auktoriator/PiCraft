#!/usr/bin/env python3
"""
plugins.py — Welche Plugins da sind, und wie neue dazukommen.

Drei Quellen, die auseinanderlaufen koennen, und genau das ist der Punkt:

    plugins.txt        was dazugehoeren SOLL (mit Pruefsumme)
    plugins/*.jar      was tatsaechlich da IST
    Modrinth           was es geben WUERDE

Die Oberflaeche zeigt alle drei nebeneinander. Ein Plugin, das auf dem Pi
liegt, aber nicht in der Liste steht, wird **gemeldet und nie geloescht** --
in Plugin-Ordnern stecken Einstellungen und Datenbanken, die niemand
versehentlich verlieren soll (Lastenheft 5.8).

MODRINTH IST DER EINZIGE WEG NACH AUSSEN
----------------------------------------
Das Lastenheft (5.7.2) sagt, ein Verwaltungswerkzeug solle keine Anfragen
nach aussen stellen. Die Plugin-Suche braucht das aber. Aufloesung
(Entscheidung E7 im Pflichtenheft C): **Von sich aus fragt die Oberflaeche
nie an.** Modrinth wird ausschliesslich auf einen ausdruecklichen Klick hin
angesprochen, und auf der Seite steht, dass dieser Klick eine Verbindung
nach aussen aufbaut. Alle uebrigen sechs Seiten funktionieren vollstaendig
ohne Internet.

DER WEG EINER INSTALLATION
--------------------------
Entscheidung 13 im Lastenheft: Die Oberflaeche installiert nicht selbst,
sondern schreibt nach `plugins.txt` und ruft `plugin-update.sh`. Genau so
laeuft es hier:

    1. Datei herunterladen
    2. SHA512 gegen die Angabe der Modrinth-API pruefen -- das schuetzt vor
       einem manipulierten oder abgeschnittenen Download
    3. SHA256 aus der so bestaetigten Datei bilden (das Format der
       plugins.txt)
    4. Die Datei an ihren Platz legen und die Zeile in die plugins.txt
       schreiben
    5. `plugin-update.sh --laden` aufrufen -- es findet die Datei bereits
       korrekt vor und bestaetigt das

Schritt 5 ist keine Formsache: Damit prueft dasselbe Werkzeug, das auch bei
einer frischen Installation prueft, und die Oberflaeche baut sich keine
zweite Wahrheit daneben.
"""

import hashlib
import json
import os
import re
import shutil
import tempfile
import urllib.error
import urllib.parse
import urllib.request
import zipfile
from pathlib import Path

from einstellungen import MCS_SERVER_DIR
from system import aktion_vermerken, run_command

PLUGIN_DIR = f"{MCS_SERVER_DIR}/plugins"
PLUGIN_LISTE = f"{MCS_SERVER_DIR}/plugins.txt"

# Modrinth verlangt eine aussagekraeftige Absenderkennung, sonst lehnt die
# API Anfragen ab -- dieselbe Regel wie bei der PaperMC-API.
KENNUNG = "Pi-MCS/2.1 (privater Raspberry-Pi-Server; github.com/Pi-MCS)"
MODRINTH = "https://api.modrinth.com/v2"

# Wie lange auf Modrinth gewartet wird. Kurz genug, dass eine Seite nicht
# haengt, lang genug fuer eine langsame Leitung.
ZEITLIMIT = 15


# ----------------------------------------------------------------------------
# Was da ist
# ----------------------------------------------------------------------------
def _aus_jar(pfad):
    """Name und Version aus der plugin.yml im Jar.

    Mit zipfile aus der Standardbibliothek statt mit `unzip`: Das Werkzeug
    ist auf einem schlanken Raspberry Pi OS nicht zwangslaeufig
    installiert, und ein Plugin ohne Namen anzuzeigen waere schade.
    """
    name = version = ""
    try:
        with zipfile.ZipFile(pfad) as archiv:
            for kandidat in ("plugin.yml", "paper-plugin.yml"):
                if kandidat not in archiv.namelist():
                    continue
                text = archiv.read(kandidat).decode("utf-8", errors="ignore")
                for zeile in text.splitlines():
                    treffer = re.match(r"^name:\s*['\"]?([^'\"]+?)['\"]?\s*$", zeile)
                    if treffer and not name:
                        name = treffer.group(1)
                    treffer = re.match(r"^version:\s*['\"]?([^'\"]+?)['\"]?\s*$", zeile)
                    if treffer and not version:
                        version = treffer.group(1)
                if name:
                    break
    except (OSError, zipfile.BadZipFile):
        pass
    return name or Path(pfad).stem.replace(".jar", ""), version or "unbekannt"


def installierte():
    """Was wirklich im plugins-Ordner liegt — aktiv und abgeschaltet."""
    ordner = Path(PLUGIN_DIR)
    if not ordner.is_dir():
        return []

    gefunden = []
    for datei in sorted(ordner.iterdir()):
        if datei.name.endswith(".jar"):
            aktiv = True
        elif datei.name.endswith(".jar.disabled"):
            aktiv = False
        else:
            continue
        name, version = _aus_jar(datei)
        gefunden.append({
            "datei": datei.name,
            "name": name,
            "version": version,
            "aktiv": aktiv,
            "groesse_mb": round(datei.stat().st_size / (1024 * 1024), 1),
        })
    return gefunden


def soll_liste():
    """Was laut plugins.txt dazugehört."""
    eintraege = []
    try:
        text = Path(PLUGIN_LISTE).read_text(encoding="utf-8", errors="ignore")
    except OSError:
        return eintraege
    for zeile in text.splitlines():
        zeile = zeile.strip()
        if not zeile or zeile.startswith("#") or "|" not in zeile:
            continue
        teile = (zeile.split("|") + ["", "", ""])[:4]
        eintraege.append({"name": teile[0].strip(), "version": teile[1].strip(),
                          "url": teile[2].strip(), "sha256": teile[3].strip()})
    return eintraege


def uebersicht():
    """Soll und Ist nebeneinander.

    Drei Zustände, und jeder bedeutet etwas anderes:

        installiert   steht in der Liste und liegt da
        fehlt         steht in der Liste, liegt aber nicht da
        zusaetzlich   liegt da, steht nicht in der Liste

    Der dritte Fall ist keine Störung. Er entsteht, wenn jemand ein Plugin
    von Hand abgelegt hat, oder wenn es nirgends öffentlich zu beziehen ist
    (auf dem gepflegten Pi trifft das auf HsRails zu). Deshalb wird er
    gemeldet und nie behoben.
    """
    ist = {e["name"]: e for e in installierte()}
    soll = {e["name"]: e for e in soll_liste()}

    zeilen = []
    for name in sorted(set(ist) | set(soll), key=str.lower):
        vorhanden = ist.get(name)
        gewuenscht = soll.get(name)
        if vorhanden and gewuenscht:
            zustand = "installiert"
        elif gewuenscht:
            zustand = "fehlt"
        else:
            zustand = "zusaetzlich"
        zeilen.append({
            "name": name,
            "zustand": zustand,
            "aktiv": vorhanden["aktiv"] if vorhanden else False,
            "datei": vorhanden["datei"] if vorhanden else "",
            "version": (vorhanden or gewuenscht).get("version", ""),
            "soll_version": gewuenscht["version"] if gewuenscht else "",
            "groesse_mb": vorhanden["groesse_mb"] if vorhanden else 0,
            "url": gewuenscht["url"] if gewuenscht else "",
        })
    return zeilen


# ----------------------------------------------------------------------------
# Ein- und ausschalten
# ----------------------------------------------------------------------------
def umschalten(datei):
    """Schaltet ein Plugin ab oder wieder an — durch Umbenennen.

    `.jar` ↔ `.jar.disabled`. Simpel und ehrlich: Paper lädt beim Start,
    was auf `.jar` endet, und sonst nichts. Es braucht dafür einen
    Neustart, und das sagt die Oberfläche auch.

    Bewusst kein Löschen: Im Ordner daneben stecken Einstellungen und
    Datenbanken des Plugins, und die will niemand versehentlich verlieren.
    """
    ordner = Path(PLUGIN_DIR)
    # Den Namen in der Liste nachschlagen statt einen Pfad zusammenzubauen —
    # er kommt aus dem Browser.
    bekannt = {e["datei"] for e in installierte()}
    if datei not in bekannt:
        return "fehler", "Diese Plugin-Datei gibt es nicht."

    quelle = ordner / datei
    if datei.endswith(".jar.disabled"):
        ziel = ordner / datei[:-len(".disabled")]
        was = "eingeschaltet"
    else:
        ziel = ordner / (datei + ".disabled")
        was = "abgeschaltet"

    if ziel.exists():
        return "fehler", f"{ziel.name} gibt es schon — bitte von Hand aufräumen."
    try:
        quelle.rename(ziel)
    except OSError as fehler:
        return "fehler", f"Umbenennen fehlgeschlagen: {fehler}"
    aktion_vermerken(f"plugin_{was}", f"{datei} -> {ziel.name}")

    return "gut", (f"{datei} {was}. Das wirkt erst nach einem Neustart des "
                   "Servers — Paper lädt Plugins nur beim Start.")


# ----------------------------------------------------------------------------
# Modrinth
# ----------------------------------------------------------------------------
def spielversion():
    """Für welche Minecraft-Version gesucht wird.

    Aus dem Merkzettel der tatsächlich installierten Paper-Version, nicht
    aus der Vorgabe im Repository: Gesucht werden soll, was zu dem läuft,
    was da ist.
    """
    try:
        for zeile in (Path(MCS_SERVER_DIR) / "paper.installiert").read_text(
                encoding="utf-8", errors="ignore").splitlines():
            if zeile.startswith("version="):
                wert = zeile.split("=", 1)[1].strip()
                if wert:
                    return wert
    except OSError:
        pass
    return os.getenv("MCS_MINECRAFT_VERSION", "")


def _abfragen(pfad, parameter):
    """Eine Anfrage an Modrinth. Liefert (daten, fehlertext)."""
    adresse = f"{MODRINTH}{pfad}?{urllib.parse.urlencode(parameter)}"
    anfrage = urllib.request.Request(adresse, headers={"User-Agent": KENNUNG})
    try:
        with urllib.request.urlopen(anfrage, timeout=ZEITLIMIT) as antwort:
            return json.loads(antwort.read().decode("utf-8")), ""
    except urllib.error.HTTPError as fehler:
        return None, f"Modrinth antwortet mit {fehler.code} ({fehler.reason})."
    except urllib.error.URLError as fehler:
        return None, (f"Modrinth ist nicht erreichbar: {fehler.reason}. "
                      "Hat der Pi eine Internetverbindung?")
    except (ValueError, OSError) as fehler:
        return None, f"Die Antwort von Modrinth war unbrauchbar: {fehler}"


def suchen(text):
    """Sucht Paper-Plugins für die laufende Spielversion."""
    text = (text or "").strip()
    if len(text) < 2:
        return [], "Bitte mindestens zwei Zeichen eingeben."

    version = spielversion()

    # NUR die Loader-Facette, KEIN project_type.
    #
    # Am 28.08.2026 nachgemessen, weil die Suche nichts fand, obwohl die
    # Versionsabfrage fuer dasselbe Plugin etwas lieferte:
    #
    #   categories:paper                  8 Treffer
    #   project_type:mod                 15 Treffer
    #   categories:paper + project_type:mod   0 Treffer   <-- so war es
    #   categories:paper + versions:26.2      3 Treffer   <-- so ist es richtig
    #
    # Die beiden schliessen sich im Suchindex gegenseitig aus: Modrinth
    # fuehrt Plugin-Projekte dort unter "project_type:plugin", obwohl die
    # Projektauskunft desselben Plugins "project_type: mod" meldet (bei
    # Chunky nachgesehen, das fuer bukkit UND fabric erscheint). Wer sich
    # auf die Projektauskunft verlaesst, baut eine Suche, die nie etwas
    # findet -- und zwar ohne Fehlermeldung.
    facetten = [["categories:paper"]]
    if version:
        facetten.append([f"versions:{version}"])

    daten, fehler = _abfragen("/search", {
        "query": text, "limit": 12, "facets": json.dumps(facetten)})
    if daten is None:
        return [], fehler

    treffer = []
    for eintrag in daten.get("hits", []):
        treffer.append({
            "id": eintrag.get("project_id", ""),
            "slug": eintrag.get("slug", ""),
            "titel": eintrag.get("title", ""),
            "beschreibung": eintrag.get("description", ""),
            "downloads": eintrag.get("downloads", 0),
            "seite": f"https://modrinth.com/plugin/{eintrag.get('slug', '')}",
        })
    if not treffer and version:
        return [], (f"Nichts gefunden, das zu Minecraft {version} passt. "
                    "Vielleicht gibt es das Plugin noch nicht für diese "
                    "Version — dann hilft nur warten.")
    return treffer, ""


def versionen(projekt):
    """Die passenden Fassungen eines Projekts, neueste zuerst."""
    if not re.match(r"^[A-Za-z0-9_-]{1,64}$", projekt or ""):
        return [], "Das ist keine gültige Projektkennung."

    parameter = {"loaders": json.dumps(["paper", "spigot", "bukkit"])}
    version = spielversion()
    if version:
        parameter["game_versions"] = json.dumps([version])

    daten, fehler = _abfragen(f"/project/{projekt}/version", parameter)
    if daten is None:
        return [], fehler

    gefunden = []
    for eintrag in daten:
        datei = next((d for d in eintrag.get("files", []) if d.get("primary")),
                     None) or (eintrag.get("files") or [None])[0]
        if not datei:
            continue
        gefunden.append({
            "id": eintrag.get("id", ""),
            "nummer": eintrag.get("version_number", ""),
            "datum": (eintrag.get("date_published") or "")[:10],
            "spielversionen": ", ".join(eintrag.get("game_versions", [])[:6]),
            "dateiname": datei.get("filename", ""),
            "url": datei.get("url", ""),
            "sha512": (datei.get("hashes") or {}).get("sha512", ""),
            "groesse_mb": round(datei.get("size", 0) / (1024 * 1024), 1),
        })
    if not gefunden:
        return [], (f"Für Minecraft {version or '(unbekannt)'} gibt es von "
                    "diesem Plugin keine Fassung.")
    return gefunden, ""


# ----------------------------------------------------------------------------
# Installieren
# ----------------------------------------------------------------------------
def _zeile_setzen(name, version, url, sha256):
    """Schreibt oder ersetzt die Zeile eines Plugins in plugins.txt.

    Zeilenweise und nicht durch Neuschreiben der ganzen Datei: In der
    plugins.txt stehen viele Kommentare, Vorschläge und Notizen darüber,
    was bewusst NICHT dazugehört. Die wegzuwerfen, weil ein Plugin
    dazukam, wäre ein schlechter Tausch.
    """
    neue_zeile = f"{name}|{version}|{url}|{sha256}\n"
    try:
        text = Path(PLUGIN_LISTE).read_text(encoding="utf-8", errors="ignore")
    except OSError:
        text = ""

    zeilen, ersetzt = [], False
    for zeile in text.splitlines(keepends=True):
        nackt = zeile.strip()
        if nackt and not nackt.startswith("#") and nackt.split("|")[0].strip() == name:
            if not ersetzt:
                zeilen.append(neue_zeile)
                ersetzt = True
            continue
        zeilen.append(zeile)

    if not ersetzt:
        if zeilen and not zeilen[-1].endswith("\n"):
            zeilen.append("\n")
        zeilen.append(neue_zeile)

    Path(PLUGIN_LISTE).write_text("".join(zeilen), encoding="utf-8")


def installieren(projekt, version_id):
    """Lädt eine Fassung, prüft sie und trägt sie in plugins.txt ein.

    Der ganze Weg mit seinen Begründungen steht im Kopfkommentar dieses
    Moduls. Kurz: herunterladen, SHA512 gegen Modrinth prüfen, SHA256
    daraus bilden, ablegen, eintragen, von plugin-update.sh bestätigen
    lassen.
    """
    fassungen, fehler = versionen(projekt)
    if fehler:
        return "fehler", fehler

    gewaehlt = next((f for f in fassungen if f["id"] == version_id), None)
    if gewaehlt is None:
        return "fehler", "Diese Fassung gibt es nicht (mehr)."
    if not gewaehlt["url"] or not gewaehlt["sha512"]:
        return "fehler", ("Modrinth liefert für diese Fassung keine "
                          "Prüfsumme. Ohne die wird hier nichts installiert.")

    # Die Adresse muss von Modrinth kommen. Sie stammt zwar aus deren
    # eigener Antwort, aber ein Download von irgendwoher ist genau die
    # Sorte Zutrauen, die man sich nicht angewöhnen sollte.
    if not gewaehlt["url"].startswith("https://cdn.modrinth.com/"):
        return "fehler", f"Unerwartete Download-Adresse: {gewaehlt['url'][:60]}"

    anfrage = urllib.request.Request(gewaehlt["url"],
                                     headers={"User-Agent": KENNUNG})
    try:
        with urllib.request.urlopen(anfrage, timeout=120) as antwort, \
                tempfile.NamedTemporaryFile(delete=False, suffix=".jar") as ziel:
            shutil.copyfileobj(antwort, ziel)
            zwischendatei = ziel.name
    except (urllib.error.URLError, OSError) as fehler:
        return "fehler", f"Der Download ist fehlgeschlagen: {fehler}"

    try:
        roh = Path(zwischendatei).read_bytes()
        if hashlib.sha512(roh).hexdigest() != gewaehlt["sha512"]:
            return "fehler", ("Die Prüfsumme der geladenen Datei stimmt nicht "
                              "mit Modrinths Angabe überein. Der Download war "
                              "unvollständig oder verändert — es wurde nichts "
                              "installiert.")
        sha256 = hashlib.sha256(roh).hexdigest()

        # Der Name muss der aus der plugin.yml sein: plugin-update.sh legt
        # die Datei als <name>.jar ab und sucht sie später genau so wieder.
        name, dateiversion = _aus_jar(zwischendatei)
        if not re.match(r"^[A-Za-z0-9._-]{1,64}$", name):
            return "fehler", f"Unerwarteter Plugin-Name im Jar: {name[:40]}"

        os.makedirs(PLUGIN_DIR, exist_ok=True)
        ziel = os.path.join(PLUGIN_DIR, f"{name}.jar")
        # Erst daneben, dann umbenennen — wie ueberall sonst in diesem
        # Projekt. Ein copyfile direkt auf den Endnamen laesst bei einem
        # Abbruch ein abgeschnittenes .jar in plugins/ liegen, und Paper
        # scheitert beim naechsten Start daran, statt es zu ueberspringen.
        roh_ziel = os.path.join(PLUGIN_DIR, f".unfertig-{name}.jar")
        shutil.copyfile(zwischendatei, roh_ziel)
        os.replace(roh_ziel, ziel)
    finally:
        try:
            os.remove(zwischendatei)
        except OSError:
            pass

    # Schlaegt der Eintrag fehl, muss das Jar wieder weg.
    #
    # Sonst laege eine Datei in plugins/, die in keiner plugins.txt steht:
    # "mcs plugins" meldete sie dauerhaft als "nicht in der Liste", und der
    # naechste Serverstart luede ein Plugin, das niemand bestellt hat. Halb
    # installiert ist hier schlechter als gar nicht.
    try:
        _zeile_setzen(name, gewaehlt["nummer"] or dateiversion,
                      gewaehlt["url"], sha256)
    except OSError as fehler:
        try:
            os.remove(ziel)
        except OSError:
            pass
        return "fehler", (f"{name} konnte nicht in die plugins.txt eingetragen "
                          f"werden ({fehler}). Das Jar wurde wieder entfernt — "
                          "es ist nichts halb installiert.")

    # Und jetzt dasselbe Werkzeug prüfen lassen, das auch bei einer frischen
    # Installation prüft. Es findet die Datei bereits korrekt vor.
    code, aus, fehlertext = run_command(
        ["/usr/bin/bash", f"{MCS_SERVER_DIR}/plugin-update.sh", "--laden"],
        timeout=300, cwd=MCS_SERVER_DIR)
    bestaetigung = (aus or fehlertext or "").strip()
    # Wie beim Umschalten: Eine neue Datei in plugins/ soll sich später
    # zuordnen lassen, auch wenn die Prüfung danach etwas zu meckern hatte.
    aktion_vermerken("plugin_installiert", f"{name} {gewaehlt['nummer'] or dateiversion}")

    if code != 0:
        return "warnung", (f"{name} wurde geladen und eingetragen, aber "
                           f"plugin-update.sh meldet einen Fehler:\n{bestaetigung}")
    return "gut", (f"{name} {gewaehlt['nummer']} installiert und geprüft. "
                   "Das wirkt erst nach einem Neustart des Servers — Paper "
                   f"lädt Plugins nur beim Start.\n\n{bestaetigung}")


def abgleich():
    """`plugin-update.sh` ohne Parameter: zeigt Soll und Ist im Vergleich."""
    code, aus, fehler = run_command(
        ["/usr/bin/bash", f"{MCS_SERVER_DIR}/plugin-update.sh"],
        timeout=120, cwd=MCS_SERVER_DIR)
    return ("gut" if code == 0 else "warnung"), (aus or fehler or "(keine Ausgabe)")


# ----------------------------------------------------------------------------
# Vorschläge
# ----------------------------------------------------------------------------
# Die Empfehlungen aus Lastenheft 5.8. Sie stehen hier und nicht in der
# Vorlage, weil hier auch ihre Begründung steht — und die ist der Grund,
# warum man eines davon will.
VORSCHLAEGE = [
    {
        "slug": "chunky", "titel": "Chunky",
        "warum": ("Gelände zu erzeugen ist mit Abstand das Teuerste, was ein "
                  "Server tut — deshalb ruckelt es genau dann, wenn jemand in "
                  "unerforschtes Gebiet läuft. Einmal über Nacht einen Radius "
                  "vorgenerieren, und das Problem ist praktisch weg. Einmalig "
                  "benutzt, große Wirkung."),
    },
    {
        "slug": "worldedit", "titel": "WorldEdit",
        "warum": ("Große Bereiche auf einmal setzen, kopieren, spiegeln. Wer "
                  "je von Hand eine Wand aus 400 Blöcken gebaut hat, weiß, "
                  "warum es das gibt."),
    },
    {
        "slug": "worldguard", "titel": "WorldGuard",
        "warum": ("Gebiete markieren, in denen nur bestimmte Spieler bauen "
                  "dürfen. Braucht WorldEdit."),
    },
    # GSit stand hier bis zum 21.10.2026 — auf Wunsch des Betreibers
    # gestrichen, zusammen mit Lastenheft 5.8 und plugins.txt.beispiel.
]
