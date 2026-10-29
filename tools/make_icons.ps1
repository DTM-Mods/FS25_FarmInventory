param([string]$OutDir)
Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'

function New-Canvas {
    $bmp = New-Object System.Drawing.Bitmap 512, 512
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.TextRenderingHint = 'AntiAliasGridFit'
    $g.InterpolationMode = 'HighQualityBicubic'
    return $bmp, $g
}
function C([int]$r, [int]$gg, [int]$b, [int]$a = 255) { [System.Drawing.Color]::FromArgb($a, $r, $gg, $b) }
function Brush($c) { New-Object System.Drawing.SolidBrush $c }
function Grad($x1, $y1, $x2, $y2, $c1, $c2) {
    New-Object System.Drawing.Drawing2D.LinearGradientBrush (New-Object System.Drawing.PointF $x1, $y1), (New-Object System.Drawing.PointF $x2, $y2), $c1, $c2
}
function Background($g, $c1, $c2) {
    $g.FillRectangle((Grad 0 0 0 512 $c1 $c2), 0, 0, 512, 512)
}
# Silo body with domed roof and horizontal ring lines
function Silo($g, [float]$x, [float]$y, [float]$w, [float]$h, $light, $dark, $ring) {
    $body = Grad $x 0 ($x + $w) 0 $light $dark
    $g.FillRectangle($body, $x, $y + $w / 2, $w, $h - $w / 2)
    $g.FillPie($body, $x, $y, $w, $w, 180, 180)
    $pen = New-Object System.Drawing.Pen $ring, 3
    for ($ry = $y + $w / 2 + 28; $ry -lt $y + $h - 8; $ry += 30) { $g.DrawLine($pen, $x, $ry, $x + $w, $ry) }
    $cap = Brush $ring
    $g.FillRectangle($cap, $x + $w / 2 - 6, $y - 14, 12, 18)
}
function Text($g, $s, [float]$size, $brush, [float]$cx, [float]$cy, [string]$style = 'Bold') {
    $font = New-Object System.Drawing.Font 'Arial', $size, ([System.Drawing.FontStyle]$style), ([System.Drawing.GraphicsUnit]::Pixel)
    $fmt = New-Object System.Drawing.StringFormat
    $fmt.Alignment = 'Center'; $fmt.LineAlignment = 'Center'
    $g.DrawString($s, $font, $brush, (New-Object System.Drawing.RectangleF ($cx - 256), ($cy - 128), 512, 256), $fmt)
}
function RoundRect([float]$x, [float]$y, [float]$w, [float]$h, [float]$r) {
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $p.AddArc($x, $y, $r * 2, $r * 2, 180, 90)
    $p.AddArc($x + $w - $r * 2, $y, $r * 2, $r * 2, 270, 90)
    $p.AddArc($x + $w - $r * 2, $y + $h - $r * 2, $r * 2, $r * 2, 0, 90)
    $p.AddArc($x, $y + $h - $r * 2, $r * 2, $r * 2, 90, 90)
    $p.CloseFigure()
    return $p
}

$green = C 142 190 30; $greenDark = C 88 128 14
$steel = C 214 220 226; $steelDark = C 128 138 148; $ring = C 96 104 112
$white = Brush (C 255 255 255)

# --- A: steel silo with green price tag ---------------------------------------------------
$bmp, $g = New-Canvas
Background $g (C 44 52 60) (C 22 26 30)
$g.FillEllipse((Brush (C 0 0 0 70)), 90, 420, 260, 40)
Silo $g 120 110 200 330 $steel $steelDark $ring
$tag = RoundRect 270 250 200 130 22
$g.TranslateTransform(370, 315); $g.RotateTransform(-12); $g.TranslateTransform(-370, -315)
$g.FillPath((Brush (C 0 0 0 90)), (RoundRect 276 258 200 130 22))
$g.FillPath((Grad 0 250 0 380 $green $greenDark), $tag)
$g.FillEllipse((Brush (C 22 26 30)), 288, 303, 22, 22)
Text $g '$' 104 $white 392 316
$g.ResetTransform()
$bmp.Save((Join-Path $OutDir 'icon_A_siloTag.png'), [System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose()

# --- B: three silos with a rising price line ----------------------------------------------
$bmp, $g = New-Canvas
Background $g (C 34 58 86) (C 14 24 38)
$g.FillRectangle((Brush (C 70 96 40)), 0, 430, 512, 82)
Silo $g 60 190 120 250 $steel $steelDark $ring
Silo $g 196 130 130 310 $steel $steelDark $ring
Silo $g 342 210 110 230 $steel $steelDark $ring
$pts = @((New-Object System.Drawing.PointF 40, 330), (New-Object System.Drawing.PointF 150, 270), (New-Object System.Drawing.PointF 250, 300), (New-Object System.Drawing.PointF 360, 170), (New-Object System.Drawing.PointF 450, 110))
$shadow = New-Object System.Drawing.Pen (C 0 0 0 120), 26; $shadow.LineJoin = 'Round'; $shadow.StartCap = 'Round'
$g.DrawLines($shadow, $pts)
$line = New-Object System.Drawing.Pen $green, 18; $line.LineJoin = 'Round'; $line.StartCap = 'Round'
$g.DrawLines($line, $pts)
$arrow = New-Object System.Drawing.Drawing2D.GraphicsPath
$arrow.AddPolygon(@((New-Object System.Drawing.PointF 482, 78), (New-Object System.Drawing.PointF 418, 96), (New-Object System.Drawing.PointF 466, 142)))
$g.FillPath((Brush $green), $arrow)
$g.FillEllipse((Brush $green), 18, 438, 64, 64)
Text $g '$' 50 $white 50 471
$bmp.Save((Join-Path $OutDir 'icon_B_siloChart.png'), [System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose()

# --- C: green silo with gold coin stack -----------------------------------------------------
$bmp, $g = New-Canvas
Background $g (C 250 246 236) (C 222 214 196)
$g.FillEllipse((Brush (C 0 0 0 40)), 70, 440, 300, 36)
Silo $g 90 100 210 350 $green $greenDark (C 60 90 10)
$gold = C 246 196 50; $goldDark = C 190 136 20
for ($k = 0; $k -lt 5; $k++) {
    $cy = 420 - $k * 30
    $g.FillEllipse((Brush $goldDark), 300, $cy + 8, 170, 50)
    $g.FillEllipse((Grad 300 0 470 0 $gold $goldDark), 300, $cy, 170, 50)
}
$g.FillEllipse((Brush (C 255 220 90)), 318, 286, 134, 36)
Text $g '$' 34 (Brush $goldDark) 385 304
$bmp.Save((Join-Path $OutDir 'icon_C_siloCoins.png'), [System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose()

# --- preview sheet ---------------------------------------------------------------------------
$sheet = New-Object System.Drawing.Bitmap 1580, 560
$sg = [System.Drawing.Graphics]::FromImage($sheet); $sg.Clear((C 255 255 255)); $sg.InterpolationMode = 'HighQualityBicubic'
$i = 0
foreach ($n in 'icon_A_siloTag.png', 'icon_B_siloChart.png', 'icon_C_siloCoins.png') {
    $img = [System.Drawing.Image]::FromFile((Join-Path $OutDir $n))
    $sg.DrawImage($img, 10 + $i * 525, 10, 512, 512); $img.Dispose()
    $font = New-Object System.Drawing.Font 'Arial', 22, ([System.Drawing.FontStyle]::Bold), ([System.Drawing.GraphicsUnit]::Pixel)
    $sg.DrawString([string][char](65 + $i), $font, (Brush (C 0 0 0)), 10 + $i * 525 + 246, 526)
    $i++
}
$sheet.Save((Join-Path $OutDir 'preview.png'), [System.Drawing.Imaging.ImageFormat]::Png); $sg.Dispose(); $sheet.Dispose()
'ok'
