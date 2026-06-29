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
# Per-TC indexed overrides for pointer variables; cleared at start of each Parse-SetValuesOverrides call
$script:_pointerIndexedOverrides = @{}

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

    # Reset per-TC pointer indexed overrides
    $script:_pointerIndexedOverrides = @{}

    $overrides = [ordered]@{}
    foreach ($raw in $SetValues) {
        if ($null -eq $raw) { continue }

        $sv = $null
        if ($raw -is [string]) {
            $sv = $raw
        } else {
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
        # Pattern 3: "varname[index].member = value" or "varname[index] = value" or "varname = value"
        # Extract base variable name and value for direct override
        if ($sv -match '^([A-Za-z_][A-Za-z0-9_]*)(?:\[[^\]]*\])?(?:\.[A-Za-z_][A-Za-z0-9_]*)?\s*=\s*(.+)$') {
            $varBase = $Matches[1].Trim()
            $value   = $Matches[2].Trim()
            $overrides[$varBase] = $value
            Write-Host "  [SET $varBase = $value] from: $sv" -ForegroundColor DarkGreen
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

    # Per-teststep stub overrides: only emitted when TC-specific return values differ from default
    if ($StubFunctionNames.Count -gt 0) {
        $stubOvr = Parse-StubOverrides -StubFunctionNames $StubFunctionNames
        $ovrFuncs = @(
            $allFunctions.Keys | Sort-Object | ForEach-Object {
                $f = $allFunctions[$_]
                if ($f.ReturnType -ne 'void' -and $stubOvr.ContainsKey($f.Name) -and $null -ne $stubOvr[$f.Name]) { $f }
            }
        )
        if ($ovrFuncs.Count -gt 0) {
            $out += "`t`t`t`$stubfunctions {`n"
            foreach ($sf in $ovrFuncs) {
                $sig = "$($sf.ReturnType) $($sf.Name)($($sf.Parameters))"
                $raw = $stubOvr[$sf.Name]
                if ($raw.StartsWith('__BODY__|')) {
                    $retVal = $raw.Substring(9)
                } else {
                    $norm = Normalize-StubReturnValue -ReturnType $sf.ReturnType -RawValue $raw
                    $retVal = if ($norm) { "return $norm;" } else { Get-StubDefaultReturn -ReturnType $sf.ReturnType }
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

            if ($gv.IsUnion -and $gv.Members.Count -gt 0) {
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
            } elseif ($gv.IsStruct -and $gv.Members.Count -gt 0) {
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

            if ($ev.IsUnion -and $ev.Members.Count -gt 0) {
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
            } elseif ($ev.IsStruct -and $ev.Members.Count -gt 0) {
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
                #                   &target_cfgRomContainerROM_DS1[0] = <value>
                $targetName = "target_$($ev.Name)"
                $out += "`t`t`t`t$varName = $targetName`n"
                if ($script:_pointerIndexedOverrides.ContainsKey($ev.Name)) {
                    foreach ($kv in ($script:_pointerIndexedOverrides[$ev.Name].GetEnumerator() | Sort-Object { [int]$_.Key })) {
                        $out += "`t`t`t`t&$targetName[$($kv.Key)] = $($kv.Value)`n"
                        Write-Host "  [PTR $varName] &$targetName[$($kv.Key)] = $($kv.Value)" -ForegroundColor DarkGreen
                    }
                } else {
                    $out += "`t`t`t`t&$targetName[0] = $defVal`n"
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

            if ($p.IsStruct -or $p.IsUnion) {
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
                $targetName = "target_$pName"
                $out += "`t`t`t`t$pName = $targetName`n"
                $out += "`t`t`t`t&$targetName`[0`] = $defVal`n"
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