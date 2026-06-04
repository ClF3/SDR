param(
    [string]$BoardIp = "192.168.10.2",
    [string]$DestinationIp = "192.168.10.1",
    [string]$Log = ""
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoDir = Resolve-Path (Join-Path $scriptDir "..")
$probe = Join-Path $scriptDir "ac920_debug_probe.py"

if ($Log -eq "") {
    $logDir = Join-Path $repoDir "_vitis\logs"
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    $Log = Join-Path $logDir ("ac920_debug_probe_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".log")
}

Push-Location $repoDir
try {
    & cmd.exe /c "python `"$probe`" $BoardIp --destination-ip $DestinationIp > `"$Log`" 2>&1"
    $exitCode = $LASTEXITCODE
} finally {
    Pop-Location
}

Get-Content $Log
if ($exitCode -ne 0) {
    throw "ac920_debug_probe.py failed with exit code $exitCode"
}
