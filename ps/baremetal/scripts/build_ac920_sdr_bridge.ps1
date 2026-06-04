param(
    [string]$Vitis = "E:\vivadoref\Vitis\2024.2\bin\vitis.bat",
    [string]$Xsa = "C:\Users\86135\Desktop\SDR\fpga\build\ac920_vendor_sdr\ac920_sdr.xsa",
    [string]$SdtRepo = "",
    [string]$Workspace = ""
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoDir = Resolve-Path (Join-Path $scriptDir "..\..\..")
$vitisRoot = Resolve-Path (Join-Path (Split-Path -Parent $Vitis) "..")
$expectedVitisEmbeddedsw = Join-Path $vitisRoot "data\embeddedsw"
$expectedA53Gcc = Join-Path $vitisRoot "gnu\aarch64\nt\aarch64-none\bin\aarch64-none-elf-gcc.exe"
$vitisScript = Join-Path $scriptDir "vitis_create_ac920_sdr.py"
$prepareSdtRepo = Join-Path $repoDir "fpga\scripts\prepare_ac920_sdt_repo.ps1"
$prepareSoftwareXsa = Join-Path $repoDir "fpga\scripts\prepare_ac920_software_xsa.ps1"

if ($SdtRepo -eq "") {
    $SdtRepo = Join-Path $repoDir "fpga\build\ac920_vendor_sdr\sdt_repo_patched"
}

if (-not (Test-Path $Vitis)) {
    throw "Vitis not found: $Vitis"
}
if (-not (Test-Path $Xsa)) {
    throw "XSA not found: $Xsa"
}
if (-not (Test-Path $prepareSdtRepo)) {
    throw "SDT repo preparation script not found: $prepareSdtRepo"
}
if (-not (Test-Path $prepareSoftwareXsa)) {
    throw "Software XSA preparation script not found: $prepareSoftwareXsa"
}
if (-not (Test-Path $expectedVitisEmbeddedsw)) {
    Write-Warning "Vitis data\embeddedsw is missing: $expectedVitisEmbeddedsw"
}
if (-not (Test-Path $expectedA53Gcc)) {
    Write-Warning "A53 bare-metal GCC is missing: $expectedA53Gcc"
    Write-Warning "Install the Vitis 2024.2 embedded/standalone toolchain before building the PS ELF."
}

& powershell -ExecutionPolicy Bypass -File $prepareSdtRepo -PatchedRepo $SdtRepo
if ($LASTEXITCODE -ne 0) {
    throw "Failed to prepare patched SDT repo"
}
$softwareXsa = Join-Path $repoDir "fpga\build\ac920_vendor_sdr\ac920_sdr_sw.xsa"
& powershell -ExecutionPolicy Bypass -File $prepareSoftwareXsa -SourceXsa $Xsa -OutXsa $softwareXsa
if ($LASTEXITCODE -ne 0) {
    throw "Failed to prepare software XSA"
}

$env:SDR_REPO_DIR = $repoDir.Path
$env:AC920_XSA = (Resolve-Path $softwareXsa).Path
$env:VITIS_SDT_REPO = (Resolve-Path $SdtRepo).Path
if ($Workspace -eq "") {
    $Workspace = Join-Path $repoDir ("_vitis\ac920_" + (Get-Date -Format "MMdd_HHmmss"))
}
$env:AC920_VITIS_WORKSPACE = $Workspace

$logDir = Join-Path $repoDir "_vitis\logs"
New-Item -ItemType Directory -Path $logDir -Force | Out-Null
$buildLog = Join-Path $logDir ("ac920_vitis_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".log")

& $Vitis -s $vitisScript *> $buildLog
Write-Host "Vitis build log: $buildLog"
if ($LASTEXITCODE -ne 0) {
    Get-Content -Path $buildLog -Tail 120
    throw "Vitis build failed with exit code $LASTEXITCODE"
}

$appDir = Join-Path $Workspace "ac920_sdr_bridge"
$elf = Get-ChildItem -Path $appDir -Recurse -Filter "*.elf" -ErrorAction SilentlyContinue | Select-Object -First 1
if (-not (Test-Path $appDir) -or $null -eq $elf) {
    Get-Content -Path $buildLog -Tail 120
    throw "Vitis did not produce ac920_sdr_bridge ELF. Check the warnings above; the embedded platform/toolchain is probably incomplete."
}

Write-Host "Generated AC920 SDR bridge ELF: $($elf.FullName)"
