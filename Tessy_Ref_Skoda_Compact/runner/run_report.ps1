# ============================================================================
# run_report.ps1 - Optional coverage-report add-on
# ============================================================================
# Layout:
#   <project>\runner\run_report.ps1
#   <project>\helpers\config.ps1, logger.ps1
#   <project>\steps\step01.ps1, step09.ps1
#
# No command-line parameters are required.
# ============================================================================

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

# This add-on only needs config.ps1. Step 01 and Step 09 load common.ps1 in
# their own child processes, so common.ps1 must not be dot-sourced here.
$reportRunnerRoot  = [System.IO.Path]::GetFullPath($PSScriptRoot)
$reportProjectRoot = [System.IO.Path]::GetFullPath(
    (Join-Path $reportRunnerRoot '..')
)

$reportConfigFile = [System.IO.Path]::GetFullPath(
    (Join-Path $reportProjectRoot 'helpers\config.ps1')
)
$reportLoggerFile = [System.IO.Path]::GetFullPath(
    (Join-Path $reportProjectRoot 'helpers\logger.ps1')
)
$reportStepFile = [System.IO.Path]::GetFullPath(
    (Join-Path $reportProjectRoot 'steps\step01.ps1')
)
$analysisStepFile = [System.IO.Path]::GetFullPath(
    (Join-Path $reportProjectRoot 'steps\step09.ps1')
)

$requiredReportFiles = @(
    $reportConfigFile,
    $reportLoggerFile,
    $reportStepFile,
    $analysisStepFile
)

foreach ($requiredFile in $requiredReportFiles) {
    if (-not (Test-Path -LiteralPath $requiredFile)) {
        throw "Required report file not found: $requiredFile"
    }
}

Write-Host "[PATH] Project: $reportProjectRoot" -ForegroundColor DarkGray
Write-Host "[PATH] Config:  $reportConfigFile" -ForegroundColor DarkGray
Write-Host "[PATH] Report:  $reportStepFile" -ForegroundColor DarkGray
Write-Host "[PATH] Analyze: $analysisStepFile" -ForegroundColor DarkGray

. $reportConfigFile
. $reportLoggerFile

$testObject     = [string]$Config.TestObjects
$module         = [string]$Config.Module
$folder         = if ($null -eq $Config.Folder) { '' } else { [string]$Config.Folder }
$tessyProject   = [string]$Config.TessyProject
$testCollection = [string]$Config.TestCollection
$scriptRoot     = [string]$Config.ScriptRoot
$workingDir     = [string]$Config.WorkDir
$statusFile     = Join-Path $workingDir "json_files\${testObject}_coverage_status.json"

$powerShell = if (Get-Command 'pwsh.exe' -ErrorAction SilentlyContinue) {
    'pwsh.exe'
} elseif (Get-Command 'powershell.exe' -ErrorAction SilentlyContinue) {
    'powershell.exe'
} else {
    throw 'Neither pwsh.exe nor powershell.exe was found.'
}

Write-Host "`n$('=' * 80)" -ForegroundColor Magenta
Write-Host ' OPTIONAL ADD-ON : GENERATE AND ANALYZE COVERAGE REPORT' -ForegroundColor Magenta
Write-Host " Test Object: $testObject" -ForegroundColor Magenta
Write-Host " Module: $module" -ForegroundColor Magenta
Write-Host ('=' * 80) -ForegroundColor Magenta

try {
    Write-Host "`n[REPORT] Generating Tessy report..." -ForegroundColor Cyan
    & $powerShell `
        -NoLogo `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $reportStepFile

    if ($LASTEXITCODE -ne 0) {
        throw "Report generation failed with exit code $LASTEXITCODE."
    }

    Write-Host "`n[ANALYZE] Running Step 09 report analysis..." -ForegroundColor Cyan
    & $powerShell `
        -NoLogo `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $analysisStepFile

    if ($LASTEXITCODE -ne 0) {
        throw "Step 09 analysis failed with exit code $LASTEXITCODE."
    }

    if (-not (Test-Path -LiteralPath $statusFile)) {
        throw "Coverage status was not created: $statusFile"
    }

    $status = Get-Content $statusFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $color = if (
        [double]$status.C0 -ge 100 -and
        [double]$status.C1 -ge 100 -and
        [int]$status.Failed -eq 0
    ) {
        'Green'
    } else {
        'Yellow'
    }

    Write-Host "`nCoverage: C0=$($status.C0)% C1=$($status.C1)%" -ForegroundColor $color
    Write-Host "Tests: Total=$($status.Total) Passed=$($status.Passed) Failed=$($status.Failed)" -ForegroundColor $color
    Write-Host "Status: $statusFile" -ForegroundColor DarkGray
    Write-Host '[OK] Optional report add-on completed.' -ForegroundColor Green
    exit 0
}
catch {
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}
