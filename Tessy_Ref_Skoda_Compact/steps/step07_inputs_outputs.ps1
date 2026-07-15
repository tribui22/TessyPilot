# ============================================================================
# STEP 07C - Inputs / Outputs / Calltrace Renderer
# ============================================================================
# Dot-sourced by step07_generate_testcases.ps1.
# Self-contained: no secondary engine/implementation file is required.
# ============================================================================

function ConvertTo-Step07Bool {
    param($Value, [bool]$Default = $true)
    if ($null -eq $Value) { return $Default }
    if ($Value -is [bool]) { return $Value }
    switch -Regex (([string]$Value).Trim()) {
        '^(?i:true|1|yes|on)$'  { return $true }
        '^(?i:false|0|no|off)$' { return $false }
        default                  { return $Default }
    }
}

function Get-Step07DefaultValue {
    param($Variable)

    $decl = [string](if ($Variable.FullDeclaration) { $Variable.FullDeclaration } else { $Variable.Type })
    if ($decl -match '\b(bool|boolean_t)\b') { return 'FALSE' }
    if ($decl -match '\b(float|double)\b')   { return '0.0' }
    if ($decl -match '\*')                   { return '0' }
    return '0'
}

# Public compatibility API retained.
function Get-VarDefaultValue {
    param($VarInfo, [hashtable]$OverrideMap = @{})
    if ($OverrideMap.ContainsKey([string]$VarInfo.Name)) {
        return [string]$OverrideMap[[string]$VarInfo.Name]
    }
    return Get-Step07DefaultValue $VarInfo
}

function Add-Step07PointerMembers {
    param(
        [hashtable]$Map,
        [object[]]$Members,
        [string]$Prefix = ''
    )

    foreach ($member in @($Members)) {
        if ($null -eq $member) { continue }
        $name = if ($member.Name) { [string]$member.Name } elseif ($member.Path) { [string]$member.Path } else { '' }
        if (-not $name) { continue }
        $path = if ($Prefix) { "$Prefix.$name" } else { $name }

        if ($member.PSObject.Properties.Name -contains 'Value') { $Map[$path] = [string]$member.Value }
        elseif ($member.PSObject.Properties.Name -contains 'V') { $Map[$path] = [string]$member.V }

        if ($member.Members) { Add-Step07PointerMembers $Map @($member.Members) $path }
    }
}

# Public compatibility API retained.
function Parse-SetValuesOverrides {
    param([object[]]$SetValues = @())

    $result = [ordered]@{}
    $script:Step07PointerObjects = @{}
    $script:Step07MemberValues = @{}
    $script:Step07IndexedValues = @{}

    foreach ($entry in @($SetValues)) {
        if ($null -eq $entry) { continue }

        if ($entry -isnot [string] -and $entry.PointerName) {
            $name = [string]$entry.PointerName
            $members = @{}
            Add-Step07PointerMembers $members @($entry.Members)
            $script:Step07PointerObjects[$name] = @{
                Allocate      = ConvertTo-Step07Bool $entry.Allocate $true
                DynamicObject = if ($entry.DynamicObject) { [string]$entry.DynamicObject } else { "target_$name" }
                Members       = $members
            }
            continue
        }

        $text = if ($entry -is [string]) {
            $entry.Trim()
        } else {
            $path = if ($entry.Path) { $entry.Path } elseif ($entry.N) { $entry.N } elseif ($entry.Name) { $entry.Name } else { $null }
            $value = if ($entry.PSObject.Properties.Name -contains 'Value') { $entry.Value } elseif ($entry.PSObject.Properties.Name -contains 'V') { $entry.V } else { $null }
            if ($path -and $null -ne $value) { "$path = $value" } else { '' }
        }
        if (-not $text) { continue }
        $text = $text -replace '\s*->\s*', '.'

        if ($text -match '^([A-Za-z_]\w*)\[(\d+)\]\s*=\s*(.+)$') {
            $base = $Matches[1]
            if (-not $script:Step07IndexedValues.ContainsKey($base)) { $script:Step07IndexedValues[$base] = @{} }
            $script:Step07IndexedValues[$base][$Matches[2]] = $Matches[3].Trim()
            continue
        }
        if ($text -match '^([A-Za-z_]\w*)\.([A-Za-z0-9_.]+)\s*=\s*(.+)$') {
            $base = $Matches[1]
            if (-not $script:Step07MemberValues.ContainsKey($base)) { $script:Step07MemberValues[$base] = @{} }
            $script:Step07MemberValues[$base][$Matches[2]] = $Matches[3].Trim()
            continue
        }
        if ($text -match '^(?:[A-Za-z_]\w*::)?([A-Za-z_]\w*)(?:#\d+)?(?:\[\d+\])?\s*=\s*(.+)$') {
            $result[$Matches[1]] = $Matches[2].Trim()
        }
    }
    return $result
}

# Public compatibility API retained for legacy condition strings.
function Resolve-ConditionValue {
    param([string]$CondExpr, [string]$VarName, [bool]$IsTrue, [string]$VarDecl)
    if ($VarDecl -match '\b(bool|boolean_t)\b') { return $(if ($IsTrue) { 'TRUE' } else { 'FALSE' }) }
    if ($CondExpr -match "(?:0U?\s*==\s*$([regex]::Escape($VarName))|$([regex]::Escape($VarName))\s*==\s*0U?)") {
        return $(if ($IsTrue) { '0' } else { '1' })
    }
    return $(if ($IsTrue) { '1' } else { '0' })
}

function Add-Step07ScalarOrArray {
    param([Text.StringBuilder]$Builder, $Variable, [hashtable]$Overrides, [int]$Indent = 4)

    $name = if ($Variable.FullName) { [string]$Variable.FullName } else { [string]$Variable.Name }
    $short = [string]$Variable.Name
    $tabs = "`t" * $Indent
    $default = Get-VarDefaultValue $Variable $Overrides

    if ($script:Step07IndexedValues.ContainsKey($short)) {
        foreach ($item in ($script:Step07IndexedValues[$short].GetEnumerator() | Sort-Object { [int]$_.Key })) {
            [void]$Builder.AppendLine("$tabs$name[$($item.Key)] = $($item.Value)")
        }
    } elseif ([int]$Variable.ArrayLength -gt 0) {
        [void]$Builder.AppendLine("$tabs$name[0] = $default")
    } else {
        [void]$Builder.AppendLine("$tabs$name = $default")
    }
}

function Add-Step07Pointer {
    param([Text.StringBuilder]$Builder, $Variable, [hashtable]$Overrides, [int]$Indent = 4)

    $name = [string]$Variable.Name
    $renderedName = if ($Variable.FullName) { [string]$Variable.FullName } else { $name }
    $spec = if ($script:Step07PointerObjects.ContainsKey($name)) { $script:Step07PointerObjects[$name] } else { $null }
    $tabs = "`t" * $Indent

    if ($spec -and -not $spec.Allocate) {
        [void]$Builder.AppendLine("$tabs$renderedName = 0")
        return
    }

    $target = if ($spec) { $spec.DynamicObject } else { "target_$name" }
    [void]$Builder.AppendLine("$tabs$renderedName = $target[0]")

    $members = @{}
    if ($script:Step07MemberValues.ContainsKey($name)) {
        foreach ($key in $script:Step07MemberValues[$name].Keys) { $members[$key] = $script:Step07MemberValues[$name][$key] }
    }
    if ($spec) {
        foreach ($key in $spec.Members.Keys) { $members[$key] = $spec.Members[$key] }
    }
    foreach ($key in ($members.Keys | Sort-Object)) {
        [void]$Builder.AppendLine("$tabs$target[0].$key = $($members[$key])")
    }
}

function Add-Step07Inputs {
    param([Text.StringBuilder]$Builder, [hashtable]$Overrides)

    $variables = @($script:globalVariablesInfo) + @($script:externalVariablesInfo) + @($script:parametersInfo)
    $inputs = @($variables | Where-Object { $_.Passing -match 'IN|INOUT' })
    if (-not $inputs.Count) { return }

    [void]$Builder.AppendLine("`t`t`t`$inputs {")
    foreach ($variable in $inputs) {
        $decl = [string](if ($variable.FullDeclaration) { $variable.FullDeclaration } else { $variable.Type })
        if ($decl -match '\*') { Add-Step07Pointer $Builder $variable $Overrides }
        else { Add-Step07ScalarOrArray $Builder $variable $Overrides }
    }
    [void]$Builder.AppendLine("`t`t`t}")
}

function Add-Step07Outputs {
    param([Text.StringBuilder]$Builder, [hashtable]$Overrides)

    $variables = @($script:globalVariablesInfo) + @($script:externalVariablesInfo) + @($script:parametersInfo)
    $outputs = @($variables | Where-Object { $_.Passing -match 'OUT|INOUT' })
    $hasReturn = $script:returnType -and $script:returnType -notmatch '^\(?void\)?$'
    if (-not $hasReturn -and -not $outputs.Count) { return }

    [void]$Builder.AppendLine("`t`t`t`$outputs {")
    if ($hasReturn -and $script:returnType -notmatch '\b(struct|union)\b') {
        $value = if ($Overrides.ContainsKey('return')) { $Overrides['return'] } else { '0' }
        [void]$Builder.AppendLine("`t`t`t`treturn = $value")
    }
    foreach ($variable in $outputs) {
        Add-Step07ScalarOrArray $Builder $variable @{}
    }
    [void]$Builder.AppendLine("`t`t`t}")
}

function Build-TCInputsOutputs {
    param(
        [Parameter(Mandatory)][ValidateRange(1,[int]::MaxValue)][int]$TcNum,
        [Parameter(Mandatory)][ValidateRange(1,[int]::MaxValue)][int]$StepNum,
        [object[]]$SetValues = @(),
        [object[]]$StubFunctionNames = @(),
        [string]$TCDescription = ''
    )

    $overrides = Parse-SetValuesOverrides @($SetValues)
    $name = ($TCDescription -replace '^TC\d+:\s*','' -replace '[^\x20-\x7E]','?').Trim()
    if ($name.Length -gt 120) { $name = $name.Substring(0,120) }

    $builder = [Text.StringBuilder]::new()
    [void]$builder.AppendLine("`t`t`$teststep 1.$StepNum {")
    [void]$builder.AppendLine("`t`t`t`$name `"$name`"")

    if (@($StubFunctionNames).Count) {
        $stubOverrides = Parse-StubOverrides @($StubFunctionNames)
        [void]$builder.AppendLine("`t`t`t`$stubfunctions {")
        foreach ($stubName in ($stubOverrides.Keys | Sort-Object)) {
            if (-not $script:allFunctions.ContainsKey($stubName)) {
                $script:allFunctions[$stubName] = @{Name=$stubName;ReturnType='int';Parameters='void'}
            }
            $stub = $script:allFunctions[$stubName]
            if ($stub.ReturnType -eq 'void') { continue }
            $raw = $stubOverrides[$stubName]
            $body = if ($raw -and $raw.StartsWith('__BODY__|')) { $raw.Substring(9) }
                    elseif ($raw) { "return $(Normalize-StubReturnValue $stub.ReturnType $raw);" }
                    else { Get-StubDefaultReturn $stub.ReturnType }
            [void]$builder.AppendLine("`t`t`t`t$($stub.ReturnType) $($stub.Name)($($stub.Parameters)) '''")
            if ($body) { [void]$builder.AppendLine("`t`t`t`t`t$body") }
            [void]$builder.AppendLine("`t`t`t`t'''")
        }
        [void]$builder.AppendLine("`t`t`t}")
    }

    Add-Step07Inputs $builder $overrides
    Add-Step07Outputs $builder $overrides
    [void]$builder.AppendLine("`t`t`t`$calltrace {")
    [void]$builder.AppendLine("`t`t`t`t*** Ignore Call Trace ***")
    [void]$builder.AppendLine("`t`t`t}")
    [void]$builder.AppendLine("`t`t}")
    return $builder.ToString()
}
