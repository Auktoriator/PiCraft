# Sicherheitslücken melden

Bitte **nicht** als öffentliches Issue. Stattdessen über GitHub:
Reiter **Security** → **Report a vulnerability**. Die Meldung sieht dann nur,
wer das Repository betreut.

Hilfreich sind: was betroffen ist (Skript, Seite der Weboberfläche), wie es
sich nachstellen lässt, und welche Version (`cat VERSION`).

## Was hier ernst genommen wird

PiCraft läuft auf einem Rechner, der meist auch anderes im Heimnetz
erledigt. Besonders wichtig sind deshalb:

- alles, was die **Weboberfläche** von außen erreichbar oder ohne Anmeldung
  bedienbar macht. Sie ist so mächtig wie ein SSH-Zugang und gehört nie ins
  Internet (siehe README, Abschnitt Sicherheit);
- alles, was **Zugangsdaten** offenlegt: RCON-Passwort, das Passwort der
  Oberfläche, DNS-Token, der Schlüssel der Cloud-Kopie;
- alles, was einem **Mitspieler** mehr erlaubt, als der Betreiber ihm
  gegeben hat;
- der kleine Teil, der als **root** läuft (`backup/usb-kopie.sh`).

## Was bewusst so ist

Einige Entscheidungen sehen nach einer Lücke aus und sind im Lastenheft
abgewogen — etwa der RCON-Port, der sich nicht auf `127.0.0.1` beschränken
lässt und deshalb von der Firewall gesperrt wird. Die Liste steht in
`CLAUDE.md` unter „Das Folgende ist bewusst so und kein Befund".
