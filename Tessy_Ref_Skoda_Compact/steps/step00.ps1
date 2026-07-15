# ============================================================================
# STEP 00 - Connect to Tessy and Discover Test Objects
# ============================================================================
# Pipeline entry point. No command-line input is required.
# All Tessy context values are loaded from config.ps1 through common.ps1.
# ============================================================================

[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot "..\common.ps1")

$STEP           = 'STEP0'
$Project        = $Config.TessyProject
$TestCollection = $Config.TestCollection
$Folder         = if ($null -eq $Config.Folder) { '' } else { [string]$Config.Folder }
$Module         = $Config.Module
$TestObject     = $Config.TestObjects
$TessyCmd       = Join-Path $Config.ScriptRoot 'tessycmd.exe'

Show-Banner 'STEP 0 : DISCOVER ALL TEST OBJECTS'
Write-StepStart $STEP

try {
    Connect-Tessy $STEP

    Write-Info -Step $STEP -Message 'Selecting Tessy context...'

    # Select-TessyContext is the shared helper from common_step08_additions.
    # Named arguments prevent PowerShell from prompting for mandatory values.
    Select-TessyContext `
        -Executable $TessyCmd `
        -Project $Project `
        -TestCollection $TestCollection `
        -Folder $Folder `
        -Module $Module `
        -TestObject $TestObject

    Write-Info -Step $STEP -Message 'Selection completed.'
    Write-Info -Step $STEP -Message 'Retrieving Test Objects.' -Command 'list-test-objects'

    $result = Invoke-TessyCommand `
        -Executable $TessyCmd `
        -Arguments @('list-test-objects') `
        -FailureMessage 'Failed to list Test Objects.'

    $testObjects = @(
        $result.Output |
            ForEach-Object { ([string]$_).Trim() } |
            Where-Object {
                $_ -and $_ -notmatch '^(?i:error|warning|tessycmd)'
            }
    )

    if ($testObjects.Count -eq 0) {
        throw 'No Test Objects found in the selected module.'
    }

    Write-Host "`nFound $($testObjects.Count) Test Object(s):" -ForegroundColor Green
    $testObjects | ForEach-Object {
        Write-Host "    - $_" -ForegroundColor DarkGray
    }

    Write-StepEnd $STEP

    Write-Host "`n$('=' * 80)" -ForegroundColor Cyan
    Write-Host 'STEP 0 COMPLETE' -ForegroundColor Cyan
    Write-Host 'Next: Execute Steps 1-10 for each Test Object.' -ForegroundColor Cyan
    Write-Host ('=' * 80) -ForegroundColor Cyan

    # Preserve the original Step 0 output contract.
    return $testObjects
}
catch {
    Write-ErrorLog `
        -Step $STEP `
        -Message $_.Exception.Message `
        -Command 'Step 0 discovery' `
        -ExitCode 1

    exit 1
}
