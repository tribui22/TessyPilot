# ============================================================================
# STEP 3: Find Function in Source and Save to testObjectCode/
# ============================================================================
# Purpose:
#   - Locate the function under test in the configured source directory.
#   - Search the configured module first, then all other C source files.
#   - Save the complete unmodified function text to:
#       <WorkDir>\testObjectCode\<TestObject>.c
#
# Configuration is loaded by common.ps1.
# ============================================================================

. (Join-Path $PSScriptRoot "..\common.ps1")

$STEP       = "STEP3"
$TestObject = $Config.TestObjects
$Module     = $Config.Module
$SourceDir  = $Config.SourceDir
$WorkingDir = $Config.WorkDir

Show-Banner "STEP 3 : FIND FUNCTION AND SAVE FULL FUNCTION CODE"
Write-StepStart $STEP

Write-Info -Step $STEP -Message "Test Object: $TestObject"
Write-Info -Step $STEP -Message "Module: $Module"
Write-Info -Step $STEP -Message "Source Directory: $SourceDir"

$result = Export-TestObjectFunctionCode `
    -Step $STEP `
    -TestObject $TestObject `
    -Module $Module `
    -SourceDir $SourceDir `
    -WorkingDir $WorkingDir

Write-Info -Step $STEP -Message "Function source: $($result.SourceFile)"
Write-Info -Step $STEP -Message "Function code saved: $($result.OutputFile)"
Write-Info `
    -Step $STEP `
    -Message "Return type: $($result.ReturnType); Parameters: $($result.Parameters)"

Write-StepEnd $STEP

Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host "STEP 3 COMPLETE" -ForegroundColor Cyan
Write-Host "Next-> Run step4: strip conditions" -ForegroundColor Cyan
Write-Host ("=" * 80) -ForegroundColor Cyan

exit 0
