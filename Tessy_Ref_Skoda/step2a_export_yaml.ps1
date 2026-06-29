# ============================================================================
# STEP 2a: Export YAML Configuration from Tessy
# ============================================================================
# Purpose: Export the current test-object configuration from Tessy to a
#          YAML file.
#          Called by step2_configure_stubs.ps1 (Step 2).
#          May also be run standalone for debugging/re-export.
# ============================================================================
param(
    [Parameter(Mandatory=$true)][string]$TestObject,
    [Parameter(Mandatory=$true)][string]$TessyProject,
    [Parameter(Mandatory=$true)][string]$TestCollection,
    [Parameter(Mandatory=$true)][string]$ScriptRoot,
    [Parameter(Mandatory=$true)][string]$ExportDir
)

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "  STEP 2a: EXPORT YAML CONFIGURATION" -ForegroundColor Cyan
Write-Host "  Test Object: $TestObject" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

Set-Location $ScriptRoot

# Create yml folder for exports
$ymlFolder = "$ExportDir\yml"
if (-not (Test-Path $ymlFolder)) {
    New-Item -ItemType Directory -Path $ymlFolder -Force | Out-Null
    Write-Host "Created yml folder: $ymlFolder" -ForegroundColor DarkGray
}

Write-Host "`n[EXPORT] Exporting current configuration to YAML..." -ForegroundColor Yellow
$yamlFile   = "$ymlFolder\${TestObject}_export.yml"
$exportFile = "${TestObject}_export"
tessycmd export -format yaml -expected -file $exportFile "$ymlFolder"
if (-not (Test-Path $yamlFile)) {
    Write-Host "ERROR: Export file not created: $yamlFile" -ForegroundColor Red
    exit 1
}
Write-Host "Exported: $yamlFile" -ForegroundColor Green

Write-Host "`n================================================================================" -ForegroundColor Cyan
Write-Host "  STEP 2a COMPLETE" -ForegroundColor Cyan
Write-Host "  Next: Run step2_configure_stubs.ps1" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

exit 0
