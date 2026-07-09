# ============================================================================
# STEP 7c: TC Inputs / Outputs / Calltrace Generator (Plan-based)
# Defines: Parse-SetValuesOverrides, Resolve-ConditionValue,
#          Get-VarDefaultValue, Build-TCInputsOutputs
# Dot-sourced by step7_generate_testcases.ps1
# Uses script-level: $globalVariablesInfo, $externalVariablesInfo,
#                    $parametersInfo, $returnType, $SourceDir, $TestObject
# Parameters: -TcNum, -SetValues
# Source: _testcase_plan.json "SetValues" field
#
# SetValues entries are like either:
#   "// condition[0]: TRUE == isDriverPORRequested_en[idx] -> set so that it is TRUE"
# or object entries such as:
#   { "Path": "chipaddress[0]", "Value": "0" }
# For variables matching known interface variables, the correct value is derived.
# All other interface variables get type-appropriate default values.
# ============================================================================

# ---------------------------------------------------------------------------
# Parse enum members from the already-loaded _conditions_after_passing.c
# content ($rawConditionsContent, available because this file is dot-sourced).
# Much faster than scanning all source files.
# ---------------------------------------------------------------------------
$script:condFileEnumCache = @{}
$script:condFileStructCache = @{}
# Per-TC indexed overrides for pointer variables; cleared at start of each Parse-SetValuesOverrides call
$script:_pointerIndexedOverrides = @{}
# Per-TC pointer member overrides, e.g. config_ptr->field or config_ptr.field
$script:_pointerMemberOverrides = @{}
# Per-TC pointer object overrides from JSON schema (PointerName/Allocate/DynamicObject/Members)
$script:_pointerObjectOverrides = @{}

function ConvertTo-BoolFlag {
    param(
        [Parameter(Mandatory=$false)]$Value,
        [bool]$Default = $true
    )

    if ($null -eq $Value) { return $Default }
    if ($Value -is [bool]) { return $Value }

    $s = [string]$Value
    if ([string]::IsNullOrWhiteSpace($s)) { return $Default }
    $v = $s.Trim().ToLowerInvariant()

    if ($v -in @('true','1','yes','y','on')) { return $true }
    if ($v -in @('false','0','no','n','off')) { return $false }
    return $Default
}

function Flatten-PointerMembers {
    param(
        [object[]]$Members,
        [string]$ParentPath = ''
    )

    $flat = @{}
    foreach ($m in @($Members)) {
        if ($null -eq $m) { continue }

        $name = $null
        if ($m -is [string]) {
            continue
        }
        if ($m.PSObject.Properties['Name']) { $name = [string]$m.Name }
        elseif ($m.PSObject.Properties['N']) { $name = [string]$m.N }
        elseif ($m.PSObject.Properties['Path']) { $name = [string]$m.Path }
        if ([string]::IsNullOrWhiteSpace($name)) { continue }

        $currPath = if ([string]::IsNullOrWhiteSpace($ParentPath)) { $name.Trim() } else { "$ParentPath.$($name.Trim())" }

        $hasValue = $false
        $val = $null
        if ($m.PSObject.Properties['V']) { $val = [string]$m.V; $hasValue = $true }
        elseif ($m.PSObject.Properties['Value']) { $val = [string]$m.Value; $hasValue = $true }

        if ($hasValue) {
            $flat[$currPath] = $val.Trim()
        }

        $childMembers = @()
        if ($m.PSObject.Properties['Members']) { $childMembers = @($m.Members) }
        elseif ($m.PSObject.Properties['MemberList']) { $childMembers = @($m.MemberList) }

        if ($childMembers.Count -gt 0) {
            $childFlat = Flatten-PointerMembers -Members $childMembers -ParentPath $currPath
            foreach ($k in $childFlat.Keys) {
                $flat[$k] = $childFlat[$k]
            }
        }
    }

    return $flat
}

function Get-EnumMembersFromConditionsFile {
    param([string]$TypeName)

    if ($script:condFileEnumCache.ContainsKey($TypeName)) {
        return $script:condFileEnumCache[$TypeName]
    }

    $members = @()
    $src = if ($rawConditionsContent) { $rawConditionsContent } else { '' }
    if (-not $src) {
        $script:condFileEnumCache[$TypeName] = $members
        return $members
    }

    $esc = [regex]::Escape($TypeName)
    $enumBody = $null

    # typedef enum [optional_tag] { ... } TypeName ;
    if ($src -match "(?ms)typedef\s+enum\b[^{]*\{([^}]+)\}\s*$esc\s*;") {
        $enumBody = $Matches[1]
    }
    # enum TypeName { ... }
    elseif ($src -match "(?ms)\benum\s+$esc\s*\{([^}]+)\}") {
        $enumBody = $Matches[1]
    }

    if ($enumBody) {
        foreach ($line in ($enumBody -split '[\r\n]+')) {
            $t = ($line -replace '/\*.*?\*/', '' -replace '//.*$', '').Trim().TrimEnd(',').Trim()
            if ($t -eq '') { continue }
            # Member identifier, optionally followed by = value
            if ($t -match '^([A-Za-z_][A-Za-z0-9_]*)') {
                $members += $Matches[1]
            }
        }
    }

    $script:condFileEnumCache[$TypeName] = $members
    return $members
}

function Get-StructMembersFromConditionsFile {
    param([string]$TypeName)

    if ($script:condFileStructCache.ContainsKey($TypeName)) {
        return $script:condFileStructCache[$TypeName]
    }

    $members = @()
    $src = if ($rawConditionsContent) { $rawConditionsContent } else { '' }
    if (-not $src) {
        $script:condFileStructCache[$TypeName] = $members
        return $members
    }

    $esc = [regex]::Escape($TypeName)
    $structBody = $null

    # typedef struct [optional_tag] { ... } TypeName ;
    if ($src -match "(?ms)typedef\s+struct\b[^\{]*\{([^}]+)\}\s*$esc\s*;") {
        $structBody = $Matches[1]
    }
    # struct TypeName { ... }
    elseif ($src -match "(?ms)\bstruct\s+$esc\s*\{([^}]+)\}") {
        $structBody = $Matches[1]
    }

    if ($structBody) {
        foreach ($line in ($structBody -split '[\r\n]+')) {
            $t = ($line -replace '/\*.*?\*/', '' -replace '//.*$', '').Trim().TrimEnd(';').Trim()
            if ($t -eq '') { continue }
            if ($t -match '^(.+?)\s+([A-Za-z_][A-Za-z0-9_]*)\s*(\[[^\]]*\])?$') {
                $mType = $Matches[1].Trim()
                $mName = $Matches[2].Trim()
                $arrDecl = if ($Matches[3]) { [string]$Matches[3] } else { '' }
                $arrLen = 0
                if ($arrDecl -match '\[(\d+)\]') { $arrLen = [int]$Matches[1] }
                if ($mName -and ($members | Where-Object { $_.Name -eq $mName }).Count -eq 0) {
                    $members += @{ Name = $mName; FullDeclaration = $mType; Type = $mType; Passing = 'IN'; ArrayLength = $arrLen }
                }
            }
        }
    }

    $script:condFileStructCache[$TypeName] = $members
    return $members
}

function Get-PointerBaseTypeName {
    param([string]$Declaration)

    if ([string]::IsNullOrWhiteSpace($Declaration)) { return '' }
    $d = ($Declaration -replace '\s+', ' ').Trim()
    $d = ($d -replace '\bconst\b|\bvolatile\b|\bstatic\b|\bextern\b', '').Trim()

    # Case 1: "Type * varName" / "Type ** varName"
    if ($d -match '^(.+?)\s*(\*+)\s*[A-Za-z_][A-Za-z0-9_]*$') {
        return $Matches[1].Trim()
    }
    # Case 2: "Type *" / "Type **"
    if ($d -match '^(.+?)\s*(\*+)$') {
        return $Matches[1].Trim()
    }
    return ''
}

function Get-PointerDepthFromDeclaration {
    param([string]$Declaration)

    if ([string]::IsNullOrWhiteSpace($Declaration)) { return 0 }
    $d = ($Declaration -replace '\s+', ' ').Trim()
    $d = ($d -replace '\bconst\b|\bvolatile\b|\bstatic\b|\bextern\b', '').Trim()

    if ($d -match '^.+?\s*(\*+)\s*[A-Za-z_][A-Za-z0-9_]*$') {
        return $Matches[1].Length
    }
    if ($d -match '^.+?\s*(\*+)$') {
        return $Matches[1].Length
    }
    return 0
}

function Get-TypeBaseName {
    param([string]$Declaration)

    if ([string]::IsNullOrWhiteSpace($Declaration)) { return '' }
    $d = ($Declaration -replace '\bconst\b|\bvolatile\b|\bstatic\b|\bextern\b|\bunsigned\b|\bsigned\b', '').Trim()
    $d = ($d -replace '\*+', '' -replace '\[.*$', '' -replace '\s+', ' ').Trim()
    return $d
}

function Expand-InterfaceMembers {
    param(
        [array]$Members,
        [string]$Prefix = ''
    )

    $flat = @()
    foreach ($m in @($Members)) {
        if ($null -eq $m) { continue }
        if ($m.Passing -match 'IRRELEVANT') { continue }
        if (-not $m.Name) { continue }

        $seg = if ($m.ArrayLength -and [int]$m.ArrayLength -gt 0) { "$($m.Name)[0]" } else { "$($m.Name)" }
        $path = if ([string]::IsNullOrWhiteSpace($Prefix)) { $seg } else { "$Prefix.$seg" }

        if ($m.Members -and @($m.Members).Count -gt 0) {
            $flat += Expand-InterfaceMembers -Members $m.Members -Prefix $path
        } else {
            $flat += @{ Name = $path; FullDeclaration = if ($m.FullDeclaration) { $m.FullDeclaration } else { $m.Type }; Type = $m.Type; Passing = if ($m.Passing) { $m.Passing } else { 'IN' } }
        }
    }
    return $flat
}

function Expand-StructMembersRecursive {
    param(
        [string]$TypeName,
        [string]$Prefix = '',
        [int]$Depth = 0,
        [hashtable]$SeenTypes
    )

    if (-not $SeenTypes) { $SeenTypes = @{} }
    if ([string]::IsNullOrWhiteSpace($TypeName)) { return @() }
    if ($Depth -ge 6) { return @() }

    $baseType = Get-TypeBaseName -Declaration $TypeName
    if ([string]::IsNullOrWhiteSpace($baseType)) { return @() }
    if ($SeenTypes.ContainsKey($baseType)) { return @() }

    $members = @(Get-StructMembersFromConditionsFile -TypeName $baseType)
    if ($members.Count -eq 0) { return @() }

    $SeenTypes[$baseType] = $true
    $flat = @()
    foreach ($m in $members) {
        if (-not $m.Name) { continue }
        $seg = if ($m.ArrayLength -and [int]$m.ArrayLength -gt 0) { "$($m.Name)[0]" } else { "$($m.Name)" }
        $path = if ([string]::IsNullOrWhiteSpace($Prefix)) { $seg } else { "$Prefix.$seg" }

        $mDecl = if ($m.FullDeclaration) { [string]$m.FullDeclaration } else { [string]$m.Type }
        $mPtrDepth = Get-PointerDepthFromDeclaration -Declaration $mDecl
        $nestedType = Get-TypeBaseName -Declaration $mDecl
        $nestedStructMembers = @()
        if ($mPtrDepth -eq 0) {
            $nestedStructMembers = @(Get-StructMembersFromConditionsFile -TypeName $nestedType)
        }

        if ($mPtrDepth -eq 0 -and $nestedStructMembers.Count -gt 0) {
            $flat += Expand-StructMembersRecursive -TypeName $nestedType -Prefix $path -Depth ($Depth + 1) -SeenTypes $SeenTypes
        } else {
            $flat += @{ Name = $path; FullDeclaration = $mDecl; Type = $mDecl; Passing = 'IN' }
        }
    }

    $SeenTypes.Remove($baseType) | Out-Null
    return $flat
}

function Get-FullPointerMemberList {
    param(
        [string]$PointerDeclaration,
        [array]$InterfaceMembers
    )

    $merged = @()
    $seen = @{}

    $ifaceFlattened = @(Expand-InterfaceMembers -Members $InterfaceMembers)
    foreach ($m in $ifaceFlattened) {
        if ($null -eq $m -or -not $m.Name) { continue }
        if (-not $seen.ContainsKey($m.Name)) {
            $merged += $m
            $seen[$m.Name] = $true
        }
    }

    $typeName = Get-PointerBaseTypeName -Declaration $PointerDeclaration
    if ($typeName) {
        $extra = Expand-StructMembersRecursive -TypeName $typeName -Prefix '' -Depth 0 -SeenTypes @{}
        foreach ($m in @($extra)) {
            if (-not $m.Name) { continue }
            if (-not $seen.ContainsKey($m.Name)) {
                $merged += $m
                $seen[$m.Name] = $true
            }
        }
    }

    return $merged
}

function Emit-PointerTargetInputLines {
    param(
        [string]$VariableName,
        [string]$TargetName,
        [array]$InitMembers,
        [hashtable]$MemberOverrides,
        [hashtable]$OverrideMap,
        [string]$FallbackValue,
        [scriptblock]$DefaultValueResolver,
        [bool]$AllocatePointedObject = $true,
        [int]$PointerDepth = 1
    )

    $lines = @()

    if (-not $AllocatePointedObject) {
        # Explicit de-allocation request from testcase plan schema.
        $lines += "`t`t`t`t$VariableName = 0"
        return ($lines -join "`n") + "`n"
    }

    # Bind pointer to a concrete pointed object first. This mirrors Tessy's
    # manual "Create Pointed Object" workflow and materializes Dynamics.
    $depth = if ($PointerDepth -gt 0) { $PointerDepth } else { 1 }
    $lines += "`t`t`t`t$VariableName = $TargetName`[0`]"

    $finalTargetName = $TargetName
    if ($depth -gt 1) {
        $carrier = $TargetName
        for ($lvl = 2; $lvl -le $depth; $lvl++) {
            $nextTarget = if ($lvl -eq $depth) { "${TargetName}_leaf" } else { "${TargetName}_l$($lvl - 1)" }
            $lines += "`t`t`t`t$carrier`[0`] = $nextTarget`[0`]"
            $carrier = $nextTarget
        }
        $finalTargetName = $carrier
    }

    $emitMemberAssignments = $true

    $appliedMembers = @{}
    if ($emitMemberAssignments -and @($InitMembers).Count -gt 0) {
        foreach ($mem in @($InitMembers)) {
            if ($null -eq $mem) { continue }
            if ($mem.Passing -match 'IRRELEVANT') { continue }
            $mName = $mem.Name
            if (-not $mName) { continue }

            $mVal = if ($DefaultValueResolver) { & $DefaultValueResolver $mem } else { '0' }
            if ($MemberOverrides -and $MemberOverrides.ContainsKey($mName)) {
                $mVal = $MemberOverrides[$mName]
            }
            $lines += "`t`t`t`t$finalTargetName`[0`].$mName = $mVal"
            $appliedMembers[$mName] = $true
        }
    }

    # Apply explicit overrides (including nested paths) after defaults so testcase values win.
    if ($emitMemberAssignments -and $MemberOverrides -and $MemberOverrides.Count -gt 0) {
        foreach ($entry in ($MemberOverrides.GetEnumerator() | Sort-Object Name)) {
            if ($appliedMembers.ContainsKey($entry.Name)) { continue }
            $lines += "`t`t`t`t$finalTargetName`[0`].$($entry.Name) = $($entry.Value)"
        }
    }

    if ($emitMemberAssignments -and @($InitMembers).Count -eq 0 -and (-not $MemberOverrides -or $MemberOverrides.Count -eq 0)) {
        $lines += "`t`t`t`t$finalTargetName`[0`] = $FallbackValue"
    }

    return ($lines -join "`n") + "`n"
}

# ---------------------------------------------------------------------------
# Get a type-appropriate default value for a variable (string suitable for .script)
# ---------------------------------------------------------------------------
function Get-VarDefaultValue {
    param(
        [hashtable]$VarInfo,    # the interface variable info object
        [hashtable]$OverrideMap # optional: varShortName -> overrideValue
    )
    $name = $VarInfo.Name
    # Check for override
    if ($OverrideMap -and $OverrideMap.Contains($name)) {
        return $OverrideMap[$name]
    }
    $decl = if ($VarInfo.FullDeclaration) { $VarInfo.FullDeclaration } else { $VarInfo.Type }

    # boolean_t / bool -> FALSE
    if ($decl -match '\bboolean_t\b|\bbool\b') { return 'FALSE' }
    # float / double -> 0.0
    if ($decl -match '\b(float|double)\b') { return '0.0' }
    # Explicit "enum TypeName" form -> first enum member
    if ($decl -match '(?:^|\s)enum\s+(\w+)') {
        $members = Get-EnumMembersFromConditionsFile -TypeName $Matches[1]
        if ($members.Count -gt 0) { return $members[0] }
        return '0'
    }
    # Typedef'd enum: extract bare type name and try enum lookup from conditions file.
    # Skip known numeric / standard C types.
    $knownNumericTypes = @('u8','u16','u32','u64','s8','s16','s32',
                           'uint8_t','uint16_t','uint32_t','uint64_t',
                           'int8_t','int16_t','int32_t','int64_t',
                           'int','char','short','long','unsigned','signed',
                           'size_t','ptrdiff_t','void')
    $typeName = ($decl -replace '\bconst\b|\bvolatile\b|\bstatic\b|\bextern\b|\bunsigned\b|\bsigned\b', '' `
                       -replace '\*.*$', '' `
                       -replace '\[.*$', '' `
                       -replace '\s+', '').Trim()
    if ($typeName -and $typeName -notin $knownNumericTypes) {
        $members = Get-EnumMembersFromConditionsFile -TypeName $typeName
        if ($members.Count -gt 0) { return $members[0] }
    }
    # int / char / everything else -> 0
    return '0'
}

# ---------------------------------------------------------------------------
# Parse SetValues array -> hashtable { shortVarName -> value }
# Only matches interface variables (global, external, parameter).
# ---------------------------------------------------------------------------
function Parse-SetValuesOverrides {
    param([object[]]$SetValues)

    $allIfaceVars = @()
    $allIfaceVars += $globalVariablesInfo | Select-Object -Property Name, FullDeclaration
    $allIfaceVars += $externalVariablesInfo | Select-Object -Property Name, FullDeclaration
    $allIfaceVars += $parametersInfo | ForEach-Object {
        @{ Name = $_.Name; FullDeclaration = $_.Type }
    }

    # Reset per-TC pointer overrides
    $script:_pointerIndexedOverrides = @{}
    $script:_pointerMemberOverrides = @{}
    $script:_pointerObjectOverrides = @{}

    $overrides = [ordered]@{}
    foreach ($raw in $SetValues) {
        if ($null -eq $raw) { continue }

        $sv = $null
        if ($raw -is [string]) {
            $sv = $raw
        } else {
            # New pointer object schema (preferred):
            # {
            #   "PointerName": "config_ptr",
            #   "Allocate": true,
            #   "DynamicObject": "target_config_ptr",
            #   "Members": [ {"Name":"field","Value":"1"}, {"Name":"nested","Members":[...]} ]
            # }
            $pointerName = $null
            if ($raw.PSObject.Properties['PointerName']) { $pointerName = [string]$raw.PointerName }
            elseif ($raw.PSObject.Properties['Pointer']) { $pointerName = [string]$raw.Pointer }

            $looksLikePointerObject = ($pointerName -and (
                $raw.PSObject.Properties['DynamicObject'] -or
                $raw.PSObject.Properties['Allocate'] -or
                $raw.PSObject.Properties['Allocated'] -or
                $raw.PSObject.Properties['Members'] -or
                $raw.PSObject.Properties['MemberList']))

            if ($looksLikePointerObject) {
                $allocVal = $null
                if ($raw.PSObject.Properties['Allocate']) { $allocVal = $raw.Allocate }
                elseif ($raw.PSObject.Properties['Allocated']) { $allocVal = $raw.Allocated }

                $allocate = ConvertTo-BoolFlag -Value $allocVal -Default $true

                $dynamicObj = $null
                if ($raw.PSObject.Properties['DynamicObject']) { $dynamicObj = [string]$raw.DynamicObject }
                elseif ($raw.PSObject.Properties['PointedObject']) { $dynamicObj = [string]$raw.PointedObject }
                elseif ($raw.PSObject.Properties['Target']) { $dynamicObj = [string]$raw.Target }
                if ([string]::IsNullOrWhiteSpace($dynamicObj)) { $dynamicObj = "target_$pointerName" }

                $membersRaw = @()
                if ($raw.PSObject.Properties['Members']) { $membersRaw = @($raw.Members) }
                elseif ($raw.PSObject.Properties['MemberList']) { $membersRaw = @($raw.MemberList) }

                $membersMap = Flatten-PointerMembers -Members $membersRaw
                $existingPtrSpec = if ($script:_pointerObjectOverrides.ContainsKey($pointerName)) { $script:_pointerObjectOverrides[$pointerName] } else { $null }
                $mergedMembers = @{}
                if ($existingPtrSpec -and $existingPtrSpec.Members) {
                    foreach ($k in $existingPtrSpec.Members.Keys) { $mergedMembers[$k] = $existingPtrSpec.Members[$k] }
                }
                foreach ($k in $membersMap.Keys) { $mergedMembers[$k] = $membersMap[$k] }

                $resolvedAllocate = if ($null -ne $existingPtrSpec -and -not $allocate) { $false } else { $allocate }
                $resolvedDynamicObject = if (-not [string]::IsNullOrWhiteSpace($dynamicObj)) { $dynamicObj } elseif ($existingPtrSpec -and $existingPtrSpec.DynamicObject) { [string]$existingPtrSpec.DynamicObject } else { "target_$pointerName" }

                $script:_pointerObjectOverrides[$pointerName] = @{
                    PointerName = $pointerName
                    Allocate = $resolvedAllocate
                    DynamicObject = $resolvedDynamicObject
                    Members = $mergedMembers
                }

                if (-not $allocate) {
                    # Keep compatibility with legacy scalar path handling.
                    $overrides[$pointerName] = '0'
                }

                if (-not $script:_pointerMemberOverrides.ContainsKey($pointerName)) {
                    $script:_pointerMemberOverrides[$pointerName] = @{}
                }
                foreach ($k in $membersMap.Keys) {
                    $script:_pointerMemberOverrides[$pointerName][$k] = $membersMap[$k]
                }

                Write-Host "  [SET pointer-object $pointerName allocate=$resolvedAllocate dynamic=$resolvedDynamicObject members=$($mergedMembers.Count)]" -ForegroundColor DarkGreen
                continue
            }

            $path = $null
            $value = $null

            if ($raw.PSObject.Properties['N'])            { $path = [string]$raw.N }
            elseif ($raw.PSObject.Properties['Path'])     { $path = [string]$raw.Path }
            elseif ($raw.PSObject.Properties['Name'])     { $path = [string]$raw.Name }
            elseif ($raw.PSObject.Properties['Variable']) { $path = [string]$raw.Variable }

            if ($raw.PSObject.Properties['V'])           { $value = [string]$raw.V }
            elseif ($raw.PSObject.Properties['Value'])   { $value = [string]$raw.Value }
            elseif ($raw.PSObject.Properties['SetTo'])   { $value = [string]$raw.SetTo }
            elseif ($raw.PSObject.Properties['Return'])  { $value = [string]$raw.Return }

            if ($path) {
                $sv = if ($null -ne $value -and $value -ne '') { "$($path.Trim()) = $($value.Trim())" } else { $path.Trim() }
            }
        }

        if (-not $sv) { continue }

        # Normalize pointer member syntax into dot notation for robust matching.
        # Example: config_ptr->fccMeasureSource_en = 0 -> config_ptr.fccMeasureSource_en = 0
        if ($sv -match '->') {
            $sv = ($sv -replace '\s*->\s*', '.')
        }
        # Pattern 1: "// condition[N]: EXPR -> set so that it is TRUE|FALSE"
        if ($sv -match '//\s*condition\[\d+\]:\s*(.*?)\s*->\s*set so that it is\s*(TRUE|FALSE)') {
            $condExpr = $Matches[1].Trim()
            $isTrue   = $Matches[2] -eq 'TRUE'

            foreach ($v in $allIfaceVars) {
                $vName = $v.Name
                if (-not $vName -or $vName -eq 'UNKNOWN') { continue }
                if ($condExpr -notmatch "\b$([regex]::Escape($vName))\b") { continue }

                # Found matching variable -- determine the value
                $value = Resolve-ConditionValue -CondExpr $condExpr -VarName $vName `
                             -IsTrue $isTrue -VarDecl $v.FullDeclaration
                $overrides[$vName] = $value
                Write-Host "  [SET $vName = $value] from: $sv" -ForegroundColor DarkGreen
                break
            }
            continue
        }
        # Pattern 2: Local static "FunctionName::varName#N[index] = value"
        if ($sv -match '^[A-Za-z_][A-Za-z0-9_]*::([A-Za-z_][A-Za-z0-9_]*)#\d+(?:\[\d+\])?\s*=\s*(.+)$') {
            $varBase = $Matches[1].Trim()
            $value   = $Matches[2].Trim()
            $overrides[$varBase] = $value
            Write-Host "  [SET local-static $varBase = $value] from: $sv" -ForegroundColor DarkGreen
            continue
        }
        # Pattern 3: direct base assignment only (var[index] = value or var = value).
        # Intentionally DO NOT match member paths like "config_ptr.field = x" to avoid
        # collapsing pointer-member overrides into "config_ptr = x".
        if ($sv -match '^([A-Za-z_][A-Za-z0-9_]*)(?:\[[^\]]*\])?\s*=\s*(.+)$') {
            $varBase = $Matches[1].Trim()
            $value   = $Matches[2].Trim()
            $overrides[$varBase] = $value
            Write-Host "  [SET $varBase = $value] from: $sv" -ForegroundColor DarkGreen
        }
        # Capture pointer-member override path: ptr.member[.submember] = value
        if ($sv -match '^([A-Za-z_][A-Za-z0-9_]*)\.([A-Za-z_][A-Za-z0-9_\.]*)\s*=\s*(.+)$') {
            $ptrBase = $Matches[1].Trim()
            $memberPath = $Matches[2].Trim()
            $ptrVal = $Matches[3].Trim()
            if (-not $script:_pointerMemberOverrides.ContainsKey($ptrBase)) {
                $script:_pointerMemberOverrides[$ptrBase] = @{}
            }
            $script:_pointerMemberOverrides[$ptrBase][$memberPath] = $ptrVal
            Write-Host "  [SET pointer-member $ptrBase.$memberPath = $ptrVal] from: $sv" -ForegroundColor DarkGreen
        }
        # Also track per-index values for pointer variables: varname[N] = value
        if ($sv -match '^([A-Za-z_][A-Za-z0-9_]*)\[(\d+)\]\s*=\s*(.+)$') {
            $ptrBase = $Matches[1].Trim()
            $ptrIdx  = [int]$Matches[2]
            $ptrVal  = $Matches[3].Trim()
            if (-not $script:_pointerIndexedOverrides.ContainsKey($ptrBase)) {
                $script:_pointerIndexedOverrides[$ptrBase] = @{}
            }
            $script:_pointerIndexedOverrides[$ptrBase]["$ptrIdx"] = $ptrVal
        }
        # Also capture the leaf field for paths like "struct.field = value" or "var[0].struct.field = value" -> overrides["field"] = value
        # This allows single-level (e.g. internalState_st.State_DRL_PO) as well as deeper paths to be applied correctly.
        if ($sv -match '^[A-Za-z_][A-Za-z0-9_:]*(?:#\d+)?(?:\[\d+\])?(?:\.[A-Za-z_][A-Za-z0-9_]*){1,}\s*=\s*') {
            $leafMatch = [regex]::Match($sv, '\.([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+)$')
            if ($leafMatch.Success) {
                $leafName = $leafMatch.Groups[1].Value.Trim()
                $leafVal  = $leafMatch.Groups[2].Value.Trim()
                if (-not $overrides.Contains($leafName)) {
                    $overrides[$leafName] = $leafVal
                    Write-Host "  [SET leaf-field $leafName = $leafVal] from: $sv" -ForegroundColor DarkGray
                }
            }
        }
    }
    return $overrides
}

# ---------------------------------------------------------------------------
# Given a condition expression and a variable name, determine the value
# needed to make the condition evaluate to IsTrue.
# ---------------------------------------------------------------------------
function Resolve-ConditionValue {
    param(
        [string]$CondExpr,
        [string]$VarName,
        [bool]$IsTrue,
        [string]$VarDecl
    )
    $isBool = $VarDecl -match '\b(boolean_t|bool)\b'
    $esc = [regex]::Escape($VarName)

    # "0U != VarName" -> TRUE needs VarName != 0 -> 1
    if ($CondExpr -match "0U?\s*!=\s*$esc")    { return $(if ($IsTrue) { '1' } else { '0' }) }
    if ($CondExpr -match "$esc\s*!=\s*0U?")    { return $(if ($IsTrue) { '1' } else { '0' }) }
    # "0U == VarName" -> TRUE needs VarName == 0 -> 0
    if ($CondExpr -match "0U?\s*==\s*$esc")    { return $(if ($IsTrue) { '0' } else { '1' }) }
    if ($CondExpr -match "$esc\s*==\s*0U?")    { return $(if ($IsTrue) { '0' } else { '1' }) }
    # "TRUE == VarName" -> TRUE needs VarName == TRUE
    if ($CondExpr -match "TRUE\s*==\s*$esc")   { return $(if ($IsTrue) { 'TRUE' } else { 'FALSE' }) }
    if ($CondExpr -match "$esc\s*==\s*TRUE")   { return $(if ($IsTrue) { 'TRUE' } else { 'FALSE' }) }
    # "FALSE == VarName" -> TRUE needs VarName == FALSE
    if ($CondExpr -match "FALSE\s*==\s*$esc")  { return $(if ($IsTrue) { 'FALSE' } else { 'TRUE' }) }
    if ($CondExpr -match "$esc\s*==\s*FALSE")  { return $(if ($IsTrue) { 'FALSE' } else { 'TRUE' }) }
    # "FALSE != VarName" -> TRUE needs VarName != FALSE -> TRUE
    if ($CondExpr -match "FALSE\s*!=\s*$esc")  { return $(if ($IsTrue) { 'TRUE' } else { 'FALSE' }) }
    if ($CondExpr -match "$esc\s*!=\s*FALSE")  { return $(if ($IsTrue) { 'TRUE' } else { 'FALSE' }) }

    # Boolean/enum default
    if ($isBool) { return $(if ($IsTrue) { 'TRUE' } else { 'FALSE' }) }
    return $(if ($IsTrue) { '1' } else { '0' })
}

# ---------------------------------------------------------------------------
# Main function: open $teststep 1.N, build $inputs + $outputs + $calltrace,
# close $teststep.  $testcase 1 is opened by Build-TestCaseHeader (step7a)
# and closed by the main loop in step7 after all teststeps are emitted.
# ---------------------------------------------------------------------------
function Build-TCInputsOutputs {
    param(
        [int]$TcNum,
        [int]$StepNum,
        [object[]]$SetValues,
        [object[]]$StubFunctionNames = @(),
        [string]$TCDescription = ""
    )

    $out = ""

    # ---- Open $teststep 1.N ----
    $out += "`t`t`$teststep 1.$StepNum {`n"

    # Teststep $name: short description from TCDescription
    $stepName = if ($TCDescription -match '^TC\d+:\s*(.*)$') { $Matches[1] } else { $TCDescription }
    $stepName = $stepName.Substring(0, [Math]::Min(120, $stepName.Length)).Trim()
    $stepName = $stepName -replace [char]0x2014, '--' -replace [char]0x2013, '--' -replace '[^\x00-\x7E]', '?'
    $out += "`t`t`t`$name `"$stepName`"`n"

    # Per-teststep stub overrides: always emit requested non-void StubFunctions.
    # This ensures Step 7 preserves TC-specific stub intent from testcase_plan.json.
    if ($StubFunctionNames.Count -gt 0) {
        $stubOvr = Parse-StubOverrides -StubFunctionNames $StubFunctionNames
        $requestedFuncs = @()
        foreach ($ovrName in @($stubOvr.Keys | Sort-Object -Unique)) {
            # Add synthetic signatures for plan-only stubs when interface parsing missed them.
            if (-not $allFunctions.ContainsKey($ovrName)) {
                $allFunctions[$ovrName] = @{ Name = $ovrName; ReturnType = 'int'; Parameters = 'void' }
            }
            $f = $allFunctions[$ovrName]
            if ($f -and $f.ReturnType -ne 'void') { $requestedFuncs += $f }
        }
        if ($requestedFuncs.Count -gt 0) {
            $out += "`t`t`t`$stubfunctions {`n"
            foreach ($sf in $requestedFuncs) {
                $sig = "$($sf.ReturnType) $($sf.Name)($($sf.Parameters))"
                $raw = $stubOvr[$sf.Name]
                if ($raw.StartsWith('__BODY__|')) {
                    $retVal = $raw.Substring(9)
                } elseif ($null -ne $raw -and $raw -ne '') {
                    $norm = Normalize-StubReturnValue -ReturnType $sf.ReturnType -RawValue $raw
                    $retVal = if ($norm) { "return $norm;" } else { Get-StubDefaultReturn -ReturnType $sf.ReturnType }
                } else {
                    $retVal = Get-StubDefaultReturn -ReturnType $sf.ReturnType
                }
                if ($sig -match '\[') { $out += "`t`t`t`t'$sig' '''`n" } else { $out += "`t`t`t`t$sig '''`n" }
                if ($retVal) { $out += "`t`t`t`t`t$retVal`n" }
                $out += "`t`t`t`t'''`n"
            }
            $out += "`t`t`t}`n"
        }
    }

    # Build the SetValues override map
    $overrides = Parse-SetValuesOverrides -SetValues $SetValues

    # =========================================================================
    # $inputs section
    # =========================================================================
    $hasAnyInput = (($externalVariablesInfo | Where-Object { $_.Passing -match 'IN|INOUT' }).Count -gt 0) -or
                   (($globalVariablesInfo   | Where-Object { $_.Passing -match 'IN|INOUT' }).Count -gt 0) -or
                   ($parametersInfo.Count -gt 0)

    if ($hasAnyInput) {
        $out += "`t`t`t`$inputs {`n"

        # ---- Global variables (IN / INOUT) ----
        foreach ($gv in $globalVariablesInfo) {
            if ($gv.Passing -notmatch 'IN|INOUT') { continue }
            $varName  = if ($gv.FullName) { $gv.FullName } else { $gv.Name }
            $shortName = $gv.Name
            $defVal   = Get-VarDefaultValue -VarInfo $gv -OverrideMap $overrides

            if ($gv.IsUnion -and $gv.Members.Count -gt 0 -and $gv.FullDeclaration -notmatch '\*') {
                # Union: use first non-IRRELEVANT member
                $firstMember = $gv.Members | Where-Object { $_.Passing -notmatch 'IRRELEVANT' } | Select-Object -First 1
                if (-not $firstMember) { $firstMember = $gv.Members[0] }
                $varBaseOverride = if ($overrides -and $overrides.Contains($shortName)) { $overrides[$shortName] } else { $null }
                $memberName = $firstMember.Name
                $idxSuffix  = if ($gv.ArrayLength -gt 0) { '[0]' } else { '' }
                if ($firstMember.Members -and $firstMember.Members.Count -gt 0) {
                    # Struct-within-union: expand each field with $inputs block syntax
                    $out += "`t`t`t`t$varName$idxSuffix = $memberName`n"
                    $out += "`t`t`t`t$varName$idxSuffix.$memberName {`n"
                    foreach ($field in $firstMember.Members) {
                        if ($field.Passing -match 'IRRELEVANT') { continue }
                        $fVal = Get-VarDefaultValue -VarInfo $field -OverrideMap $overrides
                        $out += "`t`t`t`t`t$($field.Name) = $fVal`n"
                    }
                    $out += "`t`t`t`t}`n"
                } else {
                    # Scalar union member: use base override if provided, else type default
                    $memberVal = if ($null -ne $varBaseOverride) { $varBaseOverride } else { Get-VarDefaultValue -VarInfo $firstMember -OverrideMap $overrides }
                    $out += "`t`t`t`t$varName$idxSuffix = $memberName`n"
                    $out += "`t`t`t`t$varName$idxSuffix.$memberName = $memberVal`n"
                }
            } elseif ($gv.IsStruct -and $gv.Members.Count -gt 0 -and $gv.FullDeclaration -notmatch '\*') {
                # Struct: block initializer — include only IN/INOUT members in $inputs
                $inMembers = @($gv.Members | Where-Object { $_.Passing -match 'IN|INOUT' })
                if ($inMembers.Count -gt 0) {
                    $idxSuffix = if ($gv.ArrayLength -gt 0) { '[0]' } else { '' }
                    $out += "`t`t`t`t$varName$idxSuffix {`n"
                    foreach ($mem in $inMembers) {
                        $mVal = Get-VarDefaultValue -VarInfo $mem -OverrideMap $overrides
                        if ($mem.ArrayLength -gt 0) {
                            $out += "`t`t`t`t`t$($mem.Name)`[0`] = $mVal`n"
                        } else {
                            $out += "`t`t`t`t`t$($mem.Name) = $mVal`n"
                        }
                    }
                    $out += "`t`t`t`t}`n"
                }
                # else: no IN/INOUT members — skip this variable in $inputs entirely
            } elseif ($gv.FullDeclaration -match '\*' -and $gv.ArrayLength -gt 0) {
                # Pointer array: name[0] = target + &target[0] = val
                $targetName = "target_$shortName"
                $out += "`t`t`t`t$varName`[0`] = $targetName`n"
                $out += "`t`t`t`t&$targetName`[0`] = $defVal`n"
            } elseif ($gv.FullDeclaration -match '\*') {
                # Pointer scalar: preserve pointer-member overrides when provided.
                $ptrSpec = if ($script:_pointerObjectOverrides.ContainsKey($shortName)) { $script:_pointerObjectOverrides[$shortName] } else { $null }
                $targetName = if ($ptrSpec -and $ptrSpec.DynamicObject) { [string]$ptrSpec.DynamicObject } else { "target_$shortName" }
                $allocatePtr = if ($ptrSpec) { [bool]$ptrSpec.Allocate } else { $true }
                $ptrDepth = Get-PointerDepthFromDeclaration -Declaration $gv.FullDeclaration
                $memberOverrides = if ($script:_pointerMemberOverrides.ContainsKey($shortName)) { $script:_pointerMemberOverrides[$shortName] } else { $null }
                if ($ptrSpec -and $ptrSpec.Members) {
                    if (-not $memberOverrides) { $memberOverrides = @{} }
                    foreach ($k in $ptrSpec.Members.Keys) { $memberOverrides[$k] = $ptrSpec.Members[$k] }
                }
                $initMembers = @(Get-FullPointerMemberList -PointerDeclaration $gv.FullDeclaration -InterfaceMembers $gv.Members)
                $out += Emit-PointerTargetInputLines `
                    -VariableName $varName `
                    -TargetName $targetName `
                    -InitMembers $initMembers `
                    -MemberOverrides $memberOverrides `
                    -OverrideMap $overrides `
                    -FallbackValue $defVal `
                    -DefaultValueResolver { param($m) Get-VarDefaultValue -VarInfo $m -OverrideMap $overrides } `
                        -AllocatePointedObject $allocatePtr `
                        -PointerDepth $ptrDepth
            } elseif ($gv.ArrayLength -gt 0) {
                # Scalar array — use per-index overrides when present, else default to [0]
                if ($script:_pointerIndexedOverrides.ContainsKey($shortName) -and $script:_pointerIndexedOverrides[$shortName].Count -gt 0) {
                    foreach ($kv in ($script:_pointerIndexedOverrides[$shortName].GetEnumerator() | Sort-Object { [int]$_.Key })) {
                        $out += "`t`t`t`t$varName[$($kv.Key)] = $($kv.Value)`n"
                    }
                } else {
                    $out += "`t`t`t`t$varName`[0`] = $defVal`n"
                }
            } else {
                # Plain scalar / enum
                $out += "`t`t`t`t$varName = $defVal`n"
            }
        }

        # ---- External variables (IN / INOUT) ----
        foreach ($ev in $externalVariablesInfo) {
            if ($ev.Passing -match 'IRRELEVANT') { continue }
            if ($ev.Passing -notmatch 'IN|INOUT') { continue }
            $varName  = $ev.Name
            $defVal   = Get-VarDefaultValue -VarInfo $ev -OverrideMap $overrides

            if ($ev.IsUnion -and $ev.Members.Count -gt 0 -and $ev.FullDeclaration -notmatch '\*') {
                $firstMem  = $ev.Members | Where-Object { $_.Passing -notmatch 'IRRELEVANT' } | Select-Object -First 1
                if (-not $firstMem) { $firstMem = $ev.Members[0] }
                $mVal = Get-VarDefaultValue -VarInfo $firstMem -OverrideMap $overrides
                if ($ev.ArrayLength -gt 0) {
                    $out += "`t`t`t`t$varName`[0`] = $($firstMem.Name)`n"
                    $out += "`t`t`t`t$varName`[0`].$($firstMem.Name) = $mVal`n"
                } else {
                    $out += "`t`t`t`t$varName = $($firstMem.Name)`n"
                    $out += "`t`t`t`t$varName.$($firstMem.Name) = $mVal`n"
                }
            } elseif ($ev.IsStruct -and $ev.Members.Count -gt 0 -and $ev.FullDeclaration -notmatch '\*') {
                $idxSuffix = if ($ev.ArrayLength -gt 0) { '[0]' } else { '' }
                $out += "`t`t`t`t$varName$idxSuffix {`n"
                foreach ($mem in $ev.Members) {
                    if ($mem.Passing -match 'IRRELEVANT') { continue }
                    $mVal = Get-VarDefaultValue -VarInfo $mem -OverrideMap $overrides
                    $out += "`t`t`t`t`t$($mem.Name) = $mVal`n"
                }
                $out += "`t`t`t`t}`n"
            } elseif ($ev.FullDeclaration -match '\*') {
                # Pointer variable: cfgRomContainerROM_DS1 = target_cfgRomContainerROM_DS1
                #                   target_cfgRomContainerROM_DS1.member = <value>
                $ptrSpec = if ($script:_pointerObjectOverrides.ContainsKey($ev.Name)) { $script:_pointerObjectOverrides[$ev.Name] } else { $null }
                $targetName = if ($ptrSpec -and $ptrSpec.DynamicObject) { [string]$ptrSpec.DynamicObject } else { "target_$($ev.Name)" }
                $allocatePtr = if ($ptrSpec) { [bool]$ptrSpec.Allocate } else { $true }
                $ptrDepth = Get-PointerDepthFromDeclaration -Declaration $ev.FullDeclaration
                $memberOverrides = if ($script:_pointerMemberOverrides.ContainsKey($ev.Name)) { $script:_pointerMemberOverrides[$ev.Name] } else { $null }
                if ($ptrSpec -and $ptrSpec.Members) {
                    if (-not $memberOverrides) { $memberOverrides = @{} }
                    foreach ($k in $ptrSpec.Members.Keys) { $memberOverrides[$k] = $ptrSpec.Members[$k] }
                }
                $initMembers = @(Get-FullPointerMemberList -PointerDeclaration $ev.FullDeclaration -InterfaceMembers $ev.Members)
                if ($initMembers.Count -gt 0) {
                    $out += Emit-PointerTargetInputLines `
                        -VariableName $varName `
                        -TargetName $targetName `
                        -InitMembers $initMembers `
                        -MemberOverrides $memberOverrides `
                        -OverrideMap $overrides `
                        -FallbackValue $defVal `
                        -DefaultValueResolver { param($m) Get-VarDefaultValue -VarInfo $m -OverrideMap $overrides } `
                        -AllocatePointedObject $allocatePtr `
                        -PointerDepth $ptrDepth
                } elseif ($script:_pointerIndexedOverrides.ContainsKey($ev.Name)) {
                    $out += "`t`t`t`t$varName = $targetName`[0`]`n"
                    foreach ($kv in ($script:_pointerIndexedOverrides[$ev.Name].GetEnumerator() | Sort-Object { [int]$_.Key })) {
                        $out += "`t`t`t`t$targetName`[$($kv.Key)`] = $($kv.Value)`n"
                        Write-Host "  [PTR $varName] $targetName[$($kv.Key)] = $($kv.Value)" -ForegroundColor DarkGreen
                    }
                } elseif ($memberOverrides -and $memberOverrides.Count -gt 0) {
                    $out += Emit-PointerTargetInputLines `
                        -VariableName $varName `
                        -TargetName $targetName `
                        -InitMembers @() `
                        -MemberOverrides $memberOverrides `
                        -OverrideMap $overrides `
                        -FallbackValue $defVal `
                        -DefaultValueResolver { param($m) Get-VarDefaultValue -VarInfo $m -OverrideMap $overrides } `
                        -AllocatePointedObject $allocatePtr `
                        -PointerDepth $ptrDepth
                } else {
                    $out += Emit-PointerTargetInputLines `
                        -VariableName $varName `
                        -TargetName $targetName `
                        -InitMembers @() `
                        -MemberOverrides @{} `
                        -OverrideMap $overrides `
                        -FallbackValue $defVal `
                        -DefaultValueResolver { param($m) Get-VarDefaultValue -VarInfo $m -OverrideMap $overrides } `
                        -AllocatePointedObject $allocatePtr `
                        -PointerDepth $ptrDepth
                }
            } elseif ($ev.ArrayLength -gt 0) {
                # Scalar array — use per-index overrides when present, else default to [0]
                if ($script:_pointerIndexedOverrides.ContainsKey($varName) -and $script:_pointerIndexedOverrides[$varName].Count -gt 0) {
                    foreach ($kv in ($script:_pointerIndexedOverrides[$varName].GetEnumerator() | Sort-Object { [int]$_.Key })) {
                        $out += "`t`t`t`t$varName[$($kv.Key)] = $($kv.Value)`n"
                    }
                } else {
                    $out += "`t`t`t`t$varName`[0`] = $defVal`n"
                }
            } else {
                $out += "`t`t`t`t$varName = $defVal`n"
            }
        }

        # ---- Parameters (IN / INOUT) ----
        foreach ($p in $parametersInfo) {
            if ($p.Passing -notmatch 'IN|INOUT') { continue }
            $pName  = $p.Name
            $defVal = Get-VarDefaultValue -VarInfo @{ Name = $p.Name; FullDeclaration = $p.Type } -OverrideMap $overrides

            if (($p.IsStruct -or $p.IsUnion) -and $p.Type -notmatch '\*') {
                if ($p.Members.Count -gt 0) {
                    $out += "`t`t`t`t$pName {`n"
                    foreach ($mem in $p.Members) {
                        if ($mem.Passing -match 'IRRELEVANT') { continue }
                        $mVal = Get-VarDefaultValue -VarInfo @{ Name = $mem.Name; FullDeclaration = $mem.Type } -OverrideMap $overrides
                        $out += "`t`t`t`t`t$($mem.Name) = $mVal`n"
                    }
                    $out += "`t`t`t`t}`n"
                } else {
                    $out += "`t`t`t`t$pName = $defVal`n"
                }
            } elseif ($p.Type -match '\*') {
                # Pointer parameter
                $ptrSpec = if ($script:_pointerObjectOverrides.ContainsKey($pName)) { $script:_pointerObjectOverrides[$pName] } else { $null }
                $targetName = if ($ptrSpec -and $ptrSpec.DynamicObject) { [string]$ptrSpec.DynamicObject } else { "target_$pName" }
                $allocatePtr = if ($ptrSpec) { [bool]$ptrSpec.Allocate } else { $true }
                $ptrDepth = Get-PointerDepthFromDeclaration -Declaration $p.Type
                $memberOverrides = if ($script:_pointerMemberOverrides.ContainsKey($pName)) { $script:_pointerMemberOverrides[$pName] } else { $null }
                if ($ptrSpec -and $ptrSpec.Members) {
                    if (-not $memberOverrides) { $memberOverrides = @{} }
                    foreach ($k in $ptrSpec.Members.Keys) { $memberOverrides[$k] = $ptrSpec.Members[$k] }
                }
                $initMembers = @(Get-FullPointerMemberList -PointerDeclaration $p.Type -InterfaceMembers $p.Members)
                $out += Emit-PointerTargetInputLines `
                    -VariableName $pName `
                    -TargetName $targetName `
                    -InitMembers $initMembers `
                    -MemberOverrides $memberOverrides `
                    -OverrideMap $overrides `
                    -FallbackValue $defVal `
                    -DefaultValueResolver { param($m) Get-VarDefaultValue -VarInfo @{ Name = $m.Name; FullDeclaration = $m.Type } -OverrideMap $overrides } `
                        -AllocatePointedObject $allocatePtr `
                        -PointerDepth $ptrDepth
            } else {
                $out += "`t`t`t`t$pName = $defVal`n"
            }
        }

        $out += "`t`t`t}`n"  # close $inputs
    }

    # =========================================================================
    # $outputs section - OUT / INOUT variables with default expected values
    # =========================================================================
    $hasNonVoidReturn = ($returnType -and $returnType -ne 'void' -and $returnType -ne '(void)')
    $outVarsGV = @($globalVariablesInfo   | Where-Object { $_.Passing -match 'OUT|INOUT' })
    $outVarsEV = @($externalVariablesInfo | Where-Object { $_.Passing -match 'OUT|INOUT' })
    $outVarsP  = @($parametersInfo        | Where-Object { $_.Passing -match 'OUT|INOUT' })

    if ($hasNonVoidReturn -or $outVarsGV.Count -gt 0 -or $outVarsEV.Count -gt 0 -or $outVarsP.Count -gt 0) {
        $out += "`t`t`t`$outputs {`n"

        # Return value — skip for struct/union returns (no scalar syntax available)
        if ($hasNonVoidReturn) {
            $retDecl = $returnType
            # Determine if return is a struct/union type (directly or via typedef)
            $isStructReturn = $retDecl -match '\bstruct\b|\bunion\b'
            if (-not $isStructReturn) {
                $retTypeName = ($retDecl -replace '\bconst\b|\bvolatile\b', '' `
                                         -replace '\*.*$', '' `
                                         -replace '\[.*$', '' `
                                         -replace '\s+', '').Trim()
                $src = if ($rawConditionsContent) { $rawConditionsContent } else { '' }
                if ($retTypeName -and $src) {
                    $escRet = [regex]::Escape($retTypeName)
                    if ($src -match "(?ms)typedef\s+(?:struct|union)\b[^}]*\}\s*$escRet\s*;") {
                        $isStructReturn = $true
                    }
                }
            }
            if (-not $isStructReturn) {
                $retDefault = '0'
                if ($retDecl -match '\bboolean_t\b|\bbool\b') {
                    $retDefault = 'FALSE'
                } elseif ($retDecl -match '\*') {
                    $retDefault = 'NULL'
                } elseif ($retDecl -match '(?:^|\s)enum\s+(\w+)') {
                    $m = Get-EnumMembersFromConditionsFile -TypeName $Matches[1]
                    if ($m.Count -gt 0) { $retDefault = $m[0] }
                } else {
                    $knownRet = @('u8','u16','u32','u64','s8','s16','s32',
                                  'uint8_t','uint16_t','uint32_t','uint64_t',
                                  'int8_t','int16_t','int32_t','int64_t',
                                  'int','char','short','long','void')
                    if ($retTypeName -and $retTypeName -notin $knownRet) {
                        $m = Get-EnumMembersFromConditionsFile -TypeName $retTypeName
                        if ($m.Count -gt 0) { $retDefault = $m[0] }
                    }
                }
                $out += "`t`t`t`treturn = $retDefault`n"
            }
            # struct/union return: omit from $outputs — Tessy does not require it
        }

        # Global variables OUT / INOUT
        foreach ($gv in $outVarsGV) {
            $cKeywords = @('int','char','short','long','float','double','void','unsigned','signed','const','volatile','static','extern')
            if ($gv.Name -eq 'UNKNOWN' -or $cKeywords -contains $gv.Name) { continue }
            $varName = if ($gv.FullName) { $gv.FullName } else { $gv.Name }
            $defVal  = Get-VarDefaultValue -VarInfo $gv -OverrideMap @{}

            if ($gv.IsUnion -and $gv.Members.Count -gt 0) {
                # Union: use member-based format to avoid invalid C code generation
                $firstMember = $gv.Members | Where-Object { $_.Passing -notmatch 'IRRELEVANT' } | Select-Object -First 1
                if (-not $firstMember) { $firstMember = $gv.Members[0] }
                $memberName = $firstMember.Name
                $idxSuffix  = if ($gv.ArrayLength -gt 0) { '[0]' } else { '' }
                if ($firstMember.Members -and $firstMember.Members.Count -gt 0) {
                    # Struct-within-union: expand each field with block syntax
                    $out += "`t`t`t`t$varName$idxSuffix = $memberName`n"
                    $out += "`t`t`t`t$varName$idxSuffix.$memberName {`n"
                    foreach ($field in $firstMember.Members) {
                        if ($field.Passing -match 'IRRELEVANT') { continue }
                        $fVal = Get-VarDefaultValue -VarInfo $field -OverrideMap @{}
                        $out += "`t`t`t`t`t$($field.Name) = $fVal`n"
                    }
                    $out += "`t`t`t`t}`n"
                } else {
                    $memberVal = Get-VarDefaultValue -VarInfo $firstMember -OverrideMap @{}
                    $out += "`t`t`t`t$varName$idxSuffix = $memberName`n"
                    $out += "`t`t`t`t$varName$idxSuffix.$memberName = $memberVal`n"
                }
            } elseif ($gv.IsStruct -and $gv.Members.Count -gt 0) {
                # Struct array: emit every index with block format, OUT/INOUT members only
                $outMembers = @($gv.Members | Where-Object { $_.Passing -match 'OUT|INOUT' })
                if ($outMembers.Count -gt 0) {
                    $count = if ($gv.ArrayLength -gt 0) { $gv.ArrayLength } else { 1 }
                    for ($i = 0; $i -lt $count; $i++) {
                        $idxSuffix = if ($gv.ArrayLength -gt 0) { "[$i]" } else { '' }
                        $out += "`t`t`t`t$varName$idxSuffix {`n"
                        foreach ($mem in $outMembers) {
                            $mVal = Get-VarDefaultValue -VarInfo $mem -OverrideMap @{}
                            $out += "`t`t`t`t`t$($mem.Name) = $mVal`n"
                        }
                        $out += "`t`t`t`t}`n"
                    }
                }
            } elseif ($gv.ArrayLength -gt 0) {
                $out += "`t`t`t`t$varName`[0`] = $defVal`n"
            } else {
                $out += "`t`t`t`t$varName = $defVal`n"
            }
        }

        # External variables OUT / INOUT
        foreach ($ev in $outVarsEV) {
            $cKeywords = @('int','char','short','long','float','double','void','unsigned','signed','const','volatile')
            if ($ev.Name -eq 'UNKNOWN' -or $cKeywords -contains $ev.Name) { continue }
            $defVal = Get-VarDefaultValue -VarInfo $ev -OverrideMap @{}
            if ($ev.IsUnion -and $ev.Members.Count -gt 0) {
                $firstMem  = $ev.Members | Where-Object { $_.Passing -notmatch 'IRRELEVANT' } | Select-Object -First 1
                if (-not $firstMem) { $firstMem = $ev.Members[0] }
                $mVal = Get-VarDefaultValue -VarInfo $firstMem -OverrideMap @{}
                if ($ev.ArrayLength -gt 0) {
                    $out += "`t`t`t`t$($ev.Name)`[0`] = $($firstMem.Name)`n"
                    $out += "`t`t`t`t$($ev.Name)`[0`].$($firstMem.Name) = $mVal`n"
                } else {
                    $out += "`t`t`t`t$($ev.Name) = $($firstMem.Name)`n"
                    $out += "`t`t`t`t$($ev.Name).$($firstMem.Name) = $mVal`n"
                }
            } elseif ($ev.ArrayLength -gt 0) {
                $out += "`t`t`t`t$($ev.Name)`[0`] = $defVal`n"
            } else {
                $out += "`t`t`t`t$($ev.Name) = $defVal`n"
            }
        }

        # Parameter OUT / INOUT
        foreach ($p in $outVarsP) {
            $defVal = Get-VarDefaultValue -VarInfo @{ Name = $p.Name; FullDeclaration = $p.Type } -OverrideMap @{}
            $out += "`t`t`t`t$($p.Name) = $defVal`n"
        }

        $out += "`t`t`t}`n"  # close $outputs
    }

    # =========================================================================
    # $calltrace
    # =========================================================================
    $out += "`t`t`t`$calltrace {`n"
    $out += "`t`t`t`t*** Ignore Call Trace ***`n"
    $out += "`t`t`t}`n"

    # Close $teststep only ($testcase 1 is closed by the main loop in step7)
    $out += "`t`t}`n"   # close $teststep

    return $out
}