# Leistungsoptimierung vom 2026-07-27 — warum welcher Wert so steht

Dieses Dokument gehört zu den Einstellungen in `server/`. Es beantwortet die
Frage, die man sich in einem Jahr stellt: *Warum steht das so da, und darf ich
es ändern?*

> **Herkunft.** Die Optimierung wurde am 2026-07-27 auf dem Pi selbst gemessen.
> Das ausführliche Messprotokoll lag danach nur dort, unter
> `/home/pi/mcs-optimierung-2026-07-27/PLAN.md`, und drei Dateien im Repository
> verwiesen darauf — für jeden, der das Repository klont, ins Leere. Dieses
> Dokument fasst die Begründungen zusammen, die im Repository belegt sind
> (Kommentare in den Konfigurationsdateien und im Startskript) und ergänzt sie
> um einen Abgleich gegen die tatsächlichen Paper-Voreinstellungen.
>
> **Noch zu tun:** Das Original-Messprotokoll vom Pi hierher kopieren und
> unten unter „Rohdaten der Messung" anhängen. Erst dann ist die Optimierung
> vollständig im Repository abgebildet.

Zielsystem: Raspberry Pi 5, 8 GB RAM, NVMe-SSD, 4 Kerne (Cortex-A76),
Creative-Modus, maximal 5 Spieler, parallel läuft ein Time-Machine-Backupdienst.

---

## 1. Arbeitsspeicher

| Verwendung | Größe | Warum |
|---|---|---|
| Minecraft-Heap (`-Xms`/`-Xmx`) | **3 GB** | Gemessen liegt das Live-Set nach der Garbage Collection bei 0,7–1,3 GB. 3 GB lassen über das Doppelte als Rangierfläche |
| Java nebenher (GC, Code, Threads) | ~1 GB | Braucht Java zusätzlich zum Heap |
| Betriebssystem + Admin-Tool | ~1 GB | Grundbedarf |
| **Festplatten-Cache** | **~3 GB** | Linux hält damit Weltdaten im RAM — Chunks laden spürbar schneller |

Vorher standen 4 GB im Startskript. Unter Last blieben dem System dann nur noch
~1,4 GB statt der geforderten 2 GB.

Eingestellt in `mcs.conf` als `MCS_HEAP=3G`.

## 2. JVM-Optionen („Aikar-Flags")

Grundlage sind die in der Paper-Gemeinschaft etablierten Einstellungen für die
Java-Speicherverwaltung ([Dokumentation](https://docs.papermc.io/paper/aikars-flags)).
Kern-Idee: viele kleine, kurze Aufräum-Pausen statt seltener langer. Sie
funktionieren unverändert auf ARM.

Drei bewusste Abweichungen, alle am 2026-07-27 auf diesem Pi nachgemessen:

| Abweichung | Warum |
|---|---|
| `-XX:+AlwaysPreTouch` **entfernt** | Die JVM hat damit den kompletten Heap beim Start eingefaultet: **4,4 GB RSS bei 354 MB tatsächlich benutztem Heap**, der Rest landete im zram-Swap. Auf diesem Pi teilt sich Minecraft den Speicher mit dem Time-Machine-Dienst; als Festplatten-Cache ist er besser angelegt. Das übliche Gegenargument (Transparent Huge Pages) greift nicht — die gibt es im Raspberry-Pi-Kernel nicht |
| `-XX:G1PeriodicGCInterval=300000` **ergänzt** | Ohne `AlwaysPreTouch` wächst der Heap bedarfsgerecht, G1 gibt ihn per Voreinstellung aber **nie** zurück. Mit 5 Minuten Intervall räumt er im Leerlauf auf |
| `-XX:+UseCompactObjectHeaders` **ergänzt** | 8 statt 12 Byte Objektkopf. Weniger Heap-Druck, bessere Cache-Ausnutzung auf dem Cortex-A76 |

> **Achtung bei `UseCompactObjectHeaders`:** Diese Option gibt es erst ab
> Java 24. Auf älterem Java verweigert die JVM den Start mit
> `Unrecognized VM option` — sie lässt eine unbekannte Option nicht weg.
> `start-minecraft.sh` ermittelt deshalb die Java-Version zur Laufzeit und
> hängt die Option nur an, wenn sie unterstützt wird. Die gewünschte
> Java-Version steht in `server/versions.env`.

Zusätzlich schreibt die JVM ein rotierendes GC-Protokoll nach `logs/gc.log`
(max. 5 × 5 MB), damit sich Pausen später nachvollziehen lassen.

## 3. `server.properties`

| Einstellung | Wert | Warum |
|---|---|---|
| `view-distance` | 16 | Sichtweite in Chunks. Kostet vor allem Netzwerk und RAM, kaum Tick-Zeit — dafür ist `simulation-distance` zuständig |
| `simulation-distance` | 10 | Umkreis, in dem die Welt „lebt" (Mobs, Redstone). Der teure Wert: (2·10+1)² = **441 voll getickte Chunks je Spieler** |
| `sync-chunk-writes` | false | Welt-Speicherung asynchron → flüssigeres Spiel. Restrisiko bei Stromausfall fangen NVMe und tägliche Backups ab |
| `region-file-compression` | lz4 | Auf dem Cortex-A76 ist die Kompression die teuerste Stelle beim Chunk-Lesen und -Schreiben. Preis: ~11 % größere Region-Dateien |
| `pause-when-empty-seconds` | 60 | Server pausiert sich selbst, wenn niemand online ist → spart CPU und Strom im Dauerbetrieb |
| `difficulty` / `spawn-monsters` | peaceful / false | Kreativ-Server: keine Monster = weniger Rechenlast |
| `spawn-protection` | 0 | Kein Bauschutz am Spawn — stört beim kreativen Bauen nur |
| `white-list` | true | Sicherheit, nicht Leistung |

> `pause-when-empty-seconds` und `region-file-compression` setzen eine
> Mindest-Minecraft-Version voraus. Unbekannte Schlüssel verwirft der Server
> beim Neuschreiben **kommentarlos** — nach einem Versionswechsel also
> nachsehen, ob sie noch in der Datei stehen.

## 4. Paper-Konfiguration

Alle vier YAML-Dateien im Repository sind vollständige Abzüge der
Voreinstellungen; die bewusst geänderten Werte sind darin mit `# PiCraft:`
markiert. Der folgende Vergleich wurde am **2026-07-28 gegen einen frisch
erzeugten Abzug von Paper 26.2 Build 84** erstellt — also nicht aus dem
Gedächtnis, sondern gegen die echte Voreinstellung.

### `config/paper-global.yml`

| Einstellung | Voreinstellung | hier | Warum |
|---|---|---|---|
| `chunk-system.io-threads` | -1 | **2** | Bei -1 leitet Paper die Anzahl aus der Kernzahl ab und landet auf dem Pi 5 bei je **einem** Thread. Genau diese Pipeline muss bei hoher Sichtweite die Chunks liefern |
| `chunk-system.worker-threads` | -1 | **2** | dito |
| `player-max-chunk-send-rate` | 75.0 | **-1.0** | Bei `view-distance 16` sind 1089 Chunks je Spieler zu senden; mit 75/s dauert allein der Beitritt ~15 Sekunden |

### `config/paper-world-defaults.yml`

| Einstellung | Voreinstellung | hier | Warum |
|---|---|---|---|
| `max-auto-save-chunks-per-tick` | 24 | **12** | Mit mehr geladenen Chunks wird der Autosave-Schub größer; 12 verteilt dieselbe Arbeit auf doppelt so viele Ticks |
| `optimize-explosions` | false | **true** | Günstigeres Berechnungsverfahren; auf einem Kreativ-Server ohne Monster fällt der minimale Unterschied nicht ins Gewicht |

### `spigot.yml`

| Einstellung | Voreinstellung | hier | Warum |
|---|---|---|---|
| `netty-threads` | 4 | **2** | 4 Netzwerk-Threads auf 4 Kernen nehmen dem Server-Thread unnötig Rechenzeit weg — bei maximal 5 Spielern reichen 2 |
| `save-user-cache-on-stop-only` | false | **true** | Spielerdatenbank nur beim Stoppen schreiben statt bei jeder An-/Abmeldung — weniger kleine Schreibzugriffe auf die SSD |
| `merge-radius.item` | 0.5 | **2.5** | Gegenstände werden in größerem Umkreis zusammengefasst → weniger getickte Entitäten |
| `merge-radius.exp` | -1.0 | **3.0** | -1.0 hieße: Erfahrungskugeln gar nicht zusammenfassen |
| `mob-spawn-range` | 8 | **6** | Mobs entstehen näher am Spieler, dadurch weniger in geladenen, aber unbesuchten Chunks |
| `entity-activation-range.animals` | 32 | **24** | Nur was in diesem Radius um einen Spieler liegt, wird voll getickt. **Der spürbarste Einzelhebel** gegen Tick-Last |
| `…monsters` | 32 | **24** | dito |
| `…villagers` | 32 | **24** | dito |
| `…flying-monsters` | 32 | **24** | dito |
| `…water` | 16 | **12** | dito |
| `…misc` | 16 | **8** | dito |
| `restart-on-crash` | true | **false** | *(keine Leistungsfrage)* Spigot hätte bei einem Absturz `./start.sh` aufgerufen — die Datei gibt es hier nicht, und für Neustarts ist systemd zuständig |

`entity-activation-range.raiders` steht auf 64 — das **ist** die Voreinstellung
und keine Änderung.

### `bukkit.yml`

| Einstellung | Voreinstellung | hier |
|---|---|---|
| `spawn-limits.monsters` | 70 | **50** |
| `spawn-limits.animals` | 10 | **8** |
| `spawn-limits.water-ambient` | 20 | **5** |
| `spawn-limits.water-underground-creature` | 5 | **3** |
| `spawn-limits.ambient` | 15 | **5** |
| `ticks-per.monster-spawns` | 1 | **2** |
| `ticks-per.water-ambient-spawns` | 1 | **20** |
| `ticks-per.water-underground-creature-spawns` | 1 | **20** |
| `ticks-per.ambient-spawns` | 1 | **20** |

Weniger gleichzeitig lebende Mobs und seltenere Spawn-Versuche. Auf einem
Kreativ-Server mit `difficulty=peaceful` spawnen ohnehin kaum Monster; die
Grenzen wirken vor allem als Deckel.

## 4b. Wenn Paper eine neue Version bekommt

Die vier YAML-Dateien sind Abzüge eines bestimmten Paper-Builds (erkennbar an
`_version:` ganz oben). Paper ergänzt mit neuen Versionen Schlüssel und ändert
gelegentlich Voreinstellungen — der Abzug im Repository veraltet also
zwangsläufig. Beim Vergleich am 2026-07-28 ist zum Beispiel aufgefallen, dass
`chunk-loading-advanced.catchup-ticks` in Paper 26.2 existiert, im Abzug hier
aber fehlt.

Das ist harmlos: Paper ergänzt fehlende Schlüssel beim Start selbst mit ihrer
Voreinstellung. Wichtig ist nur, nach einem Versionswechsel einmal
nachzusehen, ob die markierten Werte noch dastehen und noch dasselbe bedeuten.

So erzeugt man einen frischen Vergleichsabzug:

```sh
# in einem leeren Verzeichnis, mit derselben paper.jar
mkdir /tmp/paper-neu && cd /tmp/paper-neu
cp /home/pi/mcs/mc_server/paper.jar .
echo "eula=true" > eula.txt
printf 'level-type=flat\nview-distance=3\n' > server.properties
java -Xmx1G -jar paper.jar --nogui    # kurz laufen lassen, dann "stop"

# dann vergleichen
diff /tmp/paper-neu/spigot.yml ~/PiCraft/server/spigot.yml
```

Alles, was dabei auftaucht und **nicht** mit `# PiCraft:` markiert ist, ist
eine Änderung durch Paper — nicht durch uns.

## 5. Rücksicht auf den Time-Machine-Dienst

Auf dem Pi läuft parallel ein Time-Machine-Backupserver. Bei Rechen- oder
Plattenlast soll Minecraft Vorrang haben — es ist der interaktive Dienst, bei
dem Verzögerungen sofort als Ruckeln ankommen.

- `minecraft.service`: `CPUWeight=200`, `IOWeight=200` (Normalwert ist 100)
- `mcs-playerlog.service`: `Nice=10`, Gewichte 20
- `mcs-admin.service`: `Nice=5`, `CPUWeight=50`
- das nächtliche Backup läuft mit `nice -n 15 ionice -c3`

## 6. Was man gefahrlos ändern kann

Jeder Wert oben ist einzeln rücknehmbar — es gibt keine Abhängigkeiten
untereinander außer den hier genannten.

- **Mehr Weitblick:** `view-distance` schrittweise erhöhen und dabei mit
  `mcs status` und `/spark tps` RAM und Tickrate im Auge behalten. Die Grenze
  setzt hier der Arbeitsspeicher, nicht die CPU.
- **Mehr Leben in der Welt:** die Spawn-Grenzen in `bukkit.yml` und die
  Aktivierungsradien in `spigot.yml` wieder anheben. Das kostet am direktesten
  Tick-Zeit.
- **Heap:** nur mit Messung ändern. `MCS_HEAP` in `mcs.conf`, danach
  `./deploy.sh && mcs restart`.

Nach jeder Änderung:

```sh
./deploy.sh --konfig-uebernehmen
mcs restart
```

## 7. Rohdaten der Messung

*(Hier gehört das Original-Messprotokoll vom Pi hinein —
`/home/pi/mcs-optimierung-2026-07-27/PLAN.md`. Solange es fehlt, sind die
Zahlen oben nur zusammengefasst, nicht belegt.)*
