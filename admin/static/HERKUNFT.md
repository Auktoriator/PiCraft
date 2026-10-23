# Woher die Dateien in `fremd/` stammen

Die Weboberfläche liefert **alles selbst aus**. Nichts kommt von einem CDN,
nichts wird zur Laufzeit nachgeladen. Zwei Gründe:

1. **Sie muss ohne Internet funktionieren.** Wer seinen Server verwaltet,
   weil das Netz gerade Ärger macht, soll nicht vor einer halb geladenen
   Seite sitzen.
2. **Ein Verwaltungswerkzeug sollte keine Anfragen nach außen stellen.**
   Ein CDN sieht sonst bei jedem Aufruf, wann jemand auf seinen Pi schaut.

Der Preis dafür: Diese Dateien muss jemand von Hand aktualisieren. Damit das
überhaupt möglich ist, steht hier, woher jede stammt und welche Prüfsumme sie
beim Herunterladen hatte — dasselbe Verfahren wie bei `paper.jar` und den
Plugins.

**Stand: 28.08.2026**

| Datei | Version | Lizenz | SHA256 |
|---|---|---|---|
| `htmx.min.js` | 2.0.10 | 0BSD | `71ea67185bfa8c98c39d31717c6fce5d852370fcdfd129db4543774d3145c0de` |
| `uPlot.iife.min.js` | 1.6.32 | MIT | `19c8d4c6ad88929a79f4ae49d6f7161566dfd0ba3d15cc495e974f787eb78f1f` |
| `uPlot.min.css` | 1.6.32 | MIT | `df630c6a8d6f8eeaff264b50f73ce5b114f646ffd9a0bb74f049b0a00135fa04` |
| `pixelify-sans-latin.woff2` | v3, Teilmenge `latin` | SIL OFL 1.1 | `e0abf68489dbb71bd83272f766d37ce71174a33110bb3b7323bb97292d4acff5` |
| `OFL-pixelify-sans.txt` | — | — | `b66ba46f511a851ab09998b5a5a9fdbb102545a3864cb993095e1745996873a7` |

Zusammen rund 111 KB. Zum Vergleich: Ein einzelnes modernes JavaScript-Gerüst
bringt ein Vielfaches davon mit, bevor eine einzige Zeile eigener Code
dazukommt.

## Bezugsquellen

```sh
curl -o htmx.min.js       https://unpkg.com/htmx.org@2.0.10/dist/htmx.min.js
curl -o uPlot.iife.min.js https://unpkg.com/uplot@1.6.32/dist/uPlot.iife.min.js
curl -o uPlot.min.css     https://unpkg.com/uplot@1.6.32/dist/uPlot.min.css
curl -o OFL-pixelify-sans.txt \
     https://raw.githubusercontent.com/google/fonts/main/ofl/pixelifysans/OFL.txt
```

Die Schriftdatei kommt von Google Fonts. Die Adresse ändert sich mit jeder
Fassung, deshalb wird sie nicht fest notiert; sie steht im Stylesheet, das
`https://fonts.googleapis.com/css2?family=Pixelify+Sans` ausliefert, im
Abschnitt `/* latin */`. **Wichtig:** mit einem Browser-`User-Agent`
abfragen, sonst liefert Google `ttf` statt `woff2`.

Nach jedem Austausch die Prüfsummen hier nachziehen:

```sh
shasum -a 256 admin/static/fremd/*
```

## Warum genau diese drei

**htmx** statt eines JavaScript-Gerüsts (Entscheidung 4 im Lastenheft). Es
macht aus einem gewöhnlichen HTML-Element eines, das eine Serveranfrage
auslösen und einen Teil der Seite ersetzen kann — mehr nicht. Damit
bekommt die Oberfläche das Verhalten, das man von einer modernen Anwendung
erwartet, ohne Build-Schritt, ohne npm und ohne Node auf dem Pi. Die Seiten
bleiben ganz normale Jinja-Vorlagen; wer sie liest, sieht HTML.

**uPlot** statt Chart.js für die Verlaufskurven. Es ist für Zeitreihen
gebaut, um Größenordnungen schneller und ein Bruchteil so groß. Auf dem
Handy ist das der Unterschied zwischen „die Kurve ist da" und „die Seite
ruckelt beim Wischen".

**Pixelify Sans** für Überschriften und große Zahlen. Das Lastenheft
(§5.7.1) will Pixelschrift ausdrücklich **nicht** im Fließtext — auf dem
Handy schlecht lesbar, und genau die Sorte „altbacken", die nicht gewollt
ist. Für Überschriften ist sie dagegen der billigste Minecraft-Bezug, den es
gibt.

Geprüft wurden drei Kandidaten. Ausschlusskriterium waren die **Umlaute**:
Eine Überschrift „Übersicht" in einer Schrift ohne Ü ist keine. Alle drei
haben sie, entschieden hat die Lesbarkeit in Überschriftengröße —
*Silkscreen* (3,5 KB) und *Jersey 10* (5,2 KB) sind für kleine Größen
gezeichnet und kippen groß gesetzt ins Altbackene. *Pixelify Sans* hat
Proportionen einer normalen Grotesk, die zufällig aus Pixeln besteht: nach
Minecraft aussehend, ohne als Kostüm zu wirken.

Der Fließtext benutzt gar keine Webfont, sondern den Systemstapel. Das sind
null Byte Ladezeit, und auf jedem Gerät ist es genau die Schrift, die dort
am besten aussieht.

## Was nicht von außen kommt

Das **Tab-Symbol** (`symbol.svg`, `symbol-32.png`, `symbol-180.png`, seit
23.10.2026) ist ein Grasblock und eine **eigene Zeichnung**, keine
Minecraft-Textur. Die echten Texturen gehören Mojang und haben in einem
öffentlichen Repository nichts verloren. Gezeichnet wird es von
[`tools/symbol-zeichnen.py`](../../tools/symbol-zeichnen.py) aus einer
Pixelkarte mit den Farben aus `mcs.css`. Wer das Motiv ändern will, ändert
das Skript und lässt es laufen, nicht die Dateien.
