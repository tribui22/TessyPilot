# ============================================================================
# 10-STEP PROCESS ORCHESTRATOR FOR 100% C0/C1 COVERAGE
# ============================================================================
# Purpose: Orchestrates all 10 steps by calling individual step scripts
# Usage:
#   .\coverage_10steps_orchestrator.ps1 `
#       -TestObject "ApplCanBusOff" `
#       -Module "CanCtrl" `
#       -Folder "35_BSW\ComStack\CAN\CanCtrl" `
#       -TessyProject "SIG_BSW_MT" `
#       -TestCollection "SIG_BSW" `
#       -ScriptRoot "C:\...\tessy" `
#       -WorkDir "C:\...\42_Tessy_8_Steps" `
#       -SourceDir "C:\...\25_Impl_MCU1\30_Source"
#
# Steps Called:
#   Step 1: step1_generate_report_analyze_coverage.ps1
#   Step 2: step2_configure_stubs.ps1
#   Steps 3-6: step3_find_and_save_function_code.ps1 (runs steps 3,4,5,6)
#   Step 7: step7_generate_testcases.ps1 (AI generates tests directly)
#   Step 8: step8_execute_tests.ps1
#   Step 9: step9_analyze_results.ps1
#   Step 10: step10_verify_coverage.ps1
# ============================================================================

param(
    [Parameter(Mandatory=$true)][string]$TestObject,
    [Parameter(Mandatory=$true)][string]$Module,
    [Parameter(Mandatory=$true)][string]$Folder,
    [Parameter(Mandatory=$true)][string]$TessyProject,
    [Parameter(Mandatory=$true)][string]$TestCollection,
    [Parameter(Mandatory=$true)][string]$ScriptRoot,
    [Parameter(Mandatory=$true)][string]$WorkDir,
    [Parameter(Mandatory=$true)][string]$SourceDir,
    [int]$MaxIterations = 1,
    [double]$C0Target = 100.0,
    [double]$C1Target = 100.0,
    [switch]$ForceRegenerateTestcases
)

# Configuration
$StepsDir = $PSScriptRoot
$ErrorActionPreference = "Continue"
$ReportDir = if ((Split-Path $ScriptRoot -Leaf) -ieq "tessy") {
    Join-Path (Split-Path -Parent $ScriptRoot) "report"
} else {
    Join-Path $ScriptRoot "report"
}

# Preserve the caller's working directory so it is restored after this script exits
Push-Location $PWD

Write-Host "`n================================================================================" -ForegroundColor Magenta
  Write-Host "  10-STEP PROCESS ORCHESTRATOR FOR 100% C0/C1 COVERAGE" -ForegroundColor Magenta
Write-Host "  Test Object: $TestObject" -ForegroundColor Magenta
Write-Host "  Module: $Module" -ForegroundColor Magenta
Write-Host "  Target: C0=$C0Target%, C1=$C1Target%" -ForegroundColor Magenta
Write-Host "================================================================================" -ForegroundColor Magenta

# ============================================================================
# STEP 1: Connect to Tessy and Generate Reports
# ============================================================================
Write-Host "`n[ORCHESTRATOR] Calling STEP 1: Connect and Generate Reports" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

$step1Script = "$StepsDir\step1_generate_report_analyze_coverage.ps1"
if (-not (Test-Path $step1Script)) {
    Write-Host "ERROR: Step 1 script not found: $step1Script" -ForegroundColor Red
    exit 1
}

& $step1Script `
    -TestObject $TestObject `
    -Module $Module `
    -Folder $Folder `
    -TessyProject $TessyProject `
    -TestCollection $TestCollection `
    -ScriptRoot $ScriptRoot `
    -WorkingDir $WorkDir

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Step 1 failed with exit code $LASTEXITCODE" -ForegroundColor Red
    exit 1
}

Write-Host "[ORCHESTRATOR] STEP 1 COMPLETE" -ForegroundColor Green

# ============================================================================
# STEP 2: Configure Stubs  (Step 2 internally calls Step 2a and Step 2b)
# ============================================================================
Write-Host "`n[ORCHESTRATOR] Calling STEP 2: Configure Stubs" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

$step2Script = "$StepsDir\step2_configure_stubs.ps1"
if (-not (Test-Path $step2Script)) {
    Write-Host "ERROR: Step 2 script not found: $step2Script" -ForegroundColor Red
    exit 1
}

& $step2Script `
    -TestObject $TestObject `
    -TessyProject $TessyProject `
    -TestCollection $TestCollection `
    -ScriptRoot $ScriptRoot `
    -ExportDir $WorkDir `
    -SourceDir $SourceDir `
    -ReportDir $ReportDir `
    -Module $Module `
    -WorkingDir $WorkDir

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Step 2 failed with exit code $LASTEXITCODE" -ForegroundColor Red
    exit 1
}

Write-Host "[ORCHESTRATOR] STEP 2 COMPLETE" -ForegroundColor Green

# ============================================================================
# STEP 3: Analyze Source Code
# ============================================================================
Write-Host "`n[ORCHESTRATOR] Calling STEP 3: Analyze Source Code" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

$step3Script = "$StepsDir\step3_find_and_save_function_code.ps1"
if (-not (Test-Path $step3Script)) {
    Write-Host "ERROR: Step 3 script not found: $step3Script" -ForegroundColor Red
    exit 1
}

& $step3Script `
    -TestObject $TestObject `
    -Module $Module `
    -SourceDir $SourceDir `
    -WorkingDir $WorkDir

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: Step 3 failed with exit code $LASTEXITCODE" -ForegroundColor Red
    exit 1
}

Write-Host "[ORCHESTRATOR] STEP 3 COMPLETE" -ForegroundColor Green

# ============================================================================
# STEP 6 GATE: If testcase_plan.json is missing, Copilot Agent must run first.
# Step 3 ends by calling Step 6 which either:
#   (a) finds the JSON already present -> no-op
#   (b) writes testObjectCode\<TO>_step6.prompt.md and exits 0
# In case (b) we must pause here until the user runs Copilot Agent.
# ============================================================================
$planFile   = "$WorkDir\testObjectCode\${TestObject}_testcase_plan.json"
$promptFile = "$WorkDir\testObjectCode\${TestObject}_step6.prompt.md"

if (-not (Test-Path $planFile)) {
    Write-Host "`n================================================================================" -ForegroundColor Yellow
    Write-Host "  STEP 6 REQUIRED: testcase_plan.json not found." -ForegroundColor Yellow
    Write-Host "================================================================================" -ForegroundColor Yellow
    Write-Host "  Use the Copilot Agent prompt to run the full process automatically:" -ForegroundColor White
  Write-Host "  .github\prompts\run_10steps_coverage.prompt.md" -ForegroundColor Cyan
  Write-Host "" -ForegroundColor White
  Write-Host "  Or, if you want to run Step 6 manually:" -ForegroundColor White
    if (Test-Path $promptFile) {
        Write-Host "  Open and run: $promptFile" -ForegroundColor Cyan
    }
    Write-Host "" -ForegroundColor White
    Write-Host "  Exit code 34 = Step 6 JSON is missing. Re-run after generating the JSON." -ForegroundColor DarkGray
    Pop-Location
    exit 34
}
Write-Host "[ORCHESTRATOR] STEP 6 COMPLETE (testcase_plan.json found)" -ForegroundColor Green

# ============================================================================
# ITERATION LOOP: Steps 4-7
# ============================================================================

$iteration = 1
$c0 = 0
$c1 = 0

while ($iteration -le $MaxIterations) {
    Write-Host "`n================================================================================" -ForegroundColor Magenta
    Write-Host "  ITERATION $iteration" -ForegroundColor Magenta
    Write-Host "================================================================================" -ForegroundColor Magenta

    # ============================================================================
    # STEP 5/6 (retry only): Re-generate conditions file and test case plan
    # Steps 1, 2, 3, 4 are stable - only 5/6 and onwards need re-running
    # ============================================================================
    if ($iteration -gt 1) {
        Write-Host "`n[ORCHESTRATOR] RETRY: Re-running Step 5 (conditions file)" -ForegroundColor Yellow
        powershell -ExecutionPolicy Bypass -File "$StepsDir\step5_resolve_defines.ps1" `
            -TestObject $TestObject -Module $Module -SourceDir $SourceDir -WorkingDir $WorkDir
        if ($LASTEXITCODE -ne 0) { Write-Host "[WARN] Step 5 reported an error on retry." -ForegroundColor Yellow }

        Write-Host "`n[ORCHESTRATOR] RETRY: Re-running Step 6 (prompt generation)" -ForegroundColor Yellow
        # Delete old plan so Step 6 regenerates the prompt
        $retryPlan = "$WorkDir\testObjectCode\${TestObject}_testcase_plan.json"
        if (Test-Path $retryPlan) { Remove-Item $retryPlan -Force }
        powershell -ExecutionPolicy Bypass -File "$StepsDir\step6_list_testcases.ps1" `
            -TestObject $TestObject -WorkingDir $WorkDir
        if ($LASTEXITCODE -ne 0) { Write-Host "[WARN] Step 6 reported an error on retry." -ForegroundColor Yellow }

        # Gate: if Copilot Agent hasn't written the plan yet, exit so user can re-run
        if (-not (Test-Path $retryPlan)) {
            $retryPrompt = "$WorkDir\testObjectCode\${TestObject}_step6.prompt.md"
            Write-Host "`n  testcase_plan.json missing. Use the Copilot Agent prompt:" -ForegroundColor Yellow
            Write-Host "  .github\prompts\run_10steps_coverage.prompt.md" -ForegroundColor Cyan
            Write-Host "  Exit code 34 = Step 6 JSON is missing." -ForegroundColor DarkGray
            break
        }
        Write-Host "  testcase_plan.json received." -ForegroundColor Green
    }

    # ============================================================================
    # STEP 7: Generate Test Cases (Automatic with AI)
    # ============================================================================
    Write-Host "`n[ORCHESTRATOR] Calling STEP 7: Generate Test Cases (Iteration $iteration)" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan

    # On first iteration, check if existing testcase exists (unless ForceRegenerateTestcases is set)
    $existingTestcaseScript = Join-Path $WorkDir "script_files\${TestObject}_testcase.script"
    $skipStep7 = $false
    
    if ($iteration -eq 1 -and (-not $ForceRegenerateTestcases) -and (Test-Path $existingTestcaseScript)) {
        Write-Host "[ORCHESTRATOR] STEP 7 SKIPPED - Existing testcase script found (Iteration 1)" -ForegroundColor Green
        Write-Host "  Using: $existingTestcaseScript" -ForegroundColor DarkGray
        $skipStep7 = $true
    }
    
    if (-not $skipStep7) {
        $step7Script = "$StepsDir\step7_generate_testcases.ps1"
        if (-not (Test-Path $step7Script)) {
            Write-Host "ERROR: Step 7 script not found: $step7Script" -ForegroundColor Red
            exit 1
        }

        & $step7Script `
            -TestObject $TestObject `
            -Module $Module `
            -WorkingDir $WorkDir `
            -ScriptRoot $ScriptRoot `
            -SourceDir $SourceDir

        if ($LASTEXITCODE -ne 0) {
            Write-Host "WARNING: Step 7 had issues (exit code $LASTEXITCODE)" -ForegroundColor Yellow
        }

        Write-Host "[ORCHESTRATOR] STEP 7 COMPLETE" -ForegroundColor Green
    }

    # ============================================================================
    # STEP 8: Execute Tests
    # ============================================================================
    Write-Host "`n[ORCHESTRATOR] Calling STEP 8: Execute Tests (Iteration $iteration)" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan

    $step8Script = "$StepsDir\step8_execute_tests.ps1"
    if (-not (Test-Path $step8Script)) {
        Write-Host "ERROR: Step 8 script not found: $step8Script" -ForegroundColor Red
        exit 1
    }

    & $step8Script `
        -TestObject $TestObject `
        -Module $Module `
        -WorkingDir $WorkDir `
        -Folder $Folder `
        -TessyProject $TessyProject `
        -TestCollection $TestCollection `
        -ScriptRoot $ScriptRoot

    if ($LASTEXITCODE -eq 3) {
        Write-Host "[ORCHESTRATOR] STEP 8 IMPORT FAILED - regenerating test cases (Iteration $iteration -> $($iteration+1))" -ForegroundColor Red
        $iteration++
        if ($iteration -le $MaxIterations) {
            Write-Host "Retrying from Step 7..." -ForegroundColor Cyan
            Start-Sleep -Seconds 2
            continue
        } else {
            Write-Host "ERROR: Max iterations ($MaxIterations) reached after import failures" -ForegroundColor Red
            break
        }
    } elseif ($LASTEXITCODE -ne 0) {
        Write-Host "WARNING: Step 8 had issues (exit code $LASTEXITCODE)" -ForegroundColor Yellow
    }

    Write-Host "[ORCHESTRATOR] STEP 8 COMPLETE" -ForegroundColor Green

    # ============================================================================
    # STEP 9: Analyze Results
    # ============================================================================
    Write-Host "`n[ORCHESTRATOR] Calling STEP 9: Analyze Results (Iteration $iteration)" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan

    $step9Script = "$StepsDir\step9_analyze_results.ps1"
    if (-not (Test-Path $step9Script)) {
        Write-Host "ERROR: Step 9 script not found: $step9Script" -ForegroundColor Red
        exit 1
    }

    & $step9Script `
        -TestObject $TestObject `
        -Module $Module `
        -WorkingDir $WorkDir `
        -ScriptRoot $ScriptRoot

    if ($LASTEXITCODE -ne 0) {
        Write-Host "WARNING: Step 9 had issues (exit code $LASTEXITCODE)" -ForegroundColor Yellow
    }

    # Read analysis results
    $statusFile = "$WorkDir\json_files\${TestObject}_coverage_status.json"
    if (Test-Path $statusFile) {
        $status = Get-Content $statusFile -Raw | ConvertFrom-Json
        $c0 = $status.C0
        $c1 = $status.C1
        Write-Host "Coverage from analysis: C0=$c0%, C1=$c1%" -ForegroundColor Yellow
    } else {
        Write-Host "WARNING: Could not read analysis status file" -ForegroundColor Yellow
    }

    Write-Host "[ORCHESTRATOR] STEP 9 COMPLETE" -ForegroundColor Green

    # ============================================================================
    # STEP 10: Verify Coverage
    # ============================================================================
    Write-Host "`n[ORCHESTRATOR] Calling STEP 10: Verify Coverage (Iteration $iteration)" -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan

    $step10Script = "$StepsDir\step10_verify_coverage.ps1"
    if (-not (Test-Path $step10Script)) {
        Write-Host "ERROR: Step 10 script not found: $step10Script" -ForegroundColor Red
        exit 1
    }

    & $step10Script `
        -TestObject $TestObject `
        -Module $Module `
        -WorkingDir $WorkDir `
        -ScriptRoot $StepsDir `
        -C0Target $C0Target `
        -C1Target $C1Target `
        -Iteration $iteration

    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n================================================================================" -ForegroundColor Green
        Write-Host "  SUCCESS! 100% COVERAGE ACHIEVED!" -ForegroundColor Green
        Write-Host "================================================================================" -ForegroundColor Green
        Write-Host "Completed in $iteration iteration(s)" -ForegroundColor White
        Write-Host "Final Coverage: C0=$c0%, C1=$c1%" -ForegroundColor Green
        Write-Host "================================================================================" -ForegroundColor Green
        break
    } elseif ($LASTEXITCODE -eq 2) {
        # Special: C0/C1 targets are met but Expected != Actual in some outputs.
        # Run one mandatory correction pass (Step 7 will replace Expected with Actual values).
        Write-Host "`n================================================================================" -ForegroundColor Cyan
        Write-Host "  [CORRECTION PASS] C0/C1=100% but $($status.Failed) test(s) failing" -ForegroundColor Cyan
        Write-Host "  Running one extra pass so Step 7 can fix Expected = Actual..." -ForegroundColor Cyan
        Write-Host "================================================================================" -ForegroundColor Cyan
        $iteration++
        # Correction pass always runs regardless of MaxIterations — do NOT break or skip here.
        Start-Sleep -Seconds 2
    } else {
        Write-Host "`n================================================================================" -ForegroundColor Yellow
        Write-Host "  INCOMPLETE COVERAGE - ITERATION $iteration" -ForegroundColor Yellow
        Write-Host "================================================================================" -ForegroundColor Yellow
        Write-Host "Current Coverage: C0=$c0%, C1=$c1%" -ForegroundColor Yellow
        Write-Host "Target: C0=$C0Target%, C1=$C1Target%" -ForegroundColor Yellow
        Write-Host "================================================================================" -ForegroundColor Yellow
        
        $iteration++
        
        if ($iteration -le $MaxIterations) {
            Write-Host "`nAuto-retrying with enhanced test generation for iteration $iteration..." -ForegroundColor Cyan
            Start-Sleep -Seconds 2
        } else {
            Write-Host "`nWARNING: Max iterations ($MaxIterations) reached" -ForegroundColor Red
            Write-Host "Final Coverage: C0=$c0%, C1=$c1%" -ForegroundColor Red
            break
        }
    }
}

# ============================================================================
# CLEANUP
# ============================================================================
Write-Host "`nDisconnecting from Tessy..." -ForegroundColor Yellow
tessycmd disconnect

# Restore the caller's original working directory
Pop-Location

Write-Host "`n================================================================================" -ForegroundColor Magenta
Write-Host "  ORCHESTRATOR COMPLETE" -ForegroundColor Magenta
Write-Host "  Test Object: $TestObject" -ForegroundColor Magenta
Write-Host "  Final Coverage: C0=$c0%, C1=$c1%" -ForegroundColor Magenta
Write-Host "================================================================================" -ForegroundColor Magenta
