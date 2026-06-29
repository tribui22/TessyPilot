# ============================================================================
# STEP 2b: Export Interface Information from HTML Report
# ============================================================================
# Purpose: Parse a Tessy HTML (+ XML fallback) details report and save the
#          complete interface information to interface\<TestObject>_interface_info.txt.
#          Called by step2_configure_stubs.ps1.
#          May also be run standalone (same as export_interface_from_html.ps1).
# ============================================================================
param(
    [Parameter(Mandatory=$true)][string]$TestObject,
    [Parameter(Mandatory=$true)][string]$ReportDir,
    [Parameter(Mandatory=$true)][string]$OutputDir
)

$ErrorActionPreference = "Stop"

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "  STEP 2b: EXPORT INTERFACE FROM HTML REPORT" -ForegroundColor Cyan
Write-Host "  Test Object: $TestObject" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

# ============================================================================
# Helper: Extract array dimension from a C declaration
# ============================================================================
function Get-ArrayDimension {
    param([string]$Declaration)
    if ($Declaration -match '\[(\d+)\]') { return [int]$Matches[1] }
    return 0
}

# ============================================================================
# Helper: Format variable/member hierarchy for text output
# ============================================================================
function Format-VariableHierarchy {
    param($Variable, [int]$IndentLevel = 0)
    $indent = '    ' * $IndentLevel
    $output = "$indent$($Variable.Declaration) [Passing: $($Variable.Passing)]"
    if ($Variable.ArrayDim -gt 0) { $output += " [ArrayLength: $($Variable.ArrayDim)]" }
    foreach ($member in $Variable.Members) {
        $output += "`n" + (Format-VariableHierarchy -Variable $member -IndentLevel ($IndentLevel + 1))
    }
    return $output
}

# ============================================================================
# Helper: Parse rows from an HTML section using margin-left indentation
# ============================================================================
function Parse-HtmlRows {
    param([string]$Section)
    $pat = @'
<tr[^>]*>.*?<div\s+class="style_59"\s+style="\s*margin-left:\s*(\d+)pt;">([^<]+)</div>.*?</td>.*?<td[^>]*>.*?<div\s+class="style_59">([^<]*)</div>
'@
    return [regex]::Matches($Section, $pat.Trim(), [System.Text.RegularExpressions.RegexOptions]::Singleline)
}

# ============================================================================
# Helper: Build hierarchical variable list from HTML row matches
# ============================================================================
function Build-VarList {
    param($RowMatches, [string]$Label)
    $list     = @()
    $varStack = @()
    foreach ($m in $RowMatches) {
        $indentPt = [int]$m.Groups[1].Value
        $varDecl  = $m.Groups[2].Value.Trim() -replace '&#xa0;|&#x20;|&nbsp;', ' ' -replace '\s+', ' '
        $passing  = if ($m.Groups[3].Value.Trim() -ne '') { $m.Groups[3].Value.Trim() } else { 'UNKNOWN' }
        $level    = ($indentPt / 10) - 1

        # Skip function return type lines (e.g. "unsigned short [Passing: OUT]") - no variable name,
        # last token is a C type keyword, not an identifier
        $cTypeKeywords = @('void','char','short','int','long','float','double',
                           'u8','u16','u32','u64','s8','s16','s32','s64',
                           'bool','boolean','uint8_t','uint16_t','uint32_t','uint64_t',
                           'int8_t','int16_t','int32_t','int64_t')
        $lastWord = ($varDecl -split '\s+')[-1]
        if ($lastWord -and ($cTypeKeywords -contains $lastWord) -and $passing -eq 'OUT') {
            Write-Host ("  [SKIP] Return type line (not a parameter): $varDecl [$passing]") -ForegroundColor Yellow
            continue
        }

        # Skip anonymous union/struct: a bare 'union' or 'struct' keyword with no following
        # variable name is a C type/keyword, NOT a variable. Its children (members) should be
        # promoted to the enclosing scope. Push a transparent proxy so the stack depth is
        # maintained and the parent-routing logic below can skip over it.
        if ($varDecl -match '^\s*(union|struct)\s*$') {
            Write-Host ("  [SKIP] Anonymous union/struct keyword - not a variable name: '$varDecl' [$passing]") -ForegroundColor Yellow
            if ($level -lt $varStack.Count) { $varStack = @($varStack[0..$level]) }
            $anonProxy = @{
                Declaration = $varDecl; Passing = $passing; ArrayDim = 0
                IsStruct = $true; IsUnion = ($varDecl -match '^union'); IsAnonymous = $true
                Members = @(); IndentLevel = $level
            }
            if ($level -ge $varStack.Count) { $varStack += $anonProxy } else { $varStack[$level] = $anonProxy }
            continue
        }

        $varInfo = @{
            Declaration = $varDecl
            Passing     = $passing
            ArrayDim    = Get-ArrayDimension $varDecl
            IsStruct    = ($varDecl -match '^struct\s+') -or ($varDecl -match '^union\s+')
            IsUnion     = $varDecl -match '^union\s+'
            Members     = @()
            IndentLevel = $level
        }

        if ($level -lt $varStack.Count) { $varStack = @($varStack[0..$level]) }

        # Walk up the stack to find the real parent, skipping over any anonymous union/struct
        # proxy entries so their children are promoted to the enclosing scope.
        $effectiveLevel = $level
        while ($effectiveLevel -gt 0 -and $varStack.Count -ge $effectiveLevel `
               -and $varStack[$effectiveLevel - 1].ContainsKey('IsAnonymous') `
               -and $varStack[$effectiveLevel - 1].IsAnonymous) {
            $effectiveLevel--
        }

        if ($effectiveLevel -gt 0 -and $varStack.Count -ge $effectiveLevel) {
            $varStack[$effectiveLevel - 1].Members += $varInfo
        } else {
            $list += $varInfo
        }

        if ($varInfo.IsStruct) {
            if ($level -ge $varStack.Count) { $varStack += $varInfo } else { $varStack[$level] = $varInfo }
        }

        $indentStr = '  ' * $level
        $dimInfo   = if ($varInfo.ArrayDim -gt 0) { " [Array: $($varInfo.ArrayDim)]" } else { '' }
        $typeInfo  = if ($varInfo.IsUnion) { ' [Union]' } elseif ($varInfo.IsStruct) { ' [Struct]' } else { '' }
        Write-Host ("$indentStr  $Label $varDecl [$passing]$dimInfo$typeInfo") -ForegroundColor DarkGray
    }
    return $list
}

# ============================================================================
# Load HTML report
# ============================================================================
$htmlReportPath = "$ReportDir\TESSY_DetailsReport_${TestObject}.html"
if (-not (Test-Path $htmlReportPath)) {
    Write-Host "ERROR: HTML report not found: $htmlReportPath" -ForegroundColor Red
    exit 1
}
Write-Host "`n[PARSE] Reading: TESSY_DetailsReport_${TestObject}.html" -ForegroundColor Yellow
$htmlContent = Get-Content $htmlReportPath -Raw

# ============================================================================
# Initialise result structure
# ============================================================================
$interfaceData = @{
    ExternalFunctions = @()
    LocalFunctions    = @()
    ExternalVariables = @()
    GlobalVariables   = @()
    Parameters        = @()
    ReturnType        = ''     # e.g. "enum DmaDrv_CfgRstCheck_t [Passing: OUT]"
}

# ============================================================================
# Regex pattern for function signatures
# Allows <br> tags within return type and parameter list (Tessy wraps long
# signatures mid-token with <br/>, e.g. "unsigned sh<br/>ort").
# ============================================================================
$funcPat = '(?s)<div class="style_59" style=" margin-left: 10pt;">((?:[^<]|<br\s*/?>)+?)\s+(\w+)\s*\(((?:[^)<]|<br\s*/?>)*)\)</div>'

# ============================================================================
# External Functions
# ============================================================================
$extFuncMatch = '(?s)>External Functions</div>.*?<tr[^>]*valign="top"[^>]*>(.*?)(?=<tr[^>]*>\s*<td[^>]*>\s*<div[^>]*>(?:Local Functions|Static/Global Variables|Global Variables|Parameters|Parameter|$))'
if ($htmlContent -match $extFuncMatch) {
    $funcMatches = [regex]::Matches($Matches[1], $funcPat)
    foreach ($m in $funcMatches) {
        $sig = "$($m.Groups[1].Value.Trim()) $($m.Groups[2].Value)($($m.Groups[3].Value))"
        $sig = $sig -replace '<br\s*/?>', '' -replace '&#xa0;|&#x20;|&nbsp;', ' ' -replace '\s+', ' '
        $interfaceData.ExternalFunctions += $sig
        Write-Host "  External Function: $($m.Groups[2].Value)" -ForegroundColor DarkGray
    }
} elseif ($htmlContent -match '>External Functions</div>') {
    Write-Host '  [Fallback] Whole-HTML search for external functions...' -ForegroundColor Yellow
    $startPos = $htmlContent.IndexOf('>External Functions</div>')
    $endPos   = $htmlContent.IndexOf('>Local Functions</div>', $startPos)
    if ($endPos -lt 0) { $endPos = $htmlContent.Length }
    $funcMatches = [regex]::Matches($htmlContent.Substring($startPos, $endPos - $startPos), $funcPat)
    foreach ($m in $funcMatches) {
        $sig = "$($m.Groups[1].Value.Trim()) $($m.Groups[2].Value)($($m.Groups[3].Value))"
        $sig = $sig -replace '<br\s*/?>', '' -replace '&#xa0;|&#x20;|&nbsp;', ' ' -replace '\s+', ' '
        $interfaceData.ExternalFunctions += $sig
        Write-Host "  External Function: $($m.Groups[2].Value)" -ForegroundColor DarkGray
    }
}

# ============================================================================
# Local Functions
# ============================================================================
$localFuncMatch = '(?s)>Local Functions</div>.*?<tr[^>]*valign="top"[^>]*>(.*?)(?=<tr[^>]*>\s*<td[^>]*>\s*<div[^>]*>(?:Static/Global Variables|Global Variables|Parameters|Parameter|$))'
if ($htmlContent -match $localFuncMatch) {
    $funcMatches = [regex]::Matches($Matches[1], $funcPat)
    foreach ($m in $funcMatches) {
        $sig = "$($m.Groups[1].Value.Trim()) $($m.Groups[2].Value)($($m.Groups[3].Value))"
        $sig = $sig -replace '<br\s*/?>', '' -replace '&#xa0;|&#x20;|&nbsp;', ' ' -replace '\s+', ' '
        $interfaceData.LocalFunctions += $sig
        Write-Host "  Local Function: $($m.Groups[2].Value)" -ForegroundColor DarkGray
    }
}

# ============================================================================
# External Variables  (hierarchical, margin-left based)
# ============================================================================
$extVarMatch = '(?s)>External Variables</div>.*?(<tr[^>]*valign="top"[^>]*>.*?)(?=<tr[^>]*>\s*<td[^>]*>\s*<div[^>]*>(?:Static/Global Variables|Global Variables|Parameters|Parameter|$))'
if ($htmlContent -match $extVarMatch) {
    $rows = Parse-HtmlRows -Section $Matches[1]
    $interfaceData.ExternalVariables = Build-VarList -RowMatches $rows -Label 'External Variable:'

    # Deduplicate by variable name (keep first occurrence)
    $seen = @{}; $deduped = @()
    foreach ($var in $interfaceData.ExternalVariables) {
        $vn = if ($var.Declaration -match '\b(\w+)(?:\s*\[|$)') { $Matches[1] } else { $var.Declaration }
        if (-not $seen.ContainsKey($vn)) { $seen[$vn] = $true; $deduped += $var }
        else { Write-Host "  [FILTERED] Duplicate external variable removed: $($var.Declaration)" -ForegroundColor Yellow }
    }
    $interfaceData.ExternalVariables = $deduped
}

# ============================================================================
# Global / Static Variables  (hierarchical, margin-left based)
# ============================================================================
$globalVarMatch = '(?s)>(?:Static/Global Variables|Global Variables)</div>.*?(<tr[^>]*valign="top"[^>]*>.*?)(?=</table>|<tr[^>]*>\s*<td[^>]*>\s*<div[^>]*>(?:Parameters|Parameter|Return))'
if ($htmlContent -match $globalVarMatch) {
    $rows = Parse-HtmlRows -Section $Matches[1]
    $interfaceData.GlobalVariables = Build-VarList -RowMatches $rows -Label 'Global Variable:'
}

# ============================================================================
# Parameters  (hierarchical – handles struct members via margin-left indent)
# ============================================================================
$paramMatch = '(?s)>(?:Parameters|Parameter)</div>.*?(<tr[^>]*valign="top"[^>]*>.*?)(?=>Return</div>|<tr\s+class="style_72"|</table>)'
if ($htmlContent -match $paramMatch) {
    $rows = Parse-HtmlRows -Section $Matches[1]
    $interfaceData.Parameters = Build-VarList -RowMatches $rows -Label 'Parameter:'
}

# ============================================================================
# Return Type  (function return value – separate section from Parameters)
# ============================================================================
$returnSectionMatch = '(?s)>Return</div>.*?(<tr[^>]*valign="top"[^>]*>.*?)(?=<tr\s+class="style_72"|</table>)'
if ($htmlContent -match $returnSectionMatch) {
    $rows = Parse-HtmlRows -Section $Matches[1]
    if ($rows.Count -gt 0) {
        $retRow  = $rows[0]
        $retDecl = $retRow.Groups[2].Value.Trim() -replace '&#xa0;|&#x20;|&nbsp;', ' ' -replace '\s+', ' '
        $retPass = if ($retRow.Groups[3].Value.Trim() -ne '') { $retRow.Groups[3].Value.Trim() } else { 'OUT' }
        $interfaceData.ReturnType = "$retDecl [Passing: $retPass]"
        Write-Host "  Return Type: $retDecl [$retPass]" -ForegroundColor DarkGray
    }
}

# ============================================================================
# Fallback: XML report when HTML has no global variables
# ============================================================================
if ($interfaceData.GlobalVariables.Count -eq 0) {
    $xmlReportPath = "$ReportDir\TESSY_DetailsReport_${TestObject}.xml"
    if (Test-Path $xmlReportPath) {
        Write-Host '  [FALLBACK] No global vars in HTML - trying XML report...' -ForegroundColor Yellow
        $xmlContent = [System.IO.File]::ReadAllText($xmlReportPath)

        $knownVarNames = @{}
        foreach ($ev in $interfaceData.ExternalVariables) {
            if ($ev.Declaration -match '\b(\w+)\s*(?:\[|$)') { $knownVarNames[$Matches[1]] = $true }
        }
        foreach ($p in $interfaceData.Parameters) {
            if ($p.Declaration -match '\b(\w+)\s*(?:\[|$)') { $knownVarNames[$Matches[1]] = $true }
        }
        foreach ($ef in $interfaceData.ExternalFunctions) {
            if ($ef -match '\b(\w+)\s*\(') { $knownVarNames[$Matches[1]] = $true }
        }

        $xmlElemPat = @'
<element\s+indent="(\d+)"\s+kind="interface"\s+name="([^"]+)"(?:[^>]+passing="([^"]+)")?
'@
        $elementMatches = [regex]::Matches($xmlContent, $xmlElemPat.Trim())

        $globalList = @()
        $skipGroup  = $false
        $varStack   = @()

        foreach ($m in $elementMatches) {
            $indent   = [int]$m.Groups[1].Value
            $elemName = $m.Groups[2].Value.Trim()
            $passing  = if ($m.Groups[3].Success -and $m.Groups[3].Value -ne '') { $m.Groups[3].Value.Trim() } else { '' }
            $varName  = if ($elemName -match '\b(\w+)\s*(?:\[|\(|$)') { $Matches[1] } else { $elemName }

            if ($indent -eq 1) {
                $varStack = @()
                if ($knownVarNames.ContainsKey($varName) -or $passing -eq '') {
                    $skipGroup = $true
                } else {
                    $skipGroup = $false
                    $varInfo = @{
                        Declaration = $elemName; Passing = $passing
                        ArrayDim    = Get-ArrayDimension $elemName
                        IsStruct    = ($elemName -match '^struct\s+') -or ($elemName -match '^union\s+')
                        IsUnion     = $elemName -match '^union\s+'
                        Members     = @(); IndentLevel = 0
                    }
                    $globalList += $varInfo
                    $varStack   += $varInfo
                    Write-Host "  [XML] Global Variable: $elemName [$passing]" -ForegroundColor Yellow
                }
            } elseif (-not $skipGroup -and $passing -ne '') {
                while ($varStack.Count -gt 0 -and $varStack[-1].IndentLevel -ge ($indent - 1)) {
                    $varStack = $varStack[0..($varStack.Count - 2)]
                }
                if ($varStack.Count -gt 0) {
                    $memberInfo = @{
                        Declaration = $elemName; Passing = $passing
                        ArrayDim    = Get-ArrayDimension $elemName
                        IsStruct    = ($elemName -match '^struct\s+') -or ($elemName -match '^union\s+')
                        IsUnion     = $elemName -match '^union\s+'
                        Members     = @(); IndentLevel = $indent - 1
                    }
                    $varStack[-1].Members += $memberInfo
                    $varStack += $memberInfo
                }
            }
        }

        $interfaceData.GlobalVariables = $globalList
        Write-Host "  [XML] Found $($interfaceData.GlobalVariables.Count) global variable(s) from XML" -ForegroundColor Green
    }
}

Write-Host "`nSummary: $($interfaceData.ExternalFunctions.Count) external funcs, $($interfaceData.LocalFunctions.Count) local funcs, $($interfaceData.ExternalVariables.Count) ext vars, $($interfaceData.GlobalVariables.Count) globals, $($interfaceData.Parameters.Count) params" -ForegroundColor Green

# ============================================================================
# Validate Passing annotations - exit 1 if any UNKNOWN found
# ============================================================================
$unknownPassing = @()
$interfaceData.ExternalVariables | ForEach-Object { if ($_.Passing -eq 'UNKNOWN') { $unknownPassing += "External Variable: $($_.Declaration)" } }
$interfaceData.GlobalVariables   | ForEach-Object { if ($_.Passing -eq 'UNKNOWN') { $unknownPassing += "Global Variable: $($_.Declaration)" } }
$interfaceData.Parameters        | ForEach-Object { if ($_.Passing -eq 'UNKNOWN') { $unknownPassing += "Parameter: $($_.Declaration)" } }

if ($unknownPassing.Count -gt 0) {
    Write-Host "`n================================================================================" -ForegroundColor Red
    Write-Host "  ERROR: UNKNOWN PASSING DETECTED - USER ACTION REQUIRED" -ForegroundColor Red
    Write-Host "================================================================================" -ForegroundColor Red
    Write-Host "The following variables have UNKNOWN passing direction:" -ForegroundColor Yellow
    $unknownPassing | ForEach-Object { Write-Host "  - $_" -ForegroundColor Yellow }
    Write-Host "`nPlease manually edit the Tessy interface to specify Passing (IN/OUT/INOUT/IRRELEVANT)" -ForegroundColor Yellow
    Write-Host "Then re-run Step 1 to regenerate the report and Step 2 to update interface info." -ForegroundColor Yellow
    Write-Host "================================================================================" -ForegroundColor Red
    exit 1
}

# ============================================================================
# Save interface_info.txt
# ============================================================================
$interfaceFolder = "$OutputDir\interface"
if (-not (Test-Path $interfaceFolder)) {
    New-Item -ItemType Directory -Path $interfaceFolder -Force | Out-Null
}

$interfaceFile  = "$interfaceFolder\${TestObject}_interface_info.txt"
$extVarsText    = ($interfaceData.ExternalVariables | ForEach-Object { Format-VariableHierarchy -Variable $_ }) -join "`n"
$globalVarsText = ($interfaceData.GlobalVariables   | ForEach-Object { Format-VariableHierarchy -Variable $_ }) -join "`n"
$extFuncsText   = $interfaceData.ExternalFunctions -join "`n"
$localFuncsText = $interfaceData.LocalFunctions    -join "`n"
$paramsText     = ($interfaceData.Parameters | ForEach-Object { Format-VariableHierarchy -Variable $_ }) -join "`n"

@"
================================================================================
TESSY INTERFACE INFORMATION - $TestObject
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
================================================================================

EXTERNAL FUNCTIONS:
-------------------
$extFuncsText

LOCAL FUNCTIONS:
----------------
$localFuncsText

EXTERNAL VARIABLES:
-------------------
$extVarsText

GLOBAL VARIABLES:
-----------------
$globalVarsText

PARAMETERS:
-----------
$paramsText

RETURN TYPE:
------------
$($interfaceData.ReturnType)
================================================================================
"@ | Out-File $interfaceFile -Encoding UTF8

Write-Host "`n[SAVED] interface\${TestObject}_interface_info.txt" -ForegroundColor Green

Write-Host "`n================================================================================" -ForegroundColor Cyan
Write-Host "  STEP 2b COMPLETE" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan
exit 0
