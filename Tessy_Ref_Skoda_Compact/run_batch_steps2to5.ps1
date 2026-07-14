# ============================================================================
# BATCH RUNNER - STEPS 2, 3, 4, 5  (through Step 6 prompt generation)
#
# Step 1 (connect + generate report) is handled separately by
#   runReportAndAnalyzeCoverage.ps1
#
# After this script finishes:
#   1. Open the generated prompt file in VS Code:
#      testObjectCode\<TestObject>_step6.prompt.md
#   2. Run it with Copilot Agent (Ctrl+Enter) to create testcase_plan.json
#   3. Then run run_batch_steps7to10.ps1 with explicit parameters to continue.
#
# Each index in the three arrays below belongs together:
#   $testObjects[i]  <->  $Module[i]  <->  $Folder[i]
# ============================================================================

param(
    [Parameter(Mandatory=$true)]
    [string[]]$testObjects,

    [Parameter(Mandatory=$true)]
    [string[]]$Module,

    [Parameter(Mandatory=$true)]
    [string[]]$Folder,

    [Parameter(Mandatory=$true)]
    [string]$TessyProject,

    [Parameter(Mandatory=$true)]
    [string]$TestCollection,

    [Parameter(Mandatory=$true)]
    [string]$ScriptRoot,

    [Parameter(Mandatory=$true)]
    [string]$WorkDir,

    [Parameter(Mandatory=$true)]
    [string]$SourceDir
)

# ── Validate array lengths ────────────────────────────────────────────────────
if (($Module.Count -ne 1 -and $Module.Count -ne $testObjects.Count) -or
    ($Folder.Count -ne 1 -and $Folder.Count -ne $testObjects.Count)) {
    Write-Host "ERROR: Module/Folder count mismatch!" -ForegroundColor Red
    exit 1
}

$StepsDir = $PSScriptRoot
$ErrorActionPreference = "Continue"
$ReportDir = if ((Split-Path $ScriptRoot -Leaf) -ieq "tessy") {
    Join-Path (Split-Path -Parent $ScriptRoot) "report"
} else {
    Join-Path $ScriptRoot "report"
}
$results = @()
$total   = $testObjects.Count

foreach ($i in 0..($total - 1)) {
    $testObject = $testObjects[$i]
    $mod        = if ($Module.Count -eq 1) { $Module[0] } else { $Module[$i] }
    $fld        = if ($Folder.Count -eq 1) { $Folder[0] } else { $Folder[$i] }

    Write-Host "`n================================================================================" -ForegroundColor Magenta
    Write-Host "  BATCH [$($i+1)/$total] - STEPS 2, 3, 4, 5" -ForegroundColor Magenta
    Write-Host "  TestObject : $testObject  |  Module : $mod" -ForegroundColor Magenta
    Write-Host "================================================================================" -ForegroundColor Magenta

    $exitCode = 0

    # ── STEP 2 ────────────────────────────────────────────────────────────────
    Write-Host "`n[STEPS2-5] STEP 2: Configure Stubs" -ForegroundColor Cyan
    $s2 = "$StepsDir\step2_configure_stubs.ps1"
    if (-not (Test-Path $s2)) { Write-Host "ERROR: $s2 not found" -ForegroundColor Red; $exitCode = 1 }
    else {
        & $s2 -TestObject $testObject -TessyProject $TessyProject `
              -TestCollection $TestCollection -ScriptRoot $ScriptRoot `
              -ExportDir $WorkDir -SourceDir $SourceDir `
              -ReportDir $ReportDir `
              -Module $mod -WorkingDir $WorkDir
        if ($LASTEXITCODE -ne 0) {
            Write-Host "ERROR: Step 2 failed (exit $LASTEXITCODE)" -ForegroundColor Red
            $exitCode = $LASTEXITCODE
        } else { Write-Host "[STEPS2-5] STEP 2 COMPLETE" -ForegroundColor Green }
    }
    if ($exitCode -ne 0) { $results += [PSCustomObject]@{ Index=$i+1; TestObject=$testObject; Status="FAILED step2" }; continue }

    # ── STEP 3: Find and save function code ──────────────────────────────
    Write-Host "`n[STEPS2-5] STEP 3: Find and Save Function Code" -ForegroundColor Cyan
    $s3 = "$StepsDir\step3_find_and_save_function_code.ps1"
    if (-not (Test-Path $s3)) { Write-Host "ERROR: $s3 not found" -ForegroundColor Red; $exitCode = 1 }
    else {
        & $s3 -TestObject $testObject -Module $mod `
              -SourceDir $SourceDir -WorkingDir $WorkDir
        if ($LASTEXITCODE -ne 0) {
            Write-Host "WARNING: Step 3 reported issues (exit $LASTEXITCODE)" -ForegroundColor Yellow
        } else { Write-Host "[STEPS2-5] STEP 3 COMPLETE" -ForegroundColor Green }
    }

    # ── STEP 4: Strip conditions ──────────────────────────────────────────
    Write-Host "`n[STEPS2-5] STEP 4: Strip Conditions" -ForegroundColor Cyan
    $s4 = "$StepsDir\step4_strip_conditions.ps1"
    if (-not (Test-Path $s4)) { Write-Host "ERROR: $s4 not found" -ForegroundColor Red; $exitCode = 1 }
    else {
        & $s4 -TestObject $testObject -Module $mod `
              -SourceDir $SourceDir -WorkingDir $WorkDir
        if ($LASTEXITCODE -ne 0) {
            Write-Host "WARNING: Step 4 reported issues (exit $LASTEXITCODE)" -ForegroundColor Yellow
        } else { Write-Host "[STEPS2-5] STEP 4 COMPLETE" -ForegroundColor Green }
    }

    # ── STEP 5: Resolve #define constants ────────────────────────────────
    Write-Host "`n[STEPS2-5] STEP 5: Resolve #define Constants" -ForegroundColor Cyan
    $s5 = "$StepsDir\step5_resolve_defines.ps1"
    if (-not (Test-Path $s5)) { Write-Host "ERROR: $s5 not found" -ForegroundColor Red; $exitCode = 1 }
    else {
        & $s5 -TestObject $testObject -Module $mod `
              -SourceDir $SourceDir -WorkingDir $WorkDir
        if ($LASTEXITCODE -ne 0) {
            Write-Host "WARNING: Step 5 reported issues (exit $LASTEXITCODE)" -ForegroundColor Yellow
        } else { Write-Host "[STEPS2-5] STEP 5 COMPLETE" -ForegroundColor Green }
    }

    # ── STEP 6: Generate test case plan (Copilot Agent prompt) ────────────
    Write-Host "`n[STEPS2-5] STEP 6: Generate Test Case Plan" -ForegroundColor Cyan
    $s6 = "$StepsDir\step6_list_testcases.ps1"
    if (-not (Test-Path $s6)) { Write-Host "ERROR: $s6 not found" -ForegroundColor Red; $exitCode = 1 }
    else {
        & $s6 -TestObject $testObject -WorkingDir $WorkDir
        if ($LASTEXITCODE -ne 0) {
            Write-Host "WARNING: Step 6 reported issues (exit $LASTEXITCODE)" -ForegroundColor Yellow
        } else { Write-Host "[STEPS2-5] STEP 6 COMPLETE" -ForegroundColor Green }
    }

    # ── Check what Step 6 produced ──────────────────────────────────────────
    $promptFile = "$WorkDir\testObjectCode\${testObject}_step6.prompt.md"
    $planFile   = "$WorkDir\json_testcase\${testObject}_testcase_plan.json"

    if (Test-Path $planFile) {
        $plan = Get-Content $planFile -Raw | ConvertFrom-Json
        Write-Host ""
        Write-Host "  testcase_plan.json already exists ($($plan.TotalTestCases) TCs)." -ForegroundColor Green
        Write-Host "  -> Run run_batch_steps7to10.ps1 with explicit parameters." -ForegroundColor Green
        $results += [PSCustomObject]@{ Index=$i+1; TestObject=$testObject; Status="READY (plan exists)" }
    } elseif (Test-Path $promptFile) {
        Write-Host ""
        Write-Host "  Step 6 generated a Copilot Agent prompt:" -ForegroundColor Yellow
        Write-Host "  $promptFile" -ForegroundColor White
        Write-Host ""
        Write-Host "  NEXT ACTION:" -ForegroundColor Cyan
        Write-Host "    1. Open the file above in VS Code" -ForegroundColor White
        Write-Host "    2. Run with Copilot Agent (Ctrl+Enter)" -ForegroundColor White
        Write-Host "    3. Copilot will write $planFile" -ForegroundColor White
        Write-Host "    4. Then run run_batch_steps7to10.ps1 with explicit parameters" -ForegroundColor White
        $results += [PSCustomObject]@{ Index=$i+1; TestObject=$testObject; Status="WAITING for Copilot Agent" }
    } else {
        Write-Host "  WARNING: Neither prompt file nor plan JSON found." -ForegroundColor Red
        $results += [PSCustomObject]@{ Index=$i+1; TestObject=$testObject; Status="FAILED - no plan or prompt" }
    }
}

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host "`n`n================================================================================" -ForegroundColor Cyan
Write-Host "  BATCH COMPLETE (STEPS 2-5) - SUMMARY" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan
foreach ($r in $results) {
    $color = if ($r.Status -match 'FAILED') { "Red" } elseif ($r.Status -match 'READY') { "Green" } else { "Yellow" }
    Write-Host ("  [{0:D2}/{1:D2}] {2,-45} {3}" -f $r.Index, $total, $r.TestObject, $r.Status) -ForegroundColor $color
}
Write-Host ""
Write-Host "After Copilot Agent writes all testcase_plan.json files, run run_batch_steps7to10.ps1 with explicit parameters." -ForegroundColor Cyan
Write-Host "Note: Step 1 is handled separately by runReportAndAnalyzeCoverage.ps1" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan
