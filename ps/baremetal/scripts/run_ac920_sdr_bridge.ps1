param(
    [string]$Xsct = "E:\Xilinx\Vitis\2024.2\bin\xsct.bat",
    [string]$Vivado = "",
    [string]$Elf = "",
    [string]$PsuInit = "",
    [string]$Bitstream = "",
    [string]$Log = "",
    [switch]$SkipBitstream,
    [switch]$SystemReset,
    [switch]$SkipPsuInit
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoDir = Resolve-Path (Join-Path $scriptDir "..\..\..")
$xsctTcl = Join-Path $scriptDir "xsct_run_ac920_sdr_bridge.tcl"
$programScript = Join-Path $repoDir "fpga\scripts\program_ac920_bitstream.ps1"

if ($Vivado -eq "") {
    $vivadoCandidates = @(
        "E:\vivadoref\Vivado\2024.2\bin\vivado.bat",
        "E:\Xilinx\Vivado\2024.2\bin\vivado.bat"
    )
    foreach ($candidate in $vivadoCandidates) {
        if (Test-Path $candidate) {
            $Vivado = $candidate
            break
        }
    }
}

if (-not (Test-Path $Xsct)) {
    throw "XSCT not found: $Xsct"
}
if (-not (Test-Path $xsctTcl)) {
    throw "XSCT runner Tcl not found: $xsctTcl"
}

if ($Elf -eq "") {
    $elfFile = Get-ChildItem -Path (Join-Path $repoDir "_vitis") -Recurse -Filter "ac920_sdr_bridge.elf" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
    if ($null -eq $elfFile) {
        throw "Could not find ac920_sdr_bridge.elf under $repoDir\_vitis. Build it first with build_ac920_sdr_bridge.ps1."
    }
    $Elf = $elfFile.FullName
} else {
    $Elf = (Resolve-Path $Elf).Path
}

if ($PsuInit -eq "") {
    $elfItem = Get-Item $Elf
    $workspace = $elfItem.Directory.Parent.Parent.FullName
    $psuInitFile = Get-ChildItem -Path $workspace -Recurse -Filter "psu_init.tcl" -ErrorAction SilentlyContinue |
        Sort-Object FullName |
        Select-Object -First 1
    if ($null -eq $psuInitFile) {
        throw "Could not find psu_init.tcl under Vitis workspace $workspace"
    }
    $PsuInit = $psuInitFile.FullName
} else {
    $PsuInit = (Resolve-Path $PsuInit).Path
}

if (-not $SkipBitstream) {
    if ($Vivado -eq "" -or -not (Test-Path $Vivado)) {
        throw "Vivado not found. Pass -Vivado `"E:\path\to\Vivado\2024.2\bin\vivado.bat`" or use -SkipBitstream if PL is already programmed."
    }
    if (-not (Test-Path $programScript)) {
        throw "Bitstream programming script not found: $programScript"
    }

    $programArgs = @("-ExecutionPolicy", "Bypass", "-File", $programScript, "-Vivado", $Vivado)
    if ($Bitstream -ne "") {
        $programArgs += @("-Bitstream", $Bitstream)
    }
    Write-Host "Programming AC920 PL bitstream before running PS app..."
    & powershell @programArgs
    if ($LASTEXITCODE -ne 0) {
        throw "Bitstream programming failed with exit code $LASTEXITCODE"
    }
}

if ($Log -eq "") {
    $logDir = Join-Path $repoDir "_vitis\logs"
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    $Log = Join-Path $logDir ("ac920_xsct_run_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".log")
}

Write-Host "Running AC920 SDR bridge over JTAG..."
Write-Host "ELF     : $Elf"
Write-Host "psu_init: $PsuInit"
Write-Host "Log     : $Log"

$oldSystemReset = $env:AC920_XSCT_SYSTEM_RESET
$oldSkipPsuInit = $env:AC920_XSCT_SKIP_PSU_INIT
try {
    if ($SystemReset) {
        $env:AC920_XSCT_SYSTEM_RESET = "1"
    } else {
        Remove-Item Env:\AC920_XSCT_SYSTEM_RESET -ErrorAction SilentlyContinue
    }
    if ($SkipPsuInit) {
        $env:AC920_XSCT_SKIP_PSU_INIT = "1"
    } else {
        Remove-Item Env:\AC920_XSCT_SKIP_PSU_INIT -ErrorAction SilentlyContinue
    }

    & $Xsct $xsctTcl $Elf $PsuInit *> $Log
} finally {
    if ($null -eq $oldSystemReset) {
        Remove-Item Env:\AC920_XSCT_SYSTEM_RESET -ErrorAction SilentlyContinue
    } else {
        $env:AC920_XSCT_SYSTEM_RESET = $oldSystemReset
    }
    if ($null -eq $oldSkipPsuInit) {
        Remove-Item Env:\AC920_XSCT_SKIP_PSU_INIT -ErrorAction SilentlyContinue
    } else {
        $env:AC920_XSCT_SKIP_PSU_INIT = $oldSkipPsuInit
    }
}
if ($LASTEXITCODE -ne 0) {
    Get-Content -Path $Log -Tail 120
    throw "XSCT run failed with exit code $LASTEXITCODE. See log: $Log"
}

Get-Content -Path $Log -Tail 80
Write-Host "AC920 SDR bridge launched."
