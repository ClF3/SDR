param(
    [string]$BoardIp = "192.168.10.2",
    [string]$DestinationIp = "192.168.10.1",
    [int]$TimeoutSeconds = 5
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoDir = Resolve-Path (Join-Path $scriptDir "..")
$probe = Join-Path $scriptDir "network_probe.py"

if (-not (Test-Path $probe)) {
    throw "network_probe.py not found: $probe"
}

Write-Host "AC920 network probe"
Write-Host "Board IP      : $BoardIp"
Write-Host "Destination IP: $DestinationIp"
Write-Host ""

Write-Host "== ipconfig =="
ipconfig | Select-String -Pattern "以太网 2|IPv4 Address|Subnet Mask|Default Gateway|192.168.10" -Context 0,2
Write-Host ""

Write-Host "== ping =="
ping $BoardIp -n 3
if ($LASTEXITCODE -ne 0) {
    throw "Ping failed"
}
Write-Host ""

Write-Host "== TCP 9000 =="
$tcp = Test-NetConnection $BoardIp -Port 9000 -InformationLevel Detailed
$tcp
if (-not $tcp.TcpTestSucceeded) {
    throw "TCP $BoardIp:9000 failed"
}
Write-Host ""

Write-Host "== protocol probe =="
Push-Location $repoDir
try {
    python $probe $BoardIp --skip-psd --destination-ip $DestinationIp --timeout $TimeoutSeconds
    if ($LASTEXITCODE -ne 0) {
        throw "network_probe.py failed with exit code $LASTEXITCODE"
    }
} finally {
    Pop-Location
}
