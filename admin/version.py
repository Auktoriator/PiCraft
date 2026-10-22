#!/usr/bin/env python3
"""
version.py — Welcher Stand hier tatsaechlich laeuft.

Der Wunsch war, die Version sehen zu koennen. Die naheliegende Umsetzung —
eine Zahl im Quelltext, angezeigt in der Fusszeile — beantwortet aber die
falsche Frage. Interessant ist nie, welche Version das Repository hat,
sondern **welcher Stand tatsaechlich ausgerollt ist.**

Diese Unterscheidung war in diesem Projekt schon zweimal teuer: Eine
Einheitendatei sagte etwas anderes als die Installation (`systemctl show …
-p WantedBy`), und eine Vorlage sagte etwas anderes als die
Live-Konfiguration. Beide Male war die Datei ueberzeugend und falsch.

Deshalb zwei Angaben, und die Oberflaeche zeigt die zweite:

    ~/mcs/VERSION     Was die ausgerollten DATEIEN sagen. Kommt als Kopie
                      der VERSION aus dem Wurzelverzeichnis der Vorlage.
    ~/mcs/ausgerollt  Was ein Ausrollen zuletzt WIRKLICH abgeschlossen hat.
                      deploy.sh und install.sh schreiben diese Datei ganz
                      am Ende — nach allem anderen.

Laufen beide auseinander, ist ein Ausrollen unterwegs steckengeblieben:
Die Dateien tragen schon die neue Nummer, abgeschlossen wurde sie nie. Das
ist genau die Sorte halb fertiger Zustand, die sonst niemandem auffaellt.
"""

from pathlib import Path

from einstellungen import MCS_DIR, kv_lesen

VERSION_DATEI = Path(MCS_DIR) / "VERSION"
STAND_DATEI = Path(MCS_DIR) / "ausgerollt"


def _erste_zeile(pfad):
    """Die erste nicht-leere Zeile einer Datei, oder None."""
    try:
        for zeile in pfad.read_text(encoding="utf-8", errors="ignore").splitlines():
            zeile = zeile.strip()
            if zeile and not zeile.startswith("#"):
                return zeile
    except OSError:
        pass
    return None


def stand():
    """Was die Oberflaeche ueber ihren eigenen Stand sagen darf.

    Liefert ein dict mit:
        installation  die zuletzt abgeschlossen ausgerollte Fassung (oder None)
        vorlage       was die ausgerollten Dateien sagen (oder None)
        abweichung    True, wenn beide bekannt sind und sich unterscheiden
        zeit, womit   wann und wodurch zuletzt ausgerollt wurde

    `installation` kann None sein, und das ist keine Stoerung: Auf einer
    Installation von vor v1.1 gibt es die Datei noch nicht. Dann wird das
    gesagt und nichts erfunden.
    """
    # ~/mcs/ausgerollt ist KEY=WERT, wie alles hier — gelesen wird es mit
    # derselben einen Funktion (einstellungen.kv_lesen).
    werte = kv_lesen(STAND_DATEI)
    installation = werte.get("MCS_STAND") or None
    vorlage = _erste_zeile(VERSION_DATEI)
    return {
        "installation": installation,
        "vorlage": vorlage,
        "abweichung": bool(installation and vorlage and installation != vorlage),
        "zeit": werte.get("MCS_STAND_ZEIT") or "",
        "womit": werte.get("MCS_STAND_WOMIT") or "",
    }
