#!/bin/bash
#
# usb-kopie.sh — Legt das neueste Backup auf einen USB-Stick.
#
# Wozu: Welt, Backups und Dauerarchiv liegen auf DERSELBEN SSD. Ein Stick,
# den man einsteckt und wieder abzieht, ist die einfachste Kopie, die den
# Ausfall dieser SSD überlebt — und man öffnet sie ohne jedes Werkzeug: Auf
# dem Stick liegen dieselben tar.gz-Dateien wie im Backup-Ordner.
#
# Erkannt wird der Stick an seinem NAMEN (Dateisystem-Label), Standard
# "MCS-BACKUP", nicht an "irgendein Stick". Wer einen Stick mit Urlaubsfotos
# einsteckt, soll darauf keine 750 MB Minecraft finden — und schon gar nicht
# erleben, dass dafür Platz geschaffen wurde. Gelöscht wird ohnehin nur, was
# dieses Skript selbst angelegt hat (backup_*.tar.gz im Ordner PiCraft-Backups).
#
# Ausgelöst wird es auf zwei Wegen:
#   - beim Einstecken (99-picraft-usb.rules → mcs-usb-kopie.service)
#   - nach jedem gelungenen Backup (mcs-usb-kopie.path), falls der Stick
#     dauerhaft steckt. Steckt keiner, endet es sofort und still.
#
# Die grüne LED (ACT) sagt, wann der Stick abgezogen werden darf:
#   blinkt im Herzschlag   kopiert gerade — NICHT abziehen
#   leuchtet dauerhaft     fertig, geprüft und ausgehängt — darf raus
#   blinkt schnell         Fehler, der Grund steht in "mcs usb"
# Nach dem Abziehen kehrt sie in ihren Normalzustand zurück. Ohne diese
# Anzeige wüsste an einem Pi ohne Bildschirm niemand, wann die Kopie fertig
# ist — und ein Stick, der mitten im Schreiben gezogen wird, hält nichts.
#
# ZWEI TEILE, zwei Benutzer. Einhängen, Aushängen und die LED darf nur root.
# Alles, was mit den Dateien geschieht, läuft dagegen als Benutzer des
# Servers (setpriv, Abschnitt 2b). Der Grund ist nicht Stil: Die Backups
# liegen in einem Ordner, den dieser Benutzer beschreiben kann. Läse root
# dort, genügte ein Symlink "backup_x.tar.gz -> /etc/shadow", und root trüge
# die Datei auf den Stick. Dienste laufen in diesem Projekt nie als root
# (CLAUDE.md, Sicherheit) — der root-Teil hier ist so klein wie möglich und
# fasst keine einzige Datei des Benutzers an.
#
# Aus demselben Grund liegt das Skript NICHT im Backup-Ordner wie die
# anderen, sondern unter /usr/local/lib/picraft/, wo der Benutzer es nicht
# ändern kann. Und die mcs.conf, die dem Benutzer gehört, bekommt der
# root-Teil weder per "." noch per EnvironmentFile= zu sehen: Beides gäbe
# dem Benutzer die Umgebung eines root-Prozesses in die Hand — BASH_ENV,
# LD_PRELOAD, MCS_USER=root. Der root-Teil liest stattdessen genau drei
# Schlüssel und prüft jeden gegen ein Muster (Abschnitt 0 unten). Gefunden
# am 22.10.2026 von einer Sicherheitsprüfung des ersten Entwurfs, der noch
# EnvironmentFile= benutzte.
#
# Aufrufe:
#   usb-kopie.sh                   als root: Stick suchen, einhängen, kopieren
#   usb-kopie.sh --verzeichnis D   nur der Datei-Teil, ohne Einhängen (Tests)
#   usb-kopie.sh --led-normal      nur die LED zurückstellen (beim Abziehen)
# Von Hand: "mcs usb jetzt", Zustand: "mcs usb".

set -euo pipefail

ORDNER_NAME="PiCraft-Backups"

# ============================================================================
# DATEI-TEIL — läuft als Benutzer des Servers
# ============================================================================
# Kopiert das neueste Backup nach $1/PiCraft-Backups, prüft es und räumt auf.
# Die letzte Zeile der Ausgabe ist das Ergebnis; der root-Teil übernimmt sie
# in den Stand.
#
# Die beiden Werte kommen aus der Umgebung: vom root-Teil, der sie geprüft
# hat, oder vom Test. Dieser Teil läuft mit den Rechten des Benutzers, er
# darf also lesen, was der Benutzer ohnehin lesen darf.
dateien_kopieren() {
  local PUNKT="$1" ZIEL_DIR NEUESTES BASIS GROESSE BRAUCHT FREI AELTESTES ROH ALT ANZAHL GLEICH
  local BACKUP_DIR="${MCS_BACKUP_DIR:-}" BEHALTEN="${MCS_USB_BEHALTEN:-3}"

  # Wie viele Backups auf dem Stick bleiben. Eine unbrauchbare Angabe gilt
  # als Standard, nicht als "alles löschen" (Befund 23.09.2026, siehe
  # tests/pruefung-backup.sh). Mindestens eines — sonst wäre der Stick leer.
  case "$BEHALTEN" in
    ''|*[!0-9]*) BEHALTEN=3 ;;
  esac
  [ "$BEHALTEN" -ge 1 ] || BEHALTEN=1

  if [ -z "$BACKUP_DIR" ]; then
    echo "Kein Backup-Ordner angegeben (MCS_BACKUP_DIR)."
    return 1
  fi

  # Nur fertige, geprüfte Archive: Der Zwischenname ".unfertig-backup_*"
  # passt nicht auf dieses Muster (minecraft-backup.sh, Abschnitt 5b).
  # "-type f" lässt Symlinks aus, aus dem Grund im Kopf dieser Datei.
  # "|| true": Ist der Ordner nicht lesbar, endet find mit 1, und unter
  # pipefail beendete die Zuweisung das Skript OHNE Meldung. Die Prüfung
  # darunter sagt dann, was los ist.
  NEUESTES=$(find "$BACKUP_DIR" -maxdepth 1 -type f -name 'backup_*.tar.gz' -printf '%T@ %p\n' 2>/dev/null \
             | sort -rn | head -n1 | cut -d' ' -f2-) || true
  if [ -z "$NEUESTES" ]; then
    echo "Im Backup-Ordner $BACKUP_DIR liegt kein lesbares Backup."
    return 1
  fi
  BASIS=$(basename "$NEUESTES")
  GROESSE=$(stat -c %s "$NEUESTES")

  ZIEL_DIR="$PUNKT/$ORDNER_NAME"
  if ! mkdir -p "$ZIEL_DIR"; then
    echo "Auf dem Stick lässt sich kein Ordner anlegen (schreibgeschützt?)."
    return 1
  fi

  # Reste eines abgebrochenen Laufs, etwa weil der Stick zu früh gezogen
  # wurde. Hier ohne Frist: Der Ordner gehört diesem Skript allein.
  find "$ZIEL_DIR" -maxdepth 1 -name '.unfertig-backup_*.tar.gz' -delete 2>/dev/null || true

  if [ -f "$ZIEL_DIR/$BASIS" ] && [ "$(stat -c %s "$ZIEL_DIR/$BASIS")" = "$GROESSE" ]; then
    echo "$BASIS liegt schon auf dem Stick."
  else
    # Platz schaffen, ältestes zuerst. Nach dem NAMEN sortiert, nicht nach
    # Änderungszeit: FAT speichert sie nur auf zwei Sekunden genau und in
    # Ortszeit, der Name trägt den Zeitstempel verlässlich. 16 MB Reserve
    # für die Verwaltungsdaten des Dateisystems.
    BRAUCHT=$((GROESSE + 16 * 1024 * 1024))
    while :; do
      FREI=$(df --output=avail -B1 "$ZIEL_DIR" | tail -n1 | tr -d ' ')
      [ "$FREI" -lt "$BRAUCHT" ] || break
      AELTESTES=$(find "$ZIEL_DIR" -maxdepth 1 -name 'backup_*.tar.gz' -printf '%f\n' | sort | head -n1)
      if [ -z "$AELTESTES" ]; then
        echo "Auf dem Stick ist zu wenig Platz: gebraucht $((BRAUCHT / 1024 / 1024)) MB, frei $((FREI / 1024 / 1024)) MB. Fremde Dateien werden nicht angefasst."
        return 1
      fi
      rm -f "$ZIEL_DIR/$AELTESTES"
      echo "Platz geschaffen: $AELTESTES gelöscht."
    done

    # Unter einem Zwischennamen, aus demselben Grund wie im Backup-Skript:
    # Wird der Stick mittendrin gezogen, darf nichts liegen bleiben, das wie
    # ein gültiges Backup aussieht.
    ROH="$ZIEL_DIR/.unfertig-$BASIS"
    echo "Kopiere $BASIS ($((GROESSE / 1024 / 1024)) MB) auf den Stick..."
    # --preserve=timestamps statt -a: FAT kennt weder Besitzer noch Rechte,
    # und "cp -a" bricht dort mit "preserving permissions" ab.
    if ! nice -n 15 ionice -c3 cp --preserve=timestamps "$NEUESTES" "$ROH"; then
      rm -f "$ROH"
      echo "Kopieren auf den Stick fehlgeschlagen (voll, gezogen oder defekt?)."
      return 1
    fi
    sync "$ROH" 2>/dev/null || sync

    # Prüfen heißt: VOM STICK lesen. Direkt nach dem Schreiben liegt die
    # ganze Datei noch im Arbeitsspeicher, und ein gewöhnlicher Vergleich
    # läse nur den — er bestünde auch an einem Stick, der nichts behalten
    # hat. "iflag=direct" geht am Zwischenspeicher vorbei; am 22.10.2026 an
    # exFAT und FAT32 gemessen, beide können es. Wo nicht, bleibt die
    # zweitbeste Bitte an den Kern, die Seiten zu verwerfen.
    #
    # cmp statt "tar -t": Gleich mit einem geprüften Backup heißt brauchbar
    # — und der Vergleich fängt auch Sticks, die mehr Speicher vorgeben, als
    # sie haben. Die schreiben klaglos und liefern beim Lesen etwas anderes.
    if dd if="$ROH" iflag=direct bs=4M count=0 status=none 2>/dev/null; then
      nice -n 15 ionice -c3 dd if="$ROH" iflag=direct bs=4M status=none | cmp -s "$NEUESTES" - \
        && GLEICH=true || GLEICH=false
    else
      dd if="$ROH" iflag=nocache count=0 status=none 2>/dev/null || true
      nice -n 15 ionice -c3 cmp -s "$NEUESTES" "$ROH" && GLEICH=true || GLEICH=false
    fi
    if [ "$GLEICH" != true ]; then
      rm -f "$ROH"
      echo "Die Kopie auf dem Stick weicht vom Backup ab und wurde verworfen. Der Stick ist womöglich defekt."
      return 1
    fi
    if ! mv "$ROH" "$ZIEL_DIR/$BASIS"; then
      echo "Die geprüfte Kopie ließ sich nicht umbenennen."
      return 1
    fi
    echo "Geprüft: $BASIS ist identisch mit dem Backup."
  fi

  # Aufräumen: die neuesten $BEHALTEN bleiben.
  while IFS= read -r ALT; do
    rm -f "$ZIEL_DIR/$ALT" && echo "Alt, gelöscht: $ALT"
  done < <(find "$ZIEL_DIR" -maxdepth 1 -name 'backup_*.tar.gz' -printf '%f\n' | sort -r \
           | tail -n +"$((BEHALTEN + 1))")

  # Ein Zettel für den, der den Stick in fünf Jahren in einer Schublade findet.
  cat > "$ZIEL_DIR/LIESMICH.txt" <<ENDE
PiCraft — Backups eines Minecraft-Servers
========================================

Jede Datei backup_JJJJ-MM-TT_HH-MM-SS.tar.gz ist ein vollständiger Stand:
die Welt, die Einstellungen, Whitelist, Plugins. Kein Spezialwerkzeug
nötig — am Mac öffnet ein Doppelklick das Archiv.

Zurückspielen auf dem Pi:
  1. Datei nach ~/mcs/mcs_backup/ kopieren
  2. mcs restore --probe DATEINAME    (prüft nur)
  3. mcs restore DATEINAME            (spielt zurück)

ACHTUNG: In jedem Archiv steht das RCON-Passwort des Servers
(server.properties). Den Stick nicht verleihen. Geht er verloren, das
Passwort ändern.

Zuletzt beschrieben: $(date '+%d.%m.%Y %H:%M') — neuestes: $BASIS
Es bleiben die neuesten $BEHALTEN. Andere Dateien auf dem Stick werden nie angefasst.
ENDE
  sync

  FREI=$(df --output=avail -B1 "$ZIEL_DIR" | tail -n1 | tr -d ' ')
  ANZAHL=$(find "$ZIEL_DIR" -maxdepth 1 -name 'backup_*.tar.gz' | wc -l | tr -d ' ')
  echo "$BASIS ist das neueste von $ANZAHL Backup(s) auf dem Stick, $((FREI / 1024 / 1024)) MB frei."
}

if [ "${1:-}" = "--verzeichnis" ]; then
  [ -n "${2:-}" ] || { echo "Aufruf: $0 --verzeichnis ZIEL" >&2; exit 2; }
  dateien_kopieren "$2"
  exit $?
fi

# ============================================================================
# ROOT-TEIL — Stick finden, einhängen, LED, Stand
# ============================================================================
# Ab hier gilt jede Eingabe als verdächtig, die der Benutzer beeinflussen
# kann. Deshalb stehen die Pfade fest im Skript und nicht in der Umgebung,
# und vertraut wird nur zwei Werten der Einheit (die root gehört):
# MCS_USER und MCS_CONF. Beide setzt deploy.sh beim Ausrollen ein.
STAND_DIR="/var/lib/picraft"
STAND="$STAND_DIR/usb-kopie.stand"
EINHAENGEPUNKT="/run/picraft-usb/stick"
# Was die LED vorher anzeigte, und welche LED es war. Bewusst NICHT im
# RuntimeDirectory: Das löscht systemd, sobald der Dienst endet — gebraucht
# wird der Wert aber erst beim Abziehen, lange danach. Die udev-Regel ruft
# "--led-normal" ohne mcs.conf auf und liest beides nur hier.
LED_MERKER="/run/picraft-usb-led.vorher"
LED=""

led() {   # led herzschlag|an|fehler|normal
  local NAME="$LED" VORHER="" PFAD ECHT
  if [ "$1" = normal ]; then
    [ -f "$LED_MERKER" ] || return 0
    read -r NAME VORHER < "$LED_MERKER" || true
  fi

  # Nur ein schlichter Name, und er muss zu einer LED führen. Ohne diese
  # Prüfung schriebe root mit MCS_USB_LED=../../irgendwas an eine beliebige
  # Stelle unter /sys (Sicherheitsprüfung 22.10.2026).
  [[ $NAME =~ ^[A-Za-z0-9_:-]{1,32}$ ]] || return 0
  PFAD="/sys/class/leds/$NAME"
  ECHT=$(realpath -e "$PFAD" 2>/dev/null) || return 0
  case "$ECHT" in /sys/devices/*) ;; *) return 0 ;; esac
  [ -w "$PFAD/trigger" ] || return 0

  if [ "$1" = normal ]; then
    [[ $VORHER =~ ^[A-Za-z0-9_:-]{1,32}$ ]] && echo "$VORHER" > "$PFAD/trigger" 2>/dev/null
    rm -f "$LED_MERKER"
    return 0
  fi

  # Den Normalzustand nur beim ERSTEN Umschalten merken. Sonst merkte sich
  # der zweite Lauf (Stick steckt, nächste Nacht) "dauerhaft an" als normal,
  # und nach dem Abziehen bliebe die LED für immer an.
  if [ ! -f "$LED_MERKER" ]; then
    printf '%s %s\n' "$NAME" "$(sed -n 's/.*\[\([^]]*\)\].*/\1/p' "$PFAD/trigger")" \
      > "$LED_MERKER" 2>/dev/null || true
  fi

  {
    case "$1" in
      herzschlag) echo heartbeat > "$PFAD/trigger" ;;
      an)         echo none > "$PFAD/trigger"
                  cat "$PFAD/max_brightness" > "$PFAD/brightness" ;;
      fehler)     echo timer > "$PFAD/trigger"
                  echo 100 > "$PFAD/delay_on"
                  echo 100 > "$PFAD/delay_off" ;;
    esac
  } 2>/dev/null || true
}

if [ "${1:-}" = "--led-normal" ]; then
  led normal
  exit 0
fi

# Eine Datei mit Schlüssel=Wert, die "mcs usb", "mcs status" und die
# Weboberfläche lesen. Ins Journal geht dieselbe Meldung über stdout.
stand_schreiben() {   # stand_schreiben ok|fehler MELDUNG
  mkdir -p "$STAND_DIR"
  {
    echo "zeit=$(date '+%Y-%m-%d %H:%M:%S')"
    echo "epoch=$(date +%s)"
    echo "ergebnis=$1"
    echo "meldung=$(printf '%s' "$2" | tr -d '\n')"
  } > "$STAND.neu" && mv "$STAND.neu" "$STAND"
}

GERAET=""
EINGEHAENGT=false

aushaengen() {
  [ "$EINGEHAENGT" = true ] || return 0
  sync
  umount "$EINHAENGEPUNKT" 2>/dev/null || umount -l "$EINHAENGEPUNKT" 2>/dev/null || true
  EINGEHAENGT=false
}

fehler() {
  echo "FEHLER: $1" >&2
  stand_schreiben fehler "$1"
  aushaengen
  # Wurde der Stick mitten im Kopieren gezogen, hat die udev-Regel die LED
  # womöglich schon zurückgestellt. Schnelles Blinken hieße dann "Fehler" an
  # einem Pi, an dem gar kein Stick mehr steckt — und zwar bis zum nächsten.
  if [ -n "$GERAET" ] && [ ! -b "$GERAET" ]; then
    led normal
  else
    led fehler
  fi
  exit 1
}

if [ "$(id -u)" -ne 0 ]; then
  echo "Dieser Teil hängt den Stick ein und braucht root. Von Hand: mcs usb jetzt" >&2
  exit 2
fi

# ----------------------------------------------------------------------------
# 0) Die Einstellungen — drei Schlüssel, jeder gegen ein Muster geprüft
# ----------------------------------------------------------------------------
MCS_USER="${MCS_USER:-pi}"
MCS_CONF="${MCS_CONF:-/home/$MCS_USER/mcs/mcs.conf}"

# Liest einen Schlüssel, ohne die Datei auszuführen. Gilt die LETZTE Zeile,
# wie beim Einlesen mit "." in den anderen Skripten. Fehlt der Schlüssel
# oder passt der Wert nicht aufs Muster, gilt der Standard.
conf_lesen() {   # conf_lesen SCHLUESSEL MUSTER STANDARD
  local ZEILE WERT
  ZEILE=$(grep "^$1=" "$MCS_CONF" 2>/dev/null | tail -n1) || ZEILE=""
  if [ -z "$ZEILE" ]; then echo "$3"; return 0; fi
  WERT="${ZEILE#*=}"
  WERT="${WERT//\'/}"
  WERT="${WERT//\"/}"
  if [[ $WERT =~ $2 ]]; then echo "$WERT"; else echo "$3"; fi
}

# Dieselbe Regel für den Namen wie beim Einsetzen in die udev-Regel
# (lib/dateien.sh) — sonst suchte das Skript einen Namen, auf den die Regel
# nie anspringt. Leeres MCS_USB_LED heißt "LED nicht anfassen".
STICK_NAME=$(conf_lesen MCS_USB_NAME '^[A-Za-z0-9._-]{1,32}$' MCS-BACKUP)
BEHALTEN=$(conf_lesen MCS_USB_BEHALTEN '^[0-9]{1,3}$' 3)
LED=$(conf_lesen MCS_USB_LED '^[A-Za-z0-9_:-]{0,32}$' ACT)
# Den Backup-Ordner liest nur der Datei-Teil, mit den Rechten des Benutzers.
# root fasst ihn nicht an; ein Pfad, den der Benutzer einträgt, verschafft
# ihm also nichts, was er nicht schon hat.
BACKUP_DIR=$(conf_lesen MCS_BACKUP_DIR '^/[^[:cntrl:]]*$' "/home/$MCS_USER/mcs/mcs_backup")

UID_SERVER=$(id -u "$MCS_USER" 2>/dev/null) || fehler "Den Benutzer $MCS_USER gibt es nicht (Environment=MCS_USER in der Einheit)."
GID_SERVER=$(id -g "$MCS_USER")
# Nie als root: Dann läse der Datei-Teil doch wieder mit allen Rechten.
[ "$UID_SERVER" -ne 0 ] || fehler "Der Datei-Teil läuft nie als root (MCS_USER=$MCS_USER)."

# ----------------------------------------------------------------------------
# 1) Den Stick finden
# ----------------------------------------------------------------------------
GERAET=$(blkid -L "$STICK_NAME" 2>/dev/null || true)
if [ -z "$GERAET" ]; then
  # Kein Fehler: Nach dem nächtlichen Backup wird jedes Mal nachgesehen, und
  # meistens steckt eben keiner. Den letzten Stand nicht überschreiben —
  # "zuletzt kopiert am ..." soll stehen bleiben.
  echo "Kein Stick mit dem Namen $STICK_NAME angeschlossen — nichts zu tun."
  exit 0
fi

# Nur FAT32 und exFAT. Beide lassen sich so einhängen, dass die Dateien dem
# Benutzer des Servers gehören (uid=, gid=), ohne dass root je eine davon
# anfasst — und beide liest jeder Mac und jeder Windows-Rechner. Ein Stick
# mit ext4 wäre auf dem Pi lesbar, aber genau dort, wo man ihn im Ernstfall
# braucht, an einem anderen Rechner, nicht.
TYP=$(blkid -o value -s TYPE "$GERAET" 2>/dev/null || true)
case "$TYP" in
  vfat|exfat) ;;
  *) fehler "Der Stick $STICK_NAME hat das Dateisystem \"${TYP:-unbekannt}\". Bitte als exFAT formatieren (am Mac: Festplattendienstprogramm → Löschen → ExFAT, Name $STICK_NAME)." ;;
esac

led herzschlag

# ----------------------------------------------------------------------------
# 2) Einhängen — und zwar immer selbst
# ----------------------------------------------------------------------------
# Auch wenn ein Desktop den Stick schon eingehängt hat: Dessen Einhängepunkt
# gehört womöglich einem anderen Benutzer, und "fertig, darf raus" darf die
# LED erst sagen, wenn NIEMAND mehr schreibt. Linux erlaubt dasselbe
# Dateisystem an zwei Stellen; ausgehängt wird nur die eigene.
mkdir -p "$EINHAENGEPUNKT"
mount -t "$TYP" -o "noatime,nodev,nosuid,noexec,uid=$UID_SERVER,gid=$GID_SERVER,umask=022" \
      "$GERAET" "$EINHAENGEPUNKT" \
  || fehler "Der Stick $GERAET ließ sich nicht einhängen."
EINGEHAENGT=true

# ----------------------------------------------------------------------------
# 2b) Der Datei-Teil, als Benutzer des Servers
# ----------------------------------------------------------------------------
# setpriv statt runuser oder su: kein PAM, keine Sitzung, nur der Wechsel der
# Kennung. Die Umgebung wird geleert und nur mit dem gefüllt, was der
# Datei-Teil braucht — geprüft, siehe Abschnitt 0.
set +e
AUSGABE=$(env -i PATH=/usr/sbin:/usr/bin:/sbin:/bin LANG="${LANG:-C.UTF-8}" \
            MCS_BACKUP_DIR="$BACKUP_DIR" MCS_USB_BEHALTEN="$BEHALTEN" \
            setpriv --reuid="$UID_SERVER" --regid="$GID_SERVER" --init-groups \
            /usr/bin/bash "${BASH_SOURCE[0]}" --verzeichnis "$EINHAENGEPUNKT" 2>&1)
STATUS=$?
set -e
printf '%s\n' "$AUSGABE"
LETZTE=$(printf '%s\n' "$AUSGABE" | tail -n1)
[ "$STATUS" -eq 0 ] || fehler "${LETZTE:-Der Kopierteil endete mit Status $STATUS.}"

# ----------------------------------------------------------------------------
# 3) Aushängen, erst dann "fertig"
# ----------------------------------------------------------------------------
sync
umount "$EINHAENGEPUNKT" || fehler "Kopiert und geprüft, aber der Stick ließ sich nicht aushängen. Vor dem Abziehen: mcs usb"
EINGEHAENGT=false

stand_schreiben ok "$LETZTE"
echo "Fertig. Der Stick darf raus."
led an
