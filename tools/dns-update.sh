#!/bin/bash
#
# dns-update.sh — Damit Mitspieler den Server immer unter demselben Namen finden.
#
#   dns-update.sh              Adresse melden (so ruft der Timer es auf)
#   dns-update.sh --erzwingen  auch melden, wenn sich nichts geändert hat
#   dns-update.sh --zeigen     was eingestellt ist und was zuletzt geschah
#   dns-update.sh --srv        SRV-Eintrag anlegen (nur deSEC), einmalig
#   dns-update.sh --json       Zustand als JSON (für die Weboberfläche)
#
# ----------------------------------------------------------------------------
# Wozu
# ----------------------------------------------------------------------------
# Die meisten Internetanschlüsse zu Hause bekommen regelmäßig eine neue
# Adresse. Ohne einen Namen müssten Mitspieler jedes Mal eine neue Zahl
# eintippen — und erführen von der Änderung erst, wenn sie nicht mehr
# hereinkommen.
#
# Dieses Skript ersetzt seit Etappe D das frühere duckdns.sh und kann zwei
# Anbieter (Entscheidung 11 im Lastenheft):
#
#   deSEC     Empfehlung. Kostenlos, DNSSEC, betrieben von einem deutschen
#             gemeinnützigen Verein — und der einzige der beiden, der
#             SRV-Einträge kann.
#   DuckDNS   bleibt möglich, kann keine SRV-Einträge.
#
# ----------------------------------------------------------------------------
# Warum BEIDE Adressfamilien gemeldet werden
# ----------------------------------------------------------------------------
# Bei DS-Lite — einem grossen Teil der deutschen Anschlüsse — gibt es gar
# keine öffentliche IPv4-Adresse. Der AAAA-Eintrag ist dort der einzige, der
# etwas nützt. Ihn wegzulassen hiesse, ausgerechnet dort nichts zu tun, wo es
# darauf ankommt.
#
# Und umgekehrt: Fehlt eine der beiden Adressen, wird der zugehörige Eintrag
# GELÖSCHT statt stehen gelassen. Ein veralteter AAAA-Eintrag ist schlimmer
# als keiner — Mitspieler laufen dann in einen Verbindungsversuch, der erst
# nach Zeitüberschreitung aufgibt, und halten den Server für kaputt.
#
# ----------------------------------------------------------------------------
# Der SRV-Eintrag
# ----------------------------------------------------------------------------
# Mit einem Eintrag "_minecraft._tcp" tippen Mitspieler nur
# "mc.beispiel.de" — ohne Portangabe, auch wenn der Server auf einem
# anderen Port läuft. Das ist der praktische Vorteil von deSEC gegenüber
# DuckDNS.
#
# Angelegt wird er einmalig, auf Knopfdruck, NICHT aus dem Timer: Er ändert
# sich nicht, wenn sich die Adresse ändert.
#
# ----------------------------------------------------------------------------
# Wo der Token liegt — und warum nicht in mcs.conf
# ----------------------------------------------------------------------------
# mcs.conf wird von Shell, Python UND systemd gelesen und hat entsprechend
# offene Rechte. Ein API-Token gehört dort nicht hinein. Er steht in
# <Installationsort>/dns.env mit chmod 600 — dasselbe Muster wie bei
# duckdns.env, und aus demselben Grund.

set -uo pipefail

MCS_HOME="${HOME:-/home/$(id -un)}"
MCS_CONF="${MCS_CONF:-$MCS_HOME/mcs/mcs.conf}"
# shellcheck source=/dev/null
if [ -f "$MCS_CONF" ]; then . "$MCS_CONF"; fi

MC_DIR="${MCS_DIR:-$MCS_HOME/mcs}"
ANBIETER="${MCS_DNS_ANBIETER:-}"
NAME="${MCS_DNS_NAME:-}"
ZONE="${MCS_DNS_ZONE:-}"
PROPERTIES="${MCS_SERVER_PROPERTIES:-${MCS_SERVER_DIR:-$MC_DIR/mc_server}/server.properties}"

ZUGANG="${MCS_DNS_ENV:-$MC_DIR/dns.env}"
if [ -f "$ZUGANG" ]; then
  # shellcheck source=/dev/null
  . "$ZUGANG"
fi
TOKEN="${MCS_DNS_TOKEN:-}"

LOG="$MC_DIR/dns.log"
MERKDATEI="$MC_DIR/.dns-zuletzt"

MODUS=melden
while [ $# -gt 0 ]; do
  case "$1" in
    --erzwingen) MODUS=erzwingen ;;
    --zeigen)    MODUS=zeigen ;;
    --srv)       MODUS=srv ;;
    --json)      MODUS=json ;;
    -h|--hilfe|--help) sed -n '3,9p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unbekannter Parameter: $1" >&2; exit 1 ;;
  esac
  shift
done

protokoll() {
  mkdir -p "$MC_DIR"
  printf '%s | %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >> "$LOG" 2>/dev/null || true
}

# Nur die letzten 200 Zeilen aufheben. Ein Timer, der alle fünf Minuten
# läuft, schreibt sonst im Jahr über hunderttausend Zeilen — und dann sucht
# niemand mehr darin.
protokoll_kuerzen() {
  [ -f "$LOG" ] || return 0
  local ZEILEN; ZEILEN=$(wc -l < "$LOG" 2>/dev/null || echo 0)
  if [ "$ZEILEN" -gt 400 ]; then
    tail -n 200 "$LOG" > "$LOG.neu" 2>/dev/null && mv "$LOG.neu" "$LOG"
  fi
}

jstr() { printf '"%s"' "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"; }

# ----------------------------------------------------------------------------
# Zustand ausgeben (--zeigen / --json)
# ----------------------------------------------------------------------------
if [ "$MODUS" = json ] || [ "$MODUS" = zeigen ]; then
  LETZTES=""
  [ -f "$LOG" ] && LETZTES=$(tail -n1 "$LOG" 2>/dev/null)
  GEMELDET=""
  [ -f "$MERKDATEI" ] && GEMELDET=$(cat "$MERKDATEI" 2>/dev/null)

  if [ "$MODUS" = json ]; then
    printf '{\n'
    printf '  "anbieter": %s,\n' "$(jstr "$ANBIETER")"
    printf '  "name": %s,\n' "$(jstr "$NAME")"
    printf '  "zone": %s,\n' "$(jstr "$ZONE")"
    printf '  "token_da": %s,\n' "$([ -n "$TOKEN" ] && echo true || echo false)"
    printf '  "nur_ipv4": %s,\n' "$([ "${MCS_DNS_NUR_IPV4:-}" = "ja" ] && echo true || echo false)"
    printf '  "zuletzt_gemeldet": %s,\n' "$(jstr "$GEMELDET")"
    printf '  "letzte_zeile": %s\n' "$(jstr "$LETZTES")"
    printf '}\n'
  else
    echo "Anbieter:          ${ANBIETER:-keiner (DNS ist aus)}"
    echo "Name:              ${NAME:-–}"
    [ "$ANBIETER" = desec ] && echo "Zone bei deSEC:    ${ZONE:-–}"
    echo "Token hinterlegt:  $([ -n "$TOKEN" ] && echo "ja ($ZUGANG)" || echo "nein")"
    if [ "${MCS_DNS_NUR_IPV4:-}" = "ja" ]; then
      echo "IPv6 (AAAA):       wird nicht gemeldet (MCS_DNS_NUR_IPV4=ja)"
    fi
    echo "Zuletzt gemeldet:  ${GEMELDET:-noch nie}"
    echo "Letzte Zeile:      ${LETZTES:-–}"
  fi
  exit 0
fi

# ----------------------------------------------------------------------------
# Nicht eingerichtet? Dann still enden.
# ----------------------------------------------------------------------------
# Der Timer läuft immer mit (er gehört zu mcs.target). Ohne Anbieter tut
# dieses Skript nichts und sagt auch nichts — sonst stünde alle fünf Minuten
# eine Zeile im Journal, die nur bedeutet, dass etwas nicht eingerichtet ist.
#
# Warum der Timer trotzdem immer läuft: Sonst müsste die Weboberfläche ihn
# aktivieren können, also "systemctl enable" dürfen. Das wäre eine weite
# sudo-Regel für einen Komfortgewinn. So schreibt die Oberfläche nur zwei
# Dateien im eigenen Verzeichnis.
if [ -z "$ANBIETER" ]; then exit 0; fi

if [ -z "$NAME" ] || [ -z "$TOKEN" ]; then
  echo "Fehler: DNS ist auf \"$ANBIETER\" eingestellt, aber es fehlt $([ -z "$NAME" ] && echo "der Name" || echo "der Token")." >&2
  echo "Einrichten in der Weboberfläche unter \"Konfiguration\"." >&2
  protokoll "FEHLER: unvollständig eingerichtet (Name oder Token fehlt)"
  exit 1
fi

if ! command -v curl >/dev/null 2>&1; then
  echo "Fehler: curl fehlt." >&2; exit 1
fi

# ----------------------------------------------------------------------------
# SRV-Eintrag anlegen (nur deSEC)
# ----------------------------------------------------------------------------
if [ "$MODUS" = srv ]; then
  if [ "$ANBIETER" != desec ]; then
    echo "SRV-Einträge kann nur deSEC. DuckDNS bietet sie nicht an." >&2
    exit 1
  fi
  if [ -z "$ZONE" ]; then
    echo "Fehler: Es ist keine Zone eingetragen (MCS_DNS_ZONE)." >&2
    echo "Die Zone ist die Domain, die dir bei deSEC gehört — z. B." >&2
    echo "\"meinserver.dedyn.io\". Der Name darf darunter liegen." >&2
    exit 1
  fi

  PORT=$(sed -n 's/^server-port=//p' "$PROPERTIES" 2>/dev/null | tail -n1)
  case "$PORT" in ''|*[!0-9]*) PORT=25565 ;; esac

  # Welcher Teil des Namens steht VOR der Zone? Bei name=mc.beispiel.de und
  # zone=beispiel.de ist das "mc"; ist der Name die Zone selbst, ist es leer.
  # Der SRV-Eintrag heisst dann "_minecraft._tcp.mc" bzw. "_minecraft._tcp".
  if [ "$NAME" = "$ZONE" ]; then
    UNTERNAME="_minecraft._tcp"
  else
    case "$NAME" in
      *".$ZONE") UNTERNAME="_minecraft._tcp.${NAME%".$ZONE"}" ;;
      *)
        echo "Fehler: \"$NAME\" liegt nicht unterhalb der Zone \"$ZONE\"." >&2
        exit 1 ;;
    esac
  fi

  # Ein SRV-Wert lautet: Priorität Gewicht Port Ziel.
  # Der Punkt am Ende des Ziels ist Pflicht — ohne ihn haengt deSEC die Zone
  # noch einmal an, und der Eintrag zeigt auf mc.beispiel.de.beispiel.de.
  WERT="0 5 ${PORT} ${NAME}."

  # PUT auf die Sammlung statt POST auf einen Eintrag: deSEC legt damit an
  # ODER aktualisiert. Mit POST scheitert jeder zweite Aufruf daran, dass es
  # den Eintrag schon gibt — und dann muesste man den Fehlertext auswerten,
  # um zu wissen, ob alles in Ordnung ist.
  ANTWORT=$(curl -sS --max-time 30 -X PUT \
    -H "Authorization: Token $TOKEN" \
    -H "Content-Type: application/json" \
    -w '\n%{http_code}' \
    -d "[{\"subname\":\"$UNTERNAME\",\"type\":\"SRV\",\"ttl\":3600,\"records\":[\"$WERT\"]}]" \
    "https://desec.io/api/v1/domains/${ZONE}/rrsets/" 2>&1)
  CODE=$(printf '%s' "$ANTWORT" | tail -n1)
  RUMPF=$(printf '%s' "$ANTWORT" | sed '$d')

  case "$CODE" in
    2*)
      protokoll "SRV gesetzt: $UNTERNAME.$ZONE -> $WERT"
      echo "SRV-Eintrag gesetzt: $UNTERNAME.$ZONE  ->  $WERT"
      echo "Mitspieler geben ab jetzt nur noch \"$NAME\" ein, ohne Port."
      echo "Bis der Eintrag überall bekannt ist, kann eine Stunde vergehen (TTL 3600)."
      exit 0 ;;
    *)
      # Den Text des Anbieters wörtlich weitergeben. Eine eigene Deutung
      # wäre hier geraten — und Raten hilft niemandem beim Beheben.
      protokoll "FEHLER SRV ($CODE): $RUMPF"
      echo "Der SRV-Eintrag ließ sich nicht setzen (HTTP $CODE)." >&2
      echo "Antwort von deSEC: $RUMPF" >&2
      exit 1 ;;
  esac
fi

# ----------------------------------------------------------------------------
# Adresse melden
# ----------------------------------------------------------------------------
# Dieselben Dienste wie im Erreichbarkeitstest — die von deSEC.
IPV4=$(curl -4 -fsS --max-time 10 https://checkipv4.dedyn.io 2>/dev/null | tr -d '[:space:]')

# MCS_DNS_NUR_IPV4: kein AAAA-Eintrag, auch wenn der Pi IPv6 hat.
#
# Klingt nach einem Rückschritt, ist aber für viele Anschlüsse das Richtige.
# Ein AAAA sagt "hier bin ich über IPv6 erreichbar". Stimmt das nicht — weil
# die Firewall des Routers eingehendes IPv6 blockt, und das ist bei den
# meisten Heimroutern die Voreinstellung —, dann ist der Eintrag schlimmer
# als keiner: Clients bevorzugen IPv6, laufen in einen Timeout und fallen
# erst danach auf IPv4 zurück. Der Server wirkt dann für jeden mit IPv6
# langsam oder tot, obwohl über IPv4 alles in Ordnung ist.
#
# Wer eingehendes IPv6 freigegeben hat, lässt den Schalter aus: Dann ist ein
# AAAA der einzige Weg, der ohne Portfreigabe auskommt (IPv6 kennt kein NAT).
# Diese Entscheidung hängt am Router und lässt sich hier nicht raten —
# "mcs erreichbarkeit" beantwortet sie.
#
# Ein leeres IPV6 wird ausdrücklich mitgemeldet und löscht einen bereits
# vorhandenen AAAA. Sonst bliebe beim Umschalten ein veralteter Eintrag
# stehen, und der ist genau das Problem, das hier vermieden werden soll.
if [ "${MCS_DNS_NUR_IPV4:-}" = "ja" ]; then
  IPV6=""
else
  IPV6=$(curl -6 -fsS --max-time 10 https://checkipv6.dedyn.io 2>/dev/null | tr -d '[:space:]')
fi

[[ "$IPV4" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || IPV4=""
{ [[ "$IPV6" =~ ^[0-9a-fA-F:]+$ ]] && [[ "$IPV6" == *:* ]]; } || IPV6=""

if [ -z "$IPV4" ] && [ -z "$IPV6" ]; then
  protokoll "FEHLER: keine öffentliche Adresse ermittelbar (kein Netz?)"
  echo "Fehler: Es ließ sich keine öffentliche Adresse ermitteln." >&2
  exit 1
fi

# Was an deSEC geht, wenn eine Abfrage LEER blieb: "preserve" oder leer?
#
# Leer LOESCHT den Eintrag (deSEC-Doku, Update-API), "preserve" laesst ihn
# stehen. Leer darf deshalb nur heissen "diese Adresse gibt es nicht", nie
# "die Abfrage hat gerade nicht geklappt". Bis zum 23.09.2026 genuegte ein
# einzelner Aussetzer von checkipv4 — im dns.log dieses Pi vier an zwei
# Tagen —, und der A-Eintrag war bis zum naechsten Lauf weg; fuer IPv6
# (auf DS-Lite der einzige Weg) blieb dieselbe Luecke offen.
#
# Unterschieden wird an der Standardroute, wie in erreichbarkeit.sh: Gibt es
# eine fuer diese Adressfamilie und die Abfrage scheitert trotzdem, war es ein
# Aussetzer -> preserve. Ohne Route gibt es keine Adresse -> leer, loeschen.
# MCS_DNS_NUR_IPV4=ja heisst fuer IPv6 immer leer: bewusst geloescht (siehe
# oben).
#
# Fuer IPv6 zaehlt nicht die Route, sondern eine globale Adresse am Pi (ohne
# private fc/fd-Adressen): Schaltet der Anbieter IPv6 ab, kann der Router die
# Route weiter ankuendigen — dann hielte "preserve" einen toten AAAA fuer
# immer (Zweitmeinung zu Durchgang 2). Fuer IPv4 geht das nicht: Hinter NAT
# hat der Pi nie eine oeffentliche IPv4, dort bleibt die Route das Merkmal.
familie_melden() {   # familie_melden ADRESSE -4|-6
  if [ -n "$1" ]; then printf '%s' "$1"; return; fi
  if [ "$2" = -6 ]; then
    # Erst in eine Variable, dann suchen: "ip | grep -q" ist unter pipefail
    # die Falle aus CLAUDE.md — grep hoert beim ersten Treffer auf, ip
    # bekommt SIGPIPE, die Pipeline endet mit 141, und aus "preserve" wird
    # "loeschen" (nachgestellt mit 20000 Adresszeilen). "-deprecated": Eine
    # Adresse, deren Praefix der Router nicht mehr ankuendigt, belegt nichts.
    # Der Filter ^f[cd] ist derselbe wie LOKAL_IPV6 in erreichbarkeit.sh
    # (Zweitmeinung zu Durchgang 3, Befunde 4, 6, 8).
    local ADRESSEN
    ADRESSEN=$(ip -6 -o addr show scope global -deprecated 2>/dev/null | awk '{print $4}')
    # Leer abfangen: Ein Here-String aus "" ist eine leere Zeile, und die
    # traefe "grep -v".
    if [ -n "$ADRESSEN" ] && grep -qvE '^f[cd]' <<<"$ADRESSEN"; then
      printf 'preserve'
    fi
    return 0
  fi
  if [ -n "$(ip -4 route show default 2>/dev/null)" ]; then
    printf 'preserve'
  fi
}
MELDE_V4=$(familie_melden "$IPV4" -4)
if [ "${MCS_DNS_NUR_IPV4:-}" = "ja" ]; then
  MELDE_V6=""
else
  MELDE_V6=$(familie_melden "$IPV6" -6)
fi

# Hat sich etwas geändert? Wenn nicht, wird nicht gemeldet.
#
# Nicht aus Sparsamkeit: Der Timer läuft alle fünf Minuten, und ein Anbieter,
# der jahrelang alle fünf Minuten dieselbe unveränderte Adresse bekommt, hat
# ein Recht darauf, das nicht zu mögen. Nebenbei bleibt das Protokoll lesbar
# — dort steht dann nur, was wirklich passiert ist.
# Gemerkt wird, was GEMELDET wurde, nicht was die Abfrage ergab. Sonst sahen
# "Aussetzer" (preserve) und "Adresse weg" (leer) gleich aus, und der echte
# Wegfall nach einem Aussetzer wurde nie gemeldet: Der AAAA blieb fuer immer
# auf der toten Adresse (Zweitmeinung zu Durchgang 2, nachgestellt).
STAND="${MELDE_V4}|${MELDE_V6}"
if [ "$MODUS" != erzwingen ] && [ -f "$MERKDATEI" ] \
   && [ "$(cat "$MERKDATEI" 2>/dev/null)" = "$STAND" ]; then
  exit 0
fi

case "$ANBIETER" in
  desec)
    # deSEC nimmt die Adressen als Parameter entgegen. Ein LEERER Wert
    # löscht den zugehörigen Eintrag — genau das ist gewollt, wenn eine der
    # beiden Familien weggefallen ist (siehe Kopf dieser Datei).
    ANTWORT=$(curl -sS --max-time 30 -w '\n%{http_code}' \
      -H "Authorization: Token $TOKEN" \
      "https://update.dedyn.io/?hostname=${NAME}&myipv4=${MELDE_V4}&myipv6=${MELDE_V6}" 2>&1)
    CODE=$(printf '%s' "$ANTWORT" | tail -n1)
    RUMPF=$(printf '%s' "$ANTWORT" | sed '$d' | tr -d '\n')
    ;;
  duckdns)
    # DuckDNS will nur den Teil vor ".duckdns.org". Beide Schreibweisen
    # werden angenommen — wer seinen Namen von der Webseite kopiert, hat
    # die lange Form vor sich.
    SUB="${NAME%.duckdns.org}"
    ANTWORT=$(curl -sS --max-time 30 -w '\n%{http_code}' \
      "https://www.duckdns.org/update?domains=${SUB}&token=${TOKEN}&ip=${IPV4}&ipv6=${IPV6}" 2>&1)
    CODE=$(printf '%s' "$ANTWORT" | tail -n1)
    RUMPF=$(printf '%s' "$ANTWORT" | sed '$d' | tr -d '\n')
    # DuckDNS antwortet mit "OK" oder "KO" und HTTP 200 in beiden Fällen —
    # der Rückgabecode allein sagt hier also nichts.
    [ "$RUMPF" = "OK" ] || CODE="fehler"
    ;;
  *)
    echo "Fehler: Unbekannter Anbieter \"$ANBIETER\" (erlaubt: desec, duckdns)." >&2
    exit 1 ;;
esac

case "$CODE" in
  2*)
    echo "$STAND" > "$MERKDATEI"
    TEXT_V4="${MELDE_V4:-(gelöscht)}"; TEXT_V6="${MELDE_V6:-(gelöscht)}"
    protokoll "gemeldet an $ANBIETER: $NAME -> IPv4 ${TEXT_V4/#preserve/(unverändert, Abfrage gescheitert)}, IPv6 ${TEXT_V6/#preserve/(unverändert, Abfrage gescheitert)} [$RUMPF]"
    protokoll_kuerzen
    exit 0 ;;
  *)
    protokoll "FEHLER bei $ANBIETER ($CODE): $RUMPF"
    protokoll_kuerzen
    echo "Die Adresse ließ sich nicht melden (HTTP $CODE): $RUMPF" >&2
    exit 1 ;;
esac
