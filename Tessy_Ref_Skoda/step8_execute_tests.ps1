# ============================================================================
# STEP 8: Execute Tests via tessycmd
# ============================================================================
# Purpose: Import test script and execute tests using tessycmd
# Usage: .\step8_execute_tests.ps1 -TestObject "PreTransFnc_DGC_RR_50F" -Module "CanCtrl" -WorkingDir "..." -ScriptRoot "..."
# ============================================================================
param(
    [Parameter(Mandatory=$true)][string]$TestObject,
    [Parameter(Mandatory=$true)][string]$Module,
    [Parameter(Mandatory=$true)][string]$WorkingDir,
    [Parameter(Mandatory=$true)][string]$Folder,
    [Parameter(Mandatory=$true)][string]$TessyProject,
    [Parameter(Mandatory=$true)][string]$TestCollection,
    [Parameter(Mandatory=$true)][string]$ScriptRoot
)

Write-Host "`n================================================================================" -ForegroundColor Cyan
Write-Host "  STEP 8: EXECUTE TESTS" -ForegroundColor Cyan
Write-Host "  Test Object: $TestObject" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

# Check if test case script exists
$scriptFile = "$WorkingDir\script_files\${TestObject}_testcase.script"
if (-not (Test-Path $scriptFile)) {
    Write-Host "[ERROR] Test case script not found: $scriptFile" -ForegroundColor Red
    exit 1
}

Set-Location $ScriptRoot
Write-Host "`n[CONTEXT] NOTE: Step 8 assumes Tessy context is already selected (from Step 1)." -ForegroundColor DarkGray

# Import test case script (replace mode to avoid HTTP 500 errors from duplicate test cases)
Write-Host "`n[IMPORT] Importing test case script..." -ForegroundColor Yellow
Write-Host "  Script: $scriptFile" -ForegroundColor DarkGray

$importOutput = tessycmd import "$scriptFile" 2>&1
Write-Host $importOutput
Write-Host "[INFO] Import done (exit $LASTEXITCODE) - continuing to execute tests..." -ForegroundColor DarkGray

# Execute tests and generate report using batch file from Step 1
Write-Host "`n[EXECUTE] Executing tests and generating report..." -ForegroundColor Yellow
$tbsDir = "$WorkingDir\tbs_files"
$batchFileHtml = "$tbsDir\generate_report_${TestObject}_html.tbs"

if (-not (Test-Path $batchFileHtml)) {
    Write-Host "[ERROR] Batch file not found (run Step 1 first): $batchFileHtml" -ForegroundColor Red
    exit 1
}

Write-Host "  Batch: $batchFileHtml" -ForegroundColor DarkGray
tessycmd -animate exec-test "$batchFileHtml"
$execExitCode = $LASTEXITCODE

if ($execExitCode -eq 0) {
    Write-Host "[OK] Tests executed and report generated" -ForegroundColor Green
} else {
    Write-Host "[WARNING] Batch execution exit code: $execExitCode (might still be OK)" -ForegroundColor Yellow
}

Write-Host "`n================================================================================" -ForegroundColor Cyan
Write-Host "  STEP 8 COMPLETE" -ForegroundColor Cyan
Write-Host "  Next: Run step9_analyze_results.ps1" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan
exit $execExitCode