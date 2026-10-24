#!/bin/bash
# Abnahmetest: Installation von null in einer wegwerfbaren ARM64-Umgebung.
# Läuft INNERHALB eines debian:trixie-slim-Containers (linux/arm64).
set -uo pipefail
export DEBIAN_FRONTEND=noninteractive

trenner() { echo; echo "################ $* ################"; }

# Sammelstelle für Inhaltsprüfungen, die den Test rot machen sollen.
#
# Bis zum 21.09.2026 konnte dieses Skript nur an einem fehlgeschlagenen
# Installationslauf scheitern. Inhaltliche Prüfungen gaben ihr Ergebnis als
# Text aus — wer das Protokoll nicht las, sah einen grünen Test. Genau die
# Fehlerklasse, wegen der am 01.09.2026 schon die Auswertung der beiden
# Exitcodes nachgerüstet wurde (siehe ganz unten).
#
# Wer eine neue Prüfung schreibt, setzt bei einem Befund FEHLER_GEFUNDEN=1.
FEHLER_GEFUNDEN=0

trenner "0) Grundwerkzeuge"
apt-get update -qq >/dev/null
# python3-yaml gehoert seit Etappe C dazu: Ohne echten Parser kann der
# Expertenmodus kaputtes YAML nicht erkennen -- und dann pruefte dieser
# Test etwas anderes als den Betrieb. install-admin.sh installiert es;
# hier steht es zusaetzlich, damit die Reihenfolge egal ist.
# iproute2 liefert "ss": Ohne das kann die Konfigurationsseite die offenen
# Ports nicht ermitteln, und der Test pruefte eine leere Liste.
apt-get install -y -qq sudo cron curl ca-certificates procps screen systemd \
                      python3-yaml iproute2 >/dev/null 2>&1
# Der Testbenutzer heisst absichtlich NICHT "pi".
#
# Bis 2026-08-28 steckte "pi" fest in mcs.conf und in der Vorpruefung von
# install.sh — jeder andere Benutzername brach die Installation sofort ab.
# Seit Raspberry Pi OS Bookworm (2022) legt der Imager aber gar keinen
# Benutzer "pi" mehr an. Genau deshalb prueft dieser Test mit einem anderen
# Namen: Ein Test, der "pi" benutzt, haette den Fehler nie gefunden.
TESTUSER="${TESTUSER:-mcstester}"
TESTHOME="/home/$TESTUSER"

useradd -m -u 1000 -s /bin/bash "$TESTUSER"
echo "$TESTUSER ALL=(ALL) NOPASSWD: ALL" > "/etc/sudoers.d/$TESTUSER"
chmod 440 "/etc/sudoers.d/$TESTUSER"

# systemd läuft im Container nicht als PID 1. Ein Platzhalter protokolliert,
# was install.sh aufgerufen hätte, und meldet Erfolg. Die Dienstdateien
#
# Hinweis: install.sh laeuft hier mit --standard. Seit 2026-08-26 fuehrt
# es sonst einen Assistenten mit Rueckfragen - hier antwortet niemand.
# (Ohne Terminal schaltet es selbst in den Schnellmodus, aber darauf
# soll sich der Test nicht verlassen muessen.)
# selbst werden weiter unten mit systemd-analyze richtig geprüft.
cat > /usr/local/sbin/systemctl <<'STUB'
#!/bin/bash
echo "[systemctl-platzhalter] $*" >> /var/log/systemctl-aufrufe.log
case "${1:-}" in
  is-active) exit 3 ;;   # "nicht aktiv" — install.sh nimmt den Startpfad
  *) exit 0 ;;
esac
STUB
chmod +x /usr/local/sbin/systemctl
ln -sf /usr/local/sbin/systemctl /usr/bin/systemctl
touch /var/log/systemctl-aufrufe.log && chmod 666 /var/log/systemctl-aufrufe.log

cp -r /repo $TESTHOME/PiCraft
rm -rf $TESTHOME/PiCraft/.git

# Ein frischer Klon hat KEINE mcs.conf — sie steht seit 2026-08-28 in
# .gitignore und wird von install.sh erzeugt (Befund B2). Der Test kopiert
# aber den Arbeitsbaum, in dem sie auf dem Entwicklerrechner noch liegen
# darf. Ohne dieses rm testete er also nicht die Erstinstallation, sondern
# den Sonderfall "fremde mcs.conf liegt im Repo".
rm -f $TESTHOME/PiCraft/mcs.conf
chown -R "$TESTUSER:$TESTUSER" $TESTHOME/PiCraft

trenner "1) ERSTE INSTALLATION (von null)"
su "$TESTUSER" -c "cd $TESTHOME/PiCraft && ./install.sh --standard" 2>&1 | tail -45
LAUF1=${PIPESTATUS[0]}
echo ">>> Exitcode Lauf 1: $LAUF1"

trenner "2) Ergebnis prüfen"
echo "--- Verzeichnisbaum ---"
find $TESTHOME/mcs -maxdepth 2 -not -path '*/logs/*' | sort | sed 's/^/  /'
echo "--- paper.jar ---"
if [ -f $TESTHOME/mcs/mc_server/paper.jar ]; then
  IST=$(sha256sum $TESTHOME/mcs/mc_server/paper.jar | cut -d' ' -f1)
  SOLL=$(sed -n 's/^MCS_PAPER_SHA256=//p' $TESTHOME/PiCraft/server/versions.env)
  # install.sh ruft paper-update.sh --festgelegt: Eine Erstinstallation
  # nimmt genau den Build aus versions.env, nicht den neuesten (seit
  # 03.10.2026 holt "mcs update" ohne Zusatz den neuesten).
  echo "  Prüfsumme stimmt mit der Vorgabe überein: $([ "$IST" = "$SOLL" ] && echo JA || echo NEIN) (muss JA sein)"
  cat $TESTHOME/mcs/mc_server/paper.installiert | sed 's/^/  /'
else
  echo "  FEHLT!"
fi
echo "--- Java ---"; java -version 2>&1 | head -1 | sed 's/^/  /'
echo "--- erzeugte mcs.conf (Befund B1/B2) ---"
if [ -f "$TESTHOME/mcs/mcs.conf" ]; then
  echo "  MCS_USER: $(sed -n 's/^MCS_USER=//p' "$TESTHOME/mcs/mcs.conf")  (muss $TESTUSER sein, NICHT pi)"
  echo "  MCS_DIR:  $(sed -n 's/^MCS_DIR=//p'  "$TESTHOME/mcs/mcs.conf")"
  echo "  Platzhalter uebrig: $(grep -c '__' "$TESTHOME/mcs/mcs.conf") (muss 0 sein)"
  # Die Schluessel der Spieler-Historie (v1.2). Eine frische Installation
  # bekommt sie aus mcs.conf.beispiel, eine bestehende aus deploy.sh --
  # zwei Wege, und bisher pruefte keiner von beiden den ersten.
  for SCHLUESSEL in MCS_HISTORIE_DB MCS_HISTORIE_TAGE; do
    WERT=$(sed -n "s/^${SCHLUESSEL}=//p" "$TESTHOME/mcs/mcs.conf")
    if [ -z "$WERT" ] && [ "$SCHLUESSEL" = MCS_HISTORIE_DB ]; then
      echo "  FEHLER: $SCHLUESSEL fehlt in der erzeugten mcs.conf."
      FEHLER_GEFUNDEN=1
    else
      echo "  ok  $SCHLUESSEL=$WERT"
    fi
  done
  if ! grep -q "^MCS_HISTORIE_DB=$TESTHOME/mcs/admin/historie.db$" \
       "$TESTHOME/mcs/mcs.conf"; then
    echo "  FEHLER: MCS_HISTORIE_DB zeigt nicht auf das Installationsverzeichnis."
    FEHLER_GEFUNDEN=1
  fi
  echo "  im Repo versioniert: $([ -f "$TESTHOME/PiCraft/mcs.conf" ] && echo 'JA - FEHLER' || echo 'nein, richtig')"
else
  echo "  FEHLT!"
fi
echo "--- Cronjob (der Timer hat uebernommen) ---"
su "$TESTUSER" -c "crontab -l" 2>/dev/null | sed 's/^/  /' || echo "  (keine Crontab - richtig)"
# Die vergleichbare Zeile fuer tests/muss-zeilen.py. Bis zum 23.09.2026 stand
# das "(muss LEER sein)" nur in der Ueberschrift darueber; ein uebrig
# gebliebener Eintrag liess den Lauf gruen (Zweitmeinung zu Durchgang 3).
echo "  Crontab-Eintraege: $(su "$TESTUSER" -c "crontab -l" 2>/dev/null | grep -cvE '^[[:space:]]*(#|$)') (muss 0 sein)"
echo "--- logrotate ---"
# Nicht nur anzeigen, sondern pruefen. Bis zum 21.09.2026 stand hier ein
# "head -3", also eine Anzeige ohne Aussage -- und genau in dieser Regel
# stand jahrelang player_activity.log. Die Folge auf der echten Maschine:
# Nach jeder woechentlichen Rotation war das Hauptbuch leer und die
# Spielerseite meldete fuer jeden Spieler "nicht aufgezeichnet".
if [ -f /etc/logrotate.d/picraft ]; then
  sed 's/^/  /' /etc/logrotate.d/picraft
  if grep -q "^[^#]*player_activity\.log" /etc/logrotate.d/picraft; then
    echo "  FEHLER: player_activity.log wird rotiert. Es ist ein Hauptbuch;"
    echo "          die Weboberflaeche liest es als GANZES."
    FEHLER_GEFUNDEN=1
  else
    echo "  ok  player_activity.log wird nicht rotiert (Hauptbuch)"
  fi
else
  echo "  (keine Regel - logrotate ist im Container nicht installiert)"
fi
echo "--- systemctl-Aufrufe ---"; sed 's/^/  /' /var/log/systemctl-aufrufe.log

trenner "3) Dienstdateien mit systemd-analyze prüfen"
for U in mcs.target minecraft.service mcs-playerlog.service \
         mcs-backup.service mcs-backup.timer \
         mcs-dns.service mcs-dns.timer; do
  echo "--- $U ---"
  systemd-analyze verify "/etc/systemd/system/$U" 2>&1 | sed 's/^/  /' || true
  echo "  (keine Ausgabe = keine Beanstandung)"
done

echo "--- Verdrahtung des Hauptschalters (Befund B4) ---"
for U in minecraft.service mcs-playerlog.service mcs-backup.timer mcs-dns.timer; do
  D="/etc/systemd/system/$U"
  [ -f "$D" ] || { echo "  $U: FEHLT"; continue; }
  printf '  %-24s PartOf=%-12s WantedBy=%s\n' "$U" \
    "$(sed -n 's/^PartOf=//p'   "$D" | tail -n1)" \
    "$(sed -n 's/^WantedBy=//p' "$D" | tail -n1)"
done
echo "  (beides muss mcs.target sein - sonst schaltet 'mcs aus' nicht wirklich ab)"
echo "  Backup-Uhrzeit: $(sed -n 's/^OnCalendar=//p' /etc/systemd/system/mcs-backup.timer 2>/dev/null)"

trenner "4) Startet der Server wirklich?"
# Vorher eine Konfigurationsaenderung VORMERKEN (Etappe C).
#
# Die Vormerkung ist die Antwort auf Korrektur K3: Paper schreibt die
# server.properties neu, sobald ein Befehl eine dort gespeicherte
# Einstellung aendert. Die Weboberflaeche schreibt bei laufendem Server
# deshalb nicht direkt, sondern legt die vollstaendige neue Fassung ab, und
# start-minecraft.sh schiebt sie beim naechsten Start an ihren Platz.
#
# Genau dieser Uebergang laesst sich nur hier pruefen -- er passiert
# zwischen zwei Prozessen, in dem einen Augenblick, in dem der Server noch
# nicht laeuft.
# Als TESTUSER anlegen, nicht als root: Die Weboberflaeche laeuft unter dem
# Benutzer, dem der Server gehoert, und legt sie genau so ab. Beim ersten
# Lauf am 28.08.2026 lag sie root, das "rm" scheiterte, und der Server kam
# unter "set -e" gar nicht mehr hoch. Der Startvorgang ist deshalb jetzt
# gegen jeden Fehlschlag abgesichert -- und dieser Test legt die Datei so
# an, wie sie im Betrieb wirklich entsteht.
su "$TESTUSER" -c "mkdir -p '$TESTHOME/mcs/vorgemerkt' && \
  sed 's/^motd=.*/motd=VORGEMERKT-ANGEKOMMEN/' \
      '$TESTHOME/mcs/mc_server/server.properties' \
      > '$TESTHOME/mcs/vorgemerkt/server.properties'"
echo "  Vormerkung abgelegt: motd=VORGEMERKT-ANGEKOMMEN"
echo "  motd vor dem Start:  $(sed -n 's/^motd=//p' "$TESTHOME/mcs/mc_server/server.properties")"

# Weltdaten und eine Markierung anlegen, um den zweiten Lauf zu prüfen.
su "$TESTUSER" -c "cd $TESTHOME/mcs/mc_server && bash start-minecraft.sh" > /tmp/start.log 2>&1 &
for i in $(seq 1 240); do
  if grep -q 'Done (' $TESTHOME/mcs/mc_server/logs/latest.log 2>/dev/null; then
    echo ">>> Server ist nach ${i}s oben."
    break
  fi
  sleep 1
done
grep -E 'Done \(|Starting minecraft server|ERROR|Unrecognized|Invalid -Xlog' \
  $TESTHOME/mcs/mc_server/logs/latest.log 2>/dev/null | head -5 | sed 's/^/  /'
echo "--- gc.log angelegt? ---"; ls -la $TESTHOME/mcs/mc_server/logs/gc.log 2>/dev/null | sed 's/^/  /'
echo "--- Welt erzeugt? ---"; ls -d $TESTHOME/mcs/mc_server/world* 2>/dev/null | sed 's/^/  /'

echo "--- Vorgemerkte Aenderung angekommen? (Etappe C) ---"
echo "  motd nach dem Start: $(sed -n 's/^motd=//p' "$TESTHOME/mcs/mc_server/server.properties")"
echo "  angewendet:          $(grep -qc '^motd=VORGEMERKT-ANGEKOMMEN' "$TESTHOME/mcs/mc_server/server.properties" && echo JA || echo 'NEIN - FEHLER')"
echo "  Vormerkung weggeraeumt: $([ -f "$TESTHOME/mcs/vorgemerkt/server.properties" ] && echo 'NEIN - FEHLER, sie wuerde beim naechsten Start erneut angewendet' || echo JA)"
echo "  Vorfassung liegt daneben: $(find "$TESTHOME/mcs/mc_server" -maxdepth 1 -name 'server.properties.vor-vormerkung-*' | wc -l | tr -d ' ') (muss 1 sein)"
grep -c 'Vorgemerkte Änderung angewendet' /tmp/start.log 2>/dev/null | sed 's/^/  im Startprotokoll gemeldet: /'

trenner "4b) RCON — Antworten statt nur Befehle"
# Der Unterschied zu screen: Hier kommt etwas ZURUECK. Geprueft werden die
# drei Wege, auf denen so etwas schiefgeht (Pflichtenheft Etappe B, Abnahme
# 3 bis 5): normale Antwort, sehr lange Antwort ueber mehrere Pakete, und
# ein falsches Passwort.
echo "--- Einstellungen in der server.properties ---"
grep -E '^(enable-rcon|rcon\.port|broadcast-rcon-to-ops)=' "$TESTHOME/mcs/mc_server/server.properties" | sed 's/^/  /'
echo "  rcon.password gesetzt: $(sed -n 's/^rcon\.password=//p' "$TESTHOME/mcs/mc_server/server.properties" | tail -n1 | wc -c | tr -d ' ') Zeichen (inkl. Zeilenende)"
echo "  Dateirechte: $(stat -c '%a' "$TESTHOME/mcs/mc_server/server.properties") (muss 600 sein)"

if [ -f "$TESTHOME/mcs/admin/rcon.py" ]; then
  su "$TESTUSER" -c "MCS_SERVER_PROPERTIES=$TESTHOME/mcs/mc_server/server.properties python3 - <<'PYTEST'
import sys
sys.path.insert(0, '$TESTHOME/mcs/admin')
import rcon

print('  verfuegbar:', rcon.verfuegbar())
antwort = rcon.befehl('list')
print('  list ->', repr(antwort))

# Eine Antwort ueber 4096 Byte erzwingen — nur so wird der mehrteilige
# Pfad ueberhaupt durchlaufen, und genau dort versteckt sich die Sorte
# Fehler, die man sonst erst mit einer vollen Whitelist bemerkt.
#
# Warum IP-Sperren und nicht die Whitelist? 'whitelist add' schlaegt den
# Namen bei Mojang nach (online-mode=true) und scheitert im Container an
# erfundenen Namen. 'ban-ip' mit einer echten Adresse braucht keinen
# Nachschlag.
ANZAHL = 400
# EINE Verbindung fuer alle Befehle. rcon.befehl() baut je Aufruf eine neue
# auf; vierhundert davon in Folge quittiert der Server mit dem Schliessen
# der Verbindung. Fuer den normalen Betrieb ist das egal (ein Befehl je
# Klick, ein Messwert je Minute), fuer eine Schleife nicht — und genau so
# wuerde ein Aufrufer es auch schreiben.
# Die Schleife wird abgefangen, und zwar aus einem gemessenen Grund: Am
# 01.09.2026 schloss der Server sie unter Last mitten in den 400 Befehlen.
# Ohne diesen Block riss die Ausnahme das ganze Python-Stueck ab — der
# mehrteilige Pfad wurde damit stillschweigend NICHT geprueft, und der Test
# meldete trotzdem Erfolg. In den beiden Laeufen davor lief dieselbe Stelle
# durch; es ist also nichts, was man beim einmaligen Hinsehen bemerkt.
#
# Abgefangen heisst hier NICHT verschwiegen: Kommt die Antwort nicht
# zustande, steht das als Warnung da — genauso wie unten beim einteiligen
# Fall. Ein Test, der still durchwinkt, ist schlimmer als kein Test.
lang = None
try:
    with rcon.Rcon(zeitlimit=20.0, **rcon.rcon_einstellungen()) as verbindung:
        for i in range(ANZAHL):
            verbindung.befehl('ban-ip 10.%d.%d.%d Testsperre'
                              % (i // 65536, (i // 256) % 256, i % 256))
        lang = verbindung.befehl('banlist ips')
except rcon.RconFehler as fehler:
    print('  WARNUNG: Verbindung waehrend der %d Befehle verloren (%s).' % (ANZAHL, fehler))
    print('  Der mehrteilige Pfad wurde damit NICHT geprueft.')

if lang is not None:
    print('  banlist ips -> %d Zeichen, mehrteilig: %s' % (len(lang), len(lang) > 4096))
    if len(lang) <= 4096:
        print('  WARNUNG: Antwort blieb einteilig — der mehrteilige Pfad wurde NICHT geprueft.')
    fehlend = [i for i in range(ANZAHL)
               if ('10.%d.%d.%d' % (i // 65536, (i // 256) % 256, i % 256)) not in lang]
    print('  fehlende Eintraege:', len(fehlend), '(muss 0 sein)')

werte = rcon.rcon_einstellungen()
try:
    with rcon.Rcon(passwort='definitivFalsch', port=werte['port']) as r:
        r.befehl('list')
    print('  falsches Passwort: NICHT erkannt - FEHLER')
except rcon.RconAnmeldungFehlgeschlagen:
    print('  falsches Passwort: richtig als Anmeldefehler erkannt')
except Exception as f:
    print('  falsches Passwort: FALSCHE Fehlerklasse', type(f).__name__)
PYTEST" 2>&1 | sed 's/^/  /'
else
  echo "  rcon.py nicht installiert (Weboberflaeche fehlt?)"
fi

echo "--- Aufgeteilte Module (Pflichtenheft B4) ---"
# app.py war bis 2026-08-28 eine Datei mit 980 Zeilen und ist jetzt auf zehn
# Module verteilt. Die Weboberflaeche laeuft im Container nicht (systemd ist
# ein Platzhalter), deshalb hier der entscheidende Test: Laesst sich app.py
# am ZIELORT importieren? Das schlaegt fehl, sobald ein Modul beim Kopieren
# vergessen wurde oder ein Import ins Leere zeigt.
echo "  installierte Module: $(ls "$TESTHOME/mcs/admin"/*.py 2>/dev/null | wc -l | tr -d ' ')"
find "$TESTHOME/mcs/admin" -maxdepth 1 -name '*.py' -printf '%f ' 2>/dev/null | sed 's/^/    /'; echo
su "$TESTUSER" -c "cd $TESTHOME/mcs/admin && MCS_CONF=$TESTHOME/mcs/mcs.conf python3 -c '
import app
routen = sorted(str(r) for r in app.app.url_map.iter_rules() if r.endpoint != \"static\")
print(\"  app.py importiert, %d Routen registriert\" % len(routen))
print(\"  \" + \", \".join(routen))
'" 2>&1 | sed 's/^/  /'

echo "--- Die Weboberflaeche antwortet (Etappe C) ---"
# Der Dienst laeuft im Container nicht (systemd ist ein Platzhalter). Der
# Flask-Testclient braucht ihn auch nicht: Er ruft die Seiten direkt in der
# Anwendung auf. Damit laesst sich pruefen, was sonst erst auf dem Pi
# auffiele -- eine Vorlage mit Tippfehler, ein url_for auf einen Endpunkt,
# den es nicht gibt, oder eine vergessene Datei beim Kopieren.
su "$TESTUSER" -c "cd $TESTHOME/mcs/admin && \
  MCS_CONF=$TESTHOME/mcs/mcs.conf \
  MCS_ADMIN_PASSWORD=abnahmetest \
  MCS_ADMIN_SECRET=abnahmeschluessel \
  python3 - <<'PYTEST'
import re
import app as anwendung

app = anwendung.app
app.testing = True
c = app.test_client()

# 1) Ohne Anmeldung darf nichts erreichbar sein.
offen = [p for p in ('/', '/teil/kacheln', '/api/status', '/spieler',
                     '/leistung', '/konfiguration', '/backups',
                     '/plugins', '/karte')
         if c.get(p).status_code == 200]
print('  ohne Anmeldung erreichbar:', offen or 'nichts (richtig)')

# 2) HTMX bekommt keine Umleitung, sondern einen HX-Redirect -- sonst baute
#    es die Anmeldeseite mitten in eine Kachel.
a = c.get('/teil/kacheln', headers={'HX-Request': 'true'})
print('  HTMX unangemeldet: %s, HX-Redirect: %s'
      % (a.status_code, bool(a.headers.get('HX-Redirect'))))

# 3) Falsches Passwort.
a = c.post('/anmelden', data={'benutzer': 'admin', 'passwort': 'falsch'})
print('  falsches Passwort abgewiesen:', 'stimmt nicht' in a.get_data(as_text=True), '(muss True sein)')

# 4) Richtiges Passwort.
a = c.post('/anmelden', data={'benutzer': 'admin', 'passwort': 'abnahmetest'})
print('  Anmeldung:', 'ok' if a.status_code == 302 else 'FEHLGESCHLAGEN', '(muss ok sein)')

# 4b) Ein neues Passwort meldet alle ab (seit 24.10.2026). Die Gegenprobe mit
#     dem alten zeigt, dass die erste Zeile wirklich das Passwort misst.
import sicherheit
sicherheit.ADMIN_PASSWORD = 'neu'
print('  nach Passwortwechsel abgemeldet:', c.get('/').status_code == 302, '(muss True sein)')
sicherheit.ADMIN_PASSWORD = 'abnahmetest'
print('  mit dem alten Passwort angemeldet:', c.get('/').status_code == 200, '(muss True sein)')

# 5) Jede Seite muss sich zeichnen lassen. Eine kaputte Jinja-Vorlage
#    faellt genau hier auf und nicht erst im Browser.
for pfad in ('/', '/teil/kacheln', '/teil/ereignisse', '/teil/kopfzustand',
             '/spieler', '/teil/spielerliste', '/leistung', '/teil/leistungswerte',
             '/konfiguration', '/teil/paper', '/konfiguration/datei/server.properties',
             '/konfiguration/datei/bukkit.yml',
             '/backups', '/teil/backupliste', '/plugins', '/karte'):
    a = c.get(pfad)
    print('  %-20s %s (%d Byte)' % (pfad, a.status_code, len(a.data)))

# 6) Der CSRF-Schutz. Ohne Token muss eine schreibende Anfrage scheitern --
#    sonst genuegte ein Formular auf einer fremden Seite, um den Server zu
#    stoppen.
seite = c.get('/').get_data(as_text=True)
token = re.search(r'X-CSRF-Token\": \"([^\"]+)', seite)
token = token.group(1) if token else ''
print('  Token in der Seite:', bool(token), '(muss True sein)')
print('  ohne Token abgelehnt:',
      c.post('/aktion/backup_now', data={}).status_code == 403, '(muss True sein)')
print('  mit falschem Token abgelehnt:',
      c.post('/aktion/backup_now', data={},
             headers={'X-CSRF-Token': 'quatsch'}).status_code == 403, '(muss True sein)')
print('  fremde Herkunft abgelehnt:',
      c.post('/aktion/backup_now', data={},
             headers={'X-CSRF-Token': token,
                      'Origin': 'http://fremd.invalid'}).status_code == 403, '(muss True sein)')

# 7) Ratenbegrenzung: nach fuenf Fehlversuchen ist Schluss.
c2 = app.test_client()
for _ in range(6):
    letzte = c2.post('/anmelden', data={'benutzer': 'admin', 'passwort': 'falsch'})
gesperrt = 'Fehlversuche' in letzte.get_data(as_text=True)
richtig = c2.post('/anmelden', data={'benutzer': 'admin', 'passwort': 'abnahmetest'})
print('  Ratenbegrenzung greift:', gesperrt, '(muss True sein)')
print('  auch mit richtigem Passwort gesperrt:', richtig.status_code != 302, '(muss True sein)')
PYTEST" 2>&1 | sed 's/^/  /'

echo "--- Paper-Tafel: bietet sie an, was sie soll, und nur das? ---"
# Die Notiz paper.verfuegbar schreibt sonst "mcs update --pruefen" nach
# einer Anfrage bei PaperMC. Hier wird sie vorgegeben: Geprueft wird die
# Entscheidung der Tafel, nicht das Netz. Der echte Weg samt Download ist
# am 03.10.2026 auf dem Pi gegen eine Wegwerf-Installation gelaufen.
su "$TESTUSER" -c "cd $TESTHOME/mcs/admin && \
  MCS_CONF=$TESTHOME/mcs/mcs.conf \
  MCS_ADMIN_PASSWORD=abnahmetest \
  MCS_ADMIN_SECRET=abnahmeschluessel \
  python3 - <<'PYTEST'
import paper
import app as anwendung

c = anwendung.app.test_client()
c.post('/anmelden', data={'benutzer': 'admin', 'passwort': 'abnahmetest'})
s = paper.stand()
neu = (s['build'] or 0) + 10

def notiz(version):
    paper.VERFUEGBAR.write_text('geprueft=2026-10-03T12:00:00+02:00\\n'
                                'version=%s\\nneuester_build=%d\\n'
                                'neuere_stabil=99.1\\nneuere_beta=99.2\\n' % (version, neu))

print('  ohne Notiz: Knopf zum Aktualisieren angeboten:',
      'paper/aktualisieren' in c.get('/teil/paper').get_data(as_text=True), '(muss False sein)')
notiz(s['version'])
seite = c.get('/teil/paper').get_data(as_text=True)
print('  neuer Build erkannt:', paper.stand()['neuer_build'] == neu, '(muss True sein)')
print('  Knopf nennt den neuen Build:', ('Auf Build %d aktualisieren' % neu) in seite, '(muss True sein)')
print('  Versionswechsel nur als Terminal-Hinweis:', 'mcs update --minecraft 99.1' in seite, '(muss True sein)')
print('  Knoepfe, die etwas installieren:', seite.count('paper/aktualisieren'), '(muss 1 sein)')
print('  Beta-Version als in Vorbereitung genannt:', 'In Vorbereitung: Minecraft 99.2' in seite, '(muss True sein)')
notiz('0.0')
print('  Notiz zu anderer Minecraft-Version ignoriert:',
      paper.stand()['neuer_build'] is None, '(muss True sein)')
paper.VERFUEGBAR.unlink()
PYTEST" 2>&1 | sed 's/^/  /'

echo "--- Spielerdaten: der ganze Rundlauf (Etappe C) ---"
# Der interessante Weg geht ueber drei Stationen und nicht nur ueber eine:
#
#   Oberflaeche --RCON--> Server --schreibt--> ops.json --liest--> Oberflaeche
#
# Erst wenn er ganz durchlaufen ist, weiss man, dass die Spielerseite mit
# dem arbeitet, was Paper WIRKLICH schreibt -- und nicht mit einer
# Attrappe, die zufaellig dasselbe Format hat.
#
# "op" und "whitelist add" schlagen den Namen bei Mojang nach. Der
# Container hat Internet (er hat paper.jar geladen); fehlt es, meldet der
# Test das, statt stillschweigend nichts zu pruefen.
su "$TESTUSER" -c "cd $TESTHOME/mcs/admin && \
  MCS_CONF=$TESTHOME/mcs/mcs.conf python3 - <<'PYTEST'
import spieler

print('  Weltname aus server.properties:', spieler.weltname())
print('  Whitelist eingeschaltet:', spieler.whitelist_aktiv())
print('  vorher bekannt:', [e['name'] for e in spieler.alle()] or '(niemand)')

# 1) Ueber die Oberflaeche aendern.
for was in ('op', 'whitelist_dazu'):
    art, text = spieler.aktion('Steve', was)
    print('  %-14s -> %-8s %s' % (was, art, text[:58]))

# 2) Was der Server daraus gemacht hat, wieder einlesen.
liste = spieler.alle()
print('  danach bekannt:', [e['name'] for e in liste] or '(niemand)')
for e in liste:
    print('    %-10s uuid=%-9s whitelist=%s op=%s(%s) gesperrt=%s spielzeit=%s'
          % (e['name'], (e['uuid'] or '-')[:8], e['whitelist'], e['op'],
             e['op_stufe'], e['gesperrt'], e['spielzeit'] or '-'))

steve = next((e for e in liste if e['name'] == 'Steve'), None)
if steve is None:
    print('  FEHLER: Steve taucht nicht auf -- der Rundlauf ist unterbrochen.')
else:
    print('  Rundlauf vollstaendig:', steve['op'] and steve['whitelist'])
    # Auf einem Server, auf dem nie jemand gespielt hat, gibt es keine
    # Statistikdatei. Dann muss dort ein Strich stehen und keine Null --
    # unbekannt ist etwas anderes als null Minuten.
    print('  Spielzeit ohne stats-Datei:', repr(steve['spielzeit']), '(muss None sein)')

    # Und mit Datei -- an BEIDEN Orten, an denen sie liegen kann. Seit der
    # Formatumstellung sammelt Minecraft die Spielerdateien unter
    # <welt>/players/, davor lagen sie in <welt>/stats/. Wer nur einen der
    # beiden Zweige prueft, prueft womoeglich den, den es auf dem Pi gar
    # nicht gibt: Am 29.08.2026 las die Oberflaeche ausschliesslich den
    # alten Ort, und die Spielzeit blieb auf der echten Welt immer leer.
    import json, pathlib
    from einstellungen import MCS_SERVER_DIR
    welt = pathlib.Path(MCS_SERVER_DIR) / spieler.weltname()
    for ort in ('players/stats', 'stats'):
        ordner = welt / ort
        ordner.mkdir(parents=True, exist_ok=True)
        datei = ordner / ('%s.json' % steve['uuid'])
        # json.dumps statt eines Literals: Dieser Python-Block steckt in
        # einem doppelt gequoteten su-Aufruf. Ein doppeltes
        # Anfuehrungszeichen hier wuerde diesen String beenden -- deshalb
        # kommt im ganzen Block nur einfaches Quoting vor.
        datei.write_text(json.dumps(
            {'stats': {'minecraft:custom': {'minecraft:play_time': 72000}}}))
        gemessen = spieler.spielzeit_sekunden(steve['uuid'])
        print('  Spielzeit aus %-14s -> %s s (erwartet 3600)' % (ort, gemessen))
        datei.unlink()

# 3) Wieder aufraeumen, damit der zweite Installationslauf denselben
#    Ausgangszustand vorfindet wie der erste.
for was in ('deop', 'whitelist_weg'):
    spieler.aktion('Steve', was)

# Namen mit Sonderzeichen duerfen gar nicht erst zu einem Befehl werden.
print('  Namenspruefung greift:',
      all(not spieler.name_pruefen(n) for n in ('; rm -rf /', 'a' * 17, '', 'bös')), '(muss True sein)')
print('  unbekannte Aktion abgewiesen:',
      spieler.aktion('Steve', 'server_loeschen')[0] == 'fehler', '(muss True sein)')
PYTEST" 2>&1 | sed 's/^/  /'

echo "--- Konfigurationsseite: schreiben, pruefen, vormerken (Etappe C) ---"
# Der Minecraft-Server laeuft an dieser Stelle wirklich -- aber die
# Oberflaeche fragt "laeuft er?" ueber systemctl, und das ist im Container
# ein Platzhalter, der "unbekannt" meldet. Fuer den Vormerk-Test wird der
# Zustand deshalb ausdruecklich vorgegeben.
#
# Das ist keine Schoenfaerberei: Ob die Vormerkung im Betrieb WIRKLICH
# ankommt, prueft dieser Test an anderer Stelle mit echten Dateien und
# echtem Serverstart (Abschnitte 4 und 6b). Hier geht es nur um die
# Entscheidung "direkt schreiben oder vormerken".
su "$TESTUSER" -c "cd $TESTHOME/mcs/admin && \
  MCS_CONF=$TESTHOME/mcs/mcs.conf python3 - <<'PYTEST'
import konfig

print('  Paper:', konfig.versionen()['paper'], '| Java:', konfig.versionen()['java'])
print('  offene Ports:', [(p['port'], p['wofuer']) for p in konfig.offene_ports()])

# Alle fuenfzehn Werte muessen sich lesen lassen, und keiner darf leer sein.
werte = konfig.einstellungen_lesen()
print('  kuratierte Werte:', len(werte))
leer = [e['schluessel'] for e in werte if e['wert'] in (None, '')]
print('  ohne Wert:', leer or 'keiner')
print('  Quellen:', sorted({e['quelle'] for e in werte}))

# Server gilt als GESTOPPT -> direkt schreiben.
konfig.service_state = lambda frisch=False: 'inactive'
art, text = konfig.einstellung_setzen('max-players', '7')
print('  gestoppt, max-players=7 ->', art, '| vorgemerkt:',
      konfig.vormerkung('server.properties') is not None, '(muss False sein)')
print('  in der Datei:',
      konfig.properties_lesen(konfig.datei_pfad('server.properties')).get('max-players'),
      '(muss 7 sein)')

# Server gilt als LAUFEND -> vormerken, Datei unangetastet.
konfig.service_state = lambda frisch=False: 'active'
art, text = konfig.einstellung_setzen('max-players', '9')
print('  laufend,  max-players=9 ->', art, '| vorgemerkt:',
      konfig.vormerkung('server.properties') is not None, '(muss True sein)')
print('  in der Datei weiterhin:',
      konfig.properties_lesen(konfig.datei_pfad('server.properties')).get('max-players'),
      '(muss 7 bleiben)')
print('  Unterschiede der Vormerkung:',
      [(z['schluessel'], z['vorher'], z['nachher'])
       for z in konfig.unterschiede('server.properties')])

# Eine zweite Aenderung muss auf der Vormerkung aufbauen, nicht auf der
# Datei -- sonst ginge die erste verloren.
konfig.einstellung_setzen('pvp', 'false')
print('  nach der zweiten Aenderung:',
      sorted(z['schluessel'] for z in konfig.unterschiede('server.properties')),
      '(beide muessen dabei sein)')

# Der Expertenmodus muss auf derselben Vormerkung weiterarbeiten. Bis zum
# 24.10.2026 zeigte er die Datei, und sein Speichern warf beide Aenderungen weg.
text = konfig.datei_lesen('server.properties')
print('  Expertenmodus zeigt die Vormerkung:', 'max-players=9' in text, '(muss True sein)')
konfig.datei_schreiben('server.properties', text.rstrip('\n') + '\npicraft-probe=1\n')
schluessel = {z['schluessel'] for z in konfig.unterschiede('server.properties')}
print('  nach dem Expertenmodus alle drei vorgemerkt:',
      {'max-players', 'pvp', 'picraft-probe'} <= schluessel, '(muss True sein)')

# YAML wird auch bei laufendem Server direkt geschrieben (Korrektur K3).
print('  YAML bei laufendem Server:',
      konfig.datei_schreiben('bukkit.yml', 'settings:\n  allow-end: true\n')[0],
      '| vorgemerkt:', konfig.vormerkung('bukkit.yml') is not None, '(muss False sein)')

# Wertebereiche.
for schluessel, wert in (('max-players', '999'), ('gamemode', 'gottmodus')):
    print('  %-12s = %-9s ->' % (schluessel, wert),
          konfig.einstellung_setzen(schluessel, wert)[0])

# Der Expertenmodus: Geheimnis verdeckt, YAML geprueft.
inhalt = konfig.datei_lesen('server.properties')
echt = konfig.properties_lesen(konfig.datei_pfad('server.properties')).get('rcon.password')
print('  RCON-Passwort im Editor sichtbar:', bool(echt) and echt in inhalt, '(muss False sein)')
print('  Platzhalter gesetzt:', 'rcon.password=********' in inhalt, '(muss True sein)')

print('  kaputtes YAML abgewiesen:',
      konfig.datei_schreiben('bukkit.yml', 'a:\n  b: [1, 2\n')[0] == 'fehler', '(muss True sein)')
print('  Tabulator abgewiesen:',
      konfig.datei_schreiben('bukkit.yml', 'a:\n\tb: 1\n')[0] == 'fehler', '(muss True sein)')
print('  kaputte properties abgewiesen:',
      konfig.datei_schreiben('server.properties', 'keine gueltige zeile\n')[0] == 'fehler', '(muss True sein)')
print('  fremde Datei abgewiesen:',
      konfig.datei_schreiben('../../etc/passwd', 'x')[0] == 'fehler', '(muss True sein)')
print('  fremde Datei nicht lesbar:', konfig.datei_lesen('/etc/passwd') is None, '(muss True sein)')

# Aufraeumen, damit der zweite Installationslauf nichts Vorgemerktes findet.
konfig.vormerkung_verwerfen('server.properties')
print('  Vormerkung aufgeraeumt:', not konfig.vorgemerkte(), '(muss True sein)')
PYTEST" 2>&1 | sed 's/^/  /'

echo "--- Plugins und Karte (Etappe C) ---"
# Nach der Installation liegt genau ein Plugin da (Pl3xMap). Die
# Plugin-Seite muss es finden, seinen Namen aus der plugin.yml im Jar lesen
# und es mit der plugins.txt abgleichen.
#
# Die Modrinth-Suche wird hier NICHT geprueft: Sie braucht Internet und
# fremde Server, und ein Abnahmetest, der von beidem abhaengt, meldet
# irgendwann Fehler, die keine sind. Geprueft wird stattdessen, dass die
# Absicherungen greifen, bevor ueberhaupt jemand angefragt wird.
su "$TESTUSER" -c "cd $TESTHOME/mcs/admin && \
  MCS_CONF=$TESTHOME/mcs/mcs.conf python3 - <<'PYTEST'
import plugins, seite_karte

print('  Spielversion aus paper.installiert:', plugins.spielversion() or '(leer)')
for p in plugins.uebersicht():
    print('    %-12s %-13s aktiv=%-5s datei=%s'
          % (p['name'], p['zustand'], p['aktiv'], p['datei'] or '-'))

# Name und Version kommen aus der plugin.yml IM Jar, nicht aus dem
# Dateinamen -- mit zipfile aus der Standardbibliothek, weil unzip auf
# einem schlanken Raspberry Pi OS fehlen kann.
echte = [e for e in plugins.installierte()]
print('  aus der plugin.yml gelesen:',
      [(e['name'], e['version']) for e in echte] or '(keine)')

print('  Absicherungen:')
print('    zu kurze Suche abgewiesen:  ', plugins.suchen('a')[1][:38])
print('    boese Projektkennung:       ', plugins.versionen('../../etc')[1][:38])
print('    fremde Datei umschalten:    ', plugins.umschalten('../../etc/passwd')[1][:38])

# Ein- und ausschalten durch Umbenennen: der ganze Mechanismus.
if echte:
    datei = echte[0]['datei']
    art, text = plugins.umschalten(datei)
    print('  abschalten:', art, '|', text[:46])
    nachher = {e['datei']: e['aktiv'] for e in plugins.installierte()}
    print('  jetzt abgeschaltet:', nachher.get(datei + '.disabled') is False, '(muss True sein)')
    plugins.umschalten(datei + '.disabled')
    print('  wieder eingeschaltet:',
          {e['datei']: e['aktiv'] for e in plugins.installierte()}.get(datei) is True, '(muss True sein)')

print('  Kartenserver:', seite_karte.kartenport())
PYTEST" 2>&1 | sed 's/^/  /'

echo "--- Operator-Stufe (W7): schreibt nur bei gestopptem Server ---"
#
# Warum das hier geprueft wird und nicht auf dem Pi: Die Regel dahinter ist
# gemessen (M9, 01.09.2026) und steht fest -- ops.json wird beim START
# gelesen und ueberlebt ihn, bei laufendem Server dagegen aus dem
# Arbeitsspeicher ueberschrieben. Zu pruefen bleibt, ob der Code sich daran
# haelt, und das braucht keinen laufenden Server, sondern nur eine
# Attrappe fuer service_state.
#
# Die Bloecke arbeiten in einem WEGWERF-Verzeichnis, nicht in der
# Testinstallation: Ein Test, der die ops.json der Installation umschreibt,
# waere ein zweiter Weg zu derselben Datei -- genau das Muster, das dieses
# Projekt schon 18-mal bezahlt hat.
#
# assert und nicht print: Ein Block, der nur ausgibt, faellt niemandem auf,
# wenn er das Falsche ausgibt. Eine gerissene Zusicherung wirft eine
# Ausnahme, und die faengt die Traceback-Wache in abnahme.sh ab.
su "$TESTUSER" -c "cd $TESTHOME/mcs/admin && \
  MCS_SERVER_DIR=$TESTHOME/w7-wegwerf python3 - <<'PYTEST'
import json, os, pathlib
import spieler

ORDNER = pathlib.Path(os.environ['MCS_SERVER_DIR'])
ORDNER.mkdir(parents=True, exist_ok=True)
OPS = ORDNER / 'ops.json'
OPS.write_text(json.dumps([
    {'uuid': '11111111-1111-1111-1111-111111111111', 'name': 'Alpha',
     'level': 4, 'bypassesPlayerLimit': False},
    {'uuid': '22222222-2222-2222-2222-222222222222', 'name': 'Beta',
     'level': 4, 'bypassesPlayerLimit': False},
]))
os.chmod(OPS, 0o640)

def stufen():
    return {e['name']: e['level'] for e in json.loads(OPS.read_text())}

def server(zustand):
    spieler.service_state = lambda frisch=False, *a, **k: zustand

# Laufender Server: die Datei darf nicht einmal beruehrt werden.
server('active')
vorher = OPS.read_text()
art, text = spieler.stufe_setzen('Alpha', 3)
assert art == 'fehler', (art, text)
assert OPS.read_text() == vorher, 'ops.json bei laufendem Server geschrieben!'
print('  laufender Server: verweigert, Datei unberuehrt')

# Gestoppter Server: genau ein Eintrag aendert sich.
server('inactive')
art, text = spieler.stufe_setzen('Alpha', 3)
assert art == 'gut', (art, text)
assert stufen() == {'Alpha': 3, 'Beta': 4}, stufen()
print('  gestoppt: Alpha auf 3, Beta unberuehrt')

# Die Rechte der Datei ueberleben das Schreiben, eine Sicherung liegt daneben.
assert oct(OPS.stat().st_mode & 0o777) == '0o640', oct(OPS.stat().st_mode)
assert list(ORDNER.glob('ops.json.bak-*')), 'keine Sicherung angelegt'
print('  Rechte erhalten, Sicherung daneben')

# Unsinn wird abgewiesen, ohne den vorhandenen Wert anzutasten. 2.5 steht
# ausdruecklich dabei: int(2.5) ergaebe stillschweigend 2.
for wert in (0, 5, 'drei', None, 2.5, '', '3; rm -rf /'):
    art, text = spieler.stufe_setzen('Alpha', wert)
    assert art == 'fehler', (wert, art, text)
assert stufen()['Alpha'] == 3
print('  0/5/drei/None/2.5/leer/Einschleusung abgewiesen, Wert unveraendert')

# Wer kein Operator ist, bekommt keine Stufe -- und erfaehrt, warum.
art, text = spieler.stufe_setzen('Fremder', 2)
assert art == 'fehler' and 'Operatorliste' in text, (art, text)
assert spieler.stufe_setzen('../../etc/passwd', 2)[0] == 'fehler'
print('  Nicht-Operator und ungueltiger Name abgewiesen')

# Ein Nullvorgang meldet sich als solcher statt Erfolg zu behaupten.
art, text = spieler.stufe_setzen('Alpha', 3)
assert art == 'warnung', (art, text)
print('  gleiche Stufe: als Nullvorgang gemeldet')

# Der Weg, den die Oberflaeche tatsaechlich nimmt.
art, text = spieler.aktion('Beta', 'stufe', '', '1')
assert art == 'gut' and stufen()['Beta'] == 1, (art, text, stufen())
print('  ueber aktion(was=stufe) gesetzt')

# Die uebrigen Felder muessen erhalten bleiben: Ohne UUID ist ein Eintrag
# fuer Paper wertlos.
daten = json.loads(OPS.read_text())
assert daten[0]['uuid'] == '11111111-1111-1111-1111-111111111111'
assert daten[0]['bypassesPlayerLimit'] is False
print('  UUID und uebrige Felder erhalten')
PYTEST" 2>&1 | sed 's/^/  /'

echo "--- Sind alle Vorlagen und statischen Dateien angekommen? ---"
# Der haeufigste Fehler beim Ausrollen: eine neue Datei wurde im Repository
# angelegt, aber das Kopierskript kennt nur die alten. Deshalb wird hier
# gezaehlt statt gehofft.
for VERZ in templates static; do
  IM_REPO=$(find "$TESTHOME/PiCraft/admin/$VERZ" -type f 2>/dev/null | wc -l | tr -d " ")
  AUF_PI=$(find "$TESTHOME/mcs/admin/$VERZ" -type f 2>/dev/null | wc -l | tr -d " ")
  printf "  %-10s Repo: %s  installiert: %s  %s\n" "$VERZ" "$IM_REPO" "$AUF_PI" \
    "$([ "$IM_REPO" = "$AUF_PI" ] && echo "ok" || echo "FEHLER - es fehlt etwas")"
done
echo "  Sitzungsschluessel in der .env: $(grep -c "^MCS_ADMIN_SECRET=" "$TESTHOME/mcs/admin/.env") (muss 1 sein)"
echo "  Rechte der .env: $(stat -c "%a" "$TESTHOME/mcs/admin/.env") (muss 600 sein)"

echo "--- RCON-Passwort im Konfigurations-Editor verdeckt? ---"
# Seit Etappe B steht in der server.properties ein Geheimnis. Der Editor der
# Weboberflaeche darf es nicht im Klartext ausliefern.
#
# Geprueft wird konfig.py, nicht routen.py: Bis zum 31.08.2026 gab es die
# Verdeckung ZWEIMAL, und die schwaechere in routen.py ist mit dem Endpunkt
# verschwunden, der sie benutzte (Vollpruefung, Befund 05). Dieser Test rief
# sie danach weiter auf — mit einem AttributeError, den der Lauf verschluckte:
# Der Abnahmetest blieb gruen und pruefte das Geheimnis ueberhaupt nicht mehr.
# Gefunden am 01.09.2026. "Ein Test, der still durchwinkt, ist schlimmer als
# kein Test" (Leitsatz 5) — und hier war er es zwei Etappen lang.
su "$TESTUSER" -c "cd $TESTHOME/mcs/admin && MCS_CONF=$TESTHOME/mcs/mcs.conf python3 -c '
import konfig
info = konfig.DATEIEN[\"server.properties\"]
roh = open(konfig.datei_pfad(\"server.properties\")).read()
echt = konfig.properties_lesen(konfig.datei_pfad(\"server.properties\")).get(\"rcon.password\")
verdeckt = konfig.datei_lesen(\"server.properties\")
print(\"  Geheimnisliste dieser Datei:\", info[\"geheim\"])
print(\"  Passwort ueberhaupt gesetzt:\", bool(echt), \"(muss True sein)\")
print(\"  Passwort im Klartext ausgeliefert:\", \"JA - FEHLER\" if echt and echt in verdeckt else \"nein, richtig\")
print(\"  Platzhalter gesetzt:\", \"rcon.password=\" + konfig.PLATZHALTER in verdeckt, \"(muss True sein)\")
zurueck = konfig._geheim_zuruecksetzen(verdeckt, roh, info[\"art\"], info[\"geheim\"])
print(\"  beim Speichern wiederhergestellt:\", (\"rcon.password=\" + (echt or \"\")) in zurueck, \"(muss True sein)\")
'" 2>&1 | sed 's/^/  /'
rm -rf "$TESTHOME/mcs/admin/__pycache__"

echo "--- CPU-Messung: je Aufrufer eine Probe (v1.1, W1) ---"
# Der Anlass von v1.1: Sammler (60 s) und Kacheln (5 s) teilten sich EINE
# /proc/stat-Probe. Wer sie liest, setzt sie zurueck — der Sammler mass
# danach nicht seine Minute, sondern die Restspanne seit dem letzten
# Seitenaufruf. Ueber 24 h ergab das 394 Spruenge ueber 30 Punkte bei
# durchgehend 20,0 TPS: Rauschen, kein Messwert.
su "$TESTUSER" -c "cd $TESTHOME/mcs/admin && python3 - <<'PYCPU'
import time
import system

w1, f1 = system.cpu_auslastung('sammler')
w2, f2 = system.cpu_auslastung('anzeige')
print('  erste Aufrufe frisch:      ', f1 and f2, '(muss True sein)')
print('  getrennte Proben angelegt: ', sorted(system._cpu_proben) == ['anzeige', 'sammler'], '(muss True sein)')

# Zwoelf Anzeigeaufrufe duerfen die Probe des Sammlers nicht anfassen.
vorher = dict(system._cpu_proben['sammler'])
for _ in range(12):
    system.cpu_auslastung('anzeige')
    time.sleep(0.02)
print('  Sammlerprobe unberuehrt:   ', system._cpu_proben['sammler'] == vorher,
      '(muss True sein)')

# Untergrenze: zwei Fenster sind beide 'anzeige' und wuerden sich sonst
# genauso zuruecksetzen wie frueher Sammler und Kacheln.
system.cpu_auslastung('zweifenster')
probe = dict(system._cpu_proben['zweifenster'])
wert, frisch = system.cpu_auslastung('zweifenster')
print('  unter 1 s nicht frisch:    ', frisch is False, '(muss True sein)')
print('  voriger Wert geliefert:    ', wert == probe['wert'], '(muss True sein)')
print('  Probe NICHT zurueckgesetzt:', system._cpu_proben['zweifenster'] == probe,
      '(muss True sein — sonst waere der Schutz wirkungslos)')
PYCPU" 2>&1 | sed 's/^/  /'
rm -rf "$TESTHOME/mcs/admin/__pycache__"

echo "--- Portanzeige sagt, was sie weiss (v1.1, W2) ---"
su "$TESTUSER" -c "cd $TESTHOME/mcs/admin && MCS_CONF=$TESTHOME/mcs/mcs.conf python3 - <<'PYPORT'
import konfig
ports = konfig.offene_ports()
schluessel = set(ports[0]) if ports else set()
print('  Schluessel je Port:', sorted(schluessel))
print('  prozess und fluechtig vorhanden:',
      {'prozess', 'fluechtig'} <= schluessel, '(muss True sein)')
# Die Adressnormalisierung ist der Teil, der auf echter Hardware einen
# Dienst uebersehen hat: Java lauscht als [::ffff:1.2.3.4], ip -o addr
# meldet 1.2.3.4. Ohne Vereinheitlichung vergleicht man ins Leere.
faelle = {'192.168.1.44:8091': '192.168.1.44',
          '[::ffff:192.168.1.44]:8090': '192.168.1.44',
          '0.0.0.0:22': '0.0.0.0', '[::]:22': '::', '*:25565': '*'}
print('  Adressen vereinheitlicht:',
      all(konfig._host_aus_adresse(a) == s for a, s in faelle.items()), '(muss True sein)')
print('  Rueckschleife zaehlt nicht als geliehen:',
      konfig._ist_rueckschleife('127.0.0.1') and not konfig._ist_rueckschleife('192.168.1.44'), '(muss True sein)')
PYPORT" 2>&1 | sed 's/^/  /'
rm -rf "$TESTHOME/mcs/admin/__pycache__"

echo "--- Spielerprotokoll nachtragen (v1.1, W3) ---"
# Das Werkzeug schreibt die EINZIGE dauerhafte Aufzeichnung darueber neu, wer
# wann da war. Geprueft wird deshalb mit erfundenen Protokollen und
# Platzhalternamen, und zwar genau das, was gefaehrlich waere: Verlust von
# Altbestand, doppelte Eintraege, und die Datierung ueber Mitternacht.
#
# Der Mitternachtsfall ist der Grund fuer den synthetischen Aufbau: In den
# Logzeilen steht nur [HH:MM:SS]. Auf echter Hardware kam der Fall in einem
# halben Jahr kein einziges Mal vor — die Logik waere also von den Daten nie
# geprueft worden.
PRUEF="$TESTHOME/w3"
su "$TESTUSER" -c "mkdir -p $PRUEF/logs"
su "$TESTUSER" -c "python3 - <<'PYVOR'
import gzip, os, time, pathlib
s = pathlib.Path('$PRUEF')
with gzip.open(s / 'logs' / '2026-05-10-1.log.gz', 'wt', encoding='utf-8') as f:
    f.write('[23:58:01] [Server thread/INFO]: Spieler_A[/10.0.0.5:5001] logged in with entity id 1\n')
    f.write('[23:58:02] [Server thread/INFO]: Spieler_A joined the game\n')
    f.write('[00:03:10] [Server thread/INFO]: Spieler_B joined the game\n')
    f.write('[00:07:44] [Server thread/INFO]: Spieler_A left the game\n')
lat = s / 'logs' / 'latest.log'
lat.write_text('[23:50:00] [Server thread/INFO]: Spieler_C joined the game\n'
               '[00:10:00] [Server thread/INFO]: Spieler_C lost connection: Disconnected\n',
               encoding='utf-8')
t = time.mktime(time.strptime('2026-05-12 00:20:00', '%Y-%m-%d %H:%M:%S'))
os.utime(lat, (t, t))
# Ein Altbestand, den das Werkzeug nicht verlieren darf.
(s / 'pa.log').write_text('Spieler-Aktivitaetslog (PiCraft)\n'
                          '------------------------------\n'
                          '2026-06-01 12:00:00 | Spieler_D ist dem Spiel beigetreten\n',
                          encoding='utf-8')
PYVOR"
su "$TESTUSER" -c "cd $TESTHOME/PiCraft && python3 tools/spielerprotokoll-nachtragen.py \
  --logs $PRUEF/logs --protokoll $PRUEF/pa.log" 2>&1 | tail -3 | sed 's/^/  /'
SUMME1=$(sha256sum "$PRUEF/pa.log" | cut -d" " -f1)
su "$TESTUSER" -c "cd $TESTHOME/PiCraft && python3 tools/spielerprotokoll-nachtragen.py \
  --logs $PRUEF/logs --protokoll $PRUEF/pa.log" 2>&1 | tail -2 | sed 's/^/  /'
SUMME2=$(sha256sum "$PRUEF/pa.log" | cut -d" " -f1)
echo "  zweiter Lauf aendert nichts: $([ "$SUMME1" = "$SUMME2" ] && echo "JA" || echo "NEIN - FEHLER")"
echo "  Kopfzeile erhalten:          $(head -1 "$PRUEF/pa.log" | grep -qF 'Spieler-Aktivitaetslog' && echo "JA" || echo "NEIN - FEHLER")"
echo "  Altbestand erhalten:         $(grep -c '^2026-06-01 12:00:00 | Spieler_D' "$PRUEF/pa.log") (muss 1 sein)"
echo "  Mitternacht im Archiv:       $(grep -c '^2026-05-11 00:03:10 | Spieler_B' "$PRUEF/pa.log") (muss 1 sein)"
echo "  Mitternacht in latest.log:   $(grep -c '^2026-05-12 00:10:00 | Spieler_C' "$PRUEF/pa.log") (muss 1 sein)"
echo "  Sicherung angelegt:          $([ -f "$PRUEF/pa.log.vor-nachtrag" ] && echo "JA" || echo "NEIN - FEHLER")"
echo "  aufsteigend sortiert:        $(su "$TESTUSER" -c "grep -oE '^[0-9-]+ [0-9:]+' $PRUEF/pa.log" | { L=$(cat); [ "$L" = "$(printf '%s\n' "$L" | sort)" ] && echo JA || echo "NEIN - FEHLER"; })"

# Hier stand bis zum 2026-09-02 die Pruefung W1: ob das einmalige Verwerfen
# der CPU-Altwerte wiederholbar ist. Das Werkzeug dafuer ist entfernt (die
# Umstellung ist gelaufen), und ein Test ohne Pruefling prueft nichts.

echo "--- Verlaufsdaten (Pflichtenheft B3) ---"
# Der Sammler laeuft im Dienst der Weboberflaeche; im Container laeuft der
# Dienst nicht (systemd ist ein Platzhalter). Deshalb hier ein direkter
# Test der Bausteine: Parser gegen echte Serverantworten, dann ein
# Schreib-/Lesedurchgang gegen eine echte Datenbank.
if [ -f "$TESTHOME/mcs/admin/metrik.py" ]; then
  su "$TESTUSER" -c "MCS_SERVER_PROPERTIES=$TESTHOME/mcs/mc_server/server.properties \
    MCS_METRIK_DB=$TESTHOME/mcs/admin/metrik-test.db python3 - <<'PYTEST'
import sys, time
sys.path.insert(0, '$TESTHOME/mcs/admin')
import metrik

roh_tps = metrik.rcon.befehl('tps')
roh_mspt = metrik.rcon.befehl('mspt')
tps, mspt = metrik.tps_lesen(roh_tps), metrik.mspt_lesen(roh_mspt)
print('  tps  vom Server:', repr(roh_tps[:50]), '->', tps)
print('  mspt vom Server:', repr(roh_mspt[:50]), '->', mspt)
print('  beide plausibel:', tps is not None and 0 < tps <= 20.5 and mspt is not None and mspt >= 0, '(muss True sein)')

jetzt = time.time()
for i in range(90):
    metrik.schreiben({'cpu': 10.0, 'ram': 40.0, 'platte': 9.0, 'temp': 50.0,
                      'tps': tps, 'mspt': mspt, 'spieler': 0}, zeitpunkt=jetzt - i * 60)
print('  90 Minuten geschrieben, Anzahl:', metrik.anzahl())
print('  verlauf(1h):', len(metrik.verlauf(stunden=1)), 'Punkte')
metrik.schreiben({'cpu': 1.0}, zeitpunkt=jetzt - 30 * 86400)
print('  ein 30 Tage alter Wert dazu:', metrik.anzahl(), '(muss 91 sein)')
metrik.aufraeumen()
print('  nach aufraeumen (Grenze 7 Tage):', metrik.anzahl(), '(muss wieder 90 sein)')
PYTEST" 2>&1 | sed 's/^/  /'
else
  echo "  metrik.py nicht installiert"
fi
rm -f "$TESTHOME/mcs/admin/metrik-test.db"*

echo "--- mcs rcon ---"
su "$TESTUSER" -c "mcs rcon list" 2>&1 | sed 's/^/  /'

echo "--- Mitinstallierte Plugins (Lastenheft 5.8: nur Pl3xMap) ---"
find "$TESTHOME/mcs/mc_server/plugins" -maxdepth 1 -name '*.jar' -printf '  %f\n' 2>/dev/null \
  || echo "  (keine)"
echo "  Anzahl .jar: $(find "$TESTHOME/mcs/mc_server/plugins" -maxdepth 1 -name '*.jar' 2>/dev/null | wc -l | tr -d ' ') (muss 1 sein)"

trenner "5) Backup im laufenden Betrieb"
su "$TESTUSER" -c "bash $TESTHOME/mcs/mcs_backup/minecraft-backup.sh" 2>&1 | tail -8 | sed 's/^/  /'

trenner "5z) Das Archiv traegt seinen Namen erst nach der Pruefung (Lastenheft 5.4)"
# Bis 2026-08-30 schrieb tar direkt nach backup_<zeit>.tar.gz. Ein harter
# Abbruch (Stromausfall, OOM-Killer) hinterliess damit eine halbe Datei, die
# fuer die Rotation wie ein gueltiges Backup aussah — und in `mcs status`
# als "Backup von heute Nacht" gemeldet wurde. Also ein Backup, das es nicht
# gibt, das aber ein echtes verdraengt und dabei Entwarnung gibt.
echo "  keine Rohdatei uebrig: $(find "$TESTHOME/mcs/mcs_backup" -maxdepth 1 -name '.unfertig-backup_*' | wc -l | tr -d ' ') (muss 0 sein)"

# Der eigentliche Beweis: Eine liegengebliebene Rohdatei darf NIRGENDS als
# Backup zaehlen. Nachgestellt mit einer Datei, die groesser ist als jedes
# echte Archiv hier — sie wuerde also auffallen, wenn sie mitgezaehlt wird.
head -c 2000000 /dev/zero > "$TESTHOME/mcs/mcs_backup/.unfertig-backup_2099-01-01_00-00-00.tar.gz"
chown "$TESTUSER:$TESTUSER" "$TESTHOME/mcs/mcs_backup/.unfertig-backup_2099-01-01_00-00-00.tar.gz"
ECHTE=$(find "$TESTHOME/mcs/mcs_backup" -maxdepth 1 -name 'backup_*.tar.gz' | wc -l | tr -d ' ')
echo "  echte Archive: $ECHTE"
echo "--- sieht 'mcs status' die Rohdatei? ---"
su "$TESTUSER" -c "mcs status" 2>&1 | grep -E "Letztes Backup" | sed 's/^/  /'
echo "  (muss $ECHTE Stueck melden und NICHT 2099)"
echo "--- sieht 'mcs restore' sie? ---"
# Wert und Sollwert in EINER Zeile, damit tests/muss-zeilen.py sie liest (im
# ersten echten Lauf am 24.09.2026 stand beides auf zwei Zeilen und blieb
# ungeprueft).
echo "  Treffer 2099: $(su "$TESTUSER" -c "mcs restore" 2>&1 | grep -c "2099-01-01") (muss 0 sein)"
rm -f "$TESTHOME/mcs/mcs_backup/.unfertig-backup_2099-01-01_00-00-00.tar.gz"

trenner "5a) Benachrichtigung — sie darf das Backup NIE aufhalten (Etappe D)"
# Die gefaehrlichste Stelle des ganzen Pakets ist nicht die Nachricht,
# sondern das, was passiert, wenn sie NICHT rausgeht.
#
# Das Backup-Skript laeuft unter "set -e". Ein misslungener Versand — kein
# Netz, ntfy nicht erreichbar, falsches Thema — wuerde ohne die "|| true"
# in benachrichtigen() das Backup abbrechen. Dann kostete die Meldung genau
# das Backup, das sie melden soll, und zwar jede Nacht.
#
# Geprueft wird deshalb mit einem Server, der garantiert nicht antwortet.
echo "  Skript auf dem Pi:  $([ -x "$TESTHOME/mcs/benachrichtigung.sh" ] && echo "da" || echo "FEHLT - install.sh kopiert es nicht")"
echo "  mcs.conf kennt MCS_NTFY_THEMA: $(grep -c '^MCS_NTFY_THEMA=' "$TESTHOME/mcs/mcs.conf") (muss 1 sein)"

echo "--- nicht eingerichtet: muss 78 liefern und schweigen ---"
AUSGABE=$(su "$TESTUSER" -c "$TESTHOME/mcs/benachrichtigung.sh 'T' 'X'" 2>&1); RC=$?
echo "  Exitcode: $RC (muss 78 sein), Ausgabe: \"$AUSGABE\" (muss leer sein)"

echo "--- eingerichtet, aber Server unerreichbar ---"
# 127.0.0.1:1 nimmt niemand entgegen: curl scheitert sofort, ohne Wartezeit.
sed -i 's#^MCS_NTFY_THEMA=.*#MCS_NTFY_THEMA=mcs-abnahmetest#' "$TESTHOME/mcs/mcs.conf"
sed -i 's#^MCS_NTFY_SERVER=.*#MCS_NTFY_SERVER=http://127.0.0.1:1#' "$TESTHOME/mcs/mcs.conf"
su "$TESTUSER" -c "$TESTHOME/mcs/benachrichtigung.sh 'T' 'X'" >/dev/null 2>&1
echo "  Exitcode allein aufgerufen: $? (muss 1 sein — Versand schlug fehl)"

BACKUPS_VORHER=$(find "$TESTHOME/mcs/mcs_backup" -name 'backup_*.tar.gz' | wc -l | tr -d ' ')
su "$TESTUSER" -c "bash $TESTHOME/mcs/mcs_backup/minecraft-backup.sh" >/dev/null 2>&1
RC_BACKUP=$?
BACKUPS_NACHHER=$(find "$TESTHOME/mcs/mcs_backup" -name 'backup_*.tar.gz' | wc -l | tr -d ' ')
echo "  Backup mit totem ntfy-Server: Exitcode $RC_BACKUP (muss 0 sein)"
echo "  Archive vorher/nachher: $BACKUPS_VORHER -> $BACKUPS_NACHHER (muss um 1 gewachsen sein)"

# Und jetzt der Fehlerpfad: Liegt ein Merkzettel, muss der naechste
# erfolgreiche Lauf ihn wegraeumen — und dabei die Entwarnung anstossen,
# ohne daran zu scheitern.
echo "  Testfehlschlag notiert" > "$TESTHOME/mcs/mcs_backup/.letzter-fehler"
su "$TESTUSER" -c "bash $TESTHOME/mcs/mcs_backup/minecraft-backup.sh" >/dev/null 2>&1
echo "  Lauf nach Fehlschlag (mit Entwarnungsversuch): Exitcode $? (muss 0 sein)"
echo "  Merkzettel weggeraeumt: $([ -f "$TESTHOME/mcs/mcs_backup/.letzter-fehler" ] && echo "NEIN - FEHLER" || echo "ja")"

# Aufraeumen: Die uebrigen Abschnitte sollen nicht in jeden toten Server rennen.
sed -i 's#^MCS_NTFY_THEMA=.*#MCS_NTFY_THEMA=#' "$TESTHOME/mcs/mcs.conf"
sed -i 's#^MCS_NTFY_SERVER=.*#MCS_NTFY_SERVER=https://ntfy.sh#' "$TESTHOME/mcs/mcs.conf"

trenner "5b) Backup pruefen (mcs restore --probe, Etappe C)"
# Neu in Etappe C. "Wir haben Backups" ist eine Behauptung; "wir haben
# gepruefte Backups" ist eine Aussage. Der Unterschied faellt erst auf,
# wenn man eines braucht.
#
# Das Backup-Skript prueft jedes Archiv direkt nach dem Packen. --probe ist
# die zweite, spaetere Pruefung: Sie packt das Archiv wirklich aus, statt
# nur das Inhaltsverzeichnis zu lesen -- ein beschaedigtes Archiv hat oft
# ein voellig intaktes Verzeichnis.
NEUESTES=$(find "$TESTHOME/mcs/mcs_backup" -name 'backup_*.tar.gz' | head -n1)
if [ -n "$NEUESTES" ]; then
  su "$TESTUSER" -c "mcs restore '$NEUESTES' --probe" 2>&1 | sed 's/^/  /'
  echo "  Exitcode: ${PIPESTATUS[0]}"

  echo "--- und ein absichtlich beschaedigtes Archiv ---"
  # Ein Archiv, dessen Inhaltsverzeichnis stimmt, dessen Daten aber kaputt
  # sind. Genau der Fall, den eine Pruefung finden muss und ein Blick ins
  # Verzeichnis nicht.
  cp "$NEUESTES" /tmp/kaputt.tar.gz
  dd if=/dev/urandom of=/tmp/kaputt.tar.gz bs=1024 seek=200 count=64 \
     conv=notrunc status=none
  chown "$TESTUSER:$TESTUSER" /tmp/kaputt.tar.gz
  su "$TESTUSER" -c "mcs restore /tmp/kaputt.tar.gz --probe" >/tmp/probe2.log 2>&1
  echo "  Exitcode: $? (muss ungleich 0 sein)"
  grep -iE 'FEHLGESCHLAGEN|nicht' /tmp/probe2.log | head -3 | sed 's/^/    /'
  rm -f /tmp/kaputt.tar.gz
else
  echo "  Kein Archiv gefunden -- nichts zu pruefen."
fi

echo "--- Die Backup-Seite der Oberflaeche ---"
su "$TESTUSER" -c "cd $TESTHOME/mcs/admin && \
  MCS_CONF=$TESTHOME/mcs/mcs.conf python3 - <<'PYTEST'
import backups

eintraege = backups.liste()
print('  gefundene Archive:', [(e['name'][:24], e['herkunft']) for e in eintraege])
z = backups.zustand(eintraege)
print('  Zustand: %d Archive, zu alt: %s, kein Backup: %s, Fehler: %r'
      % (z['anzahl'], z['zu_alt'], z['keines'], z['fehler'][:30]))
print('  Zeitplan:', backups.einstellungen()['uhrzeit'] or '(nicht ermittelbar)')

# Die Absicherungen. Sie sind der eigentliche Grund, warum es dieses Modul
# gibt: Wiederherstellen tauscht Weltdaten aus, Loeschen ist endgueltig.
name = eintraege[0]['name'] if eintraege else 'nichts.tar.gz'
print('  fremder Pfad abgewiesen:',
      backups.pruefen('../../etc/passwd')[0] == 'fehler', '(muss True sein)')
print('  ohne abgetippten Namen abgewiesen:',
      backups.wiederherstellen(name, 'ja')[0] == 'fehler', '(muss True sein)')
print('  neuestes Backup nicht loeschbar:',
      backups.loeschen(name, name)[0] == 'fehler', '(muss True sein)')
backups.service_state = lambda frisch=False: 'active'
print('  bei laufendem Server kein Restore:',
      backups.wiederherstellen(name, name)[0] == 'fehler', '(muss True sein)')
print('  ungueltiges Zweitziel abgewiesen:',
      backups.zweitziel_setzen('/gibt/es/nicht')[0] == 'fehler', '(muss True sein)')
PYTEST" 2>&1 | sed 's/^/  /'

trenner "6) Sauber stoppen"
su "$TESTUSER" -c "cd $TESTHOME/mcs/mc_server && bash stop-minecraft.sh" 2>&1 | sed 's/^/  /'
echo ">>> Exitcode stop: $?"
grep -cE 'Saved the game|ThreadedAnvilChunkStorage: All dimensions are saved|All chunks are saved' \
  $TESTHOME/mcs/mc_server/logs/latest.log 2>/dev/null | sed 's/^/  Speicher-Bestätigungen im Log: /'

trenner "6b) Eine unloeschbare Vormerkung darf den Start NICHT verhindern"
# Der Fehler, den der erste Lauf dieses Tests am 28.08.2026 gefunden hat:
# start-minecraft.sh laeuft unter "set -e". Eine Vormerkung, die dem
# Serverbenutzer nicht gehoert, liess sich nicht loeschen, das "rm"
# scheiterte -- und der Server startete gar nicht mehr.
#
# Eine Einstellung, die nicht ankommt, ist aergerlich. Ein Server, der
# deswegen nicht hochkommt, ist ein Ausfall. Genau das wird hier geprueft.
mkdir -p "$TESTHOME/mcs/vorgemerkt"
sed 's/^motd=.*/motd=UNLOESCHBAR/' "$TESTHOME/mcs/mc_server/server.properties" \
  > "$TESTHOME/mcs/vorgemerkt/server.properties"
chown root:root "$TESTHOME/mcs/vorgemerkt" "$TESTHOME/mcs/vorgemerkt/server.properties"
chmod 755 "$TESTHOME/mcs/vorgemerkt"
echo "  Vormerkung gehoert root, Verzeichnis ist fuer den Serverbenutzer schreibgeschuetzt."

# Das alte Log beiseite legen. Sonst findet die Suche unten das "Done (" des
# VORIGEN Laufs und meldet Erfolg, ohne dass der Server ueberhaupt gestartet
# waere -- ein Test, der immer gruen ist, prueft nichts.
mv "$TESTHOME/mcs/mc_server/logs/latest.log" "$TESTHOME/mcs/mc_server/logs/vorher.log" 2>/dev/null || true

su "$TESTUSER" -c "cd $TESTHOME/mcs/mc_server && bash start-minecraft.sh" > /tmp/start2.log 2>&1 &
OBEN=nein
for i in $(seq 1 180); do
  if grep -q 'Done (' "$TESTHOME/mcs/mc_server/logs/latest.log" 2>/dev/null; then
    echo "  Server kam trotzdem hoch (nach ${i}s) - richtig."
    OBEN=ja
    break
  fi
  sleep 1
done
if [ "$OBEN" = nein ]; then
  echo "  FEHLER: Der Server kam NICHT hoch. Eine liegengebliebene Vormerkung"
  echo "  darf den Start niemals verhindern."
  tail -8 /tmp/start2.log | sed 's/^/    /'
fi
echo "  Meldung im Protokoll: $(grep -c 'ließ sich aber nicht' /tmp/start2.log) (muss 1 sein)"
echo "  motd trotzdem angewendet: $(sed -n 's/^motd=//p' "$TESTHOME/mcs/mc_server/server.properties")"
su "$TESTUSER" -c "cd $TESTHOME/mcs/mc_server && bash stop-minecraft.sh" >/dev/null 2>&1
rm -rf "$TESTHOME/mcs/vorgemerkt"

trenner "7) Markierung setzen, dann ZWEITE INSTALLATION"
# Die Welt heisst NICHT zwangslaeufig "world" - der Name steht in
# server.properties und wird vom Installationsassistenten abgefragt. Bis
# 2026-08-26 stand hier "world" fest verdrahtet; als die Vorlage einen
# anderen Namen bekam, schrieb der Test seine Pruefmarke ins Leere und
# meldete trotzdem Erfolg. Ein Test, der nichts mehr prueft, ist
# schlimmer als keiner.
WELT_NAME=$(grep '^level-name=' $TESTHOME/mcs/mc_server/server.properties | cut -d= -f2)
WELT_DIR="$TESTHOME/mcs/mc_server/${WELT_NAME}"
if [ ! -d "$WELT_DIR" ]; then
  echo "  FEHLER: Weltverzeichnis $WELT_DIR gibt es nicht - Test kann nichts pruefen."
  exit 1
fi
echo "  Welt laut server.properties: $WELT_NAME"
echo "DIESE-DATEI-MUSS-UEBERLEBEN" > "$WELT_DIR/pruefmarke.txt"
WELT_VORHER=$(find "$WELT_DIR" -type f | wc -l)
sed -i 's/^view-distance=16/view-distance=12/' $TESTHOME/mcs/mc_server/server.properties
echo ">>> Weltdateien vor Lauf 2: $WELT_VORHER"
# Vollstaendig mitschreiben, dann gezielt pruefen. Der Hinweis auf eine
# bestehende Installation kommt frueh; danach folgt die komplette
# Installation. Mit "tail" waere er nie sichtbar - und ein Test, der nur die
# letzten Zeilen anschaut, prueft ihn ueberhaupt nicht.
su "$TESTUSER" -c "cd $TESTHOME/PiCraft && ./install.sh --standard" > /tmp/lauf2.log 2>&1
LAUF2=$?
tail -40 /tmp/lauf2.log
echo ">>> Exitcode Lauf 2: $LAUF2"

echo "--- Verhalten beim Zweitlauf ---"
if grep -q 'bereits eine Installation' /tmp/lauf2.log; then
  echo "  ok      Hinweis auf bestehende Installation erschien"
else
  echo "  FEHLT   Hinweis auf bestehende Installation"
fi
if grep -q 'bleibt unangetastet' /tmp/lauf2.log; then
  echo "  ok      server.properties als unangetastet angekuendigt"
else
  echo "  FEHLT   Ankuendigung zu server.properties"
fi

trenner "8) Kein Datenverlust?"
WELT_NACHHER=$(find "$WELT_DIR" -type f | wc -l)
echo "  Weltdateien nachher:      $WELT_NACHHER (vorher $WELT_VORHER)"
echo "  Prüfmarke noch da:        $(cat "$WELT_DIR/pruefmarke.txt" 2>/dev/null || echo 'WEG!!!')"
echo "  view-distance unangetastet: $(grep '^view-distance=' $TESTHOME/mcs/mc_server/server.properties)  (muss 12 bleiben)"
echo "  Backups noch da:          $(find $TESTHOME/mcs/mcs_backup -name 'backup_*.tar.gz' | wc -l)"
echo "  paper.jar unverändert:    $(sha256sum $TESTHOME/mcs/mc_server/paper.jar | cut -c1-16)..."
echo "  Cronjob entfernt:         $(su "$TESTUSER" -c 'crontab -l' 2>/dev/null | grep -c minecraft-backup.sh) Eintrag/Einträge (muss 0 sein)"
echo "  mcs.conf unverändert:     $(sed -n 's/^MCS_USER=//p' "$TESTHOME/mcs/mcs.conf")  (muss $TESTUSER sein)"

trenner "9) mcs-Kommando"
su "$TESTUSER" -c "mcs version" 2>&1 | sed 's/^/  /'
echo "--- kennt mcs den Hauptschalter? ---"
su "$TESTUSER" -c "mcs hilfe" 2>&1 | grep -E '^  mcs (an|aus) ' | sed 's/^/  /' \
  || echo "  FEHLT - 'mcs an'/'mcs aus' stehen nicht im Hilfetext"
echo "--- mcs status (Auszug) ---"
su "$TESTUSER" -c "mcs status" 2>&1 | tail -12 | sed 's/^/  /'

trenner "10) deploy.sh — fasst es die Konfiguration des Pi an?"
# Befund B2: Bis 2026-08-28 hat deploy.sh die Repo-Fassung von mcs.conf ueber
# die des Pi kopiert. Wer eigene Pfade eingetragen hatte, verlor sie bei jedem
# Ausrollen. Jetzt darf es sie nur noch vergleichen.
echo "MCS_BACKUP_BEHALTEN=99" >> "$TESTHOME/mcs/mcs.conf"
VORHER=$(sha256sum "$TESTHOME/mcs/mcs.conf" | cut -d" " -f1)

# Dasselbe fuer plugins.txt (Etappe C, Entscheidung E6). Die Weboberflaeche
# traegt dort installierte Plugins ein; wuerde deploy.sh die Repo-Fassung
# darueberkopieren, waere jede Installation beim naechsten Ausrollen weg.
echo "Testplugin|1.0|https://beispiel.invalid/t.jar|0000" >> "$TESTHOME/mcs/mc_server/plugins.txt"
PLUGINS_VORHER=$(sha256sum "$TESTHOME/mcs/mc_server/plugins.txt" | cut -d" " -f1)

# Die Backup-Uhrzeit (v1.1, E20). Sie ist der Grund fuer das Drop-in: Sie
# steht in OnCalendar, systemd liest das nicht aus einer EnvironmentFile, und
# die Einheit selbst gehoert der Vorlage — deploy.sh ersetzt sie. Stuende die
# Zeit dort, waere sie nach jedem Ausrollen stillschweigend wieder 04:00.
ZEIT_DROPIN="/etc/systemd/system/mcs-backup.timer.d/zeit.conf"
sudo mkdir -p "$(dirname "$ZEIT_DROPIN")"
printf '[Timer]\nOnCalendar=\nOnCalendar=Mon..Fri 05:17:00\n' | sudo tee "$ZEIT_DROPIN" >/dev/null
ZEIT_VORHER=$(sha256sum "$ZEIT_DROPIN" | cut -d" " -f1)
echo "  Backup-Uhrzeit von Hand gesetzt: $(sed -n 's/^OnCalendar=\(..*\)/\1/p' "$ZEIT_DROPIN" | tail -n1)"

echo "--- ./deploy.sh --probe ---"
su "$TESTUSER" -c "cd $TESTHOME/PiCraft && MCS_CONF=$TESTHOME/mcs/mcs.conf ./deploy.sh --probe" 2>&1 | tail -12
echo ">>> Exitcode probe: $?"

echo "--- Aktualisierungsweg: was deploy.sh auf einer BESTEHENDEN Installation nachtraegt ---"
# Genau der Weg, den ein gepflegter Pi geht: Er hat schon eine .env, und
# install-admin.sh legt die neuen Werte nur an, wenn es die Datei ERSTMALS
# schreibt. Ein Wert, den niemand von Hand waehlt, darf nicht in einer
# Anleitung stehen -- deploy.sh muss ihn nachtragen.
sed -i '/^MCS_ADMIN_SECRET=/d' "$TESTHOME/mcs/admin/.env"
echo "  Sitzungsschluessel entfernt (wie auf einer Installation von vor Etappe C)"
echo "  vorhanden: $(grep -c '^MCS_ADMIN_SECRET=' "$TESTHOME/mcs/admin/.env") (muss 0 sein)"

echo "--- ./deploy.sh (echt) ---"
su "$TESTUSER" -c "cd $TESTHOME/PiCraft && MCS_CONF=$TESTHOME/mcs/mcs.conf ./deploy.sh" >/dev/null 2>&1
NACHHER=$(sha256sum "$TESTHOME/mcs/mcs.conf" | cut -d" " -f1)
echo "  mcs.conf unangetastet:    $([ "$VORHER" = "$NACHHER" ] && echo "JA" || echo "NEIN - FEHLER, deploy hat sie ueberschrieben")"
echo "  eigener Wert ueberlebt:   $(grep -c "^MCS_BACKUP_BEHALTEN=99" "$TESTHOME/mcs/mcs.conf") (muss 1 sein)"
echo "  deploy legt keine mcs.conf im Repo an: $([ -f "$TESTHOME/PiCraft/mcs.conf" ] && echo "DOCH - FEHLER" || echo "richtig")"
echo "  Sitzungsschluessel nachgetragen: $(grep -c '^MCS_ADMIN_SECRET=' "$TESTHOME/mcs/admin/.env") (muss 1 sein)"
echo "  Laenge:                          $(sed -n 's/^MCS_ADMIN_SECRET=//p' "$TESTHOME/mcs/admin/.env" | tr -d '\n' | wc -c | tr -d ' ') Zeichen (muss 48 sein)"
echo "  .env immer noch 600:             $(stat -c '%a' "$TESTHOME/mcs/admin/.env")"
echo "  Passwort unangetastet:           $(grep -c '^MCS_ADMIN_PASSWORD=' "$TESTHOME/mcs/admin/.env") (muss 1 sein)"
PLUGINS_NACHHER=$(sha256sum "$TESTHOME/mcs/mc_server/plugins.txt" | cut -d" " -f1)
echo "  plugins.txt unangetastet: $([ "$PLUGINS_VORHER" = "$PLUGINS_NACHHER" ] && echo "JA" || echo "NEIN - FEHLER, deploy hat sie ueberschrieben")"
echo "  eigener Eintrag ueberlebt: $(grep -c "^Testplugin|" "$TESTHOME/mcs/mc_server/plugins.txt") (muss 1 sein)"
echo "  im Repo liegt nur die Vorlage: $([ -f "$TESTHOME/PiCraft/server/plugins.txt" ] && echo "NEIN - FEHLER" || echo "richtig")"

# --- v1.1: Backup-Uhrzeit und Versionsanzeige ------------------------------
ZEIT_NACHHER=$(sha256sum "$ZEIT_DROPIN" | cut -d" " -f1)
echo "  Backup-Uhrzeit ueberlebt deploy: $([ "$ZEIT_VORHER" = "$ZEIT_NACHHER" ] && echo "JA" || echo "NEIN - FEHLER, deploy hat das Drop-in angefasst")"
echo "  gilt weiterhin:                  $(sed -n 's/^OnCalendar=\(..*\)/\1/p' "$ZEIT_DROPIN" | tail -n1) (muss Mon..Fri 05:17:00 sein)"
echo "  Einheit traegt wieder die Vorgabe: $(sed -n 's/^OnCalendar=//p' /etc/systemd/system/mcs-backup.timer | tail -n1)"

# Welcher Stand ist ausgerollt? Nicht die Nummer im Repo ist die Frage,
# sondern was hier wirklich angekommen ist (E19).
echo "  VERSION ausgerollt:       $(cat "$TESTHOME/mcs/VERSION" 2>/dev/null || echo 'FEHLT - FEHLER')"
echo "  Stand festgeschrieben:    $(sed -n 's/^MCS_STAND=//p' "$TESTHOME/mcs/ausgerollt" 2>/dev/null || echo 'FEHLT - FEHLER')"
echo "  womit:                    $(sed -n 's/^MCS_STAND_WOMIT=//p' "$TESTHOME/mcs/ausgerollt" 2>/dev/null)"
su "$TESTUSER" -c "cd $TESTHOME/mcs/admin && MCS_CONF=$TESTHOME/mcs/mcs.conf python3 -c '
import version
s = version.stand()
print(\"  Fusszeile zeigt:          \", s[\"installation\"], \"| Abweichung:\", s[\"abweichung\"], \"(muss False sein)\")
'" 2>&1 | sed 's/^/  /'
rm -rf "$TESTHOME/mcs/admin/__pycache__"

trenner "10b) Erreichbarkeitstest (Etappe D)"
# Was hier NICHT geprueft wird: ob dieser Container aus dem Internet
# erreichbar ist. Das haengt am Anschluss, nicht am Rechner, und gehoert
# nach PRUEFEN-AUF-DEM-PI.md.
#
# Geprueft wird das, was schiefgehen kann, ohne dass es auffaellt: die
# Einordnung. Ein Test, der "nicht erreichbar" sagt, wo "konnte nicht
# gefragt werden" richtig waere, schickt jemanden auf die Suche nach einem
# Problem, das er vielleicht nicht hat.
echo "  Skript auf dem Pi: $([ -x "$TESTHOME/mcs/erreichbarkeit.sh" ] && echo "da" || echo "FEHLT")"

echo "--- ohne Netzzugriff: liefert es ueberhaupt lesbares JSON? ---"
su "$TESTUSER" -c "$TESTHOME/mcs/erreichbarkeit.sh --lokal --json" > /tmp/erreich.json 2>/dev/null
if jq -e . /tmp/erreich.json >/dev/null 2>&1; then
  echo "  ok      gueltiges JSON, Urteil: $(jq -r .urteil_art /tmp/erreich.json)"
else
  echo "  FEHLER  keine lesbare JSON-Ausgabe:"; head -3 /tmp/erreich.json | sed 's/^/    /'
fi

echo "--- Einordnung des Anschlusses (mit Attrappen) ---"
# Die Attrappen liegen in einem eigenen Verzeichnis und werden nur diesen
# Aufrufen vorangestellt. Danach ist wieder alles echt.
#
# DREI Attrappen, nicht nur curl — und das ist eine Lehre aus dem ersten
# Lauf dieses Abschnitts: Er steht NACH "6) Sauber stoppen", also mit
# gestopptem Server. Das Skript urteilte deshalb voellig richtig
# "server-aus" und kam nie bis zur Einordnung des Anschlusses. Vier
# FEHLER-Zeilen, und keine davon lag am Skript.
#
# Wer einen spaeteren Zweig pruefen will, muss die frueheren erfuellen.
mkdir -p /tmp/attrappe
cat > /tmp/attrappe/curl <<'STUB'
#!/bin/bash
ZIEL="${!#}"
case "$ZIEL" in
  *checkipv4*) [ -n "${STUB_OEFF4:-}" ] && { echo "$STUB_OEFF4"; exit 0; }; exit 7 ;;
  *checkipv6*) exit 7 ;;
  *mcsrvstat*) [ -n "${STUB_ONLINE:-}" ] && { echo "{\"online\":${STUB_ONLINE}}"; exit 0; }; exit 7 ;;
esac
exit 7
STUB
# "Der Dienst laeuft" — sonst endet der Test beim ersten Zweig.
cat > /tmp/attrappe/systemctl <<'STUB'
#!/bin/bash
[ "${1:-}" = is-active ] && { echo active; exit 0; }
exec /usr/local/sbin/systemctl "$@"
STUB
# "Auf dem Port lauscht etwas" — sonst endet der Test beim zweiten Zweig.
cat > /tmp/attrappe/ss <<'STUB'
#!/bin/bash
echo "State Recv-Q Send-Q Local-Address:Port Peer"
echo "LISTEN 0 128 *:25565 *:*"
STUB
chmod 755 /tmp/attrappe/curl /tmp/attrappe/systemctl /tmp/attrappe/ss
chmod 777 /tmp/attrappe

urteil() {  # $1 Name  $2 erwartet  Rest: Umgebung
  local NAME="$1" ERW="$2"; shift 2
  local ART
  ART=$(su "$TESTUSER" -c "env $* PATH=/tmp/attrappe:\$PATH $TESTHOME/mcs/erreichbarkeit.sh --json" 2>/dev/null | jq -r .urteil_art 2>/dev/null)
  if [ "$ART" = "$ERW" ]; then printf "  ok      %-32s -> %s\n" "$NAME" "$ART"
  else printf "  FEHLER  %-32s -> %s   erwartet: %s\n" "$NAME" "${ART:-<nichts>}" "$ERW"; fi
}
urteil "CGNAT 100.90.x"           dslite         STUB_OEFF4=100.90.5.7
urteil "100.63.x ist KEIN CGNAT"  keine-freigabe STUB_OEFF4=100.63.0.1 STUB_ONLINE=false
urteil "erreichbar"               gut            STUB_OEFF4=203.0.113.7 STUB_ONLINE=true
urteil "Pruefdienst schweigt"     unklar         STUB_OEFF4=203.0.113.7

echo "--- \"online\": false darf NICHT zu \"unbekannt\" werden ---"
# Diese eine Zeile ist der Grund fuer diesen ganzen Abschnitt. Zuerst stand
# im Skript  jq -r '.online // "fehlt"'  — und "//" liefert in jq die rechte
# Seite auch bei "false". Ein sauber gemeldetes "nicht erreichbar" wurde
# damit zu "konnte nicht gefragt werden": genau die Verwechslung, die der
# Test vermeiden soll, und im Betrieb unsichtbar, weil beides plausibel
# aussieht.
V4=$(su "$TESTUSER" -c "env STUB_OEFF4=203.0.113.7 STUB_ONLINE=false PATH=/tmp/attrappe:\$PATH $TESTHOME/mcs/erreichbarkeit.sh --json" 2>/dev/null | jq -r .v4_erreichbar 2>/dev/null)
echo "  v4_erreichbar = ${V4:-<nichts>} $([ "$V4" = nein ] && echo "(ok)" || echo "(FEHLER - muss nein sein)")"
rm -rf /tmp/attrappe

trenner "10c) DNS-Modul (Etappe D)"
# Was hier NICHT geprueft wird: ein echter Eintrag bei deSEC oder DuckDNS.
# Dafuer braucht es ein Konto und einen Token — das steht als D-P7/D-P8 in
# PRUEFEN-AUF-DEM-PI.md.
#
# Geprueft wird, was ohne Konto pruefbar ist: dass ohne Einrichtung nichts
# passiert, dass die richtige Adresse zusammengebaut wird und dass der Token
# nicht in der mcs.conf landet.
echo "  Skript auf dem Pi:  $([ -x "$TESTHOME/mcs/dns-update.sh" ] && echo "da" || echo "FEHLT")"
echo "  mcs.conf kennt MCS_DNS_ANBIETER: $(grep -c '^MCS_DNS_ANBIETER=' "$TESTHOME/mcs/mcs.conf") (muss 1 sein)"

echo "--- nicht eingerichtet: still, und Rueckgabewert 0 ---"
AUS=$(su "$TESTUSER" -c "$TESTHOME/mcs/dns-update.sh" 2>&1); RC=$?
echo "  Exitcode: $RC (muss 0 sein), Ausgabe: \"$AUS\" (muss leer sein)"

echo "--- eingerichtet: welche Adresse wird aufgerufen? ---"
# curl-Attrappe: sie schreibt nur mit, statt irgendwohin zu telefonieren.
mkdir -p /tmp/dnsattrappe && chmod 777 /tmp/dnsattrappe
cat > /tmp/dnsattrappe/curl <<'STUB'
#!/bin/bash
ARGS=("$@"); ZIEL="${!#}"; DATEN=""
for i in "${!ARGS[@]}"; do [ "${ARGS[$i]}" = "-d" ] && DATEN="${ARGS[$((i+1))]}"; done
{ echo "URL: $ZIEL"; [ -n "$DATEN" ] && echo "DATEN: $DATEN"; } >> /tmp/dnsattrappe/mitschnitt
case "$ZIEL" in
  *checkipv4*) echo "203.0.113.7"; exit 0 ;;
  *checkipv6*) exit 7 ;;
esac
printf 'good
200
'
STUB
chmod 755 /tmp/dnsattrappe/curl
: > /tmp/dnsattrappe/mitschnitt; chmod 666 /tmp/dnsattrappe/mitschnitt

sed -i 's#^MCS_DNS_ANBIETER=.*#MCS_DNS_ANBIETER=desec#' "$TESTHOME/mcs/mcs.conf"
sed -i 's#^MCS_DNS_NAME=.*#MCS_DNS_NAME=mc.abnahme.dedyn.io#' "$TESTHOME/mcs/mcs.conf"
sed -i 's#^MCS_DNS_ZONE=.*#MCS_DNS_ZONE=abnahme.dedyn.io#' "$TESTHOME/mcs/mcs.conf"
su "$TESTUSER" -c "printf 'MCS_DNS_TOKEN=abnahmetoken\n' > $TESTHOME/mcs/dns.env; chmod 600 $TESTHOME/mcs/dns.env"

su "$TESTUSER" -c "env PATH=/tmp/dnsattrappe:\$PATH $TESTHOME/mcs/dns-update.sh" >/dev/null 2>&1
echo "  Exitcode: $? (muss 0 sein)"
grep -o 'update.dedyn.io/?hostname=[^ ]*' /tmp/dnsattrappe/mitschnitt | sed 's/^/  /'
echo "  IPv6 wird als LEERER Parameter gesendet (loescht einen veralteten AAAA-Eintrag):"
echo "    $(grep -c 'myipv6=$' /tmp/dnsattrappe/mitschnitt) Treffer (muss 1 sein)"

echo "--- unveraendert: darf NICHT erneut melden ---"
: > /tmp/dnsattrappe/mitschnitt
su "$TESTUSER" -c "env PATH=/tmp/dnsattrappe:\$PATH $TESTHOME/mcs/dns-update.sh" >/dev/null 2>&1
echo "  Aufrufe an update.dedyn: $(grep -c 'update.dedyn' /tmp/dnsattrappe/mitschnitt) (muss 0 sein)"

echo "--- SRV-Eintrag: Untername, Port und der Punkt am Ende ---"
: > /tmp/dnsattrappe/mitschnitt
su "$TESTUSER" -c "env PATH=/tmp/dnsattrappe:\$PATH $TESTHOME/mcs/dns-update.sh --srv" >/dev/null 2>&1
grep '^DATEN' /tmp/dnsattrappe/mitschnitt | sed 's/^/  /'

echo "--- der Token darf NICHT in der mcs.conf stehen ---"
echo "  Treffer in mcs.conf: $(grep -c 'abnahmetoken' "$TESTHOME/mcs/mcs.conf") (muss 0 sein)"
echo "  Rechte von dns.env:  $(stat -c '%a' "$TESTHOME/mcs/dns.env") (muss 600 sein)"

# Aufraeumen, damit die folgenden Abschnitte einen unveraenderten Stand sehen.
sed -i 's#^MCS_DNS_ANBIETER=.*#MCS_DNS_ANBIETER=#' "$TESTHOME/mcs/mcs.conf"
rm -rf /tmp/dnsattrappe

trenner "11) Hardware-Erkennung"
# Warum das hier steht und nicht auf dem Pi:
#
# Die Einordnung eines Datentraegers ist der Teil von Etappe D mit den
# meisten Fallen — und ausgerechnet der laesst sich auf echter Hardware
# kaum pruefen, weil dort immer nur EIN Fall vorliegt. Ein Pi mit NVMe zeigt
# nie, was das Skript bei einer SD-Karte sagen wuerde.
#
# Deshalb wird hier ein /sys-Baum nachgebaut und die Einordnung gegen alle
# Faelle gefahren. Der Container ist dafuer genau richtig: Er hat selbst
# keine echten Geraete, also faellt nichts durch einen Zufallstreffer auf.
#
# Geprueft werden namentlich die drei Fallen aus dem Kopf von
# lib/hardware.sh:
#   mmcblk0 (type SD)  -> SD-Karte, mit Warnung
#   mmcblk1 (type MMC) -> eMMC, OHNE Warnung   (sonst warnt es beim CM4)
#   sdc am USB-Bus mit rotational=1 -> "usb", NICHT "hdd"
#      (viele USB-SATA-Bruecken melden faelschlich 1; eine SSD im Gehaeuse
#       wuerde sonst als Festplatte gemeldet)
SYSNACHBAU=/tmp/sysnachbau
rm -rf "$SYSNACHBAU"; mkdir -p "$SYSNACHBAU/block"
mkdir -p "$SYSNACHBAU/g/mmc0/mmcblk0/device"; echo SD  > "$SYSNACHBAU/g/mmc0/mmcblk0/device/type"
mkdir -p "$SYSNACHBAU/g/mmc1/mmcblk1/device"; echo MMC > "$SYSNACHBAU/g/mmc1/mmcblk1/device/type"
mkdir -p "$SYSNACHBAU/g/pci/nvme0n1/queue";   echo 0   > "$SYSNACHBAU/g/pci/nvme0n1/queue/rotational"
mkdir -p "$SYSNACHBAU/g/ata1/sda/queue";      echo 0   > "$SYSNACHBAU/g/ata1/sda/queue/rotational"
mkdir -p "$SYSNACHBAU/g/ata2/sdb/queue";      echo 1   > "$SYSNACHBAU/g/ata2/sdb/queue/rotational"
mkdir -p "$SYSNACHBAU/g/pci/usb1/1-1/sdc/queue"; echo 1 > "$SYSNACHBAU/g/pci/usb1/1-1/sdc/queue/rotational"
for D in mmcblk0 mmcblk1; do ln -s "$SYSNACHBAU/g/mmc${D#mmcblk}/$D" "$SYSNACHBAU/block/$D"; done
ln -s "$SYSNACHBAU/g/pci/nvme0n1"        "$SYSNACHBAU/block/nvme0n1"
ln -s "$SYSNACHBAU/g/ata1/sda"           "$SYSNACHBAU/block/sda"
ln -s "$SYSNACHBAU/g/ata2/sdb"           "$SYSNACHBAU/block/sdb"
ln -s "$SYSNACHBAU/g/pci/usb1/1-1/sdc"   "$SYSNACHBAU/block/sdc"

# Geprueft wird die Fassung, die auf dem PI gelandet ist — nicht die im
# Repo. Sonst pruefte der Test eine Datei, die dort vielleicht gar nicht
# ankommt (dieselbe Lehre wie bei B7).
# Auf dem Pi liegt sie FLACH als hardware.sh, im Repository unter
# lib/hardware.sh (siehe install.sh). Geprueft wird die Fassung auf dem Pi.
echo "  Bibliothek auf dem Pi: $([ -f "$TESTHOME/mcs/hardware.sh" ] && echo "da" || echo "FEHLT - install.sh kopiert sie nicht")"
HARDWARE_SYS="$SYSNACHBAU" bash -c '
  . '"$TESTHOME"'/mcs/hardware.sh
  # lsblk gibt es im Container nicht; dann greift die Namensform, und genau
  # die soll hier mitgeprueft werden — auf einem Pi OS ohne util-linux waere
  # es derselbe Weg.
  fall() {
    hardware_medium_einordnen "$1"
    if [ "$MEDIUM_ART" = "$2" ] && [ "${MEDIUM_WARNUNG:--}" = "$3" ]; then
      printf "  ok      %-16s -> %-9s %s\n" "$1" "$MEDIUM_ART" "${MEDIUM_WARNUNG:--}"
    else
      printf "  FEHLER  %-16s -> %s/%s   erwartet: %s/%s\n" \
        "$1" "$MEDIUM_ART" "${MEDIUM_WARNUNG:--}" "$2" "$3"
    fi
  }
  fall /dev/mmcblk0p2 sd        "SD-Karte"
  fall /dev/mmcblk1p2 emmc      "-"
  fall /dev/nvme0n1p1 nvme      "-"
  fall /dev/sda2      ssd       "-"
  fall /dev/sdb1      hdd       "Festplatte"
  fall /dev/sdc1      usb       "-"
  fall overlay        unbekannt "-"
  fall ""             unbekannt "-"
'
echo "--- mcs hardware auf dieser Installation ---"
su "$TESTUSER" -c "mcs hardware" 2>&1 | sed "s/^/  /"

trenner "ERGEBNIS"
echo "  Lauf 1 Exitcode: $LAUF1"
echo "  Lauf 2 Exitcode: $LAUF2"

# Bis zum 01.09.2026 endete dieses Skript hier — mit den beiden Zahlen als
# Ausgabe und dem Rueckgabewert des letzten "echo", also immer 0. Ein
# fehlgeschlagener Installationslauf hat den Abnahmetest damit NIE rot
# gemacht; er fiel nur auf, wenn jemand das Protokoll las.
#
# Aufgefallen ist es, weil genau das passierte: Eine Aenderung an install.sh
# brach den ZWEITEN Lauf (eine Variable, die nur im else-Zweig gesetzt wurde,
# unter "set -u"). "Lauf 2 Exitcode: 1" stand da — und der Test meldete
# Erfolg. Das ist die Fehlerklasse, die dieses Projekt am teuersten bezahlt
# hat, und ausgerechnet im Werkzeug, das sie finden soll.
#
# Der zweite Lauf zaehlt genauso wie der erste: "Ein zweiter Lauf der
# Installation muss durchlaufen, ohne etwas zu veraendern oder zu zerstoeren"
# steht so in CLAUDE.md.
if [ "$LAUF1" -ne 0 ] || [ "$LAUF2" -ne 0 ]; then
  echo ""
  echo "  FEHLGESCHLAGEN: Eine Installation ist nicht durchgelaufen."
  exit 1
fi

# Und die Inhaltspruefungen. Sie liefen vorher nur als Text mit; ein Befund
# darin machte den Test nicht rot (siehe FEHLER_GEFUNDEN ganz oben).
if [ "$FEHLER_GEFUNDEN" -ne 0 ]; then
  echo ""
  echo "  FEHLGESCHLAGEN: Beide Installationen liefen durch, aber eine"
  echo "  Inhaltspruefung hat einen Befund gemeldet. Im Protokoll oben"
  echo "  nach 'FEHLER:' suchen."
  exit 1
fi

echo "  Beide Installationslaeufe sind durchgelaufen."
echo "  Keine Inhaltspruefung hat einen Befund gemeldet."
