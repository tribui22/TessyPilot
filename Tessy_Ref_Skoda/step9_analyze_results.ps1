# ============================================================================
# STEP 9: Analyze Test Results (Coverage + Pass/Fail)
# ============================================================================
# Purpose: Analyze coverage and test results, generate corrections for failures
# Usage: .\step9_analyze_results.ps1 -TestObject "tpsDrvCfgCrcCheckResult" -Module "tps929120_drv_cfg"
# ============================================================================
param(
    [Parameter(Mandatory=$false)][string]$TestObject,
    [Parameter(Mandatory=$false)][string]$Module = "",
    [Parameter(Mandatory=$false)][string]$WorkingDir = $PSScriptRoot,
    [Parameter(Mandatory=$false)][string]$ScriptRoot = (Split-Path -Parent $PSScriptRoot)
)

Write-Host "`n================================================================================" -ForegroundColor Cyan
Write-Host "  STEP 9: ANALYZE RESULTS" -ForegroundColor Cyan
Write-Host "  Test Object: $TestObject" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

if ($Module) {
    $ModuleName = $Module -replace '\.c$',''
    tessycmd select-module $Module 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) { tessycmd select-module $ModuleName 2>&1 | Out-Null }
}
if ($TestObject) {
    tessycmd select-test-object $TestObject 2>&1 | Out-Null
}
if ($LASTEXITCODE -ne 0) { Write-Host "WARNING: Selection failed (may not be connected)." -ForegroundColor Yellow }

Write-Host "Getting coverage summary..." -ForegroundColor Yellow

# Try to read from generated HTML report first
# Check multiple possible locations
$reportFile1 = "$ScriptRoot\report\TESSY_DetailsReport_${TestObject}.html"
$reportFile2 = "$WorkingDir\${TestObject}_coverage_report.html"

if (Test-Path $reportFile1) {
    $reportFile = $reportFile1
    Write-Host "[REPORT] Found report at: $reportFile" -ForegroundColor Cyan
} elseif (Test-Path $reportFile2) {
    $reportFile = $reportFile2
    Write-Host "[REPORT] Found report at: $reportFile" -ForegroundColor Cyan
} else {
    $reportFile = $null
}

$c0Coverage=0; $c1Coverage=0; $passCount=0; $failCount=0; $totalCount=0

if ($reportFile -and (Test-Path $reportFile)) {
    Write-Host "[REPORT] Reading coverage from HTML report..." -ForegroundColor Cyan
    $reportContent = Get-Content $reportFile -Raw
    
    # Extract coverage from HTML
    if ($reportContent -match 'C0[^>]*>(\d+\.?\d*)%') { $c0Coverage=[double]$Matches[1] }
    if ($reportContent -match 'C1[^>]*>(\d+\.?\d*)%') { $c1Coverage=[double]$Matches[1] }
    
    # Count test results
    $passMatches = [regex]::Matches($reportContent, 'PASSED|passed|OK')
    $failMatches = [regex]::Matches($reportContent, 'FAILED|failed|ERROR')
    $passCount = $passMatches.Count
    $failCount = $failMatches.Count
    $totalCount = $passCount + $failCount
    
    Write-Host "  C0: $c0Coverage%" -ForegroundColor White
    Write-Host "  C1: $c1Coverage%" -ForegroundColor White
} else {
    Write-Host "[WARNING] Coverage report not found, using default values" -ForegroundColor Yellow
}

# BEST SOURCE: Try reading from C0/C1 txt files first (most reliable)
# Check both tessy/report and parent/report directories
$reportDir1 = "$ScriptRoot\report"
$reportDir2 = Join-Path (Split-Path -Parent $ScriptRoot) "report"

$c0TxtFile = "$reportDir1\TESSY_DetailsReport_${TestObject}.c0.txt"
$c1TxtFile = "$reportDir1\TESSY_DetailsReport_${TestObject}.c1.txt"

if (-not (Test-Path $c0TxtFile)) {
    $c0TxtFile = "$reportDir2\TESSY_DetailsReport_${TestObject}.c0.txt"
    $c1TxtFile = "$reportDir2\TESSY_DetailsReport_${TestObject}.c1.txt"
}

if ((Test-Path $c0TxtFile) -and (Test-Path $c1TxtFile)) {
    Write-Host "[TXT] Reading coverage from C0/C1 txt files..." -ForegroundColor Cyan
    
    $c0Content = Get-Content $c0TxtFile -Raw
    $c1Content = Get-Content $c1TxtFile -Raw
    
    if ($c0Content -match 'C0-COVERAGE\s+(\d+\.?\d*)\s*%') {
        $c0Coverage = [double]$Matches[1]
        Write-Host "  C0: $c0Coverage%" -ForegroundColor Green
    }
    
    if ($c1Content -match 'C1-COVERAGE\s+(\d+\.?\d*)\s*%') {
        $c1Coverage = [double]$Matches[1]
        Write-Host "  C1: $c1Coverage%" -ForegroundColor Green
    }
}

# Also try reading from XML/HTML report from Tessy project report folder
if (Test-Path "$reportDir1\TESSY_DetailsReport_${TestObject}.html") {
    $reportDir = $reportDir1
} else {
    $reportDir = $reportDir2
}
$xmlReport = "$reportDir\TESSY_DetailsReport_${TestObject}.xml"
$htmlReport = "$reportDir\TESSY_DetailsReport_${TestObject}.html"

$executionSuccess = $false

if (Test-Path $htmlReport) {
    Write-Host "[HTML] Reading from Tessy HTML report..." -ForegroundColor Cyan
    $reportContent = Get-Content $htmlReport -Raw
    
    # Extract coverage from HTML - ONLY from actual coverage tables, NOT test descriptions!
    # Pattern: Tessy HTML format "Statement (C0) Coverage" followed by <div>80 %</div>
    # Use .NET regex with Singleline mode for proper multiline matching
    $c0Match = [regex]::Match($reportContent, 'Statement \(C0\) Coverage.{1,400}?<div[^>]*>(\d+\.?\d*)\s*%</div>', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    $c1Match = [regex]::Match($reportContent, 'Branch \(C1\) Coverage.{1,400}?<div[^>]*>(\d+\.?\d*)\s*%</div>', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    
    $c0Found = $false
    $c1Found = $false
    
    if ($c0Match.Success) {
        $c0Coverage = [double]$c0Match.Groups[1].Value
        $c0Found = $true
    }
    
    if ($c1Match.Success) {
        $c1Coverage = [double]$c1Match.Groups[1].Value
        $c1Found = $true
    }
    
    # Extract test statistics using .NET regex
    # NOTE: HTML structure varies - some reports have Successful/Failed fields, others don't!
    # Always try to get Total first
    $totalMatch = [regex]::Match($reportContent, 'Total Testcases.{1,400}?<div[^>]*>(\d+)</div>', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if ($totalMatch.Success) {
        $totalCount = [int]$totalMatch.Groups[1].Value
    }
    
    # Try to get Successful count (may not exist for some test objects)
    $successMatch = [regex]::Match($reportContent, 'Successful</div>.{1,400}?<div[^>]*>(\d+)</div>', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if ($successMatch.Success) {
        $passCount = [int]$successMatch.Groups[1].Value
    } else {
        # If Successful field doesn't exist, check test case status from individual results
        # Pattern: Look for test execution results (pass/fail indicators)
        $passedTests = [regex]::Matches($reportContent, 'style="[^"]*background-color:\s*rgb\(144,\s*238,\s*144\)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($passedTests.Count -gt 0) {
            $passCount = $passedTests.Count
        }
    }
    
    # Try to get Failed count (may not exist for some test objects)  
    $failMatch = [regex]::Match($reportContent, 'Failed</div>.{1,400}?<div[^>]*>(\d+)</div>', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    if ($failMatch.Success) {
        $failCount = [int]$failMatch.Groups[1].Value
    } else {
        # If Failed field doesn't exist, look for failed test indicators
        $failedTests = [regex]::Matches($reportContent, 'style="[^"]*background-color:\s*rgb\(255,\s*128,\s*128\)', [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        if ($failedTests.Count -gt 0) {
            $failCount = $failedTests.Count
        }
        # If we have Total but no explicit counts, calculate failed from total - passed
        if ($totalCount -gt 0 -and $passCount -ge 0 -and $failCount -eq 0) {
            $failCount = $totalCount - $passCount
        }
    }
    
    # Display what was actually found in the HTML
    if ($c0Found) {
        Write-Host "  C0: $c0Coverage% (from HTML)" -ForegroundColor Green
    } else {
        Write-Host "  C0: NO COVERAGE DATA IN HTML" -ForegroundColor Yellow
    }
    
    if ($c1Found) {
        Write-Host "  C1: $c1Coverage% (from HTML)" -ForegroundColor Green
    } else {
        Write-Host "  C1: NO COVERAGE DATA IN HTML" -ForegroundColor Yellow
    }
    
    Write-Host "  Tests: Total=$totalCount, Passed=$passCount, Failed=$failCount" -ForegroundColor White
} elseif (Test-Path $xmlReport) {
    Write-Host "[XML] Reading from Tessy details report..." -ForegroundColor Cyan
    [xml]$xmlContent = Get-Content $xmlReport

    if ($xmlContent.report -and $xmlContent.report.success -and ($xmlContent.report.success -eq 'ok')) {
        $executionSuccess = $true
    }
    
    # Try to extract coverage from XML
    $c0Node = $xmlContent.SelectSingleNode("//coverage[@type='C0']/@percent")
    $c1Node = $xmlContent.SelectSingleNode("//coverage[@type='C1']/@percent")
    
    if ($c0Node) { $c0Coverage = [double]$c0Node.Value }
    if ($c1Node) { $c1Coverage = [double]$c1Node.Value }
    
    Write-Host "  C0: $c0Coverage% (from XML)" -ForegroundColor White
    Write-Host "  C1: $c1Coverage% (from XML)" -ForegroundColor White
}

# ============================================================================
# TESSY XML: Try reading coverage directly from Tessy XML report format
# Tessy XML uses: <c0 ... percentage="100"/> and <c1 ... percentage="100"/>
# This is more reliable than HTML pattern matching for Tessy reports
# ============================================================================
if (($c0Coverage -le 0 -or $c1Coverage -le 0) -and (Test-Path $xmlReport)) {
    Write-Host "[TESSY-XML] Reading coverage from Tessy XML report..." -ForegroundColor Cyan
    try {
        $xmlRaw = [System.IO.File]::ReadAllText($xmlReport)
        # Match <c0 ... percentage="NNN"/> format
        $c0XmlMatch = [regex]::Match($xmlRaw, '<c0\b[^>]+\bpercentage="(\d+\.?\d*)"')
        $c1XmlMatch = [regex]::Match($xmlRaw, '<c1\b[^>]+\bpercentage="(\d+\.?\d*)"')
        if ($c0XmlMatch.Success -and $c0Coverage -le 0) {
            $c0Coverage = [double]$c0XmlMatch.Groups[1].Value
            Write-Host "  C0: $c0Coverage% (from Tessy XML)" -ForegroundColor Green
        }
        if ($c1XmlMatch.Success -and $c1Coverage -le 0) {
            $c1Coverage = [double]$c1XmlMatch.Groups[1].Value
            Write-Host "  C1: $c1Coverage% (from Tessy XML)" -ForegroundColor Green
        }
        # Also check execution success from XML
        if ($xmlRaw -match '<testcase[^>]+success="ok"') { $executionSuccess = $true }
        elseif ($xmlRaw -match 'success="notexecuted"') { $executionSuccess = $false }
    } catch {
        Write-Host "  [WARN] Could not parse Tessy XML: $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# Fallback inference for branchless functions when reports don't contain C0/C1 percentages
if (($c0Coverage -le 0 -and $c1Coverage -le 0) -and (Test-Path $xmlReport)) {
    try {
        [xml]$xmlContent2 = Get-Content $xmlReport
        if ($xmlContent2.report -and $xmlContent2.report.success -and ($xmlContent2.report.success -eq 'ok')) {
            $executionSuccess = $true
        }
    } catch {
        # ignore
    }

    $analysisFile = "$WorkingDir\json_files\${TestObject}_analysis_status.json"
    if ($executionSuccess -and (Test-Path $analysisFile)) {
        try {
            $analysis = Get-Content $analysisFile -Raw | ConvertFrom-Json
            $body = [string]$analysis.FunctionBody

            $conditions = [regex]::Matches($body, 'if\s*\(').Count
            $switches = [regex]::Matches($body, 'switch\s*\(').Count
            $cases = [regex]::Matches($body, 'case\s+[^:]+:').Count

            $branchLike = $conditions + $switches + $cases

            if ($branchLike -eq 0 -and $body.Trim().Length -gt 0) {
                $c0Coverage = 100.0
                $c1Coverage = 100.0
                Write-Host "[FALLBACK] No branches detected + tests executed => assuming C0/C1 = 100%" -ForegroundColor Green
            }
        } catch {
            # ignore
        }
    }
}

Write-Host "`nCoverage: C0=$c0Coverage% C1=$c1Coverage%" -ForegroundColor Yellow
Write-Host "Tests: Total=$totalCount Passed=$passCount Failed=$failCount" -ForegroundColor Yellow

# ============================================================================
# ENHANCED: Parse detailed test failure information from HTML report
# Compare Actual vs Expected values to determine real failures
# ============================================================================
$failureDetails = @()
$allVarDetails   = @()   # ALL variable rows (pass + fail) for complete $outputs reconstruction
$actualFailCount = 0
$actualPassCount = 0

if ((Test-Path $htmlReport) -and ($c0Coverage -ge 100 -and $c1Coverage -ge 100)) {
    Write-Host "`n[ANALYSIS] C0/C1 = 100% - Parsing variable comparison results..." -ForegroundColor Cyan
    $reportContent = Get-Content $htmlReport -Raw
    
    # Find all test case sections
    $testCasePattern = 'Test Case (\d+):'
    $testCaseMatches = [regex]::Matches($reportContent, $testCasePattern)
    
    Write-Host "[DEBUG] Found $($testCaseMatches.Count) test cases" -ForegroundColor DarkGray
    
    # Extract all variable comparison rows from the HTML
    # Pattern: <tr class="style_83"> rows that contain Name, Actual Value, Expected Value
    $rowPattern = '(?s)<tr[^>]*class="style_83"[^>]*>.*?</tr>'
    $allRows = [regex]::Matches($reportContent, $rowPattern)
    
    Write-Host "[DEBUG] Found $($allRows.Count) data rows total" -ForegroundColor DarkGray
    
    foreach ($row in $allRows) {
        $rowHtml = $row.Value
        
        # Extract all <div class="style_11"> elements (variable name and values)
        $divPattern = '<div[^>]*class="style_11"[^>]*>([^<]*(?:<br[^>]*>[^<]*)*)</div>'
        $divMatches = [regex]::Matches($rowHtml, $divPattern)
        
        if ($divMatches.Count -ge 3) {
            # First div = variable name, Second = actual value, Third = expected value
            $varName = $divMatches[0].Groups[1].Value -replace '<br[^>]*>','' -replace '&nbsp;',' ' -replace '\s+', ' '
            $actualValue = $divMatches[1].Groups[1].Value.Trim()
            $expectedValue = $divMatches[2].Groups[1].Value.Trim()
            
            $varName = $varName.Trim()
            
            # Skip if this is a header row or empty
            if ($varName -eq "Name" -or $varName -eq "" -or $varName -eq "Actual Value") { continue }
            
            # Determine which test case this belongs to
            $beforeRow = $reportContent.Substring(0, $row.Index)
            $tcMatches = [regex]::Matches($beforeRow, $testCasePattern)
            $testCaseNum = if ($tcMatches.Count -gt 0) { [int]$tcMatches[$tcMatches.Count - 1].Groups[1].Value } else { 0 }

            # Compare actual vs expected - ONLY count as failure if they don't match
            if ($actualValue -ne $expectedValue) {
                $rowStatus = "FAIL"
                $failureDetails += [ordered]@{
                    TestCase = $testCaseNum
                    Variable = $varName
                    ActualValue = $actualValue
                    ExpectedValue = $expectedValue
                    Status = $rowStatus
                }
                
                $actualFailCount++
                
                Write-Host "  [FAIL] TC$testCaseNum : $varName" -ForegroundColor Yellow
                Write-Host "     Expected: $expectedValue" -ForegroundColor Red
                Write-Host "     Actual:   $actualValue" -ForegroundColor Cyan
            } else {
                $rowStatus = "PASS"
                $actualPassCount++
            }

            # Always record every variable row (pass AND fail) for full $outputs reconstruction
            $allVarDetails += [ordered]@{
                TestCase     = $testCaseNum
                Variable     = $varName
                ExpectedValue = $expectedValue
                ActualValue  = $actualValue
                Status       = $rowStatus
            }
        }
    }
    
    if ($failureDetails.Count -gt 0) {
        Write-Host "`n[SUMMARY] Found $($failureDetails.Count) failed variable(s)" -ForegroundColor Yellow
        Write-Host "  Variables: $actualPassCount passed, $actualFailCount failed" -ForegroundColor White
        # Count unique test cases with failures
        $uniqueFailedTCs = ($failureDetails | Select-Object -Property TestCase -Unique).Count
        Write-Host "  Test Cases: $uniqueFailedTCs failed" -ForegroundColor White
        # Set failCount based on unique test cases with variable failures
        if ($uniqueFailedTCs -gt 0) {
            $failCount = $uniqueFailedTCs
            $passCount = $totalCount - $failCount
        }
    } else {
        Write-Host "`n[SUMMARY] All variable comparisons PASSED" -ForegroundColor Green
        Write-Host "  Variables checked: $actualPassCount" -ForegroundColor White
        # Override counts based on actual comparison results
        if ($actualPassCount -gt 0) {
            $failCount = 0
            $passCount = $totalCount
        }
    }
}

# Persist status JSON for iteration decision (with failure details)
$status = [ordered]@{
    TestObject=$TestObject; Module=$Module; C0=$c0Coverage; C1=$c1Coverage;
    Total=$totalCount; Passed=$passCount; Failed=$failCount;
    FailureDetails=$failureDetails;
    Timestamp=(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
}
$jsonDir = "$WorkingDir\json_files"
if (-not (Test-Path $jsonDir)) { New-Item -ItemType Directory -Path $jsonDir -Force | Out-Null }
$statusFile = "$jsonDir\${TestObject}_coverage_status.json"
$status | ConvertTo-Json -Depth 10 | Out-File -FilePath $statusFile -Encoding UTF8
Write-Host "`nStatus saved: $statusFile" -ForegroundColor DarkGray

# ============================================================================
# Save ALL variable comparisons to CSV (both PASS and FAIL rows)
# Step 4 correction pass uses this to rebuild complete $outputs blocks.
# Format: TestCase, Variable, ExpectedValue, ActualValue, Status
# ============================================================================
$correctionFile = "$jsonDir\${TestObject}_corrections.csv"
if ($allVarDetails.Count -gt 0) {
    Write-Host "`n[CORRECTIONS] Saving all variable comparison data for Step 4..." -ForegroundColor Cyan
    
    $csvContent = "TestCase,Variable,ExpectedValue,ActualValue,Status`n"
    $allVarDetails | Sort-Object { [int]$_.TestCase } | ForEach-Object {
        $varEscaped = $_.Variable     -replace ',', ';'
        $expEscaped = $_.ExpectedValue -replace ',', ';'
        $actEscaped = $_.ActualValue  -replace ',', ';'
        $csvContent += "$($_.TestCase),$varEscaped,$expEscaped,$actEscaped,$($_.Status)`n"
    }
    
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($correctionFile, $csvContent, $utf8NoBom)
    
    $failRows = ($allVarDetails | Where-Object { $_.Status -eq 'FAIL' }).Count
    $passRows = ($allVarDetails | Where-Object { $_.Status -eq 'PASS' }).Count
    Write-Host ("[OK] Saved {0} variable rows ({1} PASS, {2} FAIL)" -f $allVarDetails.Count, $passRows, $failRows) -ForegroundColor Green
    Write-Host "  File: $correctionFile" -ForegroundColor White
} elseif ($failureDetails.Count -gt 0) {
    # Fallback: allVarDetails empty (HTML parse returned nothing) but failures exist - save failures only
    Write-Host "`n[CORRECTIONS] Saving failure summary (fallback) for Step 4..." -ForegroundColor Cyan
    $csvContent = "TestCase,Variable,ExpectedValue,ActualValue,Status`n"
    $failureDetails | Sort-Object { [int]$_.TestCase } | ForEach-Object {
        $varEscaped = $_.Variable     -replace ',', ';'
        $expEscaped = $_.ExpectedValue -replace ',', ';'
        $actEscaped = $_.ActualValue  -replace ',', ';'
        $csvContent += "$($_.TestCase),$varEscaped,$expEscaped,$actEscaped,FAIL`n"
    }
    $utf8NoBom = New-Object System.Text.UTF8Encoding $false
    [System.IO.File]::WriteAllText($correctionFile, $csvContent, $utf8NoBom)
    Write-Host "[OK] Saved $($failureDetails.Count) failure rows" -ForegroundColor Green
} else {
    Write-Host "`n[INFO] No corrections needed - all tests passed" -ForegroundColor Green
}

if ((Test-Path $htmlReport) -and -not ($c0Coverage -ge 100 -and $c1Coverage -ge 100)) {
    Write-Host "`n[SKIP] C0=$c0Coverage% C1=$c1Coverage% - coverage not 100%, skipping variable comparison parse" -ForegroundColor Yellow
}

Write-Host "`n================================================================================" -ForegroundColor Cyan
Write-Host "  STEP 9 COMPLETE" -ForegroundColor Cyan
Write-Host "  Next: Run step10_verify_coverage.ps1" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan
exit 0
