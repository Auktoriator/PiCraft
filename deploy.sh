#!/bin/bash
#
# deploy.sh — Bringt Änderungen aus diesem Repository auf den laufenden Server.
#
# Warum ein eigenes Skript neben install.sh? Weil beides bisher dasselbe war.
# Wer eine Skriptänderung ausrollen wollte, musste install.sh erneut laufen
# lassen — und das hat nebenbei Pakete aktualisiert und Serverdateien
# heruntergeladen. Deploy soll aber nur eines tun: Dateien kopieren.
#
# Was dieses Skript anfasst:
#   - die Skripte der Installation (start, stop, update, backup, mcs, ...)
#   - versions.env (gehört dem Repository)
#   - die systemd-Dienstdateien
#
# Was es NIE anfasst:
#   - Weltdaten, logs/, plugins/, ops.json, whitelist.json, banned-*.json
#   - vorhandene Backups
#   - die Konfiguration (server.properties, spigot.yml, bukkit.yml,
#     config/*.yml) — Unterschiede werden nur ANGEZEIGT, übernommen
#     werden sie erst mit --konfig-uebernehmen
#   - mcs.conf. Sie gehört seit 2026-08-28 dem Pi. Im Repository liegt nur
#     die Vorlage mcs.conf.beispiel, und install.sh erzeugt die echte Datei
#     einmalig daraus. Vorher hat dieses Skript die Repo-Fassung darüber
#     kopiert — wer eigene Pfade eingetragen hatte, verlor sie bei jedem
#     Ausrollen.
#   - plugins.txt. Seit 2026-08-28 aus demselben Grund: Die Weboberfläche
#     installiert Plugins und schreibt sie dort hinein. Würde das Repo die
#     Datei weiter überschreiben, wäre jede so installierte Erweiterung
#     beim nächsten Ausrollen wieder aus der Liste. Vorlage:
#     server/plugins.txt.beispiel. Soll und Ist vergleicht "mcs plugins".
#
# Aufruf (als Benutzer pi, aus dem Repo-Verzeichnis):
#   ./deploy.sh                       Skripte ausrollen, Konfig nur vergleichen
#
# Liegt die Installation nicht unter ~/mcs:  MCS_CONF=/pfad/mcs.conf ./deploy.sh
#   ./deploy.sh --konfig-uebernehmen  zusätzlich die Konfiguration übernehmen
#   ./deploy.sh --probe               nichts ändern, nur zeigen was wäre

set -euo pipefail

# ----------------------------------------------------------------------------
# Einstellungen
# ----------------------------------------------------------------------------
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Die Einstellungen kommen vom PI. Im Repository liegt nur die Vorlage.
# Ohne eine installierte mcs.conf kann dieses Skript nichts ausrollen — es
# wüsste nicht, wohin.
MCS_CONF="${MCS_CONF:-${HOME:-/home/$(id -un)}/mcs/mcs.conf}"
# shellcheck source=/dev/null
if [ -f "$MCS_CONF" ]; then
  . "$MCS_CONF"
else
  echo "Fehler: $MCS_CONF nicht gefunden — hier ist PiCraft nicht installiert." >&2
  echo "Erstinstallation:      ./install.sh" >&2
  echo "Anderer Ort:           MCS_CONF=/pfad/zur/mcs.conf ./deploy.sh" >&2
  exit 1
fi

MCS_USER="${MCS_USER:-$(id -un)}"
MC_DIR="${MCS_DIR:-${HOME:-/home/$MCS_USER}/mcs}"
MC_SERVER_DIR="${MCS_SERVER_DIR:-$MC_DIR/mc_server}"
MC_BACKUP_DIR="${MCS_BACKUP_DIR:-$MC_DIR/mcs_backup}"
MC_ADMIN_DIR="${MCS_ADMIN_DIR:-$MC_DIR/admin}"

# Welche Dateien auf den Pi gehoeren — dieselbe Liste, die install.sh benutzt.
# Erst hier eingebunden, weil die Ziele oben stehen muessen; gefuellt wird die
# Liste durch den Aufruf von mcs_dateiliste in Abschnitt 1.
# shellcheck source=lib/dateien.sh
. "$REPO_DIR/lib/dateien.sh"

# Wurde an der Weboberfläche etwas ausgerollt? Dann muss ihr Dienst neu
# starten — sonst läuft die alte Fassung im Speicher weiter, und man sucht
# den Fehler in Dateien, die längst richtig sind.
ADMIN_GEAENDERT=false
# Dasselbe fuer das Spielerprotokoll: mcs-playerlog.service ist ein
# Dauerdienst (tail -F in einer Schleife) und liest sein Skript und die
# Suchmuster nur beim Start. Bis zum 24.09.2026 sagte deploy.sh dazu nichts
# — nach dem Ausrollen von "tail -n 0" lief die alte Fassung weiter, bis
# jemand den Pi neu startete. Ein Fix, der nicht wirkt, und niemand merkt es.
PROTOKOLL_GEAENDERT=false
SERVICE_DIR="/etc/systemd/system"
# Die Backup-Uhrzeit der Installation (seit v1.1, siehe E20). Sie steht
# BEWUSST nicht in der Einheit: Die gehoert der Vorlage und wird hier
# ersetzt. deploy.sh liest dieses Drop-in nur, um zu erkennen, ob es schon
# da ist — geschrieben wird es genau einmal, beim Umstieg.
ZEIT_DROPIN="$SERVICE_DIR/mcs-backup.timer.d/zeit.conf"

KONFIG_UEBERNEHMEN=false
PROBE=false

while [ $# -gt 0 ]; do
  case "$1" in
    --konfig-uebernehmen) KONFIG_UEBERNEHMEN=true ;;
    --probe)              PROBE=true ;;
    -h|--hilfe|--help)
      sed -n '2,28p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *)
      echo "Unbekannter Parameter: $1" >&2
      echo "Erlaubt: --konfig-uebernehmen | --probe" >&2
      exit 1
      ;;
  esac
  shift
done

# ----------------------------------------------------------------------------
# Vorab-Prüfungen
# ----------------------------------------------------------------------------
if [ ! -d "$MC_SERVER_DIR" ]; then
  echo "Fehler: $MC_SERVER_DIR gibt es nicht — hier ist noch nichts installiert." >&2
  echo "Für die Erstinstallation: ./install.sh" >&2
  exit 1
fi

if [ "$(id -un)" != "$MCS_USER" ]; then
  echo "Fehler: Bitte als Benutzer '$MCS_USER' ausführen (ohne sudo davor)." >&2
  exit 1
fi

NEUSTART_NOETIG=false
GEAENDERT=0

# ----------------------------------------------------------------------------
# Abbruch soll nicht wortlos passieren
# ----------------------------------------------------------------------------
# install.sh hat seit jeher bei_fehler + SCHRITT; hier fehlte beides bis zum
# 2026-08-31. Unter "set -e" endete ein Ausrollen dann einfach mitten in der
# Liste — mit der letzten Zeile "~ aktualisiert: ..." als letzter Ausgabe.
# Das sieht aus wie ein Ende, ist aber eines mit halb ausgerollten Dateien:
# genau die Sorte stiller Ausfall, um die es in diesem Projekt geht.
SCHRITT="Start"
bei_fehler() {
  local RC=$?
  echo "" >&2
  echo "================================================================" >&2
  echo " ABBRUCH im Schritt: $SCHRITT (Rückgabewert $RC)" >&2
  echo "================================================================" >&2
  echo "Das Ausrollen ist UNVOLLSTÄNDIG. Die Ursache steht in den Zeilen" >&2
  echo "darüber. Bereits kopierte Dateien bleiben liegen." >&2
  echo "" >&2
  echo "Nach dem Beheben erneut starten:  ./deploy.sh" >&2
  echo "Vorher ansehen, was fehlt:        ./deploy.sh --probe" >&2
  exit "$RC"
}
trap bei_fehler ERR

echo "================================================================"
if [ "$PROBE" = true ]; then
  echo " PiCraft Deploy — PROBELAUF (es wird nichts verändert)"
else
  echo " PiCraft Deploy"
fi
echo " Quelle: $REPO_DIR"
echo " Ziel:   $MC_DIR"
echo "================================================================"

# ----------------------------------------------------------------------------
# Hilfsfunktion: eine Datei ausrollen, wenn sie sich unterscheidet
# ----------------------------------------------------------------------------
# $1 Quelle, $2 Ziel, $3 "neustart" wenn die Änderung erst nach einem
# Server-Neustart wirkt.
ausrollen() {
  local QUELLE="$1" ZIEL="$2" WIRKUNG="${3:-sofort}"

  if [ ! -f "$QUELLE" ]; then
    echo "  ! fehlt im Repo: $QUELLE"
    return 0
  fi

  if [ -f "$ZIEL" ] && cmp -s "$QUELLE" "$ZIEL"; then
    return 0
  fi

  if [ -f "$ZIEL" ]; then
    echo "  ~ aktualisiert: ${ZIEL#"$MC_DIR"/}"
  else
    echo "  + neu:          ${ZIEL#"$MC_DIR"/}"
  fi

  GEAENDERT=$((GEAENDERT + 1))
  [ "$WIRKUNG" = "neustart" ] && NEUSTART_NOETIG=true
  case "$ZIEL" in "$MC_ADMIN_DIR"/*) ADMIN_GEAENDERT=true ;; esac
  case "$ZIEL" in
    "$MC_DIR/log_player_activity.sh"|"$MC_DIR/log-muster.sh") PROTOKOLL_GEAENDERT=true ;;
  esac

  if [ "$PROBE" = false ]; then
    mkdir -p "$(dirname "$ZIEL")"
    cp "$QUELLE" "$ZIEL"
    case "$ZIEL" in *.sh) chmod +x "$ZIEL" ;; esac
  fi
}

# ----------------------------------------------------------------------------
# 1) Skripte und Vorgabedateien
# ----------------------------------------------------------------------------
echo ""
SCHRITT="Skripte und Vorgaben ausrollen"
echo "--- Skripte und Vorgaben ---"

# WELCHE Dateien das sind, steht in lib/dateien.sh — in derselben Liste, aus
# der install.sh eine Erstinstallation bestueckt. Bis zum 2026-09-02 gab es
# hier eine zweite; sie war schon einmal auseinandergelaufen (lib/hardware.sh
# fehlte, "mcs hardware" benutzte auf einer nur ausgerollten Installation
# eine veraltete Fassung).
#
# mcs.conf und plugins.txt sind dort nicht bzw. als "nur-wenn-fehlt"
# eingetragen und werden hier deshalb nie angefasst — siehe Kopfkommentar.
mcs_dateiliste
for EINTRAG in "${MCS_DATEIEN[@]}"; do
  IFS='|' read -r QUELLE ZIEL MODUS <<<"$EINTRAG"
  # Vorlagen gehoeren ab dem ersten Start dem Pi. Ausrollen wuerde
  # ueberschreiben, was die Weboberflaeche dort eingetragen hat.
  if [ "$MODUS" = "nur-wenn-fehlt" ]; then
    continue
  fi
  ausrollen "$QUELLE" "$ZIEL" "$MODUS"
done

# Auf einer Installation von vor Etappe D fehlen die neuen Zeilen in
# mcs.conf. Sie wird hier NICHT ueberschrieben (Befund B2) — aber ein
# fehlender Schluessel bedeutet stumm "aus", und der Nutzer sucht die
# Einstellung dann in einer Datei, in der sie gar nicht steht.
if [ -f "$MCS_CONF" ] && ! grep -q '^MCS_DNS_ANBIETER=' "$MCS_CONF" 2>/dev/null; then
  echo "  ~ mcs.conf: die DNS-Schluessel werden nachgetragen"
  GEAENDERT=$((GEAENDERT + 1))
  if [ "$PROBE" = false ]; then
    {
      echo ""
      echo "# --- Dauerhafter Name im Internet (Etappe D) ---"
      echo "# Leer = aus. Einrichten in der Weboberflaeche unter \"Konfiguration\"."
      echo "# Erlaubt: desec, duckdns. Der Token steht in dns.env (chmod 600)."
      echo "MCS_DNS_ANBIETER="
      echo "MCS_DNS_NAME="
      echo "MCS_DNS_ZONE="
    } >> "$MCS_CONF"
  fi
fi

# Eigener Block, nicht im obigen mitgeführt: Wer die DNS-Schluessel schon hat,
# bekaeme einen spaeter dazugekommenen sonst nie zu sehen — die Bedingung oben
# ist dann laengst falsch. Jeder neue Schluessel braucht deshalb seine eigene
# Abfrage. (Dieselbe Luecke wie bei den systemd-Einheiten, siehe Block 3c.)
if [ -f "$MCS_CONF" ] && ! grep -q '^MCS_DNS_NUR_IPV4=' "$MCS_CONF" 2>/dev/null; then
  echo "  ~ mcs.conf: MCS_DNS_NUR_IPV4 wird nachgetragen"
  GEAENDERT=$((GEAENDERT + 1))
  if [ "$PROBE" = false ]; then
    {
      echo ""
      echo "# Kein AAAA-Eintrag melden, auch bei vorhandener IPv6-Adresse."
      echo "# Auf \"ja\" setzen, wenn der Router eingehendes IPv6 blockt: Ein AAAA"
      echo "# behauptet sonst eine Erreichbarkeit, die es nicht gibt, und Clients"
      echo "# laufen erst in einen Timeout, bevor sie auf IPv4 zurueckfallen."
      echo "MCS_DNS_NUR_IPV4="
    } >> "$MCS_CONF"
  fi
fi

# Spieler-Historie (v1.2). Wieder ein eigener Block, aus demselben Grund:
# Wer die DNS- und ntfy-Schluessel schon hat, bekaeme diese hier sonst nie.
if [ -f "$MCS_CONF" ] && ! grep -q '^MCS_HISTORIE_DB=' "$MCS_CONF" 2>/dev/null; then
  echo "  ~ mcs.conf: MCS_HISTORIE_DB und MCS_HISTORIE_TAGE werden nachgetragen"
  GEAENDERT=$((GEAENDERT + 1))
  if [ "$PROBE" = false ]; then
    MCS_BASIS="$(dirname "$MCS_CONF")"
    {
      echo ""
      echo "# --- Spieler-Historie (v1.2) ---"
      echo "# Wer war wann wie lange online, und was wurde im Chat"
      echo "# geschrieben oder als Befehl abgesetzt. Die Seite \"Historie\""
      echo "# schreibt diesen Index beim Oeffnen fort; den ersten, grossen"
      echo "# Durchlauf nimmt \"python3 tools/historie-aufbauen.py\" ab."
      echo "#"
      echo "# Die Datei enthaelt Chat-Inhalte und Spielernamen und wird"
      echo "# deshalb mit chmod 600 angelegt."
      echo "MCS_HISTORIE_DB=${MCS_BASIS}/admin/historie.db"
      echo ""
      echo "# Aufbewahrung in Tagen. 0 heisst ausdruecklich UNBEGRENZT und"
      echo "# ist die Vorgabe -- Sitzungen sind winzig, und \"wer war im"
      echo "# letzten Sommer da\" ist die Frage, wegen der es die Seite gibt."
      echo "MCS_HISTORIE_TAGE=0"
    } >> "$MCS_CONF"
  fi
fi

if [ -f "$MCS_CONF" ] && ! grep -q '^MCS_NTFY_THEMA=' "$MCS_CONF" 2>/dev/null; then
  echo "  ~ mcs.conf: MCS_NTFY_THEMA und MCS_NTFY_SERVER werden nachgetragen"
  GEAENDERT=$((GEAENDERT + 1))
  if [ "$PROBE" = false ]; then
    {
      echo ""
      echo "# --- Benachrichtigung bei Backup-Fehlschlag (Etappe D) ---"
      echo "# Leer = aus. Einrichten in der Weboberflaeche unter \"Backups\"."
      echo "# ACHTUNG: Bei ntfy.sh ist der Themenname das ganze Geheimnis."
      echo "MCS_NTFY_THEMA="
      echo "MCS_NTFY_SERVER=https://ntfy.sh"
    } >> "$MCS_CONF"
  fi
fi

# Die Weboberfläche nur, wenn sie überhaupt installiert ist.
if [ -d "$MC_ADMIN_DIR" ]; then
  # Alle Python-Module der Oberflaeche. Sie einzeln aufzuzaehlen hiesse, beim
  # naechsten Modul eines zu vergessen.
  for MODUL in "$REPO_DIR"/admin/*.py; do
    ausrollen "$MODUL" "$MC_ADMIN_DIR/$(basename "$MODUL")"
  done

  # Vorlagen und statische Dateien. Seit Etappe C sind es viele, in
  # Unterverzeichnissen — deshalb wird der Baum durchlaufen statt Datei fuer
  # Datei aufgezaehlt. Sonst fehlt nach dem naechsten neuen Reiter genau
  # eine Vorlage, und zwar erst auf dem Pi.
  while IFS= read -r DATEI; do
    REL="${DATEI#"$REPO_DIR"/admin/}"
    ausrollen "$DATEI" "$MC_ADMIN_DIR/$REL"
  done < <(find "$REPO_DIR/admin/templates" "$REPO_DIR/admin/static" -type f 2>/dev/null)

  # Was im Repository geloescht wurde, muss auch auf dem Pi verschwinden.
  # Eine liegengebliebene alte Vorlage waere sonst weiterhin auffindbar —
  # etwa index.html, die es seit Etappe C nicht mehr gibt.
  while IFS= read -r DATEI; do
    REL="${DATEI#"$MC_ADMIN_DIR"/}"
    if [ ! -f "$REPO_DIR/admin/$REL" ]; then
      echo "  - entfernt:     $REL (im Repository nicht mehr vorhanden)"
      GEAENDERT=$((GEAENDERT + 1))
      [ "$PROBE" = false ] && rm -f "$DATEI"
    fi
  done < <(find "$MC_ADMIN_DIR/templates" "$MC_ADMIN_DIR/static" -type f 2>/dev/null)

  # Die Weboberflaeche liest dieselben Suchmuster wie das Spielerlog.
  ausrollen "$REPO_DIR/tools/log-muster.sh"            "$MC_ADMIN_DIR/log-muster.sh"

  # --------------------------------------------------------------------------
  # Was seit Etappe C in der .env stehen muss
  # --------------------------------------------------------------------------
  # Die .env gehört dem Pi: Dort steht das Passwort, und deploy.sh fasst sie
  # nicht an. Ein Wert ist aber neu dazugekommen und wird auf einer
  # bestehenden Installation schlicht fehlen — install-admin.sh legt ihn nur
  # an, wenn es die Datei ERSTMALS schreibt.
  #
  # MCS_ADMIN_SECRET unterschreibt das Anmelde-Cookie. Ohne ihn erzeugt die
  # Oberfläche bei jedem Start einen zufälligen und meldet damit alle ab.
  # Sie sagt das auch — aber ein Wert, den niemand von Hand wählt, gehört
  # nicht in eine Anleitung, sondern hierher.
  ENV_DATEI="$MC_ADMIN_DIR/.env"
  if [ -f "$ENV_DATEI" ] && ! grep -q '^MCS_ADMIN_SECRET=' "$ENV_DATEI"; then
    echo "  + .env: MCS_ADMIN_SECRET fehlt (neu seit Etappe C) — wird erzeugt"
    GEAENDERT=$((GEAENDERT + 1))
    ADMIN_GEAENDERT=true
    if [ "$PROBE" = false ]; then
      # Endliche Menge lesen statt "head -c" hinter tr: Sonst bekommt tr
      # SIGPIPE, und unter "set -o pipefail" scheitert die ganze Zeile.
      # Dieselbe Falle wie in install-admin.sh, dort am 2026-08-28
      # reproduzierbar aufgetreten.
      SCHLUESSEL="$(head -c 512 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9')"
      SCHLUESSEL="${SCHLUESSEL:0:48}"
      if [ "${#SCHLUESSEL}" -ge 48 ]; then
        {
          echo ""
          echo "# Womit das Anmelde-Cookie unterschrieben wird (Etappe C)."
          echo "# Genauso geheim wie das Passwort. Wird er geändert, sind alle"
          echo "# abgemeldet — sonst nichts."
          echo "MCS_ADMIN_SECRET=${SCHLUESSEL}"
        } >> "$ENV_DATEI"
        chmod 600 "$ENV_DATEI"
      else
        echo "  ! Zufallsschlüssel ließ sich nicht erzeugen — bitte von Hand nachtragen."
      fi
    fi
  fi

  # python3-yaml ist seit Etappe C nötig: Der Expertenmodus der Oberfläche
  # prüft damit, ob eine bearbeitete YAML-Datei noch gültig ist. Ohne den
  # Parser kann er nur auf Tabulatoren prüfen — und ein anderer Tippfehler
  # fällt erst auf, wenn der Server nicht mehr startet.
  #
  # Installiert wird hier NICHT: deploy.sh rollt das Repository aus, es
  # verwaltet keine Systempakete. Aber verschweigen wäre schlechter.
  if ! python3 -c 'import yaml' >/dev/null 2>&1; then
    echo "  ! python3-yaml fehlt. Der YAML-Editor der Oberfläche kann dann"
    echo "    nur auf Tabulatoren prüfen. Nachholen mit:"
    echo "      sudo apt-get install -y python3-yaml"
  fi

  # Hier stand bis zum 2026-09-02 ein Aufruf von
  # tools/cpu-altwerte-verwerfen.py: eine einmalige Umstellung, die die als
  # Rauschen entstandenen CPU-Altwerte aus der Verlaufsdatenbank raeumte
  # (v1.1). Sie ist gelaufen und hat sich in der Datenbank vermerkt; ein
  # zweiter Lauf tat ohnehin nichts. Werkzeug und Aufruf sind entfernt.
  # Der Sachverhalt selbst steht im Kopf von admin/metrik.py, wo er
  # hingehoert — eine Migration ist irgendwann fertig, die Erklaerung nicht.
fi

# duckdns.sh gibt es seit Etappe D nicht mehr — es ist in dns-update.sh
# aufgegangen. Eine noch vorhandene alte Fassung auf dem Pi wird NICHT
# angefasst: Wer sie benutzt hat, hat einen Cronjob dafuer, und ein Cronjob
# ohne sein Skript scheitert still. install.sh sagt, was zu tun ist.

# ----------------------------------------------------------------------------
# 2) Was root gehört: das mcs-Kommando, die USB-Kopie und ihre udev-Regel
# ----------------------------------------------------------------------------
# Die Liste steht in lib/dateien.sh (mcs_systemdateien), dieselbe wie in
# install.sh. Eine geänderte udev-Regel gilt erst, wenn udev sie neu liest —
# ohne das reagierte der Pi beim Einstecken weiter auf die alte.
mcs_systemdateien
UDEV_GEAENDERT=false
for EINTRAG in "${MCS_SYSTEMDATEIEN[@]}"; do
  IFS='|' read -r QUELLE ZIEL RECHTE <<<"$EINTRAG"
  if mcs_systemdatei_inhalt "$QUELLE" | cmp -s - "$ZIEL" 2>/dev/null; then
    continue
  fi
  if [ -f "$ZIEL" ]; then echo "  ~ aktualisiert: $ZIEL"; else echo "  + neu:          $ZIEL"; fi
  GEAENDERT=$((GEAENDERT + 1))
  case "$ZIEL" in *.rules) UDEV_GEAENDERT=true ;; esac
  if [ "$PROBE" = false ]; then
    sudo mkdir -p "$(dirname "$ZIEL")"
    mcs_systemdatei_inhalt "$QUELLE" | sudo tee "$ZIEL" >/dev/null
    sudo chmod "$RECHTE" "$ZIEL"
  fi
done
if [ "$UDEV_GEAENDERT" = true ] && [ "$PROBE" = false ]; then
  sudo udevadm control --reload \
    || echo "  ! udev hat die Regel nicht neu gelesen — von Hand: sudo udevadm control --reload"
fi

# ----------------------------------------------------------------------------
# 3) systemd-Dienstdateien
# ----------------------------------------------------------------------------
echo ""
SCHRITT="systemd-Dienste einrichten"
echo "--- systemd-Dienste ---"

DIENSTE_GEAENDERT=false
# Einheiten, die dieser Lauf zum ersten Mal anlegt. Nur sie darf Block 3c
# aktivieren — die Begründung steht dort.
NEUE_EINHEITEN=""
# mcs.target zuerst: Die Dienste darunter verweisen mit "WantedBy=mcs.target"
# darauf. Käme es später, stünde zwischendurch ein Dienst da, dessen Ziel es
# noch gar nicht gibt.
for QUELLE in "$REPO_DIR/server/mcs.target" \
              "$REPO_DIR/server/minecraft.service" \
              "$REPO_DIR/tools/mcs-playerlog.service" \
              "$REPO_DIR/backup/mcs-backup.service" \
              "$REPO_DIR/backup/mcs-backup.timer" \
              "$REPO_DIR/server/mcs-dns.service" \
              "$REPO_DIR/server/mcs-dns.timer" \
              "$REPO_DIR/backup/mcs-usb-kopie.service" \
              "$REPO_DIR/backup/mcs-usb-kopie.path" \
              "$REPO_DIR/backup/mcs-cloud-kopie.service" \
              "$REPO_DIR/backup/mcs-cloud-kopie.path" \
              "$REPO_DIR/admin/mcs-admin.service"; do
  NAME="$(basename "$QUELLE")"
  ZIEL="$SERVICE_DIR/$NAME"

  # mcs-admin nur, wenn die Weboberfläche installiert ist.
  if [ "$NAME" = "mcs-admin.service" ] && [ ! -d "$MC_ADMIN_DIR" ]; then
    continue
  fi

  # Der Backup-Timer traegt eine vom Nutzer gewaehlte Uhrzeit. Die gehoert der
  # Installation, nicht dem Repository — sonst setzte jedes Ausrollen sie
  # stillschweigend auf vier Uhr zurueck.
  #
  # Bis v1.1 wurde sie dafuer aus der bestehenden Einheit gelesen und in die
  # neue zurueckgeschrieben. Seit v1.1 steht sie in einem Drop-in (E20) — und
  # ZWEI Wege zu derselben Einstellung laufen in diesem Projekt verlaesslich
  # auseinander. Deshalb nur noch eine EINMALIGE Uebernahme: Steht in der
  # alten Einheit eine abweichende Zeit und gibt es noch kein Drop-in, wandert
  # sie dorthin. Danach ist das Drop-in die einzige Wahrheit, und deploy.sh
  # fasst es nie wieder an.
  if [ "$NAME" = "mcs-backup.timer" ] && [ -f "$ZIEL" ] && [ ! -f "$ZEIT_DROPIN" ]; then
    BISHER=$(sed -n 's#^OnCalendar=##p' "$ZIEL" | tail -n1)
    VORLAGE_ZEIT=$(sed -n 's#^OnCalendar=##p' "$QUELLE" | tail -n1)
    if [ -n "$BISHER" ] && [ "$BISHER" != "$VORLAGE_ZEIT" ]; then
      echo "  ~ Backup-Uhrzeit \"$BISHER\" wandert ins Drop-in $ZEIT_DROPIN"
      GEAENDERT=$((GEAENDERT + 1))
      if [ "$PROBE" = false ]; then
        sudo mkdir -p "$(dirname "$ZEIT_DROPIN")"
        {
          echo "# Beim Umstieg auf v1.1 aus mcs-backup.timer uebernommen."
          echo "# Diese Datei gehoert der Installation; deploy.sh fasst sie"
          echo "# nicht mehr an. Aendern in der Weboberflaeche unter Backups."
          echo "[Timer]"
          echo "# Leerer Wert zuerst: OnCalendar ist eine Liste."
          echo "OnCalendar="
          echo "OnCalendar=$BISHER"
        } | sudo tee "$ZEIT_DROPIN" >/dev/null
      fi
    fi
  fi

  # Wie in install.sh: abweichende Pfade aus mcs.conf einsetzen.
  # Environment=MCS_USER: die USB-Kopie läuft als root und liest den
  # Benutzer deshalb nicht aus der mcs.conf, sondern aus ihrer Einheit.
  ANGEPASST=$(sed -e "s#/home/pi/mcs#${MC_DIR}#g" \
                  -e "s#^User=pi\$#User=${MCS_USER}#" \
                  -e "s#^Group=pi\$#Group=${MCS_USER}#" \
                  -e "s#^Environment=MCS_USER=pi\$#Environment=MCS_USER=${MCS_USER}#" \
                  "$QUELLE")

  if [ -f "$ZIEL" ] && printf '%s\n' "$ANGEPASST" | cmp -s - "$ZIEL"; then
    continue
  fi

  # Eine Einheit, die es hier noch nicht gibt, ist neu — und neu heisst: Sie
  # wurde auf diesem Pi auch noch nie aktiviert. Block 3c holt das nach, aber
  # nur, wenn ein [Install]-Abschnitt ueberhaupt vorsieht, dass sie irgendwo
  # eingehaengt wird: "mcs-dns.service" ist "static" und wird vom Timer
  # gestartet, nicht vom Autostart.
  if [ ! -f "$ZIEL" ]; then
    echo "  + neu:          $ZIEL"
    if grep -q '^\[Install\]' "$QUELLE"; then
      NEUE_EINHEITEN="$NEUE_EINHEITEN $NAME"
    fi
  else
    echo "  ~ aktualisiert: $ZIEL"
  fi
  GEAENDERT=$((GEAENDERT + 1))
  DIENSTE_GEAENDERT=true
  # Die Kopien haben mit dem laufenden Server nichts zu tun. Ohne diese
  # Ausnahme verlangte das erste Ausrollen von v1.4 einen Neustart, der
  # Spieler hinauswirft und nichts bewirkt.
  case "$NAME" in
    mcs-usb-kopie.*|mcs-cloud-kopie.*) ;;
    *) NEUSTART_NOETIG=true ;;
  esac

  if [ "$PROBE" = false ]; then
    printf '%s\n' "$ANGEPASST" | sudo tee "$ZIEL" >/dev/null
    sudo chmod 644 "$ZIEL"
  fi
done

if [ "$DIENSTE_GEAENDERT" = true ] && [ "$PROBE" = false ]; then
  # Bewusst nicht abbrechen, wenn das schiefgeht: Der wichtigste Teil des
  # Deploys — der Konfigurationsvergleich weiter unten — soll auch dann
  # noch erscheinen. Ohne daemon-reload gelten schlicht die alten
  # Dienstdateien weiter, das ist ärgerlich, aber ungefährlich.
  if sudo systemctl daemon-reload; then
    echo "  systemd hat die geänderten Dienstdateien eingelesen."
  else
    echo "  ! systemctl daemon-reload ist fehlgeschlagen — bitte von Hand nachholen:"
    echo "    sudo systemctl daemon-reload"
  fi
fi

# ----------------------------------------------------------------------------
# 3b) Die Verankerung nachziehen (WantedBy)
# ----------------------------------------------------------------------------
# daemon-reload liest geänderte Dienstdateien ein, aber es fasst die
# enable-Verweise NICHT an. Die entstehen einmalig beim "systemctl enable" und
# folgen dem [Install]-Abschnitt, der damals galt.
#
# Auf einer Installation aus der Zeit vor mcs.target hängen die Dienste
# deshalb weiter unter multi-user.target, obwohl in der frisch ausgerollten
# Datei "WantedBy=mcs.target" steht. Gemessen am 2026-08-29 auf dem Pi:
#
#   Datei sagt:            WantedBy=mcs.target
#   systemctl show sagt:   WantedBy=multi-user.target
#
# Die Folge ist genau der Fehler, den mcs.target verhindern soll: "mcs aus"
# stoppt die Dienste (über PartOf), aber beim nächsten Booten zieht
# multi-user.target sie über die alten Verweise wieder hoch. Der Hauptschalter
# sieht aus, als wirke er — bis zum Neustart.
#
# Nur "systemctl reenable" räumt die alten Verweise ab und legt sie nach dem
# heutigen [Install] neu an. Angefasst werden ausschließlich Dienste, die
# bereits aktiviert sind: Wer einen Dienst bewusst deaktiviert hat, behält
# ihn deaktiviert.
ANKER_UMGEHAENGT=false

for NAME in mcs-admin.service minecraft.service mcs-playerlog.service \
            mcs-backup.timer mcs-dns.timer; do
  ZIEL="$SERVICE_DIR/$NAME"
  [ -f "$ZIEL" ] || continue

  # Nur aktivierte Dienste. "disabled", "static", "masked" bleiben unberührt.
  [ "$(systemctl is-enabled "$NAME" 2>/dev/null)" = "enabled" ] || continue

  SOLL=$(sed -n 's/^WantedBy=//p' "$ZIEL" | tail -n1)
  IST=$(systemctl show "$NAME" -p WantedBy --value 2>/dev/null)
  [ -n "$SOLL" ] || continue
  [ "$SOLL" != "$IST" ] || continue

  if [ "$PROBE" = true ]; then
    echo "  ~ $NAME hängt unter '$IST', soll unter '$SOLL' — wird umgehängt"
    GEAENDERT=$((GEAENDERT + 1))
    ANKER_UMGEHAENGT=true
    continue
  fi

  if sudo systemctl reenable "$NAME" >/dev/null 2>&1; then
    echo "  ~ $NAME umgehängt: '$IST' -> '$SOLL'"
    GEAENDERT=$((GEAENDERT + 1))
    ANKER_UMGEHAENGT=true
  else
    echo "  ! $NAME liess sich nicht umhängen — bitte von Hand nachholen:"
    echo "    sudo systemctl reenable $NAME"
  fi
done

# Wurde etwas umgehängt, hängt der Autostart jetzt an mcs.target. Ist das
# selbst nicht aktiviert, käme nach dem nächsten Neustart NICHTS mehr hoch —
# das Ausrollen hätte den Server stillgelegt. Ein Deploy darf den
# Autostart-Zustand aber nicht verändern, also wird mcs.target nachgezogen.
# Ohne --now: Was gerade läuft, läuft weiter; was aus ist, bleibt aus.
if [ "$ANKER_UMGEHAENGT" = true ] \
   && [ "$(systemctl is-enabled mcs.target 2>/dev/null)" != "enabled" ]; then
  if [ "$PROBE" = true ]; then
    echo "  ~ mcs.target wird aktiviert (sonst startet nach dem Umhängen nichts mehr)"
  elif sudo systemctl enable mcs.target >/dev/null 2>&1; then
    echo "  ~ mcs.target aktiviert — der Autostart bleibt damit erhalten."
  else
    echo "  ! mcs.target liess sich nicht aktivieren. ACHTUNG: Nach dem"
    echo "    nächsten Neustart käme nichts mehr hoch. Von Hand nachholen:"
    echo "    sudo systemctl enable mcs.target"
  fi
fi

# ----------------------------------------------------------------------------
# 3c) Neu hinzugekommene Einheiten aktivieren
# ----------------------------------------------------------------------------
# Block 3b haengt nur um, was bereits aktiviert ist. Eine Einheit, die mit
# einer neuen Etappe dazukommt, war noch nie aktiviert: "reenable" laesst sie
# liegen, und ausgerollt allein tut sie nichts.
#
# Gemessen am 2026-08-30 auf dem Pi, unmittelbar nach dem Ausrollen von
# Etappe D:
#
#   systemctl is-enabled mcs-dns.timer        -> disabled
#   systemctl show mcs-dns.timer -p WantedBy  -> (leer)
#
# install.sh aktiviert denselben Timer bei einer frischen Installation immer
# ("Der DNS-Timer wird IMMER eingerichtet", siehe dort). Ohne diesen Block
# haengt das Ergebnis davon ab, auf welchem Weg jemand zu Etappe D kommt, und
# wer aufruestet, bekaeme den Namen nie nachgefuehrt. Der Fehler waere dabei
# still: Ein Timer, der nicht laeuft, meldet nichts.
#
# Angefasst wird ausschliesslich, was DIESER Lauf zum ersten Mal angelegt hat.
# Wer eine Einheit selbst abgeschaltet hat, behaelt sie abgeschaltet — ihre
# Datei lag ja schon da, sie steht also gar nicht in dieser Liste.
for NAME in $NEUE_EINHEITEN; do
  if [ "$PROBE" = true ]; then
    echo "  ~ $NAME ist neu und wird aktiviert"
    continue
  fi

  # Wie in install.sh: Ist PiCraft gerade abgeschaltet ("mcs aus"), wird zwar
  # aktiviert, aber nicht gestartet — sonst naehme das Ausrollen dem Nutzer
  # seine Entscheidung ab und zoege einen Dienst hoch, den er abgeschaltet hat.
  if [ "$(systemctl is-enabled mcs.target 2>/dev/null)" = "disabled" ]; then
    if sudo systemctl enable "$NAME" >/dev/null 2>&1; then
      echo "  ~ $NAME aktiviert (nicht gestartet — PiCraft ist gerade aus)."
    else
      echo "  ! $NAME liess sich nicht aktivieren. Von Hand nachholen:"
      echo "    sudo systemctl enable $NAME"
    fi
  else
    if sudo systemctl enable --now "$NAME" >/dev/null 2>&1; then
      echo "  ~ $NAME aktiviert und gestartet."
    else
      echo "  ! $NAME liess sich nicht aktivieren. Von Hand nachholen:"
      echo "    sudo systemctl enable --now $NAME"
    fi
  fi
done

# ----------------------------------------------------------------------------
# 3d) Nachträgliche Korrekturen an der Installation
# ----------------------------------------------------------------------------
# Dinge, die install.sh bei einer FRISCHEN Installation inzwischen richtig
# macht, die aber auf einer bestehenden noch falsch dastehen. Jede Korrektur
# bekommt eine eigene Abfrage — eine Sammelbedingung ("wenn die erste schon
# erledigt ist") ließe später Hinzugekommenes stillschweigend liegen.

SCHRITT="Nachträgliche Korrekturen"

# Nimmt player_activity.log aus einer bestehenden logrotate-Regel heraus.
#
# Warum das ein eigener Schritt sein MUSS: install.sh richtet ein, deploy.sh
# rollt aus. Die Korrektur vom 21.09.2026 steht in install.sh — eine
# bestehende Installation sieht davon nichts, dort bliebe die Regel stehen.
# Und sie ist nicht harmlos: Die Weboberfläche liest das Hauptbuch als
# Ganzes für "zuletzt gesehen"; nach jeder Rotation stand die Live-Datei auf
# 0 Byte und die Spielerseite meldete für jeden Spieler "nicht
# aufgezeichnet". Ohne diesen Block macht die nächste wöchentliche Rotation
# ein nachgetragenes Protokoll wieder zunichte — genau so geschehen zwischen
# dem 01.09. (nachgetragen) und dem 06.09.2026 (rotiert).
# Der Hinweis, der in der Regel stehen bleibt, nachdem die Zeile weg ist.
# Ohne ihn stünde dort nur noch eine Lücke — und der nächste, der die Datei
# aufmacht, trägt das Hauptbuch gutgemeint wieder ein. Die erste Zeile ist
# zugleich die Marke, an der ein zweiter Lauf erkennt, dass nichts zu tun
# ist.
#
# WORTGLEICH mit dem Block in install.sh (Funktion logrotate_einrichten).
# Das ist kein Schmuck: Liefe eine frische Installation mit anderem
# Wortlaut, fände dieser Schritt seine Marke nicht und schriebe eine
# ZWEITE Erklärung darüber. tests/pruefung-historie.py vergleicht beide.
LOGROTATE_MARKE="# player_activity.log gehört hier NICHT hinein (Hauptbuch)."
LOGROTATE_HINWEIS_2="# Die Weboberfläche liest es als Ganzes; eine Rotation schneidet ihr"
LOGROTATE_HINWEIS_3="# genau die Antwort auf \"zuletzt gesehen\" weg (Befund 21.09.2026)."

logrotate_hauptbuch_loesen() {
  local REGEL=/etc/logrotate.d/picraft
  local ZEILE_DA=false MARKE_DA=false

  [ -f "$REGEL" ] || return 0

  grep -q "^[^#]*player_activity\.log" "$REGEL" && ZEILE_DA=true
  grep -qF "$LOGROTATE_MARKE" "$REGEL" && MARKE_DA=true

  if [ "$ZEILE_DA" = false ] && [ "$MARKE_DA" = true ]; then
    return 0
  fi

  if [ "$PROBE" = true ]; then
    [ "$ZEILE_DA" = true ] \
      && echo "  ~ player_activity.log würde aus $REGEL entfernt (Hauptbuch)"
    [ "$MARKE_DA" = false ] \
      && echo "  ~ der Hinweis, warum es dort fehlt, würde ergänzt"
    return 0
  fi

  # Trennzeichen "#", weil der Pfad Schrägstriche enthält. Nur
  # Nicht-Kommentarzeilen: Der Hinweis nennt den Dateinamen selbst.
  if [ "$ZEILE_DA" = true ]; then
    sudo sed -i '\#^[^#]*player_activity\.log#d' "$REGEL"
  fi

  if [ "$MARKE_DA" = false ]; then
    # awk und nicht sed: Der einzufügende Text beginnt selbst mit "#", und
    # damit kollidiert er mit jedem sed-Trennzeichen, das nahe liegt. Der
    # erste Versuch am 21.09.2026 endete genau so ("unknown option to `s'")
    # — gefunden in einer Sandbox, bevor er die Maschine erreichte.
    local TMP
    TMP=$(mktemp)
    awk -v z1="$LOGROTATE_MARKE" -v z2="$LOGROTATE_HINWEIS_2" \
        -v z3="$LOGROTATE_HINWEIS_3" '
      # Vor die erste Zeile, die kein Kommentar ist — also direkt über die
      # Liste der rotierten Dateien, wo jemand den Hinweis suchen würde.
      !fertig && /^[^#]/ { print z1; print z2; print z3; fertig = 1 }
      { print }
    ' "$REGEL" > "$TMP"
    sudo cp "$TMP" "$REGEL"
    sudo chmod 644 "$REGEL"
    rm -f "$TMP"
  fi

  if grep -q "^[^#]*player_activity\.log" "$REGEL"; then
    echo "  ! player_activity.log steht weiterhin in $REGEL — von Hand"
    echo "    entfernen, sonst leert die nächste Rotation das Hauptbuch."
    return 0
  fi

  echo "  ~ $REGEL: Hauptbuch wird nicht mehr rotiert (Hinweis ergänzt)"
  GEAENDERT=$((GEAENDERT + 1))
}

echo ""
echo "--- Nachträgliche Korrekturen ---"
logrotate_hauptbuch_loesen

# ----------------------------------------------------------------------------
# 4) Konfiguration vergleichen
# ----------------------------------------------------------------------------
# Das ist der Teil, den es vorher gar nicht gab: Konfigurationsvorlagen
# wurden nur kopiert, wenn die Zieldatei FEHLTE. Eine Änderung an
# server.properties oder paper-global.yml im Repository erreichte einen
# bestehenden Server also nie — und umgekehrt driftete die Datei auf dem
# Pi (Editor in der Weboberfläche, von Paper ergänzte Schlüssel)
# unbemerkt vom Repo weg.
echo ""
SCHRITT="Konfiguration vergleichen"
echo "--- Konfiguration ---"

KONFIG_ABWEICHUNGEN=0
KONFIG_INSTANZ=0

# a) YAML-Dateien: ganze Datei vergleichen — aber OHNE Kommentarzeilen.
#
# Die Vorlagen tragen "# PiCraft:"-Kommentare, die sagen, warum ein Wert von
# der Paper-Voreinstellung abweicht. Paper schreibt diese Dateien beim
# Start neu und wirft dabei jeden Kommentar weg. Bis zum 21.10.2026 meldete
# deshalb JEDER Lauf alle vier Dateien als abweichend, mit seitenlangen
# Kommentar-Diffs, und die echten Unterschiede gingen darin unter: Dass
# Paper 26.3 vier Schlüssel neu brachte und zwei strich, stand eine Woche
# lang in dieser Ausgabe, ohne dass es jemand sah. Jetzt zählt nur, was
# Paper auch liest. Bleiben bloß die Kommentare übrig, gibt es eine Zeile
# Hinweis und sonst nichts — auch kein Kopieren und keinen Neustart.
ohne_kommentare() {
  grep -v -E '^[[:space:]]*(#|$)' "$1" || true
}
NUR_KOMMENTARE=""

for REL in spigot.yml bukkit.yml config/paper-global.yml config/paper-world-defaults.yml; do
  QUELLE="$REPO_DIR/server/$REL"
  ZIEL="$MC_SERVER_DIR/$REL"

  [ -f "$QUELLE" ] || continue

  if [ ! -f "$ZIEL" ]; then
    echo "  + $REL fehlt auf dem Pi — wird angelegt."
    KONFIG_ABWEICHUNGEN=$((KONFIG_ABWEICHUNGEN + 1))
    if [ "$PROBE" = false ]; then
      mkdir -p "$(dirname "$ZIEL")"
      cp "$QUELLE" "$ZIEL"
      NEUSTART_NOETIG=true
    fi
    continue
  fi

  if cmp -s "$QUELLE" "$ZIEL"; then
    continue
  fi

  if cmp -s <(ohne_kommentare "$QUELLE") <(ohne_kommentare "$ZIEL"); then
    NUR_KOMMENTARE="$NUR_KOMMENTARE $REL"
    continue
  fi

  KONFIG_ABWEICHUNGEN=$((KONFIG_ABWEICHUNGEN + 1))
  echo ""
  # Hier stand bis zum 21.10.2026 "(links Repo, rechts Pi)" — genau
  # verkehrt herum: diff -u bekommt zuerst den Pi. Wer dem Text glaubte,
  # hielt neue Schlüssel für gestrichene (so geschehen am 21.10.).
  echo "  ~ $REL weicht ab (- nur auf dem Pi, + nur in der Vorlage; Kommentare ausgeblendet):"
  diff -u <(ohne_kommentare "$ZIEL") <(ohne_kommentare "$QUELLE") | tail -n +3 | sed 's/^/      /' || true

  if [ "$KONFIG_UEBERNEHMEN" = true ] && [ "$PROBE" = false ]; then
    cp "$ZIEL" "$ZIEL.vorher-$(date +%Y%m%d-%H%M%S)"
    cp "$QUELLE" "$ZIEL"
    echo "      -> übernommen (die bisherige Fassung liegt als .vorher-... daneben)"
    NEUSTART_NOETIG=true
  fi
done

if [ -n "$NUR_KOMMENTARE" ]; then
  echo "  = wertgleich mit der Vorlage, nur ohne deren Kommentare:$NUR_KOMMENTARE"
  echo "    (Paper entfernt Kommentare beim Schreiben — nichts zu tun.)"
fi

# b) server.properties: NICHT die ganze Datei ersetzen.
#
# Der Server schreibt diese Datei beim Start selbst neu und ergänzt dabei
# Schlüssel, die es in der Repo-Vorlage gar nicht gibt. Ein vollständiges
# Überschreiben würde sie alle auf die Voreinstellung zurücksetzen.
# Verglichen und übernommen werden deshalb nur die Schlüssel, die in der
# Vorlage tatsächlich gesetzt sind.
QUELLE="$REPO_DIR/server/server.properties"
ZIEL="$MC_SERVER_DIR/server.properties"

# ----------------------------------------------------------------------------
# Schlüssel, die JEDE Installation für sich selbst beantwortet
# ----------------------------------------------------------------------------
# Diese Werte werden verglichen und gemeldet, aber NIE übernommen — auch
# nicht mit --konfig-uebernehmen.
#
# Warum das sein muss, am gefährlichsten Beispiel: `level-name` sagt, wie der
# Weltordner heißt. Heißt die Welt auf einem Pi anders als in der Vorlage
# (dort: "world"), und würde --konfig-uebernehmen den Vorlagenwert schreiben,
# erzeugte der nächste Start eine leere Welt namens "world" — die echte Welt
# läge unberührt daneben, aber der Server öffnete sie nicht mehr. Für alle
# Beteiligten sähe es aus, als wären sämtliche Bauten weg.
#
# Bis 2026-08-26 stand `level-name` gar nicht in der Vorlage; die Falle
# entstand erst dadurch, dass sie vervollständigt wurde. Diese Liste ist
# die Antwort darauf.
#
# `motd` steht aus einem harmloseren Grund hier: Der Begrüßungstext gehört
# dem Betreiber, nicht der Vorlage.
#
# `server-port` kam am 2026-08-29 dazu, aufgefallen bei der Abnahme auf dem
# Pi. Die Vorlage nennt seit dem ersten Commit 25565 — den Standardport, den
# ein fremder Nutzer erwartet. Dieser Pi läuft auf 25570. Ohne diesen Eintrag
# meldete jeder Probelauf die Abweichung als zu übernehmen, und ein
# --konfig-uebernehmen hätte den Server auf einen Port gestellt, auf dem ihn
# niemand sucht: Die Spieler kämen nicht mehr durch, und die
# Router-Weiterleitung zeigte weiter auf 25570. Wie beim Weltnamen gilt: Die
# Vorlage darf den Standard vorschlagen, ihn dieser Installation aber nicht
# aufzwingen.

# Die Liste wird nicht mehr hier gefuehrt, sondern AUS DER VORLAGE gelesen.
#
# Bis zum 2026-08-31 stand hier eine fest verdrahtete Zeichenkette, und genau
# die musste zweimal von Hand nachgezogen werden — beide Male erst, nachdem
# es beinahe schiefgegangen war (level-name am 2026-08-26, server-port am
# 2026-08-29). Eine Liste, die man beim Hinzufuegen eines Wertes vergessen
# kann, vergisst irgendwann jemand; und was sie schuetzt, ist die Welt.
#
# Jetzt steht die Angabe dort, wo der Wert steht: als Kommentarzeile
# "# PiCraft: instanzspezifisch" direkt ueber ihm in server/server.properties.
# Wer einen solchen Wert hinzufuegt, sieht die Markierung der Nachbarn.
#
# Findet die Suche NICHTS, ist das ein Fehler und kein leeres Ergebnis:
# Ohne Liste wuerde ein --konfig-uebernehmen den Weltnamen ueberschreiben.
# Also lieber abbrechen als ungeschuetzt weiterlaufen.
INSTANZ_SCHLUESSEL="$(
  awk '/^# PiCraft: instanzspezifisch/ { merk = 1; next }
       merk && /^[A-Za-z0-9._-]+=/     { sub(/=.*/, ""); print; merk = 0; next }
       { merk = 0 }' "$QUELLE" 2>/dev/null | tr '\n' ' '
)"

if [ -z "${INSTANZ_SCHLUESSEL// /}" ]; then
  echo "Fehler: In $QUELLE ist kein Schlüssel als instanzspezifisch markiert." >&2
  echo "        Erwartet wird über level-name, motd, server-port und" >&2
  echo "        enable-command-block je eine Zeile" >&2
  echo "        '# PiCraft: instanzspezifisch'. Ohne sie würde --konfig-uebernehmen" >&2
  echo "        den Weltnamen dieser Installation überschreiben." >&2
  exit 1
fi

ist_instanzspezifisch() {
  local K
  for K in $INSTANZ_SCHLUESSEL; do
    [ "$K" = "$1" ] && return 0
  done
  return 1
}

# Bei laufendem Server wird NICHT geschrieben (Korrektur K3).
#
# Paper schreibt server.properties beim Start neu — und die ganze Datei aus dem
# Speicher, sobald ein Befehl eine dort gespeicherte Einstellung tatsaechlich
# aendert. Es genuegt, dass jemand im Spiel "/whitelist add" tippt. Ein
# --konfig-uebernehmen waere dann lautlos verworfen, und der abschliessende
# Hinweis "mcs restart" haette nicht ahnen lassen, dass etwas auf dem Spiel
# stand. Bis zum 2026-08-31 fehlte diese Pruefung hier ganz, obwohl
# admin/konfig.py genau dagegen verteidigt: derselbe Fehler auf dem zweiten Weg
# zur selben Datei.
#
# Gemeldet werden die Abweichungen trotzdem — nur eben geschrieben nicht.
KONFIG_SCHREIBEN="$KONFIG_UEBERNEHMEN"
if [ "$KONFIG_UEBERNEHMEN" = true ] \
   && systemctl is-active --quiet "${MCS_SERVICE_NAME:-minecraft.service}" 2>/dev/null; then
  KONFIG_SCHREIBEN=false
  echo "  ! Der Minecraft-Server läuft — server.properties wird NICHT geschrieben."
  echo "    Paper schreibt die Datei beim Start und bei jeder Änderung aus dem"
  echo "    Speicher neu; die Übernahme verschwände lautlos. Erst stoppen:"
  echo "      mcs stop && ./deploy.sh --konfig-uebernehmen"
  echo "    Die Abweichungen werden unten trotzdem aufgeführt."
fi

if [ -f "$QUELLE" ] && [ -f "$ZIEL" ]; then
  while IFS= read -r ZEILE; do
    case "$ZEILE" in ''|\#*) continue ;; esac
    case "$ZEILE" in *=*) : ;; *) continue ;; esac

    SCHLUESSEL="${ZEILE%%=*}"
    SOLL="${ZEILE#*=}"
    IST=$(sed -n "s/^${SCHLUESSEL}=//p" "$ZIEL" | tail -n1)

    if [ "$SOLL" != "$IST" ]; then
      # Instanzspezifisches zählt nicht als Abweichung: Bis zum 21.10.2026
      # stand am Ende jedes Laufs "4 Abweichung(en) gefunden — Übernehmen
      # mit --konfig-uebernehmen", obwohl genau diese vier nie übernommen
      # werden. Die Empfehlung lief also ins Leere, und ein echter fünfter
      # Fund wäre in der gewohnten Zahl verschwunden.
      if ist_instanzspezifisch "$SCHLUESSEL"; then
        KONFIG_INSTANZ=$((KONFIG_INSTANZ + 1))
        echo "  = server.properties: $SCHLUESSEL — Pi hat '${IST:-（fehlt）}', Vorlage '$SOLL'"
        echo "      (gehört dieser Installation, wird nie übernommen)"
        continue
      fi
      KONFIG_ABWEICHUNGEN=$((KONFIG_ABWEICHUNGEN + 1))

      echo "  ~ server.properties: $SCHLUESSEL — Pi hat '${IST:-（fehlt）}', Repo will '$SOLL'"

      if [ "$KONFIG_SCHREIBEN" = true ] && [ "$PROBE" = false ]; then
        if [ -z "$IST" ] && ! grep -q "^${SCHLUESSEL}=" "$ZIEL"; then
          printf '%s=%s\n' "$SCHLUESSEL" "$SOLL" >> "$ZIEL"
        else
          sed -i "s|^${SCHLUESSEL}=.*|${SCHLUESSEL}=${SOLL}|" "$ZIEL"
        fi
        echo "      -> übernommen"
        NEUSTART_NOETIG=true
      fi
    fi
  done < "$QUELLE"
elif [ -f "$QUELLE" ] && [ ! -f "$ZIEL" ]; then
  echo "  + server.properties fehlt auf dem Pi — wird angelegt."
  [ "$PROBE" = false ] && cp "$QUELLE" "$ZIEL"
fi

# c) plugins.txt: nur anlegen, wenn sie ganz fehlt.
#
# Sie gehört dem Pi (siehe Kopfkommentar), wird also weder verglichen noch
# überschrieben. Fehlt sie aber komplett — etwa auf einer Installation von
# vor dieser Änderung —, hätte plugin-update.sh gar keine Liste mehr. Dann
# kommt einmalig die Vorlage hin.
if [ ! -f "$MC_SERVER_DIR/plugins.txt" ] && [ -f "$REPO_DIR/server/plugins.txt.beispiel" ]; then
  echo "  + plugins.txt fehlt auf dem Pi — wird aus der Vorlage angelegt."
  KONFIG_ABWEICHUNGEN=$((KONFIG_ABWEICHUNGEN + 1))
  [ "$PROBE" = false ] && cp "$REPO_DIR/server/plugins.txt.beispiel" "$MC_SERVER_DIR/plugins.txt"
fi

if [ "$KONFIG_ABWEICHUNGEN" -eq 0 ] && [ "$KONFIG_INSTANZ" -gt 0 ]; then
  echo ""
  echo "  Nichts zu übernehmen. ($KONFIG_INSTANZ Wert(e) oben gehören dieser Installation.)"
elif [ "$KONFIG_ABWEICHUNGEN" -eq 0 ]; then
  echo "  Repo und Pi sind identisch."
elif [ "$KONFIG_UEBERNEHMEN" = false ]; then
  # Vor der Übernahme wird nur angezeigt. Das ist Absicht: Der Pi ist die
  # Instanz, auf der wirklich gespielt wird, und niemand soll dort
  # versehentlich eine Einstellung verlieren.
  echo ""
  echo "  $KONFIG_ABWEICHUNGEN Abweichung(en) gefunden — es wurde NICHTS geändert."
  echo "  Übernehmen mit:  ./deploy.sh --konfig-uebernehmen"
  echo "  (Die bisherigen Fassungen bleiben dabei als .vorher-... liegen.)"
fi

# ----------------------------------------------------------------------------
# 5) Abschluss
# ----------------------------------------------------------------------------
# Der Stand wird GANZ AM ENDE festgeschrieben, nach allem anderen. Das ist
# der ganze Sinn der Datei: Sie sagt nicht, welche Nummer im Repository
# steht, sondern welches Ausrollen wirklich durchgelaufen ist. Bricht der
# Lauf vorher ab, tragen die Dateien schon die neue Nummer, diese hier aber
# noch die alte — und die Oberflaeche sagt das in der Fusszeile.
#
# In diesem Projekt war dieselbe Unterscheidung schon zweimal teuer: Die
# Unit-Datei sagte "WantedBy=mcs.target", die Installation etwas anderes;
# die Vorlage sagte einen Port, die Live-Konfiguration einen anderen.
# Beide Male war die Datei ueberzeugend und falsch.
if [ "$PROBE" = false ]; then
  SCHRITT="Stand festschreiben"
  STAND="$(head -n1 "$REPO_DIR/VERSION" 2>/dev/null | tr -d '[:space:]')"
  if [ -n "$STAND" ]; then
    {
      echo "# Von deploy.sh geschrieben. Welcher Stand hier zuletzt"
      echo "# VOLLSTAENDIG ausgerollt wurde — nicht, was im Repo steht."
      echo "MCS_STAND=$STAND"
      echo "MCS_STAND_ZEIT=$(date '+%Y-%m-%d %H:%M:%S')"
      echo "MCS_STAND_WOMIT=deploy.sh"
    } > "$MC_DIR/ausgerollt"
  else
    echo "  ! $REPO_DIR/VERSION fehlt oder ist leer — der Stand wurde nicht"
    echo "    festgeschrieben. Die Oberflaeche meldet ihn dann als unbekannt."
  fi
fi

echo ""
echo "================================================================"
if [ "$PROBE" = true ]; then
  echo " Probelauf beendet — verändert wurde nichts."
  echo " Wirklich ausrollen:  ./deploy.sh"
elif [ "$GEAENDERT" -eq 0 ] && [ "$KONFIG_ABWEICHUNGEN" -eq 0 ]; then
  echo " Alles schon aktuell — nichts zu tun."
else
  echo " Fertig: $GEAENDERT Datei(en) ausgerollt."
  if [ "$NEUSTART_NOETIG" = true ]; then
    echo ""
    echo " Damit die Änderungen wirken, den Server neu starten:"
    echo "   mcs restart"
    echo " (Spieler bekommen dabei zehn Sekunden Vorwarnung.)"
  fi
  # Die Weboberfläche läuft als eigener Dienst und hält ihren Python-Code
  # im Speicher. Wer sie nicht neu startet, sieht nach dem Ausrollen
  # weiterhin die alte Fassung — und sucht den Fehler in Dateien, die
  # längst richtig sind.
  if [ "$ADMIN_GEAENDERT" = true ]; then
    echo ""
    echo " Die Weboberfläche wurde geändert. Ihr Dienst muss neu starten:"
    echo "   sudo systemctl restart mcs-admin.service"
  fi
  if [ "$PROTOKOLL_GEAENDERT" = true ]; then
    echo ""
    echo " Das Spielerprotokoll wurde geändert. Sein Dienst muss neu starten:"
    echo "   sudo systemctl restart mcs-playerlog.service"
  fi
fi
echo "================================================================"
