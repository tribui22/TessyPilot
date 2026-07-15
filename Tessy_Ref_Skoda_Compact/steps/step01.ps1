# ============================================================================
# STEP 1: Connect, Clean Old Reports, Generate New Interface Reports
# ============================================================================
# Purpose:
#   - Connect to Tessy
#   - Select project, test collection, folder, module, and test object
#   - Remove old reports
#   - Generate and execute the HTML interface report batch
#   - Analyze and save coverage status
#   - Export the existing testcase script when C0 > 0
#
# Notes:
#   - Existing Step 01 behavior is preserved.
#   - Reusable operations are delegated to common.ps1 where behavior matches.
# ============================================================================

. (Join-Path $PSScriptRoot "..\common.ps1")

$STEP          = "STEP1"
$Module        = $Config.Module
$Folder        = $Config.Folder
$TestObject    = $Config.TestObjects
$WorkingDir    = $Config.WorkDir
$ScriptRoot    = $Config.ScriptRoot
$ReportDir     = Resolve-TessyReportDir -ScriptRoot $ScriptRoot

Show-Banner "STEP 1 : CONNECT + GENERATE INTERFACE REPORTS"
Write-StepStart $STEP

Write-Info -Step $STEP -Message "Test Object: $TestObject"
Write-Info -Step $STEP -Message "Report Directory: $ReportDir"

# ----------------------------------------------------------------------------
# Connect
# ----------------------------------------------------------------------------

Connect-Tessy $STEP

# ----------------------------------------------------------------------------
# Select Tessy Context
# Keep the original Step 01 module-selection behavior:
#   - folder-selection failure does not stop the script
#   - use select-module -c when no folder is configured
#   - retry module selection without .c
# ----------------------------------------------------------------------------

Write-Info -Step $STEP -Message "Selecting Tessy context..."

Select-Project $STEP
Select-TestCollection $STEP

$folders = @()
$noFolder = [string]::IsNullOrWhiteSpace($Folder) -or $Folder -eq "."

if(-not $noFolder)
{
    $folders = $Folder -split '[/\\]'

    foreach($folderLevel in $folders)
    {
        Write-Info -Step $STEP -Message "Select Folder: $folderLevel"

        Set-Location $ScriptRoot
        & tessycmd "select-folder" $folderLevel 2>&1 | Out-Null

        if($LASTEXITCODE -ne 0)
        {
            Write-WarningLog `
                -Step $STEP `
                -Message "Failed to select folder '$folderLevel'; continue with current Tessy context." `
                -Command "select-folder $folderLevel" `
                -ExitCode $LASTEXITCODE
        }
    }
}

$moduleWithoutExtension = $Module -replace '\.c$',''
$selectedModule = $null

# Build unique selection attempts. The direct form is tried first because it is
# identical to the manual command: tessycmd select-module <Module>.
$moduleAttempts = @(
    [PSCustomObject]@{
        Name      = $Module
        Arguments = @($Module)
        Label     = "direct"
    }
)

# When no folder is configured, preserve the original -c selection attempt.
if($noFolder)
{
    $moduleAttempts += [PSCustomObject]@{
        Name      = $Module
        Arguments = @("-c", $Module)
        Label     = "collection"
    }
}

# Retry without .c only when the resulting name is actually different.
if($moduleWithoutExtension -ne $Module)
{
    $moduleAttempts += [PSCustomObject]@{
        Name      = $moduleWithoutExtension
        Arguments = @($moduleWithoutExtension)
        Label     = "direct without .c"
    }

    if($noFolder)
    {
        $moduleAttempts += [PSCustomObject]@{
            Name      = $moduleWithoutExtension
            Arguments = @("-c", $moduleWithoutExtension)
            Label     = "collection without .c"
        }
    }
}

foreach($attempt in $moduleAttempts)
{
    $commandText = "select-module $($attempt.Arguments -join ' ')"

    Write-Info `
        -Step $STEP `
        -Message "Select Module ($($attempt.Label)): $($attempt.Name)" `
        -Command $commandText

    Set-Location $ScriptRoot
    $moduleOutput = & tessycmd "select-module" @($attempt.Arguments) 2>&1
    $moduleExitCode = $LASTEXITCODE

    if($moduleExitCode -eq 0)
    {
        $selectedModule = $attempt.Name
        break
    }

    $outputText = ($moduleOutput | Out-String).Trim()

    Write-WarningLog `
        -Step $STEP `
        -Message "Module selection attempt failed. Tessy output: $outputText" `
        -Command $commandText `
        -ExitCode $moduleExitCode
}

if([string]::IsNullOrWhiteSpace($selectedModule))
{
    Write-ErrorLog `
        -Step $STEP `
        -Message "Failed to select module '$Module'." `
        -Command "select-module" `
        -ExitCode 1

    exit 1
}

Select-TestObject `
    -Step $STEP `
    -TestObject $TestObject

Write-Info -Step $STEP -Message "Tessy context selection completed."

# ----------------------------------------------------------------------------
# Clean Existing Reports
# ----------------------------------------------------------------------------

Write-Info -Step $STEP -Message "Deleting old reports for '$TestObject'."

Clear-TestObjectReports `
    -ReportDir $ReportDir `
    -TestObject $TestObject

# ----------------------------------------------------------------------------
# Generate Tessy Batch File
# New-TessyInterfaceReportBatch removes one trailing .c from its Module input.
# Append a temporary .c only when the selected Tessy module includes .c, so the
# generated XML keeps the exact module name selected by the original Step 01.
# ----------------------------------------------------------------------------

$batchModule = if($selectedModule -match '\.c$')
{
    "$selectedModule.c"
}
else
{
    $selectedModule
}

$batchFile = New-TessyInterfaceReportBatch `
    -TestObject $TestObject `
    -Module $batchModule `
    -Folder $Folder `
    -TestCollection $Config.TestCollection `
    -ReportDir $ReportDir `
    -WorkingDir $WorkingDir

Write-Info -Step $STEP -Message "Batch file created: $batchFile"

# ----------------------------------------------------------------------------
# Execute Tessy Batch
# ----------------------------------------------------------------------------

Invoke-TessyBatch `
    -Step $STEP `
    -BatchFile $batchFile

# ----------------------------------------------------------------------------
# Analyze Coverage Report
# ----------------------------------------------------------------------------

$htmlReport = Join-Path $ReportDir "TESSY_DetailsReport_${TestObject}.html"

if(-not (Test-Path $htmlReport))
{
    Write-WarningLog `
        -Step $STEP `
        -Message "HTML report not found: $htmlReport"
}

$coverage = Read-CoverageReport -HtmlReport $htmlReport

Write-Info `
    -Step $STEP `
    -Message "Coverage: C0=$($coverage.C0)% C1=$($coverage.C1)% Total=$($coverage.Total) Passed=$($coverage.Passed) Failed=$($coverage.Failed)"

# ----------------------------------------------------------------------------
# Save Coverage Status
# ----------------------------------------------------------------------------

$statusFile = Save-CoverageStatus `
    -WorkingDir $WorkingDir `
    -TestObject $TestObject `
    -Module $Module `
    -Coverage $coverage

Write-Info -Step $STEP -Message "Coverage status saved: $statusFile"

# ----------------------------------------------------------------------------
# Export Existing Testcase Script
# Preserve original behavior: export failure is a warning and remains non-fatal.
# ----------------------------------------------------------------------------

if([double]$coverage.C0 -gt 0)
{
    $scriptFile = Export-TestScriptNonFatal `
        -Step $STEP `
        -WorkingDir $WorkingDir `
        -TestObject $TestObject

    if($scriptFile)
    {
        Write-Info -Step $STEP -Message "Testcase script exported: $scriptFile"
    }
}

# ----------------------------------------------------------------------------
# Complete
# ----------------------------------------------------------------------------

Write-StepEnd $STEP

Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host "STEP 1 COMPLETE" -ForegroundColor Cyan
Write-Host "Next-> Run step2: configure stubs" -ForegroundColor Cyan
Write-Host ("=" * 80) -ForegroundColor Cyan

exit 0
