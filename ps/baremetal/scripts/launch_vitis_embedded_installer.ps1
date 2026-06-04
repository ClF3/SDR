param(
    [string]$Installer = "E:\FPGAs_AdaptiveSoCs_Unified_2024.2_1113_1001\FPGAs_AdaptiveSoCs_Unified_2024.2_1113_1001\xsetup.exe"
)

$ErrorActionPreference = "Stop"

if (!(Test-Path -LiteralPath $Installer -PathType Leaf)) {
    throw "AMD/Xilinx installer not found: $Installer"
}

Write-Host "Launching AMD/Xilinx installer as Administrator..."
Write-Host "Installer: $Installer"
Write-Host ""
Write-Host "In the installer, use the existing install location:"
Write-Host "  E:\vivadoref"
Write-Host ""
Write-Host "Add/install this component:"
Write-Host "  Vitis Embedded Development"
Write-Host ""
Write-Host "When it finishes, come back and tell Codex to continue."

Start-Process -FilePath $Installer -Verb RunAs
