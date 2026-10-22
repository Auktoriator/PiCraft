# shellcheck shell=bash
# (Keine Shebang: Diese Datei wird eingebunden, nicht ausgeführt.)
#
# lib/dateien.sh — WELCHE Dateien aus dem Repository auf den Pi gehören.
#
# Warum es diese Datei gibt: Bis zum 2026-09-02 stand dieselbe Liste zweimal
# im Repository — als `cp`-Block in install.sh und als `ausrollen`-Block in
# deploy.sh. Zwei Listen derselben fünfzehn Dateien laufen auseinander, und
# das ist hier keine Vermutung: lib/hardware.sh fehlte in deploy.sh "bis
# zuletzt" (Kommentar dort), mit der Folge, dass `mcs hardware` auf einer nur
# ausgerollten Installation eine veraltete Fassung benutzte. Wer heute eine
# Datei ergänzt, ergänzt sie an EINER Stelle.
#
# Die Liste wird von einer Funktion gefüllt und nicht beim Einbinden: Die
# Ziele stehen erst fest, wenn $REPO_DIR, $MC_DIR, $MC_SERVER_DIR und
# $MC_BACKUP_DIR gesetzt sind. Beide Skripte binden diese Datei früh ein und
# rufen `mcs_dateiliste` später auf.
#
# Aufbau je Zeile:  QUELLE|ZIEL|MODUS
#
#   (leer)          normal ausrollen
#   neustart        die Änderung wirkt erst nach einem Server-Neustart;
#                   deploy.sh merkt sich das und sagt es am Ende
#   nur-wenn-fehlt  eine VORLAGE. install.sh legt sie einmalig an, deploy.sh
#                   fasst sie nie an — ab dem ersten Start gehört sie dem Pi
#
# Nicht in dieser Liste, mit Absicht:
#   mcs.conf        gehört dem Pi; install.sh erzeugt sie einmalig aus
#                   mcs.conf.beispiel (Befund B2)
#   tools/mcs       liegt außerhalb von $MC_DIR und braucht sudo — steht in
#                   mcs_systemdateien, zusammen mit allem anderen, das root gehört
#   admin/          die Weboberfläche wird als Baum ausgerollt (deploy.sh,
#                   Abschnitt 1) bzw. von install-admin.sh eingerichtet

mcs_dateiliste() {
  # shellcheck disable=SC2034  # gelesen wird sie von install.sh und deploy.sh
  MCS_DATEIEN=(
    # lib-konsole.sh MUSS vor den Skripten stehen, die sie einbinden — sonst
    # stünden die zwischendurch ohne ihre Funktionen da.
    "$REPO_DIR/server/lib-konsole.sh|$MC_SERVER_DIR/lib-konsole.sh|neustart"
    "$REPO_DIR/server/start-minecraft.sh|$MC_SERVER_DIR/start-minecraft.sh|neustart"
    "$REPO_DIR/server/stop-minecraft.sh|$MC_SERVER_DIR/stop-minecraft.sh|"
    "$REPO_DIR/server/paper-update.sh|$MC_SERVER_DIR/paper-update.sh|"
    "$REPO_DIR/server/plugin-update.sh|$MC_SERVER_DIR/plugin-update.sh|"

    # versions.env gehört dem Repository (anders als mcs.conf): Sie legt fest,
    # in welcher Minecraft-Version der Server bleibt und welchen Build eine
    # Erstinstallation lädt. Ohne sie wüsste das Update nicht, wo es stehen
    # bleiben muss, und könnte die Welt umwandeln. "mcs update" schreibt sie
    # hier UND im Repository, damit dieses Kopieren nichts zurückdreht.
    "$REPO_DIR/server/versions.env|$MC_SERVER_DIR/versions.env|"

    # Die Plugin-Liste gehört dem Pi: Die Weboberfläche trägt dort ein, was
    # sie installiert hat. Käme sie bei jedem Ausrollen neu, wäre jede so
    # installierte Erweiterung beim nächsten Mal wieder aus der Liste.
    "$REPO_DIR/server/plugins.txt.beispiel|$MC_SERVER_DIR/plugins.txt|nur-wenn-fehlt"

    "$REPO_DIR/backup/minecraft-backup.sh|$MC_BACKUP_DIR/minecraft-backup.sh|"
    # Die Cloud-Kopie läuft als Benutzer des Servers und darf deshalb hier
    # liegen. Ihr Gegenstück usb-kopie.sh läuft als root und steht darum
    # NICHT in dieser Liste: Es gehört nach /usr/local/lib/pi-mcs/, wo der
    # Benutzer es nicht ändern kann (mcs_systemdateien weiter unten).
    "$REPO_DIR/backup/cloud-kopie.sh|$MC_BACKUP_DIR/cloud-kopie.sh|"
    "$REPO_DIR/tools/log_player_activity.sh|$MC_DIR/log_player_activity.sh|"
    # Die gemeinsamen Suchmuster für das Server-Log — dieselbe Datei nutzen
    # das Spielerlog-Skript und die Weboberfläche.
    "$REPO_DIR/tools/log-muster.sh|$MC_DIR/log-muster.sh|"

    # Die Hardware-Erkennung wird nicht nur beim Installieren gebraucht:
    # `mcs hardware` schlägt später nach, was für ein Gerät das ist. Auf dem
    # Pi liegt sie FLACH als hardware.sh — dort gibt es kein lib/, und für
    # eine einzige Datei eines anzulegen wäre Struktur um ihrer selbst willen.
    "$REPO_DIR/lib/hardware.sh|$MC_DIR/hardware.sh|"

    # Benachrichtigung, Erreichbarkeitstest und DNS: alle drei enthalten keine
    # Zugangsdaten. Thema und Namen stehen in mcs.conf, die Token in ntfy.env
    # bzw. dns.env — und die gehören dem Pi.
    "$REPO_DIR/tools/benachrichtigung.sh|$MC_DIR/benachrichtigung.sh|"
    "$REPO_DIR/tools/erreichbarkeit.sh|$MC_DIR/erreichbarkeit.sh|"
    "$REPO_DIR/tools/dns-update.sh|$MC_DIR/dns-update.sh|"

    # Welchen Stand die ausgerollten DATEIEN haben. Was davon wirklich
    # abgeschlossen wurde, steht in $MC_DIR/ausgerollt — die schreiben
    # install.sh und deploy.sh ganz am Ende, nicht hier.
    "$REPO_DIR/VERSION|$MC_DIR/VERSION|"
  )
}

# ----------------------------------------------------------------------------
# Dateien, die root gehören (seit v1.4)
# ----------------------------------------------------------------------------
# Was außerhalb von $MC_DIR liegt und mit sudo geschrieben wird. Bis v1.3 war
# das nur das mcs-Kommando, und beide Skripte kopierten es mit einer eigenen
# Zeile. Mit der USB-Kopie kamen zwei Dateien dazu — und drei Einzelzeilen in
# zwei Skripten sind genau die zwei Listen, wegen der es diese Datei gibt.
#
# usb-kopie.sh steht hier und nicht oben, weil es als root läuft: Ein
# root-Dienst darf kein Skript starten, das der Benutzer ändern kann (Kopf
# von backup/usb-kopie.sh).
#
# Aufbau je Zeile:  QUELLE|ZIEL|RECHTE
mcs_systemdateien() {
  # shellcheck disable=SC2034  # gelesen wird sie von install.sh und deploy.sh
  MCS_SYSTEMDATEIEN=(
    "$REPO_DIR/tools/mcs|/usr/local/bin/mcs|755"
    "$REPO_DIR/backup/usb-kopie.sh|/usr/local/lib/pi-mcs/usb-kopie.sh|755"
    "$REPO_DIR/backup/99-pi-mcs-usb.rules|/etc/udev/rules.d/99-pi-mcs-usb.rules|644"
  )
}

# Der Inhalt, wie er auf dem Pi stehen soll. Einzige Anpassung: ein anderer
# Stick-Name aus mcs.conf (MCS_USB_NAME) in der udev-Regel. Nur Buchstaben,
# Ziffern, Punkt, Binde- und Unterstrich — alles andere bräche die Regel
# oder diesen sed-Ausdruck, und dann bliebe es beim Standard, wie in
# usb-kopie.sh auch.
mcs_systemdatei_inhalt() {   # mcs_systemdatei_inhalt QUELLE
  local NAME="${MCS_USB_NAME:-MCS-BACKUP}"
  case "$NAME" in
    *[!A-Za-z0-9._-]*) NAME=MCS-BACKUP ;;
  esac
  case "$1" in
    *.rules) sed "s#MCS-BACKUP#$NAME#g" "$1" ;;
    *)       cat "$1" ;;
  esac
}
