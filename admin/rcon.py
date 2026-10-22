#!/usr/bin/env python3
"""
rcon.py — Mit dem laufenden Minecraft-Server sprechen und eine Antwort bekommen.

Warum überhaupt? Bisher gehen Befehle über die screen-Sitzung
(`screen -X stuff`). Das ist ein Briefkasten ohne Rückweg: Man wirft etwas
ein und muss die Antwort hinterher aus latest.log fischen. Für "sag allen
Hallo" reicht das. Für "wer steht auf der Whitelist?" oder "welches
Berechtigungslevel hat Steve?" nicht — und genau solche Fragen stellt die
geplante Spielerseite.

RCON ist Minecrafts eingebaute Fernsteuerung: Man schickt einen Befehl und
bekommt zurück, was der Server in die Konsole geschrieben hätte.

screen bleibt trotzdem: für `mcs console` zum Mitlesen, und weil systemd
einen Vordergrundprozess braucht. Die beiden stören sich nicht.

SICHERHEITSHINWEIS
------------------
Am 2026-08-28 nachgemessen (Paper 26.2 Build 119):

    [INFO]: RCON running on 0.0.0.0:25575

RCON lauscht auf ALLEN Netzwerkkarten, nicht nur lokal. Einen Schlüssel
`rcon.ip` gibt es nicht — Minecraft koppelt die Adresse an `server-ip`, und
die muss leer bleiben, damit der Spielserver von außen erreichbar ist.

Abgeschottet wird der Port deshalb von der Firewall. Wer RCON einschaltet
und die Firewall weglässt, öffnet im lokalen Netz eine Fernsteuerung für
seinen Server. Das Passwort ist damit die letzte Verteidigungslinie und wird
bei der Installation zufällig erzeugt.

DAS PROTOKOLL
-------------
Ein Paket besteht aus vier Teilen, alle Zahlen little-endian:

    [Länge: 4 Byte][Kennung: 4 Byte][Typ: 4 Byte][Text][0x00][0x00]

Die Länge zählt alles NACH sich selbst. Die Kennung wählt der Aufrufer; der
Server schickt sie in seiner Antwort zurück — daran erkennt man, welche
Antwort zu welcher Frage gehört.

Typen:
    3  Anmelden          (wir → Server)
    2  Befehl ausführen  (wir → Server)
    0  Antwort           (Server → wir)
    2  Anmeldung ok      (Server → wir; ja, dieselbe Zahl wie "Befehl")
"""

import socket
import struct
import threading

# Nur fuer den Pfad der server.properties und den gemeinsamen KEY=WERT-Leser.
# einstellungen.py ist das Blattmodul (es importiert nichts Eigenes), also
# entsteht dadurch kein Ring — auch nicht, wenn metrik.py rcon.py laedt.
from einstellungen import SERVER_PROPERTIES, kv_lesen

# --- Pakettypen -------------------------------------------------------------
TYP_ANMELDEN = 3
TYP_BEFEHL = 2
TYP_ANTWORT = 0

# Ein Paket darf höchstens so groß werden. Der Wert stammt aus der
# Protokollbeschreibung; alles Größere ist entweder ein Fehler oder ein
# Versuch, uns den Speicher vollzuschreiben.
MAX_PAKETLAENGE = 4 * 1024 * 1024


class RconFehler(Exception):
    """Irgendetwas an der RCON-Verbindung ging schief."""


class RconAnmeldungFehlgeschlagen(RconFehler):
    """Falsches Passwort.

    Eigene Klasse, weil der Fall eine andere Antwort verdient als ein
    Netzwerkproblem: Beim falschen Passwort schließt der Server einfach die
    Verbindung. Wer nur auf Ausnahmen schaut, sieht dann einen
    Verbindungsabbruch und rät auf ein Netzproblem — dabei muss schlicht
    jemand das Passwort richtigstellen.
    """


class RconZeitueberschreitung(RconFehler):
    """Der Server hat nicht rechtzeitig geantwortet.

    Ebenfalls eine eigene Klasse, und aus demselben Grund wie oben — nur
    andersherum. RCON wird im Hauptthread von Paper abgearbeitet, und
    Leitsatz 1 raeumt selbst ein, dass der beschaeftigt sein kann. Bis zum
    2026-08-31 schrieb _anmelden() jeden RconFehler zu "vermutlich das
    falsche Passwort" um: Ein Ruckler beim Speichern einer grossen Welt
    schickte den Administrator also los, ein Passwort zu aendern, das
    stimmte. Genau die Fehldiagnose, gegen die es diese Klassen gibt.
    """


def _paket_bauen(kennung, typ, text):
    """Baut ein Paket nach obigem Schema."""
    rumpf = struct.pack("<ii", kennung, typ) + text.encode("utf-8") + b"\x00\x00"
    return struct.pack("<i", len(rumpf)) + rumpf


def _genau_lesen(verbindung, anzahl):
    """Liest genau so viele Bytes — oder wirft.

    recv() darf jederzeit weniger liefern als angefordert; das ist kein
    Fehler, sondern normal. Wer das übersieht, baut einen Leser, der bei
    kleinen Antworten immer funktioniert und bei großen gelegentlich Unsinn
    liefert.
    """
    daten = b""
    while len(daten) < anzahl:
        try:
            stueck = verbindung.recv(anzahl - len(daten))
        except socket.timeout as fehler:
            # Als eigene Klasse weiterreichen, damit die Anmeldung sie nicht
            # zu "falsches Passwort" umdeutet (siehe RconZeitueberschreitung).
            raise RconZeitueberschreitung(
                f"Der Server hat innerhalb von {verbindung.gettimeout()} s "
                "nicht geantwortet. Das ist kein Passwortproblem — RCON läuft "
                "im Hauptthread des Servers, der gerade beschäftigt sein kann."
            ) from fehler
        if not stueck:
            raise RconFehler("Der Server hat die Verbindung geschlossen.")
        daten += stueck
    return daten


def _paket_lesen(verbindung):
    """Liest ein Paket und liefert (Kennung, Typ, Rohbytes).

    Bewusst BYTES und kein Text: Eine lange Antwort kommt in mehreren
    Paketen, und die Grenze faellt irgendwo in den Bytestrom — auch mitten
    in ein UTF-8-Zeichen. Wer jedes Paket einzeln dekodiert, macht aus
    einem halben "ue" zwei Ersatzzeichen; zusammengesetzt waere es
    fehlerfrei gewesen. Bei einer Whitelist mit Umlauten im Namen war das
    reproduzierbar (gefunden 2026-08-31). Dekodiert wird deshalb erst,
    wenn alle Teile beisammen sind — siehe befehl().
    """
    (laenge,) = struct.unpack("<i", _genau_lesen(verbindung, 4))
    if laenge < 10 or laenge > MAX_PAKETLAENGE:
        raise RconFehler(f"Unplausible Paketlänge vom Server: {laenge}")
    rumpf = _genau_lesen(verbindung, laenge)
    kennung, typ = struct.unpack("<ii", rumpf[:8])
    # Die beiden abschließenden Nullbytes gehören nicht zum Text.
    return kennung, typ, rumpf[8:-2]


class Rcon:
    """Eine RCON-Verbindung. Gedacht für kurze Benutzung:

        with Rcon(passwort="...") as r:
            print(r.befehl("list"))

    Absichtlich keine Dauerverbindung. RCON wird im HAUPT-Thread des Servers
    abgearbeitet — dort, wo auch die Spielwelt tickt. Eine offene Verbindung
    je Browserfenster wäre eine Einladung, dem Server genau da Zeit zu
    stehlen, wo es weh tut.
    """

    def __init__(self, passwort, host="127.0.0.1", port=25575, zeitlimit=5.0):
        self.host = host
        self.port = port
        self.passwort = passwort
        self.zeitlimit = zeitlimit
        self._verbindung = None
        self._kennung = 0

    # -- Auf- und Abbau ------------------------------------------------------
    def verbinden(self):
        if not self.passwort:
            raise RconFehler(
                "RCON ist nicht eingerichtet: In der server.properties fehlt "
                "'rcon.password', oder 'enable-rcon' steht nicht auf true.")
        try:
            self._verbindung = socket.create_connection(
                (self.host, self.port), timeout=self.zeitlimit)
            # Auch fürs Lesen ein Zeitlimit. Ohne das hängt die
            # Weboberfläche endlos, wenn der Server gerade nicht antwortet —
            # etwa während er eine große Welt speichert.
            self._verbindung.settimeout(self.zeitlimit)
        except OSError as fehler:
            raise RconFehler(
                f"Keine RCON-Verbindung zu {self.host}:{self.port} — {fehler}. "
                "Läuft der Server? Steht 'enable-rcon=true' in der server.properties?"
            ) from fehler
        self._anmelden()
        return self

    def _anmelden(self):
        kennung = self._naechste_kennung()
        self._senden(kennung, TYP_ANMELDEN, self.passwort)
        try:
            antwort_kennung, _typ, _text = self._paket_lesen_intern()
        except RconZeitueberschreitung:
            # Eine Zeitüberschreitung ist KEIN Passwortproblem — unverändert
            # weiterreichen, statt sie zu einer Falschmeldung umzuschreiben.
            raise
        except RconFehler as fehler:
            # Der Server schließt bei falschem Passwort die Verbindung,
            # statt eine Ablehnung zu schicken. Siehe Klassenkommentar.
            raise RconAnmeldungFehlgeschlagen(
                "RCON-Anmeldung fehlgeschlagen — vermutlich das falsche Passwort. "
                "Es steht in 'rcon.password' in der server.properties."
            ) from fehler
        # -1 ist die ausdrückliche Ablehnung.
        if antwort_kennung == -1:
            raise RconAnmeldungFehlgeschlagen(
                "RCON-Anmeldung abgelehnt: falsches Passwort. "
                "Es steht in 'rcon.password' in der server.properties."
            )

    def schliessen(self):
        if self._verbindung is not None:
            try:
                self._verbindung.close()
            except OSError:
                pass
            self._verbindung = None

    def __enter__(self):
        return self.verbinden()

    def __exit__(self, *_):
        self.schliessen()
        return False

    # -- Innereien -----------------------------------------------------------
    def _naechste_kennung(self):
        self._kennung += 1
        return self._kennung

    def _senden(self, kennung, typ, text):
        try:
            self._verbindung.sendall(_paket_bauen(kennung, typ, text))
        except OSError as fehler:
            raise RconFehler(f"Senden fehlgeschlagen: {fehler}") from fehler

    def _paket_lesen_intern(self):
        try:
            return _paket_lesen(self._verbindung)
        except socket.timeout as fehler:
            # Wird heute schon in _genau_lesen abgefangen; bleibt als Netz
            # fuer den Fall, dass hier einmal anders gelesen wird. Wichtig ist
            # die KLASSE: als RconZeitueberschreitung, damit die Anmeldung sie
            # nicht zu "falsches Passwort" umdeutet.
            raise RconZeitueberschreitung(
                f"Der Server hat innerhalb von {self.zeitlimit} s nicht geantwortet."
            ) from fehler
        except OSError as fehler:
            raise RconFehler(f"Lesen fehlgeschlagen: {fehler}") from fehler

    # -- Der eigentliche Zweck -----------------------------------------------
    def befehl(self, text):
        """Führt einen Serverbefehl aus und liefert die Antwort als Text.

        Lange Antworten kommen in MEHREREN Paketen: Ein einzelnes fasst nur
        rund 4 KB. Wer nur eines liest, bekommt bei einer Whitelist mit
        vielen Namen eine abgeschnittene Antwort — und merkt es nicht, weil
        sie ja plausibel aussieht.

        Der übliche Trick dagegen: Direkt hinter den Befehl ein zweites,
        absichtlich sinnloses Paket schicken. Der Server arbeitet die
        Anfragen der Reihe nach ab, also kommt dessen Antwort garantiert
        NACH der letzten Antwort auf den Befehl. Sobald sie auftaucht, ist
        alles Vorherige vollständig eingesammelt.
        """
        if self._verbindung is None:
            raise RconFehler("Nicht verbunden — bitte zuerst verbinden().")

        kennung_befehl = self._naechste_kennung()
        kennung_ende = self._naechste_kennung()
        self._senden(kennung_befehl, TYP_BEFEHL, text)
        self._senden(kennung_ende, TYP_ANTWORT, "")

        teile = []
        while True:
            kennung, _typ, inhalt = self._paket_lesen_intern()
            if kennung == kennung_ende:
                break
            if kennung == kennung_befehl:
                teile.append(inhalt)
            # Pakete mit anderer Kennung gehören zu nichts, was wir gefragt
            # haben — stillschweigend übergehen statt daran zu scheitern.
        # Erst zusammensetzen, dann dekodieren: Ein Zeichen, das auf einer
        # Paketgrenze zerfaellt, ist so wieder heil (siehe _paket_lesen).
        return b"".join(teile).decode("utf-8", errors="replace").strip()


# ----------------------------------------------------------------------------
# Bequemer Zugang für den Rest des Programms
# ----------------------------------------------------------------------------
# Nur EINE Abfrage zur Zeit. Ohne diese Sperre könnten mehrere geöffnete
# Browserfenster gleichzeitig Befehle schicken; jeder davon kostet den Server
# Zeit in seinem Hauptthread, also genau dort, wo Ruckler entstehen.
_sperre = threading.Lock()


def aus_server_properties(pfad=None):
    """Liest Port und Passwort dort, wo sie ohnehin stehen müssen.

    Minecraft liest das RCON-Passwort ausschließlich aus server.properties.
    Es zusätzlich in eine .env zu kopieren, schüfe eine zweite Wahrheit —
    und zwei Kopien eines Geheimnisses laufen früher oder später
    auseinander. Wer das Passwort ändert, ändert es an genau einer Stelle.

    Die Datei gehört dem Server-Benutzer und ist auf 600 gesetzt; die
    Weboberfläche läuft unter demselben Benutzer und darf sie lesen.

    Gelesen wird mit derselben einen KEY=WERT-Funktion wie überall sonst
    (einstellungen.kv_lesen); ist die Datei nicht lesbar, kommt ein leeres
    dict zurück — dann ist RCON eben nicht verfügbar. Das ist kein Grund, die
    Oberfläche scheitern zu lassen.
    """
    return kv_lesen(pfad or SERVER_PROPERTIES)


def rcon_einstellungen(pfad=None):
    """Host, Port und Passwort für eine Verbindung."""
    werte = aus_server_properties(pfad)
    aktiv = werte.get("enable-rcon", "false").lower() == "true"
    try:
        port = int(werte.get("rcon.port", "25575"))
    except ValueError:
        port = 25575
    return {
        # Immer über die lokale Adresse verbinden. Dass der Server AUCH auf
        # anderen Karten lauscht (siehe Sicherheitshinweis oben), ist ein
        # Grund für die Firewall — kein Grund, selbst den Umweg zu nehmen.
        "host": "127.0.0.1",
        "port": port,
        "passwort": werte.get("rcon.password", "") if aktiv else "",
    }


def verfuegbar():
    """Ist RCON eingeschaltet und mit einem Passwort versehen?"""
    return bool(rcon_einstellungen()["passwort"])


def befehl(text, zeitlimit=5.0):
    """Einen Befehl schicken und die Antwort holen — der übliche Weg."""
    werte = rcon_einstellungen()
    with _sperre:
        with Rcon(zeitlimit=zeitlimit, **werte) as verbindung:
            return verbindung.befehl(text)
