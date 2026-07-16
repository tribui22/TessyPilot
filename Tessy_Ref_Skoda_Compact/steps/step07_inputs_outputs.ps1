# ============================================================================
# STEP 07C - Inputs / Outputs / Calltrace Renderer
# ============================================================================
# Dot-sourced by step07_generate_testcases.ps1.
# Windows PowerShell 5.1 compatible. No secondary engine is required.
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

    $decl = [string]$Variable.Type
    if ($Variable.FullDeclaration) {
        $decl = [string]$Variable.FullDeclaration
    }

    if ($decl -match '\b(bool|boolean_t)\b') { return 'FALSE' }
    if ($decl -match '\b(float|double)\b')   { return '0.0' }
    if ($decl -match '\*')                   { return '0' }
    return '0'
}

function Get-VarDefaultValue {
    param($VarInfo, [hashtable]$OverrideMap = @{})
    if ($OverrideMap.ContainsKey([string]$VarInfo.Name)) {
        return [string]$OverrideMap[[string]$VarInfo.Name]
    }
    return Get-Step07DefaultValue $VarInfo
}

function Add-Step07PointerMembers {
    param([hashtable]$Map, [object[]]$Members, [string]$Prefix = '')

    foreach ($member in @($Members)) {
        if ($null -eq $member) { continue }

        $name = ''
        if ($member.Name) { $name = [string]$member.Name }
        elseif ($member.Path) { $name = [string]$member.Path }
        if (-not $name) { continue }

        $path = $name
        if ($Prefix) { $path = "$Prefix.$name" }

        if ($member.PSObject.Properties.Name -contains 'Value') {
            $Map[$path] = [string]$member.Value
        } elseif ($member.PSObject.Properties.Name -contains 'V') {
            $Map[$path] = [string]$member.V
        }

        if ($member.Members) {
            Add-Step07PointerMembers $Map @($member.Members) $path
        }
    }
}

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

            $dynamicObject = "target_$name"
            if ($entry.DynamicObject) { $dynamicObject = [string]$entry.DynamicObject }

            $script:Step07PointerObjects[$name] = @{
                Allocate      = ConvertTo-Step07Bool $entry.Allocate $true
                DynamicObject = $dynamicObject
                Members       = $members
            }
            continue
        }

        $text = ''
        if ($entry -is [string]) {
            $text = $entry.Trim()
        } else {
            $path = $null
            if ($entry.Path) { $path = $entry.Path }
            elseif ($entry.N) { $path = $entry.N }
            elseif ($entry.Name) { $path = $entry.Name }

            $value = $null
            if ($entry.PSObject.Properties.Name -contains 'Value') { $value = $entry.Value }
            elseif ($entry.PSObject.Properties.Name -contains 'V') { $value = $entry.V }

            if ($path -and $null -ne $value) { $text = "$path = $value" }
        }

        if (-not $text) { continue }
        $text = $text -replace '\s*->\s*', '.'

        if ($text -match '^([A-Za-z_]\w*)\[(\d+)\]\s*=\s*(.+)$') {
            $base = $Matches[1]
            if (-not $script:Step07IndexedValues.ContainsKey($base)) {
                $script:Step07IndexedValues[$base] = @{}
            }
            $script:Step07IndexedValues[$base][$Matches[2]] = $Matches[3].Trim()
            continue
        }

        if ($text -match '^([A-Za-z_]\w*)\.([A-Za-z0-9_.]+)\s*=\s*(.+)$') {
            $base = $Matches[1]
            if (-not $script:Step07MemberValues.ContainsKey($base)) {
                $script:Step07MemberValues[$base] = @{}
            }
            $script:Step07MemberValues[$base][$Matches[2]] = $Matches[3].Trim()
            continue
        }

        if ($text -match '^(?:[A-Za-z_]\w*::)?([A-Za-z_]\w*)(?:#\d+)?(?:\[\d+\])?\s*=\s*(.+)$') {
            $result[$Matches[1]] = $Matches[2].Trim()
        }
    }
    return $result
}

function Resolve-ConditionValue {
    param([string]$CondExpr, [string]$VarName, [bool]$IsTrue, [string]$VarDecl)

    if ($VarDecl -match '\b(bool|boolean_t)\b') {
        if ($IsTrue) { return 'TRUE' }
        return 'FALSE'
    }

    if ($CondExpr -match "(?:0U?\s*==\s*$([regex]::Escape($VarName))|$([regex]::Escape($VarName))\s*==\s*0U?)") {
        if ($IsTrue) { return '0' }
        return '1'
    }

    if ($IsTrue) { return '1' }
    return '0'
}

function Add-Step07ScalarOrArray {
    param([Text.StringBuilder]$Builder, $Variable, [hashtable]$Overrides, [int]$Indent = 4)

    $name = [string]$Variable.Name
    if ($Variable.FullName) { $name = [string]$Variable.FullName }

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
    $renderedName = $name
    if ($Variable.FullName) { $renderedName = [string]$Variable.FullName }

    $spec = $null
    if ($script:Step07PointerObjects.ContainsKey($name)) {
        $spec = $script:Step07PointerObjects[$name]
    }

    $tabs = "`t" * $Indent
    if ($spec -and -not $spec.Allocate) {
        [void]$Builder.AppendLine("$tabs$renderedName = 0")
        return
    }

    $target = "target_$name"
    if ($spec) { $target = $spec.DynamicObject }
    [void]$Builder.AppendLine("$tabs$renderedName = $target[0]")

    $members = @{}
    if ($script:Step07MemberValues.ContainsKey($name)) {
        foreach ($key in $script:Step07MemberValues[$name].Keys) {
            $members[$key] = $script:Step07MemberValues[$name][$key]
        }
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
        $decl = [string]$variable.Type
        if ($variable.FullDeclaration) { $decl = [string]$variable.FullDeclaration }

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
        $value = '0'
        if ($Overrides.ContainsKey('return')) { $value = $Overrides['return'] }
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

    $builder = New-Object System.Text.StringBuilder
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
            $body = Get-StubDefaultReturn $stub.ReturnType
            if ($raw -and $raw.StartsWith('__BODY__|')) {
                $body = $raw.Substring(9)
            } elseif ($raw) {
                $body = "return $(Normalize-StubReturnValue $stub.ReturnType $raw);"
            }

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
