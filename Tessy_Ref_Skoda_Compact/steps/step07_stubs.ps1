# ============================================================================
# STEP 07B - Tessy Stub Renderer
# ============================================================================
# Dot-sourced by step07_generate_testcases.ps1.
# Generic object/property normalization lives in common.ps1.
# ============================================================================

# Load generic helpers from common.ps1 when the generator runs in a child
# PowerShell process. Local fallbacks keep this renderer independently usable.
$commonFile = Join-Path $PSScriptRoot\helpers\ 'common.ps1'
if (Test-Path $commonFile) { . $commonFile }

if (-not (Get-Command Get-ObjectPropertyValue -CommandType Function -ErrorAction SilentlyContinue)) {
    function Get-ObjectPropertyValue {
        param([Parameter(Mandatory)]$InputObject, [Parameter(Mandatory)][string[]]$Names)
        foreach ($propertyName in $Names) {
            if ($InputObject.PSObject.Properties.Name -contains $propertyName) {
                return $InputObject.$propertyName
            }
        }
        return $null
    }
}

if (-not (Get-Command ConvertTo-FunctionInfo -CommandType Function -ErrorAction SilentlyContinue)) {
    function ConvertTo-FunctionInfo {
        param([Parameter(Mandatory)]$InputObject, [string]$FallbackName = '')

        $name = [string](Get-ObjectPropertyValue $InputObject @('Name'))
        if ([string]::IsNullOrWhiteSpace($name)) { $name = $FallbackName }

        $returnType = [string](Get-ObjectPropertyValue $InputObject @('ReturnType'))
        if ([string]::IsNullOrWhiteSpace($returnType)) { $returnType = 'int' }

        $parameters = [string](Get-ObjectPropertyValue $InputObject @('Parameters'))
        if ([string]::IsNullOrWhiteSpace($parameters)) { $parameters = 'void' }

        return [PSCustomObject]@{
            Name       = $name.Trim()
            ReturnType = $returnType.Trim()
            Parameters = $parameters.Trim()
        }
    }
}

if (-not (Get-Command ConvertTo-NormalizedReturnValue -CommandType Function -ErrorAction SilentlyContinue)) {
    function ConvertTo-NormalizedReturnValue {
        param([string]$ReturnType, [AllowNull()][string]$Value)

        if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
        $result = (($Value -replace '^\s*return\s+', '') -replace ';\s*$', '').Trim()

        if ($ReturnType -match '\b(bool|boolean_t)\b') {
            if ($result -match '^(?i:true|1(?:U|UL|L)?)$')  { return '1' }
            if ($result -match '^(?i:false|0(?:U|UL|L)?)$') { return '0' }
        }
        return $result
    }
}

function Get-Step07Registry {
    param([hashtable]$FunctionRegistry)

    if ($null -ne $FunctionRegistry) { return $FunctionRegistry }
    $variable = Get-Variable allFunctions -Scope Script -ErrorAction SilentlyContinue
    if ($variable -and $variable.Value -is [hashtable]) { return $variable.Value }
    return @{}
}

function Get-StubDefaultReturn
{
    param(
        [AllowEmptyString()]
        [string]$ReturnType
    )

    $type = ""

    if($null -ne $ReturnType)
    {
        $type = (
            $ReturnType -replace "\s+", " "
        ).Trim()
    }

    # Void functions must not return a value.
    if($type -match "^void$")
    {
        return ""
    }

    # Pointer return.
    if($type -match "\*")
    {
        return "return (void *)0;"
    }

    # Floating-point return.
    if($type -match "\b(float|double)\b")
    {
        return "return 0.0;"
    }

    # Struct return.
    if($type -match "^struct\s+([A-Za-z_]\w*)")
    {
        $typeName = $Matches[1]

        return (
            "struct $typeName ret_val; " +
            "(void)memset(&ret_val, 0, sizeof(ret_val)); " +
            "return ret_val;"
        )
    }

    # Integer, enum, boolean, and typedef return.
    return "return 0;"
}

function Normalize-StubReturnValue {
    param([string]$ReturnType, [AllowNull()][string]$RawValue)
    ConvertTo-NormalizedReturnValue -ReturnType $ReturnType -Value $RawValue
}

function Parse-StubOverrides {
    param([object[]]$StubFunctionNames = @())

    $result = @{}
    foreach ($item in @($StubFunctionNames)) {
        if ($null -eq $item) { continue }

        $name = $value = $null
        if ($item -is [string]) {
            $text = $item.Trim()
            if ($text -match '^([A-Za-z_]\w*)\s*(?:[=:]|returns)\s*(.+)$') {
                $name, $value = $Matches[1], $Matches[2]
            } elseif ($text -match '^[A-Za-z_]\w*$') {
                $name = $text
            }
        } else {
            $name = Get-ObjectPropertyValue $item @('Name','Function','Stub')
            $body = Get-ObjectPropertyValue $item @('Body')
            $value = if ($null -ne $body) { '__BODY__|' + [string]$body }
                     else { Get-ObjectPropertyValue $item @('Return','Returns','Value') }
        }

        if (-not [string]::IsNullOrWhiteSpace([string]$name)) {
            $result[[string]$name.Trim()] = if ($null -eq $value) { $null } else { [string]$value.Trim() }
        }
    }
    return $result
}

function Get-Step07Stubs {
    param(
        [object[]]$PlanStubs = @(),
        [hashtable]$FunctionRegistry,
        [switch]$NonVoidOnly
    )

    $result = [ordered]@{}
    $registry = Get-Step07Registry $FunctionRegistry

    foreach ($name in ($registry.Keys | Sort-Object)) {
        $info = ConvertTo-FunctionInfo $registry[$name] $name
        if (-not $NonVoidOnly -or $info.ReturnType -ne 'void') { $result[$info.Name] = $info }
    }

    foreach ($name in ((Parse-StubOverrides $PlanStubs).Keys | Sort-Object)) {
        if (-not $result.Contains($name)) {
            $result[$name] = [PSCustomObject]@{ Name=$name; ReturnType='int'; Parameters='void' }
            Write-Host "[STUB] Synthesized: int $name(void)" -ForegroundColor Yellow
        }
    }
    return @($result.Values)
}

function Get-EffectiveNonVoidStubs {
    param([object[]]$StubFunctionNames = @(), [hashtable]$FunctionRegistry)
    @(Get-Step07Stubs $StubFunctionNames $FunctionRegistry -NonVoidOnly)
}

function Get-EffectiveStubs {
    param([object[]]$StubFunctionNames = @(), [hashtable]$FunctionRegistry)
    @(Get-Step07Stubs $StubFunctionNames $FunctionRegistry)
}

function Get-Step07StubBody {
    param($FunctionInfo, [AllowNull()][string]$Override, [switch]$CoveragePolicy)

    if ($null -ne $Override) {
        if ($Override.StartsWith('__BODY__|')) { return $Override.Substring(9) }
        $value = Normalize-StubReturnValue $FunctionInfo.ReturnType $Override
        if ($value) { return "return $value;" }
    }

    if ($CoveragePolicy) {
        if ($FunctionInfo.Name -eq 'ucDrv_FCCDone') {
            return 'if (TS_CURRENT_TESTCASE == 1) { static int call_count = 0; if (call_count++ == 0) return 0; return 1; } return 0;'
        }
        if ($FunctionInfo.Name -eq 'ucDrv_ReadFCC') {
            return 'if (TS_CURRENT_TESTCASE == 1) { return 2; } else if (TS_CURRENT_TESTCASE == 2) { return 0; } else if (TS_CURRENT_TESTCASE == 3) { return 1; } return 0;'
        }
    }
    return Get-StubDefaultReturn $FunctionInfo.ReturnType
}

function Add-Step07Stub {
    param(
        [Parameter(Mandatory)][Text.StringBuilder]$Builder,
        [Parameter(Mandatory)]$FunctionInfo,
        [string]$Body = '',
        [int]$Indent = 2
    )

    $tabs = "`t" * $Indent
    $signature = "$($FunctionInfo.ReturnType) $($FunctionInfo.Name)($($FunctionInfo.Parameters))"
    if ($signature -match '\[') { $signature = "'$signature'" }

    [void]$Builder.AppendLine("$tabs$signature '''")
    if ($Body) { [void]$Builder.AppendLine("$tabs`t$Body") }
    [void]$Builder.AppendLine("$tabs'''")
}

function Build-TCStubs {
    param(
        [Parameter(Mandatory)][ValidateRange(1,[int]::MaxValue)][int]$TcNum,
        [object[]]$StubFunctionNames = @(),
        [hashtable]$FunctionRegistry
    )

    $overrides = Parse-StubOverrides $StubFunctionNames
    $functions = Get-EffectiveNonVoidStubs $StubFunctionNames $FunctionRegistry
    $builder = New-Object System.Text.StringBuilder

    if ($functions.Count) {
        [void]$builder.AppendLine("`t`t`$stubfunctions {")
        foreach ($function in $functions) {
            $body = Get-Step07StubBody $function $(if ($overrides.ContainsKey($function.Name)) { $overrides[$function.Name] } else { $null })
            Add-Step07Stub $builder $function $body 3
        }
        [void]$builder.AppendLine("`t`t}")
        [void]$builder.AppendLine()
    }

    [void]$builder.AppendLine("`t`t`$teststep $TcNum.1 {")
    [void]$builder.AppendLine("`t`t`t`$name `"Test step 1`"")
    return $builder.ToString()
}

function Build-TestObjectStubs {
    param([object[]]$PlanStubFunctionNames = @(), [hashtable]$FunctionRegistry)

    $functions = Get-EffectiveStubs $PlanStubFunctionNames $FunctionRegistry
    if (-not $functions.Count) { return '' }

    $overrides = Parse-StubOverrides $PlanStubFunctionNames
    $builder = New-Object System.Text.StringBuilder
    [void]$builder.AppendLine("`t`$stubfunctions {")

    foreach ($function in $functions) {
        $override = if ($overrides.ContainsKey($function.Name)) { $overrides[$function.Name] } else { $null }
        $body = if ($null -ne $override) { Get-Step07StubBody $function $override }
                else { Get-Step07StubBody $function $null -CoveragePolicy }
        Add-Step07Stub $builder $function $body 2
    }

    [void]$builder.AppendLine("`t}")
    [void]$builder.AppendLine()
    return $builder.ToString()
}
