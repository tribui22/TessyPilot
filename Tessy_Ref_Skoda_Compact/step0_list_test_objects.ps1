# ============================================================================
# STEP 0: Connect to Tessy and List All TestObjects in a Module
# ============================================================================
# Purpose: Connect to Tessy, navigate to the specified project/collection/
#          folder/module, then list all available test objects.
#          Outputs the discovered test object names — one per line — to stdout
#          so the caller can capture and iterate over them.
# Usage:
#   $testObjects = .\step0_list_test_objects.ps1 `
#       -Module         "ani_spd_appl" `
#       -Folder         "aniSPDAppl" `
#       -TessyProject   "Chery_E0V_Variant" `
#       -TestCollection "Chery_A_Variant_ASW" `
#       -ScriptRoot     "C:\...\tessy"
# ============================================================================
param(
    [Parameter(Mandatory=$true)][string]$Module,
    [Parameter(Mandatory=$true)][string]$Folder,
    [Parameter(Mandatory=$true)][string]$TessyProject,
    [Parameter(Mandatory=$true)][string]$TestCollection,
    [Parameter(Mandatory=$true)][string]$ScriptRoot
)

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "  STEP 0: DISCOVER ALL TEST OBJECTS" -ForegroundColor Cyan
Write-Host "  Module : $Module" -ForegroundColor Cyan
Write-Host "  Folder : $Folder" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

# ── Connect ──────────────────────────────────────────────────────────────────
Write-Host "`n[CONNECT] Connecting to Tessy..." -ForegroundColor Yellow
Set-Location $ScriptRoot
tessycmd connect
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to connect to Tessy!" -ForegroundColor Red
    exit 1
}
Write-Host "Connected to Tessy." -ForegroundColor Green

# ── Select project ────────────────────────────────────────────────────────────
Write-Host "`n[SELECT] Selecting context..." -ForegroundColor Yellow
Write-Host "  Project: $TessyProject" -ForegroundColor DarkGray
tessycmd select-project "$TessyProject" 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to select project '$TessyProject'" -ForegroundColor Red
    exit 1
}

# ── Select test collection ────────────────────────────────────────────────────
Write-Host "  Test Collection: $TestCollection" -ForegroundColor DarkGray
tessycmd select-test-collection "$TestCollection" 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Failed to select test collection '$TestCollection'" -ForegroundColor Red
    exit 1
}

# ── Select folder (one level per path segment) ────────────────────────────────
if ($Folder -ne "." -and $Folder -ne "" -and $null -ne $Folder) {
    $folderLevels = $Folder -split '[/\\]'
    foreach ($folderLevel in $folderLevels) {
        Write-Host "  Folder: $folderLevel" -ForegroundColor DarkGray
        tessycmd select-folder "$folderLevel" 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            Write-Host "ERROR: Failed to select folder '$folderLevel'" -ForegroundColor Red
            exit 1
        }
    }
}

# ── Select module (try with and without .c extension) ────────────────────────
$ModuleName = $Module -replace '\.c$', ''
Write-Host "  Module: $Module" -ForegroundColor DarkGray
tessycmd select-module "$Module" 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "  Module (retry without .c): $ModuleName" -ForegroundColor DarkGray
    tessycmd select-module "$ModuleName" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: Failed to select module '$Module' or '$ModuleName'" -ForegroundColor Red
        exit 1
    }
}
Write-Host "Selection complete." -ForegroundColor Green

# ── List test objects ─────────────────────────────────────────────────────────
Write-Host "`n[LIST] Retrieving test objects..." -ForegroundColor Yellow
$rawOutput = tessycmd list-test-objects 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: 'tessycmd list-test-objects' failed (exit $LASTEXITCODE)" -ForegroundColor Red
    exit 1
}

# Filter to non-empty, non-error lines
$testObjects = $rawOutput |
    Where-Object { $_ -and ($_ -notmatch '^\s*$') -and ($_ -notmatch '^(error|warning|tessycmd)') } |
    ForEach-Object { $_.Trim() }

if ($testObjects.Count -eq 0) {
    Write-Host "ERROR: No test objects found in module '$Module'" -ForegroundColor Red
    exit 1
}

Write-Host "  Found $($testObjects.Count) test object(s):" -ForegroundColor Green
foreach ($to in $testObjects) {
    Write-Host "    - $to" -ForegroundColor DarkGray
}

Write-Host "`n================================================================================" -ForegroundColor Cyan
Write-Host "  STEP 0 COMPLETE" -ForegroundColor Cyan
Write-Host "  Next: Iterate over the test objects above and run Steps 1-5, 6, 7-10" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

# ── Return the list to the caller ─────────────────────────────────────────────
return $testObjects
