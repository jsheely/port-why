# Draws the Port Why app icon and writes it everywhere it is used.
#
#   pwsh tool/make_icon.ps1                 # rewrites every icon below
#   pwsh tool/make_icon.ps1 -Preview x.png  # also saves a sheet of every size on light and dark
#
# It writes:
#
#   windows/runner/resources/app_icon.ico           the Windows app and its installer
#   macos/Runner/Assets.xcassets/AppIcon.appiconset the macOS app
#   packaging/icons/<size>.png                      Linux's icon theme and the installers' artwork
#
# The icon is the mark from the app's header: a three-node network in neon
# cyan on a night-dark tile inside a cyan, violet and pink rim. Each size is drawn from the same shapes rather than scaled
# down from the largest, so the small taskbar sizes can use heavier strokes and
# fill the whole canvas.
param(
  [string]$Out = (Join-Path $PSScriptRoot '..\windows\runner\resources\app_icon.ico'),
  [string]$MacIcons = (Join-Path $PSScriptRoot '..\macos\Runner\Assets.xcassets\AppIcon.appiconset'),
  [string]$PngIcons = (Join-Path $PSScriptRoot '..\packaging\icons'),
  [string]$Preview
)

Add-Type -AssemblyName System.Drawing
$ErrorActionPreference = 'Stop'

$sizes = 16, 20, 24, 32, 40, 48, 64, 128, 256

function New-RoundedRect([single]$x, [single]$y, [single]$w, [single]$h, [single]$r) {
  $path = New-Object System.Drawing.Drawing2D.GraphicsPath
  $d = 2 * $r
  $path.AddArc($x, $y, $d, $d, 180, 90)
  $path.AddArc($x + $w - $d, $y, $d, $d, 270, 90)
  $path.AddArc($x + $w - $d, $y + $h - $d, $d, $d, 0, 90)
  $path.AddArc($x, $y + $h - $d, $d, $d, 90, 90)
  $path.CloseFigure()
  $path
}

# -Margin is the air around the tile, as a fraction of the canvas. macOS wants
# more than Windows: its icons sit on a 1024 grid whose tile is 824 across.
function New-IconBitmap([int]$size, [double]$margin = 0.055) {
  # Draw oversized and reduce, which gives cleaner edges than GDI+ antialiasing alone.
  # The largest sizes have pixels enough already.
  $oversample = if ($size -ge 512) { 2 } else { 4 }
  $canvas = $size * $oversample
  $big = New-Object System.Drawing.Bitmap $canvas, $canvas, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($big)
  $g.SmoothingMode = 'AntiAlias'
  $g.PixelOffsetMode = 'HighQuality'
  $g.Clear([System.Drawing.Color]::Transparent)

  $small = $size -le 24
  # Large sizes keep a little air around the tile; small ones cannot spare it.
  $inset = if ($small) { 0 } else { $margin * $canvas }
  $u = $canvas - 2 * $inset   # the tile's edge; every measure below is a fraction of it

  # The neon rim: the header mark's cyan, violet and pink, corner to corner.
  $radius = 0.225 * $u
  $tile = New-RoundedRect $inset $inset $u $u $radius
  $bounds = New-Object System.Drawing.RectangleF $inset, $inset, $u, $u
  $rimFill = New-Object System.Drawing.Drawing2D.LinearGradientBrush $bounds, `
    ([System.Drawing.Color]::Black), ([System.Drawing.Color]::Black), 45.0
  $blend = New-Object System.Drawing.Drawing2D.ColorBlend 3
  $blend.Colors = [System.Drawing.Color[]]@(
    [System.Drawing.Color]::FromArgb(255, 0x19, 0xe3, 0xff),   # Neon.cyan
    [System.Drawing.Color]::FromArgb(255, 0xa5, 0x73, 0xff),   # Neon.violet
    [System.Drawing.Color]::FromArgb(255, 0xff, 0x2e, 0x7e))   # Neon.pink
  $blend.Positions = [single[]]@(0, 0.5, 1)
  $rimFill.InterpolationColors = $blend
  $g.FillPath($rimFill, $tile)

  # The night inside it, dusk at the top to abyss at the bottom. Small sizes
  # get a heavier rim so it still reads.
  $rim = $(if ($small) { 0.09 } else { 0.05 }) * $u
  $inner = $u - 2 * $rim
  $glass = New-RoundedRect ($inset + $rim) ($inset + $rim) $inner $inner ($radius - $rim)
  $innerBounds = New-Object System.Drawing.RectangleF ($inset + $rim), ($inset + $rim), $inner, $inner
  $night = New-Object System.Drawing.Drawing2D.LinearGradientBrush $innerBounds, `
    ([System.Drawing.Color]::FromArgb(255, 0x12, 0x10, 0x2e)), `
    ([System.Drawing.Color]::FromArgb(255, 0x04, 0x05, 0x0d)), 90.0
  $g.FillPath($night, $glass)

  $nodeW = $(if ($small) { 0.30 } else { 0.25 }) * $u
  $nodeH = $(if ($small) { 0.22 } else { 0.18 }) * $u
  $stroke = $(if ($small) { 0.085 } else { 0.055 }) * $u
  $topY = 0.29 * $u; $bottomY = 0.71 * $u; $midY = 0.5 * $u
  $leftX = 0.29 * $u; $centreX = 0.5 * $u; $rightX = 0.71 * $u

  $tree = New-Object System.Drawing.Drawing2D.GraphicsPath
  $tree.AddLine($inset + $centreX, $inset + $topY, $inset + $centreX, $inset + $midY)
  $tree.StartFigure()
  $tree.AddLines([System.Drawing.PointF[]]@(
      (New-Object System.Drawing.PointF ($inset + $leftX), ($inset + $bottomY)),
      (New-Object System.Drawing.PointF ($inset + $leftX), ($inset + $midY)),
      (New-Object System.Drawing.PointF ($inset + $rightX), ($inset + $midY)),
      (New-Object System.Drawing.PointF ($inset + $rightX), ($inset + $bottomY))))
  $nodes = New-Object System.Drawing.Drawing2D.GraphicsPath
  foreach ($centre in @($centreX, $topY), @($leftX, $bottomY), @($rightX, $bottomY)) {
    $nodes.AddPath((New-RoundedRect ($inset + $centre[0] - $nodeW / 2) ($inset + $centre[1] - $nodeH / 2) $nodeW $nodeH (0.05 * $u)), $false)
  }

  # The glow a neon tube throws (neonGlow in the app), as ever wider and
  # fainter strokes of the glyph's outline; too fine to show when small.
  $cyan = [System.Drawing.Color]::FromArgb(255, 0x19, 0xe3, 0xff)
  if (-not $small) {
    foreach ($step in 8, 7, 6, 5, 4, 3, 2, 1) {
      $haze = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(13, $cyan)), ($stroke + $step * 0.016 * $u)
      $haze.StartCap = 'Round'; $haze.EndCap = 'Round'; $haze.LineJoin = 'Round'
      $g.DrawPath($haze, $tree)
      $g.DrawPath($haze, $nodes)
    }
  }

  # Connectors first, so the nodes sit on top of their ends.
  $pen = New-Object System.Drawing.Pen $cyan, $stroke
  $pen.StartCap = 'Round'; $pen.EndCap = 'Round'; $pen.LineJoin = 'Round'
  $g.DrawPath($pen, $tree)
  $g.FillPath((New-Object System.Drawing.SolidBrush $cyan), $nodes)
  $g.Dispose()

  $bmp = New-Object System.Drawing.Bitmap $size, $size, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.InterpolationMode = 'HighQualityBicubic'
  $g.PixelOffsetMode = 'HighQuality'
  $g.CompositingQuality = 'HighQuality'
  # Without this the resampler blends the edge pixels with nothing and darkens them.
  $wrap = New-Object System.Drawing.Imaging.ImageAttributes
  $wrap.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY)
  $target = New-Object System.Drawing.Rectangle 0, 0, $size, $size
  $g.DrawImage($big, $target, 0, 0, $canvas, $canvas, [System.Drawing.GraphicsUnit]::Pixel, $wrap)
  $g.Dispose(); $big.Dispose()
  $bmp
}

# One .ico image: PNG for 256 (the only size Windows expects compressed), and a
# classic 32-bit bitmap with its transparency mask for the rest, which is what
# the resource compiler and every version of the shell accept.
function Get-IconImageBytes([System.Drawing.Bitmap]$bmp) {
  $size = $bmp.Width
  $stream = New-Object System.IO.MemoryStream
  if ($size -ge 256) {
    $bmp.Save($stream, [System.Drawing.Imaging.ImageFormat]::Png)
    return , $stream.ToArray()
  }

  $rect = New-Object System.Drawing.Rectangle 0, 0, $size, $size
  $data = $bmp.LockBits($rect, 'ReadOnly', [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $pixels = New-Object byte[] ($size * $size * 4)
  for ($row = 0; $row -lt $size; $row++) {
    [System.Runtime.InteropServices.Marshal]::Copy([IntPtr]::Add($data.Scan0, $row * $data.Stride), $pixels, $row * $size * 4, $size * 4)
  }
  $bmp.UnlockBits($data)

  $maskStride = [int]([math]::Ceiling($size / 32.0) * 4)
  $writer = New-Object System.IO.BinaryWriter $stream
  $writer.Write([int]40)              # BITMAPINFOHEADER size
  $writer.Write([int]$size)
  $writer.Write([int]($size * 2))     # colour rows plus mask rows
  $writer.Write([int16]1)             # planes
  $writer.Write([int16]32)            # bits per pixel
  $writer.Write([int]0)               # uncompressed
  $writer.Write([int]($size * $size * 4 + $maskStride * $size))
  $writer.Write([int]0); $writer.Write([int]0); $writer.Write([int]0); $writer.Write([int]0)
  # Bitmaps are stored bottom row first.
  for ($row = $size - 1; $row -ge 0; $row--) { $writer.Write($pixels, $row * $size * 4, $size * 4) }
  for ($row = $size - 1; $row -ge 0; $row--) {
    $line = New-Object byte[] $maskStride
    for ($x = 0; $x -lt $size; $x++) {
      if ($pixels[($row * $size + $x) * 4 + 3] -eq 0) { $line[$x -shr 3] = $line[$x -shr 3] -bor (0x80 -shr ($x -band 7)) }
    }
    $writer.Write($line)
  }
  $writer.Flush()
  , $stream.ToArray()
}

$bitmaps = foreach ($size in $sizes) { New-IconBitmap $size }
$images = foreach ($bmp in $bitmaps) { , (Get-IconImageBytes $bmp) }

$file = New-Object System.IO.MemoryStream
$writer = New-Object System.IO.BinaryWriter $file
$writer.Write([int16]0); $writer.Write([int16]1); $writer.Write([int16]$sizes.Count)   # ICONDIR
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
  $dimension = [byte]($sizes[$i] % 256)   # 256 is written as 0
  $writer.Write($dimension); $writer.Write($dimension)
  $writer.Write([byte]0); $writer.Write([byte]0)
  $writer.Write([int16]1); $writer.Write([int16]32)
  $writer.Write([int]$images[$i].Length); $writer.Write([int]$offset)
  $offset += $images[$i].Length
}
foreach ($image in $images) { $writer.Write($image) }
$writer.Flush()
$Out = [System.IO.Path]::GetFullPath($Out)
[System.IO.File]::WriteAllBytes($Out, $file.ToArray())
"wrote $Out ($($file.Length) bytes, sizes $($sizes -join ', '))"

function Save-Png([System.Drawing.Bitmap]$bmp, [string]$path) {
  $path = [System.IO.Path]::GetFullPath($path)
  [void](New-Item -ItemType Directory -Force (Split-Path $path))
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $bmp.Dispose()
}

# The macOS app's sizes, named as the asset catalog's Contents.json lists them.
foreach ($size in 16, 32, 64, 128, 256, 512, 1024) {
  Save-Png (New-IconBitmap $size (100 / 1024)) (Join-Path $MacIcons "app_icon_$size.png")
}
"wrote $([System.IO.Path]::GetFullPath($MacIcons))"

# The hicolor theme's sizes, for Linux; the installers' artwork uses them too.
foreach ($size in 16, 32, 48, 64, 128, 256, 512) {
  Save-Png (New-IconBitmap $size) (Join-Path $PngIcons "$size.png")
}
"wrote $([System.IO.Path]::GetFullPath($PngIcons))"

if ($Preview) {
  # Every size at 1:1 on a light and a dark strip, as a taskbar would show them.
  [int]$width = ($sizes | Measure-Object -Sum).Sum + 24 * ($sizes.Count + 1)
  $sheet = New-Object System.Drawing.Bitmap $width, 608
  $g = [System.Drawing.Graphics]::FromImage($sheet)
  $bands = @(0, [System.Drawing.Color]::FromArgb(243, 243, 243)), @(304, [System.Drawing.Color]::FromArgb(32, 32, 32))
  foreach ($band in $bands) {
    $g.FillRectangle((New-Object System.Drawing.SolidBrush $band[1]), 0, $band[0], $width, 304)
    $x = 24
    foreach ($bmp in $bitmaps) {
      $g.DrawImageUnscaled($bmp, $x, $band[0] + 24 + (256 - $bmp.Height))
      $x += $bmp.Width + 24
    }
  }
  $g.Dispose()
  $Preview = [System.IO.Path]::GetFullPath($Preview)
  $sheet.Save($Preview, [System.Drawing.Imaging.ImageFormat]::Png)
  "wrote $Preview"
}
