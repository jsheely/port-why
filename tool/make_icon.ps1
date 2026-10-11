# Draws the Port Why app icon and writes it as a multi-size .ico.
#
#   pwsh tool/make_icon.ps1                 # rewrites windows/runner/resources/app_icon.ico
#   pwsh tool/make_icon.ps1 -Preview x.png  # also saves a sheet of every size on light and dark
#
# The icon is the mark from the app's header: a three-node network on a blue
# rounded square. Each size is drawn from the same shapes rather than scaled
# down from the largest, so the small taskbar sizes can use heavier strokes and
# fill the whole canvas.
param(
  [string]$Out = (Join-Path $PSScriptRoot '..\windows\runner\resources\app_icon.ico'),
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

function New-IconBitmap([int]$size) {
  # Draw oversized and reduce, which gives cleaner edges than GDI+ antialiasing alone.
  $oversample = 4
  $canvas = $size * $oversample
  $big = New-Object System.Drawing.Bitmap $canvas, $canvas, ([System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
  $g = [System.Drawing.Graphics]::FromImage($big)
  $g.SmoothingMode = 'AntiAlias'
  $g.PixelOffsetMode = 'HighQuality'
  $g.Clear([System.Drawing.Color]::Transparent)

  $small = $size -le 24
  # Large sizes keep a little air around the tile; small ones cannot spare it.
  $inset = if ($small) { 0 } else { 0.055 * $canvas }
  $u = $canvas - 2 * $inset   # the tile's edge; every measure below is a fraction of it

  $tile = New-RoundedRect $inset $inset $u $u (0.225 * $u)
  $bounds = New-Object System.Drawing.RectangleF $inset, $inset, $u, $u
  $fill = New-Object System.Drawing.Drawing2D.LinearGradientBrush $bounds, `
    ([System.Drawing.Color]::FromArgb(255, 94, 150, 255)), `
    ([System.Drawing.Color]::FromArgb(255, 40, 86, 214)), 55.0
  $g.FillPath($fill, $tile)

  $white = [System.Drawing.Brushes]::White
  $nodeW = $(if ($small) { 0.31 } else { 0.27 }) * $u
  $nodeH = $(if ($small) { 0.23 } else { 0.20 }) * $u
  $stroke = $(if ($small) { 0.09 } else { 0.062 }) * $u
  $topY = 0.275 * $u; $bottomY = 0.725 * $u; $midY = 0.5 * $u
  $leftX = 0.27 * $u; $centreX = 0.5 * $u; $rightX = 0.73 * $u

  # Connectors first, so the nodes sit on top of their ends.
  $pen = New-Object System.Drawing.Pen ([System.Drawing.Color]::White), $stroke
  $pen.StartCap = 'Round'; $pen.EndCap = 'Round'; $pen.LineJoin = 'Round'
  $tree = New-Object System.Drawing.Drawing2D.GraphicsPath
  $tree.AddLine($inset + $centreX, $inset + $topY, $inset + $centreX, $inset + $midY)
  $tree.StartFigure()
  $tree.AddLines([System.Drawing.PointF[]]@(
      (New-Object System.Drawing.PointF ($inset + $leftX), ($inset + $bottomY)),
      (New-Object System.Drawing.PointF ($inset + $leftX), ($inset + $midY)),
      (New-Object System.Drawing.PointF ($inset + $rightX), ($inset + $midY)),
      (New-Object System.Drawing.PointF ($inset + $rightX), ($inset + $bottomY))))
  $g.DrawPath($pen, $tree)

  foreach ($centre in @($centreX, $topY), @($leftX, $bottomY), @($rightX, $bottomY)) {
    $node = New-RoundedRect ($inset + $centre[0] - $nodeW / 2) ($inset + $centre[1] - $nodeH / 2) $nodeW $nodeH (0.05 * $u)
    $g.FillPath($white, $node)
  }
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
