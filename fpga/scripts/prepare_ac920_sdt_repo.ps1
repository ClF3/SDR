param(
    [string]$SourceRepo = "E:\vivadoref\Vivado\2024.2\xsct-trim\data\system-device-tree-xlnx",
    [string]$PatchedRepo = ""
)

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$repoDir = (Resolve-Path (Join-Path $scriptDir "..\..")).Path

if ($PatchedRepo -eq "") {
    $PatchedRepo = Join-Path $repoDir "fpga\build\ac920_vendor_sdr\sdt_repo_patched"
}

if (!(Test-Path -LiteralPath $SourceRepo -PathType Container)) {
    throw "Source SDT repo not found: $SourceRepo"
}

if (Test-Path -LiteralPath $PatchedRepo) {
    Remove-Item -LiteralPath $PatchedRepo -Recurse -Force
}

New-Item -ItemType Directory -Path (Split-Path -Parent $PatchedRepo) -Force | Out-Null
Copy-Item -LiteralPath $SourceRepo -Destination $PatchedRepo -Recurse -Force

$deviceTreeTcl = Join-Path $PatchedRepo "device_tree\data\device_tree.tcl"
if (!(Test-Path -LiteralPath $deviceTreeTcl -PathType Leaf)) {
    throw "Patched SDT repo is missing device_tree.tcl: $deviceTreeTcl"
}

$text = Get-Content -LiteralPath $deviceTreeTcl -Raw
$old = @'
	if {![string_is_empty $pss_ref_clk_mhz]} {
	        add_prop $node "xlnx,pss-ref-clk-freq" $pss_ref_clk_mhz int "pcw.dtsi"
	}
'@
$new = @'
	if {![string_is_empty $pss_ref_clk_mhz]} {
		set pss_ref_clk_hz $pss_ref_clk_mhz
		if {[regexp {^[0-9]+\.[0-9]+$} $pss_ref_clk_mhz]} {
			set pss_ref_clk_hz [expr {int(round(double($pss_ref_clk_mhz) * 1000000.0))}]
		}
	        add_prop $node "xlnx,pss-ref-clk-freq" $pss_ref_clk_hz int "pcw.dtsi"
	}
'@

if (-not $text.Contains($old)) {
    throw "Could not find SDT pss-ref-clk-freq block to patch in: $deviceTreeTcl"
}

Set-Content -LiteralPath $deviceTreeTcl -Value $text.Replace($old, $new) -NoNewline

Write-Host "Prepared patched AC920 SDT repo:"
Write-Host "  $PatchedRepo"
