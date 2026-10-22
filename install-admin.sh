#!/bin/bash
#
# install-admin.sh — Installiert die optionale Admin-Weboberfläche.
#
# Voraussetzung: Die Server-Grundinstallation (./install.sh) wurde
# bereits ausgeführt.
#
# Was dieses Skript macht:
#   1. Python-Flask installieren (das Web-Framework der Oberfläche)
#   2. Die App nach ~/mcs/admin kopieren
#   3. Eine .env-Datei mit den Zugangsdaten anlegen (Passwort ändern!)
#   4. Eng begrenzte sudo-Rechte einrichten, damit die Oberfläche den
#      Minecraft-Dienst starten/stoppen darf — und sonst nichts
#   5. Den Dienst mcs-admin.service einrichten und starten
#
# Aufruf als Benutzer pi (ohne sudo davor):
#   ./install-admin.sh

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Zentrale Einstellungen aus dem Repo lesen (Pfade, Benutzer, Dienstname).
# Die Einstellungen kommen vom Pi, nicht aus dem Repository (dort liegt nur
# die Vorlage mcs.conf.beispiel). install.sh ruft dieses Skript auf, nachdem
# es die echte mcs.conf erzeugt hat.
# Wo liegt die Installation, wenn mcs.conf (noch) fehlt? Im Heimatverzeichnis
# des Benutzers, dem der Server gehört. Bis 2026-08-28 stand hier fest
# "/home/pi" — auf jedem Pi mit einem anderen Benutzernamen zeigte der
# Rückfallwert damit stumm ins Leere. Siehe CLAUDE.md.
MCS_HOME="${HOME:-/home/$(id -un)}"
MCS_CONF="${MCS_CONF:-${HOME:-/home/$(id -un)}/mcs/mcs.conf}"
# shellcheck source=/dev/null
if [ -f "$MCS_CONF" ]; then . "$MCS_CONF"; fi

# Kein "pi" annehmen: Der Benutzer heisst, wie er heisst (Befund B1).
# Wird dieses Skript von install.sh aufgerufen, steht der Wert schon in
# der mcs.conf, die oben eingelesen wurde.
MCS_USER="${MCS_USER:-$(id -un)}"
MC_DIR="${MCS_DIR:-$MCS_HOME/mcs}"
DIENST="${MCS_SERVICE_NAME:-minecraft.service}"
ADMIN_QUELLE="$REPO_DIR/admin"
ADMIN_ZIEL="${MCS_ADMIN_DIR:-$MC_DIR/admin}"
SERVICE_ZIEL="/etc/systemd/system/mcs-admin.service"
SUDOERS_DATEI="/etc/sudoers.d/mcs-admin"
ENV_DATEI="$ADMIN_ZIEL/.env"

echo "===== Pi-MCS Admin-Weboberfläche installieren ====="

if [ ! -d "$ADMIN_QUELLE" ]; then
  echo "Fehler: $ADMIN_QUELLE nicht gefunden — bitte aus dem Repo-Verzeichnis starten." >&2
  exit 1
fi

echo "== 1/5: Flask installieren =="
# python3-yaml kommt dazu (Etappe C): Der Expertenmodus der Weboberfläche
# lässt YAML-Dateien bearbeiten, und ohne Parser könnte er beim Speichern
# nur auf Tabulatoren prüfen. Ein Tippfehler in paper-global.yml lässt den
# Server beim nächsten Start mit einer unverständlichen Meldung stehen —
# dagegen ist ein 200-KB-Paket aus den Standardquellen gut angelegt.
# Fehlt es trotzdem, sagt die Oberfläche das beim Speichern deutlich.
sudo apt-get update
sudo apt-get install -y python3-flask python3-yaml

echo "== 2/5: Dateien kopieren =="
mkdir -p "$ADMIN_ZIEL"
# ALLE Python-Module der Oberflaeche. Seit 2026-08-28 ist app.py in mehrere
# Dateien aufgeteilt (einstellungen, system, protokoll, konsole, status,
# sicherheit, routen, rcon, metrik, seite_*). Sie einzeln aufzuzaehlen
# hiesse, beim naechsten Modul eines zu vergessen -- und der Fehler zeigte
# sich erst auf einem frisch installierten Pi.
cp "$ADMIN_QUELLE"/*.py "$ADMIN_ZIEL/"

# Vorlagen und statische Dateien als GANZE Verzeichnisbaeume.
#
# Bis Etappe C stand hier eine einzelne Zeile fuer templates/index.html --
# das ging, solange es genau eine Vorlage gab. Jetzt sind es ein Geruest,
# eine Seite je Reiter und die HTMX-Stuecke unter templates/teile/, dazu
# static/ mit dem Stylesheet und den mitgelieferten Fremdteilen (htmx,
# uPlot, Schrift). Einzelne Dateien aufzuzaehlen waere dieselbe Falle wie
# oben bei den Modulen, nur mit mehr Dateien.
#
# Erst loeschen, dann kopieren: Sonst bliebe eine Vorlage, die im
# Repository geloescht wurde, auf dem Pi liegen und wuerde von einer alten
# url_for-Zeile weiter gefunden.
rm -rf "$ADMIN_ZIEL/templates" "$ADMIN_ZIEL/static"
cp -r "$ADMIN_QUELLE/templates" "$ADMIN_ZIEL/templates"
cp -r "$ADMIN_QUELLE/static"    "$ADMIN_ZIEL/static"

# Dieselben Suchmuster fuer das Server-Log, die auch das Spielerlog nutzt.
cp "$REPO_DIR/tools/log-muster.sh"        "$ADMIN_ZIEL/log-muster.sh"

# ----------------------------------------------------------------------------
# Freien Port für die Weboberfläche finden
# ----------------------------------------------------------------------------
# 8080 ist die Voreinstellung — und ausgerechnet auch die von Pl3xMap, dem
# Karten-Plugin, das dieses Projekt mitinstalliert. Wer beides betreibt, hatte
# bisher zwei Programme auf demselben Port: Eines gewinnt, das andere startet
# nicht, und die Fehlermeldung steht in einem Log, in das niemand schaut.
#
# ss gibt es nicht überall; fehlt es, wird einfach 8080 genommen. Ein Ratespiel
# ist besser als ein Abbruch, denn die Weboberfläche ist Zubehör.
ADMIN_PORT=8080

# Hat diese Installation schon eine .env, gilt deren Port — die Suche unten
# entfaellt dann. Sonst sieht sie den eigenen, gerade laufenden Dienst als
# "Beleger", weicht aus und meldet einen Port, der anschliessend gar nicht
# verwendet wird: Die .env bleibt ja unveraendert (Schritt 3/5). Genau das
# passierte am 2026-08-29 auf dem Pi — gemeldet wurde 8081, gelauscht wurde
# weiter auf 8080. Wer der Meldung folgt, sucht die Oberflaeche auf dem
# falschen Port.
BESTEHENDER_PORT=""
if [ -f "$ENV_DATEI" ]; then
  BESTEHENDER_PORT=$(sed -n 's/^MCS_ADMIN_PORT=//p' "$ENV_DATEI" 2>/dev/null | tail -n1) \
    || BESTEHENDER_PORT=""
fi

if [ -n "$BESTEHENDER_PORT" ]; then
  ADMIN_PORT="$BESTEHENDER_PORT"
  echo "Bestehende Weboberfläche auf Port $ADMIN_PORT — bleibt unverändert."
elif command -v ss >/dev/null 2>&1; then
  while ss -ltnH "sport = :$ADMIN_PORT" 2>/dev/null | grep -q .; do
    # Wer belegt ihn? Das interessiert den Nutzer mehr als die Portnummer.
    BELEGER=$(ss -ltnpH "sport = :$ADMIN_PORT" 2>/dev/null \
              | grep -oE 'users:\(\("[^"]+' | head -n1 | cut -d'"' -f2) || BELEGER=""
    echo "Port $ADMIN_PORT ist belegt${BELEGER:+ (von $BELEGER)}."
    ADMIN_PORT=$((ADMIN_PORT + 1))
    if [ "$ADMIN_PORT" -gt 8090 ]; then
      echo "Zwischen 8080 und 8090 ist kein Port frei — die Oberfläche nimmt 8080." >&2
      echo "Läuft dort schon etwas, bitte MCS_ADMIN_PORT in der .env von Hand setzen." >&2
      ADMIN_PORT=8080
      break
    fi
  done
fi
if [ "$ADMIN_PORT" != "8080" ]; then
  echo "Die Weboberfläche benutzt stattdessen Port $ADMIN_PORT."
fi

echo "== 3/5: Zugangsdaten anlegen =="
if [ ! -f "$ENV_DATEI" ]; then
  # Ein zufälliges Passwort statt eines festen Platzhalters.
  #
  # Vorher stand hier "BITTE_AENDERN" — ein Wert, der öffentlich in diesem
  # Repository steht. Zusammen mit dem Lauschen auf allen Netzwerkkarten
  # war die Oberfläche damit ab der Sekunde ihrer Installation für jeden
  # im Netz bedienbar, der dieses Repo kennt: einschließlich "Server
  # stoppen".
  # Warum nicht das naheliegende "tr -dc ... </dev/urandom | head -c 20"?
  # Weil head nach 20 Zeichen aussteigt und die Pipe schliesst — tr bekommt
  # SIGPIPE und endet mit 141. Unter "set -o pipefail" ist damit die ganze
  # Pipeline fehlgeschlagen, und "set -e" bricht das Skript ab. Ob das
  # passiert, haengt am Zufall der Zeitplanung: mal laeuft es durch, mal
  # nicht. Im Abnahmetest vom 2026-08-28 ist es reproduzierbar gescheitert.
  #
  # Stattdessen eine ENDLICHE Menge lesen: head liest 512 Bytes aus einem
  # Geraet (dabei kann niemand SIGPIPE bekommen), tr verarbeitet sie
  # vollstaendig und endet normal. Von den 512 Bytes sind im Schnitt rund
  # 120 alphanumerisch — weit mehr als die gebrauchten 20.
  # Hat der Assistent ein Passwort erfragt, gilt das (Lastenheft 5.1).
  # Sonst wird eines erzeugt. Der Weg fuehrt ueber die Umgebung und nicht
  # ueber einen Aufrufparameter: Parameter stehen in der Prozessliste, die
  # jeder Benutzer des Systems lesen kann.
  PASSWORT="${MCS_ADMIN_PASSWORT_WUNSCH:-}"
  if [ -n "$PASSWORT" ]; then
    SELBST_GEWAEHLT=true
  else
    SELBST_GEWAEHLT=false
    ZUFALL="$(head -c 512 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9')"
    PASSWORT="${ZUFALL:0:20}"
    if [ "${#PASSWORT}" -lt 20 ]; then
      echo "Fehler: Es liess sich kein Zufallspasswort erzeugen." >&2
      echo "Ist /dev/urandom lesbar?" >&2
      exit 1
    fi
  fi

  # Der Sitzungsschluessel (Etappe C). Damit unterschreibt Flask das
  # Anmelde-Cookie. Wer ihn kennt, kann sich ein Cookie bauen, das wie eine
  # gueltige Anmeldung aussieht — er ist also genauso schuetzenswert wie das
  # Passwort und steht deshalb in derselben Datei mit chmod 600.
  #
  # Ohne ihn erzeugt die Oberflaeche beim Start selbst einen zufaelligen.
  # Das funktioniert, meldet aber bei JEDEM Neustart des Dienstes alle ab —
  # sie sagt das dann auch deutlich auf jeder Seite. Hier ist der richtige
  # Ort, das gleich zu vermeiden.
  SCHLUESSEL="$(head -c 512 /dev/urandom | LC_ALL=C tr -dc 'A-Za-z0-9')"
  SCHLUESSEL="${SCHLUESSEL:0:48}"
  if [ "${#SCHLUESSEL}" -lt 48 ]; then
    echo "Fehler: Es liess sich kein Sitzungsschluessel erzeugen." >&2
    exit 1
  fi

  # Die .env-Datei enthält das Passwort. Die Klammern mit "umask 077"
  # sorgen dafür, dass sie SCHON BEIM ANLEGEN nur für den Benutzer pi
  # lesbar ist — chmod erst danach ließe ein kurzes Zeitfenster offen.
  (
    umask 077


    cat > "$ENV_DATEI" <<EOF
# Zugangsdaten der Admin-Weboberfläche.
# Alle übrigen Einstellungen (Pfade, Namen) stehen in ${MC_DIR}/mcs.conf.
# Nach Änderungen: sudo systemctl restart mcs-admin.service
MCS_ADMIN_USER=admin
MCS_ADMIN_PASSWORD=${PASSWORT}

# Womit das Anmelde-Cookie unterschrieben wird. Genauso geheim wie das
# Passwort. Wird er geändert, sind alle abgemeldet — sonst nichts.
MCS_ADMIN_SECRET=${SCHLUESSEL}

# Auf welcher Adresse die Oberfläche lauscht.
#   127.0.0.1  nur auf dem Pi selbst (sicherste Voreinstellung; von außen
#              über einen SSH-Tunnel erreichbar, siehe README)
#   0.0.0.0    im ganzen Heimnetz — dann bitte die Firewall-Regel aus dem
#              README setzen und den Port NICHT im Router freigeben
MCS_ADMIN_HOST=127.0.0.1
MCS_ADMIN_PORT=${ADMIN_PORT}

# Pi-Neustart/-Herunterfahren über die Weboberfläche erlauben?
# Dazu auch die sudo-Regeln in /etc/sudoers.d/mcs-admin einkommentieren.
# MCS_ALLOW_HOST_POWER=1

# Läuft die Oberfläche über HTTPS (Tailscale Serve)? Dann bekommt das
# Anmelde-Cookie zusätzlich das Merkmal "Secure". Über eine reine
# HTTP-Verbindung im Heimnetz dürfte der Browser es dann nicht mehr
# setzen — die Anmeldung wäre unmöglich. Deshalb steht es standardmäßig aus.
# MCS_ADMIN_HTTPS=1
EOF
  )
  chmod 600 "$ENV_DATEI"
  echo "Neue .env-Datei angelegt, mit einem zufälligen Passwort."
else
  echo "Bestehende .env-Datei gefunden — bleibt unverändert."
  PASSWORT=""
fi

echo "== 4/5: sudo-Rechte einrichten =="
# Die Weboberfläche läuft als Benutzer pi. Damit sie den Minecraft-Dienst
# steuern kann, erlauben wir GENAU diese drei systemctl-Befehle ohne
# Passwort — keine anderen. Wichtig: voller Pfad /usr/bin/systemctl,
# er muss exakt zu den Aufrufen in app.py passen.
#
# ┌─ Wie weit diese Einschränkung wirklich trägt ─────────────────────────┐
# │ Auf einem normalen Raspberry Pi OS hat der Benutzer pi bereits eine   │
# │ generelle Regel: /etc/sudoers.d/010_pi-nopasswd mit "NOPASSWD: ALL".  │
# │ Solange die existiert, schränkt die Datei hier faktisch NICHTS ein —  │
# │ pi darf ohnehin alles ohne Passwort.                                  │
# │                                                                       │
# │ Daraus folgt für die Oberfläche: Wer ihr Passwort kennt, kann über    │
# │ den Konsolen-Endpunkt beliebige Minecraft-Befehle absetzen und über   │
# │ den server.properties-Editor die Konfiguration ändern. Das ist der    │
# │ Zweck der Oberfläche — aber es heißt auch, dass ihr Passwort so       │
# │ schützenswert ist wie ein SSH-Zugang. Nicht ins Internet stellen.     │
# │                                                                       │
# │ Die Regel bleibt trotzdem eng gefasst: Sie greift, falls die          │
# │ generelle Regel je entfällt, und sie dokumentiert, was gebraucht wird.│
# │ Geprüft am 2026-08-26.                                                │
# └───────────────────────────────────────────────────────────────────────┘
#
# Erst in eine temporäre Datei schreiben, DANN prüfen, DANN scharfstellen.
#
# Vorher lief es umgekehrt: Die Datei landete direkt in /etc/sudoers.d und
# wurde erst danach geprüft. Eine fehlerhafte Datei ist dort aber sofort
# wirksam — und eine kaputte Datei in sudoers.d kann sudo systemweit
# blockieren. Man hätte sich vom eigenen Pi ausgesperrt.
SUDOERS_TMP="$(mktemp)"
trap 'rm -f "$SUDOERS_TMP"' EXIT

cat > "$SUDOERS_TMP" <<EOF
# Von Pi-MCS angelegt (install-admin.sh).
# Erlaubt der Weboberfläche GENAU diese Befehle ohne Passwort — keine
# anderen. Der volle Pfad muss exakt zu den Aufrufen im Code passen.
${MCS_USER} ALL=(root) NOPASSWD: /usr/bin/systemctl start ${DIENST}, /usr/bin/systemctl stop ${DIENST}, /usr/bin/systemctl restart ${DIENST}
#
# Die Backup-Uhrzeit (seit v1.1). Sie steht in OnCalendar, und das liest
# systemd nicht aus einer EnvironmentFile — die mcs.conf scheidet aus.
# Geschrieben wird ein Drop-in, damit ein ./deploy.sh die Einstellung nicht
# stillschweigend auf 04:00 zurückstellt.
#
# Der Zielpfad ist FEST angegeben, nicht als Muster: "tee" mit freiem Pfad
# wäre ein Schreibrecht auf jede Datei des Systems. So ist es genau eine.
${MCS_USER} ALL=(root) NOPASSWD: /usr/bin/mkdir -p /etc/systemd/system/mcs-backup.timer.d
${MCS_USER} ALL=(root) NOPASSWD: /usr/bin/tee /etc/systemd/system/mcs-backup.timer.d/zeit.conf
${MCS_USER} ALL=(root) NOPASSWD: /usr/bin/systemctl daemon-reload
${MCS_USER} ALL=(root) NOPASSWD: /usr/bin/systemctl restart mcs-backup.timer
# Optional: Pi über die Weboberfläche neu starten / herunterfahren
# (nur einkommentieren, wenn auch MCS_ALLOW_HOST_POWER=1 gesetzt ist):
# ${MCS_USER} ALL=(root) NOPASSWD: /usr/bin/systemctl reboot, /usr/bin/systemctl poweroff
EOF

if ! sudo visudo -cf "$SUDOERS_TMP"; then
  echo "Fehler: Die erzeugte sudo-Regel ist fehlerhaft — sie wird NICHT installiert." >&2
  exit 1
fi

sudo install -m 440 -o root -g root "$SUDOERS_TMP" "$SUDOERS_DATEI"
rm -f "$SUDOERS_TMP"
trap - EXIT
echo "sudo-Regel geprüft und installiert."

echo "== 5/5: Dienst einrichten und starten =="
# Wie in install.sh: die Standardpfade stehen in der Dienstdatei im Klartext,
# abweichende Werte aus mcs.conf werden hier eingesetzt.
sed -e "s#/home/pi/mcs#${MC_DIR}#g" \
    -e "s#^User=pi\$#User=${MCS_USER}#" \
    -e "s#^Group=pi\$#Group=${MCS_USER}#" \
    "$ADMIN_QUELLE/mcs-admin.service" | sudo tee "$SERVICE_ZIEL" >/dev/null
sudo chmod 644 "$SERVICE_ZIEL"
sudo systemctl daemon-reload
sudo systemctl enable mcs-admin.service
sudo systemctl restart mcs-admin.service

echo ""
echo "===== Fertig! ====="
if [ -n "${PASSWORT:-}" ]; then
  echo ""
  echo "  Zugangsdaten (stehen in $ENV_DATEI):"
  echo "    Benutzer: admin"
  if [ "${SELBST_GEWAEHLT:-false}" = true ]; then
    # Ein selbst gewaehltes Passwort wird NICHT noch einmal ausgegeben. Der
    # Nutzer kennt es, und im Terminalverlauf (oder im Protokoll einer
    # ueber SSH mitgeschnittenen Sitzung) hat es nichts verloren.
    echo "    Passwort: das von dir gewählte"
  else
    echo "    Passwort: $PASSWORT"
    echo ""
    echo "  Bitte jetzt notieren — danach steht es nur noch in der Datei."
  fi
fi
echo ""
echo "Die Oberfläche lauscht standardmäßig NUR auf dem Pi selbst"
echo "(127.0.0.1). Das ist Absicht: So ist sie aus dem Netz nicht"
echo "erreichbar, bevor jemand bewusst entscheidet, wer sie sehen darf."
echo ""
echo "Vom eigenen Rechner aus per SSH-Tunnel:"
echo "  ssh -L ${ADMIN_PORT}:localhost:${ADMIN_PORT} ${MCS_USER}@<pi-adresse>"
echo "  danach im Browser: http://localhost:${ADMIN_PORT}"
echo ""
echo "Vom Handy unterwegs, ohne Portfreigabe: über Tailscale."
echo "  Anleitung im README, Abschnitt \"Zugriff über Tailscale\"."
echo ""
echo "Oder dauerhaft im Heimnetz freigeben (siehe README, Sicherheit):"
echo "  1) MCS_ADMIN_HOST=0.0.0.0 in $ENV_DATEI"
echo "  2) sudo ufw allow from 192.168.0.0/16 to any port ${ADMIN_PORT}"
echo "  3) sudo systemctl restart mcs-admin.service"
echo ""
echo "Status im Terminal: mcs status"
