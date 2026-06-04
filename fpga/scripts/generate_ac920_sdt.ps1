param(
    [string]$Vivado = "E:\vivadoref\Vivado\2024.2\bin\vivado.bat",
    [string]$Xsa = "",
    [string]$OutDir = "",
    [string]$SdtRepo = "E:\vivadoref\Vivado\2024.2\data\embeddedsw",
    [string]$Log = ""
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoDir = (Resolve-Path (Join-Path $scriptDir "..\..")).Path
$platformUtil = "E:\vivadoref\Vitis\2024.2\vitis-server\scripts\platformutil.tcl"

if ($Xsa -eq "") {
    $Xsa = Join-Path $repoDir "fpga\build\ac920_vendor_sdr\ac920_sdr.xsa"
}
if ($OutDir -eq "") {
    $OutDir = Join-Path $repoDir "fpga\build\ac920_vendor_sdr\sdt_probe_now"
}
if ($Log -eq "") {
    $Log = Join-Path $repoDir "fpga\build\ac920_vendor_sdr\sdt_probe_now.log"
}

if (!(Test-Path -LiteralPath $Vivado -PathType Leaf)) {
    throw "Vivado not found: $Vivado"
}
if (!(Test-Path -LiteralPath $platformUtil -PathType Leaf)) {
    throw "Vitis platformutil.tcl not found: $platformUtil"
}
if (!(Test-Path -LiteralPath $Xsa -PathType Leaf)) {
    throw "XSA not found: $Xsa"
}
if (!(Test-Path -LiteralPath $SdtRepo -PathType Container)) {
    throw "SDT repo not found: $SdtRepo"
}

$Xsa = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Xsa)
$OutDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutDir)
$Log = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Log)
$Journal = [System.IO.Path]::ChangeExtension($Log, ".jou")

$env:PWD = $repoDir

Write-Host "Generating AC920 SDT probe..."
Write-Host "XSA: $Xsa"
Write-Host "Out: $OutDir"
Write-Host "Log: $Log"

Push-Location -LiteralPath $repoDir
try {
    & $Vivado -mode batch -log $Log -journal $Journal -source $platformUtil -tclargs $Xsa $OutDir -repo $SdtRepo
    $status = $LASTEXITCODE
} finally {
    Pop-Location
}

if ($status -ne 0) {
    throw "SDT generation failed with exit code $status. See log: $Log"
}

Write-Host "AC920 SDT probe generated."
