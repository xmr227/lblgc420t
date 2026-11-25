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
- **Bild drucken**: PNG-, JPG- und PDF-Dateien (Seite 1) direkt aufs Etikett.
  Über **Datei…** auswählen; das Bild wird automatisch auf die Etikettenbreite
  skaliert (Bildbreite in mm einstellbar, 0 = volle Breite).
- **Bildmodus**: „Schwarz/Weiß (Logo)" für scharfe Logos/Schrift mit
  einstellbarer Grauschwelle, oder „Dithering (Foto)" für Graustufen/Fotos
  (Floyd–Steinberg-Diffusion).
- Text und Barcode erscheinen (falls ausgefüllt) unterhalb des Bildes.

Rechts unten läuft eine **Live-Vorschau** im richtigen Seitenverhältnis, auch
mit dem geladenen Bild.

## Bilder drucken (PNG / JPG / PDF)

- Das Programm wandelt die Grafik intern in eine 1-bit-Zebra-Rastergrafik um
  (ZPL `^GFA` mit Z64-Kompression) – der Drucker erhält exakt die Auflösung,
  die er physikalisch druckt (203 dpi). Kein Umweg über den Druckertreiber.
- Bei PDF wird **Seite 1** gerendert; mehrseitige PDFs bitte vorher
  zuschneiden oder als PNG speichern.
- Für Logos/Schriften den Modus „Schwarz/Weiß" und ggf. die Schwelle höher
  stellen (z. B. 170–200), damit Grautöne nicht verlorengehen.
- Bilder mit weißem (nicht transparentem) Hintergrund liefern die besten
  Ergebnisse; bei transparenten PNGs werden transparente Flächen schwarz.

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
