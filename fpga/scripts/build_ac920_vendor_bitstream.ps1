param(
    [string]$Project = $(if ($env:AC920_PROJECT) { $env:AC920_PROJECT } else { "" }),
    [string]$Vivado = $(if ($env:VIVADO) { $env:VIVADO } else { "vivado" }),
    [int]$Jobs = $(if ($env:VIVADO_JOBS) { [int]$env:VIVADO_JOBS } else { 1 })
)

$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$FpgaDir = (Resolve-Path (Join-Path $ScriptDir "..")).Path
$RepoDir = (Resolve-Path (Join-Path $FpgaDir "..")).Path
$ProjectName = "CM3432_DualChannel_TCP.xpr"

function Resolve-VivadoExecutable {
    param([string]$VivadoArg)

    $Command = Get-Command $VivadoArg -ErrorAction SilentlyContinue
    if ($null -ne $Command) {
        return $Command.Source
    }

    if (Test-Path -LiteralPath $VivadoArg -PathType Leaf) {
        return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($VivadoArg)
    }

    if (Test-Path -LiteralPath $VivadoArg -PathType Container) {
        foreach ($CandidateName in @("vivado.bat", "vivado.exe")) {
            $Candidate = Join-Path $VivadoArg $CandidateName
            if (Test-Path -LiteralPath $Candidate -PathType Leaf) {
                return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Candidate)
            }
        }
    }

    if ($env:XILINX_VIVADO) {
        foreach ($CandidateName in @("vivado.bat", "vivado.exe")) {
            $Candidate = Join-Path $env:XILINX_VIVADO (Join-Path "bin" $CandidateName)
            if (Test-Path -LiteralPath $Candidate -PathType Leaf) {
                return $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Candidate)
            }
        }
    }

    foreach ($Root in @("C:\Xilinx\Vivado", "D:\Xilinx\Vivado", "E:\vivadoref\Vivado", "C:\Xilinx", "D:\Xilinx")) {
        if (Test-Path -LiteralPath $Root -PathType Container) {
            $Candidates = Get-ChildItem -Path $Root -Recurse -Filter vivado.bat -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -match "\\Vivado\\[^\\]+\\bin\\vivado\.bat$" } |
                Sort-Object FullName -Descending
            if ($Candidates.Count -gt 0) {
                return $Candidates[0].FullName
            }
        }
    }

    return $null
}

if ([string]::IsNullOrWhiteSpace($Project)) {
    $Project = Join-Path $FpgaDir "build\ac920_vendor_sdr\$ProjectName"
}

$Project = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($Project)
$BuildDir = Split-Path -Parent $Project
$BuildScript = Join-Path $ScriptDir "vivado_ac920_build_bitstream.tcl"
$VivadoLog = Join-Path $BuildDir "ac920_bitstream_vivado.log"
$VivadoJournal = Join-Path $BuildDir "ac920_bitstream_vivado.jou"

if (!(Test-Path -LiteralPath $Project -PathType Leaf)) {
    Write-Error "Vivado project not found: $Project"
}

$VivadoExe = Resolve-VivadoExecutable $Vivado
if ($null -eq $VivadoExe) {
    Write-Error "Vivado not found: $Vivado"
}

$env:AC920_PROJECT = $Project
$env:SDR_REPO_DIR = $RepoDir
$env:VIVADO_JOBS = "$Jobs"
$env:PWD = $RepoDir

Push-Location -LiteralPath $RepoDir
try {
    & $VivadoExe -mode batch -source $BuildScript -log $VivadoLog -journal $VivadoJournal
    $VivadoStatus = $LASTEXITCODE
} finally {
    Pop-Location
}

if ($VivadoStatus -ne 0) {
    Write-Error "Vivado bitstream build failed with exit code $VivadoStatus. See log: $VivadoLog"
}

if (!(Test-Path -LiteralPath $VivadoLog -PathType Leaf)) {
    Write-Error "Vivado did not create the expected log file: $VivadoLog"
}

$VivadoLogText = Get-Content -LiteralPath $VivadoLog -Raw
if ($VivadoLogText -notmatch "AC920 bitstream complete\.") {
    Write-Error "Vivado did not complete bitstream generation. See log: $VivadoLog"
}

$Bitstream = Join-Path $BuildDir "CM3432_DualChannel_TCP.runs\impl_1\top.bit"
Write-Host ""
Write-Host "Generated AC920 SDR bitstream:"
Write-Host "  $Bitstream"
