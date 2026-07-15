# ============================================================================
# BATCH RUNNER
# Each index in the three arrays below belongs together:
#   $testObjects[i]  <->  $Module[i]  <->  $Folder[i]
# Add/remove rows in all three arrays at the same time.
# ============================================================================

$testObjects = @(
"tpsDrvFdtIrqHandler"
)

$Module = @(
    "tps929240_drv.c"
)

$Folder = @(
    "SmartLedDrv\TpsDrv_929240"
)

# ── Fixed parameters (same for every run) ────────────────────────────────────
$TessyProject   = "Chery_A_Variant"
$TestCollection = "Chery_A_Variant_ASW"
$ScriptRoot     = "C:\Data\Project\112_Code_Chery_A_Variant_Tessy\tessy"
$WorkDir        = "C:\Data\Project\206_TessyCheryAVariantWithCopilot\50_Tessy_Auto_10_Steps"
$SourceDir      = "C:\Data\Project\112_Code_Chery_A_Variant_Tessy\25_Impl\30_Source"

# ── Validate array lengths match ─────────────────────────────────────────────
# $Module and $Folder may each have either a single entry (used for all test objects)
# or exactly as many entries as $testObjects.
if (($Module.Count -ne 1 -and $Module.Count -ne $testObjects.Count) -or
    ($Folder.Count -ne 1 -and $Folder.Count -ne $testObjects.Count)) {
    Write-Host "ERROR: Module and Folder must each have 1 entry (shared) or match the number of testObjects!" -ForegroundColor Red
    Write-Host "  testObjects: $($testObjects.Count)  Module: $($Module.Count)  Folder: $($Folder.Count)" -ForegroundColor Red
    exit 1
}

$results = @()
$total   = $testObjects.Count
$idx     = 0

foreach ($i in 0..($total - 1)) {
    $idx++
    $testObject = $testObjects[$i]
    $mod        = if ($Module.Count -eq 1) { $Module[0] } else { $Module[$i] }
    $fld        = if ($Folder.Count -eq 1) { $Folder[0] } else { $Folder[$i] }

    Write-Host "`n================================================================================" -ForegroundColor Magenta
    Write-Host "  BATCH [$idx/$total]" -ForegroundColor Magenta
    Write-Host "  Folder     : $fld" -ForegroundColor Magenta
    Write-Host "  Module     : $mod" -ForegroundColor Magenta
    Write-Host "  TestObject : $testObject" -ForegroundColor Magenta
    Write-Host "================================================================================" -ForegroundColor Magenta

    & ".\coverage_10steps_orchestrator.ps1" `
        -TestObject     $testObject `
        -Module         $mod `
        -Folder         $fld `
        -TessyProject   $TessyProject `
        -TestCollection $TestCollection `
        -ScriptRoot     $ScriptRoot `
        -WorkDir        $WorkDir `
        -SourceDir      $SourceDir

    $exitCode = $LASTEXITCODE
    $status   = if ($exitCode -eq 0) { "SUCCESS" } else { "FAILED (exit $exitCode)" }
    $color    = if ($exitCode -eq 0) { "Green"   } else { "Red" }

    Write-Host "`n[$idx/$total] $testObject -> $status" -ForegroundColor $color

    $results += [PSCustomObject]@{
        Index      = $idx
        Folder     = $fld
        Module     = $mod
        TestObject = $testObject
        ExitCode   = $exitCode
        Status     = $status
    }
}

# ── Summary ──────────────────────────────────────────────────────────────────
Write-Host "`n`n================================================================================" -ForegroundColor Cyan
Write-Host "  BATCH COMPLETE - SUMMARY ($total test objects)" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

$lastFolder = ""; $lastModule = ""
foreach ($r in $results) {
    if ($r.Folder -ne $lastFolder) {
        Write-Host "`n  Folder: $($r.Folder)" -ForegroundColor Yellow
        $lastFolder = $r.Folder; $lastModule = ""
    }
    if ($r.Module -ne $lastModule) {
        Write-Host "    Module: $($r.Module)" -ForegroundColor DarkYellow
        $lastModule = $r.Module
    }
    $color = if ($r.ExitCode -eq 0) { "Green" } else { "Red" }
    Write-Host ("      [{0:D2}/{1:D2}] {2,-45} {3}" -f $r.Index, $total, $r.TestObject, $r.Status) -ForegroundColor $color
}

$passed = ($results | Where-Object { $_.ExitCode -eq 0 }).Count
$failed = ($results | Where-Object { $_.ExitCode -ne 0 }).Count
Write-Host "`n  Passed: $passed   Failed: $failed" -ForegroundColor White
Write-Host "================================================================================" -ForegroundColor Cyan