# Renders the installers' artwork from its SVGs:
#
#   pwsh packaging/render.ps1
#
#   windows/sidebar.svg        -> windows/sidebar.bmp, sidebar-2x.bmp (24-bit)
#   icons/512.png              -> windows/small.bmp, small-2x.bmp     (32-bit, straight alpha)
#   macos/dmg-background.svg   -> macos/dmg-background.png, dmg-background@2x.png
#
# The results are committed, so the release jobs need none of this. Run it
# again after changing an SVG, or after tool/make_icon.ps1 redraws the icons
# the artwork shows. It needs Windows, for Microsoft Edge (which draws the
# SVGs, filters and all) and the Bahnschrift and Cascadia Mono fonts they are
# set in, and ImageMagick's magick for the bitmaps.
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot

$edge = "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe"
if (-not (Test-Path -LiteralPath $edge)) { throw "render.ps1: no Microsoft Edge at $edge" }
if (-not (Get-Command magick -ErrorAction Ignore)) { throw 'render.ps1: ImageMagick (magick) is required' }

$scratch = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid())
New-Item -ItemType Directory $scratch | Out-Null

# Draws an SVG at its own size times $scale into a PNG, on a transparent
# background. Its own profile keeps it clear of any Edge the user has open.
function Render-Svg([string]$svg, [int]$width, [int]$height, [int]$scale, [string]$png) {
  $uri = ([Uri](Resolve-Path -LiteralPath $svg).Path).AbsoluteUri
  & $edge --headless --disable-gpu --hide-scrollbars --no-first-run "--user-data-dir=$scratch\profile" `
    "--force-device-scale-factor=$scale" "--window-size=$width,$height" --default-background-color=00000000 `
    "--screenshot=$png" $uri 2>&1 | Out-Null
  # Edge returns before the file is always there.
  for ($i = 0; $i -lt 50 -and -not (Test-Path -LiteralPath $png); $i++) { Start-Sleep -Milliseconds 100 }
  if (-not (Test-Path -LiteralPath $png)) { throw "render.ps1: Edge didn't render $svg" }
  $size = (& magick identify -format '%wx%h' $png)
  if ($size -ne "$($width * $scale)x$($height * $scale)") { throw "render.ps1: $svg rendered at $size" }
}

try {
  foreach ($scale in 1, 2) {
    $suffix = if ($scale -eq 1) { '' } else { '-2x' }

    # Inno Setup reads BMPs only: the sidebar opaque, the small image with
    # alpha (WizardImageAlphaFormat=defined).
    $png = Join-Path $scratch "sidebar$scale.png"
    Render-Svg (Join-Path $here 'windows\sidebar.svg') 202 386 $scale $png
    & magick $png -background black -alpha remove -alpha off -type TrueColor "BMP3:$(Join-Path $here "windows\sidebar$suffix.bmp")"
    $side = 58 * $scale
    & magick (Join-Path $here 'icons\512.png') -filter Lanczos -resize "${side}x$side" -define bmp3:alpha=true `
      "BMP3:$(Join-Path $here "windows\small$suffix.bmp")"

    $dmg = if ($scale -eq 1) { 'dmg-background.png' } else { 'dmg-background@2x.png' }
    Render-Svg (Join-Path $here 'macos\dmg-background.svg') 660 420 $scale (Join-Path $scratch $dmg)
    & magick (Join-Path $scratch $dmg) -background black -alpha remove -alpha off -strip `
      -density (72 * $scale) -units PixelsPerInch (Join-Path $here "macos\$dmg")
  }
  Get-ChildItem (Join-Path $here 'windows\*.bmp'), (Join-Path $here 'macos\*.png') |
    ForEach-Object { "wrote $($_.FullName)" }
} finally {
  Remove-Item $scratch -Recurse -Force -ErrorAction Ignore
}
