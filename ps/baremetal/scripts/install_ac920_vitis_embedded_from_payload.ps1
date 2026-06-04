param(
    [string]$VitisRoot = "E:\vivadoref\Vitis\2024.2",
    [string]$VivadoRoot = "E:\vivadoref\Vivado\2024.2",
    [string]$PayloadRoot = "E:\FPGAs_AdaptiveSoCs_Unified_2024.2_1113_1001\FPGAs_AdaptiveSoCs_Unified_2024.2_1113_1001\payload"
)

$ErrorActionPreference = "Stop"

if (!(Test-Path -LiteralPath $VitisRoot -PathType Container)) {
    throw "Vitis root not found: $VitisRoot"
}
if (!(Test-Path -LiteralPath $VivadoRoot -PathType Container)) {
    throw "Vivado root not found: $VivadoRoot"
}
$vivadoEmbeddedsw = Join-Path $VivadoRoot "data\embeddedsw"
if (!(Test-Path -LiteralPath $vivadoEmbeddedsw -PathType Container)) {
    throw "Vivado embeddedsw not found: $vivadoEmbeddedsw"
}

throw @"
The AMD installer payload files are encrypted 7z archives and cannot be
extracted with Windows tar/bsdtar/7za directly. Use the AMD installer GUI
instead:

  E:\FPGAs_AdaptiveSoCs_Unified_2024.2_1113_1001\FPGAs_AdaptiveSoCs_Unified_2024.2_1113_1001\xsetup.exe

Run it as Administrator, choose the installed 2024.2 location:

  E:\vivadoref

Then add/install:

  Vitis Embedded Development

After the installer finishes, verify these exist:

  E:\vivadoref\Vitis\2024.2\gnu\aarch64\nt\aarch64-none\bin\aarch64-none-elf-gcc.exe
  E:\vivadoref\Vitis\2024.2\data\embeddedsw
"@
