# ============================================================
#  Etikettendruck fuer Zebra GC420t (Windows 10)
#  Sendet ZPL direkt als RAW-Daten an den Drucker.
#  Dadurch ignoriert Windows das Papierformat des Treibers (A4-Problem).
# ============================================================
$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Drawing, System.Windows.Forms

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

    [DllImport("winspool.Drv", SetLastError = true)]
    public static extern bool StartDocPrinter(IntPtr hPrinter, int level, IntPtr di);

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
            IntPtr pDi = Marshal.AllocHGlobal(Marshal.SizeOf(typeof(DOCINFOA)));
            try
            {
                Marshal.StructureToPtr(di, pDi, false);
                if (!StartDocPrinter(hPrinter, 1, pDi)) return false;
            }
            finally { Marshal.FreeHGlobal(pDi); }
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

if (-not ('GrfEncoder' -as [type])) {
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.IO.Compression;
using System.Runtime.InteropServices;
using System.Text;

public static class GrfEncoder
{
    [DllImport("gdi32.dll")]
    private static extern bool DeleteObject(IntPtr hObject);

    public static void FreeHBitmap(IntPtr h) { DeleteObject(h); }

    public static string Encode(Bitmap src, int dstW, int dstH, bool dither, double threshold, int cropLeft, int cropTop)
    {
        int rowBytes = (dstW + 7) / 8;
        int total = rowBytes * dstH;
        byte[] gray = new byte[dstW * dstH];

        using (Bitmap scaled = new Bitmap(dstW, dstH, PixelFormat.Format24bppRgb))
        {
            using (Graphics g = Graphics.FromImage(scaled))
            {
                g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                g.SmoothingMode = SmoothingMode.HighQuality;
                g.PixelOffsetMode = PixelOffsetMode.HighQuality;
                g.Clear(Color.White);
                g.DrawImage(src, new Rectangle(0, 0, dstW, dstH));
            }
            BitmapData d = scaled.LockBits(new Rectangle(0, 0, dstW, dstH), ImageLockMode.ReadOnly, PixelFormat.Format24bppRgb);
            try
            {
                int stride = d.Stride;
                byte[] row = new byte[stride];
                IntPtr ptr = d.Scan0;
                for (int y = 0; y < dstH; y++)
                {
                    Marshal.Copy(ptr + y * stride, row, 0, stride);
                    int baseIdx = y * dstW;
                    for (int x = 0; x < dstW; x++)
                    {
                        int o = x * 3;
                        gray[baseIdx + x] = (byte)((row[o] * 11 + row[o + 1] * 59 + row[o + 2] * 30) / 100);
                    }
                }
            }
            finally { scaled.UnlockBits(d); }
        }

        byte[] mono = new byte[total];
        if (!dither || dstW < 2 || dstH < 2)
        {
            int thr = (int)Math.Max(0.0, Math.Min(255.0, threshold));
            for (int y = 0; y < dstH; y++)
            {
                int srcBase = y * dstW;
                int dstBase = y * rowBytes;
                for (int x = 0; x < dstW; x++)
                {
                    if (gray[srcBase + x] < thr) mono[dstBase + (x >> 3)] |= (byte)(0x80 >> (x & 7));
                }
            }
        }
        else
        {
            float[] buf = new float[gray.Length];
            for (int i = 0; i < gray.Length; i++) buf[i] = gray[i];
            const int thr = 128;
            for (int y = 0; y < dstH; y++)
            {
                for (int x = 0; x < dstW; x++)
                {
                    int idx = y * dstW + x;
                    float oldv = buf[idx];
                    float newv = (oldv < thr) ? 0f : 255f;
                    float err = oldv - newv;
                    if (newv == 0f) mono[y * rowBytes + (x >> 3)] |= (byte)(0x80 >> (x & 7));
                    buf[idx] = newv;
                    if (x + 1 < dstW) buf[idx + 1] += err * 7f / 16f;
                    if (y + 1 < dstH)
                    {
                        int below = idx + dstW;
                        if (x > 0) buf[below - 1] += err * 3f / 16f;
                        buf[below] += err * 5f / 16f;
                        if (x + 1 < dstW) buf[below + 1] += err * 1f / 16f;
                    }
                }
            }
        }

        if (cropLeft > 0 || cropTop > 0)
        {
            if (cropLeft > dstW - 1) cropLeft = dstW - 1;
            if (cropTop > dstH - 1) cropTop = dstH - 1;
            int outW = dstW - cropLeft;
            int outH = dstH - cropTop;
            int srcRowBytes = (dstW + 7) / 8;
            int outRowBytes = (outW + 7) / 8;
            byte[] outBuf = new byte[outRowBytes * outH];
            for (int y = 0; y < outH; y++)
            {
                int srcBase = (y + cropTop) * srcRowBytes;
                int dstBase = y * outRowBytes;
                for (int x = 0; x < outW; x++)
                {
                    int sx = x + cropLeft;
                    if ((mono[srcBase + (sx >> 3)] & (0x80 >> (sx & 7))) != 0)
                        outBuf[dstBase + (x >> 3)] |= (byte)(0x80 >> (x & 7));
                }
            }
            mono = outBuf;
            dstW = outW;
            dstH = outH;
        }

        StringBuilder sb = new StringBuilder(mono.Length * 2);
        const string hex = "0123456789ABCDEF";
        for (int i = 0; i < mono.Length; i++)
        {
            sb.Append(hex[mono[i] >> 4]);
            sb.Append(hex[mono[i] & 0x0F]);
        }
        return sb.ToString();
    }

    private static byte[] ZlibCompress(byte[] data)
    {
        using (MemoryStream ms = new MemoryStream())
        {
            ms.WriteByte(0x78);
            ms.WriteByte(0x9C);
            using (DeflateStream ds = new DeflateStream(ms, CompressionMode.Compress, true))
            {
                ds.Write(data, 0, data.Length);
            }
            uint adler = Adler32(data);
            ms.WriteByte((byte)(adler >> 24));
            ms.WriteByte((byte)(adler >> 16));
            ms.WriteByte((byte)(adler >> 8));
            ms.WriteByte((byte)adler);
            return ms.ToArray();
        }
    }

    private static uint Adler32(byte[] data)
    {
        uint a = 1;
        uint b = 0;
        for (int i = 0; i < data.Length; i++)
        {
            a = (a + data[i]) % 65521;
            b = (b + a) % 65521;
        }
        return (b << 16) | a;
    }

    private static string Crc16(string s)
    {
        const ushort polynomial = 0x8408;
        ushort crc = 0xFFFF;
        byte[] bytes = Encoding.ASCII.GetBytes(s);
        foreach (byte b in bytes)
        {
            crc ^= b;
            for (int i = 0; i < 8; i++)
            {
                bool lsb = (crc & 1) != 0;
                crc >>= 1;
                if (lsb) crc ^= polynomial;
            }
        }
        return crc.ToString("X4");
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

# ---------- Bild-Unterstützung (PNG / JPG / PDF) ----------
$script:AsTaskGeneric = $null
$script:AsTaskAction = $null

function Initialize-WinRtAwait {
    if ($script:AsTaskGeneric) { return }
    Add-Type -AssemblyName System.Runtime.WindowsRuntime
    foreach ($m in [System.WindowsRuntimeSystemExtensions].GetMethods()) {
        if ($m.Name -ne 'AsTask') { continue }
        $ps = $m.GetParameters()
        if ($ps.Count -ne 1) { continue }
        $pn = $ps[0].ParameterType.Name
        if ($pn -eq 'IAsyncOperation`1' -and -not $script:AsTaskGeneric) { $script:AsTaskGeneric = $m }
        if ($pn -eq 'IAsyncAction' -and -not $script:AsTaskAction) { $script:AsTaskAction = $m }
    }
}

function Wait-WinRtResult($op, [Type]$type) {
    Initialize-WinRtAwait
    $t = $script:AsTaskGeneric.MakeGenericMethod($type).Invoke($null, @($op))
    $t.Wait() | Out-Null
    return $t.Result
}

function Wait-WinRtAction($action) {
    Initialize-WinRtAwait
    $t = $script:AsTaskAction.Invoke($null, @($action))
    $t.Wait() | Out-Null
}

function ConvertFrom-Pdf([string]$path) {
    try {
        $full = (Resolve-Path -LiteralPath $path).Path
        $null = [Windows.Data.Pdf.PdfDocument,Windows.Data.Pdf,ContentType=WindowsRuntime]
        $null = [Windows.Storage.StorageFile,Windows.Storage,ContentType=WindowsRuntime]
        $file = Wait-WinRtResult ([Windows.Storage.StorageFile]::GetFileFromPathAsync($full)) ([Windows.Storage.StorageFile])
        $pdf = Wait-WinRtResult ([Windows.Data.Pdf.PdfDocument]::LoadFromFileAsync($file)) ([Windows.Data.Pdf.PdfDocument])
        if ($pdf.PageCount -lt 1) { return $null }
        $page = $pdf.GetPage(0)
        $mem = New-Object Windows.Storage.Streams.InMemoryRandomAccessStream
        try {
            $opts = New-Object Windows.Data.Pdf.PdfPageRenderOptions
            $opts.DestinationWidth = [System.UInt32][math]::Min(4000, [math]::Ceiling($page.Size.Width * 4))
            Wait-WinRtAction ($page.RenderToStreamAsync($mem, $opts))
        } catch {
            Wait-WinRtAction ($page.RenderToStreamAsync($mem))
        }
        $size = [int]$mem.Size
        if ($size -lt 8) { return $null }
        $reader = New-Object Windows.Storage.Streams.DataReader($mem.GetInputStreamAt(0))
        [void](Wait-WinRtResult ($reader.LoadAsync([System.UInt32]$size)) ([System.UInt32]))
        $bytes = New-Object byte[] $size
        $reader.ReadBytes($bytes)
        $ms = New-Object System.IO.MemoryStream(,$bytes)
        $img = [System.Drawing.Image]::FromStream($ms)
        try { return New-Object System.Drawing.Bitmap($img) } finally { $img.Dispose() }
    } catch {
        return $null
    }
}

function Get-ImageBitmap([string]$path) {
    if (-not $path) { return $null }
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    $ext = [System.IO.Path]::GetExtension($path).ToLowerInvariant()
    if ($ext -eq '.pdf') { return ConvertFrom-Pdf $path }
    try {
        $img = [System.Drawing.Image]::FromFile($path)
        try { return New-Object System.Drawing.Bitmap($img) } finally { $img.Dispose() }
    } catch {
        return $null
    }
}

function Get-ImageSourceForPreview {
    $p = ''
    try { $p = $TxtImage.Text.Trim() } catch { return $null }
    if ($p.Length -eq 0) { return $null }
    $rot = $CmbImgRot.SelectedIndex * 90
    $key = $p + '|' + $rot
    try {
        if (Test-Path -LiteralPath $p) {
            $key = (Resolve-Path -LiteralPath $p).Path + '|' + (Get-Item -LiteralPath $p).LastWriteTimeUtc.Ticks + '|' + $rot
        }
    } catch { }
    if ($script:ImgCache.Key -eq $key) {
        if ($script:ImgCache.Failed) { return $null }
        return $script:ImgCache.Source
    }
    $script:ImgCache.Key = $key
    $script:ImgCache.Failed = $false
    $script:ImgCache.Source = $null
    $bmp = Get-ImageBitmap $p
    if (-not $bmp) { $script:ImgCache.Failed = $true; return $null }
    try {
        $src = $null
        $hBitmap = $bmp.GetHbitmap()
        try {
            $src = [System.Windows.Interop.Imaging]::CreateBitmapSourceFromHBitmap($hBitmap, [IntPtr]::Zero, [System.Windows.Int32Rect]::Empty, [System.Windows.Media.Imaging.BitmapSizeOptions]::FromEmptyOptions())
        } finally { [GrfEncoder]::FreeHBitmap($hBitmap) }
        $src.Freeze()
        if ($rot -gt 0) {
            $rotated = New-Object Windows.Media.Imaging.TransformedBitmap
            $rotated.BeginInit()
            $rotated.Source = $src
            $rotated.Transform = New-Object Windows.Media.RotateTransform($rot)
            $rotated.EndInit()
            $rotated.Freeze()
            $src = $rotated
        }
        $script:ImgCache.Source = $src
        return $src
    } finally {
        $bmp.Dispose()
    }
}

$script:ImgCache = @{ Key = ''; Source = $null; Failed = $false }

function New-Zpl {
    param(
        [double]$wMm, [double]$hMm,
        [string[]]$textLines, [int]$font,
        [string]$barcode, [int]$barcodeH,
        [int]$qty, [int]$darkness, [int]$align,
        $imgBitmap,
        [double]$imgWidthMm, [bool]$imgDither, [int]$imgThreshold,
        [double]$scale = 100,
        [int]$imgOffsetX = 0,
        [int]$imgOffsetY = 0,
        [switch]$WithBorder
    )
    $pw = [int][math]::Round($wMm * $script:dpmm)
    $ll = [int][math]::Round($hMm * $script:dpmm)
    $margin = 16
    $just = @('L','C','R')[[math]::Max(0, [math]::Min(2, $align))]
    $k = [math]::Max(0.5, [math]::Min(4.0, $scale / 100.0))
    $sz = [math]::Max(10, [int][math]::Round($font * $k))
    $bz = [math]::Max(20, [int][math]::Round($barcodeH * $k))

    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("^XA`n^CI28`n")
    if ($darkness -ne 0) { [void]$sb.Append("^MD$darkness`n") }
    [void]$sb.Append("^PW$pw`n^LL$ll`n^LH0,0`n")
    if ($WithBorder) { [void]$sb.Append("^FO0,0^GB$pw,$ll,4^FS`n") }

    $clean = @()
    foreach ($l in $textLines) { $clean += (ConvertTo-ZplText $l) }
    $hasText = $false
    foreach ($l in $clean) { if ($l.Trim().Length -gt 0) { $hasText = $true; break } }
    $hasBarcode = $barcode.Trim().Length -gt 0

    $y = $margin
    if ($imgBitmap) {
        $maxW = $pw - 2 * $margin
        $dstW = [int][math]::Round($maxW * $k)
        if ($imgWidthMm -gt 0) { $dstW = [int][math]::Round($imgWidthMm * $script:dpmm * $k) }
        if ($dstW -lt 1) { $dstW = 1 }
        $dstH = [math]::Max(1, [int][math]::Round($dstW * $imgBitmap.Height / $imgBitmap.Width))
        $imgX = [int](($pw - $dstW) / 2) + $imgOffsetX
        $imgY = $margin + $imgOffsetY
        $cropLeft = 0
        $cropTop = 0
        if ($imgX -lt 0) { $cropLeft = [math]::Min(-$imgX, $dstW - 1) }
        if ($imgY -lt 0) { $cropTop = [math]::Min(-$imgY, $dstH - 1) }
        if ($imgX -gt ($pw - 1)) { $imgX = $pw - 1 }
        if ($imgY -gt ($ll - 1)) { $imgY = $ll - 1 }
        $imgX = [math]::Max(0, $imgX)
        $imgY = [math]::Max(0, $imgY)
        $visW = $dstW - $cropLeft
        $visH = $dstH - $cropTop
        $rowBytes = [int][math]::Ceiling($visW / 8.0)
        $imgHex = [GrfEncoder]::Encode($imgBitmap, $dstW, $dstH, $imgDither, [double]$imgThreshold, $cropLeft, $cropTop)
        $stripRows = 96
        $rowsLeft = $visH
        $yy = $imgY
        $pos = 0
        while ($rowsLeft -gt 0) {
            $rows = [math]::Min($stripRows, $rowsLeft)
            $len = $rows * $rowBytes
            $part = $imgHex.Substring($pos, $len * 2)
            [void]$sb.Append("^FO$imgX,$yy^GFA,$len,$len,$rowBytes,$part^FS`n")
            $yy += $rows
            $pos += $len * 2
            $rowsLeft -= $rows
        }
        $y = $imgY + $visH + 12
    }

    if ($hasText) {
        $availH = $ll - $y - $margin
        if ($hasBarcode) { $availH -= ($bz + 24) }
        $maxLines = [math]::Max(1, [int][math]::Floor($availH / $sz))
        [void]$sb.Append("^FO$margin,$y^A0N,$sz,$sz^FB$($pw - 2 * $margin),$maxLines,0,$just,0^FD$($clean -join '\&')^FS`n")
        $y += $maxLines * $sz + 12
    }

    if ($hasBarcode) {
        $bct = ConvertTo-ZplText $barcode
        $module = [math]::Max(1, [int][math]::Round(2 * $k))
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
        Title="Etikettendruck für Zebra (GC420t)" Height="770" Width="1020"
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

            <TextBlock Text="Skalierung des Inhalts (Text, Barcode, Bild)" FontWeight="SemiBold" Margin="0,14,0,4"/>
            <StackPanel Orientation="Horizontal">
                <Slider x:Name="SldScale" Width="220" Minimum="50" Maximum="400" Value="100" IsSnapToTickEnabled="True" TickFrequency="5"/>
                <TextBlock x:Name="TblScale" Text="100 %" VerticalAlignment="Center" Margin="10,0,0,0"/>
            </StackPanel>
            <TextBlock Text="Über 100 % ragt der Inhalt über den Etikettenrand hinaus (wird am Rand abgeschnitten)." Margin="0,4,0,0" Foreground="#888" FontSize="11"/>

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

            <TextBlock Text="Bild drucken (PNG / JPG / PDF – Seite 1)" FontWeight="SemiBold" Margin="0,14,0,4"/>
            <DockPanel LastChildFill="True">
                <Button x:Name="BtnImgBrowse" Content="Datei…" DockPanel.Dock="Right" Width="70" Height="24" Margin="8,0,0,0"/>
                <TextBox x:Name="TxtImage" Height="24" VerticalContentAlignment="Center"/>
            </DockPanel>
            <StackPanel Orientation="Horizontal" Margin="0,8,0,0">
                <TextBlock Text="Bildbreite (mm, 0 = voll):" VerticalAlignment="Center" Margin="0,0,6,0"/>
                <TextBox x:Name="TxtImgWidth" Width="60" Height="24" Text="0"/>
                <TextBlock Text="Modus:" VerticalAlignment="Center" Margin="14,0,6,0"/>
                <ComboBox x:Name="CmbImgMode" Width="150" Height="24" SelectedIndex="0">
                    <ComboBoxItem Content="Schwarz/Weiß (Logo)"/>
                    <ComboBoxItem Content="Dithering (Foto)"/>
                </ComboBox>
                <TextBlock Text="Schwelle:" VerticalAlignment="Center" Margin="14,0,6,0"/>
                <TextBox x:Name="TxtImgThreshold" Width="50" Height="24" Text="150"/>
                <TextBlock Text="Drehung:" VerticalAlignment="Center" Margin="14,0,6,0"/>
                <ComboBox x:Name="CmbImgRot" Width="60" Height="24" SelectedIndex="0">
                    <ComboBoxItem Content="0°"/>
                    <ComboBoxItem Content="90°"/>
                    <ComboBoxItem Content="180°"/>
                    <ComboBoxItem Content="270°"/>
                </ComboBox>
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
                <TextBlock x:Name="TblPreviewTitle" Text="Vorschau – Bild anklicken und mit der Maus verschieben" FontWeight="SemiBold" Margin="10,8,0,4"/>
                <Canvas x:Name="CnvPreview" Grid.Row="1" Margin="10,0,10,10" ClipToBounds="False" Background="#FAFAFA"/>
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
$SldScale        = $form.FindName('SldScale')
$TblScale        = $form.FindName('TblScale')
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
$TxtImage        = $form.FindName('TxtImage')
$BtnImgBrowse    = $form.FindName('BtnImgBrowse')
$TxtImgWidth     = $form.FindName('TxtImgWidth')
$CmbImgMode      = $form.FindName('CmbImgMode')
$TxtImgThreshold = $form.FindName('TxtImgThreshold')
$CmbImgRot       = $form.FindName('CmbImgRot')

$script:Presets = @(
    @{ Name = '25 x 10 mm';   W = 25;  H = 10 },
    @{ Name = '30 x 20 mm';   W = 30;  H = 20 },
    @{ Name = '40 x 30 mm';   W = 40;  H = 30 },
    @{ Name = '50 x 25 mm';   W = 50;  H = 25 },
    @{ Name = '58 x 40 mm';   W = 58;  H = 40 },
    @{ Name = '62 x 100 mm';  W = 62;  H = 100 },
    @{ Name = '70 x 30 mm';   W = 70;  H = 30 },
    @{ Name = '70 x 50 mm';   W = 70;  H = 50 },
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
        $k = [math]::Max(0.5, [math]::Min(4.0, $SldScale.Value / 100.0))
        $textPx = [math]::Max(6, $font * $k * $pxPerDot)
        $bch = [int][math]::Max(20, [math]::Round((Get-Number $TxtBarcodeHeight.Text 100) * $k))
        $textH = 0

        $imgTopY = $oy + 2
        $imgSrc = Get-ImageSourceForPreview
        if ($imgSrc) {
            if ($TxtImage.Text -ne $script:LastImgPath) {
                $script:LastImgPath = $TxtImage.Text
                $script:ImgOffsetX = 0
                $script:ImgOffsetY = 0
            }
            $imgmm = Get-Number $TxtImgWidth.Text 0
            $maxWmm = $wMm - (32 / $script:dpmm)
            if ($imgmm -le 0 -or $imgmm -gt $maxWmm) { $imgmm = $maxWmm }
            $imgWpx = [math]::Max(2, $imgmm * $scale * $k)
            $imgHpx = $imgWpx * $imgSrc.Height / $imgSrc.Width
            $el = New-Object Windows.Controls.Image
            $el.Source = $imgSrc
            $el.Width = $imgWpx
            $el.Height = $imgHpx
            $el.Stretch = 'Fill'
            $el.Cursor = 'Hand'
            $ix = $ox + ($rectW - $imgWpx) / 2 + $script:ImgOffsetX * $pxPerDot
            $iy = $oy + (2 * $pxPerDot) + $script:ImgOffsetY * $pxPerDot
            if ($ix -gt ($ox + $rectW - 4)) { $ix = $ox + $rectW - 4 }
            if ($iy -gt ($oy + $rectH - 4)) { $iy = $oy + $rectH - 4 }
            if ($ix -lt ($ox - $imgWpx + 4)) { $ix = $ox - $imgWpx + 4 }
            if ($iy -lt ($oy - $imgHpx + 4)) { $iy = $oy - $imgHpx + 4 }
            [Windows.Controls.Canvas]::SetLeft($el, $ix)
            [Windows.Controls.Canvas]::SetTop($el, $iy)
            [void]$CnvPreview.Children.Add($el)
            $script:PreviewImageEl = $el
            $ol = New-Object Windows.Shapes.Rectangle
            $ol.Width = $rectW
            $ol.Height = $rectH
            $ol.Fill = [Windows.Media.Brushes]::Transparent
            $ol.Stroke = [Windows.Media.Brushes]::Red
            $ol.StrokeThickness = 1.5
            try { $ol.StrokeDashArray = '3,2' } catch { }
            $ol.IsHitTestVisible = $false
            [Windows.Controls.Canvas]::SetLeft($ol, $ox)
            [Windows.Controls.Canvas]::SetTop($ol, $oy)
            [void]$CnvPreview.Children.Add($ol)
            $TblPreviewTitle.Text = "Vorschau ($wMm × $hMm mm) – rot gestrichelt = Etikettenrand"
            $imgTopY = $iy + $imgHpx + (4 * $pxPerDot)
            $el.Add_MouseLeftButtonDown({
                param($s, $e)
                $p = $e.GetPosition($CnvPreview)
                $script:ImgDrag.Active = $true
                $script:ImgDrag.StartX = $p.X
                $script:ImgDrag.StartY = $p.Y
                $script:ImgDrag.BaseLeft = [Windows.Controls.Canvas]::GetLeft($s)
                $script:ImgDrag.BaseTop = [Windows.Controls.Canvas]::GetTop($s)
                $script:ImgDrag.BaseOffX = $script:ImgOffsetX
                $script:ImgDrag.BaseOffY = $script:ImgOffsetY
                [void]$CnvPreview.CaptureMouse()
            })
        }
        $script:LastPxPerDot = $pxPerDot

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
            [Windows.Controls.Canvas]::SetTop($tb, $imgTopY)
            [void]$CnvPreview.Children.Add($tb)
            $textH = ($lines.Count - 1) * $textPx * 1.35 + $textPx
        }

        $bc = $TxtBarcode.Text.Trim()
        if ($bc.Length -gt 0) {
            $bcHpx = $bch * $pxPerDot
            if ($bcHpx -gt $rectH) { $bcHpx = [math]::Max(6, $rectH - 4) }
            $estDots = (11 * $bc.Length + 23) * 2
            $maxDots = ($wMm * $script:dpmm) - 32
            $modulePx = [math]::Max(1.0, 2 * $k * $pxPerDot)
            $bcWpx = $estDots * $pxPerDot
            $x = $ox + 16 * $pxPerDot
            if ($CmbAlign.SelectedIndex -eq 1) { $x = $ox + ($rectW - $bcWpx) / 2 }
            elseif ($CmbAlign.SelectedIndex -eq 2) { $x = $ox + $rectW - 16 * $pxPerDot - $bcWpx }
            $yTop = $imgTopY + $textH + (4 * $pxPerDot)
            $yBottom = $oy + $rectH - $bcHpx - (14 * $pxPerDot)
            $y = $yTop
            if ($textH -le 0 -and $TxtImage.Text.Trim().Length -eq 0) { $y = [math]::Max($oy + (4 * $pxPerDot), $yBottom) }
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
    $all = @()
    foreach ($p in [System.Drawing.Printing.PrinterSettings]::InstalledPrinters) {
        $all += [string]$p
    }
    $zebra = @($all | Where-Object { $_ -match '(?i)zebra|gc42|zdesigner' })
    if ($zebra.Count -gt 0) { $all = $zebra }
    foreach ($p in $all) { [void]$CmbPrinter.Items.Add($p) }
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
    try {
    $TblStatus.Text = 'Druckauftrag wird vorbereitet…'
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

    $imgBitmap = $null
    if ($TxtImage.Text.Trim().Length -gt 0) {
        $imgBitmap = Get-ImageBitmap ($TxtImage.Text.Trim())
        if (-not $imgBitmap) {
            [void][System.Windows.MessageBox]::Show("Die Bild-/PDF-Datei konnte nicht geladen werden: $($TxtImage.Text)", 'Fehler', 'OK', 'Error')
            return
        }
        $rot = $CmbImgRot.SelectedIndex * 90
        if ($rot -gt 0) {
            $imgBitmap.RotateFlip([System.Drawing.RotateFlipType]('Rotate' + $rot + 'FlipNone'))
        }
    }
    $zpl = New-Zpl -wMm $wMm -hMm $hMm -textLines $lines -font $font `
                   -barcode $TxtBarcode.Text.Trim() -barcodeH $bch `
                   -imgBitmap $imgBitmap -imgWidthMm (Get-Number $TxtImgWidth.Text 0) `
                   -imgDither ($CmbImgMode.SelectedIndex -eq 1) `
                   -imgThreshold ([int](Get-Number $TxtImgThreshold.Text 150)) `
                   -qty $qty -darkness $dark -align $CmbAlign.SelectedIndex `
                   -scale ([double]$SldScale.Value) `
                   -imgOffsetX ([int]$script:ImgOffsetX) -imgOffsetY ([int]$script:ImgOffsetY) `
                   -WithBorder:$WithBorder

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
    } catch {
        $TblStatus.Text = ''
        [void][System.Windows.MessageBox]::Show("Unerwarteter Fehler: $($_.Exception.Message)", 'Fehler', 'OK', 'Error')
    }
}

# ---------- Ereignisse ----------
$BtnRefresh.Add_Click({ Update-Printers })

$BtnImgBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Filter = 'Bilder und PDF|*.png;*.jpg;*.jpeg;*.pdf|PNG-Bild|*.png|JPEG-Bild|*.jpg;*.jpeg|PDF-Dokument|*.pdf|Alle Dateien|*.*'
    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $TxtImage.Text = $dlg.FileName
    }
})

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

foreach ($c in @($TxtLines, $TxtBarcode, $TxtWidth, $TxtHeight, $TxtFontSize, $TxtBarcodeHeight, $TxtImage, $TxtImgWidth, $TxtImgThreshold)) {
    $c.Add_TextChanged({ Update-Preview })
}
$CmbAlign.Add_SelectionChanged({ Update-Preview })
$CmbImgMode.Add_SelectionChanged({ Update-Preview })
$CmbImgRot.Add_SelectionChanged({ Update-Preview })

$SldDarkness.Add_ValueChanged({
    $v = [int]$SldDarkness.Value
    if ($v -eq 0) { $TblDarkness.Text = '0 (Standard)' }
    elseif ($v -gt 0) { $TblDarkness.Text = "+$v (dunkler)" }
    else { $TblDarkness.Text = "$v (heller)" }
})

$SldScale.Add_ValueChanged({
    $TblScale.Text = ([string][int]$SldScale.Value) + ' %'
    Update-Preview
})

$script:ImgOffsetX = 0
$script:ImgOffsetY = 0
$script:PreviewImageEl = $null
$script:LastImgPath = $null
$script:LastPxPerDot = 0
$script:ImgDrag = @{ Active = $false; StartX = 0; StartY = 0; BaseLeft = 0; BaseTop = 0; BaseOffX = 0; BaseOffY = 0 }

$CnvPreview.Add_MouseMove({
    if (-not $script:ImgDrag.Active) { return }
    $img = $script:PreviewImageEl
    if (-not $img) { return }
    $p = [System.Windows.Input.Mouse]::GetPosition($CnvPreview)
    [Windows.Controls.Canvas]::SetLeft($img, $script:ImgDrag.BaseLeft + ($p.X - $script:ImgDrag.StartX))
    [Windows.Controls.Canvas]::SetTop($img, $script:ImgDrag.BaseTop + ($p.Y - $script:ImgDrag.StartY))
})

$CnvPreview.Add_MouseLeftButtonUp({
    if (-not $script:ImgDrag.Active) { return }
    $script:ImgDrag.Active = $false
    [void]$CnvPreview.ReleaseMouseCapture()
    if ($script:LastPxPerDot -gt 0) {
        $p = [System.Windows.Input.Mouse]::GetPosition($CnvPreview)
        $script:ImgOffsetX = $script:ImgDrag.BaseOffX + [int][math]::Round(($p.X - $script:ImgDrag.StartX) / $script:LastPxPerDot)
        $script:ImgOffsetY = $script:ImgDrag.BaseOffY + [int][math]::Round(($p.Y - $script:ImgDrag.StartY) / $script:LastPxPerDot)
    }
    Update-Preview
})

$BtnPrint.Add_Click({ Invoke-Print -WithBorder:$false })
$BtnTest.Add_Click({ Invoke-Print -WithBorder })

$form.Add_Loaded({
    Update-Printers
    Update-Preview
})

[void]$form.ShowDialog()
