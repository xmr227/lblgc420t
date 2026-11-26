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

- **Drucker**: In der Liste erscheinen nur Zebra-Drucker (z. B. „ZDesigner
  GC420t“); alle anderen Systemdrucker werden ausgeblendet. Wird kein
  Zebra-Drucker gefunden, zeigt das Programm zur Sicherheit alle an.
  Der Zebra-Drucker wird automatisch vorausgewählt.
- **Etikettengröße**: Presets (u. a. 70 × 50 mm und 100 × 150 mm) oder
  „Eigene Größe“ –
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
- **Skalierung des Inhalts**: 50–400 % – vergrößert/verkleinert Text,
  Barcode und Bild gemeinsam, falls alles „etwas zu klein“ erscheint.
  100 % = unverändert. Über 100 % ragt der Inhalt über den Etikettenrand
  hinaus und wird dort abgeschnitten (bewusst erlaubt, z. B. für
  randabfallende Bilder).
- **Bild drucken**: PNG-, JPG- und PDF-Dateien (Seite 1) direkt aufs Etikett.
  Über **Datei…** auswählen; das Bild wird automatisch auf die Etikettenbreite
  skaliert (Bildbreite in mm einstellbar, 0 = volle Breite).
- **Bildmodus**: „Schwarz/Weiß (Logo)" für scharfe Logos/Schrift mit
  einstellbarer Grauschwelle, oder „Dithering (Foto)" für Graustufen/Fotos
  (Floyd–Steinberg-Diffusion).
- **Drehung**: Das Bild kann um 0° / 90° / 180° / 270° gedreht gedruckt
  werden – die Vorschau dreht mit.
- **Bild verschieben**: In der Live-Vorschau das Bild mit der Maus anklicken
  und an die gewünschte Stelle ziehen – die Position wird so auch gedruckt.
  Beim Laden eines neuen Bildes wird die Position zurückgesetzt.
- Text und Barcode erscheinen (falls ausgefüllt) unterhalb des Bildes.

Rechts unten läuft eine **Live-Vorschau** im richtigen Seitenverhältnis, auch
mit dem geladenen Bild.

## Bilder drucken (PNG / JPG / PDF)

- Das Programm wandelt die Grafik intern in eine 1-bit-Zebra-Rastergrafik um
  (ZPL `^GFA`, unkomprimiert in Streifen von je max. 96 Bildzeilen) – der
  Drucker erhält exakt die Auflösung, die er physikalisch druckt (203 dpi).
  Kein Umweg über den Druckertreiber, keine Kompression – maximale
  Firmware-Kompatibilität.
- Bei PDF wird **Seite 1** gerendert; mehrseitige PDFs bitte vorher
  zuschneiden oder als PNG speichern.
- Für Logos/Schriften den Modus „Schwarz/Weiß" und ggf. die Schwelle höher
  stellen (z. B. 170–200), damit Grautöne nicht verlorengehen.
- Bilder mit weißem (nicht transparentem) Hintergrund liefern die besten
  Ergebnisse; bei transparenten PNGs werden transparente Flächen schwarz.

## Fehlerdiagnose beim Drucken

Der Statustext unter dem Drucken-Button zeigt jeden Schritt an
(„Druckauftrag wird vorbereitet…“ → „Gesendet: …“). Bleibt es bei
„wird vorbereitet“ hängen oder erscheint eine Fehlermeldung, gibt der Text
den konkreten Grund an. Erscheint „Gesendet“, hat Windows den Auftrag
entgegengenommen – druckt der Drucker dann trotzdem nicht, prüfen Sie die
Druckerwarteschlange (ggf. Warteschlange anhalten/leeren) und ob der Drucker
online ist.

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
