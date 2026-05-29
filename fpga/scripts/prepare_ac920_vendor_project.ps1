param(
    [string]$VendorDir = $(if ($env:AC920_VENDOR_DIR) { $env:AC920_VENDOR_DIR } else { Join-Path $env:USERPROFILE "Downloads\AC920_CM3432_DualChannel_TCP" }),
    [string]$WorkDir = $(if ($env:AC920_WORK_DIR) { $env:AC920_WORK_DIR } else { "" }),
    [string]$Vivado = $(if ($env:VIVADO) { $env:VIVADO } else { "vivado" })
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

    $Candidates = @()
    foreach ($Root in @("C:\Xilinx\Vivado", "D:\Xilinx\Vivado", "C:\Xilinx", "D:\Xilinx")) {
        if (Test-Path -LiteralPath $Root -PathType Container) {
            $Candidates += Get-ChildItem -Path $Root -Recurse -Filter vivado.bat -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -match "\\Vivado\\[^\\]+\\bin\\vivado\.bat$" } |
                Sort-Object FullName -Descending
        }
    }

    if ($Candidates.Count -gt 0) {
        return $Candidates[0].FullName
    }

    return $null
}

if ([string]::IsNullOrWhiteSpace($WorkDir)) {
    $WorkDir = Join-Path $FpgaDir "build\ac920_vendor_sdr"
}

$VendorDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($VendorDir)
$WorkDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($WorkDir)
$ProjectPath = Join-Path $VendorDir $ProjectName
$OverlayScript = Join-Path $ScriptDir "vivado_ac920_vendor_overlay.tcl"

if (!(Test-Path -LiteralPath $ProjectPath -PathType Leaf)) {
    Write-Error "Vendor project not found: $ProjectPath`nUsage: .\prepare_ac920_vendor_project.ps1 -VendorDir C:\path\to\AC920_CM3432_DualChannel_TCP"
}

$VivadoExe = Resolve-VivadoExecutable $Vivado
if ($null -eq $VivadoExe) {
    Write-Error "Vivado not found: $Vivado`nRun from a Vivado shell, add Vivado\bin to PATH, or pass -Vivado C:\Xilinx\Vivado\<version>\bin\vivado.bat."
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $WorkDir) | Out-Null
if (Test-Path -LiteralPath $WorkDir) {
    Remove-Item -LiteralPath $WorkDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null

robocopy $VendorDir $WorkDir /MIR /XF .DS_Store /NFL /NDL /NJH /NJS /NP | Out-Null
$RoboCopyStatus = $LASTEXITCODE
if ($RoboCopyStatus -ge 8) {
    Write-Error "robocopy failed with exit code $RoboCopyStatus"
}

$env:AC920_PROJECT = Join-Path $WorkDir $ProjectName
$env:SDR_REPO_DIR = $RepoDir

& $VivadoExe -mode batch -source $OverlayScript
if ($LASTEXITCODE -ne 0) {
    exit $LASTEXITCODE
}

Write-Host ""
Write-Host "Prepared AC920 SDR Vivado project:"
Write-Host "  $env:AC920_PROJECT"
Write-Host ""
Write-Host "Open it with:"
Write-Host "  vivado $env:AC920_PROJECT"
