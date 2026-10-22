# shellcheck shell=bash
# (Keine Shebang: Diese Datei wird eingebunden, nicht ausgeführt. Die
#  Direktive darüber sagt shellcheck trotzdem, welche Shell gemeint ist.)
# lib/hardware.sh — Was für ein Gerät ist das hier eigentlich?
#
# Eingebunden von install.sh (vor den Fragen des Assistenten) und von
# tools/mcs (Befehl `mcs hardware`).
#
# ----------------------------------------------------------------------------
# Warum das eine eigene Datei ist
# ----------------------------------------------------------------------------
# Das Lastenheft (5.1) verlangt: "Alles ermitteln, nichts annehmen." Bis
# 2026-08-30 nahm die Installation genau zwei Dinge an — den Arbeitsspeicher
# las sie, alles andere nicht. Damit blieb die wichtigste Frage überhaupt
# unbeantwortet:
#
#     Liegt der Server auf einer SD-Karte?
#
# Eine SD-Karte ist die häufigste Ursache für einen ruckelnden Minecraft-Server
# UND für tote Karten. Minecraft schreibt dauernd kleine Blöcke; SD-Karten
# haben dafür weder die Schreibrate noch die Lebensdauer. Wer das erst nach
# drei Monaten merkt, hat dann eine unlesbare Karte mit der Welt darauf.
#
# Eine deutliche Warnung an dieser Stelle ist mehr wert als jede JVM-Option.
#
# ----------------------------------------------------------------------------
# Drei Fallen, bei denen das Naheliegende falsch ist
# ----------------------------------------------------------------------------
# 1. "rotational=0 heißt SSD" — stimmt nur ohne USB dazwischen. Viele
#    USB-SATA-Brücken reichen die Angabe nicht durch und melden pauschal
#    "1". Eine SSD im USB-Gehäuse (auf dem Pi der Normalfall) sähe damit aus
#    wie eine Festplatte. Deshalb wird über USB NICHT behauptet, was
#    dahintersteckt.
#
# 2. "mmcblk heißt SD-Karte" — auf Compute-Modulen ist derselbe Gerätename
#    der fest verlötete eMMC-Speicher, und der ist deutlich besser als eine
#    SD-Karte. Unterschieden wird über /sys/block/<gerät>/device/type.
#
# 3. "Das Gerät der Partition ist das Gerät der Platte" — /dev/nvme0n1p2 ist
#    eine Partition; die Angaben unter /sys/block stehen am Elterngerät
#    nvme0n1. Wer p2 nachschlägt, findet nichts und meldet "unbekannt".
# ----------------------------------------------------------------------------


# ----------------------------------------------------------------------------
# Prüfbarkeit: woher die Angaben über den Datenträger kommen
# ----------------------------------------------------------------------------
# Die Einordnung eines Datenträgers ist der Teil, bei dem am meisten schiefgehen
# kann — und ausgerechnet der lässt sich auf dem Entwicklungsrechner und im
# Container nicht auslösen: Dort gibt es weder /sys/block noch echte Geräte.
#
# Deshalb steht der Pfad zu /sys in einer Variablen. Der Abnahmetest legt sich
# einen Nachbau an (tests/abnahme-im-container.sh) und prüft damit alle Fälle:
# SD-Karte, eMMC, NVMe, SSD, USB. Im Betrieb bleibt es bei /sys, und niemand
# muss die Variable kennen.
HARDWARE_SYS="${HARDWARE_SYS:-/sys}"

# ----------------------------------------------------------------------------
# Pi-Modell
# ----------------------------------------------------------------------------
# /proc/device-tree/model enthält den Klartextnamen, den der Bootloader
# hinterlegt, z. B. "Raspberry Pi 5 Model B Rev 1.0". Die Datei endet auf
# ein Nullbyte — deshalb "tr -d '\0'", sonst hängt es in jeder Ausgabe mit
# drin und verwirrt später beim Vergleichen.
hardware_modell() {
  if [ -r /proc/device-tree/model ]; then
    tr -d '\0' < /proc/device-tree/model
  elif [ -r /sys/firmware/devicetree/base/model ]; then
    tr -d '\0' < /sys/firmware/devicetree/base/model
  else
    echo ""
  fi
}

# Welche Pi-Generation? Gibt eine Zahl zurück, mit der sich rechnen lässt:
#   5, 4, 3, 2, 1   die jeweilige Generation
#   0               Pi Zero (jeder Art)
#   -1              kein Raspberry Pi (oder nicht feststellbar)
#
# Compute-Module zählen wie ihre Generation: Ein CM5 ist leistungsmäßig ein
# Pi 5. "Raspberry Pi Compute Module 4" enthält aber auch die Ziffer 4 an
# anderer Stelle — deshalb wird auf das erste Zahlwort nach "Pi" bzw. nach
# "Compute Module" geschaut und nicht blind die erste Ziffer genommen.
hardware_pi_generation() {
  local MODELL; MODELL="$(hardware_modell)"
  case "$MODELL" in
    "") echo "-1"; return ;;
    *"Raspberry Pi"*) : ;;
    *) echo "-1"; return ;;
  esac
  case "$MODELL" in
    *Zero*)              echo "0" ;;
    *"Compute Module 5"*) echo "5" ;;
    *"Compute Module 4"*) echo "4" ;;
    *"Compute Module 3"*) echo "3" ;;
    *"Pi 5"*)            echo "5" ;;
    # "Pi 400" MUSS vor "Pi 4" stehen: Das Muster *"Pi 4"* trifft auch auf
    # "Pi 400" zu, und in einem case gewinnt der erste Treffer. Andersherum
    # waere der 400er-Zweig toter Code (von shellcheck gefunden, SC2222).
    # Am Ergebnis aendert es hier nichts — an der Lesbarkeit schon, und beim
    # naechsten Modell mit aehnlichem Namen auch am Ergebnis.
    *"Pi 400"*)          echo "4" ;;
    *"Pi 4"*)            echo "4" ;;
    *"Pi 3"*)            echo "3" ;;
    *"Pi 2"*)            echo "2" ;;
    *"Pi Model"*)        echo "1" ;;
    *)                   echo "-1" ;;
  esac
}

# 64 oder 32. Ein 32-Bit-System kann pro Prozess nicht mehr als knapp 3 GB
# adressieren — der Heap ist dort gedeckelt, egal wie viel RAM verbaut ist.
#
# Gefragt wird das USERLAND (getconf LONG_BIT), nicht der Kernel (uname -m).
# Das 32-Bit-Raspberry-Pi-OS startet auf Pi 4 und 5 seit 2023 von Haus aus
# einen 64-Bit-Kernel: uname meldet dort "aarch64", Java ist aber ein
# 32-Bit-Prozess. Bis zum 23.09.2026 fehlte die Warnung genau in diesem,
# dem häufigsten 32-Bit-Fall. uname bleibt nur der Rückfall ohne getconf.
hardware_bits() {
  case "$(getconf LONG_BIT 2>/dev/null)" in
    64) echo "64"; return ;;
    32) echo "32"; return ;;
  esac
  case "$(uname -m 2>/dev/null)" in
    aarch64|arm64|x86_64) echo "64" ;;
    *)                    echo "32" ;;
  esac
}

# Arbeitsspeicher in GB, kaufmännisch gerundet.
#
# Kaufmännisch statt abschneiden: MemTotal meldet auf einem 8-GB-Pi rund
# 7,88 GB (der Rest ist für Hardware reserviert). Abschneiden ergäbe "7 GB"
# — was den Nutzer verwirrt und die Heap-Empfehlung unnötig senkt.
hardware_ram_gb() {
  local KB
  KB=$(awk '/MemTotal/ {print $2}' /proc/meminfo 2>/dev/null || echo 0)
  echo $(( (KB + 524288) / 1048576 ))
}


# ----------------------------------------------------------------------------
# hardware_medium PFAD — auf welcher Art Datenträger liegt dieser Pfad?
# ----------------------------------------------------------------------------
# Zwei Schritte, bewusst getrennt:
#
#   1. hardware_medium            findet zum PFAD das Blockgerät
#   2. hardware_medium_einordnen  ordnet ein Blockgerät ein
#
# Getrennt, weil nur Schritt 1 echte Geräte braucht und damit auf keinem
# Entwicklungsrechner läuft. Schritt 2 — der Teil mit den drei Fallen — ist
# so für sich prüfbar (siehe HARDWARE_SYS weiter oben).
#
# Beide setzen dieselben vier Variablen (kein Rückgabewert, weil es vier
# Angaben sind):
#
#   MEDIUM_ART       nvme | ssd | hdd | usb | sd | emmc | unbekannt
#   MEDIUM_GERAET    z. B. nvme0n1  (leer, wenn nicht ermittelbar)
#   MEDIUM_TEXT      eine Zeile Klartext für die Anzeige
#   MEDIUM_WARNUNG   leer, oder der Grund zur Sorge
#
# "usb" ist bewusst eine eigene Art und nicht in ssd/hdd einsortiert:
# siehe Falle 1 im Kopf dieser Datei.
hardware_medium() {
  local PFAD="${1:-/}"
  MEDIUM_ART="unbekannt"; MEDIUM_GERAET=""; MEDIUM_WARNUNG=""
  MEDIUM_TEXT="nicht feststellbar"

  # Der Pfad muss existieren — bei einer frischen Installation gibt es das
  # Zielverzeichnis noch nicht. Dann wird das nächste vorhandene
  # Elternverzeichnis geprüft; es liegt auf demselben Dateisystem, sobald
  # das Verzeichnis darin angelegt wird.
  while [ ! -e "$PFAD" ] && [ "$PFAD" != "/" ]; do
    PFAD="$(dirname "$PFAD")"
  done

  # Zu welchem Gerät gehört der Pfad? findmnt ist der genaue Weg (es kennt
  # Einhängepunkte), df der Rückfallweg für Systeme ohne util-linux.
  # Die "|| true" sind hier nicht Zierde: install.sh laeuft mit
  # "set -Eeuo pipefail". Eine Pipe, in der ein Glied fehlschlaegt — etwa
  # weil lsblk oder findmnt gar nicht installiert ist —, laesst dort die
  # ganze Installation abbrechen, mit einer Meldung, die auf die
  # Hardware-Erkennung zeigt statt auf das fehlende Programm. Ein nicht
  # ermittelbarer Datentraeger ist aber kein Grund abzubrechen; er ist eine
  # Auskunft, die eben "unbekannt" lautet.
  local QUELLE=""
  if command -v findmnt >/dev/null 2>&1; then
    QUELLE=$(findmnt -no SOURCE --target "$PFAD" 2>/dev/null | head -n1 || true)
  fi
  if [ -z "$QUELLE" ]; then
    QUELLE=$(df -P "$PFAD" 2>/dev/null | awk 'NR==2 {print $1}' || true)
  fi

  hardware_medium_einordnen "$QUELLE"
}


# hardware_medium_einordnen /dev/mmcblk0p2 — was für ein Ding ist das?
hardware_medium_einordnen() {
  local QUELLE="${1:-}"
  MEDIUM_ART="unbekannt"; MEDIUM_GERAET=""; MEDIUM_WARNUNG=""
  MEDIUM_TEXT="nicht feststellbar"

  # Kein Blockgerät? Das ist der Normalfall in einem Container (overlay),
  # bei tmpfs und bei Netzlaufwerken. Ehrlich melden statt raten.
  case "$QUELLE" in
    /dev/*) : ;;
    "")     MEDIUM_TEXT="nicht feststellbar (kein Gerät ermittelt)"; return 0 ;;
    *)      MEDIUM_TEXT="kein Blockgerät ($QUELLE) — z. B. Container, Netzlaufwerk oder tmpfs"
            return 0 ;;
  esac

  local NAME BASIS
  NAME="$(basename "$QUELLE")"
  # Vom Partitionsgerät zum Elterngerät (Falle 3). lsblk kennt den
  # Zusammenhang; ohne lsblk bleibt die Namensform.
  BASIS=$(lsblk -no pkname "$QUELLE" 2>/dev/null | head -n1 || true)
  if [ -z "$BASIS" ]; then
    case "$NAME" in
      nvme*p[0-9]*)   BASIS="${NAME%p[0-9]*}" ;;
      mmcblk*p[0-9]*) BASIS="${NAME%p[0-9]*}" ;;
      sd[a-z][0-9]*)  BASIS="${NAME%%[0-9]*}" ;;
      *)              BASIS="$NAME" ;;
    esac
  fi
  MEDIUM_GERAET="$BASIS"

  # Hängt das Gerät am USB-Bus? Der Pfad unter <sys>/block ist ein Symlink
  # in den Gerätebaum; kommt "/usb" darin vor, führt der Weg über USB.
  local USB=false GERAETEPFAD
  GERAETEPFAD=$(readlink -f "$HARDWARE_SYS/block/$BASIS" 2>/dev/null || echo "")
  case "$GERAETEPFAD" in *"/usb"*) USB=true ;; esac

  case "$BASIS" in
    nvme*)
      MEDIUM_ART="nvme"
      MEDIUM_TEXT="NVMe-SSD ($BASIS) — die beste Wahl für einen Minecraft-Server"
      ;;
    mmcblk*)
      # Falle 2: SD-Karte oder eMMC?
      local TYP; TYP=$(cat "$HARDWARE_SYS/block/$BASIS/device/type" 2>/dev/null || echo "")
      if [ "$TYP" = "MMC" ]; then
        MEDIUM_ART="emmc"
        MEDIUM_TEXT="eMMC-Speicher ($BASIS) — fest verbaut, deutlich besser als eine SD-Karte"
      else
        MEDIUM_ART="sd"
        MEDIUM_TEXT="SD-Karte ($BASIS)"
        MEDIUM_WARNUNG="SD-Karte"
      fi
      ;;
    sd*)
      if [ "$USB" = true ]; then
        MEDIUM_ART="usb"
        # Bewusst keine Aussage über SSD oder Festplatte (Falle 1).
        MEDIUM_TEXT="USB-Datenträger ($BASIS) — über USB lässt sich nicht sicher sagen, ob SSD oder Festplatte"
      else
        local ROT; ROT=$(cat "$HARDWARE_SYS/block/$BASIS/queue/rotational" 2>/dev/null || echo "")
        if [ "$ROT" = "0" ]; then
          MEDIUM_ART="ssd"
          MEDIUM_TEXT="SSD ($BASIS)"
        elif [ "$ROT" = "1" ]; then
          MEDIUM_ART="hdd"
          MEDIUM_TEXT="Festplatte mit Scheiben ($BASIS)"
          MEDIUM_WARNUNG="Festplatte"
        else
          MEDIUM_TEXT="Datenträger $BASIS (Art nicht feststellbar)"
        fi
      fi
      ;;
    *)
      MEDIUM_TEXT="Datenträger $BASIS (Art nicht feststellbar)"
      ;;
  esac
  return 0
}


# ----------------------------------------------------------------------------
# hardware_bericht [SERVERPFAD] [BACKUPPFAD] — der Block, den der Nutzer sieht
# ----------------------------------------------------------------------------
# Gibt Klartext aus. Farben kommen aus lib/assistent.sh, falls die geladen
# ist — `mcs hardware` bindet sie nicht ein, deshalb die Rückfallwerte.
#
# Setzt außerdem HARDWARE_BEDENKEN auf true, wenn etwas dabei war, das der
# Nutzer gesehen haben sollte, bevor er weitermacht. install.sh hält daran
# an dieser Stelle kurz an.
# HARDWARE_BEDENKEN wird vom Aufrufer gelesen (install.sh haelt daran an),
# nicht in dieser Datei. shellcheck kann das nicht sehen — es kennt immer nur
# eine Datei — und meldete es deshalb als ungenutzt.
# shellcheck disable=SC2034
hardware_bericht() {
  local SERVERPFAD="${1:-$PWD}" BACKUPPFAD="${2:-}"
  local GELB="${F_GELB:-}" AUS="${F_AUS:-}" LEISE="${F_LEISE:-}" TITEL="${F_TITEL:-}"
  HARDWARE_BEDENKEN=false

  local MODELL GENERATION BITS RAM
  MODELL="$(hardware_modell)"
  GENERATION="$(hardware_pi_generation)"
  BITS="$(hardware_bits)"
  RAM="$(hardware_ram_gb)"

  printf '  %sGerät%s\n' "$TITEL" "$AUS"
  if [ -n "$MODELL" ]; then
    printf '    Modell:         %s\n' "$MODELL"
  else
    printf '    Modell:         %snicht feststellbar (kein Raspberry Pi?)%s\n' "$LEISE" "$AUS"
  fi
  printf '    System:         %s-Bit (%s)\n' "$BITS" "$(uname -m 2>/dev/null || echo '?')"
  printf '    Arbeitsspeicher: %s GB\n' "$RAM"

  # --- Speichermedium: der wichtigste Punkt --------------------------------
  hardware_medium "$SERVERPFAD"
  local SERVER_ART="$MEDIUM_ART" SERVER_WARNUNG="$MEDIUM_WARNUNG"
  printf '    Server liegt auf: %s\n' "$MEDIUM_TEXT"

  # Das Backup nur erwähnen, wenn es auf einem ANDEREN Datenträger liegt —
  # sonst steht zweimal dasselbe da. Genau dieser Fall ist aber der
  # interessante: Backups auf einem zweiten Datenträger sind der Sinn der
  # Sache (Lastenheft 5.4).
  if [ -n "$BACKUPPFAD" ]; then
    local SERVER_GERAET="$MEDIUM_GERAET"
    hardware_medium "$BACKUPPFAD"
    if [ "$MEDIUM_GERAET" != "$SERVER_GERAET" ]; then
      printf '    Backups liegen auf: %s\n' "$MEDIUM_TEXT"
    fi
  fi
  printf '\n'

  # --- Was daraus folgt ----------------------------------------------------
  if [ "$SERVER_WARNUNG" = "SD-Karte" ]; then
    HARDWARE_BEDENKEN=true
    printf '  %s!! Der Server soll auf einer SD-Karte laufen.%s\n' "$GELB" "$AUS"
    printf '\n'
    printf '     Das ist die häufigste Ursache für einen ruckelnden Server — und\n'
    printf '     für tote Karten. Minecraft schreibt ununterbrochen kleine Blöcke;\n'
    printf '     SD-Karten haben dafür weder die Schreibrate noch die Lebensdauer.\n'
    printf '     Erfahrungsgemäß fällt beides zusammen auf: Der Server wird\n'
    printf '     langsamer, und irgendwann ist die Karte nicht mehr lesbar — mit\n'
    printf '     der Welt darauf.\n'
    printf '\n'
    printf '     Was hilft: eine SSD. Am Pi 5 über NVMe (HAT), sonst über USB 3.\n'
    printf '     Das bringt mehr als jede Einstellung in diesem Assistenten.\n'
    printf '\n'
    printf '     Es geht trotzdem weiter — aber die Backups sollten dann\n'
    printf '     unbedingt auf einen zweiten Datenträger (MCS_EXTERN_DIR).\n'
    printf '\n'
  elif [ "$SERVER_WARNUNG" = "Festplatte" ]; then
    HARDWARE_BEDENKEN=true
    printf '  %s!  Der Server soll auf einer Festplatte mit Scheiben laufen.%s\n' "$GELB" "$AUS"
    printf '     Das hält lange, ist aber bei vielen kleinen Zugriffen langsam —\n'
    printf '     und genau die macht Minecraft. Eine SSD wäre spürbar besser.\n'
    printf '\n'
  elif [ "$SERVER_ART" = "sd" ] || [ "$SERVER_ART" = "unbekannt" ]; then
    :
  fi

  if [ "$BITS" = "32" ]; then
    HARDWARE_BEDENKEN=true
    printf '  %s!! Dieses System läuft im 32-Bit-Modus.%s\n' "$GELB" "$AUS"
    printf '     Ein 32-Bit-Prozess kann nicht mehr als knapp 3 GB Arbeitsspeicher\n'
    printf '     benutzen — der Heap ist damit gedeckelt, egal wie viel RAM\n'
    printf '     verbaut ist. Raspberry Pi OS gibt es seit Jahren in 64 Bit;\n'
    printf '     ein Wechsel bedeutet aber eine Neuinstallation des Systems.\n'
    printf '\n'
  fi

  case "$GENERATION" in
    5) : ;;   # Alles gut. Die Messungen von 2026-07-27 gelten für dieses Gerät.
    4)
      printf '  %sHinweis: Raspberry Pi 4.%s\n' "$LEISE" "$AUS"
      printf '     Ein Minecraft-Server läuft darauf gut, aber nicht so gut wie auf\n'
      printf '     einem Pi 5. Der Assistent schlägt deshalb eine kleinere Sichtweite\n'
      printf '     und Simulationsweite vor.\n'
      printf '     %sDiese Zahlen sind aus dem Leistungsunterschied abgeleitet, nicht%s\n' "$LEISE" "$AUS"
      printf '     %sauf einem Pi 4 nachgemessen. Wer es besser weiß, hebt sie an.%s\n' "$LEISE" "$AUS"
      printf '\n'
      ;;
    3|2|1|0)
      HARDWARE_BEDENKEN=true
      printf '  %s!! Dieses Gerät ist für einen Minecraft-Server zu schwach.%s\n' "$GELB" "$AUS"
      printf '     Ein Pi 3 oder Zero hat weder die Rechenleistung noch den\n'
      printf '     Arbeitsspeicher dafür. Der Server startet, aber schon ein\n'
      printf '     einzelner Spieler in unerforschtem Gebiet lässt ihn stehen.\n'
      printf '     Empfehlung: Pi 5, notfalls Pi 4 mit mindestens 4 GB.\n'
      printf '\n'
      printf '     Es geht trotzdem weiter, wenn du willst.\n'
      printf '\n'
      ;;
    *)
      if [ -z "$MODELL" ]; then
        printf '  %sHinweis: Das hier scheint kein Raspberry Pi zu sein. Pi-MCS läuft%s\n' "$LEISE" "$AUS"
        printf '  %sauch anderswo, die Empfehlungen sind aber auf einen Pi 5 gemessen.%s\n' "$LEISE" "$AUS"
        printf '\n'
      fi
      ;;
  esac

  if [ "$RAM" -lt 4 ] && [ "$RAM" -gt 0 ]; then
    HARDWARE_BEDENKEN=true
    printf '  %s!  Nur %s GB Arbeitsspeicher.%s\n' "$GELB" "$RAM" "$AUS"
    printf '     Das reicht für wenige Spieler und kleine Sichtweiten. Der Heap\n'
    printf '     wird entsprechend klein vorgeschlagen.\n'
    printf '\n'
  fi
}
