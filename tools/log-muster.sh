# shellcheck shell=bash
# shellcheck disable=SC2034
# (Diese Datei wird nur eingelesen, nicht ausgeführt — deshalb kein
#  Shebang. Und die Muster werden vom einlesenden Skript benutzt, nicht
#  hier; die Prüfsoftware kann das nicht sehen.)
#
# log-muster.sh — Die Suchmuster für das Server-Log, an EINER Stelle.
#
# Warum diese Datei? Das Server-Log wurde bisher zweimal ausgewertet: im
# Shell-Skript log_player_activity.sh und noch einmal in der Python-App
# app.py — mit zwei getrennten Musterlisten. Ändert Paper das Logformat,
# hätte man das an zwei Stellen merken und nachziehen müssen; in der
# Praxis fällt so etwas erst auf, wenn eine der beiden Auswertungen
# stillschweigend nichts mehr findet.
#
# Jetzt lesen beide dieselbe Datei: die Shell mit "source", Python mit
# einer kleinen Lesefunktion (siehe lade_log_muster in app.py).
#
# Format: NAME='regulärer Ausdruck' — eine Zeile je Muster, in einfachen
# Anführungszeichen, keine Zeilenumbrüche.
#
# ---------------------------------------------------------------------------
# WICHTIG für Änderungen: Die Ausdrücke müssen von BEIDEN Regex-Motoren
# verstanden werden. Bash kann weniger als Python — deshalb hier nur
# Konstrukte benutzen, die beide kennen:
#     erlaubt:  ^ $ . * + ? [] [^] () | {n,m} \( \) \[ \]
#     NICHT:    (?:...) \d \s \S \b  und  [[:space:]]
# Statt [[:space:]] also " " schreiben, statt \S besser [^ ].
# ---------------------------------------------------------------------------
#
# Eine Server-Logzeile sieht so aus:
#   [12:34:56] [Server thread/INFO]: Steve joined the game
#
# Gruppen (in dieser Reihenfolge, damit beide Auswertungen sie gleich
# verstehen):
#   1 = Uhrzeit    2 = Spielername    3 = Zusatz    4 = Grund
#
# AUSNAHME: BEITRITT und VERLASSEN — dort steht der Name in Gruppe 3.
# Seit Paper 26.3 (am 21.10.2026 auf dem Pi gefunden) sehen genau diese
# zwei Zeilen so aus:
#   [13:21:03] [Server thread/INFO]: System chat: Steve joined the game
# Die anderen ("lost connection", "logged in", "UUID of player") kommen
# weiterhin ohne Vorsatz. Eine Woche lang fanden die alten Muster deshalb
# keinen einzigen Beitritt: 0 Spieler in der Oberflaeche, keine Sitzung in
# der Historie, keine Vorwarnung vor einem Neustart — und keine Meldung.
# Der Vorsatz ist optional, damit aeltere Logs (Nachtrag!) weiter passen.
# Und er braucht eine eigene Gruppe, weil Bash kein "(?:...)" kennt; darum
# rueckt der Name eine Stelle weiter. Wer ein Muster nutzt, nimmt fuer diese
# beiden ${BASH_REMATCH[3]} bzw. groups()[2]. Geprueft: make muster.

# Der Server meldet die eindeutige Spieler-ID beim Anmelden.
MUSTER_UUID='^\[([^]]+)\] \[[^]]*\]: UUID of player ([A-Za-z0-9_]{1,16}) is ([0-9a-fA-F-]+)$'

# Spieler ist der Welt beigetreten. Gruppe 2 = "System chat: " oder leer,
# Gruppe 3 = Name (siehe oben).
MUSTER_BEITRITT='^\[([^]]+)\] \[[^]]*\]: (System chat: )?([A-Za-z0-9_]{1,16}) joined the game$'

# Verbindung verloren (Spiel beendet, Netzproblem, ...). Gruppe 3 = Grund.
MUSTER_VERBINDUNG_WEG='^\[([^]]+)\] \[[^]]*\]: ([A-Za-z0-9_]{1,16}) lost connection: (.*)$'

# Spieler hat das Spiel regulär verlassen. Gruppe 3 = Name, wie beim Beitritt.
MUSTER_VERLASSEN='^\[([^]]+)\] \[[^]]*\]: (System chat: )?([A-Za-z0-9_]{1,16}) left the game$'

# Verbindung vom Server abgelehnt (z. B. nicht auf der Whitelist).
# Gruppe 3 = Adresse, Gruppe 4 = Begründung.
MUSTER_ABGELEHNT='^\[([^]]+)\] \[[^]]*\]: Disconnecting ([A-Za-z0-9_]{1,16}) \(([^)]*)\): (.*)$'

# Anmeldung mit Adresse. Bis Paper 26.2 kam sie vor "joined the game",
# seit 26.3 danach: Wer die beiden Zeilen paart, darf sich auf keine
# Reihenfolge verlassen.
MUSTER_ANMELDUNG='^\[([^]]+)\] \[[^]]*\]: ([A-Za-z0-9_]{1,16})\[/([^]]*)\] logged in with entity id'

# Ein Spieler hat einen Serverbefehl abgesetzt. Gruppe 3 = der Befehl.
MUSTER_BEFEHL='^\[([^]]+)\] \[[^]]*\]: ([A-Za-z0-9_]{1,16}) issued server command: (.*)$'
