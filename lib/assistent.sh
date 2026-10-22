# shellcheck shell=bash
# (Keine Shebang: Diese Datei wird eingebunden, nicht ausgeführt. Die
#  Direktive darüber sagt shellcheck trotzdem, welche Shell gemeint ist.)
# lib/assistent.sh — Die Bausteine für den geführten Installationsassistenten.
#
# Wird von install.sh eingebunden, nicht selbst ausgeführt.
#
# ----------------------------------------------------------------------------
# Zwei Regeln, die den ganzen Aufbau erklären
# ----------------------------------------------------------------------------
# 1. JEDE Frage muss auch ohne Rückfrage beantwortbar sein. Der Assistent ist
#    die bequeme Fassung, nicht die einzige: `install.sh --standard` nimmt
#    überall die Empfehlung und fragt nichts. Ohne das wäre
#    tests/abnahme-im-container.sh tot — der läuft ohne Terminal.
#
# 2. Farben und Rahmen nur, wenn wirklich ein Terminal zuschaut. Läuft die
#    Ausgabe in eine Datei oder durch eine Pipe, wären Steuerzeichen dort
#    nur Müll, der später beim Fehlersuchen stört.
# ----------------------------------------------------------------------------

# --- Darstellung -------------------------------------------------------------
if [ -t 1 ] && [ "${TERM:-dumb}" != "dumb" ] && [ -z "${NO_COLOR:-}" ]; then
  F_TITEL=$'\033[1m'        # fett
  F_LEISE=$'\033[2m'        # gedimmt
  F_GRUEN=$'\033[32m'
  F_GELB=$'\033[33m'
  F_AUS=$'\033[0m'
else
  F_TITEL=''; F_LEISE=''; F_GRUEN=''; F_GELB=''; F_AUS=''
fi

# Wird von install.sh auf true gesetzt, wenn --standard übergeben wurde.
ASSISTENT_STANDARD="${ASSISTENT_STANDARD:-false}"

# Breite der Trennlinien.
_LINIE='────────────────────────────────────────────────────────────'

_zeile() { printf '  %s\n' "$*"; }
_leer()  { printf '\n'; }


# Kopfbereich zu Beginn der Installation.
assistent_kopf() {
  _leer
  printf '  %sPi-MCS%s  ·  Minecraft-Server für den Raspberry Pi\n' "$F_TITEL" "$F_AUS"
  printf '  %s%s%s\n' "$F_LEISE" "$_LINIE" "$F_AUS"
  _leer
  if [ "$ASSISTENT_STANDARD" = true ]; then
    _zeile "${F_LEISE}Schnellmodus: alle Empfehlungen werden übernommen, es wird nichts gefragt.${F_AUS}"
  else
    _zeile "Ein paar Fragen, dann läuft die Installation durch."
    _zeile "${F_LEISE}Bei jeder Frage genügt die Eingabetaste für die Empfehlung.${F_AUS}"
    _zeile "${F_LEISE}Abbrechen mit Strg+C — bis zur Zusammenfassung wird nichts verändert.${F_AUS}"
  fi
  _leer
}


# Überschrift eines Schritts:  assistent_schritt 3 7 "Spielmodus"
assistent_schritt() {
  [ "$ASSISTENT_STANDARD" = true ] && return 0
  _leer
  printf '  %s%s%s\n' "$F_LEISE" "$_LINIE" "$F_AUS"
  printf '  %sSchritt %s von %s%s · %s%s%s\n' \
    "$F_LEISE" "$1" "$2" "$F_AUS" "$F_TITEL" "$3" "$F_AUS"
  _leer
}


# Überschrift für eine Frage, die AUSSERHALB der Zählung steht.
#
# Es gibt genau eine solche: der Installationsort. Er wird vor der
# Vorprüfung gefragt (sie misst den Platz auf dem Ziel) und nur dann, wenn
# es noch keine Installation gibt — er passt damit in keine feste Nummer.
# "Schritt 0 von 6" wäre die naheliegende Notlösung und liest sich wie ein
# Fehler; eine Zählung, die je nach Vorgeschichte bei 1 oder bei 2 anfängt,
# wäre nicht besser.
assistent_abschnitt() {
  [ "$ASSISTENT_STANDARD" = true ] && return 0
  _leer
  printf '  %s%s%s\n' "$F_LEISE" "$_LINIE" "$F_AUS"
  printf '  %s%s%s\n' "$F_TITEL" "$1" "$F_AUS"
  _leer
}


# Erklärender Fließtext unter einer Überschrift.
assistent_text() {
  [ "$ASSISTENT_STANDARD" = true ] && return 0
  local Z
  for Z in "$@"; do _zeile "$Z"; done
  _leer
}


# ----------------------------------------------------------------------------
# frage_auswahl VARNAME STANDARDNUMMER "wert|Kurztext|Erklärung" ...
# ----------------------------------------------------------------------------
# Setzt VARNAME auf den gewählten Wert. Im Schnellmodus wird ohne Ausgabe die
# Standardnummer genommen.
frage_auswahl() {
  local VARNAME="$1"; shift
  local STANDARD="$1"; shift
  local -a WERTE=() KURZ=() ERKL=()
  local EINTRAG

  for EINTRAG in "$@"; do
    WERTE+=("${EINTRAG%%|*}")
    local REST="${EINTRAG#*|}"
    KURZ+=("${REST%%|*}")
    ERKL+=("${REST#*|}")
  done

  if [ "$ASSISTENT_STANDARD" = true ]; then
    printf -v "$VARNAME" '%s' "${WERTE[$((STANDARD - 1))]}"
    return 0
  fi

  local I
  for I in "${!WERTE[@]}"; do
    printf '    %s[%s]%s %-12s %s%s%s\n' \
      "$F_TITEL" "$((I + 1))" "$F_AUS" "${KURZ[$I]}" "$F_LEISE" "${ERKL[$I]}" "$F_AUS"
  done
  _leer

  local ANTWORT
  while true; do
    printf '  %s>%s Auswahl [1-%s] (Enter = %s): ' \
      "$F_GRUEN" "$F_AUS" "${#WERTE[@]}" "$STANDARD"
    read -r ANTWORT || ANTWORT=''
    ANTWORT="${ANTWORT:-$STANDARD}"
    if [[ "$ANTWORT" =~ ^[0-9]+$ ]] && [ "$ANTWORT" -ge 1 ] && [ "$ANTWORT" -le "${#WERTE[@]}" ]; then
      printf -v "$VARNAME" '%s' "${WERTE[$((ANTWORT - 1))]}"
      printf '    %s✓ %s%s\n' "$F_GRUEN" "${KURZ[$((ANTWORT - 1))]}" "$F_AUS"
      return 0
    fi
    printf '    %sBitte eine Zahl zwischen 1 und %s eingeben.%s\n' \
      "$F_GELB" "${#WERTE[@]}" "$F_AUS"
  done
}


# ----------------------------------------------------------------------------
# frage_ja_nein VARNAME j|n "Frage"
# ----------------------------------------------------------------------------
# Setzt VARNAME auf "true" oder "false".
frage_ja_nein() {
  local VARNAME="$1" STANDARD="$2" TEXT="$3"

  if [ "$ASSISTENT_STANDARD" = true ]; then
    [ "$STANDARD" = j ] && printf -v "$VARNAME" 'true' || printf -v "$VARNAME" 'false'
    return 0
  fi

  local HINWEIS ANTWORT
  [ "$STANDARD" = j ] && HINWEIS='[J/n]' || HINWEIS='[j/N]'

  while true; do
    printf '  %s>%s %s %s ' "$F_GRUEN" "$F_AUS" "$TEXT" "$HINWEIS"
    read -r ANTWORT || ANTWORT=''
    ANTWORT="${ANTWORT:-$STANDARD}"
    case "${ANTWORT,,}" in
      j|ja|y|yes) printf -v "$VARNAME" 'true';  printf '    %s✓ ja%s\n'   "$F_GRUEN" "$F_AUS"; return 0 ;;
      n|nein|no)  printf -v "$VARNAME" 'false'; printf '    %s✓ nein%s\n' "$F_GRUEN" "$F_AUS"; return 0 ;;
      *) printf '    %sBitte j oder n eingeben.%s\n' "$F_GELB" "$F_AUS" ;;
    esac
  done
}


# ----------------------------------------------------------------------------
# frage_zahl VARNAME STANDARD MIN MAX "Frage"
# ----------------------------------------------------------------------------
frage_zahl() {
  local VARNAME="$1" STANDARD="$2" MIN="$3" MAX="$4" TEXT="$5"

  if [ "$ASSISTENT_STANDARD" = true ]; then
    printf -v "$VARNAME" '%s' "$STANDARD"
    return 0
  fi

  local ANTWORT
  while true; do
    printf '  %s>%s %s (Enter = %s): ' "$F_GRUEN" "$F_AUS" "$TEXT" "$STANDARD"
    read -r ANTWORT || ANTWORT=''
    ANTWORT="${ANTWORT:-$STANDARD}"
    if [[ "$ANTWORT" =~ ^[0-9]+$ ]] && [ "$ANTWORT" -ge "$MIN" ] && [ "$ANTWORT" -le "$MAX" ]; then
      # Fuehrende Nullen weg ("08" -> "8"). Wer die Backup-Stunde als "08"
      # tippt, tippt sie so, wie sie auf jeder Uhr steht — und printf '%02d'
      # in install.sh las "08" als ungueltige Oktalzahl. Unter der ERR-Falle
      # brach das die Installation in Schritt 6 ab, nach Welt und Diensten
      # (gemessen 23.09.2026).
      ANTWORT=$((10#$ANTWORT))
      printf -v "$VARNAME" '%s' "$ANTWORT"
      printf '    %s✓ %s%s\n' "$F_GRUEN" "$ANTWORT" "$F_AUS"
      return 0
    fi
    printf '    %sBitte eine Zahl zwischen %s und %s eingeben.%s\n' \
      "$F_GELB" "$MIN" "$MAX" "$F_AUS"
  done
}


# ----------------------------------------------------------------------------
# frage_text VARNAME "standard" "Frage"
# ----------------------------------------------------------------------------
# Leere Eingabe ist erlaubt und ergibt den Standardwert; ein einzelnes "-"
# ergibt bewusst einen leeren Wert (z. B. "kein zweites Backup-Ziel").
frage_text() {
  local VARNAME="$1" STANDARD="$2" TEXT="$3"

  if [ "$ASSISTENT_STANDARD" = true ]; then
    printf -v "$VARNAME" '%s' "$STANDARD"
    return 0
  fi

  local ANTWORT
  printf '  %s>%s %s (Enter = %s, "-" = leer): ' \
    "$F_GRUEN" "$F_AUS" "$TEXT" "${STANDARD:-leer}"
  read -r ANTWORT || ANTWORT=''
  [ -z "$ANTWORT" ] && ANTWORT="$STANDARD"
  [ "$ANTWORT" = '-' ] && ANTWORT=''
  printf -v "$VARNAME" '%s' "$ANTWORT"
  printf '    %s✓ %s%s\n' "$F_GRUEN" "${ANTWORT:-(leer)}" "$F_AUS"
}


# ----------------------------------------------------------------------------
# Zusammenfassung vor dem Loslegen — der letzte Punkt zum Abbrechen
# ----------------------------------------------------------------------------
# Erwartet Paare: assistent_zusammenfassung "Bezeichnung" "Wert" ...
# Gibt 0 zurück, wenn losgelegt werden soll, sonst 1.
assistent_zusammenfassung() {
  _leer
  printf '  %s%s%s\n' "$F_LEISE" "$_LINIE" "$F_AUS"
  printf '  %sSo wird installiert%s\n' "$F_TITEL" "$F_AUS"
  _leer

  # Ausrichten von Hand statt mit printf %-26s: printf zählt BYTES, und ein
  # Umlaut belegt in UTF-8 zwei davon. "Weboberfläche" wäre dadurch eine
  # Spalte zu weit links gerutscht. ${#TEXT} zählt dagegen Zeichen.
  local TEXT FUELL
  while [ $# -gt 1 ]; do
    TEXT="$1"
    FUELL=$(( 26 - ${#TEXT} ))
    [ "$FUELL" -lt 1 ] && FUELL=1
    printf '    %s%*s%s\n' "$TEXT" "$FUELL" '' "$2"
    shift 2
  done
  _leer
  _zeile "${F_LEISE}Bis hierher wurde nichts verändert.${F_AUS}"
  _leer

  [ "$ASSISTENT_STANDARD" = true ] && return 0

  local ANTWORT
  printf '  %s>%s Installation jetzt starten? [J/n] ' "$F_GRUEN" "$F_AUS"
  read -r ANTWORT || ANTWORT=''
  ANTWORT="${ANTWORT:-j}"
  _leer
  case "${ANTWORT,,}" in
    j|ja|y|yes) return 0 ;;
    *) return 1 ;;
  esac
}


# Abschlussbildschirm.  assistent_ende "Zeile" "Zeile" ...
assistent_ende() {
  _leer
  printf '  %s%s%s\n' "$F_LEISE" "$_LINIE" "$F_AUS"
  printf '  %s%s✓ Fertig%s\n' "$F_GRUEN" "$F_TITEL" "$F_AUS"
  _leer
  local Z
  for Z in "$@"; do _zeile "$Z"; done
  _leer
}
