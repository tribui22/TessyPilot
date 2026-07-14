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
Write-Host "`n[CONTEXT] Selecting Tessy context before import..." -ForegroundColor Yellow

$tessy = Join-Path $ScriptRoot "tessycmd.exe"
& $tessy select-project "$TessyProject" 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Failed to select project '$TessyProject'" -ForegroundColor Red
    exit 2
}

& $tessy select-test-collection "$TestCollection" 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Failed to select test collection '$TestCollection'" -ForegroundColor Red
    exit 2
}

if ($Folder -ne "." -and $Folder -ne "" -and $null -ne $Folder) {
    $folders = @($Folder -split '[/\\]' | Where-Object { $_ -ne '' })
    for ($idx = 0; $idx -lt $folders.Count; $idx++) {
        $folderLevel = $folders[$idx]
        if ($idx -eq 0) {
            & $tessy select-folder -collection "$folderLevel" 2>&1 | Out-Null
        } else {
            & $tessy select-folder "$folderLevel" 2>&1 | Out-Null
        }
        if ($LASTEXITCODE -ne 0) {
            Write-Host "[ERROR] Failed to select folder '$folderLevel' from path '$Folder'" -ForegroundColor Red
            exit 2
        }
    }
}

$moduleName = $Module -replace '\.c$',''
$noFolder = ($Folder -eq "." -or $Folder -eq "" -or $null -eq $Folder)
if ($noFolder) {
    & $tessy select-module -c "$Module" 2>&1 | Out-Null
} else {
    & $tessy select-module "$Module" 2>&1 | Out-Null
}
if ($LASTEXITCODE -ne 0) {
    if ($noFolder) {
        & $tessy select-module -c "$moduleName" 2>&1 | Out-Null
    } else {
        & $tessy select-module "$moduleName" 2>&1 | Out-Null
    }
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Failed to select module '$Module' or '$moduleName'" -ForegroundColor Red
        exit 2
    }
}

& $tessy select-test-object "$TestObject" 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "[ERROR] Failed to select test object '$TestObject'" -ForegroundColor Red
    exit 2
}
Write-Host "[OK] Tessy context selected." -ForegroundColor Green

# Import the AI-derived testcase plan as Tessy YAML instead of the legacy exported YAML.
Write-Host "`n[IMPORT] Importing testcase-plan YAML..." -ForegroundColor Yellow
$importYml = Join-Path $WorkingDir "yml\${TestObject}_import.yml"
if (-not (Test-Path $importYml)) {
    $generator = Join-Path $PSScriptRoot "generate_tessy_import_yml.ps1"
    & $generator -TestObject $TestObject -Module $Module -WorkDir $WorkingDir -ScriptRoot $ScriptRoot -StubNames @('ucDrv_CfgSetFCCFreqOfMCLK','ucDrv_ConfigureFCC','ucDrv_FCCDone','ucDrv_LockRegister','ucDrv_ReadFCC','ucDrv_SetFCCPeriod','ucDrv_StartFCC','ucDrv_UnlockRegister') -TessyProject $TessyProject
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[ERROR] Failed to generate Tessy import YAML" -ForegroundColor Red
        exit 1
    }
}
Write-Host "  YAML: $importYml" -ForegroundColor DarkGray

$importOutput = & $tessy import "$importYml" 2>&1
Write-Host $importOutput
$importExitCode = $LASTEXITCODE
if ($importExitCode -ne 0) {
    Write-Host "[ERROR] Import failed (exit $importExitCode). Stop here to avoid running with invalid stub/testcase state." -ForegroundColor Red
    exit $importExitCode
}
Write-Host "[INFO] Import done (exit $importExitCode)" -ForegroundColor DarkGray

# Execute tests and generate report using batch file from Step 1
Write-Host "`n[EXECUTE] Executing tests and generating report..." -ForegroundColor Yellow
$tbsDir = "$WorkingDir\tbs_files"
$batchFileHtml = "$tbsDir\generate_report_${TestObject}_html.tbs"

if (-not (Test-Path $batchFileHtml)) {
    Write-Host "[ERROR] Batch file not found (run Step 1 first): $batchFileHtml" -ForegroundColor Red
    exit 1
}

Write-Host "  Batch: $batchFileHtml" -ForegroundColor DarkGray
& $tessy -animate exec-test "$batchFileHtml"
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