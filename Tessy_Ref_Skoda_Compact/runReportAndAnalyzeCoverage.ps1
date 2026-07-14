# ============================================================================
# BATCH RUNNER - STEPS 1 + 9  (connect + generate report, then analyze results)
#
# Use this script to check existing coverage before running the full pipeline.
# Writes coverage status to:
#   json_files\<TestObject>_coverage_status.json
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
    [string]$WorkDir
)

# ── Validate array lengths ────────────────────────────────────────────────────
if (($Module.Count -ne 1 -and $Module.Count -ne $testObjects.Count) -or
    ($Folder.Count -ne 1 -and $Folder.Count -ne $testObjects.Count)) {
    Write-Host "ERROR: Module/Folder count mismatch!" -ForegroundColor Red
    exit 1
}

$StepsDir = $PSScriptRoot
$ErrorActionPreference = "Continue"
$results = @()
$total   = $testObjects.Count

foreach ($i in 0..($total - 1)) {
    $testObject = $testObjects[$i]
    $mod        = if ($Module.Count -eq 1) { $Module[0] } else { $Module[$i] }
    $fld        = if ($Folder.Count -eq 1) { $Folder[0] } else { $Folder[$i] }

    Write-Host "`n================================================================================" -ForegroundColor Magenta
    Write-Host "  BATCH [$($i+1)/$total] - STEPS 1 + 9" -ForegroundColor Magenta
    Write-Host "  TestObject : $testObject  |  Module : $mod" -ForegroundColor Magenta
    Write-Host "================================================================================" -ForegroundColor Magenta

    $exitCode = 0

    # ── STEP 1 ────────────────────────────────────────────────────────────────
    Write-Host "`n[STEPS1+9] STEP 1: Connect and Generate Reports" -ForegroundColor Cyan
    $s1 = "$StepsDir\step1_generate_report_analyze_coverage.ps1"
    if (-not (Test-Path $s1)) { Write-Host "ERROR: $s1 not found" -ForegroundColor Red; $exitCode = 1 }
    else {
        & $s1 -TestObject $testObject -Module $mod -Folder $fld `
              -TessyProject $TessyProject -TestCollection $TestCollection `
              -ScriptRoot $ScriptRoot -WorkingDir $WorkDir
        if ($LASTEXITCODE -ne 0) {
            Write-Host "ERROR: Step 1 failed (exit $LASTEXITCODE)" -ForegroundColor Red
            $exitCode = $LASTEXITCODE
        } else { Write-Host "[STEPS1+9] STEP 1 COMPLETE" -ForegroundColor Green }
    }
    if ($exitCode -ne 0) { $results += [PSCustomObject]@{ Index=$i+1; TestObject=$testObject; Status="FAILED step1" }; continue }

    # ── STEP 9 ────────────────────────────────────────────────────────────────
    Write-Host "`n[STEPS1+9] STEP 9: Analyze Results" -ForegroundColor Cyan
    $s9 = "$StepsDir\step9_analyze_results.ps1"
    if (-not (Test-Path $s9)) { Write-Host "ERROR: $s9 not found" -ForegroundColor Red; $exitCode = 1 }
    else {
        & $s9 -TestObject $testObject -Module $mod `
              -WorkingDir $WorkDir -ScriptRoot $ScriptRoot
        if ($LASTEXITCODE -ne 0) {
            Write-Host "ERROR: Step 9 failed (exit $LASTEXITCODE)" -ForegroundColor Red
            $exitCode = $LASTEXITCODE
        } else { Write-Host "[STEPS1+9] STEP 9 COMPLETE" -ForegroundColor Green }
    }

    # ── Read coverage status ──────────────────────────────────────────────────
    $statusFile = "$WorkDir\json_files\${testObject}_coverage_status.json"
    if (Test-Path $statusFile) {
        $status = Get-Content $statusFile -Raw | ConvertFrom-Json
        $c0 = $status.C0
        $c1 = $status.C1
        Write-Host ""
        Write-Host "  Coverage: C0=$c0% C1=$c1%" -ForegroundColor $(if ($c0 -ge 100 -and $c1 -ge 100) { "Green" } else { "Yellow" })
        $results += [PSCustomObject]@{ Index=$i+1; TestObject=$testObject; Status="C0=$c0% C1=$c1%"; ExitCode=$exitCode }
    } else {
        Write-Host "  WARNING: Coverage status file not found." -ForegroundColor Red
        $results += [PSCustomObject]@{ Index=$i+1; TestObject=$testObject; Status="NO STATUS FILE"; ExitCode=$exitCode }
    }
}

# ── Summary ───────────────────────────────────────────────────────────────────
Write-Host "`n`n================================================================================" -ForegroundColor Cyan
Write-Host "  BATCH COMPLETE (STEPS 1+9) - SUMMARY" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan
foreach ($r in $results) {
    $color = if ($r.Status -match 'FAILED') { "Red" } elseif ($r.Status -match 'C0=100') { "Green" } else { "Yellow" }
    Write-Host ("  [{0:D2}/{1:D2}] {2,-45} {3}" -f $r.Index, $total, $r.TestObject, $r.Status) -ForegroundColor $color
}
Write-Host "================================================================================" -ForegroundColor Cyan
