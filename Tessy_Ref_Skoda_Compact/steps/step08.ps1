# ============================================================================
# STEP 08 - Import and Execute Tessy Tests
# ============================================================================
# Pipeline entry point. No command-line input is required.
# All values are loaded from config.ps1 through common.ps1.
# ============================================================================

[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot "..\common.ps1")

$STEP           = 'STEP8'
$TestObject     = $Config.TestObjects
$Module         = $Config.Module
$WorkingDir     = $Config.WorkDir
$ScriptRoot     = $Config.ScriptRoot
$Folder         = if ($null -eq $Config.Folder) { '' } else { [string]$Config.Folder }
$TessyProject   = $Config.TessyProject
$TestCollection = $Config.TestCollection

$TessyCmd   = Join-Path $ScriptRoot 'tessycmd.exe'
$TestScript = Join-Path $WorkingDir "script_files\${TestObject}_testcase.script"
$ImportYaml = Join-Path $WorkingDir "yml\${TestObject}_import.yml"
$BatchFile  = Join-Path $WorkingDir "tbs_files\generate_report_${TestObject}_html.tbs"
$YmlBuilder = Join-Path $PSScriptRoot 'generate_tessy_import_yml.ps1'

$StubNames = @(
    'ucDrv_CfgSetFCCFreqOfMCLK',
    'ucDrv_ConfigureFCC',
    'ucDrv_FCCDone',
    'ucDrv_LockRegister',
    'ucDrv_ReadFCC',
    'ucDrv_SetFCCPeriod',
    'ucDrv_StartFCC',
    'ucDrv_UnlockRegister'
)

Show-Banner 'STEP 8 : EXECUTE TESSY TESTS'
Write-StepStart $STEP
Write-Info -Step $STEP -Message "Test Object: $TestObject"
Write-Info -Step $STEP -Message "Module: $Module"
Write-Info -Step $STEP -Message "Project: $TessyProject"
Write-Info -Step $STEP -Message "Test Collection: $TestCollection"

$previousLocation = Get-Location
$exitCode = 1

try {
    Assert-RequiredFiles @($TessyCmd, $TestScript, $BatchFile)
    Set-Location $ScriptRoot

    Write-Info -Step $STEP -Message 'Selecting Tessy context.'
    Select-TessyContext `
        -Executable $TessyCmd `
        -Project $TessyProject `
        -TestCollection $TestCollection `
        -Folder $Folder `
        -Module $Module `
        -TestObject $TestObject
    Write-Info -Step $STEP -Message 'Tessy context selected.'

    if (-not (Test-Path $ImportYaml)) {
        Assert-RequiredFiles @($YmlBuilder)
        Write-Info -Step $STEP -Message 'Generating Tessy import YAML.'

        & $YmlBuilder `
            -TestObject $TestObject `
            -Module $Module `
            -WorkDir $WorkingDir `
            -ScriptRoot $ScriptRoot `
            -StubNames $StubNames `
            -TessyProject $TessyProject

        if ($LASTEXITCODE -ne 0 -or -not (Test-Path $ImportYaml)) {
            throw "Failed to generate Tessy import YAML: $ImportYaml"
        }
    }

    Write-Info -Step $STEP -Message "Importing YAML: $ImportYaml"
    Invoke-TessyCommand `
        -Executable $TessyCmd `
        -Arguments @('import', $ImportYaml) `
        -FailureMessage 'Tessy import failed.' `
        -ShowOutput | Out-Null

    Write-Info -Step $STEP -Message "Executing batch: $BatchFile"
    $result = Invoke-TessyCommand `
        -Executable $TessyCmd `
        -Arguments @('-animate', 'exec-test', $BatchFile) `
        -FailureMessage 'Tessy batch execution failed.' `
        -ShowOutput `
        -AllowFailure

    $exitCode = $result.ExitCode
    if ($exitCode -eq 0) {
        Write-Info -Step $STEP -Message 'Tests executed and report generated.'
        Write-StepEnd $STEP
    } else {
        Write-WarningLog -Step $STEP -Message "Batch returned exit code $exitCode. Reports may still exist."
    }
}
catch {
    Write-ErrorLog `
        -Step $STEP `
        -Message $_.Exception.Message `
        -Command 'Step 08 execution' `
        -ExitCode 1
    $exitCode = 1
}
finally {
    Set-Location $previousLocation
}

if ($exitCode -eq 0) {
    Write-Host "`n$(('=' * 80))" -ForegroundColor Cyan
    Write-Host 'STEP 8 COMPLETE - Next-> step9: analyze results' -ForegroundColor Cyan
    Write-Host ('=' * 80) -ForegroundColor Cyan
}

exit $exitCode
