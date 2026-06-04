param(
    [Parameter(Mandatory = $true)][string]$Port,
    [int]$Baud = 115200,
    [int]$DurationSeconds = 20,
    [Parameter(Mandatory = $true)][string]$Log
)

$ErrorActionPreference = "Stop"

$logDir = Split-Path -Parent $Log
if ($logDir -ne "" -and -not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

$serial = New-Object System.IO.Ports.SerialPort $Port, $Baud, "None", 8, "One"
$serial.ReadTimeout = 200
$serial.NewLine = "`n"

try {
    $serial.Open()
    $serial.DiscardInBuffer()
    $deadline = [DateTime]::UtcNow.AddSeconds($DurationSeconds)
    $buffer = New-Object byte[] 4096
    $stream = [System.IO.File]::Open($Log, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::Read)
    try {
        while ([DateTime]::UtcNow -lt $deadline) {
            try {
                $count = $serial.Read($buffer, 0, $buffer.Length)
                if ($count -gt 0) {
                    $stream.Write($buffer, 0, $count)
                    $stream.Flush()
                }
            } catch [TimeoutException] {
            }
        }
    } finally {
        $stream.Close()
    }
} finally {
    if ($serial.IsOpen) {
        $serial.Close()
    }
}
