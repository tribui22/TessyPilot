# ============================================================================
# STEP 2: Configure Test Interface Stubs (External + Local Functions)
# ============================================================================
# Configuration is loaded by common.ps1.
# Step 2a YAML export is integrated into this file.
# Step 2b interface parsing is integrated through common.ps1 APIs.
# ============================================================================

. (Join-Path $PSScriptRoot "..\common.ps1")

$STEP           = "STEP2"
$TestObject     = $Config.TestObjects
$TessyProject   = $Config.TessyProject
$TestCollection = $Config.TestCollection
$ScriptRoot     = $Config.ScriptRoot
$ExportDir      = $Config.WorkDir
$WorkingDir     = $Config.WorkDir
$Module         = $Config.Module
$ReportDir      = ""

$ReportDir = Resolve-TessyReportDirForTestObject `
    -ScriptRoot $ScriptRoot `
    -TestObject $TestObject `
    -PreferredReportDir $ReportDir

Show-Banner "STEP 2 : CONFIGURE TEST INTERFACE STUBS"
Write-StepStart $STEP

Write-Info -Step $STEP -Message "Test Object: $TestObject"
Write-Info -Step $STEP -Message "Report Directory: $ReportDir"

$ymlFolder = Join-Path $ExportDir "yml"
$yamlFile  = Join-Path $ymlFolder "${TestObject}_export.yml"

# ----------------------------------------------------------------------------
# Step 2a: Export YAML Configuration from Tessy (integrated)
# ----------------------------------------------------------------------------

if(-not (Test-Path $ymlFolder))
{
    New-Item -ItemType Directory -Path $ymlFolder -Force | Out-Null
    Write-Info -Step $STEP -Message "Created YAML folder: $ymlFolder"
}

$exportFile = "${TestObject}_export"
$exportCommand = "export -format yaml -expected -file $exportFile $ymlFolder"

Write-Info `
    -Step $STEP `
    -Message "Export current Tessy configuration to YAML: $yamlFile" `
    -Command $exportCommand

Set-Location $ScriptRoot

$exportOutput = & tessycmd `
    "export" `
    "-format" "yaml" `
    "-expected" `
    "-file" $exportFile `
    $ymlFolder 2>&1

$exportExitCode = $LASTEXITCODE

if($exportOutput)
{
    $exportOutput | ForEach-Object {
        Write-Host "  [tessycmd] $_" -ForegroundColor Gray
    }
}

# Preserve the original Step 2a criterion: the expected file must be created.
if(-not (Test-Path $yamlFile))
{
    Write-ErrorLog `
        -Step $STEP `
        -Message "YAML export file was not created: $yamlFile" `
        -Command $exportCommand `
        -ExitCode $exportExitCode

    exit 1
}

Write-Info -Step $STEP -Message "YAML exported successfully: $yamlFile"

# Step 2b: Parse HTML/XML Interface Report (integrated)
# -----------------------------------------------------------------------------

Write-Info `
    -Step $STEP `
    -Message "Parse Tessy HTML/XML interface report for '$TestObject'."

$interfaceFile = Export-TessyInterfaceInfo `
    -Step $STEP `
    -TestObject $TestObject `
    -ReportDir $ReportDir `
    -OutputDir $ExportDir

Write-Info `
    -Step $STEP `
    -Message "Interface information saved: $interfaceFile"

# -----------------------------------------------------------------------------
# ----------------------------------------------------------------------------
# Detect LOCAL + EXTERNAL Functions and Update YAML Stubs
# ----------------------------------------------------------------------------

$stubInfo = Get-TessyStubFunctionsFromInterface `
    -Step $STEP `
    -InterfaceFile $interfaceFile

Write-Info `
    -Step $STEP `
    -Message "Stub functions ($($stubInfo.All.Count)): $($stubInfo.All -join ', ')"

Update-TessyYamlStubs `
    -Step $STEP `
    -YamlFile $yamlFile `
    -InterfaceFile $interfaceFile `
    -StubFunctions $stubInfo.All

# ----------------------------------------------------------------------------
# Import YAML Twice for Reliability
# ----------------------------------------------------------------------------

Import-TessyYamlTwice `
    -Step $STEP `
    -YamlFile $yamlFile `
    -DelaySeconds 8

# ----------------------------------------------------------------------------
# Generate Import YAML Only When Its Required Testcase Plan Exists
# ----------------------------------------------------------------------------

$importYml    = Join-Path $ExportDir "yml\${TestObject}_import.yml"
$testcasePlan = Join-Path $ExportDir "testObjectCode\${TestObject}_testcase_plan.json"

if(Test-Path $importYml)
{
    Write-Info -Step $STEP -Message "Import YAML already exists: $importYml"
}
elseif(-not (Test-Path $testcasePlan))
{
    # The configured export YAML is already a valid Tessy YAML file and includes
    # the synchronized Stubs section. Use it as the initial import YAML until a
    # testcase plan becomes available and the dedicated generator can rebuild it.
    Copy-Item `
        -Path $yamlFile `
        -Destination $importYml `
        -Force

    if(-not (Test-Path $importYml))
    {
        Write-ErrorLog `
            -Step $STEP `
            -Message "Failed to create initial import YAML: $importYml" `
            -Command "Copy-Item $yamlFile $importYml" `
            -ExitCode 1

        exit 1
    }

    Write-WarningLog `
        -Step $STEP `
        -Message "Testcase plan is not available yet. Created initial import YAML from configured export YAML: $importYml"
}
else
{
    $generator = Join-Path $PSScriptRoot "generate_tessy_import_yml.ps1"

    Invoke-ChildPowerShellStep `
        -Step $STEP `
        -Name "Generate Tessy import YAML" `
        -ScriptPath $generator `
        -Arguments @{
            TestObject   = $TestObject
            Module       = $Module
            WorkDir      = $ExportDir
            ScriptRoot   = $ScriptRoot
            StubNames    = @(
                'ucDrv_CfgSetFCCFreqOfMCLK',
                'ucDrv_ConfigureFCC',
                'ucDrv_FCCDone',
                'ucDrv_LockRegister',
                'ucDrv_ReadFCC',
                'ucDrv_SetFCCPeriod',
                'ucDrv_StartFCC',
                'ucDrv_UnlockRegister'
            )
            TessyProject = $TessyProject
        }
}

Write-StepEnd $STEP

Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host "STEP 2 COMPLETE" -ForegroundColor Cyan
Write-Host "Next-> Run step3: find and save function code" -ForegroundColor Cyan
Write-Host ("=" * 80) -ForegroundColor Cyan

exit 0
