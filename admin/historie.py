#!/usr/bin/env python3
"""
historie.py — Wer war wann online, wie lange, und was wurde dabei gesagt.

Zwei Quellen, eine Ablage:

    Sitzungen          <- player_activity.log (das Hauptbuch)
    Chat und Befehle   <- mc_server/logs/*.log.gz und latest.log

Beides landet in `admin/historie.db`.

**Warum eine eigene Datei und nicht metrik.db:** Die Metriken sind Messwerte
mit kurzer Halbwertszeit, die Historie ist ein Archiv mit eigener
Aufbewahrungsfrist. Und sie enthaelt Chat-Inhalte, also etwas, das Menschen
einander geschrieben haben. Das gehoert hinter eigene Rechte (chmod 600) und
nicht in eine Datei, die daneben Temperaturkurven fuehrt.

**Warum kein Timer und kein eigener Dienst:** Der Index wird beim Oeffnen der
Historienseite fortgeschrieben, nicht im Hintergrund. Bei geschlossener
Oberflaeche kostet die Historie damit null Rechenzeit -- Leitsatz 1. Den
ersten, grossen Durchlauf uebernimmt tools/historie-aufbauen.py.

**Die Entscheidung, bei der das Naheliegende falsch ist** (21.09.2026): Ein
Beitritt ohne zugehoeriges Ende entsteht bei einem Serverabsturz. Drei
Umgangsweisen sind denkbar, und die bequemste ist die schlechteste:

    Sitzung verwerfen          Belegte Anwesenheit verschwindet.
    bis zum naechsten Beitritt  Im Messbeispiel waeren das ZWEI TAGE statt
    rechnen                     weniger Minuten -- eine Zahl, die wie eine
                                gemessene aussieht und frei erfunden ist.
    Ende offen lassen           "Wir wissen, dass er da war. Wann er ging,
    (so ist es gebaut)          wissen wir nicht."

Das Hauptbuch enthaelt keine Serverstarts, also gibt es im Protokoll kein
Merkmal, an dem sich das wahre Ende ablesen liesse. Eine Untergrenze waere
genauso erfunden wie eine Obergrenze. Die Oberflaeche zeigt solche Sitzungen
als "Ende unbekannt" und die Summen lassen sie aus -- und sagen das.
"""

import gzip
import os
import re
import sqlite3
from datetime import date, datetime, timedelta
from pathlib import Path

import logdatum
from protokoll import CHAT_RE, COMMAND_RE

SCHEMA = """
CREATE TABLE IF NOT EXISTS sitzung (
  spieler  TEXT    NOT NULL,
  beginn   TEXT    NOT NULL,          -- 'YYYY-MM-DD HH:MM:SS', Lokalzeit
  ende     TEXT,                      -- NULL = laeuft noch ODER abgebrochen
  sekunden INTEGER,                   -- NULL, solange ende NULL ist
  grund    TEXT,                      -- verlassen | verbindung | abbruch
  PRIMARY KEY (spieler, beginn)
);
CREATE INDEX IF NOT EXISTS sitzung_beginn ON sitzung (beginn);

CREATE TABLE IF NOT EXISTS aeusserung (
  zeit    TEXT NOT NULL,
  spieler TEXT NOT NULL,
  art     TEXT NOT NULL,              -- chat | befehl
  inhalt  TEXT NOT NULL,
  PRIMARY KEY (zeit, spieler, art, inhalt)
);
CREATE INDEX IF NOT EXISTS aeusserung_zeit ON aeusserung (zeit);

-- Welche Serverprotokolle schon ausgewertet sind.
--
-- Nur ARCHIVE werden hier vermerkt: Sie aendern sich nie wieder. latest.log
-- steht bewusst nicht drin -- es waechst, und es laesst sich nicht
-- stueckweise auswerten (siehe logdatum.daten_rueckwaerts: das Datum der
-- ersten Zeile haengt am Ende der Datei).
CREATE TABLE IF NOT EXISTS quelle (
  datei   TEXT PRIMARY KEY,
  groesse INTEGER NOT NULL DEFAULT 0
);
"""

# Zeilenformat des Hauptbuchs:
#   2026-05-10 20:00:00 | Spieler_A ist dem Spiel beigetreten
_ZEILE = re.compile(r"^(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}) \| (.+)$")
_BEITRITT = re.compile(r"^([A-Za-z0-9_]{1,16}) ist dem Spiel beigetreten$")
_VERLASSEN = re.compile(r"^([A-Za-z0-9_]{1,16}) hat das Spiel verlassen$")
_VERBINDUNG = re.compile(
    r"^([A-Za-z0-9_]{1,16}) hat die Verbindung verloren \(Grund: (.*)\)$")

_ZEITFORM = "%Y-%m-%d %H:%M:%S"

# Wie weit die beiden Zeilen EINER Trennung auseinanderliegen duerfen, damit
# die zweite noch als Nachtrag des Grundes gilt und nicht als neues Ereignis.
# Gemessen am 21.09.2026: hoechstens eine Sekunde. Zwei lassen Luft, ohne
# dass zwei getrennte Besuche desselben Spielers je zusammenfallen koennten --
# dazwischen liegt immer mindestens ein Beitritt, und der raeumt die Stelle ab.
_PAARFENSTER_S = 2


def verbindung(pfad):
    """Oeffnet die Historien-Datenbank und legt das Schema an, wenn noetig.

    Die Rechte werden hier gesetzt und nicht im Werkzeug: Es gibt drei
    Wege in diese Datei -- die Seite, tools/historie-aufbauen.py und die
    Pruefung -- und nur an dieser einen Stelle treffen sie sich. Ein
    "chmod" im Werkzeug allein waere der zweite Weg zur selben Sache, der
    die Regel des ersten nicht kennt.

    Und sie werden VOR dem ersten Schreiben gesetzt, nicht danach. Die
    Datei enthaelt Chat-Inhalte und Spielernamen; laege sie auch nur einen
    Wimpernschlag offen, waere das bei einem Abbruch dazwischen dauerhaft.
    """
    pfad = Path(pfad)

    # Anlegen mit 0600, bevor SQLite sie anfasst. os.open statt touch,
    # weil nur so der Modus schon bei der Erzeugung gilt -- ein
    # nachtraegliches chmod hat immer eine Luecke davor.
    if not pfad.exists():
        os.close(os.open(str(pfad), os.O_CREAT | os.O_WRONLY, 0o600))
    elif (pfad.stat().st_mode & 0o077):
        # Eine aeltere Installation hat sie offener angelegt. Stillschweigend
        # richtigstellen ist hier richtig: Es nimmt niemandem etwas weg.
        os.chmod(pfad, 0o600)

    db = sqlite3.connect(str(pfad))
    db.executescript(SCHEMA)
    db.commit()
    return db


def _sekunden(beginn, ende):
    return int((datetime.strptime(ende, _ZEITFORM)
                - datetime.strptime(beginn, _ZEITFORM)).total_seconds())


# ----------------------------------------------------------------------------
# Sitzungen
# ----------------------------------------------------------------------------
def sitzungen_einlesen(hauptbuch, db):
    """Traegt alle Sitzungen des Hauptbuchs ein. Liefert die Anzahl NEUER.

    Wiederholbar, und zwar in zwei Richtungen: Der Primaerschluessel
    (spieler, beginn) faengt Doppelte ab, und eine Sitzung, die beim
    letzten Lauf noch offen war, bekommt jetzt ihr Ende nachgetragen --
    deshalb INSERT OR REPLACE und nicht OR IGNORE.

    Das Hauptbuch ganz zu lesen ist Absicht: Es ist die einzige Quelle, in
    der eine Sitzung ihr Ende erst Stunden nach ihrem Anfang bekommt. Eine
    Lesemarke haette genau diese Faelle verpasst. Bei 139 KB im halben Jahr
    ist das kein Argument wert.
    """
    offen = {}        # spieler -> beginn
    fertige = []      # [spieler, beginn, ende, sekunden, grund]
    # Wo die zuletzt geschlossene Sitzung eines Spielers steht, und wann
    # sie endete. Nur dafuer da, den Grund nachtragen zu koennen.
    zuletzt = {}      # spieler -> (index in fertige, endezeit)

    with open(hauptbuch, "r", encoding="utf-8", errors="ignore") as f:
        for zeile in f:
            treffer = _ZEILE.match(zeile.rstrip("\n"))
            if not treffer:
                continue
            zeit, text = treffer.group(1), treffer.group(2)

            beitritt = _BEITRITT.match(text)
            if beitritt:
                name = beitritt.group(1)
                if name in offen:
                    # Ein zweiter Beitritt, waehrend noch eine Sitzung offen
                    # ist. Zwei Ursachen, und sie sehen hier gleich aus:
                    #
                    #  * Serverabsturz -- die alte Sitzung hat nie ein Ende
                    #    bekommen, und wann sie endete, steht nirgends.
                    #  * Anmeldung von einem zweiten Geraet -- Paper meldet
                    #    dann ZUERST den neuen Beitritt und wirft erst danach
                    #    die alte Verbindung hinaus ("You logged in from
                    #    another location"), in derselben Sekunde.
                    #
                    # Vorlaeufig gilt "abbruch". Kommen gleich darauf die
                    # Abmeldezeilen, traegt der Block weiter unten Ende und
                    # Grund nach -- er erkennt den Fall daran, dass die neue
                    # Sitzung GENAU in dem Moment begann, in dem die alte
                    # geschlossen wurde.
                    fertige.append([name, offen[name], None, None, "abbruch"])
                    zuletzt[name] = (len(fertige) - 1, zeit)
                else:
                    zuletzt.pop(name, None)
                offen[name] = zeit
                continue

            # Ein Ende, und die zwei Zeilen dafuer.
            #
            # Paper schreibt fuer EINE Trennung zwei Zeilen in derselben
            # Sekunde -- "hat das Spiel verlassen" und "hat die Verbindung
            # verloren (Grund: …)" -- in wechselnder Reihenfolge. Am
            # 21.09.2026 nachgezaehlt: 350 Paare, dazu 7-mal nur die eine
            # und 7-mal nur die andere. Nur die Verbindungszeile traegt den
            # Grund, und der ist keine Formsache: neben "Disconnected" kamen
            # "You have been idle for too long!", "Server closed", "Timed
            # out" und "You logged in from another location" vor.
            #
            # Deshalb schliesst die ERSTE Zeile die Sitzung, und eine
            # Verbindungszeile in derselben Sekunde traegt den Grund
            # nachtraeglich ein. Wer stattdessen die erste Zeile auch den
            # Grund bestimmen laesst, schreibt Sortierreihenfolge in die
            # Datenbank und nennt sie Grund.
            verbindung_weg = _VERBINDUNG.match(text)
            verlassen = _VERLASSEN.match(text)
            if not (verbindung_weg or verlassen):
                continue

            name = (verbindung_weg or verlassen).group(1)
            grund = verbindung_weg.group(2) if verbindung_weg else "verlassen"
            stelle = zuletzt.get(name)

            # ZUERST: Gehoert dieses Ende noch zur ABGELOESTEN Verbindung?
            #
            # Beim Anmelden von einem zweiten Geraet meldet Paper erst den
            # neuen Beitritt und wirft danach die alte Verbindung hinaus.
            # Die Abmeldezeilen kommen also, waehrend die NEUE Sitzung schon
            # offen ist -- wer sie ihr zuschlaegt, erzeugt eine Sitzung von
            # null Sekunden und laesst die echte als "abbruch" ohne Dauer
            # stehen. Am 21.09.2026 auf echten Daten gesehen: zwei der drei
            # "abbruch"-Faelle waren in Wahrheit Doppel-Anmeldungen.
            #
            # Erkennungsmerkmal, und es ist ein exaktes: Die offene Sitzung
            # begann GENAU in dem Moment, in dem die vorige geschlossen
            # wurde. Das passiert sonst nie.
            if (stelle and offen.get(name) == stelle[1]
                    and abs(_sekunden(stelle[1], zeit)) <= _PAARFENSTER_S):
                alt = fertige[stelle[0]]
                if alt[2] is None:
                    alt[2] = zeit
                    alt[3] = _sekunden(alt[1], zeit)
                    alt[4] = grund
                elif verbindung_weg:
                    alt[4] = grund
                continue

            if name in offen:
                beginn = offen.pop(name)
                fertige.append([name, beginn, zeit,
                                _sekunden(beginn, zeit), grund])
                zuletzt[name] = (len(fertige) - 1, zeit)
                continue

            # Die zweite Zeile desselben Endes: Sie darf keine neue Sitzung
            # anlegen, aber sie darf den Grund liefern.
            #
            # Die beiden Zeilen stehen NICHT immer in derselben Sekunde. Auf
            # den echten Daten (21.09.2026) ueberspannen 14 von 364 Paaren
            # eine Sekundengrenze, z. B. 13:21:59 / 13:22:00. Dort ging es
            # gut aus, weil zufaellig die Verbindungszeile zuerst kam; in
            # der anderen Reihenfolge waere der Grund verlorengegangen.
            # Deshalb ein kleines Fenster statt eines Gleichheitstests.
            if (verbindung_weg and stelle
                    and abs(_sekunden(stelle[1], zeit)) <= _PAARFENSTER_S):
                fertige[stelle[0]][4] = grund

    # Was am Ende des Hauptbuchs offen ist, laeuft entweder gerade oder der
    # Server steht. Beides bekommt weder Ende noch Grund -- "laeuft noch"
    # und "wissen wir nicht" sind ehrlicher als eine Zahl.
    for name, beginn in offen.items():
        fertige.append([name, beginn, None, None, None])

    vorher = db.execute("SELECT COUNT(*) FROM sitzung").fetchone()[0]
    db.executemany(
        "INSERT OR REPLACE INTO sitzung "
        "(spieler, beginn, ende, sekunden, grund) VALUES (?, ?, ?, ?, ?)",
        fertige)
    db.commit()
    return db.execute("SELECT COUNT(*) FROM sitzung").fetchone()[0] - vorher


# ----------------------------------------------------------------------------
# Chat und Befehle
# ----------------------------------------------------------------------------
def _zeilen(pfad):
    """Liest eine Logdatei ganz, gepackt oder nicht.

    Kein "zcat | grep": Gepackte Protokolle und `set -o pipefail` sind in
    diesem Projekt schon aufeinandergestossen (grep bricht ab, der Erzeuger
    bekommt SIGPIPE, Rueckgabewert 141 trotz Treffer). In Python mit dem
    gzip-Modul gibt es diese Falle nicht.

    Ganz und nicht ab einer Lesemarke: latest.log wird rueckwaerts datiert,
    das Datum der ersten Zeile haengt also am Ende der Datei.
    """
    oeffnen = gzip.open if str(pfad).endswith(".gz") else open
    try:
        with oeffnen(pfad, "rt", encoding="utf-8", errors="ignore") as f:
            return f.read().splitlines()
    except (OSError, EOFError) as fehler:
        # Ein abgebrochenes Archiv ist kein Grund, den ganzen Index
        # aufzugeben — aber auch keiner, es zu verschweigen.
        print(f"  ! {Path(pfad).name} liess sich nicht lesen: {fehler}")
        return []


def aeusserungen_einlesen(logordner, db):
    """Traegt Chat und Befehle aus den Serverprotokollen ein.

    Fortlaufend: Ein Archiv wird genau einmal gelesen und vermerkt.
    latest.log waechst und wird bei JEDEM Lauf ganz gelesen -- der
    Primaerschluessel faengt ab, was schon drinsteht.
    """
    logordner = Path(logordner)
    if not logordner.is_dir():
        return 0

    fertig = {name for (name,) in db.execute("SELECT datei FROM quelle")}
    vorher = db.execute("SELECT COUNT(*) FROM aeusserung").fetchone()[0]

    for pfad in sorted(logordner.iterdir()):
        if not logdatum.ist_serverprotokoll(pfad.name):
            continue                      # gc.log und alles Fremde
        ist_archiv = logdatum.archivtag(pfad.name) is not None
        if ist_archiv and pfad.name in fertig:
            continue

        zeilen = _zeilen(pfad)
        zeitpunkte = logdatum.datieren(pfad, zeilen)

        eintraege = []
        for zeile, zeitpunkt in zip(zeilen, zeitpunkte):
            if zeitpunkt is None:
                continue
            stempel = zeitpunkt.strftime(_ZEITFORM)

            befehl = COMMAND_RE.match(zeile)
            if befehl:
                eintraege.append((stempel, befehl.group(2), "befehl",
                                  befehl.group(3)))
                continue
            chat = CHAT_RE.search(zeile)
            if chat:
                eintraege.append((stempel, chat.group(1), "chat",
                                  chat.group(2)))

        db.executemany(
            "INSERT OR IGNORE INTO aeusserung (zeit, spieler, art, inhalt) "
            "VALUES (?, ?, ?, ?)", eintraege)
        if ist_archiv:
            db.execute(
                "INSERT OR REPLACE INTO quelle (datei, groesse) VALUES (?, ?)",
                (pfad.name, pfad.stat().st_size))
        db.commit()

    return db.execute("SELECT COUNT(*) FROM aeusserung").fetchone()[0] - vorher


# ----------------------------------------------------------------------------
# Abfragen
# ----------------------------------------------------------------------------
def _als_dicts(zeilen, felder):
    return [dict(zip(felder, z)) for z in zeilen]


_SITZUNGSFELDER = ("spieler", "beginn", "ende", "sekunden", "grund")


def sitzungen(db, spieler=None, ab=None, grenze=200):
    """Sitzungen, neueste zuerst. `ab` ist ein Tag als 'YYYY-MM-DD'."""
    frage = ("SELECT spieler, beginn, ende, sekunden, grund FROM sitzung "
             "WHERE 1=1")
    werte = []
    if spieler:
        frage += " AND spieler = ?"
        werte.append(spieler)
    if ab:
        frage += " AND beginn >= ?"
        werte.append(ab)
    frage += " ORDER BY beginn DESC LIMIT ?"
    werte.append(grenze)
    return _als_dicts(db.execute(frage, werte).fetchall(), _SITZUNGSFELDER)


def summen_je_tag(db, tage=30, spieler=None):
    """Spielzeit je Tag und Spieler — die Grundlage der Balken.

    Sitzungen ohne bekanntes Ende fehlen hier zwangslaeufig (`sekunden IS
    NULL`). Wie viele das sind, sagt `offene_sitzungen()` — die Oberflaeche
    muss es dazuschreiben, sonst liest sich eine unvollstaendige Summe wie
    eine vollstaendige.
    """
    ab = (date.today() - timedelta(days=tage)).isoformat()
    frage = ("SELECT substr(beginn, 1, 10) AS tag, spieler, SUM(sekunden) "
             "FROM sitzung WHERE sekunden IS NOT NULL AND beginn >= ?")
    werte = [ab]
    if spieler:
        frage += " AND spieler = ?"
        werte.append(spieler)
    frage += " GROUP BY tag, spieler ORDER BY tag DESC"
    return _als_dicts(db.execute(frage, werte).fetchall(),
                      ("tag", "spieler", "sekunden"))


def summen_je_spieler(db, tage=30):
    """Gesamte bekannte Spielzeit je Spieler im Zeitraum, laengste zuerst."""
    ab = (date.today() - timedelta(days=tage)).isoformat()
    zeilen = db.execute(
        "SELECT spieler, SUM(sekunden), COUNT(*) FROM sitzung "
        "WHERE sekunden IS NOT NULL AND beginn >= ? "
        "GROUP BY spieler ORDER BY SUM(sekunden) DESC", (ab,)).fetchall()
    return _als_dicts(zeilen, ("spieler", "sekunden", "sitzungen"))


def offene_sitzungen(db, tage=30):
    """Wie viele Sitzungen im Zeitraum kein bekanntes Ende haben.

    Diese Zahl gehoert neben jede Summe. Ohne sie sieht eine Summe, der
    Stunden fehlen, genauso aus wie eine vollstaendige — dieselbe Sorte
    stiller Fehlaussage wie "nicht aufgezeichnet" auf der Spielerseite.
    """
    ab = (date.today() - timedelta(days=tage)).isoformat()
    return db.execute(
        "SELECT COUNT(*) FROM sitzung WHERE sekunden IS NULL AND beginn >= ?",
        (ab,)).fetchone()[0]


def aeusserungen(db, spieler=None, ab=None, art=None, grenze=200):
    """Chat und Befehle, neueste zuerst."""
    frage = "SELECT zeit, spieler, art, inhalt FROM aeusserung WHERE 1=1"
    werte = []
    if spieler:
        frage += " AND spieler = ?"
        werte.append(spieler)
    if ab:
        frage += " AND zeit >= ?"
        werte.append(ab)
    if art:
        frage += " AND art = ?"
        werte.append(art)
    frage += " ORDER BY zeit DESC LIMIT ?"
    werte.append(grenze)
    return _als_dicts(db.execute(frage, werte).fetchall(),
                      ("zeit", "spieler", "art", "inhalt"))


def zeitraum(db):
    """(erster, letzter) Tag, ueber den die Historie etwas weiss.

    Gehoert sichtbar auf die Seite, und zwar nicht als Zierde: Die
    Spielerseite zeigt die Spielzeit aus Papers Statistikdateien, und die
    reicht weiter zurueck als das aelteste Serverprotokoll. Am 21.09.2026
    auf diesem Pi gemessen -- 545 h in der Statistik gegen 92 h in der
    Historie, weil die Protokolle erst im Maerz beginnen und die Welt
    aelter ist. Ohne den Zeitraum daneben sieht das wie ein Fehler aus,
    oder schlimmer: Man glaubt der kleineren Zahl.
    """
    von = db.execute(
        "SELECT MIN(tag) FROM (SELECT MIN(substr(beginn,1,10)) AS tag "
        "FROM sitzung UNION SELECT MIN(substr(zeit,1,10)) FROM aeusserung)"
    ).fetchone()[0]
    bis = db.execute(
        "SELECT MAX(tag) FROM (SELECT MAX(substr(beginn,1,10)) AS tag "
        "FROM sitzung UNION SELECT MAX(substr(zeit,1,10)) FROM aeusserung)"
    ).fetchone()[0]
    return von, bis


def spielerliste(db):
    """Alle Namen, ueber die die Historie etwas weiss — fuer den Filter."""
    return [n for (n,) in db.execute(
        "SELECT spieler FROM sitzung UNION "
        "SELECT spieler FROM aeusserung ORDER BY 1")]


# ----------------------------------------------------------------------------
# Fortschreiben und Aufraeumen
# ----------------------------------------------------------------------------
def aktualisieren(db, hauptbuch, logordner):
    """Schreibt den Index fort. Wird beim Seitenaufruf gerufen, nie im Takt."""
    return {"sitzungen": sitzungen_einlesen(hauptbuch, db),
            "aeusserungen": aeusserungen_einlesen(logordner, db)}


def aufraeumen(db, tage):
    """Loescht Eintraege aelter als `tage`. 0 heisst unbegrenzt.

    Die ausdrueckliche 0 ist hier kein Sonderfall aus Hoeflichkeit: In
    diesem Projekt wurde aus MCS_BACKUP_BEHALTEN=0 einmal "behalte ab
    Zeile 1", und ein Lauf raeumte beide Backup-Platten leer (31.08.2026).
    Seither heisst 0 ueberall ausdruecklich "aus", und geloescht wird nie
    auf Grundlage eines Wertes, dem der Code nicht trauen kann.
    """
    try:
        tage = int(tage)
    except (TypeError, ValueError):
        return 0
    if tage <= 0:
        return 0

    grenze = (date.today() - timedelta(days=tage)).isoformat()
    weg = db.execute("DELETE FROM sitzung WHERE beginn < ?", (grenze,)).rowcount
    weg += db.execute("DELETE FROM aeusserung WHERE zeit < ?",
                      (grenze,)).rowcount
    db.commit()
    return weg
