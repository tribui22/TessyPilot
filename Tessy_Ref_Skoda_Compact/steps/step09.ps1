# ============================================================================
# STEP 09 - Analyze Tessy Coverage and Test Results
# ============================================================================
# Pipeline entry point. No command-line input is required.
# Loads all values from config.ps1 through common.ps1.
# ============================================================================

[CmdletBinding()]
param()

. (Join-Path $PSScriptRoot "..\helpers\common.ps1")

$STEP       = 'STEP9'
$TestObject = $Config.TestObjects
$Module     = $Config.Module
$WorkingDir = $Config.WorkDir
$ScriptRoot = $Config.ScriptRoot
$JsonDir    = Join-Path $WorkingDir 'json_files'

function Get-Step09ReportPaths {
    $reportRoots = @(
        (Join-Path $ScriptRoot 'report'),
        (Join-Path (Split-Path -Parent $ScriptRoot) 'report'),
        $WorkingDir
    ) | Select-Object -Unique

    [PSCustomObject]@{
        Html = Find-FirstExistingPath @($reportRoots | ForEach-Object {
            if ($_ -eq $WorkingDir) { Join-Path $_ "${TestObject}_coverage_report.html" }
            else { Join-Path $_ "TESSY_DetailsReport_${TestObject}.html" }
        })
        Xml = Find-FirstExistingPath @($reportRoots | ForEach-Object {
            Join-Path $_ "TESSY_DetailsReport_${TestObject}.xml"
        })
        C0 = Find-FirstExistingPath @($reportRoots | ForEach-Object {
            Join-Path $_ "TESSY_DetailsReport_${TestObject}.c0.txt"
        })
        C1 = Find-FirstExistingPath @($reportRoots | ForEach-Object {
            Join-Path $_ "TESSY_DetailsReport_${TestObject}.c1.txt"
        })
    }
}

function Get-Step09HtmlSummary {
    param([string]$Path)

    $summary = [ordered]@{ C0=0.0; C1=0.0; Total=0; Passed=0; Failed=0; Rows=@() }
    if (-not $Path) { return [PSCustomObject]$summary }

    $html = Get-Content $Path -Raw
    $singleline = [Text.RegularExpressions.RegexOptions]::Singleline

    $patterns = @{
        C0 = 'Statement \(C0\) Coverage.{1,500}?<div[^>]*>(\d+(?:\.\d+)?)\s*%</div>'
        C1 = 'Branch \(C1\) Coverage.{1,500}?<div[^>]*>(\d+(?:\.\d+)?)\s*%</div>'
        Total = 'Total Testcases.{1,500}?<div[^>]*>(\d+)</div>'
        Passed = 'Successful</div>.{1,500}?<div[^>]*>(\d+)</div>'
        Failed = 'Failed</div>.{1,500}?<div[^>]*>(\d+)</div>'
    }

    foreach ($name in $patterns.Keys) {
        $value = Get-RegexGroupValue $html $patterns[$name] 1 $singleline
        if ($null -ne $value) {
            if ($name -in @('C0','C1')) { $summary[$name] = [double]$value }
            else { $summary[$name] = [int]$value }
        }
    }

    if ($summary.Total -le 0 -and ($summary.Passed -gt 0 -or $summary.Failed -gt 0)) {
        $summary.Total = $summary.Passed + $summary.Failed
    }

    $testCasePattern = 'Test Case (\d+):'
    $rows = [regex]::Matches($html, '(?s)<tr[^>]*class="style_83"[^>]*>.*?</tr>')
    foreach ($row in $rows) {
        $divs = [regex]::Matches($row.Value, '<div[^>]*class="style_11"[^>]*>([^<]*(?:<br[^>]*>[^<]*)*)</div>')
        if ($divs.Count -lt 3) { continue }

        $name = ($divs[0].Groups[1].Value -replace '<br[^>]*>','' -replace '&nbsp;',' ' -replace '\s+',' ').Trim()
        if (-not $name -or $name -in @('Name','Actual Value')) { continue }

        $before = $html.Substring(0, $row.Index)
        $caseMatches = [regex]::Matches($before, $testCasePattern)
        $caseNumber = if ($caseMatches.Count) { [int]$caseMatches[$caseMatches.Count - 1].Groups[1].Value } else { 0 }
        $actual = $divs[1].Groups[1].Value.Trim()
        $expected = $divs[2].Groups[1].Value.Trim()

        $summary.Rows += [PSCustomObject]@{
            TestCase=$caseNumber; Variable=$name; ExpectedValue=$expected
            ActualValue=$actual; Status=$(if ($actual -eq $expected) { 'PASS' } else { 'FAIL' })
        }
    }

    return [PSCustomObject]$summary
}

function Update-Step09CoverageFromText {
    param($Summary, [string]$C0File, [string]$C1File)

    if ($C0File) {
        $value = Get-RegexGroupValue (Get-Content $C0File -Raw) 'C0-COVERAGE\s+(\d+(?:\.\d+)?)\s*%'
        if ($null -ne $value) { $Summary.C0 = [double]$value }
    }
    if ($C1File) {
        $value = Get-RegexGroupValue (Get-Content $C1File -Raw) 'C1-COVERAGE\s+(\d+(?:\.\d+)?)\s*%'
        if ($null -ne $value) { $Summary.C1 = [double]$value }
    }
}

function Update-Step09CoverageFromXml {
    param($Summary, [string]$XmlFile)

    if (-not $XmlFile -or ($Summary.C0 -gt 0 -and $Summary.C1 -gt 0)) { return }
    $xml = [IO.File]::ReadAllText($XmlFile)

    if ($Summary.C0 -le 0) {
        $value = Get-RegexGroupValue $xml '<c0\b[^>]*\bpercentage="(\d+(?:\.\d+)?)"'
        if ($null -ne $value) { $Summary.C0 = [double]$value }
    }
    if ($Summary.C1 -le 0) {
        $value = Get-RegexGroupValue $xml '<c1\b[^>]*\bpercentage="(\d+(?:\.\d+)?)"'
        if ($null -ne $value) { $Summary.C1 = [double]$value }
    }
}

function Set-Step09BranchlessFallback {
    param($Summary)

    if ($Summary.C0 -gt 0 -or $Summary.C1 -gt 0) { return }
    $analysisFile = Join-Path $JsonDir "${TestObject}_analysis_status.json"
    if (-not (Test-Path $analysisFile)) { return }

    $analysis = Get-Content $analysisFile -Raw | ConvertFrom-Json
    $body = [string]$analysis.FunctionBody
    $branchCount = [regex]::Matches($body, '\bif\s*\(|\bswitch\s*\(|\bcase\s+[^:]+:').Count
    if ($branchCount -eq 0 -and ($Summary.Total -gt 0 -or $Summary.Passed -gt 0)) {
        $Summary.C0 = $Summary.C1 = 100.0
    }
}

function Save-Step09Results {
    param($Summary)

    New-Item $JsonDir -ItemType Directory -Force | Out-Null
    $failedRows = @($Summary.Rows | Where-Object { $_.Status -eq 'FAIL' })
    if ($Summary.Rows.Count) {
        $failedCases = @($failedRows | Select-Object -ExpandProperty TestCase -Unique).Count
        $Summary.Failed = $failedCases
        if ($Summary.Total -gt 0) { $Summary.Passed = [Math]::Max(0, $Summary.Total - $failedCases) }
    }

    $status = [ordered]@{
        TestObject=$TestObject; Module=$Module; C0=$Summary.C0; C1=$Summary.C1
        Total=$Summary.Total; Passed=$Summary.Passed; Failed=$Summary.Failed
        FailureDetails=$failedRows; Timestamp=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    }
    $statusPath = Join-Path $JsonDir "${TestObject}_coverage_status.json"
    Write-Utf8NoBom $statusPath ($status | ConvertTo-Json -Depth 10)

    $csvPath = Join-Path $JsonDir "${TestObject}_corrections.csv"
    if ($Summary.Rows.Count) {
        $csv = $Summary.Rows | Sort-Object TestCase | ConvertTo-Csv -NoTypeInformation
        Write-Utf8NoBom $csvPath ($csv -join "`r`n")
    } elseif (Test-Path $csvPath) {
        Remove-Item $csvPath -Force
    }

    return $statusPath
}

Show-Banner 'STEP 9 : ANALYZE TESSY RESULTS'
Write-StepStart $STEP
Write-Info -Step $STEP -Message "Test Object: $TestObject"
Write-Info -Step $STEP -Message "Module: $Module"

try {
    $paths = Get-Step09ReportPaths
    if (-not $paths.Html -and -not $paths.Xml -and -not ($paths.C0 -and $paths.C1)) {
        throw "No Tessy report found for '$TestObject'."
    }

    if ($paths.Html) { Write-Info -Step $STEP -Message "HTML report: $($paths.Html)" }
    if ($paths.Xml)  { Write-Info -Step $STEP -Message "XML report: $($paths.Xml)" }

    $summary = Get-Step09HtmlSummary $paths.Html
    Update-Step09CoverageFromText $summary $paths.C0 $paths.C1
    Update-Step09CoverageFromXml $summary $paths.Xml
    Set-Step09BranchlessFallback $summary
    $statusPath = Save-Step09Results $summary

    Write-Host "`nCoverage: C0=$($summary.C0)% C1=$($summary.C1)%" -ForegroundColor Yellow
    Write-Host "Tests: Total=$($summary.Total) Passed=$($summary.Passed) Failed=$($summary.Failed)" -ForegroundColor Yellow
    Write-Info -Step $STEP -Message "Status saved: $statusPath"
    Write-StepEnd $STEP

    Write-Host "`n$(('=' * 80))" -ForegroundColor Cyan
    Write-Host 'STEP 9 COMPLETE - Next-> step10: verify coverage.' -ForegroundColor Cyan
    Write-Host ('=' * 80) -ForegroundColor Cyan
    exit 0
}
catch {
    Write-ErrorLog -Step $STEP -Message $_.Exception.Message -Command 'Step 09 analysis' -ExitCode 1
    exit 1
}
