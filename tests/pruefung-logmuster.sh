#!/bin/bash
#
# pruefung-logmuster.sh — Erkennen alle Auswertungen Beitritt und Austritt?
#
# Warum ein eigener Test: Seit Paper 26.3 stehen Beitritt und Verlassen so
# im Server-Log:
#   [13:21:03] [Server thread/INFO]: System chat: Steve joined the game
# Die Muster in tools/log-muster.sh erwarteten den Namen direkt hinter
# "]: ". Vom 14.10. bis zum 21.10.2026 zaehlte die Oberflaeche deshalb
# 0 Spieler, die Historie bekam keine einzige Sitzung, und vor einem
# Neustart wurde niemand mehr gewarnt — ohne jede Fehlermeldung, denn
# "nichts gefunden" ist fuer jede dieser Auswertungen ein gueltiges Ergebnis.
#
# Geprueft werden die ECHTEN Nutzer der Muster, kein Nachbau: Jeder greift
# den Namen auf seine Weise — log_player_activity.sh ueber BASH_REMATCH,
# das Nachtragewerkzeug ueber groups(), protokoll.py tolerant. Ein Test nur
# des Ausdrucks haette die verschobene Gruppennummer nicht bemerkt.
#
# Laeuft in einem Wegwerfverzeichnis, dauert ein bis zwei Sekunden.
# Aufruf: make muster

set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP="$(mktemp -d)"
LAUSCHER=""
aufraeumen() {
  [ -n "$LAUSCHER" ] && kill -- -"$LAUSCHER" 2>/dev/null || true
  rm -rf "$TMP"
}
trap aufraeumen EXIT

export MCS_CONF="$TMP/gibt-es-nicht.conf"
export MCS_LOG_MUSTER="$REPO/tools/log-muster.sh"
export MCS_MINECRAFT_LOG="$TMP/latest.log"
export MCS_PLAYER_ACTIVITY_LOG="$TMP/player_activity.log"

# Beide Formate, dazu zwei Zeilen, die NICHT zaehlen duerfen: eine Chatzeile,
# die wie ein Beitritt klingt, und eine Systemmeldung ohne Spieler.
BEITRITTE='[10:00:00] [Server thread/INFO]: Spieler_A joined the game
[10:00:05] [Server thread/INFO]: System chat: Spieler_B joined the game
[10:00:06] [Async Chat Thread - #1/INFO]: <Spieler_A> Spieler_C joined the game
[10:00:07] [Server thread/INFO]: System chat: Stopping the server'
AUSTRITTE='[10:05:00] [Server thread/INFO]: Spieler_A lost connection: Disconnected
[10:05:00] [Server thread/INFO]: Spieler_A left the game
[10:06:00] [Server thread/INFO]: Spieler_B lost connection: Disconnected
[10:06:00] [Server thread/INFO]: System chat: Spieler_B left the game'

FEHLER=0
pruefe() {  # pruefe <was> <ist> <soll>
  if [ "$2" = "$3" ]; then
    echo "  ok  $1"
  else
    echo "  FEHLER $1: ist '$2', soll '$3'"
    FEHLER=1
  fi
}

echo "== Logmuster: Beitritt und Austritt, Paper 26.2 und 26.3 =="

# --- 1) Spielerprotokoll (Bash, BASH_REMATCH) --------------------------------
: > "$MCS_MINECRAFT_LOG"
setsid bash "$REPO/tools/log_player_activity.sh" &
LAUSCHER=$!
# tail -n 0 liest nur, was NACH seinem Start dazukommt. Also warten, bis es
# laeuft — sonst gingen die Zeilen unter, und der Test laege am Takt, nicht
# am Muster.
for _ in $(seq 50); do
  pgrep -f "tail -n 0 -F $MCS_MINECRAFT_LOG" >/dev/null && break
  sleep 0.1
done
printf '%s\n%s\n' "$BEITRITTE" "$AUSTRITTE" >> "$MCS_MINECRAFT_LOG"
for _ in $(seq 50); do
  [ "$(grep -c ' | ' "$MCS_PLAYER_ACTIVITY_LOG" 2>/dev/null || true)" -ge 6 ] && break
  sleep 0.1
done
kill -- -"$LAUSCHER" 2>/dev/null || true
LAUSCHER=""
PROTOKOLL="$(cut -d'|' -f2- "$MCS_PLAYER_ACTIVITY_LOG" | sed 's/^ //' | sort)"
pruefe "Spielerprotokoll: Beitritte" \
  "$(grep -c 'ist dem Spiel beigetreten' <<<"$PROTOKOLL" || true)" 2
pruefe "Spielerprotokoll: Beitritt im 26.3-Format" \
  "$(grep -c '^Spieler_B ist dem Spiel beigetreten$' <<<"$PROTOKOLL" || true)" 1
pruefe "Spielerprotokoll: Verlassen im 26.3-Format" \
  "$(grep -c '^Spieler_B hat das Spiel verlassen$' <<<"$PROTOKOLL" || true)" 1
pruefe "Spielerprotokoll: Chatzeile zaehlt nicht" \
  "$(grep -c 'Spieler_C' <<<"$PROTOKOLL" || true)" 0

# --- 2) Oberflaeche (protokoll.online_players) und Nachtrag (groups()) -------
printf '%s\n' "$BEITRITTE" > "$MCS_MINECRAFT_LOG"
PYTHON_ERGEBNIS="$(AUSTRITTE="$AUSTRITTE" python3 - "$REPO" <<'PYTEST'
import importlib.util, os, sys
repo = sys.argv[1]
sys.path.insert(0, f"{repo}/admin")
import protokoll

online = ",".join(protokoll.online_players())
with open(os.environ["MCS_MINECRAFT_LOG"], "a", encoding="utf-8") as f:
    f.write(os.environ["AUSTRITTE"] + "\n")
nachher = ",".join(protokoll.online_players()) or "-"
print(f"online|{online}")
print(f"nachher|{nachher}")

spec = importlib.util.spec_from_file_location(
    "nachtragen", f"{repo}/tools/spielerprotokoll-nachtragen.py")
nachtragen = importlib.util.module_from_spec(spec)
spec.loader.exec_module(nachtragen)
zeilen = (open(os.environ["MCS_MINECRAFT_LOG"], encoding="utf-8")
          .read().splitlines())
texte = []
for zeile in zeilen:
    for muster, _rang, bauen in nachtragen.EREIGNISSE:
        treffer = muster.search(zeile)
        if treffer:
            texte.append(bauen(treffer.groups()))
print("nachtrag|" + ";".join(sorted(texte)))
PYTEST
)"
wert() { grep "^$1|" <<<"$PYTHON_ERGEBNIS" | cut -d'|' -f2-; }
pruefe "Oberflaeche: online nach den Beitritten" "$(wert online)" "Spieler_A,Spieler_B"
pruefe "Oberflaeche: online nach den Austritten" "$(wert nachher)" "-"
pruefe "Nachtrag: erkannte Ereignisse" "$(wert nachtrag)" \
  "Spieler_A hat das Spiel verlassen;Spieler_A hat die Verbindung verloren (Grund: Disconnected);Spieler_A ist dem Spiel beigetreten;Spieler_B hat das Spiel verlassen;Spieler_B hat die Verbindung verloren (Grund: Disconnected);Spieler_B ist dem Spiel beigetreten"

# --- 3) Waechter: Anmeldungen ohne erkannten Beitritt ------------------------
# Der Fall vom 14.10.2026, nachgestellt: Das Muster erkennt das neue Format
# nicht. Dazu wird ein absichtlich veraltetes Muster (ohne "System chat: ")
# uebergeben. Gegenproben: das echte Muster schweigt, ein Log ohne
# Anmeldungen schweigt, und ein Zeuge in der LETZTEN Zeile zaehlt noch nicht.
WAECHTER="$(python3 - "$REPO" "$TMP" <<'PYTEST'
import re, sys
repo, tmp = sys.argv[1], sys.argv[2]
sys.path.insert(0, f"{repo}/admin")
import protokoll, protokollpruefung as w

alt_re = re.compile(r"^\[([^]]+)\] \[[^]]*\]: ([A-Za-z0-9_]{1,16}) joined the game$")
log = f"{tmp}/waechter.log"
def schreiben(text):
    with open(log, "w", encoding="utf-8") as f:
        f.write(text)

neu_format = ("[13:21:03] [Server thread/INFO]: System chat: Spieler_B joined the game\n"
              "[13:21:03] [Server thread/INFO]: Spieler_B[/192.0.2.7:5000] logged in with entity id 7 at ([Welt]1, 2, 3)\n"
              "[13:21:04] [Server thread/INFO]: Spieler_B hat etwas gebaut\n")
schreiben(neu_format)
b = w.beitritte_unerkannt(log, alt_re, w._neuer_stand())
print("veraltet|" + (str(b["zeugen"]) if b else "-"))
print("echt|" + ("meldet" if w.beitritte_unerkannt(log, protokoll.JOIN_RE, w._neuer_stand()) else "-"))

schreiben("[10:00:06] [Async Chat Thread - #1/INFO]: <Spieler_A> Spieler_C joined the game\n"
          "[10:00:07] [Server thread/INFO]: Done (21.1s)!\n")
print("chat|" + ("meldet" if w.beitritte_unerkannt(log, alt_re, w._neuer_stand()) else "-"))

# Zeuge in der letzten Zeile: erst offen, nach einer weiteren Zeile gezaehlt.
stand = w._neuer_stand()
schreiben("[13:21:03] [Server thread/INFO]: Spieler_B[/192.0.2.7:5000] logged in with entity id 7 at ([Welt]1, 2, 3)\n")
erst = w.beitritte_unerkannt(log, alt_re, stand)
with open(log, "a", encoding="utf-8") as f:
    f.write("[13:21:03] [Server thread/INFO]: System chat: Spieler_B joined the game\n"
            "[13:21:04] [Server thread/INFO]: noch eine Zeile\n")
dann = w.beitritte_unerkannt(log, alt_re, stand)
print("letzte_zeile|" + ("meldet" if erst else "-") + "," + (str(dann["zeugen"]) if dann else "-"))
PYTEST
)"
pruefe "Waechter: veraltetes Muster meldet einen Beitritt" "$(grep '^veraltet|' <<<"$WAECHTER" | cut -d'|' -f2)" 1
pruefe "Waechter: echtes Muster schweigt" "$(grep '^echt|' <<<"$WAECHTER" | cut -d'|' -f2)" "-"
pruefe "Waechter: Chatzeile ist kein Zeuge" "$(grep '^chat|' <<<"$WAECHTER" | cut -d'|' -f2)" "-"
pruefe "Waechter: Zeuge in der letzten Zeile zaehlt erst danach" "$(grep '^letzte_zeile|' <<<"$WAECHTER" | cut -d'|' -f2)" "-,1"

exit "$FEHLER"
