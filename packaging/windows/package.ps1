# Packages Port Why for Windows:
#
#   package.ps1 <bundle> <version> <name>
#
# <bundle> is what `flutter build windows --release` made
# (build\windows\<arch>\runner\Release), <version> the version it was built
# as (1.2.0, or 1.2.0-dev.abc1234 for a build that isn't a release) and
# <name> the downloads' name without an extension
# (port-why-1.2.0-windows-x64). Writes, in the current directory:
#
#   <name>.zip        the app in a port-why folder, to unpack anywhere
#   <name>-setup.exe  an installer (port-why.iss), when Inno Setup's ISCC.exe
#                     is installed or ISCC names it
#
# The installer is for x64 or arm64 as <name> ends.

param(
    [Parameter(Mandatory)] [string] $Bundle,
    [Parameter(Mandatory)] [string] $Version,
    [Parameter(Mandatory)] [string] $Name
)

$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$out = (Get-Location).Path

if (-not (Test-Path -LiteralPath (Join-Path $Bundle 'port_why.exe'))) { throw "package.ps1: no port_why.exe in $Bundle" }

$stage = Join-Path ([IO.Path]::GetTempPath()) ([Guid]::NewGuid())
$dir = Join-Path $stage 'port-why'
New-Item -ItemType Directory $stage | Out-Null

try {
    Copy-Item -Recurse $Bundle $dir

    $zip = Join-Path $out "$Name.zip"
    Remove-Item -LiteralPath $zip -ErrorAction Ignore
    Compress-Archive -Path $dir -DestinationPath $zip
    Write-Host "Wrote $Name.zip"

    $iscc = if ($env:ISCC) { $env:ISCC } else { "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe" }
    if (Test-Path -LiteralPath $iscc) {
        $arch = if ($Name -like '*arm64') { 'arm64' } else { 'x64compatible' }
        # Windows file versions are numbers only: 1.2.0-dev.abc1234 becomes 1.2.0.
        $fileVersion = $Version -replace '-.*$', ''
        & $iscc /Q "/DAppVersion=$Version" "/DFileVersion=$fileVersion" "/DStageDir=$dir" "/DOutputBase=$Name-setup" `
            "/DArch=$arch" "/O$out" (Join-Path $here 'port-why.iss')
        if ($LASTEXITCODE -ne 0) { throw "ISCC failed ($LASTEXITCODE)" }
        Write-Host "Wrote $Name-setup.exe"
    } else {
        Write-Host "No Inno Setup at ${iscc}: skipping the installer"
    }
} finally {
    Remove-Item $stage -Recurse -Force -ErrorAction SilentlyContinue
}
