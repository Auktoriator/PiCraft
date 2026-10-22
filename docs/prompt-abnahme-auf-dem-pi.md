# Prompt für die Sitzung auf dem Raspberry Pi

Zum Kopieren in eine frische Claude-Code-Sitzung **auf dem Pi**, im
Repo-Verzeichnis (`~/Pi-MCS` oder wo der Klon liegt).

---

Wir nehmen Etappe C auf echter Hardware ab. Ich sitze am Pi, du auch —
alles, was hier läuft, läuft am lebenden Objekt.

**Lies zuerst, in dieser Reihenfolge:**

1. `PRUEFEN-AUF-DEM-PI.md` — die Arbeitsliste. Sie ist nach Risiko
   sortiert; die Reihenfolge ist keine Empfehlung, sondern eine Regel.
2. `CLAUDE.md` — Projektregeln und die Fallen, bei denen das Naheliegende
   falsch ist. Besonders die zu Paper und RCON: Beide sind im August 2026
   nachgemessen und stehen dort anders, als man vermuten würde.
3. `docs/lastenheft-minecraft-server.md` (Fassung 0.5), Abschnitt 3 und die
   Korrekturen K1 bis K8 — sie erklären, warum die Dinge so aussehen.
4. `docs/pflichtenheft-etappe-c.md` — was gerade fertig geworden ist.

**Stand (29.08.2026):** Etappen A, B und C sind umgesetzt, `make` und
`tests/abnahme.sh` sind grün, alles ist auf `main`. Die Weboberfläche hat
sieben Seiten. **Der erste Abnahmetag ist durch:** achtzehn Punkte ganz
oder teilweise erledigt, zwölf Befunde behoben, darunter alle Punkte mit
hohem Risiko — Hauptschalter über zwei Neustarts, Autostart, Neustart nach
Absturz, sauberes Herunterfahren und das Zurückspielen eines Backups.

**Fang so an:** Sieh in der Prüfliste nach, was noch offen ist, und nimm
den obersten Punkt, für den das nötige Gerät gerade da ist. Offen ist nur
noch, was ein zweites Gerät, echte Spieler oder schlicht Zeit braucht —
`B-P1` (RCON von einem anderen Gerät), `C-P2` Punkt 1 (privates Fenster),
`C-P3` (Handy), `C-P6` (sieben Tage Kurven), `C-P7` (kicken, sperren mit
Zweitkonto), `C-P8` (Tailscale mit HTTPS) und `P-D`/`P-E`/`P-F`.

> Sollte die Liste bei dir noch ganz am Anfang stehen — etwa auf einem
> zweiten Pi —, dann gilt weiter: **erst `A-P1`, vollständig, bevor
> irgendetwas anderes passiert.** Stimmt an den `[Install]`-Abschnitten der
> Dienstdateien etwas nicht, kommt der Server **nach dem nächsten Neustart
> nicht mehr hoch**.

**Vorgehen:**

- **Nichts von Hand am System reparieren.** Wenn etwas nicht stimmt: hier
  notieren, im Repository beheben, ausrollen. Sonst weicht der Pi wieder
  von dem ab, was im Repository steht — und genau daraus sind die Befunde
  B1 bis B7 entstanden.
- **Jeden abgehakten Punkt eintragen** (Datum + Ergebnis), damit der Stand
  nachvollziehbar bleibt.
- **Annahmen nicht raten, sondern nachmessen.** Auf dem Pi geht das
  direkt; im Container half `tests/messung-paper-verhalten.sh`. So sind K1
  bis K8 entstanden.
- **Was „geprüft" heißt, prüfen.** Am 29.08.2026 erklärte
  `mcs restore --probe` ein Backup für in Ordnung, das sich anschließend
  nicht zurückspielen ließ — die Prüfung nahm einen anderen Weg durch den
  Code als der Ernstfall. Wo eine Zusage nachweisbar ist, die Kette zu Ende
  gehen, statt beim ersten grünen Haken stehen zu bleiben.
- Vor jedem Commit `make`. Der Container-Abnahmetest (`tests/abnahme.sh`)
  braucht Docker und läuft auf dem Pi vermutlich nicht — dann `make` und
  der echte Betrieb.

---

## Falls der Pi noch auf altem Stand läuft

Auf der Referenz-Installation ist Etappe C seit dem 29.08.2026 ausgerollt;
dieser Abschnitt ist dann schon erledigt. Auf einem Pi, der noch den Stand
von Etappe B trägt, kommt Etappe C so dorthin:

```bash
cd ~/Pi-MCS
git pull
./deploy.sh --probe      # erst ansehen, was passieren würde
./deploy.sh
sudo systemctl restart mcs-admin.service
```

`deploy.sh` erledigt dabei drei Dinge, die neu sind und leicht zu übersehen
wären:

- Es rollt **Vorlagen und statische Dateien als ganze Bäume** aus (vorher
  war es genau eine Datei) und **entfernt**, was im Repository gelöscht
  wurde — darunter die alte `templates/index.html`.
- Es trägt **`MCS_ADMIN_SECRET`** in die `.env` nach. Der Wert ist neu seit
  Etappe C und unterschreibt das Anmelde-Cookie; ohne ihn meldet jeder
  Dienstneustart alle ab. `install-admin.sh` legt ihn nur bei einer
  **frischen** `.env` an, deshalb macht `deploy.sh` es für bestehende.
- Es **meldet**, wenn `python3-yaml` fehlt. Das braucht der Expertenmodus
  der Konfigurationsseite, um beim Speichern zu prüfen, ob eine
  YAML-Datei noch gültig ist. Fehlt der Parser, kann er nur auf
  Tabulatoren prüfen — und ein anderer Tippfehler fällt erst auf, wenn der
  Server nicht mehr startet:

  ```bash
  sudo apt-get install -y python3-yaml
  ```

Danach die Oberfläche im Browser öffnen. Sie ist dunkel, eckig, hat sieben
Reiter und verlangt eine Anmeldung mit Formular (nicht mehr den
Browser-Dialog von HTTP Basic Auth).

---

## Was auf dieser Etappe besonders wackelig war

Beim Bauen waren drei Stellen verdächtig. Zwei davon hielten stand, eine
brachte einen Befund:

1. **Vorgemerkte Konfigurationsänderungen** (`~/mcs/vorgemerkt/`) —
   `C-P5` am 29.08. bestanden, zweimal durchlaufen. Der Weg über zwei
   Prozesse und einen Neustart funktioniert.
2. **Die Anmeldung** über Sitzungs-Cookie — `C-P2` Punkte 2, 3 und 4
   bestanden. Offen bleibt nur Punkt 1 im **privaten Fenster**: Der Browser
   hat die alten Basic-Auth-Zugangsdaten möglicherweise noch gespeichert,
   sonst testet man den Zwischenspeicher des Browsers.
3. **Die Karte** — hier lag ein Befund, aber ein anderer als erwartet: Die
   Seite las die **Bindeadresse** nicht, und bei `bind: 127.0.0.1` (üblich
   hinter einem Reverse-Proxy) wäre der Rahmen leer und der Knopf tot
   gewesen. Behoben. Der HTTPS-Fall selbst (`C-P8`) steht noch aus.

## Womit tatsächlich nicht zu rechnen war

Die drei teuersten Befunde des Abnahmetags standen auf keiner Verdachtsliste
— sie brauchten alle **echte Größe oder echte Geschichte**:

1. **`mcs restore` fand die Welt nicht, die im Archiv lag.**
   `tar … | grep -q` endet unter `set -o pipefail` an SIGPIPE, sobald grep
   früh abbricht — und die Welt ist der erste Eintrag im Archiv. Das
   Zurückspielen war unmöglich, während `--probe` „in Ordnung" meldete. Im
   Container unsichtbar: Dort ist das Testarchiv zu klein.
2. **Nach einem Absturz galt eine tote screen-Sitzung als laufender
   Server.** `mcs stop` wartete 240 s, warnte falsch vor Datenverlust und
   endete in `failed`; `mcs restore` verweigerte sich. Der Container stürzt
   nie ab, also sieht er auch nicht, was danach liegen bleibt.
3. **Die Spielzeit war für alle Spieler leer** — die Statistiken liegen
   seit der Formatumstellung in `<welt>/players/stats/` (Korrektur K8). Die
   Testattrappen bildeten das alte Format ab und prüften damit den Zweig,
   den es auf keinem aktuellen Server mehr gibt.

Wer die Abnahme fortsetzt, sollte daraus vor allem eines mitnehmen: **Ein
grüner Container-Lauf sagt nichts über die Fälle, die Größe, Alter oder
einen vorherigen Absturz voraussetzen.**

---

## Wenn Zeit bleibt: Etappe D

Steht im Lastenheft, Abschnitt 6: DNS-Modul (deSEC), Erreichbarkeitstest
mit DS-Lite-Erkennung, Benachrichtigung bei Backup-Fehlschlag,
`unattended-upgrades`, Erkennung von Hardware und Speichermedium.

Vorgehen wie bisher: erst ein Pflichtenheft nach
`docs/pflichtenheft-etappe-d.md` ableiten, abstimmen, dann umsetzen. Der
offene Punkt O4 (welcher Benachrichtigungsweg) ist dabei zu entscheiden.

**Aber erst die Prüfliste.** Eine Etappe, die auf ungeprüftem Grund
aufsetzt, verschiebt die Fehlersuche nur nach hinten.
