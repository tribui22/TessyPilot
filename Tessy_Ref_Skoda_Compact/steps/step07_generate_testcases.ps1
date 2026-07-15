# ============================================================================
# STEP 07 - Generate Tessy testcase script from Step 06 plan
# ============================================================================
# Called by step07.ps1. Rendering is delegated to:
#   step07_metadata.ps1
#   step07_stubs.ps1
#   step07_inputs_outputs.ps1
# ============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$TestObject,
    [Parameter(Mandatory)][string]$Module,
    [Parameter(Mandatory)][string]$WorkingDir,
    [Parameter(Mandatory)][string]$ScriptRoot,
    [Parameter(Mandatory)][string]$SourceDir
)

$ErrorActionPreference = 'Stop'

function Get-PlanPath {
    param([string]$Root, [string]$Name)

    $current = Join-Path $Root "json_testcase\${Name}_testcase_plan.json"
    $legacy  = Join-Path $Root "testObjectCode\${Name}_testcase_plan.json"

    if (Test-Path $current) { return $current }
    if (Test-Path $legacy) {
        New-Item (Split-Path $current) -ItemType Directory -Force | Out-Null
        Move-Item $legacy $current -Force
        Write-Host "[PLAN] Migrated legacy plan: $current" -ForegroundColor Yellow
    }
    return $current
}

function Get-Section {
    param([string]$Text, [string]$Name, [string[]]$Next)

    $stop = (($Next | ForEach-Object { [regex]::Escape($_) }) + '={3,}' + '\z') -join '|'
    $match = [regex]::Match($Text, "(?ms)$([regex]::Escape($Name)):\s*-+\s*(.*?)(?=\s*(?:$stop))")
    if ($match.Success) { return $match.Groups[1].Value.Trim() }
    return ''
}

function Get-VariableName {
    param([string]$Declaration)

    $text = $Declaration.Trim()
    if ($text -match '([A-Za-z_][A-Za-z0-9_:]*(?:#\d+)?)(?:\[|\s*$)') {
        return $Matches[1]
    }
    if ($text -match '\b([A-Za-z_]\w*)\s*(?::\s*\d+)?\s*$') {
        return $Matches[1]
    }
    return 'UNKNOWN'
}

function Convert-VariableSection {
    param([string]$Section, [switch]$KeepScopedName)

    $roots = @()
    $stack = @()

    foreach ($line in ($Section -split '\r?\n' | Where-Object { $_.Trim() })) {
        if ($line -notmatch '^(\s*)(.+?)\s+\[Passing:\s*([A-Z/]+)\](.*)$') { continue }

        $level = [int]([Math]::Floor($Matches[1].Length / 4))
        $decl  = $Matches[2].Trim()
        $pass  = $Matches[3].Trim()
        $extra = $Matches[4]
        $fullName = Get-VariableName $decl
        $shortName = if ($fullName -match '::([A-Za-z_]\w*)(?:#\d+)?$') { $Matches[1] } else { $fullName }
        $length = if ($extra -match '\[ArrayLength:\s*(\d+)\]') { [int]$Matches[1] } else { 0 }

        $item = @{
            Name            = $shortName
            FullName        = if ($KeepScopedName) { $fullName } else { $shortName }
            FullDeclaration = $decl
            Type            = $decl
            Passing         = $pass
            ArrayLength     = $length
            IsStruct        = $decl -match '^struct\s+'
            IsUnion         = $decl -match '^union\s+'
            Members         = @()
        }

        if ($level -eq 0) { $stack = @() }
        elseif ($level -lt $stack.Count) { $stack = @($stack[0..($level - 1)]) }

        if ($level -eq 0) { $roots += $item }
        elseif ($stack.Count) { $stack[-1].Members += $item }

        if ($item.IsStruct -or $item.IsUnion -or $decl -match '\*') { $stack += $item }
    }
    return $roots
}

function Convert-Parameters {
    param([string]$Section)

    $result = @()
    foreach ($line in ($Section -split '\r?\n' | Where-Object { $_.Trim() })) {
        if ($line -notmatch '^(\s*)(.*?)\s+([A-Za-z_]\w*)\s+\[Passing:\s*([A-Z/]+)\]') { continue }

        $indented = $Matches[1].Length -ge 4
        $type = $Matches[2].Trim()
        $name = $Matches[3].Trim()
        $pass = $Matches[4].Trim()

        if ($indented -and $result.Count -and ($result[-1].Type -match '\*' -or $result[-1].IsStruct -or $result[-1].IsUnion)) {
            $result[-1].Members += @{ Name=$name; Type=$type; FullDeclaration=$type; Passing=$pass; Members=@(); ArrayLength=0 }
            continue
        }

        $result += @{
            Name=$name; Type=$type; FullDeclaration=$type; Passing=$pass
            IsStruct=$type -match '^struct\s+'; IsUnion=$type -match '^union\s+'; Members=@()
        }
    }
    return $result
}

function Convert-Functions {
    param([string]$Section, [hashtable]$Registry)

    foreach ($line in ($Section -split '\r?\n' | Where-Object { $_.Trim() })) {
        if ($line -notmatch '^\s*(.+?)\s+([A-Za-z_]\w*)\s*\(([^)]*)\)') { continue }
        $returnType = ($Matches[1] -replace '\s+', ' ').Trim()
        $name = $Matches[2]
        $parameters = ($Matches[3] -replace '\s+', ' ').Trim()
        if (-not $parameters) { $parameters = 'void' }
        $Registry[$name] = @{ Name=$name; ReturnType=$returnType; Parameters=$parameters }
    }
}

function Merge-SetValues {
    param([object[]]$Defaults, [object[]]$Values)
    return @($Defaults) + @($Values)
}

function Normalize-PointerTargets {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return }

    $text = Get-Content $Path -Raw
    $text = [regex]::Replace($text, '(?m)^(\s*)(\w+)\s*=\s*target_(\w+)\s*$', '$1$2 = target_$3[0]')
    $text = [regex]::Replace($text, '(?m)^(\s*)(\w+)\s*=\s*&target_(\w+)\[0\]\s*$', '$1$2 = target_$3[0]')
    $text = [regex]::Replace($text, '(?m)(\btarget_\w+)\.(?!\[0\])', '$1[0].')
    [IO.File]::WriteAllText($Path, $text, [Text.UTF8Encoding]::new($false))
}

# Inputs ----------------------------------------------------------------------
$conditionFile = Join-Path $WorkingDir "testObjectCode\${TestObject}_conditions_after_passing.c"
$planFile      = Get-PlanPath $WorkingDir $TestObject
$outputDir     = Join-Path $WorkingDir 'script_files'
$outputFile    = Join-Path $outputDir "${TestObject}_testcase.script"
$rawFunctionFile = Join-Path $WorkingDir "testObjectCode\${TestObject}.c"

foreach ($file in @($conditionFile, $planFile)) {
    if (-not (Test-Path $file)) { throw "Required Step 07 input not found: $file" }
}

New-Item $outputDir -ItemType Directory -Force | Out-Null
$rawConditionsContent = Get-Content $conditionFile -Raw -Encoding UTF8
$interfaceContent = if ($rawConditionsContent -match '(?ms)/\*(.*?)\*/') {
    (($Matches[1] -split '\r?\n') -replace '^\s*\*\s?', '') -join "`n"
} else { $rawConditionsContent }

$globalVariablesInfo = Convert-VariableSection (Get-Section $interfaceContent 'GLOBAL VARIABLES' @('PARAMETERS','RETURN TYPE')) -KeepScopedName
$externalVariablesInfo = Convert-VariableSection (Get-Section $interfaceContent 'EXTERNAL VARIABLES' @('GLOBAL VARIABLES','PARAMETERS'))
$parametersInfo = Convert-Parameters (Get-Section $interfaceContent 'PARAMETERS' @('RETURN TYPE','EXTERNAL FUNCTIONS'))

$allFunctions = @{}
Convert-Functions (Get-Section $interfaceContent 'EXTERNAL FUNCTIONS' @('LOCAL FUNCTIONS','EXTERNAL VARIABLES')) $allFunctions
Convert-Functions (Get-Section $interfaceContent 'LOCAL FUNCTIONS' @('EXTERNAL VARIABLES','GLOBAL VARIABLES')) $allFunctions

$returnType = (Get-Section $interfaceContent 'RETURN TYPE' @('PARAMETERS','EXTERNAL FUNCTIONS') -replace '\s*\[Passing:[^\]]+\]', '').Trim()
if (-not $returnType) { $returnType = 'void' }

$script:rawFunctionSource = if (Test-Path $rawFunctionFile) { Get-Content $rawFunctionFile -Raw } else { '' }
$functionBody = if ($script:rawFunctionSource -match '(?ms)^[^{]*\{(.*)\}\s*$') { $Matches[1] } else { '' }

$mainPlan = Get-Content $planFile -Raw -Encoding UTF8 | ConvertFrom-Json
$planTestCases = @($mainPlan.TestCases)
$planDefaultValues = if ($mainPlan.DefaultValues) { @($mainPlan.DefaultValues) } else { @() }
if (-not $planTestCases.Count) { throw "Testcase plan contains no TestCases: $planFile" }

# Helper renderers ------------------------------------------------------------
. (Join-Path $PSScriptRoot 'step07_metadata.ps1')
. (Join-Path $PSScriptRoot 'step07_stubs.ps1')
. (Join-Path $PSScriptRoot 'step07_inputs_outputs.ps1')

# Render ----------------------------------------------------------------------
$utf8NoBom = [Text.UTF8Encoding]::new($false)
$scriptExists = Test-Path $outputFile
$content = if ($scriptExists) { [IO.File]::ReadAllText($outputFile) } else { "`$testobject {`n" }
$startNumber = 0

if ($scriptExists) {
    foreach ($match in [regex]::Matches($content, '\$testcase\s+(\d+)\s*\{')) {
        $startNumber = [Math]::Max($startNumber, [int]$match.Groups[1].Value)
    }
} else {
    $planStubs = @($planTestCases | ForEach-Object { @($_.StubFunctions) })
    $content += Build-TestObjectStubs -PlanStubFunctionNames $planStubs -FunctionRegistry $allFunctions
}

$newBlocks = [Text.StringBuilder]::new()
$number = $startNumber
foreach ($tc in $planTestCases) {
    $number++
    $description = if ($tc.Description) { [string]$tc.Description } else { "TC$($tc.TCId)" }
    $target = if ($tc.Target) { [string]$tc.Target } else { $description }

    [void]$newBlocks.Append((Build-TCMetadata -TcNum $number -TCDescription $description -TCTarget $target -TestObjectName $TestObject))
    $step = Build-TCInputsOutputs `
        -TcNum $tc.TCId `
        -StepNum 1 `
        -SetValues (Merge-SetValues $planDefaultValues @($tc.SetValues)) `
        -StubFunctionNames @($tc.StubFunctions) `
        -TCDescription $description
    $step = $step.Replace("`t`t`$teststep 1.1 {", "`t`t`$teststep $number.1 {")
    [void]$newBlocks.Append($step)
    [void]$newBlocks.Append("`t}`n")
}

if ($scriptExists) {
    $content = [regex]::Replace($content.TrimEnd(), '\}\s*$', { $newBlocks.ToString() + '}' }) + "`n"
} else {
    $content += $newBlocks.ToString() + '}'
}

[IO.File]::WriteAllText($outputFile, $content, $utf8NoBom)
Normalize-PointerTargets $outputFile

Write-Host "[OK] Step 07 generated $($planTestCases.Count) testcase(s)." -ForegroundColor Green
Write-Host "[OUTPUT] $outputFile" -ForegroundColor Cyan
exit 0
