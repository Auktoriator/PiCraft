# shellcheck shell=bash
# (Keine Shebang: Diese Datei wird eingebunden, nicht ausgeführt. Die
#  Direktive darüber sagt shellcheck trotzdem, welche Shell gemeint ist.)
# lib-konsole.sh — Der einzige Ort, an dem PiCraft mit der Server-Konsole redet.
#
# Diese Datei wird nicht ausgeführt, sondern eingebunden:
#
#     . "$(dirname "$0")/lib-konsole.sh"
#
# ----------------------------------------------------------------------------
# Warum gibt es sie?
# ----------------------------------------------------------------------------
# Bis 2026-08-26 stand derselbe Zweizeiler in vier Dateien — im Stopp-Skript,
# im Backup, im mcs-Kommando und (als Python) in der Weboberfläche. Vier
# Kopien, und sie waren NICHT gleich:
#
#   tools/mcs             escapte Rückwärtsschrägstriche
#   admin/app.py       escapte Rückwärtsschrägstriche
#   stop-minecraft.sh     escapte NICHT
#   minecraft-backup.sh   escapte NICHT
#
# Folgenlos war das nur, weil die letzten beiden ausschließlich feste Wörter
# senden ("stop", "save-off", "save-all"). Wer dort je einen variablen Text
# einsetzt, baut sich eine Falle: Ein Rückwärtsschrägstrich im Text wird von
# screen als Steuerzeichen gelesen, "\r" mitten in einer Nachricht entspricht
# einem Druck auf die Eingabetaste — alles danach landet als eigener
# Serverbefehl auf der Konsole.
#
# Jetzt gibt es die Logik genau einmal, mit Escaping für alle.
#
# ----------------------------------------------------------------------------
# Der zweite Grund: Austauschbarkeit
# ----------------------------------------------------------------------------
# Ob die Konsole über screen läuft oder eines Tages über RCON, geht den Rest
# des Projekts nichts an. Alle anderen Dateien kennen nur noch diese vier
# Funktionen:
#
#   konsole_laeuft            läuft der Server?
#   konsole_senden ZEILE      eine Zeile an die Konsole schicken
#   konsole_anhaengen         interaktiv hineinschauen (nur mcs console)
#   konsole_abraeumen         übriggebliebene Sitzung entfernen
#
# Ein Wechsel auf RCON wäre damit eine Änderung an DIESER Datei statt an
# sieben. Solange kein Grund dafür besteht, bleibt es bei screen: Es ist
# erprobt, kostet 3,5 MB und braucht kein Passwort in server.properties.
#
# ----------------------------------------------------------------------------
# Eine Einschränkung, damit die Überschrift nicht lügt
# ----------------------------------------------------------------------------
# "Der einzige Ort" gilt für die Shell-Seite. Die Weboberfläche ist Python
# und kann diese Datei nicht einbinden — sie hat in **admin/konsole.py** eine
# eigene Fassung (send_to_minecraft_console, fuer_screen_escapen und
# sanitize_console_input).
#
# Bis zum 2026-08-31 stand hier "admin/app.py". Das stimmte einmal, war aber
# seit der Aufteilung von app.py am 2026-08-28 falsch — ausgerechnet in der
# Datei, die als maßgeblich gilt, und ausgerechnet der Verweis, dem folgen
# soll, wer beide Fassungen gleichziehen will.
#
# Es sind also ZWEI Stellen, nicht eine. Wer hier etwas am Protokoll ändert
# — anderer Sitzungsname, anderes Escaping, Wechsel auf RCON —, muss dort
# nachziehen. Beide Fassungen escapen Rückwärtsschrägstriche (seit
# 2026-08-26), entfernen Zeilenumbrüche (die Shell-Seite seit
# 2026-08-31) und escapen ^ und $ (seit 2026-09-23).
# ----------------------------------------------------------------------------

# Name der Sitzung. Kommt aus mcs.conf; der Standard steht hier, damit die
# Bibliothek auch ohne Konfiguration benutzbar bleibt.
KONSOLE_SITZUNG="${MCS_SCREEN_SESSION:-minecraft_server}"


# Läuft der Server? Prüft, ob eine LEBENDE Sitzung existiert.
#
# Das Muster "[.]NAME<Leerzeichen>" ist Absicht: screen listet Sitzungen als
# "PID.NAME (Datum)". Ohne die eckigen Klammern fände grep sich selbst in der
# Prozessliste, und ohne das abschließende Leerzeichen würde eine Sitzung
# namens "minecraft_server_alt" fälschlich mitzählen.
#
# Und "(Dead" muss weg, sonst zählt eine Leiche als laufender Server:
# Stirbt Java hart, bleibt der Sockel der Sitzung als
# "1370.minecraft_server (Dead ???)" in `screen -ls` stehen. `Restart=always`
# fängt den Absturz auf und startet daneben eine ZWEITE, lebende Sitzung
# gleichen Namens — ab da ist die Liste zweideutig.
#
# Am 29.08.2026 auf dem Pi durchgemessen (P-B, Absturztest). Die alte
# Fassung suchte nur nach dem Namen, und das kostete dreimal:
#   * `mcs stop` wartete die vollen 240 s auf einen Server, der nach
#     5 Sekunden weg war,
#   * warnte danach "Die Welt wurde möglicherweise nicht vollständig
#     gespeichert" — sie war sauber gespeichert, im Log nachlesbar,
#   * und `mcs restore` verweigerte sich mit "Der Server läuft noch".
# Das Zurückspielen war also ausgerechnet nach einem Absturz gesperrt —
# in dem Fall, für den es die Backups gibt.
konsole_laeuft() {
  screen -ls 2>/dev/null \
    | grep "[.]${KONSOLE_SITZUNG}[[:space:]]" \
    | grep -qv "(Dead"
}


# Eine Zeile an die Server-Konsole schicken.
#
# Das \r am Ende entspricht der Eingabetaste. Der Rückgabewert wird
# weitergereicht: Kommt der Befehl nicht an, hat es keinen Zweck,
# anschließend minutenlang auf eine Wirkung zu warten.
#
# VIER Dinge werden entschärft, und alle sind nötig (^ und $ seit dem
# 23.09.2026, begründet direkt an ihren Zeilen unten):
#
#   Rückwärtsschrägstriche  screen deutet sie in "stuff" als Steuerzeichen.
#                           Ein "\r" mitten im Text wäre ein Druck auf die
#                           Eingabetaste, und alles danach ein eigener Befehl.
#
#   Zeilenumbrüche          Bis zum 2026-08-31 wurden sie durchgereicht — ein
#                           echtes LF im Argument wirkt in "stuff" genauso wie
#                           die Eingabetaste. `mcs cmd "$(printf 'say hi\nop
#                           Jemand')"` schickte also zwei Befehle, von denen
#                           der zweite nirgends stand. Die Python-Fassung
#                           sichert genau das seit jeher ab
#                           (sanitize_console_input in admin/konsole.py); die
#                           Shell-Seite war die schwächere der beiden — und
#                           das in der Datei, deren ganzer Zweck es ist, dass
#                           es nur eine Fassung gibt.
#
#   ^ und $                 "^M" ist für screen ein Wagenrücklauf, "$VAR"
#                           wird aus der Umgebung des Dienstes eingesetzt —
#                           samt Geheimnissen.
konsole_senden() {
  local ZEILE="$1"
  ZEILE="${ZEILE//$'\r'/ }"
  ZEILE="${ZEILE//$'\n'/ }"
  ZEILE="${ZEILE//\\/\\\\}"
  # Und "^": screen liest "^M" als Wagenruecklauf, "^_" als Steuerzeichen.
  # Am 23.09.2026 an einer Wegwerf-Sitzung gemessen: "say hallo^Mstop"
  # kam als ZWEI Zeilen an, die zweite davon "stop". "\^" ist das woertliche
  # Zeichen. NACH den Rueckwaertsschraegstrichen, sonst wuerde dieser eine
  # gleich mitverdoppelt.
  ZEILE="${ZEILE//^/\\^}"
  # Und "$": screen setzt $VAR und ${VAR} aus der Umgebung der SITZUNG ein.
  # Das ist die Umgebung des Minecraft-Dienstes, und dort stehen Geheimnisse
  # (etwa ein API-Schluessel aus einem Drop-in). "say ${…}" schickte ihn an
  # alle Spieler; aus "Preis $5" wurde "Preis " (23.09.2026, Wegwerf-Sitzung).
  ZEILE="${ZEILE//\$/\\\$}"
  screen -S "$KONSOLE_SITZUNG" -p 0 -X stuff "${ZEILE}\r"
}


# Interaktiv in die laufende Konsole schauen (Verlassen: Strg+A, dann D).
# Ersetzt den aufrufenden Prozess, kehrt also nicht zurück.
konsole_anhaengen() {
  exec screen -x "$KONSOLE_SITZUNG"
}


# Eine übriggebliebene Sitzung entfernen. Schlägt das fehl, ist das kein
# Fehler — dann war schon keine mehr da, und genau das war das Ziel.
#
# Zwei Wege, weil es zwei Zustände gibt: `-X quit` beendet eine LEBENDE
# Sitzung. Eine tote lässt sich nicht mehr beenden — sie ist schon tot, und
# `-X quit` antwortet "No screen session found" mit Rückgabewert 1. Genau
# das ließ am 29.08.2026 den Dienst nach jedem Absturz in `failed` laufen,
# obwohl der Stopp in Ordnung war. Für den liegengebliebenen Sockel ist
# `screen -wipe` zuständig; mit Namen dahinter räumt es nur die eigene
# Sitzung ab und nicht die fremden Leichen anderer Programme.
konsole_abraeumen() {
  screen -S "$KONSOLE_SITZUNG" -X quit 2>/dev/null || true
  screen -wipe "$KONSOLE_SITZUNG" >/dev/null 2>&1 || true
}


# Der Startbefehl. Steht hier, damit auch die Startseite der Konsole an
# einer Stelle definiert ist:
#   -D -m  Sitzung starten und im Vordergrund bleiben (kein Verdoppeln des
#          Prozesses). systemd sieht den Server dadurch direkt und merkt
#          sofort, wenn er abstürzt — ganz ohne PID-Dateien.
#   -S     Name der Sitzung.
konsole_starten() {
  exec screen -DmS "$KONSOLE_SITZUNG" "$@"
}
