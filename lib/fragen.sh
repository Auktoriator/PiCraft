# shellcheck shell=bash
# (Keine Shebang: Diese Datei wird eingebunden, nicht ausgeführt. Die
#  Direktive darüber sagt shellcheck trotzdem, welche Shell gemeint ist.)
# lib/fragen.sh — Die Fragen des Installationsassistenten.
#
# Getrennt von lib/assistent.sh: dort stehen die Bausteine (wie gefragt wird),
# hier der Inhalt (was gefragt wird). So bleibt beides überschaubar, und wer
# eine Frage ergänzen will, muss die Darstellung nicht anfassen.
#
# Aufgerufen aus install.sh. Setzt Variablen, die dort weiterverwendet und in
# mcs.conf / server.properties geschrieben werden.
#
# Die Empfehlungen sind keine Geschmackssache, sondern das Ergebnis der
# Messungen vom 2026-07-27 auf einem Pi 5 (siehe docs/optimierung-2026-07-27.md).

ASSISTENT_SCHRITTE=6


# ----------------------------------------------------------------------------
# Wie viel Arbeitsspeicher hat dieses Gerät wirklich?
# ----------------------------------------------------------------------------
# Gemessen wird in lib/hardware.sh — hier steht nur, was daraus folgt.
#
# Bis 2026-08-30 stand die Messung an zwei Stellen: hier und (noch nicht) in
# der Hardware-Erkennung. Zwei Fassungen derselben Rechnung sind der sichere
# Weg zu zwei verschiedenen Antworten, sobald jemand eine davon anfasst.
#
# Daraus leitet sich die Empfehlung für den Heap ab.
#
# Die Regel ist NICHT "die Hälfte des RAM", sondern rund drei Achtel — das
# ist das Ergebnis der Messung vom 2026-07-27 (docs/optimierung-2026-07-27.md):
# Auf einem 8-GB-Pi wurde der Heap dort von 4 G auf 3 G gesenkt, weil das
# Live-Set nach der Speicherbereinigung ohnehin nur bei 0,7–1,3 GB lag,
# während dem übrigen System unter Last nur noch ~1,4 GB statt der
# geforderten 2 GB blieben.
#
# "Die Hälfte" stand hier bis 2026-08-26 und hätte auf genau diesem Gerät
# 4 GB vorgeschlagen — also den Wert, den die eigene Messung verworfen hat.
# Aufgefallen ist das erst, als eine Rundungskorrektur aus "7 GB" wieder
# "8 GB" machte.
#
# Mehr Heap macht einen Minecraft-Server ohnehin nicht schneller; er
# verlängert nur die Pausen der Speicherbereinigung.
# Gemessen wird in lib/hardware.sh (hardware_ram_gb).

# ----------------------------------------------------------------------------
# Sichtweite und Simulationsweite: was schlagen wir vor?
# ----------------------------------------------------------------------------
# Der Pi 5 ist nachgemessen (docs/optimierung-2026-07-27.md): Sichtweite 16
# bei Simulationsweite 10 ist dort unbedenklich. Diese Zahlen bleiben.
#
# Für den Pi 4 gibt es keine Messung, und der Leitsatz "Leistungsänderungen
# nur mit Messung" gilt. Er verbietet aber nicht, für ein ANDERES Gerät
# vorsichtiger zu sein — er verbietet, gemessene Werte ohne Messung zu
# ändern. Also: kleinere Vorschläge für den Pi 4, und ausdrücklich dazu
# gesagt, dass sie abgeleitet und nicht gemessen sind (siehe
# hardware_bericht). Die teure Zahl ist die Simulationsweite; sie geht
# quadratisch in die Fläche ein, in der die Welt wirklich rechnet.
#
# Für Pi 3 und Zero gibt es bewusst KEINE eigenen Zahlen. Dort ist nicht die
# Sichtweite das Problem, sondern das Gerät; die Warnung steht in
# hardware_bericht. Wer trotzdem weitermacht, bekommt die Pi-4-Vorschläge.
_sichtweite_empfehlung() {
  case "$(hardware_pi_generation)" in
    5|-1) echo "16" ;;
    *)    echo "10" ;;
  esac
}

_simulationsweite_empfehlung() {
  case "$(hardware_pi_generation)" in
    5|-1) echo "10" ;;
    *)    echo "6" ;;
  esac
}


_heap_empfehlung() {
  local GB; GB=$(hardware_ram_gb)
  # Drei Achtel, kaufmaennisch gerundet: 8 GB -> 3, 4 GB -> 2, 16 GB -> 6.
  local H=$(( (GB * 3 + 4) / 8 ))
  [ "$H" -lt 1 ] && H=1
  [ "$H" -gt 6 ] && H=6
  echo "$H"
}


assistent_fragen_stellen() {
  local RAM_GB HEAP_EMPF SICHT_EMPF SIM_EMPF SICHT_HERKUNFT
  RAM_GB=$(hardware_ram_gb)
  HEAP_EMPF=$(_heap_empfehlung)
  SICHT_EMPF=$(_sichtweite_empfehlung)
  SIM_EMPF=$(_simulationsweite_empfehlung)
  # Woher die Vorschläge kommen, gehört danebengeschrieben: Der eine Satz
  # ist eine Messung, der andere eine Ableitung. Wer das nicht weiß, hält
  # beides für gleich belastbar.
  if [ "$(hardware_pi_generation)" = "5" ]; then
    SICHT_HERKUNFT="Vorgeschlagen sind ${SICHT_EMPF} und ${SIM_EMPF} — auf einem Pi 5 nachgemessen (2026-07-27)."
  else
    SICHT_HERKUNFT="Vorgeschlagen sind ${SICHT_EMPF} und ${SIM_EMPF} — abgeleitet, nicht auf diesem Gerät gemessen."
  fi

  # --- 1: Spielmodus --------------------------------------------------------
  assistent_schritt 1 "$ASSISTENT_SCHRITTE" "Spielmodus"
  assistent_text \
    "Wie soll gespielt werden? Auf einem Pi 5 laufen beide Modi gleich gut —" \
    "das ist eine Geschmacksfrage, keine Leistungsfrage."
  frage_auswahl WAHL_MODUS 1 \
    "survival|Survival|Hunger, Monster, Fortschritt erspielen" \
    "creative|Creative|Fliegen, alle Blöcke, kein Schaden"

  # --- 2: Schwierigkeit -----------------------------------------------------
  assistent_schritt 2 "$ASSISTENT_SCHRITTE" "Schwierigkeit"
  if [ "$WAHL_MODUS" = creative ]; then
    assistent_text "Im Creative-Modus spielt die Schwierigkeit kaum eine Rolle — peaceful passt."
    frage_auswahl WAHL_SCHWIERIGKEIT 1 \
      "peaceful|Friedlich|keine Monster" \
      "easy|Leicht|Monster, wenig Schaden" \
      "normal|Normal|die übliche Einstellung" \
      "hard|Schwer|für Erfahrene"
  else
    assistent_text "Für einen Server mit Freunden ist \"Leicht\" ein guter Anfang."
    frage_auswahl WAHL_SCHWIERIGKEIT 2 \
      "peaceful|Friedlich|keine Monster" \
      "easy|Leicht|Monster, wenig Schaden" \
      "normal|Normal|die übliche Einstellung" \
      "hard|Schwer|für Erfahrene"
  fi

  # --- 3: Sichtweite und Spielerzahl ---------------------------------------
  #
  # Die beiden Werte gehören zusammen und werden deshalb zusammen gefragt.
  # Bis 2026-08-30 wurde nur die Sichtweite gefragt und die Simulationsweite
  # stillschweigend auf 10 gelassen — den gemessenen Pi-5-Wert. Auf einem
  # schwächeren Gerät war das der teuerste Wert im ganzen Assistenten, und
  # niemand bekam ihn je zu Gesicht.
  assistent_schritt 3 "$ASSISTENT_SCHRITTE" "Sichtweite und Spielerzahl"
  assistent_text \
    "Die Sichtweite bestimmt, wie weit die Spieler blicken können." \
    "Sie kostet Arbeitsspeicher und Netzwerk, aber kaum Rechenzeit." \
    "" \
    "Die Simulationsweite ist der teure Wert: Nur in diesem Umkreis \"lebt\"" \
    "die Welt wirklich — Monster, Redstone, Wachstum. Die Kosten hängen fast" \
    "ausschließlich an dieser zweiten Zahl." \
    "" \
    "${SICHT_HERKUNFT}"
  frage_zahl WAHL_SICHTWEITE "$SICHT_EMPF" 4 32 "Sichtweite in Chunks"
  frage_zahl WAHL_SIMULATION "$SIM_EMPF" 3 16 "Simulationsweite in Chunks"
  frage_zahl WAHL_MAXSPIELER 5 1 50 "Wie viele Spieler höchstens gleichzeitig"

  assistent_text \
    "Die Welt bekommt einen Ordnernamen. Er lässt sich später nicht mehr" \
    "einfach ändern — alle Sicherungen und Skripte lesen ihn aus" \
    "server.properties. \"world\" ist der übliche Name."
  # Der Weltname wird ein VERZEICHNISNAME. Ein "/" darin legte Dateien an
  # einer ganz anderen Stelle ab, ein Leerzeichen bricht die Skripte, und
  # ".." zeigte aus dem Serververzeichnis heraus. Deshalb wird hier
  # eingegrenzt statt darauf zu hoffen, dass niemand so etwas eingibt.
  while true; do
    frage_text WAHL_WELTNAME "world" "Name der Welt"
    [ -z "$WAHL_WELTNAME" ] && WAHL_WELTNAME="world"
    if [[ "$WAHL_WELTNAME" =~ ^[A-Za-z0-9._-]+$ ]] && [ "$WAHL_WELTNAME" != "." ] \
       && [ "$WAHL_WELTNAME" != ".." ]; then
      break
    fi
    [ "$ASSISTENT_STANDARD" = true ] && { WAHL_WELTNAME="world"; break; }
    printf '    %sNur Buchstaben, Ziffern, Punkt, Bindestrich und Unterstrich —%s\n' \
      "$F_GELB" "$F_AUS"
    printf '    %ses wird ein Verzeichnisname.%s\n' "$F_GELB" "$F_AUS"
  done

  # --- 4: Netzwerk und Zugang ----------------------------------------------
  assistent_schritt 4 "$ASSISTENT_SCHRITTE" "Netzwerk und Zugang"
  assistent_text \
    "Der Standardport von Minecraft ist 25565. Ein anderer Port ist" \
    "praktisch, wenn schon ein Server läuft — er ist aber kein Schutz:" \
    "Portscanner finden ihn trotzdem."
  frage_zahl WAHL_PORT 25565 1024 65535 "Port"

  assistent_text \
    "Die Whitelist ist die wirksamste Schutzmaßnahme überhaupt: Nur wer" \
    "ausdrücklich eingeladen wurde, kommt auf den Server. Alle anderen" \
    "werden abgewiesen — auch wenn sie die Adresse kennen." \
    "" \
    "Freischalten später mit:  mcs cmd \"whitelist add SPIELERNAME\""
  frage_ja_nein WAHL_WHITELIST j "Whitelist aktivieren (dringend empfohlen)?"

  if [ "$WAHL_WHITELIST" = false ]; then
    assistent_text \
      "${F_GELB}Hinweis:${F_AUS} Ohne Whitelist kann jeder beitreten, der die Adresse kennt." \
      "Das lässt sich jederzeit ändern: mcs cmd \"whitelist on\""
  fi

  assistent_text \
    "Die Firewall (ufw) sperrt alles, was nicht ausdrücklich erlaubt ist." \
    "Wird sie hier eingerichtet, bleiben SSH und der Minecraft-Port offen."
  frage_ja_nein WAHL_FIREWALL j "Firewall einrichten?"

  # Automatische Sicherheitsupdates. Steht hier und nicht unter "Zubehör",
  # weil es zur selben Frage gehört wie die Firewall: Was schützt diesen
  # Rechner, wenn er aus dem Internet erreichbar ist?
  assistent_text \
    "Ein Server, der aus dem Internet erreichbar ist, sollte seine" \
    "Sicherheitsupdates bekommen — auch dann, wenn monatelang niemand" \
    "daran denkt. Genau das macht \"unattended-upgrades\": Es holt sich" \
    "nachts die Sicherheitsaktualisierungen von Debian und spielt sie ein." \
    "" \
    "${F_LEISE}Neu gestartet wird dabei NICHT.${F_AUS} Ein Server, der sich um sechs Uhr" \
    "früh selbst neu startet, während jemand baut, wäre schlimmer als ein" \
    "Kernel-Update, das eine Woche wartet. Ist ein Neustart nötig, sagt" \
    "es die Startseite der Weboberfläche — entschieden wird von Hand."
  frage_ja_nein WAHL_UPDATES j "Automatische Sicherheitsupdates einrichten?"

  # --- 5: Betrieb -----------------------------------------------------------
  assistent_schritt 5 "$ASSISTENT_SCHRITTE" "Speicher und Backups"
  assistent_text \
    "Dieses Gerät hat ${RAM_GB} GB Arbeitsspeicher." \
    "" \
    "Mehr Heap macht einen Minecraft-Server NICHT schneller — er verlängert" \
    "nur die Pausen der Speicherbereinigung. Der Rest ist beim Betriebssystem" \
    "als Dateicache besser aufgehoben. Empfohlen sind daher ${HEAP_EMPF} GB."
  frage_zahl WAHL_HEAP "$HEAP_EMPF" 1 "$(( RAM_GB > 1 ? RAM_GB - 1 : 1 ))" "Arbeitsspeicher für Minecraft in GB"

  assistent_text \
    "Jede Nacht wird die Welt gesichert, geprüft und alte Sicherungen werden" \
    "rotiert. Die Uhrzeit sollte in einer Zeit liegen, in der niemand spielt."
  frage_zahl WAHL_BACKUP_STUNDE 4 0 23 "Uhrzeit des nächtlichen Backups (volle Stunde)"

  assistent_text \
    "Backups liegen sonst auf derselben Platte wie die Welt — geht die kaputt," \
    "ist beides weg. Ein zweiter Datenträger behebt das. Pfad angeben oder" \
    "mit \"-\" überspringen (lässt sich später in mcs.conf nachtragen)."
  frage_text WAHL_EXTERN "" "Zweiter Ablageort für Backups"

  # --- 6: Zubehör -----------------------------------------------------------
  assistent_schritt 6 "$ASSISTENT_SCHRITTE" "Zubehör"
  assistent_text \
    "Die Weboberfläche zeigt Zustand, Spieler und Protokolle und kann den" \
    "Server starten oder stoppen — vom Handy aus." \
    "" \
    "${F_GELB}Wichtig:${F_AUS} Wer ihr Passwort kennt, kann über die Konsole praktisch" \
    "alles auf diesem Gerät tun. Nur im Heimnetz betreiben, nie ins Internet."
  frage_ja_nein WAHL_ADMIN j "Weboberfläche installieren?"

  # Das Passwort der Oberfläche (Lastenheft 5.1, Entscheidung 10).
  #
  # Bis 2026-08-30 wurde es nur erzeugt und am Ende angezeigt. Das ist ein
  # gutes Passwort — aber Entscheidung 10 begründet den Klartext in der
  # .env ausdrücklich mit der NACHSCHLAGBARKEIT, und wer sich eines merken
  # will, muss es auch setzen dürfen.
  #
  # Die Eingabetaste erzeugt weiterhin ein zufälliges. Der Hinweis darunter
  # ist der aus Entscheidung 10 und gehört zwingend dazu: Das Passwort
  # steht im Klartext auf der Platte.
  if [ "$WAHL_ADMIN" = true ]; then
    assistent_text \
      "Das Passwort für die Weboberfläche steht anschließend im ${F_GELB}Klartext${F_AUS}" \
      "in ~/mcs/admin/.env (nur für dich lesbar, chmod 600). Das ist so" \
      "entschieden, damit man es nachschlagen kann." \
      "" \
      "${F_GELB}Deshalb:${F_AUS} ein eigenes Passwort, das du nirgendwo sonst benutzt." \
      "Wer die Datei lesen kann, liest es im Klartext." \
      "" \
      "Eingabetaste = ein zufälliges mit 20 Zeichen wird erzeugt und" \
      "am Ende angezeigt."
    while true; do
      frage_text WAHL_ADMIN_PASSWORT "" "Passwort (leer = zufällig)"
      # Zu kurz ist schlimmer als zufällig: Die Oberfläche kann den Server
      # stoppen und Konfiguration ändern.
      #
      # Und ohne Zeichen, die einer der DREI Leser der .env veraendert:
      # systemd (EnvironmentFile=) nimmt Anfuehrungszeichen und Backslashes
      # ab und schneidet Leerzeichen am Ende weg, die Shell (`mcs status`
      # bindet die .env mit "." ein) zerlegt an Leerzeichen und fuehrt $(…)
      # aus. Am 23.09.2026 gemessen: aus 'ab\cd' wurde "abcd", aus
      # '"quoted"pass' wurde "quotedpass" — das gewaehlte Passwort passte
      # danach nicht mehr, und niemand haette gesagt, warum.
      case "$WAHL_ADMIN_PASSWORT" in
        *[[:space:]\;\&\|\<\>\(\)\'\"\$\`\\~]*)
          [ "$ASSISTENT_STANDARD" = true ] && { WAHL_ADMIN_PASSWORT=""; break; }
          printf '    %sBitte ohne Leerzeichen und ohne diese Zeichen:%s\n' \
            "$F_GELB" "$F_AUS"
          printf '    %s; & | < > ( ) \x27 " $ ` \\ ~%s\n' "$F_GELB" "$F_AUS"
          continue ;;
      esac
      if [ -z "$WAHL_ADMIN_PASSWORT" ] || [ "${#WAHL_ADMIN_PASSWORT}" -ge 12 ]; then
        break
      fi
      [ "$ASSISTENT_STANDARD" = true ] && { WAHL_ADMIN_PASSWORT=""; break; }
      printf '    %sMindestens zwölf Zeichen — oder leer lassen für ein%s\n' \
        "$F_GELB" "$F_AUS"
      printf '    %szufälliges.%s\n' "$F_GELB" "$F_AUS"
    done
  fi

  # Hier stand bis 2026-08-30 "Vier erprobte Plugins ... WorldEdit,
  # WorldGuard, GSit". Seit Korrektur K6 (28.08.2026) wird nur noch Pl3xMap
  # mitinstalliert; die anderen drei stehen in plugins.txt.beispiel als
  # auskommentierter Vorschlag. Der Assistent versprach also drei Plugins,
  # die anschließend nicht da waren — aufgefallen ist das niemandem, weil
  # niemand nachgezählt hat.
  assistent_text \
    "Mitinstalliert wird genau ein Plugin, mit Prüfsumme in" \
    "server/plugins.txt.beispiel, damit auf jedem Gerät dasselbe ankommt:" \
    "" \
    "  Pl3xMap      Live-Karte der Welt im Browser" \
    "" \
    "WorldEdit, WorldGuard und Chunky stehen dort als Vorschlag bereit" \
    "und lassen sich später über die Weboberfläche nachinstallieren."
  frage_ja_nein WAHL_PLUGINS j "Pl3xMap installieren?"

  # ---------------------------------------------------------------------------
  # Vorsichtsmodus: kein Terminal, also niemand, der zustimmen könnte
  # ---------------------------------------------------------------------------
  # Gesetzt, wenn install.sh ohne Terminal läuft und --standard NICHT
  # ausdrücklich angegeben wurde. Dann wird der Server eingerichtet, aber
  # nichts am übrigen System angefasst — eine Firewall, die ungefragt alles
  # zumacht, kann auf einem Homeserver andere Dienste aussperren.
  # Ein ausdruecklicher Aufrufparameter schlaegt jede Antwort — auch die
  # Empfehlung im Schnellmodus. Genau dafuer gibt es ihn.
  if [ "${OHNE_OBERFLAECHE:-false}" = true ]; then
    WAHL_ADMIN=false
  fi

  if [ "${ASSISTENT_VORSICHTIG:-false}" = true ]; then
    WAHL_FIREWALL=false
    WAHL_ADMIN=false
    # Auch das gehört hierher: unattended-upgrades installiert ein Paket und
    # schreibt nach /etc/apt. Das ist ein Eingriff ins übrige System, und
    # niemand ist da, der zustimmen könnte.
    WAHL_UPDATES=false
  fi
}


# Die getroffenen Entscheidungen für die Zusammenfassung aufbereiten.
assistent_auswahl_anzeigen() {
  local WL FW AD PL EX UP
  [ "$WAHL_WHITELIST" = true ] && WL='an' || WL='aus'
  [ "$WAHL_FIREWALL"  = true ] && FW='wird eingerichtet' || FW='unverändert'
  [ "$WAHL_UPDATES"   = true ] && UP='ja, ohne Neustart' || UP='nein'
  if [ "$WAHL_ADMIN" = true ]; then
    [ -n "${WAHL_ADMIN_PASSWORT:-}" ] && AD='ja, mit eigenem Passwort' || AD='ja, Passwort wird erzeugt'
  else
    AD='nein'
  fi
  [ "$WAHL_PLUGINS"   = true ] && PL='ja' || PL='nein'
  EX="${WAHL_EXTERN:-keiner}"

  assistent_zusammenfassung \
    "Spielmodus"        "$WAHL_MODUS, $WAHL_SCHWIERIGKEIT" \
    "Welt"              "$WAHL_WELTNAME" \
    "Sichtweite"        "$WAHL_SICHTWEITE Chunks" \
    "Simulationsweite"  "$WAHL_SIMULATION Chunks" \
    "Spieler höchstens" "$WAHL_MAXSPIELER" \
    "Port"              "$WAHL_PORT" \
    "Whitelist"         "$WL" \
    "Firewall"          "$FW" \
    "Sicherheitsupdates" "$UP" \
    "Arbeitsspeicher"   "${WAHL_HEAP} GB" \
    "Backup"            "täglich $(printf '%02d' "$WAHL_BACKUP_STUNDE"):00 Uhr" \
    "Zweiter Ablageort" "$EX" \
    "Weboberfläche"     "$AD" \
    "Plugins"           "$PL" \
    "Zielverzeichnis"   "$MC_DIR"
}
