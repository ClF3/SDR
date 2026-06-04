param(
    [string]$Vivado = "E:\vivadoref\Vivado\2024.2\bin\vivado.bat",
    [string]$Xsct = "E:\Xilinx\Vitis\2024.2\bin\xsct.bat",
    [string]$Bitstream = "",
    [string]$Elf = "",
    [string]$PsuInit = "",
    [string]$BoardIp = "192.168.10.2",
    [string]$DestinationIp = "192.168.10.1",
    [int]$WaitSeconds = 8,
    [switch]$SkipBitstream,
    [switch]$SkipPsuInit,
    [switch]$SkipProbe,
    [switch]$ProgramOnly
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoDir = (Resolve-Path (Join-Path $scriptDir "..")).Path
$runBridge = Join-Path $repoDir "ps\baremetal\scripts\run_ac920_sdr_bridge.ps1"
$programBitstream = Join-Path $repoDir "fpga\scripts\program_ac920_bitstream.ps1"
$networkProbe = Join-Path $repoDir "tools\run_ac920_network_probe.ps1"

function Resolve-DefaultBitstream {
    param([string]$RepoDir)

    $defaultBit = Join-Path $RepoDir "fpga\build\ac920_vendor_sdr\CM3432_DualChannel_TCP.runs\impl_1\top.bit"
    if (Test-Path -LiteralPath $defaultBit -PathType Leaf) {
        return (Resolve-Path $defaultBit).Path
    }

    $bit = Get-ChildItem -Path (Join-Path $RepoDir "fpga\build") -Recurse -Filter "top.bit" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($null -eq $bit) {
        throw "Could not find top.bit under $RepoDir\fpga\build. Build the bitstream first."
    }
    return $bit.FullName
}

function Resolve-DefaultElf {
    param([string]$RepoDir)

    $elf = Get-ChildItem -Path (Join-Path $RepoDir "_vitis") -Recurse -Filter "ac920_sdr_bridge.elf" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($null -eq $elf) {
        throw "Could not find ac920_sdr_bridge.elf under $RepoDir\_vitis. Build the PS bridge first."
    }
    return $elf.FullName
}

if (-not (Test-Path -LiteralPath $runBridge -PathType Leaf)) {
    throw "Bridge launcher not found: $runBridge"
}
if (-not (Test-Path -LiteralPath $programBitstream -PathType Leaf)) {
    throw "Bitstream programmer not found: $programBitstream"
}

if ([string]::IsNullOrWhiteSpace($Bitstream)) {
    $Bitstream = Resolve-DefaultBitstream $repoDir
} else {
    $Bitstream = (Resolve-Path $Bitstream).Path
}

if ([string]::IsNullOrWhiteSpace($Elf)) {
    $Elf = Resolve-DefaultElf $repoDir
} else {
    $Elf = (Resolve-Path $Elf).Path
}

Write-Host "AC920 SDR board bring-up"
Write-Host "Repo          : $repoDir"
Write-Host "Vivado        : $Vivado"
Write-Host "XSCT          : $Xsct"
Write-Host "Bitstream     : $Bitstream"
Write-Host "ELF           : $Elf"
Write-Host "Board IP      : $BoardIp"
Write-Host "Destination IP: $DestinationIp"
Write-Host ""

if ($ProgramOnly) {
    Write-Host "Programming PL only..."
    & powershell -ExecutionPolicy Bypass -File $programBitstream -Vivado $Vivado -Bitstream $Bitstream
    if ($LASTEXITCODE -ne 0) {
        throw "PL programming failed with exit code $LASTEXITCODE"
    }
    Write-Host "PL programming complete."
    exit 0
}

$bridgeArgs = @(
    "-ExecutionPolicy", "Bypass",
    "-File", $runBridge,
    "-Xsct", $Xsct,
    "-Vivado", $Vivado,
    "-Elf", $Elf,
    "-Bitstream", $Bitstream
)
if ($PsuInit -ne "") {
    $bridgeArgs += @("-PsuInit", (Resolve-Path $PsuInit).Path)
}
if ($SkipBitstream) {
    $bridgeArgs += "-SkipBitstream"
}
if ($SkipPsuInit) {
    $bridgeArgs += "-SkipPsuInit"
}

Write-Host "Programming PL and launching PS bridge..."
Write-Host "Tip: if this stalls at psu_init or ELF download, power-cycle the board and run this script again."
& powershell @bridgeArgs
if ($LASTEXITCODE -ne 0) {
    throw "AC920 PS bridge launch failed with exit code $LASTEXITCODE"
}

if ($WaitSeconds -gt 0) {
    Write-Host "Waiting $WaitSeconds seconds for lwIP/TCP startup..."
    Start-Sleep -Seconds $WaitSeconds
}

if (-not $SkipProbe) {
    if (-not (Test-Path -LiteralPath $networkProbe -PathType Leaf)) {
        throw "Network probe wrapper not found: $networkProbe"
    }

    Write-Host "Running AC920 network protocol probe..."
    & powershell -ExecutionPolicy Bypass -File $networkProbe -BoardIp $BoardIp -DestinationIp $DestinationIp
    if ($LASTEXITCODE -ne 0) {
        throw "Network probe failed with exit code $LASTEXITCODE"
    }
}

Write-Host ""
Write-Host "AC920 SDR board bring-up complete."
