# ============================================================================
# STEP 7: Generate Tessy Testcase Script
# ============================================================================
# Wrapper responsibilities:
#   - Load centralized configuration from common.ps1/config.ps1.
#   - Validate Step 6 testcase plan and Step 5 conditions artifact.
#   - Call step07_generate_testcases.ps1 with explicit parameters.
#   - Validate the generated Tessy testcase script.
#
# Step 7 structure:
#   step07.ps1
#   step07_generate_testcases.ps1
#   step07_metadata.ps1
#   step07_stubs.ps1
#   step07_inputs_outputs.ps1
# ============================================================================

[CmdletBinding()]
param(
    [switch]$ForceCreate
)

. (Join-Path $PSScriptRoot "..\helpers\common.ps1")

$STEP       = "STEP7"
$TestObject = $Config.TestObjects
$Module     = $Config.Module
$WorkingDir = $Config.WorkDir
$ScriptRoot = $Config.ScriptRoot
$SourceDir  = $Config.SourceDir

$generatorFile = Join-Path $PSScriptRoot "step07_generate_testcases.ps1"
$metadataFile  = Join-Path $PSScriptRoot "step07_metadata.ps1"
$stubsFile     = Join-Path $PSScriptRoot "step07_stubs.ps1"
$ioFile        = Join-Path $PSScriptRoot "step07_inputs_outputs.ps1"

$planFile = Join-Path `
    $WorkingDir `
    "json_testcase\${TestObject}_testcase_plan.json"

$conditionFile = Join-Path `
    $WorkingDir `
    "testObjectCode\${TestObject}_conditions_after_passing.c"

$outputFile = Join-Path `
    $WorkingDir `
    "script_files\${TestObject}_testcase.script"

Show-Banner "STEP 7 : GENERATE TESSY TESTCASE SCRIPT"
Write-StepStart $STEP

Write-Info -Step $STEP -Message "Test Object: $TestObject"
Write-Info -Step $STEP -Message "Module: $Module"
Write-Info -Step $STEP -Message "Testcase plan: $planFile"
Write-Info -Step $STEP -Message "Output script: $outputFile"

# ----------------------------------------------------------------------------
# Validate Step 7 structure and inputs
# ----------------------------------------------------------------------------

$requiredFiles = @(
    $generatorFile,
    $metadataFile,
    $stubsFile,
    $ioFile,
    $planFile,
    $conditionFile
)

foreach($requiredFile in $requiredFiles)
{
    if(-not (Test-Path $requiredFile))
    {
        Write-ErrorLog `
            -Step $STEP `
            -Message "Required Step 7 file not found: $requiredFile" `
            -Command "Test-Path $requiredFile" `
            -ExitCode 1

        exit 1
    }
}

# Verify the generator is the large implementation and accepts parameters.
try
{
    $generatorCommand = Get-Command $generatorFile -ErrorAction Stop
    $requiredParameters = @(
        "TestObject",
        "Module",
        "WorkingDir",
        "ScriptRoot",
        "SourceDir"
    )

    $missingParameters = @(
        $requiredParameters | Where-Object {
            $generatorCommand.Parameters.Keys -notcontains $_
        }
    )

    if($missingParameters.Count -gt 0)
    {
        throw "Generator is missing parameters: $($missingParameters -join ', ')"
    }
}
catch
{
    Write-ErrorLog `
        -Step $STEP `
        -Message "Invalid Step 7 generator: $($_.Exception.Message)" `
        -Command "Get-Command $generatorFile" `
        -ExitCode 1

    exit 1
}

# Validate the Step 6 testcase-plan contract.
try
{
    $plan = Get-Content $planFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $testCases = @($plan.TestCases)

    if([string]::IsNullOrWhiteSpace([string]$plan.FunctionSignature))
    {
        throw "FunctionSignature is missing."
    }

    if($testCases.Count -eq 0)
    {
        throw "TestCases is empty."
    }

    if([int]$plan.TotalTestCases -ne $testCases.Count)
    {
        throw "TotalTestCases=$($plan.TotalTestCases), TestCases.Count=$($testCases.Count)."
    }

    Write-Info `
        -Step $STEP `
        -Message "Testcase plan validated: $($testCases.Count) testcase(s)."
}
catch
{
    Write-ErrorLog `
        -Step $STEP `
        -Message "Invalid testcase plan: $($_.Exception.Message)" `
        -Command "ConvertFrom-Json $planFile" `
        -ExitCode 1

    exit 1
}

# ----------------------------------------------------------------------------
# Optional fresh-create mode
# ----------------------------------------------------------------------------

if($ForceCreate -and (Test-Path $outputFile))
{
    $backupFile = "$outputFile.$(Get-Date -Format 'yyyyMMdd_HHmmss').bak"

    Copy-Item `
        -Path $outputFile `
        -Destination $backupFile `
        -Force

    Remove-Item -Path $outputFile -Force

    Write-WarningLog `
        -Step $STEP `
        -Message "ForceCreate enabled. Existing script backed up to: $backupFile"
}

# ----------------------------------------------------------------------------
# Run the large Step 7 generator in a child PowerShell process
# ----------------------------------------------------------------------------

$powerShellExecutable = if(
    Get-Command "pwsh.exe" -ErrorAction SilentlyContinue
)
{
    "pwsh.exe"
}
elseif(
    Get-Command "powershell.exe" -ErrorAction SilentlyContinue
)
{
    "powershell.exe"
}
else
{
    Write-ErrorLog `
        -Step $STEP `
        -Message "Neither pwsh.exe nor powershell.exe was found." `
        -Command "Get-Command PowerShell" `
        -ExitCode 1

    exit 1
}

Write-Info `
    -Step $STEP `
    -Message "Run Step 7 testcase generator." `
    -Command $generatorFile

& $powerShellExecutable `
    -NoLogo `
    -NoProfile `
    -ExecutionPolicy Bypass `
    -File $generatorFile `
    -TestObject $TestObject `
    -Module $Module `
    -WorkingDir $WorkingDir `
    -ScriptRoot $ScriptRoot `
    -SourceDir $SourceDir

$generatorExitCode = $LASTEXITCODE

if($generatorExitCode -ne 0)
{
    Write-ErrorLog `
        -Step $STEP `
        -Message "Step 7 testcase generator failed." `
        -Command $generatorFile `
        -ExitCode $generatorExitCode

    exit 1
}

# ----------------------------------------------------------------------------
# Validate generated Tessy script
# ----------------------------------------------------------------------------

if(-not (Test-Path $outputFile))
{
    Write-ErrorLog `
        -Step $STEP `
        -Message "Generator completed without creating: $outputFile" `
        -Command $generatorFile `
        -ExitCode 1

    exit 1
}

$generatedContent = Get-Content $outputFile -Raw -Encoding UTF8
$testcaseCount = [regex]::Matches(
    $generatedContent,
    '\$testcase\s+\d+\s*\{'
).Count

$teststepCount = [regex]::Matches(
    $generatedContent,
    '\$teststep\s+\d+\.\d+\s*\{'
).Count

if($testcaseCount -eq 0 -or $teststepCount -eq 0)
{
    Write-ErrorLog `
        -Step $STEP `
        -Message "Generated script has no testcase/teststep blocks: $outputFile" `
        -Command "Validate generated script" `
        -ExitCode 1

    exit 1
}

Write-Info `
    -Step $STEP `
    -Message "Tessy script ready: $outputFile; Testcases=$testcaseCount; Teststeps=$teststepCount"

Write-StepEnd $STEP

Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host "STEP 7 COMPLETE" -ForegroundColor Cyan
Write-Host "Next-> Run step8: execute tests" -ForegroundColor Cyan
Write-Host ("=" * 80) -ForegroundColor Cyan

exit 0
