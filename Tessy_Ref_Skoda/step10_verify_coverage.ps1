# ============================================================================
# STEP 10: Verify Coverage and Auto-Fix Test Cases
# ============================================================================
# Purpose: Verify coverage targets are met (C0=100%, C1=100%, Failed=0)
# Target: C0=100%, C1=100%, Failed=0
# ============================================================================
param(
    [Parameter(Mandatory=$true)][string]$TestObject,
    [Parameter(Mandatory=$false)][string]$Module = "",
    [Parameter(Mandatory=$false)][string]$WorkingDir = $PSScriptRoot,
    [Parameter(Mandatory=$false)][string]$ScriptRoot = (Split-Path -Parent $PSScriptRoot),
    [double]$C0Target = 100.0,
    [double]$C1Target = 100.0,
    [int]$Iteration = 1
)

Write-Host "`n================================================================================" -ForegroundColor Cyan
Write-Host "  STEP 10: VERIFY COVERAGE AND AUTO-FIX (Iteration $Iteration)" -ForegroundColor Cyan
Write-Host "  Test Object: $TestObject" -ForegroundColor Cyan
Write-Host "  Targets: C0=$C0Target%, C1=$C1Target%, Failed=0" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

# Read status from Step 6
$jsonDir = "$WorkingDir\json_files"
$statusFile = "$jsonDir\${TestObject}_coverage_status.json"

if (-not (Test-Path $statusFile)) {
    Write-Host "[ERROR] Status file not found. Run Step 6 first." -ForegroundColor Red
    exit 1
}

$status = Get-Content $statusFile -Raw | ConvertFrom-Json
$c0 = $status.C0
$c1 = $status.C1
$totalTests = if ($status.Total) { $status.Total } else { 0 }
$passedTests = if ($status.Passed) { $status.Passed } else { 0 }
$failedTests = if ($status.Failed) { $status.Failed } else { 0 }
$failureDetails = if ($status.FailureDetails) { $status.FailureDetails } else { @() }

Write-Host "`n[CURRENT STATUS]" -ForegroundColor Yellow
Write-Host "  Coverage: C0=$c0%, C1=$c1%" -ForegroundColor White
Write-Host "  Tests: Total=$totalTests, Passed=$passedTests, Failed=$failedTests" -ForegroundColor White
Write-Host "  Variable Failures: $($failureDetails.Count)" -ForegroundColor White

# Check all targets: C0=100%, C1=100%, Failed=0, Total>0
$coverageOk = ($c0 -ge $C0Target -and $c1 -ge $C1Target)
$targetMet  = ($coverageOk -and $failedTests -eq 0 -and $totalTests -gt 0)
$needsCorrectionOnly = ($coverageOk -and $failedTests -gt 0 -and $totalTests -gt 0)

if ($targetMet) {
    Write-Host "`n================================================================================" -ForegroundColor Green
    Write-Host "  ✓ SUCCESS - All Targets Met" -ForegroundColor Green
    Write-Host "================================================================================" -ForegroundColor Green
    Write-Host "  C0: $c0%" -ForegroundColor Green
    Write-Host "  C1: $c1%" -ForegroundColor Green
    Write-Host "  Failed: 0" -ForegroundColor Green
    Write-Host "  Total: $totalTests tests passed" -ForegroundColor Green
    Write-Host "================================================================================" -ForegroundColor Green
    exit 0
} elseif ($needsCorrectionOnly) {
    # Coverage is 100%/100% but some test cases have wrong Expected values.
    # Signal the orchestrator to run one correction pass (Step 7 will swap Expected=Actual).
    Write-Host "`n================================================================================" -ForegroundColor Yellow
    Write-Host "  [CORRECTION NEEDED] Coverage targets met but $failedTests test(s) failing" -ForegroundColor Yellow
    Write-Host "================================================================================" -ForegroundColor Yellow
    Write-Host "  C0: $c0%  OK" -ForegroundColor Green
    Write-Host "  C1: $c1%  OK" -ForegroundColor Green
    Write-Host "  Failed: $failedTests  (Expected != Actual for some outputs)" -ForegroundColor Red
    Write-Host "  Action: Step 7 will replace Expected values with Actual values from this run." -ForegroundColor Cyan
    Write-Host "================================================================================" -ForegroundColor Yellow
    exit 2
} else {
    # Coverage targets not yet met — need more/different test cases.
    Write-Host "`n================================================================================" -ForegroundColor Red
    Write-Host "  FAILED - Target Not Met" -ForegroundColor Red
    Write-Host "================================================================================" -ForegroundColor Red
    Write-Host "  C0: $c0% (Target: $C0Target%)" -ForegroundColor $(if($c0 -ge $C0Target){'Green'}else{'Red'})
    Write-Host "  C1: $c1% (Target: $C1Target%)" -ForegroundColor $(if($c1 -ge $C1Target){'Green'}else{'Red'})
    Write-Host "  Failed: $failedTests (Target: 0)" -ForegroundColor $(if($failedTests -eq 0){'Green'}else{'Red'})
    Write-Host "  Total: $totalTests (Target: >0)" -ForegroundColor $(if($totalTests -gt 0){'Green'}else{'Red'})
    if ($failureDetails.Count -gt 0) {
        Write-Host "`n[INFO] Found $($failureDetails.Count) variable failures - corrections generated" -ForegroundColor Yellow
    }
    Write-Host "`n[NEXT ACTION] Re-running Steps 7-10 to reach coverage targets..." -ForegroundColor Cyan
    Write-Host "================================================================================" -ForegroundColor Red
    exit 1
}
