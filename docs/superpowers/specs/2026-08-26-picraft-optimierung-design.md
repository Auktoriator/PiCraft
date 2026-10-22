# PiCraft — Optimierung 2026-08

Stand: 2026-08-26 · Branch: `optimierung-2026-08`

Ziel: Der Server soll wieder in den **Dauerbetrieb** gehen und dabei so
leichtgewichtig, stabil und einfach sein wie möglich — ohne Abstriche bei
Leistung und Sicherheit. Die Möglichkeit, ihn per `minecraft-modus ein|aus`
vollständig abzuschalten, bleibt erhalten.

---

## Ausgangslage

Der Server läuft seit **2026-08-02** nicht mehr (`minecraft-modus aus`, die
Backup-Zeile in der Crontab ist auskommentiert). Das ist kein Defekt, sondern
ein bewusster Zustand — aber er erklärt, warum das jüngste Backup vom
2026-08-02 stammt.

Der Bestand ist reif. Gepinnte Version mit Prüfsumme, Plugins mit Prüfsummen,
Aikar-Flags mit einer **gemessenen** Abweichung (`AlwaysPreTouch` entfernt),
systemd mit `OOMPolicy=stop`, `StartLimitBurst` und Ressourcen-Vorrang
gegenüber dem Time-Machine-Dienst. Es gibt hier wenig zu reparieren. Der
Gewinn liegt in **Aktualität**, in **vier konkreten Lücken** und darin,
Annahmen durch **Messungen** zu ersetzen.

### Umgebung

| | |
|---|---|
| Gerät | Raspberry Pi 5, 8 GB RAM, 4 Kerne (Cortex-A76), NVMe 235 GB (194 GB frei) |
| Java | Corretto 25.0.4.1 LTS |
| Paper | 26.2, Build **84** (gepinnt) — verfügbar ist Build **119** |
| Welt | `MeineWelt`, 824 MB — **read-only für dieses Vorhaben** |
| Betrieb | Survival, `difficulty=easy`, Port **25570**, max. 5 Spieler, Whitelist an |

---

## Entscheidungen

### Docker: verworfen, ohne Messung

Der Server bleibt bare-metal unter systemd. Begründung:

Container sind keine Virtualisierung — beim CPU-Durchsatz ist nichts zu
gewinnen. Der Unterschied läge woanders, und dort **verliert** Docker in
diesem Aufbau:

* **Der Konsolen-Kanal ist das Nadelöhr.** `mcs cmd`, `mcs say`, das Backup
  (`save-off` / `save-all`), die Admin-Oberfläche und `stop-minecraft.sh`
  reden alle über `screen -X stuff`. Im Container müsste das auf
  `docker attach` oder RCON umgestellt werden. RCON bedeutet einen weiteren
  offenen Port mit Passwort — aktuell steht bewusst `enable-rcon=false`.
* **Die systemd-Feinsteuerung müsste schlechter nachgebaut werden:**
  `OOMPolicy=stop`, `CPUWeight`/`IOWeight=200` gegen den Time-Machine-Dienst,
  `TimeoutStopSec=300`, `StartLimitBurst=5`.
* **`minecraft-modus` müsste umgebaut werden** — es schaltet drei Dienste
  plus Cronjob.
* Der Gewinn wäre eine gekapselte Java-Version und ein reproduzierbarer
  Aufbau. **Beides leistet das Repository bereits** über `versions.env` mit
  Prüfsummen und `plugins.txt`.

Eine Messreihe wurde erwogen und auf Wunsch gestrichen: Sie hätte
voraussichtlich bestätigt, was die Struktur schon zeigt, und ~30 Minuten
Laufzeit gekostet. Diese Notiz ersetzt sie, damit die Frage nicht in einem
halben Jahr erneut aufkommt.

### Backups: bewahren statt aufräumen

Ursprünglich war vorgesehen, acht `world_2026-05-*.tar.gz` (4,6 GB) in
`mcs_backup/` als Altlast zu entfernen. **Das ist verworfen.** Alte
Weltstände sollen erhalten bleiben, damit sich frühere Baustadien später
laden und ansehen lassen.

Ein Archivkonzept existiert bereits und wird **nicht** durch ein zweites
ersetzt: `weltarchiv/` bekommt jeden 10. Backup-Lauf als Hardlink und wird
von der Rotation nie angefasst (`LIESMICH.md` dort beschreibt es).

Die tatsächliche Lücke ist eine andere — und ernster als „Speicherplatz":

```
world_2026-05-12_04-00-01.tar.gz   links=2   ← im Weltarchiv gesichert
world_2026-05-13_04-00-01.tar.gz   links=1   ← existiert nur einmal
world_2026-05-14_04-00-01.tar.gz   links=1
world_2026-05-15_04-00-01.tar.gz   links=1
world_2026-05-16_04-00-01.tar.gz   links=1
world_2026-05-17_04-00-01.tar.gz   links=1
world_2026-05-18_04-00-01.tar.gz   links=1
world_2026-05-18_19-17-56.tar.gz   links=1   (gehört root)
```

Sieben Baustadien haben **keinen zweiten Namen**. Die Rotation greift sie
zwar nicht (sie sucht `backup_*`), aber sie stehen außerhalb jedes
Schutzkonzepts — ein einzelnes `rm` genügt. Sie werden ins Weltarchiv
verlinkt: additiv, kostet null Byte, löscht nichts.

### Repository bildet die Realität ab

`server/server.properties` beschreibt Creative / `peaceful` / Port 25565,
live läuft Survival / `easy` / Port 25570 mit `level-name=MeineWelt`. Solange das
so ist, kann `deploy.sh` diese Datei **nie** ausrollen — die fünf
Dauerabweichungen bei jedem Lauf sind kein Kuriosum, sondern eine Lücke im
Deploy-Weg. Die Vorlage wird an den laufenden Server angeglichen.

---

## Arbeitspakete

### A — Bestandssicherung (zuerst, vor allem anderen)

1. Die sieben ungesicherten Weltstände per Hardlink ins `weltarchiv/`.
2. Prüfen, dass danach jedes Archiv `links >= 2` hat.
3. `weltarchiv/LIESMICH.md` um die Nachzügler ergänzen.

Nichts wird gelöscht. Nichts wird verschoben.

### B — Aktualität

| Sache | von | auf |
|---|---|---|
| Paper 26.2 | Build 84 | aktueller stabiler Build (119+) |
| Pl3xMap | 26.2-553 | 26.2-554 |
| WorldEdit | 7.4.4 | 7.4.5 |
| WorldGuard | 7.0.17 | 7.0.18 |
| GSit | 3.5.1 | bereits aktuell |

Der Paper-Sprung bleibt **innerhalb** 26.2 — es findet keine
Weltkonvertierung statt, der Rückweg ist ein Austausch der `paper.jar`.
`versions.env` und `plugins.txt` werden mit neuen Prüfsummen committet.

**`hsrails` 1.5.0** deklariert `api-version: 1.14` und ist nirgends öffentlich
zu beziehen. Es wird **nicht** vorsorglich entfernt, sondern nach dem Update
gezielt darauf geprüft, ob Paper es noch lädt. Ergebnis wird dokumentiert.

### C — Repository-Hygiene

1. `server/server.properties` an den laufenden Server angleichen
   (Survival, `easy`, 25570, `level-name=MeineWelt`), mit Kommentaren zu jedem Wert.
2. Rotation im Backup-Skript: das alte Namensschema `world_*` erkennen und
   **ins Archiv überführen statt löschen**.
3. Die Backup-Altersgrenze (`MCS_BACKUP_WARNUNG_STUNDEN`, 48 h) darf bei
   `minecraft-modus aus` nicht fälschlich Alarm schlagen — prüfen und
   gegebenenfalls an den Modus koppeln.
4. Wissensgraph für PiCraft anlegen (`graphify`), damit die Regel aus
   `CLAUDE.md` auch in diesem Repository greift.

### D — Leistung, gemessen

Grundsatz: **Baseline → eine Änderung → nachmessen → behalten oder
verwerfen.** Alles läuft gegen eine **Kopie** der Welt; `MeineWelt` bleibt
unberührt. Messwerkzeug ist `spark`, das in Paper enthalten ist.

Kandidaten, nach erwartetem Nutzen:

1. **`network-compression-threshold`** (aktuell 256). Bei fünf Spielern im
   LAN kostet Kompression mehr CPU, als sie Bandbreite spart. Höher setzen
   oder abschalten.
2. **`paper-world-defaults.yml`**: Entity-Activation-Range, Mob-Spawn-Limits,
   Hopper- und Redstone-Verhalten — die klassischen Tickzeit-Fresser.
3. **Pl3xMap-Renderplan**: ein bekannter CPU-Fresser, der auf vier Kernen
   direkt mit dem Spiel konkurriert.
4. **GC-Wahl auf Java 25**: G1 gegen Generational ZGC. Erwartung ist, dass G1
   bei 3 GB Heap und vier Kernen vorn bleibt — Java 25 ist neu genug, dass
   die Faustregel eine Nachprüfung verdient.

**Nicht dabei:** Chunky-Vorgenerierung. Sie würde in die Welt schreiben.

### E — Sicherheit

1. `admin_ui/app.py` (871 Zeilen Flask) mit `claude-security` prüfen — der
   Dienst reicht Eingaben an eine Server-Konsole durch und ruft `subprocess`
   auf. Das ist der lohnendste Prüfpunkt im Repository.
2. Die Shell-Skripte mit `shellcheck` und `code-review` durchsehen.
3. Nach allen Änderungen die Angriffsfläche mit dem `exposure-audit`-Agenten
   gegenprüfen.

### F — Admin-Oberfläche und Dokumentation

1. Die Admin-Oberfläche optisch und in der Bedienung überarbeiten
   (`frontend-design`), ohne neue Angriffsfläche zu schaffen.
2. `README.md` überarbeiten — der Bestand ist gut, aber 815 Zeilen sind
   für den Einstieg zu viel.
3. Messprotokoll nach `docs/`, analog zu `optimierung-2026-07-27.md`.
4. `pi-manager-status.md` mitziehen, inklusive Datum im Kopf (Doku-Pflicht).

---

## Nicht-Ziele

* Kein Wechsel auf eine neuere **Minecraft**-Version (Weltkonvertierung ist
  endgültig).
* Kein Container-Umzug.
* Keine Schreibzugriffe auf `MeineWelt`.
* Keine SSH-Härtung (ausdrücklich abgewählt).
* Kein Anfassen der Router-Portweiterleitung — das Problem liegt am
  Router, nicht am Pi.
* Kein Löschen alter Backups.

---

## Risiken und Rückwege

| Risiko | Rückweg |
|---|---|
| Neuer Paper-Build bricht ein Plugin | alte `paper.jar` aus dem Backup zurück; `versions.env` ist versioniert |
| `hsrails` lädt nicht mehr | Plugin liegen lassen, Ausfall dokumentieren — es ist ohnehin nicht ersetzbar |
| Eine Leistungsänderung macht es schlechter | jede Änderung ist ein eigener Commit und einzeln rücknehmbar |
| Admin-Oberfläche nach Umbau defekt | eigener Dienst, unabhängig vom Server; `git revert` |
| Weltdaten beschädigt | tritt nicht auf — es wird nicht in die Welt geschrieben |

---

## Abnahme

Erfüllt, wenn:

1. Jedes Archiv in `mcs_backup/` und `weltarchiv/` hat `links >= 2` oder liegt
   im Archiv — **kein Baustadium existiert nur einmal**.
2. `deploy.sh` meldet für `server.properties` keine Dauerabweichung mehr.
3. Paper und alle Plugins sind aktuell, mit Prüfsummen committet.
4. Ein Messprotokoll belegt jede übernommene Leistungsänderung mit
   Vorher/Nachher-Zahlen.
5. Der Server läuft im Dauerbetrieb, `minecraft-modus ein|aus` funktioniert
   unverändert.
6. `mcs status` ist grün, das Backup läuft wieder nächtlich.
7. Doku und `pi-manager-status.md` stimmen mit dem System überein
   (`/doku-check` läuft sauber).
