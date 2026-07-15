# ============================================================================
# STEP 5: Build Annotated Conditions File from Interface Info
# ============================================================================
# Configuration is loaded by common.ps1.
# ============================================================================

. (Join-Path $PSScriptRoot "..\common.ps1")

$STEP       = "STEP5"
$TestObject = $Config.TestObjects
$Module     = $Config.Module
$SourceDir  = $Config.SourceDir
$WorkingDir = $Config.WorkDir

Show-Banner "STEP 5 : BUILD ANNOTATED CONDITIONS FILE"
Write-StepStart $STEP

Write-Info -Step $STEP -Message "Test Object: $TestObject"
Write-Info -Step $STEP -Message "Module: $Module"
Write-Info -Step $STEP -Message "Source Directory: $SourceDir"

$result = Export-AnnotatedConditionCode `
    -Step $STEP `
    -TestObject $TestObject `
    -Module $Module `
    -SourceDir $SourceDir `
    -WorkingDir $WorkingDir

Write-Info -Step $STEP -Message "Annotated condition file saved: $($result.OutputFile)"
Write-Info `
    -Step $STEP `
    -Message "Resolved Defines=$($result.DefineCount), Types=$($result.TypeCount), ConstVariables=$($result.ConstCount), Macros=$($result.MacroCount)"

Write-Host ""
Write-Host "Annotated condition content:" -ForegroundColor Cyan
Write-Host ("-" * 80) -ForegroundColor Gray
Get-Content $result.OutputFile | ForEach-Object { Write-Host $_ }
Write-Host ("-" * 80) -ForegroundColor Gray

Write-StepEnd $STEP

Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host "STEP 5 COMPLETE" -ForegroundColor Cyan
Write-Host "Next-> Run step6: list testcases" -ForegroundColor Cyan
Write-Host ("=" * 80) -ForegroundColor Cyan

exit 0
