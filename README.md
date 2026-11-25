# Etikettendruck für Zebra GC420t (Windows 10)

Ein kleines Programm mit grafischer Oberfläche zum Bedrucken von Etiketten in
verschiedenen Größen (inkl. 100 × 150 mm) auf dem Zebra GC420t.

## Warum das A4-Problem hier verschwindet

Das Programm sendet **ZPL** (die native Zebra-Druckersprache) **direkt als
RAW-Daten** an die Windows-Druckwarteschlange. Der Druckertreiber rendert dabei
gar nichts – sein Papierformat (DIN A4 o. ä.) wird vollständig ignoriert.
Die Etikettengröße wird stattdessen direkt im Druckbefehl festgelegt
(`^PW` / `^LL` in mm × 8 Punkte, da der GC420t mit 203 dpi = 8 Punkte/mm druckt).

Voraussetzung ist nur, dass der Zebra-Treiber installiert ist
(unter Windows erscheint der Drucker meist als „ZDesigner GC420t“).

## Starten

1. Doppelklick auf **`Start-Etikettendruck.bat`**
2. Falls Windows die Datei blockiert (nach Download), einmal in einer
   PowerShell ausführen:
   ```powershell
   Unblock-File .\LabelDruck.ps1
   ```

Keine Installation nötig – PowerShell 5.1 und WPF sind in Windows 10 enthalten.

## Bedienung

- **Drucker**: Zebra-Drucker wird automatisch vorausgewählt.
- **Etikettengröße**: Presets (u. a. 100 × 150 mm) oder „Eigene Größe“ –
  Breite/Höhe einfach in mm eintippen.
- **Textzeilen**: Eine Beschriftung pro Eingabezeile (leere Zeile = Abstand).
  Zeilenumbrüche am Etikettenrand passieren automatisch.
- **Barcode**: Code-128-Inhalt eintragen (leer = kein Barcode).
- **Ausrichtung**: Links / Mittig / Rechts für Text und Barcode.
- **Anzahl**: Ausgabeauflage (1–1000).
- **Testetikett**: Druckt das aktuelle Etikett mit gerahmtem Rand – ideal,
  um Größe und Ausrichtung zu prüfen, ohne Etiketten zu verschwenden.
- **Deckkraft-Anpassung**: Feinjustierung der Thermotransfer-Dunkelheit
  (`^MD −30…+30`), falls der Druck zu hell oder zu dunkel ist.

Rechts unten läuft eine **Live-Vorschau** im richtigen Seitenverhältnis.

## Hinweise

- Maximale Druckbreite des GC420t: **104 mm**; breitere Eingaben werden gewarnt.
- Die Anwendung druckt schwarz/weiß (Thermotransfer), wie es der Drucker vorsieht.
- Eigene Standardgrößen können im Skript in `$script:Presets` ergänzt werden
  (`Name`, `W`, `H` in mm).

## Dateien

| Datei | Zweck |
|---|---|
| `Start-Etikettendruck.bat` | Doppelklick-Starter (umgeht die Ausführungsrichtlinie) |
| `LabelDruck.ps1` | Das eigentliche Programm (GUI + ZPL + RAW-Druck) |
