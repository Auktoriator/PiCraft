#!/bin/bash
#
# erreichbarkeit.sh — Kommen meine Mitspieler überhaupt rein?
#
#   erreichbarkeit.sh          Bericht im Klartext
#   erreichbarkeit.sh --json   dasselbe als JSON (für die Weboberfläche)
#   erreichbarkeit.sh --lokal  nur, was ohne Internetzugriff feststellbar ist
#
# ----------------------------------------------------------------------------
# Warum es das gibt: DS-Lite
# ----------------------------------------------------------------------------
# Ein großer Teil der deutschen Internetanschlüsse (Kabel, viele
# Glasfaseranbieter) hat gar keine eigene öffentliche IPv4-Adresse. Der
# Anbieter teilt eine Adresse unter vielen Kunden auf — "DS-Lite" oder
# allgemeiner "CGNAT". Eine Portfreigabe im Router ist dort schlicht
# wirkungslos, und kein DNS-Dienst der Welt ändert daran etwas.
#
# Wer das nicht weiß, gibt den Port frei, prüft die Firewall, wechselt den
# DNS-Anbieter, startet den Router neu — und sucht wochenlang einen Fehler,
# den es auf seinem Pi gar nicht gibt.
#
# Das Lastenheft (5.6) verlangt deshalb nicht "Port im Router freigeben",
# sondern eine konkrete Aussage:
#   "Dein Port ist von außen nicht erreichbar, und zwar weil dein Anschluss
#    DS-Lite benutzt."
#
# ----------------------------------------------------------------------------
# Was dieses Skript sicher sagen kann — und was nicht
# ----------------------------------------------------------------------------
# Der Anspruch lässt sich zu großen Teilen einlösen, aber nicht ganz. Die
# Lücke wird benannt statt überspielt:
#
#   Von außen gar keine IPv4 zu bekommen, aber globales IPv6 da
#       -> GESICHERT: kein öffentliches IPv4. Keine Freigabe hilft.
#   Öffentliche IPv4 liegt in 100.64.0.0/10
#       -> GESICHERT: Anbieter-NAT. Freigabe wirkungslos.
#   IPv6 von außen erreichbar, IPv4 nicht
#       -> STARKES INDIZ für DS-Lite. Und die praktisch wichtigste Aussage:
#          Mitspieler mit IPv6 kommen schon jetzt herein.
#   IPv4 sieht öffentlich aus, ist aber zu
#       -> NICHT ENTSCHEIDBAR aus der Ferne. Bei DS-Lite meldet der
#          Echo-Dienst die Adresse des Anbieter-Gateways, und die sieht
#          öffentlich aus. Es kann also beides sein: fehlende Freigabe oder
#          DS-Lite. Dann werden BEIDE genannt — und wo im Router man sie
#          unterscheidet.
#
# Ein Test, der im letzten Fall "DS-Lite" behauptet, liegt in der Mehrzahl
# der Fälle falsch und schickt Leute auf die Suche nach einem Problem, das
# sie nicht haben. Ehrlich statt bequem (Leitsatz 5).
#
# ----------------------------------------------------------------------------
# Wer gefragt wird (der Test verlässt den Pi — anders geht es nicht)
# ----------------------------------------------------------------------------
#   checkipv4.dedyn.io / checkipv6.dedyn.io   die eigene öffentliche Adresse
#   api.mcsrvstat.us                          verbindet sich von außen
#
# Die Echo-Dienste sind die von deSEC — dem Anbieter, den das Lastenheft
# ohnehin empfiehlt (Entscheidung 11). So ist ein Dienst weniger im Spiel.
#
# api.mcsrvstat.us beantwortet nicht "ist Port 25565 offen", sondern "läuft
# dort ein Minecraft-Server, mit dem ich sprechen kann". Das ist die Frage,
# die eigentlich interessiert — und nebenbei wird der SRV-Eintrag mitgeprüft.
#
# Mit --lokal wird gar nichts nach außen gefragt.

# KEIN "set -e". Dieses Skript soll einen vollständigen Bericht abliefern,
# auch wenn die Hälfte nicht feststellbar ist — ein Abbruch beim ersten
# fehlenden Wert wäre das Gegenteil seines Zwecks.
set -uo pipefail

MCS_HOME="${HOME:-/home/$(id -un)}"
MCS_CONF="${MCS_CONF:-$MCS_HOME/mcs/mcs.conf}"
# shellcheck source=/dev/null
if [ -f "$MCS_CONF" ]; then . "$MCS_CONF"; fi

MC_SERVER_DIR="${MCS_SERVER_DIR:-$MCS_HOME/mcs/mc_server}"
PROPERTIES="${MCS_SERVER_PROPERTIES:-$MC_SERVER_DIR/server.properties}"
DIENST="${MCS_SERVICE_NAME:-minecraft.service}"

AUSGABE=text
NUR_LOKAL=false
while [ $# -gt 0 ]; do
  case "$1" in
    --json)  AUSGABE=json ;;
    --lokal) NUR_LOKAL=true ;;
    -h|--hilfe|--help)
      sed -n '3,5p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "Unbekannter Parameter: $1" >&2; exit 1 ;;
  esac
  shift
done

# ----------------------------------------------------------------------------
# 1) Welcher Port, und läuft überhaupt etwas?
# ----------------------------------------------------------------------------
PORT=$(sed -n 's/^server-port=//p' "$PROPERTIES" 2>/dev/null | tail -n1)
case "$PORT" in
  ''|*[!0-9]*) PORT=25565 ;;
esac

DIENST_AKTIV=false
if command -v systemctl >/dev/null 2>&1; then
  [ "$(systemctl is-active "$DIENST" 2>/dev/null)" = "active" ] && DIENST_AKTIV=true
fi

# Lauscht auf diesem Pi überhaupt jemand auf dem Port? Das ist die einzige
# Frage, die sich ohne fremde Hilfe beantworten lässt — und die erste, die
# man stellen muss. Ist hier schon nichts, braucht man draußen nicht zu
# suchen.
LOKAL_OFFEN=unbekannt
if command -v ss >/dev/null 2>&1; then
  if ss -ltn 2>/dev/null | awk '{print $4}' | grep -qE "[:.]${PORT}\$"; then
    LOKAL_OFFEN=ja
  else
    LOKAL_OFFEN=nein
  fi
fi

# ----------------------------------------------------------------------------
# 2) Adressen dieses Pi (ohne Netzzugriff)
# ----------------------------------------------------------------------------
LAN_IPV4=""
LOKAL_IPV6=""
if command -v ip >/dev/null 2>&1; then
  LAN_IPV4=$(ip -4 -o addr show scope global 2>/dev/null \
             | awk '{print $4}' | cut -d/ -f1 | head -n1)
  # "scope global" allein genügt nicht: Eine ULA-Adresse (fc00::/7, in der
  # Praxis fd..) ist global im Sinne des Kernels, aber im Internet
  # unbrauchbar. Sie hier mitzunehmen hiesse, jemandem eine Adresse zu
  # nennen, unter der ihn niemand erreicht.
  LOKAL_IPV6=$(ip -6 -o addr show scope global 2>/dev/null \
               | awk '{print $4}' | cut -d/ -f1 \
               | grep -vE '^(fc|fd)' | head -n1)
fi

# ----------------------------------------------------------------------------
# 3) Öffentliche Adressen (fragt nach draußen)
# ----------------------------------------------------------------------------
OEFF_IPV4=""
OEFF_IPV6=""
IPV4_ART=unbekannt        # oeffentlich | cgnat | keine | unbekannt
NETZ_GEFRAGT=false

ist_ipv4() { [[ "$1" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]]; }
ist_ipv6() { [[ "$1" =~ ^[0-9a-fA-F:]+$ ]] && [[ "$1" == *:* ]]; }

if [ "$NUR_LOKAL" = false ] && command -v curl >/dev/null 2>&1; then
  NETZ_GEFRAGT=true
  OEFF_IPV4=$(curl -4 -fsS --max-time 8 https://checkipv4.dedyn.io 2>/dev/null | tr -d '[:space:]')
  OEFF_IPV6=$(curl -6 -fsS --max-time 8 https://checkipv6.dedyn.io 2>/dev/null | tr -d '[:space:]')
  ist_ipv4 "$OEFF_IPV4" || OEFF_IPV4=""
  ist_ipv6 "$OEFF_IPV6" || OEFF_IPV6=""

  if [ -z "$OEFF_IPV4" ]; then
    # "keine" nur, wenn es auch keinen IPv4-Weg nach draussen gibt. Hat
    # der Pi eine IPv4-Standardroute und die Abfrage scheitert trotzdem,
    # ist das ein Aussetzer des Pruefdienstes, keine Eigenschaft des
    # Anschlusses. Bis zum 23.09.2026 genuegte ein einziger davon — im
    # dns.log dieses Pi stehen vier an zwei Tagen —, und das Urteil lautete
    # "DS-Lite, eine Portfreigabe kann daran nichts aendern". Auf einem
    # Anschluss mit funktionierender Freigabe (nachgestellt).
    if [ -n "$(ip -4 route show default 2>/dev/null)" ]; then
      IPV4_ART=unbekannt
    else
      IPV4_ART=keine
    fi
  else
    # 100.64.0.0/10 ist der Bereich, den Anbieter für ihr eigenes NAT
    # benutzen (RFC 6598). Steht die eigene "öffentliche" Adresse darin, ist
    # die Sache entschieden: Der Router hat gar keine Adresse, die man
    # freigeben könnte.
    ZWEI=${OEFF_IPV4#*.}; ZWEI=${ZWEI%%.*}
    if [ "${OEFF_IPV4%%.*}" = "100" ] && [ "$ZWEI" -ge 64 ] && [ "$ZWEI" -le 127 ]; then
      IPV4_ART=cgnat
    else
      IPV4_ART=oeffentlich
    fi
  fi
fi

# ----------------------------------------------------------------------------
# 4) Von außen erreichbar?
# ----------------------------------------------------------------------------
# Getrennt für IPv4 und IPv6, denn genau die Differenz trägt die Aussage:
# "über IPv6 ja, über IPv4 nein" ist das typische Bild bei DS-Lite — und
# zugleich die Nachricht, dass ein Teil der Mitspieler längst hereinkommt.
#
# Drei Ergebnisse, nicht zwei. "Konnte nicht gefragt werden" ist etwas
# anderes als "nicht erreichbar", und die beiden zu verwechseln schickt
# jemanden auf die Suche nach einem Problem, das vielleicht keines ist.
V4_ERREICHBAR=unbekannt   # ja | nein | unbekannt
V6_ERREICHBAR=unbekannt

von_aussen_pruefen() {
  # $1 = Adresse in der Form, die api.mcsrvstat.us erwartet
  local ADRESSE="$1" ANTWORT
  ANTWORT=$(curl -fsS --max-time 20 \
            "https://api.mcsrvstat.us/3/${ADRESSE}:${PORT}" 2>/dev/null)
  [ -z "$ANTWORT" ] && { echo unbekannt; return; }
  if command -v jq >/dev/null 2>&1; then
    # ACHTUNG, hier stand zuerst  jq -r '.online // "fehlt"'  — und das ist
    # falsch. Der Operator "//" in jq liefert die rechte Seite nicht nur bei
    # "null", sondern auch bei "false". Ein sauber gemeldetes
    # "online": false wurde damit zu "fehlt" und landete bei "unbekannt":
    # Aus "nicht erreichbar" wurde "konnte nicht gefragt werden" — also
    # genau die Verwechslung, die dieses Skript vermeiden soll.
    #
    # Gefunden hat es der Test mit den nachgestellten Anschlüssen; im Betrieb
    # wäre es nie aufgefallen, weil "unbekannt" auch plausibel aussieht.
    case "$(printf '%s' "$ANTWORT" \
            | jq -r 'if has("online") then (.online|tostring) else "fehlt" end' 2>/dev/null)" in
      true)  echo ja ;;
      false) echo nein ;;
      *)     echo unbekannt ;;
    esac
  else
    # Ohne jq: Die Antwort enthält "online":true oder "online":false. Nur
    # wenn eines von beiden wirklich dasteht, wird geurteilt.
    if printf '%s' "$ANTWORT" | grep -q '"online"[[:space:]]*:[[:space:]]*true'; then
      echo ja
    elif printf '%s' "$ANTWORT" | grep -q '"online"[[:space:]]*:[[:space:]]*false'; then
      echo nein
    else
      echo unbekannt
    fi
  fi
}

DNS_NAME="${MCS_DNS_NAME:-}"
# Der Name kommt aus mcs.conf und wird in eine URL gesetzt. Was nicht wie
# ein Rechnername aussieht, wird verworfen statt eingesetzt.
if ! [[ "$DNS_NAME" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]{0,253}[A-Za-z0-9])?$ ]]; then
  DNS_NAME=""
fi

if [ "$NUR_LOKAL" = false ] && [ "$DIENST_AKTIV" = true ] \
   && command -v curl >/dev/null 2>&1; then
  # Über IPv4 wird der DNS-Name bevorzugt: Dann prüft derselbe Aufruf
  # gleich mit, ob der Name überhaupt auf diesen Server zeigt — und ob ein
  # SRV-Eintrag greift.
  if [ -n "$DNS_NAME" ]; then
    V4_ERREICHBAR=$(von_aussen_pruefen "$DNS_NAME")
  elif [ -n "$OEFF_IPV4" ] && [ "$IPV4_ART" = oeffentlich ]; then
    V4_ERREICHBAR=$(von_aussen_pruefen "$OEFF_IPV4")
  elif [ "$IPV4_ART" = cgnat ] || [ "$IPV4_ART" = keine ]; then
    # Gar nicht erst fragen: Die Antwort steht schon fest, und ein
    # überflüssiger Aufruf bei einem fremden Dienst bleibt überflüssig.
    V4_ERREICHBAR=nein
  fi

  if [ -n "$OEFF_IPV6" ]; then
    V6_ERREICHBAR=$(von_aussen_pruefen "[$OEFF_IPV6]")
  fi
fi

# ----------------------------------------------------------------------------
# 5) Das Urteil
# ----------------------------------------------------------------------------
# Reihenfolge ist alles: Zuerst die Ursachen, die auf diesem Pi liegen. Wer
# in einer Router-Oberfläche nach einer Freigabe sucht, während sein Server
# gar nicht läuft, sucht am falschen Ort.
URTEIL_ART=unklar
URTEIL_TEXT=""
RAT=()

if [ "$DIENST_AKTIV" != true ]; then
  URTEIL_ART=server-aus
  URTEIL_TEXT="Der Minecraft-Server läuft gerade nicht. Von außen ist deshalb nichts zu erreichen — unabhängig von Router und Anschluss."
  RAT=("Starten mit:  mcs start"
       "Danach diesen Test wiederholen.")
elif [ "$LOKAL_OFFEN" = nein ]; then
  URTEIL_ART=nicht-lokal
  URTEIL_TEXT="Der Dienst läuft, aber auf diesem Pi lauscht nichts auf Port ${PORT}. Damit kann auch von außen niemand ankommen."
  RAT=("Läuft der Server wirklich?  mcs status"
       "Steht in server.properties derselbe Port?  server-port=${PORT}"
       "Ins Server-Log sehen:  mcs log")
elif [ "$NUR_LOKAL" = true ] || [ "$NETZ_GEFRAGT" = false ]; then
  URTEIL_ART=nicht-gefragt
  URTEIL_TEXT="Es wurde nichts nach außen gefragt. Der Server läuft und lauscht auf Port ${PORT}; ob er aus dem Internet erreichbar ist, lässt sich von hier aus nicht sagen."
  RAT=("Vollständig prüfen:  mcs erreichbarkeit")
elif [ "$V4_ERREICHBAR" = ja ]; then
  URTEIL_ART=gut
  URTEIL_TEXT="Der Server ist aus dem Internet erreichbar. Mitspieler kommen herein."
  if [ -n "$DNS_NAME" ]; then
    RAT=("Mitspieler geben ein:  ${DNS_NAME}")
  else
    RAT=("Mitspieler geben ein:  ${OEFF_IPV4}:${PORT}"
         "Die Adresse ändert sich bei den meisten Anschlüssen regelmäßig."
         "Ein fester Name dafür: Konfigurationsseite, Abschnitt \"Dauerhafter Name\".")
  fi
elif [ "$V6_ERREICHBAR" = ja ] && [ "$V4_ERREICHBAR" = nein ]; then
  URTEIL_ART=nur-ipv6
  URTEIL_TEXT="Über IPv6 ist der Server erreichbar, über IPv4 nicht. Das ist das typische Bild bei einem DS-Lite-Anschluss — und es heißt: Alle Mitspieler mit IPv6 kommen schon jetzt herein, alle anderen nicht."
  RAT=("Mitspieler mit IPv6:  [${OEFF_IPV6}]:${PORT}"
       "Einen Namen dafür anlegen (AAAA-Eintrag) — die IPv6-Adresse ist zu lang zum Abtippen."
       "Für Mitspieler ohne IPv6 hilft nur ein Tunnel, z. B. playit.gg (siehe README).")
elif [ "$V6_ERREICHBAR" = ja ] && [ "$IPV4_ART" != cgnat ] \
     && ! { [ "$IPV4_ART" = keine ] && [ -n "$LOKAL_IPV6" ]; }; then
  # IPv6 belegt, IPv4 offen. Bis zum 23.09.2026 landete das bei "unklar" —
  # obwohl ein Teil gerade BEWIESEN war (Zweitmeinung zu Durchgang 1). Kein
  # DS-Lite-Urteil: Ueber IPv4 wissen wir nichts.
  #
  # Nicht bei cgnat/keine: Das sind SICHERE Aussagen ueber den Anschluss
  # (weiter unten), und dass eine Freigabe dort nichts nuetzt, ist die
  # wichtigste Nachricht. Und der Text sagt, WAS gescheitert ist — die
  # Adressabfrage oder nur die Pruefung von aussen (Zweitmeinung zu
  # Durchgang 2).
  URTEIL_ART=ipv6-belegt
  #
  # "keine" nur ausnehmen, wenn danach wirklich das sichere DS-Lite-Urteil
  # kommt (lokale IPv6 vorhanden); sonst fiel der Fall auf "unklar", obwohl
  # IPv6 belegt war. Und mit DNS-Namen wurde IPv4 ueber den NAMEN geprueft,
  # nicht ueber die Adresse — dann nennt der Text den Namen (Zweitmeinung zu
  # Durchgang 3, Befunde 2 und 3).
  if [ -n "$DNS_NAME" ]; then
    WAS_FEHLT="die Prüfung von außen über den Namen ${DNS_NAME} lieferte keine Antwort"
  elif [ "$IPV4_ART" = unbekannt ]; then
    WAS_FEHLT="die Abfrage der öffentlichen IPv4-Adresse ist gescheitert"
  else
    WAS_FEHLT="die Prüfung von außen über IPv4 (${OEFF_IPV4}) lieferte keine Antwort"
  fi
  URTEIL_TEXT="Über IPv6 ist der Server von außen erreichbar. Ob er es auch über IPv4 ist, ließ sich gerade nicht prüfen — ${WAS_FEHLT}."
  RAT=("Mitspieler mit IPv6:  [${OEFF_IPV6}]:${PORT}"
       "IPv4 später noch einmal prüfen:  mcs erreichbarkeit")
elif [ "$IPV4_ART" = keine ] && [ -n "$LOKAL_IPV6" ]; then
  URTEIL_ART=dslite
  URTEIL_TEXT="Dieser Anschluss hat gar keine öffentliche IPv4-Adresse, aber IPv6. Das ist DS-Lite. Eine Portfreigabe im Router kann daran nichts ändern — sie hätte nichts, was sie freigeben könnte."
  RAT=("Der Weg ist IPv6: Mitspieler mit IPv6 erreichen den Server direkt."
       "Dafür einen AAAA-Eintrag anlegen — Konfigurationsseite, \"Dauerhafter Name\"."
       "Für Mitspieler ohne IPv6: ein Tunnel wie playit.gg (siehe README)."
       "Manche Anbieter geben auf Anfrage eine echte IPv4-Adresse heraus.")
elif [ "$IPV4_ART" = cgnat ]; then
  URTEIL_ART=dslite
  URTEIL_TEXT="Die öffentliche Adresse ${OEFF_IPV4} liegt im Bereich 100.64.0.0/10 — den benutzen Anbieter für ihr eigenes NAT. Der Router hat also gar keine Adresse, die sich freigeben ließe."
  RAT=("Eine Portfreigabe im Router bleibt hier wirkungslos."
       "Falls IPv6 vorhanden ist, ist das der Weg."
       "Sonst: ein Tunnel wie playit.gg (siehe README).")
elif [ "$V4_ERREICHBAR" = nein ]; then
  URTEIL_ART=keine-freigabe
  URTEIL_TEXT="Der Server läuft und lauscht, aber von außen kommt niemand an ${OEFF_IPV4}:${PORT} an. Dafür gibt es zwei Ursachen, und von hier aus sind sie nicht zu unterscheiden."
  RAT=("1. Die Portfreigabe im Router fehlt oder zeigt auf das falsche Gerät."
       "   Weiterleiten: TCP Port ${PORT} auf ${LAN_IPV4:-die Adresse dieses Pi}."
       "2. Der Anschluss benutzt DS-Lite. Dann meldet der Prüfdienst die"
       "   Adresse des Anbieter-Gateways, und die sieht öffentlich aus."
       "So unterscheidest du beides: Im Router unter der Internetverbindung"
       "nachsehen. Steht dort keine eigene IPv4-Adresse, sondern nur IPv6 und"
       "ein Eintrag wie \"DS-Lite\" oder \"AFTR\", ist es DS-Lite."
       "(FRITZ!Box: Internet > Online-Monitor, bzw. Internet > Zugangsdaten > IPv6.)")
else
  URTEIL_ART=unklar
  URTEIL_TEXT="Es ließ sich nicht feststellen, ob der Server von außen erreichbar ist."
  RAT=("Prüfdienst nicht erreichbar oder keine Internetverbindung."
       "Später noch einmal versuchen.")
fi

# Was am Anschluss liegt, hängt nicht am Server. Läuft der gerade nicht oder
# ist er noch am Hochfahren, bricht der Test oben ab — die Auskunft über
# DS-Lite ist aber schon da und gerade dann wertvoll: Direkt nach der
# Installation erzeugt der Server minutenlang die Welt, und genau in dieser
# Zeit will man wissen, ob eine Portfreigabe später überhaupt etwas nützt.
if [ "$URTEIL_ART" = server-aus ] || [ "$URTEIL_ART" = nicht-lokal ]; then
  case "$IPV4_ART" in
    cgnat)
      RAT+=("" \
            "Schon jetzt sicher: Die öffentliche Adresse ${OEFF_IPV4} liegt im" \
            "Anbieter-NAT-Bereich (100.64.0.0/10). Eine Portfreigabe im Router" \
            "wird auch später nichts nützen — der Weg heißt IPv6 oder Tunnel.") ;;
    keine)
      if [ -n "$LOKAL_IPV6" ]; then
        RAT+=("" \
              "Schon jetzt sicher: Dieser Anschluss hat keine öffentliche" \
              "IPv4-Adresse, aber IPv6 — das ist DS-Lite. Eine Portfreigabe" \
              "wird auch später nichts nützen; der Weg heißt IPv6.")
      fi ;;
  esac
fi

# Ein negatives IPv6-Ergebnis ist weniger belastbar als ein positives:
# Es kann auch bedeuten, dass der Prüfdienst selbst kein IPv6 spricht.
# Das gehört dazugesagt, sonst sucht jemand einen Fehler in seiner
# Firewall, den es nicht gibt.
if [ -n "$OEFF_IPV6" ] && [ "$V6_ERREICHBAR" = nein ]; then
  RAT+=("Hinweis: Über IPv6 kam keine Antwort. Das kann am Server liegen —"
        "oder daran, dass der Prüfdienst selbst kein IPv6 spricht. Ein"
        "Mitspieler mit IPv6 ist hier die verlässlichere Auskunft.")
fi

# ----------------------------------------------------------------------------
# Ausgabe
# ----------------------------------------------------------------------------
if [ "$AUSGABE" = json ]; then
  # Kleiner eigener Maskierer statt jq: Die Werte hier sind Adressen,
  # Portnummern und Texte aus diesem Skript — kein fremder Inhalt. jq wäre
  # trotzdem schöner, aber dieses Skript soll auch dann noch ein Ergebnis
  # liefern, wenn auf dem Gerät sonst nichts installiert ist.
  jstr() {
    printf '"%s"' "$(printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g')"
  }
  jbool() { [ "$1" = true ] && printf 'true' || printf 'false'; }

  printf '{\n'
  printf '  "port": %s,\n' "$PORT"
  printf '  "dienst_aktiv": %s,\n' "$(jbool "$DIENST_AKTIV")"
  printf '  "lokal_offen": %s,\n' "$(jstr "$LOKAL_OFFEN")"
  printf '  "lan_ipv4": %s,\n' "$(jstr "$LAN_IPV4")"
  printf '  "lokal_ipv6": %s,\n' "$(jstr "$LOKAL_IPV6")"
  printf '  "oeff_ipv4": %s,\n' "$(jstr "$OEFF_IPV4")"
  printf '  "oeff_ipv6": %s,\n' "$(jstr "$OEFF_IPV6")"
  printf '  "ipv4_art": %s,\n' "$(jstr "$IPV4_ART")"
  printf '  "dns_name": %s,\n' "$(jstr "$DNS_NAME")"
  printf '  "v4_erreichbar": %s,\n' "$(jstr "$V4_ERREICHBAR")"
  printf '  "v6_erreichbar": %s,\n' "$(jstr "$V6_ERREICHBAR")"
  printf '  "netz_gefragt": %s,\n' "$(jbool "$NETZ_GEFRAGT")"
  printf '  "urteil_art": %s,\n' "$(jstr "$URTEIL_ART")"
  printf '  "urteil_text": %s,\n' "$(jstr "$URTEIL_TEXT")"
  printf '  "rat": ['
  TRENNER=""
  for Z in ${RAT+"${RAT[@]}"}; do
    printf '%s%s' "$TRENNER" "$(jstr "$Z")"; TRENNER=", "
  done
  printf ']\n}\n'
  exit 0
fi

echo "=== Erreichbarkeit von außen ==="
echo ""
echo "Spielport:            $PORT"
echo "Server läuft:         $([ "$DIENST_AKTIV" = true ] && echo ja || echo nein)"
echo "Lauscht auf dem Pi:   $LOKAL_OFFEN"
echo "Adresse im Heimnetz:  ${LAN_IPV4:-nicht feststellbar}"
if [ "$NETZ_GEFRAGT" = true ]; then
  case "$IPV4_ART" in
    oeffentlich) echo "Öffentliche IPv4:     $OEFF_IPV4" ;;
    cgnat)       echo "Öffentliche IPv4:     $OEFF_IPV4  (Anbieter-NAT, 100.64.0.0/10)" ;;
    keine)       echo "Öffentliche IPv4:     keine" ;;
    *)           echo "Öffentliche IPv4:     nicht feststellbar" ;;
  esac
  echo "Öffentliche IPv6:     ${OEFF_IPV6:-keine}"
  [ -n "$DNS_NAME" ] && echo "Name:                 $DNS_NAME"
  echo "Von außen über IPv4:  $V4_ERREICHBAR"
  echo "Von außen über IPv6:  $V6_ERREICHBAR"
else
  echo ""
  echo "(Es wurde nichts nach außen gefragt.)"
fi
echo ""
echo "-----------------------------------------------------------"
echo "$URTEIL_TEXT" | fold -s -w 59
echo ""
for Z in ${RAT+"${RAT[@]}"}; do echo "  $Z"; done
echo "-----------------------------------------------------------"

# Rückgabewert: 0, wenn erreichbar; 1 sonst. So lässt sich der Test auch in
# einem Skript benutzen — "unklar" gilt dabei als nicht erreichbar, denn
# eine unbeantwortete Frage ist keine Bestätigung.
[ "$URTEIL_ART" = gut ] && exit 0
exit 1
