param(
    [string]$Vivado = "E:\vivadoref\Vivado\2024.2\bin\vivado.bat",
    [string]$Bitstream = "",
    [string]$Log = ""
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoDir = Resolve-Path (Join-Path $scriptDir "..\..")
$tcl = Join-Path $scriptDir "vivado_program_ac920_bitstream.tcl"

if (-not (Test-Path $Vivado)) {
    throw "Vivado not found: $Vivado"
}
if (-not (Test-Path $tcl)) {
    throw "Vivado program Tcl not found: $tcl"
}

if ($Bitstream -ne "") {
    $env:AC920_BIT = (Resolve-Path $Bitstream).Path
} else {
    Remove-Item Env:\AC920_BIT -ErrorAction SilentlyContinue
}

if ($Log -eq "") {
    $Log = Join-Path $repoDir "fpga\build\ac920_vendor_sdr\program_ac920_bitstream.log"
}
$journal = [System.IO.Path]::ChangeExtension($Log, ".jou")

Write-Host "Programming AC920 bitstream with Vivado..."
Write-Host "Log: $Log"

& $Vivado -mode batch -source $tcl -log $Log -journal $journal
if ($LASTEXITCODE -ne 0) {
    throw "Vivado programming failed with exit code $LASTEXITCODE. See log: $Log"
}

Write-Host "AC920 bitstream programmed."
