#!/usr/bin/env python3
"""
symbol-zeichnen.py — Das Tab-Symbol der Weboberflaeche zeichnen.

Ein Grasblock von schraeg oben, 16 x 16 Pixel. Eine Pixelkarte, drei
Ausgaben unter admin/static/:

    symbol.svg       fuer Browser, die SVG koennen (scharf in jeder Groesse)
    symbol-32.png    fuer die uebrigen, vor allem aeltere Safari
    symbol-180.png   fuer "Zum Home-Bildschirm" auf iPhone und iPad

Aufruf aus dem Repo-Verzeichnis:

    python3 tools/symbol-zeichnen.py

Zwei Dinge, die man wissen sollte:

 1. **Das ist keine Minecraft-Textur.** Die echten Texturen gehoeren Mojang
    und duerfen nicht in ein oeffentliches Repository. Das Symbol ist eine
    eigene Zeichnung mit den Farben aus mcs.css; die Flecken kommen aus
    einer festen Rechenvorschrift, nicht aus einer Vorlage.
 2. **Es braucht keine Bibliothek.** Das PNG schreibt dieses Skript selbst
    (zlib aus der Standardbibliothek). Pillow oder rsvg fehlen auf einem
    frischen Pi, und fuer 16 x 16 Pixel lohnt keine Abhaengigkeit.

Die Ausgabe ist bei jedem Lauf byte-gleich. Wer das Motiv aendert, aendert
es hier und laesst das Skript laufen, nie die Dateien von Hand.
"""
import struct
import zlib
from pathlib import Path

ZIEL = Path(__file__).resolve().parent.parent / "admin" / "static"

# Hell, Grundton, dunkel. Der Grundton ist jeweils --gras und --erde aus
# mcs.css.
GRAS = [(0x80, 0xD6, 0x5C), (0x6C, 0xC2, 0x4A), (0x5F, 0xB2, 0x40)]
ERDE = [(0x8C, 0x63, 0x43), (0x7A, 0x55, 0x39), (0x65, 0x45, 0x2F)]
TIEFE = (0x10, 0x14, 0x1A)     # --tiefe, Hintergrund des Home-Bildschirm-Symbols

# Licht von oben links: Die Oberseite bleibt, die Seiten werden dunkler.
# Zu wenig Abstand, und der Wuerfel liest sich bei 16 Pixeln als Klumpen.
LINKS, RECHTS = 0.72, 0.50


def zufall(x, y, salz):
    """Fester Pseudozufall je Pixel. random() waere je nach Python anders."""
    n = (x * 374761393 + y * 668265263 + salz * 2147483647) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    return n ^ (n >> 16)


def ton(palette, x, y, salz):
    """Meist der Grundton, je ein Fuenftel hell und dunkel."""
    r = zufall(x, y, salz) % 10
    return palette[0] if r < 2 else palette[1] if r < 8 else palette[2]


def abdunkeln(farbe, faktor):
    return tuple(int(wert * faktor) for wert in farbe)


def pixelkarte():
    """{(x, y): (r, g, b)} — was fehlt, ist durchsichtig.

    Der Wuerfel hat 2:1-Kanten: Je zwei Spalten nach aussen beginnt die
    Oberseite eine Zeile tiefer. Spalte x hat k = Abstand zur Mitte // 2;
    die Oberseite belegt dort die Zeilen 3-k bis 4+k, die Seite die acht
    Zeilen darunter.
    """
    px = {}
    for x in range(16):
        k = (x if x < 8 else 15 - x) // 2
        for y in range(3 - k, 5 + k):
            px[x, y] = ton(GRAS, x, y, 1)
        faktor, salz = (LINKS, 2) if x < 8 else (RECHTS, 3)
        # Das Gras haengt zwei bis vier Pixel ueber die Seite herab.
        gras = 2 + (zufall(x, 0, salz) % 4 == 0) + (zufall(x, 0, salz + 9) % 6 == 0)
        for r in range(8):
            y = 5 + k + r
            px[x, y] = abdunkeln(ton(GRAS if r < gras else ERDE, x, y, salz), faktor)
    return px


def svg(px):
    """Ein Pfad je Farbe, ein Rechteck je waagerechter Pixelreihe."""
    pfade = {}
    for y in range(16):
        x = 0
        while x < 16:
            farbe = px.get((x, y))
            ende = x + 1
            while ende < 16 and px.get((ende, y)) == farbe:
                ende += 1
            if farbe:
                pfade.setdefault(farbe, []).append(f"M{x} {y}h{ende - x}v1h-{ende - x}z")
            x = ende
    zeilen = [f'<path fill="#{r:02x}{g:02x}{b:02x}" d="{"".join(teile)}"/>'
              for (r, g, b), teile in sorted(pfade.items())]
    return ('<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 16 16" '
            'shape-rendering="crispEdges">\n' + "\n".join(zeilen) + "\n</svg>\n")


def png(px, faktor, rand=0, grund=None):
    """Vergroessert ohne Glaettung: jedes Pixel wird ein faktor x faktor-Block."""
    seite = 16 * faktor + 2 * rand
    leer = bytes(grund + (255,)) if grund else bytes(4)
    roh = bytearray()
    for j in range(seite):
        roh.append(0)                        # PNG-Filter "keiner" je Zeile
        for i in range(seite):
            x, y = (i - rand) // faktor, (j - rand) // faktor
            innen = 0 <= i - rand < 16 * faktor and 0 <= j - rand < 16 * faktor
            farbe = px.get((x, y)) if innen else None
            roh += bytes(farbe + (255,)) if farbe else leer

    def block(art, daten):
        return (struct.pack(">I", len(daten)) + art + daten
                + struct.pack(">I", zlib.crc32(art + daten)))

    kopf = struct.pack(">IIBBBBB", seite, seite, 8, 6, 0, 0, 0)   # RGBA, 8 Bit
    return (b"\x89PNG\r\n\x1a\n" + block(b"IHDR", kopf)
            + block(b"IDAT", zlib.compress(bytes(roh), 9)) + block(b"IEND", b""))


def main():
    px = pixelkarte()
    (ZIEL / "symbol.svg").write_text(svg(px))
    (ZIEL / "symbol-32.png").write_bytes(png(px, 2))
    # iOS fuellt Durchsichtiges schwarz und rundet die Ecken selbst ab.
    # Deshalb hier ein eigener Hintergrund und Rand, damit nichts abgeschnitten
    # wird: 16 x 10 + 2 x 10 = 180.
    (ZIEL / "symbol-180.png").write_bytes(png(px, 10, rand=10, grund=TIEFE))
    for name in ("symbol.svg", "symbol-32.png", "symbol-180.png"):
        print(f"  geschrieben: admin/static/{name}")


if __name__ == "__main__":
    main()
