# ============================================================
#  Etikettendruck fuer Zebra GC420t (Windows 10)
#  Sendet ZPL direkt als RAW-Daten an den Drucker.
#  Dadurch ignoriert Windows das Papierformat des Treibers (A4-Problem).
# ============================================================
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Drawing

# ---------- RAW-Druck ueber Windows-Spooler (winspool) ----------
if (-not ('RawPrinter' -as [type])) {
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class RawPrinter
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public struct DOCINFOA
    {
        [MarshalAs(UnmanagedType.LPStr)] public string pDocName;
        [MarshalAs(UnmanagedType.LPStr)] public string pOutputFile;
        [MarshalAs(UnmanagedType.LPStr)] public string pDataType;
    }

    [DllImport("winspool.Drv", SetLastError = true, CharSet = CharSet.Ansi)]
    public static extern bool OpenPrinter(string szPrinter, out IntPtr hPrinter, IntPtr pd);

    [DllImport("winspool.Drv", SetLastError = true)]
    public static extern bool ClosePrinter(IntPtr hPrinter);

    [DllImport("winspool.Drv", SetLastError = true, CharSet = CharSet.Ansi)]
    public static extern bool StartDocPrinter(IntPtr hPrinter, int level, [In, MarshalAs(UnmanagedType.LPStruct)] DOCINFOA di);

    [DllImport("winspool.Drv", SetLastError = true)]
    public static extern bool EndDocPrinter(IntPtr hPrinter);

    [DllImport("winspool.Drv", SetLastError = true)]
    public static extern bool StartPagePrinter(IntPtr hPrinter);

    [DllImport("winspool.Drv", SetLastError = true)]
    public static extern bool EndPagePrinter(IntPtr hPrinter);

    [DllImport("winspool.Drv", SetLastError = true)]
    public static extern bool WritePrinter(IntPtr hPrinter, IntPtr pBytes, int dwCount, out int dwWritten);

    public static bool Send(string printerName, byte[] data, string docName)
    {
        IntPtr hPrinter;
        if (!OpenPrinter(printerName, out hPrinter, IntPtr.Zero)) return false;
        try
        {
            DOCINFOA di = new DOCINFOA();
            di.pDocName = docName;
            di.pDataType = "RAW";
            if (!StartDocPrinter(hPrinter, 1, di)) return false;
            try
            {
                if (!StartPagePrinter(hPrinter)) return false;
                IntPtr pBytes = Marshal.AllocCoTaskMem(data.Length);
                try
                {
                    Marshal.Copy(data, 0, pBytes, data.Length);
                    int written;
                    if (!WritePrinter(hPrinter, pBytes, data.Length, out written)) return false;
                }
                finally { Marshal.FreeCoTaskMem(pBytes); }
                EndPagePrinter(hPrinter);
            }
            finally { EndDocPrinter(hPrinter); }
            return true;
        }
        finally { ClosePrinter(hPrinter); }
    }
}
"@
}

# ---------- Grundeinstellungen ----------
$script:dpmm = 8   # GC420t = 203 dpi = 8 Punkte pro mm

function ConvertTo-ZplText([string]$s) {
    if (-not $s) { return '' }
    return ($s -replace '[\\^~]', '_')
}

function Get-Number([string]$t, [double]$def) {
    try {
        $v = 0.0
        $ok = [double]::TryParse(("" + $t).Trim(), [System.Globalization.NumberStyles]::Any, [System.Globalization.CultureInfo]::InvariantCulture, [ref]$v)
        if ($ok -and $v -gt 0) { return $v } else { return $def }
    } catch { return $def }
}

function New-Zpl {
    param(
        [double]$wMm, [double]$hMm,
        [string[]]$textLines, [int]$font,
        [string]$barcode, [int]$barcodeH,
        [int]$qty, [int]$darkness, [int]$align,
        [switch]$WithBorder
    )
    $pw = [int][math]::Round($wMm * $script:dpmm)
    $ll = [int][math]::Round($hMm * $script:dpmm)
    $margin = 16
    $just = @('L','C','R')[[math]::Max(0, [math]::Min(2, $align))]
    $sz = [math]::Max(10, $font)
    $bz = [math]::Max(20, $barcodeH)

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("^XA`n^CI28`n")
    if ($darkness -ne 0) { [void]$sb.Append("^MD$darkness`n") }
    [void]$sb.Append("^PW$pw`n^LL$ll`n^LH0,0`n")
    if ($WithBorder) { [void]$sb.Append("^FO0,0^GB$pw,$ll,4^FS`n") }

    $clean = @()
    foreach ($l in $textLines) { $clean += (ConvertTo-ZplText $l) }
    $hasText = $false
    foreach ($l in $clean) { if ($l.Trim().Length -gt 0) { $hasText = $true; break } }

    $y = $margin
    if ($hasText) {
        $availH = $ll - 2 * $margin
        if ($barcode.Trim().Length -gt 0) { $availH -= ($bz + 24) }
        $maxLines = [math]::Max(1, [int][math]::Floor($availH / $sz))
        [void]$sb.Append("^FO$margin,$y^A0N,$sz,$sz^FB$($pw - 2 * $margin),$maxLines,0,$just,0^FD$($clean -join '\&')^FS`n")
        $y += $maxLines * $sz + 12
    }

    if ($barcode.Trim().Length -gt 0) {
        $bct = ConvertTo-ZplText $barcode
        $module = 2
        $estDots = (11 * $bct.Length + 46) * $module
        if ($estDots -gt ($pw - 2 * $margin)) { $module = 1; $estDots = (11 * $bct.Length + 46) * $module }
        $x = $margin
        if ($just -eq 'C') { $x = [math]::Max($margin, [int](($pw - $estDots) / 2)) }
        elseif ($just -eq 'R') { $x = [math]::Max($margin, $pw - $margin - $estDots) }
        [void]$sb.Append("^FO$x,$y^BY$module^BCN,$bz,Y,N^FD$bct^FS`n")
    }

    if ($qty -lt 1) { $qty = 1 }
    [void]$sb.Append("^PQ$qty,0,0,N`n^XZ`n")
    return $sb.ToString()
}

# ---------- GUI ----------
$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Etikettendruck für Zebra (GC420t)" Height="660" Width="1020"
        WindowStartupLocation="CenterScreen" Background="#F5F6F8">
    <Grid Margin="14">
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="400"/>
        </Grid.ColumnDefinitions>

        <StackPanel Grid.Column="0" Margin="0,0,14,0">
            <TextBlock Text="Drucker" FontWeight="SemiBold" Margin="0,0,0,4"/>
            <DockPanel LastChildFill="True">
                <Button x:Name="BtnRefresh" Content="Aktualisieren" DockPanel.Dock="Right" Width="110" Height="26" Margin="8,0,0,0"/>
                <ComboBox x:Name="CmbPrinter" Height="26"/>
            </DockPanel>

            <TextBlock Text="Etikettengröße" FontWeight="SemiBold" Margin="0,14,0,4"/>
            <ComboBox x:Name="CmbSize" Height="26"/>
            <StackPanel Orientation="Horizontal" Margin="0,8,0,0">
                <TextBlock Text="Breite (mm):" VerticalAlignment="Center" Margin="0,0,6,0"/>
                <TextBox x:Name="TxtWidth" Width="70" Height="24" Text="100"/>
                <TextBlock Text="Höhe (mm):" VerticalAlignment="Center" Margin="16,0,6,0"/>
                <TextBox x:Name="TxtHeight" Width="70" Height="24" Text="150"/>
                <TextBlock Text="max. Druckbreite: 104 mm" Margin="16,0,0,0" VerticalAlignment="Center" Foreground="#888"/>
            </StackPanel>

            <TextBlock Text="Deckkraft-Anpassung" FontWeight="SemiBold" Margin="0,14,0,4"/>
            <StackPanel Orientation="Horizontal">
                <Slider x:Name="SldDarkness" Width="220" Minimum="-30" Maximum="30" Value="0" IsSnapToTickEnabled="True" TickFrequency="5"/>
                <TextBlock x:Name="TblDarkness" Text="0 (Standard)" VerticalAlignment="Center" Margin="10,0,0,0"/>
            </StackPanel>

            <TextBlock Text="Textzeilen (eine Beschriftung pro Eingabezeile, leere Zeile = Abstand)" FontWeight="SemiBold" Margin="0,14,0,4"/>
            <DockPanel LastChildFill="True">
                <StackPanel Orientation="Horizontal" DockPanel.Dock="Right" Margin="10,0,0,0" VerticalAlignment="Top">
                    <TextBlock Text="Schriftgröße:" VerticalAlignment="Center" Margin="0,0,6,0"/>
                    <TextBox x:Name="TxtFontSize" Width="46" Height="24" Text="48"/>
                </StackPanel>
                <TextBox x:Name="TxtLines" Height="110" AcceptsReturn="True" VerticalScrollBarVisibility="Auto" TextWrapping="Wrap"
                         Text="Musterfirma GmbH&#x0a;Musterstraße 12&#x0a;12345 Musterstadt"/>
            </DockPanel>

            <TextBlock Text="Barcode (Code 128 – leer lassen = kein Barcode)" FontWeight="SemiBold" Margin="0,14,0,4"/>
            <StackPanel Orientation="Horizontal">
                <TextBox x:Name="TxtBarcode" Width="220" Height="24" VerticalContentAlignment="Center"/>
                <TextBlock Text="Höhe (Punkte):" VerticalAlignment="Center" Margin="14,0,6,0"/>
                <TextBox x:Name="TxtBarcodeHeight" Width="60" Height="24" Text="100"/>
            </StackPanel>

            <TextBlock Text="Ausrichtung" FontWeight="SemiBold" Margin="0,14,0,4"/>
            <StackPanel Orientation="Horizontal">
                <ComboBox x:Name="CmbAlign" Width="120" Height="24" SelectedIndex="1">
                    <ComboBoxItem Content="Links"/>
                    <ComboBoxItem Content="Mittig"/>
                    <ComboBoxItem Content="Rechts"/>
                </ComboBox>
                <TextBlock Text="Anzahl:" VerticalAlignment="Center" Margin="24,0,6,0"/>
                <TextBox x:Name="TxtQty" Width="60" Height="24" Text="1"/>
                <Button x:Name="BtnTest" Content="Testetikett" Width="110" Height="26" Margin="24,0,0,0"/>
            </StackPanel>

            <Button x:Name="BtnPrint" Content="Drucken" Height="42" FontSize="16" FontWeight="Bold" Margin="0,22,0,0" Background="#0A66C2" Foreground="White"/>
            <TextBlock x:Name="TblStatus" Text="" Margin="0,10,0,0" Foreground="#2E7D32" TextWrapping="Wrap"/>
        </StackPanel>

        <Border Grid.Column="1" Background="White" BorderBrush="#CCCCCC" BorderThickness="1" CornerRadius="4">
            <Grid>
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                </Grid.RowDefinitions>
                <TextBlock x:Name="TblPreviewTitle" Text="Vorschau" FontWeight="SemiBold" Margin="10,8,0,4"/>
                <Canvas x:Name="CnvPreview" Grid.Row="1" Margin="10,0,10,10" ClipToBounds="True"/>
            </Grid>
        </Border>
    </Grid>
</Window>
'@

$form = [Windows.Markup.XamlReader]::Parse($xaml)

$CmbPrinter      = $form.FindName('CmbPrinter')
$BtnRefresh      = $form.FindName('BtnRefresh')
$CmbSize         = $form.FindName('CmbSize')
$TxtWidth        = $form.FindName('TxtWidth')
$TxtHeight       = $form.FindName('TxtHeight')
$SldDarkness     = $form.FindName('SldDarkness')
$TblDarkness     = $form.FindName('TblDarkness')
$TxtLines        = $form.FindName('TxtLines')
$TxtFontSize     = $form.FindName('TxtFontSize')
$TxtBarcode      = $form.FindName('TxtBarcode')
$TxtBarcodeHeight= $form.FindName('TxtBarcodeHeight')
$CmbAlign        = $form.FindName('CmbAlign')
$TxtQty          = $form.FindName('TxtQty')
$BtnTest         = $form.FindName('BtnTest')
$BtnPrint        = $form.FindName('BtnPrint')
$TblStatus       = $form.FindName('TblStatus')
$TblPreviewTitle = $form.FindName('TblPreviewTitle')
$CnvPreview      = $form.FindName('CnvPreview')

$script:Presets = @(
    @{ Name = '25 x 10 mm';   W = 25;  H = 10 },
    @{ Name = '30 x 20 mm';   W = 30;  H = 20 },
    @{ Name = '40 x 30 mm';   W = 40;  H = 30 },
    @{ Name = '50 x 25 mm';   W = 50;  H = 25 },
    @{ Name = '58 x 40 mm';   W = 58;  H = 40 },
    @{ Name = '62 x 100 mm';  W = 62;  H = 100 },
    @{ Name = '70 x 30 mm';   W = 70;  H = 30 },
    @{ Name = '100 x 50 mm';  W = 100; H = 50 },
    @{ Name = '100 x 100 mm'; W = 100; H = 100 },
    @{ Name = '100 x 150 mm'; W = 100; H = 150 },
    @{ Name = 'Eigene Größe'; W = $null; H = $null }
)
foreach ($p in $script:Presets) { [void]$CmbSize.Items.Add($p.Name) }
$defIdx = 0
for ($i = 0; $i -lt $script:Presets.Count; $i++) {
    if ($script:Presets[$i].W -eq 100 -and $script:Presets[$i].H -eq 150) { $defIdx = $i }
}
$CmbSize.SelectedIndex = $defIdx

# ---------- Vorschau ----------
function Update-Preview {
    try {
        $CnvPreview.Children.Clear()
        $wMm = Get-Number $TxtWidth.Text 100
        $hMm = Get-Number $TxtHeight.Text 150
        $TblPreviewTitle.Text = "Vorschau ($wMm × $hMm mm)"

        $cw = $CnvPreview.ActualWidth; if ($cw -le 0) { $cw = 370 }
        $canvasH = $CnvPreview.ActualHeight; if ($canvasH -le 0) { $canvasH = 430 }
        $scale = [math]::Min(($cw - 24) / $wMm, ($canvasH - 24) / $hMm)
        $pxPerDot = $scale / $script:dpmm

        $rectW = $wMm * $scale
        $rectH = $hMm * $scale
        $ox = ($cw - $rectW) / 2
        $oy = ($canvasH - $rectH) / 2

        $border = New-Object Windows.Controls.Border
        $border.Width = $rectW; $border.Height = $rectH
        $border.Background = [Windows.Media.Brushes]::White
        $border.BorderBrush = [Windows.Media.Brushes]::Black
        $border.BorderThickness = New-Object Windows.Thickness(1.5)
        [Windows.Controls.Canvas]::SetLeft($border, $ox)
        [Windows.Controls.Canvas]::SetTop($border, $oy)
        [void]$CnvPreview.Children.Add($border)

        $font = [int](Get-Number $TxtFontSize.Text 48)
        $textPx = [math]::Max(6, $font * $pxPerDot)
        $textH = 0
        $allText = $TxtLines.Text
        if ($allText.Trim().Length -gt 0) {
            $lines = $allText -split "\r?\n"
            $tb = New-Object Windows.Controls.TextBlock
            $tb.Text = ($lines -join "`n")
            $tb.FontSize = $textPx
            $tb.FontFamily = New-Object Windows.Media.FontFamily('Segoe UI')
            $tb.Width = [math]::Max(10, $rectW - 4)
            $tb.TextWrapping = 'Wrap'
            $tb.Padding = '2'
            $tb.TextAlignment = switch ($CmbAlign.SelectedIndex) { 0 {'Left'} 2 {'Right'} default {'Center'} }
            [Windows.Controls.Canvas]::SetLeft($tb, $ox)
            [Windows.Controls.Canvas]::SetTop($tb, $oy + 2)
            [void]$CnvPreview.Children.Add($tb)
            $textH = ($lines.Count - 1) * $textPx * 1.35 + $textPx
        }

        $bc = $TxtBarcode.Text.Trim()
        if ($bc.Length -gt 0) {
            $bch = [int](Get-Number $TxtBarcodeHeight.Text 100)
            $bcHpx = $bch * $pxPerDot
            if ($bcHpx -gt $rectH) { $bcHpx = [math]::Max(6, $rectH - 4) }
            $estDots = (11 * $bc.Length + 23) * 2
            $maxDots = ($wMm * $script:dpmm) - 32
            $modulePx = [math]::Max(1.0, 2 * $pxPerDot)
            $bcWpx = $estDots * $pxPerDot
            $x = $ox + 16 * $pxPerDot
            if ($CmbAlign.SelectedIndex -eq 1) { $x = $ox + ($rectW - $bcWpx) / 2 }
            elseif ($CmbAlign.SelectedIndex -eq 2) { $x = $ox + $rectW - 16 * $pxPerDot - $bcWpx }
            $yTop = $oy + 2 + $textH + (4 * $pxPerDot)
            $yBottom = $oy + $rectH - $bcHpx - (14 * $pxPerDot)
            $y = $yTop
            if ($textH -le 0) { $y = [math]::Max($oy + (4 * $pxPerDot), $yBottom) }
            elseif ($yTop + $bcHpx -gt $oy + $rectH) { $y = $yBottom }

            $barX = [math]::Max($ox, $x)
            foreach ($c in $bc.ToCharArray()) {
                $v = [int]$c
                for ($k = 0; $k -lt 4; $k++) {
                    $bwModule = (($v + 3 * $k) % 3) + 1
                    $r = New-Object Windows.Shapes.Rectangle
                    $r.Width = $bwModule * $modulePx
                    $r.Height = $bcHpx
                    $r.Fill = [Windows.Media.Brushes]::Black
                    [Windows.Controls.Canvas]::SetLeft($r, $barX)
                    [Windows.Controls.Canvas]::SetTop($r, $y)
                    [void]$CnvPreview.Children.Add($r)
                    $barX += ($bwModule + 1) * $modulePx
                    if ($barX -gt ($ox + $rectW)) { break }
                }
            }
            if ($y + $bcHpx + (10 * $pxPerDot) -lt ($oy + $rectH)) {
                $cap = New-Object Windows.Controls.TextBlock
                $cap.Text = $bc
                $cap.FontSize = [math]::Max(7, (24 * $pxPerDot))
                $cap.Foreground = [Windows.Media.Brushes]::Black
                $cap.Width = $rectW - 4
                $cap.TextAlignment = 'Center'
                [Windows.Controls.Canvas]::SetLeft($cap, $ox)
                [Windows.Controls.Canvas]::SetTop($cap, $y + $bcHpx + 2)
                [void]$CnvPreview.Children.Add($cap)
            }
        }
    } catch { }
}

# ---------- Druckerliste ----------
function Update-Printers {
    $sel = $CmbPrinter.SelectedItem
    $CmbPrinter.Items.Clear()
    foreach ($p in [System.Drawing.Printing.PrinterSettings]::InstalledPrinters) {
        [void]$CmbPrinter.Items.Add([string]$p)
    }
    $idx = -1
    if ($sel) { $idx = $CmbPrinter.Items.IndexOf($sel) }
    if ($idx -lt 0) {
        for ($i = 0; $i -lt $CmbPrinter.Items.Count; $i++) {
            if ($CmbPrinter.Items[$i] -match '(?i)zebra|gc42|zdesigner') { $idx = $i; break }
        }
    }
    if ($idx -lt 0 -and $CmbPrinter.Items.Count -gt 0) { $idx = 0 }
    if ($CmbPrinter.Items.Count -gt 0) { $CmbPrinter.SelectedIndex = $idx }
}

# ---------- Drucken ----------
function Invoke-Print {
    param([switch]$WithBorder)
    $TblStatus.Text = ''
    $printer = $CmbPrinter.SelectedItem
    if ([string]::IsNullOrEmpty($printer)) {
        [void][System.Windows.MessageBox]::Show('Bitte zuerst einen Drucker auswählen.', 'Etikettendruck', 'OK', 'Warning')
        return
    }
    if ($printer -notmatch '(?i)zebra|gc42|zdesigner') {
        $r = [System.Windows.MessageBox]::Show("Der Drucker '$printer' sieht nicht nach einem Zebra-Drucker aus.`nNur Zebra-Drucker können ZPL ausgeben. Trotzdem fortfahren?", 'Etikettendruck', 'OKCancel', 'Question')
        if ($r -ne 'OK') { return }
    }

    $wMm = Get-Number $TxtWidth.Text 100
    $hMm = Get-Number $TxtHeight.Text 150
    if ($wMm -gt 104.6) {
        [void][System.Windows.MessageBox]::Show("Die Breite $wMm mm überschreitet die maximale Druckbreite des GC420t (104 mm). Der rechte Etikettenrand wird beschnitten.", 'Hinweis', 'OK', 'Warning')
    }

    $qty = [int](Get-Number $TxtQty.Text 1)
    if ($qty -lt 1) { $qty = 1 }
    if ($qty -gt 1000) { $qty = 1000 }

    $lines = @()
    foreach ($l in ($TxtLines.Text -split "\r?\n")) { $lines += $l }
    $font = [int](Get-Number $TxtFontSize.Text 48)
    $bch = [int](Get-Number $TxtBarcodeHeight.Text 100)
    $dark = [int]$SldDarkness.Value

    $zpl = New-Zpl -wMm $wMm -hMm $hMm -textLines $lines -font $font `
                   -barcode $TxtBarcode.Text.Trim() -barcodeH $bch `
                   -qty $qty -darkness $dark -align $CmbAlign.SelectedIndex -WithBorder:$WithBorder

    $bytes = [System.Text.Encoding]::UTF8.GetBytes($zpl)
    try {
        $ok = [RawPrinter]::Send($printer, $bytes, 'Etikettendruck')
        if ($ok) {
            $TblStatus.Text = "Gesendet: $qty Etikett(en) an '$printer' ($wMm × $hMm mm)."
        } else {
            [void][System.Windows.MessageBox]::Show("Der Druckauftrag konnte nicht gesendet werden.`nPrüfen Sie, ob der Drucker eingeschaltet, online und in Windows ausgewählt ist.", 'Fehler', 'OK', 'Error')
        }
    } catch {
        [void][System.Windows.MessageBox]::Show($_.Exception.Message, 'Fehler', 'OK', 'Error')
    }
}

# ---------- Ereignisse ----------
$BtnRefresh.Add_Click({ Update-Printers })

$CmbSize.Add_SelectionChanged({
    $i = $CmbSize.SelectedIndex
    if ($i -ge 0 -and $i -lt $script:Presets.Count) {
        $p = $script:Presets[$i]
        if ($null -ne $p.W) {
            $TxtWidth.Text = [string]$p.W
            $TxtHeight.Text = [string]$p.H
        }
    }
    Update-Preview
})

foreach ($c in @($TxtLines, $TxtBarcode, $TxtWidth, $TxtHeight, $TxtFontSize, $TxtBarcodeHeight)) {
    $c.Add_TextChanged({ Update-Preview })
}
$CmbAlign.Add_SelectionChanged({ Update-Preview })

$SldDarkness.Add_ValueChanged({
    $v = [int]$SldDarkness.Value
    if ($v -eq 0) { $TblDarkness.Text = '0 (Standard)' }
    elseif ($v -gt 0) { $TblDarkness.Text = "+$v (dunkler)" }
    else { $TblDarkness.Text = "$v (heller)" }
})

$BtnPrint.Add_Click({ Invoke-Print })
$BtnTest.Add_Click({ Invoke-Print -WithBorder })

$form.Add_Loaded({
    Update-Printers
    Update-Preview
})

[void]$form.ShowDialog()
