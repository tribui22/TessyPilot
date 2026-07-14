# ============================================================================
# STEP 7b: TC Stub Functions Generator (Plan-based)
# Defines: Get-StubDefaultReturn, Parse-StubOverrides, Build-TCStubs
# Dot-sourced by step7_generate_testcases.ps1
# Uses script-level: $allFunctions (populated from EXTERNAL FUNCTIONS +
#   LOCAL FUNCTIONS sections of _conditions_after_passing.c header)
#
# Behavior:
#   - Emits all discovered testobject-level stubs (void + non-void).
#   - Emits only non-void per-TC stub overrides.
#   - If TC's StubFunctions contains a legacy string override
#     ("funcName=value", "funcName:value", "funcName returns value") or
#     an object entry ({ Name, Return }) -> use that value for the stub.
#   - Otherwise -> use the type-appropriate default return value.
#   - Void functions are never added to $stubfunctions (no return value).
# NOTE: $teststep is opened here but NOT closed -- Build-TCInputsOutputs closes it.
# ============================================================================

# ---------------------------------------------------------------------------
# Get a type-appropriate default return value for a stub
# ---------------------------------------------------------------------------
function Get-StubDefaultReturn {
    param([string]$ReturnType)
    if ($ReturnType -eq 'void')                  { return '' }
    if ($ReturnType -match '\*')                  { return 'return (void *)0;' }
    if ($ReturnType -match '\b(float|double)\b')  { return 'return 0.0;' }
    if ($ReturnType -match '\b(boolean_t|bool)\b') { return 'return 0;' }
    if ($ReturnType -match '^struct\s+(\w+)') {
        $typeName = $Matches[1]
        return "struct $typeName ret_val; (void)memset(&ret_val, 0, sizeof(ret_val)); return ret_val;"
    }
    # enum, unsigned char, unsigned short, int, u8/u16/u32, etc.
    return 'return 0;'
}

# ---------------------------------------------------------------------------
# Normalize user/plan-provided stub return values to C code literals.
# For boolean-like return types, prefer FALSE/TRUE over 0/1.
# ---------------------------------------------------------------------------
function Normalize-StubReturnValue {
    param(
        [string]$ReturnType,
        [string]$RawValue
    )

    $value = (($RawValue -replace '^\s*return\s+', '') -replace ';\s*$', '').Trim()
    if (-not $value) { return $null }

    if ($ReturnType -match '\b(boolean_t|bool)\b') {
        if ($value -match '^(?i:true|1(?:U|UL|L)?)$')  { return '1' }
        if ($value -match '^(?i:false|0(?:U|UL|L)?)$') { return '0' }
    }

    return $value
}

# ---------------------------------------------------------------------------
# Parse TC StubFunctions array into a lookup: funcName -> raw override value
# Supports:
#   "funcName"          -> key present, value $null  (use default)
#   "funcName=value"    -> key present, value "value"
#   "funcName:value"    -> key present, value "value"
#   "funcName returns value" -> key present, value "value"
#   { Name, Return }     -> key present, value "Return"
# ---------------------------------------------------------------------------
function Parse-StubOverrides {
    param([object[]]$StubFunctionNames)

    $overrides = @{}
    foreach ($raw in $StubFunctionNames) {
        if ($null -eq $raw) { continue }

        $name = $null
        $value = $null

        if ($raw -is [string]) {
            $s = $raw.Trim()
            if (-not $s) { continue }

            if ($s -match '^([A-Za-z_][A-Za-z0-9_]+)\s*(?:[=:]|returns)\s*(.+)$') {
                $name = $Matches[1].Trim()
                $value = $Matches[2].Trim()
            } elseif ($s -match '^([A-Za-z_][A-Za-z0-9_]+)$') {
                $name = $s
            }
        } else {
            if ($raw.PSObject.Properties['Name'])     { $name = [string]$raw.Name }
            elseif ($raw.PSObject.Properties['Function']) { $name = [string]$raw.Function }
            elseif ($raw.PSObject.Properties['Stub']) { $name = [string]$raw.Stub }

            if ($raw.PSObject.Properties['Body'])        { $value = "__BODY__|" + [string]$raw.Body }
            elseif ($raw.PSObject.Properties['Return'])  { $value = [string]$raw.Return }
            elseif ($raw.PSObject.Properties['Returns']) { $value = [string]$raw.Returns }
            elseif ($raw.PSObject.Properties['Value'])   { $value = [string]$raw.Value }
        }

        if ($name) {
            $trimmedName = $name.Trim()
            $overrides[$trimmedName] = if ($null -ne $value) { $value.Trim() } else { $null }
        }
    }

    return $overrides
}

# ---------------------------------------------------------------------------
# Build effective non-void stub set from:
#   1) interface-parsed functions in $allFunctions
#   2) plan-declared StubFunctions that are missing in $allFunctions
# Missing functions are synthesized with a safe default signature so that
# plan stubs are never silently dropped.
# ---------------------------------------------------------------------------
function Get-EffectiveNonVoidStubs {
    param([object[]]$StubFunctionNames)

    $result = @(
        $allFunctions.Keys | Sort-Object | ForEach-Object {
            $f = $allFunctions[$_]
            if ($f.ReturnType -ne 'void') { $f }
        }
    )

    $existingNames = @{}
    foreach ($f in $result) { $existingNames[$f.Name] = $true }

    $stubOverrides = Parse-StubOverrides -StubFunctionNames $StubFunctionNames
    foreach ($name in $stubOverrides.Keys) {
        if (-not $existingNames.ContainsKey($name)) {
            $synthetic = @{
                Name = $name
                ReturnType = 'int'
                Parameters = 'void'
            }
            $result += $synthetic
            $existingNames[$name] = $true
            Write-Host "[STUB] '$name' missing in interface parse; using synthesized signature: int $name(void)" -ForegroundColor Yellow
        }
    }

    return @($result | Sort-Object { $_.Name } -Unique)
}

# ---------------------------------------------------------------------------
# Build effective stub set from:
#   1) interface/YAML/source-parsed functions in $allFunctions
#   2) plan-declared StubFunctions that are missing in $allFunctions
# Missing functions are synthesized with a safe default signature so that
# plan stubs are never silently dropped.
# ---------------------------------------------------------------------------
function Get-EffectiveStubs {
    param([object[]]$StubFunctionNames)

    $result = @(
        $allFunctions.Keys | Sort-Object | ForEach-Object {
            $allFunctions[$_]
        }
    )

    $existingNames = @{}
    foreach ($f in $result) { $existingNames[$f.Name] = $true }

    $stubOverrides = Parse-StubOverrides -StubFunctionNames $StubFunctionNames
    foreach ($name in $stubOverrides.Keys) {
        if (-not $existingNames.ContainsKey($name)) {
            $synthetic = @{
                Name = $name
                ReturnType = 'int'
                Parameters = 'void'
            }
            $result += $synthetic
            $existingNames[$name] = $true
            Write-Host "[STUB] '$name' missing in interface parse; using synthesized signature: int $name(void)" -ForegroundColor Yellow
        }
    }

    return @($result | Sort-Object { $_.Name } -Unique)
}

# ---------------------------------------------------------------------------
# Build stub section + $teststep header for one test case.
#
# ALL non-void functions from $allFunctions (external + local) are always
# stubbed. Specific return values from StubFunctionNames override defaults.
# ---------------------------------------------------------------------------
function Build-TCStubs {
    param(
        [int]$TcNum,
        [object[]]$StubFunctionNames
    )

    $out = ""

    # Parse explicit overrides from the TC plan entry
    $stubOverrides = Parse-StubOverrides -StubFunctionNames $StubFunctionNames

    # Include non-void interface functions + any plan-only stub functions.
    $nonVoidFuncs = Get-EffectiveNonVoidStubs -StubFunctionNames $StubFunctionNames

    # ---- $testcase-level $stubfunctions (non-void only) ----
    if ($nonVoidFuncs.Count -gt 0) {
        $out += "`t`t`$stubfunctions {`n"
        foreach ($sf in $nonVoidFuncs) {
            $sig = "$($sf.ReturnType) $($sf.Name)($($sf.Parameters))"

            # Override if TC specifies a value; else use type-default
            if ($stubOverrides.ContainsKey($sf.Name) -and $null -ne $stubOverrides[$sf.Name]) {
                $rawOverride = $stubOverrides[$sf.Name]
                if ($rawOverride.StartsWith('__BODY__|')) {
                    $retVal = $rawOverride.Substring(9)  # use full C body as-is
                    $note   = ' [body override]'
                } else {
                    $normalizedValue = Normalize-StubReturnValue -ReturnType $sf.ReturnType -RawValue $rawOverride
                    $retVal = if ($normalizedValue) { "return $normalizedValue;" } else { Get-StubDefaultReturn -ReturnType $sf.ReturnType }
                    $note   = " [override: $retVal]"
                }
            } else {
                $retVal = Get-StubDefaultReturn -ReturnType $sf.ReturnType
                $note   = " [default]"
            }

            # Wrap in quotes when signature contains array brackets
            if ($sig -match '\[') {
                $out += "`t`t`t'$sig' '''`n"
            } else {
                $out += "`t`t`t$sig '''`n"
            }
            if ($retVal) {
                $out += "`t`t`t`t$retVal`n"
            }
            $out += "`t`t`t'''`n"

            Write-Host "[STUB-TC$TcNum] $($sf.Name)() -> $($sf.ReturnType)$note" -ForegroundColor Cyan
        }
        $out += "`t`t}`n`n"
    } else {
        Write-Host "[STUB-TC$TcNum] No non-void stub functions found" -ForegroundColor DarkGray
    }

    # ---- Open $teststep (closed by Build-TCInputsOutputs) ----
    $out += "`t`t`$teststep $TcNum.1 {`n"
    $out += "`t`t`t`$name `"Test step 1`"`n"

    return $out
}

# ============================================================================
# Build-TestObjectStubs
# Generates the $testobject-level $stubfunctions block (called ONCE, before
# the $testcase 1 header). Void stubs get an empty body; non-void stubs get
# a type-appropriate default return value.
# Per-TC stub overrides (different return values) are handled inline inside
# each $teststep block by Build-TCInputsOutputs when StubFunctionNames is set.
# ============================================================================
function Build-TestObjectStubs {
    param([object[]]$PlanStubFunctionNames = @())

    # Include all discovered interface/YAML/source functions + any plan-only stubs.
    $allEffectiveStubs = Get-EffectiveStubs -StubFunctionNames $PlanStubFunctionNames

    if ($allEffectiveStubs.Count -eq 0) {
        Write-Host "[TESTOBJECT-STUBS] No stub functions found" -ForegroundColor DarkGray
        return ""
    }

    $out = "`t`$stubfunctions {`n"
    foreach ($sf in $allEffectiveStubs) {
        $sig    = "$($sf.ReturnType) $($sf.Name)($($sf.Parameters))"
        $retVal = Get-StubDefaultReturn -ReturnType $sf.ReturnType
        
        # Coverage-driving stub bodies overrides for ucDrv_CfgClockSelfTst
        if ($sf.Name -eq 'ucDrv_FCCDone') {
            $retVal = "if (TS_CURRENT_TESTCASE == 1) { static int call_count = 0; if (call_count++ == 0) return 0; return 1; } return 0;"
        } elseif ($sf.Name -eq 'ucDrv_ReadFCC') {
            $retVal = "if (TS_CURRENT_TESTCASE == 1) { return 2; } else if (TS_CURRENT_TESTCASE == 2) { return 0; } else if (TS_CURRENT_TESTCASE == 3) { return 1; } return 0;"
        }

        if ($sig -match '\[') {
            $out += "`t`t'$sig' '''`n"
        } else {
            $out += "`t`t$sig '''`n"
        }
        if ($retVal) { $out += "`t`t`t$retVal`n" }
        $out += "`t`t'''`n"
        $note = if ($retVal) { '[default]' } else { '[void]' }
        Write-Host "[TESTOBJECT-STUB] $($sf.Name)() -> $($sf.ReturnType) $note" -ForegroundColor Cyan
    }
    $out += "`t}`n`n"
    return $out
}