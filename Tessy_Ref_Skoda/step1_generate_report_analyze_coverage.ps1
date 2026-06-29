# ============================================================================
# STEP 1: Connect, Clean Old Reports, Generate New Interface Reports
# ============================================================================
# Renamed from: step1_generate_report.ps1
# Purpose: Connect to Tessy, select project/module/test object, remove old
#          reports and generate fresh XML + HTML interface reports.
# Usage: .\step1_generate_report_analyze_coverage.ps1 -TestObject "initAppl" -Module "init.c" -Folder "StartUp"
# ============================================================================
param(
    [Parameter(Mandatory=$true)][string]$TestObject,
    [Parameter(Mandatory=$true)][string]$Module,
    [Parameter(Mandatory=$true)][string]$Folder,
    [Parameter(Mandatory=$true)][string]$TessyProject,
    [Parameter(Mandatory=$true)][string]$TestCollection,
    [Parameter(Mandatory=$true)][string]$ScriptRoot,
    [Parameter(Mandatory=$true)][string]$WorkingDir
)

function Resolve-TessyReportDir {
    param([string]$ScriptRoot)

    $normalizedScriptRoot = [System.IO.Path]::GetFullPath($ScriptRoot)
    $scriptRootReport = Join-Path $normalizedScriptRoot "report"
    $projectRootReport = Join-Path (Split-Path -Parent $normalizedScriptRoot) "report"

    $candidates = if ((Split-Path $normalizedScriptRoot -Leaf) -ieq "tessy") {
        @($projectRootReport, $scriptRootReport)
    } else {
        @($scriptRootReport, $projectRootReport)
    }

    foreach ($candidate in ($candidates | Select-Object -Unique)) {
        if (Test-Path $candidate) { return $candidate }
    }

    return $candidates[0]
}

$ReportDir = Resolve-TessyReportDir -ScriptRoot $ScriptRoot

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "  STEP 1: CONNECT + GENERATE INTERFACE REPORTS" -ForegroundColor Cyan
Write-Host "  Test Object: $TestObject" -ForegroundColor Cyan
Write-Host "  Report Dir: $ReportDir" -ForegroundColor DarkGray
Write-Host "================================================================================" -ForegroundColor Cyan

Write-Host "`n[CONNECT] Connecting to Tessy..." -ForegroundColor Yellow
Set-Location $ScriptRoot
$tessy = Join-Path $ScriptRoot "tessycmd.exe"
& $tessy connect
if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: Failed to connect to Tessy!" -ForegroundColor Red; exit 1 }
Write-Host "Connected to Tessy." -ForegroundColor Green

Write-Host "`n[SELECT] Selecting test object context..." -ForegroundColor Yellow
Write-Host "  Project: $TessyProject" -ForegroundColor DarkGray
& $tessy select-project "$TessyProject" 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: Failed to select project '$TessyProject'" -ForegroundColor Red; exit 1 }

Write-Host "  Test Collection: $TestCollection" -ForegroundColor DarkGray
& $tessy select-test-collection "$TestCollection" 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: Failed to select test collection '$TestCollection'" -ForegroundColor Red; exit 1 }

if ($Folder -ne "." -and $Folder -ne "" -and $null -ne $Folder) {
    $folders = $Folder -split '[/\\]'
    foreach ($folderLevel in $folders) {
        Write-Host "  Folder: $folderLevel" -ForegroundColor DarkGray
        & $tessy select-folder "$folderLevel" 2>&1 | Out-Null
        #if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: Failed to select folder '$folderLevel'" -ForegroundColor Red; exit 1 }
    }
}
$ModuleName = $Module -replace '\.c$',''
$noFolder = ($Folder -eq "." -or $Folder -eq "" -or $null -eq $Folder)
# Try with .c extension first (some Tessy projects register modules with .c), then without
# When no folder is selected, use -c to select module directly from the test collection
Write-Host "  Module: $Module" -ForegroundColor DarkGray
if ($noFolder) {
    & $tessy select-module -c "$Module" 2>&1 | Out-Null
} else {
    & $tessy select-module "$Module" 2>&1 | Out-Null
}
if ($LASTEXITCODE -ne 0) {
    Write-Host "  Module (retry without .c): $ModuleName" -ForegroundColor DarkGray
    if ($noFolder) {
        & $tessy select-module -c "$ModuleName" 2>&1 | Out-Null
    } else {
        & $tessy select-module "$ModuleName" 2>&1 | Out-Null
    }
    if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: Failed to select module '$Module' or '$ModuleName'" -ForegroundColor Red; exit 1 }
} else {
    $ModuleName = $Module
}

Write-Host "  Test Object: $TestObject" -ForegroundColor DarkGray
& $tessy select-test-object "$TestObject" 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: Failed to select test object '$TestObject'" -ForegroundColor Red; exit 1 }
Write-Host "Selection complete." -ForegroundColor Green

Write-Host "`n[CLEANUP] Deleting old reports for $TestObject..." -ForegroundColor Yellow
if (-not (Test-Path $ReportDir)) { New-Item -ItemType Directory -Path $ReportDir -Force | Out-Null }
Get-ChildItem -Path $ReportDir -Filter "TESSY_DetailsReport_${TestObject}*.html" -ErrorAction SilentlyContinue |
    ForEach-Object {
        Remove-Item $_.FullName -Force
        Write-Host "  Deleted: $($_.Name)" -ForegroundColor DarkGray
    }
Write-Host "Old reports cleaned." -ForegroundColor Green

Write-Host "`n[GENERATE] Creating HTML batch file with execute and report operations..." -ForegroundColor Yellow
$folderXml = ""; $closingTags = ""
foreach ($folderLevel in $folders) { $folderXml += "            <folder name=`"$folderLevel`">`n"; $closingTags = "            </folder>`n" + $closingTags }
$batchContentHtml = @"
<?xml version="1.0" encoding="UTF-8"?>
<batchtest>
    <operations>
        <operation key="executeTest">
            <options>
                <option key="checkInterface" value="false"/>
                <option key="generateDriver" value="false"/>
                <option key="run" value="true"/>
                <option key="runNoInstrumentationTest" value="false"/>
                <option key="runPatternTest" value="false"/>
                <option key="runMutationTest" value="false"/>
                <option key="createNewTestRun" value="false"/>
                <option key="retryAbortedExecution" value="false"/>
                <option key="instrumentationType" value="TESTOBJECT_ONLY"/>
                <option key="defaultCoverage" value="false"/>
                <option key="defaultCoveragePerTestObject" value="false"/>
                <option key="abortOnMissingStubCode" value="true"/>
                <option key="preAnalyzeScript" value=""/>
                <option key="preExecuteScript" value=""/>
                <option key="postExecuteScript" value=""/>
            </options>
            <coverageTypes>
                <coverageType name="STATEMENT"/>
                <coverageType name="BRANCH"/>
            </coverageTypes>
        </operation>
        <operation key="generateTestReport">
            <options>
                <option key="reportOutputDirectory" value="`$(PROJECTROOT)\report"/>
                <option key="reportFileNamePattern" value="TESSY_DetailsReport_`$(TESTOBJECT)"/>
                <option key="reportOutputFormat" value="html"/>
            </options>
            <arguments>
                <argument name="OPT_TESTDATA_ONLY_MODE" value="false"/>
                <argument name="OPT_SHOW_PROPERTIES" value="true"/>
                <argument name="OPT_SHOW_USER_AND_HOST" value="false"/>
                <argument name="OPT_SHOW_COVERAGE" value="true"/>
                <argument name="OPT_SHOW_INTERFACE" value="true"/>
                <argument name="OPT_SHOW_METRICS" value="true"/>
                <argument name="OPT_SHOW_ATTRIBUTES" value="true"/>
                <argument name="OPT_SHOW_COMMENTS" value="true"/>
                <argument name="OPT_SHOW_CTE" value="true"/>
                <argument name="OPT_SHOW_USERCODE" value="true"/>
                <argument name="OPT_SHOW_TS_DETAILS" value="true"/>
                <argument name="OPT_SHOW_REQUIREMENT_TEXT" value="false"/>
                <argument name="OPT_SHOW_FAULT_INJECTION_TCS" value="true"/>
                <argument name="OPT_SHOW_FAULT_INJECTIONS" value="true"/>
                <argument name="OPT_HIDE_NONE_VALUES" value="true"/>
                <argument name="OPT_SHOW_NOTES" value="true"/>
                <argument name="OPT_SHOW_UUID" value="false"/>
                <argument name="OPT_HIDE_TESTSTEPS" value="false"/>
                <argument name="OPT_SHOW_VARIANT_INFO" value="true"/>
                <argument name="OPT_SHOW_LAST_MODIFIED_TIME" value="false"/>
            </arguments>
        </operation>
    </operations>
    <elements>
        <testcollection name="$TestCollection">
$folderXml                <module name="$ModuleName"><testobject name="$TestObject"/></module>
$closingTags        </testcollection>
    </elements>
</batchtest>
"@

$tbsDir = "$WorkingDir\tbs_files"
if (-not (Test-Path $tbsDir)) { New-Item -ItemType Directory -Path $tbsDir -Force | Out-Null }
$batchFileHtml = "$tbsDir\generate_report_${TestObject}_html.tbs"
$utf8NoBom = New-Object System.Text.UTF8Encoding $false
[System.IO.File]::WriteAllText($batchFileHtml,$batchContentHtml,$utf8NoBom)
Write-Host "  Created batch file in tbs_files/: generate_report_${TestObject}_html.tbs" -ForegroundColor DarkGray

Write-Host "Generating HTML report..." -ForegroundColor Yellow
.\tessycmd.exe -animate exec-test $batchFileHtml

Write-Host "  Batch file saved to tbs_files/ for Step 6:" -ForegroundColor Green
Write-Host "    - generate_report_${TestObject}_html.tbs" -ForegroundColor DarkGray

# ============================================================================
# ANALYZE REPORT: Read generated HTML/XML/TXT report and save coverage status
# Fields: C0, C1, Total, Passed, Failed -> json_files\<TestObject>_coverage_status.json
# ============================================================================
Write-Host "`n[ANALYZE] Reading coverage from generated report..." -ForegroundColor Yellow

$c0Coverage = 0.0; $c1Coverage = 0.0
$totalCount = 0;   $passCount  = 0;   $failCount  = 0

$htmlReport = "$ReportDir\TESSY_DetailsReport_${TestObject}.html"

if (Test-Path $htmlReport) {
    $html      = Get-Content $htmlReport -Raw
    $c0Match   = [regex]::Match($html, 'Statement \(C0\) Coverage.{1,400}?<div[^>]*>(\d+\.?\d*)\s*%</div>', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    $c1Match   = [regex]::Match($html, 'Branch \(C1\) Coverage.{1,400}?<div[^>]*>(\d+\.?\d*)\s*%</div>',   [System.Text.RegularExpressions.RegexOptions]::Singleline)
    $totMatch  = [regex]::Match($html, 'Total Testcases.{1,400}?<div[^>]*>(\d+)</div>',                     [System.Text.RegularExpressions.RegexOptions]::Singleline)
    $passMatch = [regex]::Match($html, 'Successful</div>.{1,400}?<div[^>]*>(\d+)</div>',                    [System.Text.RegularExpressions.RegexOptions]::Singleline)
    $failMatch = [regex]::Match($html, 'Failed</div>.{1,400}?<div[^>]*>(\d+)</div>',                        [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if ($c0Match.Success)   { $c0Coverage = [double]$c0Match.Groups[1].Value }
    if ($c1Match.Success)   { $c1Coverage = [double]$c1Match.Groups[1].Value }
    if ($totMatch.Success)  { $totalCount = [int]$totMatch.Groups[1].Value }
    if ($passMatch.Success) { $passCount  = [int]$passMatch.Groups[1].Value }
    if ($failMatch.Success) { $failCount  = [int]$failMatch.Groups[1].Value }
    if ($totalCount -gt 0 -and $passCount -eq 0 -and $failCount -eq 0) { $passCount = $totalCount }
} else {
    Write-Host "  [WARNING] HTML report not found: $htmlReport" -ForegroundColor Yellow
}

Write-Host "  C0: $c0Coverage%  C1: $c1Coverage%  Total: $totalCount  Passed: $passCount  Failed: $failCount" -ForegroundColor $(if ($c0Coverage -ge 100 -and $c1Coverage -ge 100) { "Green" } else { "Yellow" })

$jsonDir    = "$WorkingDir\json_files"
if (-not (Test-Path $jsonDir)) { New-Item -ItemType Directory -Path $jsonDir -Force | Out-Null }
$statusFile = "$jsonDir\${TestObject}_coverage_status.json"
[ordered]@{
    TestObject = $TestObject
    Module     = $Module
    C0         = $c0Coverage
    C1         = $c1Coverage
    Total      = $totalCount
    Passed     = $passCount
    Failed     = $failCount
} | ConvertTo-Json -Depth 5 | Out-File -FilePath $statusFile -Encoding UTF8
Write-Host "  Status saved: $statusFile" -ForegroundColor DarkGray

# ============================================================================
# EXPORT EXISTING SCRIPT: If C0 > 0, export current .script from Tessy
# so Step 7 can run in APPEND mode with the actual existing test cases.
# ============================================================================
if ($c0Coverage -gt 0) {
    $scriptDir        = "$WorkingDir\script_files"
    $existingTestCase = "$scriptDir\${TestObject}_testcase.script"
    if (-not (Test-Path $scriptDir)) { New-Item -ItemType Directory -Path $scriptDir -Force | Out-Null }
    Write-Host "`n[EXPORT SCRIPT] C0=$c0Coverage% > 0 -- exporting existing test case script..." -ForegroundColor Yellow
    Write-Host "  Output: $existingTestCase" -ForegroundColor DarkGray
    & $tessy export -format script -expected -file ${TestObject}_testcase.script $scriptDir
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  [OK] Script exported: $existingTestCase" -ForegroundColor Green
    } else {
        Write-Host "  [WARNING] tessycmd export returned exit code $LASTEXITCODE -- script may not have been written" -ForegroundColor Yellow
    }
}

Write-Host "`n================================================================================" -ForegroundColor Cyan
Write-Host "  STEP 1 COMPLETE" -ForegroundColor Cyan
Write-Host "  Next: Run step2_configure_stubs.ps1" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan
exit 0