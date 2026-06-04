param(
    [string]$SourceXsa = "",
    [string]$OutXsa = ""
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoDir = (Resolve-Path (Join-Path $scriptDir "..\..")).Path

if ($SourceXsa -eq "") {
    $SourceXsa = Join-Path $repoDir "fpga\build\ac920_vendor_sdr\ac920_sdr.xsa"
}
if ($OutXsa -eq "") {
    $OutXsa = Join-Path $repoDir "fpga\build\ac920_vendor_sdr\ac920_sdr_sw.xsa"
}

if (!(Test-Path -LiteralPath $SourceXsa -PathType Leaf)) {
    throw "Source XSA not found: $SourceXsa"
}

$workDir = Join-Path $repoDir "fpga\build\ac920_vendor_sdr\xsa_sw_patch"
if (Test-Path -LiteralPath $workDir) {
    Remove-Item -LiteralPath $workDir -Recurse -Force
}
New-Item -ItemType Directory -Path $workDir -Force | Out-Null

$zipXsa = Join-Path $workDir "source.zip"
Copy-Item -LiteralPath $SourceXsa -Destination $zipXsa -Force
Expand-Archive -LiteralPath $zipXsa -DestinationPath $workDir -Force
Remove-Item -LiteralPath $zipXsa -Force

$hwhFiles = Get-ChildItem -Path $workDir -Recurse -Filter "*.hwh"
if ($hwhFiles.Count -eq 0) {
    throw "No HWH file found inside XSA: $SourceXsa"
}

foreach ($hwh in $hwhFiles) {
    $text = Get-Content -LiteralPath $hwh.FullName -Raw
    $text = $text.Replace('NAME="PSU__PSS_REF_CLK__FREQMHZ" VALUE="33.333"', 'NAME="PSU__PSS_REF_CLK__FREQMHZ" VALUE="33333000"')
    Set-Content -LiteralPath $hwh.FullName -Value $text -NoNewline
}

if (Test-Path -LiteralPath $OutXsa) {
    Remove-Item -LiteralPath $OutXsa -Force
}
$outZip = [System.IO.Path]::ChangeExtension($OutXsa, ".zip")
if (Test-Path -LiteralPath $outZip) {
    Remove-Item -LiteralPath $outZip -Force
}

$oldLocation = Get-Location
try {
    Set-Location -LiteralPath $workDir
    Compress-Archive -Path * -DestinationPath $outZip -Force
} finally {
    Set-Location $oldLocation
}
Move-Item -LiteralPath $outZip -Destination $OutXsa -Force

Write-Host "Prepared AC920 software XSA:"
Write-Host "  $OutXsa"
