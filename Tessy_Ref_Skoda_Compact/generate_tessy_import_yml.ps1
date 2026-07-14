param(
    [Parameter(Mandatory=$true)][string]$TestObject,
    [Parameter(Mandatory=$true)][string]$Module,
    [Parameter(Mandatory=$true)][string]$WorkDir,
    [Parameter(Mandatory=$true)][string]$ScriptRoot,
    [Parameter(Mandatory=$false)][string[]]$StubNames = @(),
    [Parameter(Mandatory=$false)][string]$TessyProject = "sk336_t2",
    [Parameter(Mandatory=$false)][string]$PdbFile = "C:\Users\buimi1\Documents\03_repos\e-gsh_non-autosar_bsw_sk336-rcl-impl\test\tessy\tessy.pdbx",
    [Parameter(Mandatory=$false)][string]$TessyVersion = "5.1.14",
    [Parameter(Mandatory=$false)][string]$OutputFile = ""
)

$ErrorActionPreference = "Stop"

$ymlDir = Join-Path $WorkDir "yml"
New-Item -ItemType Directory -Path $ymlDir -Force | Out-Null

if ([string]::IsNullOrWhiteSpace($OutputFile)) {
    $OutputFile = Join-Path $ymlDir "$TestObject`_import.yml"
}

$planPath = Join-Path $WorkDir "json_testcase\${TestObject}_testcase_plan.json"
$scriptPath = Join-Path $WorkDir "script_files\${TestObject}_testcase.script"
if (-not (Test-Path $planPath)) {
    # Fallback to legacy path if needed
    $planPath = Join-Path $WorkDir "testObjectCode\${TestObject}_testcase_plan.json"
}
if (-not (Test-Path $planPath)) {
    throw "Testcase plan not found: $planPath"
}
if (-not (Test-Path $scriptPath)) {
    throw "Testcase script not found: $scriptPath"
}

$scriptContent = Get-Content $scriptPath -Raw

function Extract-Block {
    param(
        [string]$Content,
        [string]$Keyword
    )

    $startIdx = $Content.IndexOf($Keyword)
    if ($startIdx -eq -1) { return $null }

    $braceOpenIdx = $Content.IndexOf('{', $startIdx + $Keyword.Length)
    if ($braceOpenIdx -eq -1) { return $null }

    $depth = 0
    $chars = $Content.ToCharArray()
    for ($i = $braceOpenIdx; $i -lt $chars.Count; $i++) {
        $char = $chars[$i]
        if ($char -eq '{') {
            $depth++
        } elseif ($char -eq '}') {
            $depth--
            if ($depth -eq 0) {
                return $Content.Substring($braceOpenIdx + 1, $i - $braceOpenIdx - 1)
            }
        }
    }
    return $null
}

function Parse-Assignments {
    param([string]$BlockText)

    $assignments = [ordered]@{}
    if ([string]::IsNullOrEmpty($BlockText)) { return $assignments }

    $lines = $BlockText -split "`r?`n"
    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrEmpty($trimmed) -or $trimmed.StartsWith('$') -or $trimmed.StartsWith('/') -or $trimmed.StartsWith('*')) {
            continue
        }
        if ($trimmed -match '^\s*([^=]+)\s*=\s*(.+)$') {
            $key = $Matches[1].Trim()
            $val = $Matches[2].Trim()
            # Strip comments
            $val = $val -replace '//.*$', ''
            $val = $val -replace '/\*.*?\*/', ''
            $val = $val.Trim().TrimEnd(';')
            $assignments[$key] = $val
        }
    }
    return $assignments
}

function Format-YamlValue {
    param([string]$Value)

    if ($null -eq $Value) { return "''" }
    $text = [string]$Value
    $text = $text.Trim()
    if ($text -eq '') { return "''" }
    
    if ($text -match '^tc\d+\.\d+$') { return $text }
    if ($text.StartsWith('target_') -and -not $text.Contains('[')) { return $text }
    
    if (($text.StartsWith("'") -and $text.EndsWith("'")) -or ($text.StartsWith('"') -and $text.EndsWith('"'))) {
        return $text
    }

    if ($text -match '^[A-Za-z_][A-Za-z0-9_]*$') {
        return $text
    }

    $escaped = $text -replace "'", "''"
    return "'$escaped'"
}

# Parse stubs from testcase_plan.json or script content
$stubsBodyMap = [ordered]@{}
if (Test-Path $planPath) {
    try {
        $plan = Get-Content $planPath -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
        if ($plan.TestCases) {
            foreach ($tc in $plan.TestCases) {
                if ($tc.StubFunctions) {
                    foreach ($stub in $tc.StubFunctions) {
                        if ($stub.Name) {
                            if ($stub.PSObject.Properties['Return'] -and [string]$stub.Return -ne '') {
                                $retVal = [string]$stub.Return
                                if ($retVal -eq 'TRUE') { $retVal = '1' }
                                elseif ($retVal -eq 'FALSE') { $retVal = '0' }
                                $stubsBodyMap[$stub.Name] = "return $retVal;"
                            } elseif (-not $stubsBodyMap.Contains($stub.Name)) {
                                $stubsBodyMap[$stub.Name] = ""
                            }
                        }
                    }
                }
            }
        }
    } catch {
        Write-Warning "Skipped parsing testcase plan JSON: $_"
    }
}

$stubsEndIdx = $scriptContent.IndexOf('$testcase')
$stubsSection = if ($stubsEndIdx -ne -1) { $scriptContent.Substring(0, $stubsEndIdx) } else { $scriptContent }

$stubFuncMatches = [regex]::Matches($stubsSection, "(?ms)(void|boolean_t|u32|u16|u8|u64|s32|s16|s8|s64|float|double|struct\s+\w+|[A-Za-z_][A-Za-z0-9_]*)\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)\s*'''(.*?)'''")
foreach ($m in $stubFuncMatches) {
    $name = $m.Groups[2].Value
    $body = $m.Groups[4].Value.Trim()
    $body_lines = @()
    foreach ($line in ($body -split "`r?`n")) {
        $trimmed_line = $line.Trim()
        if ($trimmed_line) { $body_lines += $trimmed_line }
    }
    $cleaned_body = $body_lines -join " "
    if ($cleaned_body) {
        $stubsBodyMap[$name] = $cleaned_body
    } elseif (-not $stubsBodyMap.Contains($name)) {
        $stubsBodyMap[$name] = ""
    }
}

foreach ($name in @($stubsBodyMap.Keys)) {
    if ($name -match '^(?:ucDrv_FCCDone|ucDrv_ReadFCC)$') {
        if (-not $stubsBodyMap[$name]) {
            $stubsBodyMap[$name] = "return 0;"
        }
    }
}

$stubEntries = New-Object System.Collections.Generic.List[string]
foreach ($stubName in ($stubsBodyMap.Keys | Sort-Object)) {
    $body = $stubsBodyMap[$stubName]
    $stubEntries.Add("- ['0', '0', $stubName, '$body']") | Out-Null
}

# Parse teststeps dynamically
$teststeps = New-Object System.Collections.Generic.List[object]
$matches = [regex]::Matches($scriptContent, '\$teststep\s+([0-9\.]+)\s*\{')
foreach ($m in $matches) {
    $stepId = $m.Groups[1].Value
    $startIdx = $m.Index
    $stepBody = Extract-Block -Content $scriptContent.Substring($startIdx) -Keyword '$teststep'
    if ($null -ne $stepBody) {
        $teststeps.Add([pscustomobject]@{
            StepId = $stepId
            Body = $stepBody
        }) | Out-Null
    }
}

$allInputKeys = [System.Collections.Generic.HashSet[string]]::new()
$allOutputKeys = [System.Collections.Generic.HashSet[string]]::new()
$testcasesData = @()

foreach ($step in $teststeps) {
    $inputsBody = Extract-Block -Content $step.Body -Keyword '$inputs'
    $outputsBody = Extract-Block -Content $step.Body -Keyword '$outputs'

    $inputsDict = Parse-Assignments -BlockText $inputsBody
    $outputsDict = Parse-Assignments -BlockText $outputsBody

    foreach ($k in $inputsDict.Keys) { [void]$allInputKeys.Add($k) }
    foreach ($k in $outputsDict.Keys) { [void]$allOutputKeys.Add($k) }

    $testcasesData += [pscustomobject]@{
        StepId = $step.StepId
        Inputs = $inputsDict
        Outputs = $outputsDict
    }
}

function Get-HeaderName {
    param([string]$Key)
    if ($Key.StartsWith('target_') -and $Key.Contains('.')) {
        return "&$Key"
    }
    return $Key
}

function Normalize-RowValue {
    param([string]$Val)
    if ($Val.StartsWith('&')) { $Val = $Val.Substring(1) }
    if ($Val -match '^(target_[A-Za-z0-9_]+)\[\d+\]$') {
        return $Matches[1]
    }
    return $Val
}

$targetInputKeys = @($allInputKeys | Where-Object { $_.StartsWith('target_') -and $_.Contains('.') } | Sort-Object)
$otherInputKeys = @($allInputKeys | Where-Object { -not ($_.StartsWith('target_') -and $_.Contains('.')) } | Sort-Object)
$outputKeys = @($allOutputKeys | Sort-Object)

$finalHeadersKeys = $targetInputKeys + $otherInputKeys + $outputKeys
$finalHeadersNames = @($finalHeadersKeys | ForEach-Object { Get-HeaderName -Key $_ })

$typesRow = @()
foreach ($k in $finalHeadersKeys) {
    if ($allInputKeys.Contains($k)) {
        $typesRow += 'i'
    } else {
        $typesRow += 'o'
    }
}

$rowsLines = New-Object System.Collections.Generic.List[string]
foreach ($tc in $testcasesData) {
    $rowVals = @()
    $rowVals += "tc$($tc.StepId)"
    foreach ($k in $finalHeadersKeys) {
        $valStr = ""
        if ($tc.Inputs.Contains($k)) {
            $valStr = Normalize-RowValue -Val $tc.Inputs[$k]
        } elseif ($tc.Outputs.Contains($k)) {
            $valStr = Normalize-RowValue -Val $tc.Outputs[$k]
        }
        $rowVals += Format-YamlValue -Value $valStr
    }
    $rowsLines.Add("- [$($rowVals -join ', ')]") | Out-Null
}

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("Tessy: {Version: $TessyVersion, File Type: Import/Export}")
$lines.Add("---")
$lines.Add("General: {Project: $TessyProject, Testobject: $TestObject, PDB File: '$PdbFile', Tessy Version: $TessyVersion, Export Date: '$((Get-Date).ToString('yyyy-MM-dd'))', Module: $Module}")
$lines.Add("---")
$lines.Add("Properties:")
$lines.Add("- ['1', '0', '', Dummy, '', '', '', '']")

if ($stubEntries.Count -gt 0) {
    $lines.Add("---")
    $lines.Add("Stubs:")
    foreach ($entry in $stubEntries) { $lines.Add($entry) }
}

$lines.Add("---")
$lines.Add("Values:")

$headersFormatted = @($finalHeadersNames | ForEach-Object { if ($_.StartsWith('&')) { "'$_'" } else { $_ } })
$lines.Add("- [$($headersFormatted -join ', ')]") | Out-Null
$lines.Add("- [$($typesRow -join ', ')]") | Out-Null
foreach ($row in $rowsLines) {
    $lines.Add($row) | Out-Null
}

[System.IO.File]::WriteAllText($OutputFile, ($lines -join [Environment]::NewLine) + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
Write-Host "Generated Tessy import YAML: $OutputFile" -ForegroundColor Green
