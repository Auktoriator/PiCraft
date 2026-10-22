# Makefile — Prüfungen vor dem Committen.
#
# Aufruf:
#   make          alle Prüfungen
#   make syntax   nur Syntaxprüfung (braucht nur bash und python3)
#   make lint     zusätzlich shellcheck, falls installiert
#
# Warum? Bisher gab es keine automatische Prüfung. shellcheck lief einmal
# von Hand — was danach hineingeriet, hat niemand mehr kontrolliert.

SHELL := /bin/bash

# Gefunden statt aufgezaehlt — seit dem 2026-09-02.
#
# Hier stand eine handgepflegte Liste, und darueber 14 Zeilen Kommentar, die
# protokollierten, wie oft sie danebenlag: die Skripte unter tests/ fehlten
# bis 2026-08-28, die drei lib/*.sh bis 2026-08-30, server/lib-konsole.sh bis
# 2026-08-31. Alle drei Male aus demselben Grund — eine Datei kam dazu, die
# Liste nicht. Ausgerechnet lib-konsole.sh: CLAUDE.md nennt sie den einzigen
# Ort, an dem PiCraft mit der Server-Konsole redet, und ein Syntaxfehler darin
# bricht Serverstart, Stopp-Weg und Backup auf einmal.
#
# Eine Liste, die dreimal still danebenlag, ist keine Liste. Gefunden wird
# jetzt: jede *.sh im Repository, dazu tools/mcs (das keine Endung hat, weil
# es als Befehl aufgerufen wird).
#
# Der find-Rueckfall ist noetig, weil dieses Repository oeffentlich werden
# soll: Wer es als ZIP herunterlaedt, hat kein Git.
#
# "--others --exclude-standard" nimmt auch noch nicht eingecheckte Dateien
# mit. Ohne das pruefte "make" ein neu angelegtes Skript genau so lange
# nicht, wie es am dringendsten noetig waere: vor dem ersten Commit.
SKRIPTE := $(shell git ls-files --cached --others --exclude-standard '*.sh' 2>/dev/null || \
                   find . -name '*.sh' -not -path './.git/*' | sort) tools/mcs

define JS_KOMMENTAR_PRUEFUNG
import re, pathlib, sys
fehler = 0
for p in sorted(pathlib.Path("admin/templates").rglob("*.html")):
    for m in re.finditer(r"<script>(.*?)</script>", p.read_text(encoding="utf-8"), re.S):
        auf, zu = m.group(1).count("/*"), m.group(1).count("*/")
        if auf != zu:
            print(f"  FEHLER in {p}: {auf}x /* aber {zu}x */ im <script>")
            fehler = 1
if fehler:
    sys.exit(1)
print("  ok  Kommentarklammern in den Vorlagen-Skripten")
endef
export JS_KOMMENTAR_PRUEFUNG

.PHONY: alles syntax lint python konfig backup muster kopien
alles: syntax python konfig lint backup muster kopien

syntax:
	@echo "== Shell-Syntax =="
	@for f in $(SKRIPTE); do bash -n "$$f" && echo "  ok  $$f" || exit 1; done

python:
	@echo "== Python-Syntax =="
	@# Das "|| exit 1" ist nicht schmueckend: Der Rueckgabewert einer
	@# for-Schleife ist der des LETZTEN Durchlaufs, und das "&&" ueberspringt
	@# nur das echo. Ohne den Abbruch blieb "make" gruen, sobald die kaputte
	@# Datei nicht die alphabetisch letzte war (gefunden 2026-08-31).
	@# tools/*.py steht seit v1.1 mit in dieser Liste. Vorher pruefte "make"
	@# ausschliesslich admin/ — ein Python-Werkzeug unter tools/ waere von
	@# keiner einzigen Pruefung erfasst gewesen. Genau dieselbe Luecke wie
	@# bei den lib-*.sh und bei server/lib-konsole.sh, beide oben beschrieben.
	@# tests/*.py kam am 21.09.2026 dazu, aus demselben Grund und beim
	@# dritten Mal: Eine Pruefdatei, die selbst von keiner Pruefung erfasst
	@# ist, faellt genauso still aus wie der Code, den sie bewachen soll.
	@for f in admin/*.py tools/*.py tests/*.py; do python3 -m py_compile "$$f" && echo "  ok  $$f" || exit 1; done
	@rm -rf admin/__pycache__ tools/__pycache__ tests/__pycache__
	@# pyflakes findet, was die Syntaxpruefung nicht sieht: fehlende Importe,
	@# nicht definierte Namen, ueberfluessige Importe. Bei der Aufteilung von
	@# app.py am 2026-08-28 hat es auf einen Schlag 17 solcher Stellen
	@# gefunden -- von Hand haette man sie einzeln beim Ausprobieren erwischt.
	@if command -v pyflakes >/dev/null 2>&1; then \
	  pyflakes admin/*.py tools/*.py tests/*.py && echo "  ok  pyflakes: keine Beanstandungen"; \
	elif python3 -c "import pyflakes" >/dev/null 2>&1; then \
	  python3 -m pyflakes admin/*.py tools/*.py tests/*.py && echo "  ok  pyflakes: keine Beanstandungen"; \
	else \
	  echo "  !! ÜBERSPRUNGEN — pyflakes ist nicht installiert."; \
	  echo "     Damit prueft 'make' hier WENIGER als die GitHub Action,"; \
	  echo "     und ein gruenes 'make' sagt nichts ueber sie aus."; \
	  echo "     Genau so ist am 2026-08-29 ein ungenutzter Import auf main"; \
	  echo "     gelandet und hat die Action rot gemacht."; \
	  echo "     Debian/Pi:  sudo apt-get install -y pyflakes3"; \
	  echo "     sonst:      pip install pyflakes"; \
	fi

konfig:
	@echo "== Konfigurationsdateien =="
	@# mcs.conf.beispiel und versions.env müssen von Shell UND systemd lesbar
	@# sein (die Vorlage wird von install.sh nur um Platzhalter erweitert):
	@# also reine KEY=WERT-Zeilen ohne Leerzeichen um das Gleichheitszeichen.
	@for f in mcs.conf.beispiel server/versions.env; do \
	  if grep -nE '^[A-Za-z_][A-Za-z0-9_]*[[:space:]]+=|^[A-Za-z_][A-Za-z0-9_]*=[[:space:]]' "$$f"; then \
	    echo "  FEHLER in $$f: Leerzeichen um '=' — systemd kann das nicht lesen"; exit 1; \
	  fi; \
	  bash -n "$$f" && echo "  ok  $$f" || exit 1; \
	done
	@# Kommentarklammern in den Skriptbloecken der Vorlagen.
	@#
	@# Warum ausgerechnet das? Am 2026-09-02 ist beim Umbau der Kartenseite
	@# ein "*/" zu viel stehen geblieben. Folge: ein Syntaxfehler, der das
	@# GANZE Skript der Seite abschaltet -- kein Rahmen, kein Link, keine
	@# Fehlermeldung. Weder "make" noch der Abnahmetest haben es gesehen,
	@# beide pruefen nur Shell und Python. Ein JS-Interpreter ist auf dem Pi
	@# nicht installiert; diese acht Zeilen fangen wenigstens den Fehler ab,
	@# der hier wirklich passiert ist.
	@python3 -c "$$JS_KOMMENTAR_PRUEFUNG"
	@# mcs.conf gehoert dem Pi, nicht dem Repository (Befund B2). Waere sie
	@# wieder versioniert, ueberschriebe jedes ./deploy.sh die Einstellungen
	@# des Nutzers — genau der Fehler, der am 2026-08-28 behoben wurde.
	@if git ls-files --error-unmatch mcs.conf >/dev/null 2>&1; then \
	  echo "  FEHLER: mcs.conf ist wieder versioniert. Richtig: git rm --cached mcs.conf"; exit 1; \
	else \
	  echo "  ok  mcs.conf ist nicht versioniert"; \
	fi
	@# Dasselbe fuer server/plugins.txt (Etappe C): Seit die Weboberflaeche
	@# Plugins installiert und dort eintraegt, gehoert die Liste dem Pi.
	@# Im Repo liegt nur server/plugins.txt.beispiel.
	@if git ls-files --error-unmatch server/plugins.txt >/dev/null 2>&1; then \
	  echo "  FEHLER: server/plugins.txt ist versioniert. Richtig: nur plugins.txt.beispiel"; exit 1; \
	else \
	  echo "  ok  server/plugins.txt ist nicht versioniert"; \
	fi

lint:
	@echo "== shellcheck =="
	@if command -v shellcheck >/dev/null 2>&1; then \
	  shellcheck -S warning -e SC1091 $(SKRIPTE) && echo "  ok  keine Beanstandungen"; \
	else \
	  echo "  übersprungen (shellcheck nicht installiert:"; \
	  echo "   Debian/Pi: sudo apt-get install -y shellcheck)"; \
	fi

backup:
	@# Rotation und Dauerarchiv gegen unbrauchbare Zahlen in der mcs.conf.
	@# Laeuft in einem Wegwerfverzeichnis, braucht nur bash und tar. Grund
	@# und Befund stehen im Kopf von tests/pruefung-backup.sh (23.09.2026).
	@bash tests/pruefung-backup.sh

muster:
	@# Beitritt und Austritt in den Formaten von Paper 26.2 UND 26.3, durch
	@# die echten Nutzer von log-muster.sh. Grund und Befund im Kopf von
	@# tests/pruefung-logmuster.sh (21.10.2026).
	@bash tests/pruefung-logmuster.sh

kopien:
	@# USB-Kopie (Datei-Teil) und Cloud-Kopie gegen einen verschluesselten
	@# Ordner. Beide loeschen -- geprueft wird vor allem, was NICHT
	@# verschwinden darf. Grund und Befund im Kopf von
	@# tests/pruefung-kopien.sh (22.10.2026).
	@bash tests/pruefung-kopien.sh
