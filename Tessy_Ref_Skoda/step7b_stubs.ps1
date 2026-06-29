# ============================================================================
# STEP 7b: TC Stub Functions Generator (Plan-based)
# Defines: Get-StubDefaultReturn, Parse-StubOverrides, Build-TCStubs
# Dot-sourced by step7_generate_testcases.ps1
# Uses script-level: $allFunctions (populated from EXTERNAL FUNCTIONS +
#   LOCAL FUNCTIONS sections of _conditions_after_passing.c header)
#
# Behavior:
#   - Always stubs ALL non-void functions (external + local) in every TC.
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
    if ($ReturnType -match '\b(boolean_t|bool)\b') { return 'return FALSE;' }
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
        if ($value -match '^(?i:true|1(?:U|UL|L)?)$')  { return 'TRUE' }
        if ($value -match '^(?i:false|0(?:U|UL|L)?)$') { return 'FALSE' }
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

    # All non-void functions from conditions file header, sorted by name
    $nonVoidFuncs = @(
        $allFunctions.Keys | Sort-Object | ForEach-Object {
            $f = $allFunctions[$_]
            if ($f.ReturnType -ne 'void') { $f }
        }
    )

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
# the $testcase 1 header). All non-void functions get a default return value.
# Per-TC stub overrides (different return values) are handled inline inside
# each $teststep block by Build-TCInputsOutputs when StubFunctionNames is set.
# ============================================================================
function Build-TestObjectStubs {
    # All non-void functions from conditions file header, sorted by name
    $nonVoidFuncs = @(
        $allFunctions.Keys | Sort-Object | ForEach-Object {
            $f = $allFunctions[$_]
            if ($f.ReturnType -ne 'void') { $f }
        }
    )

    if ($nonVoidFuncs.Count -eq 0) {
        Write-Host "[TESTOBJECT-STUBS] No non-void stub functions found" -ForegroundColor DarkGray
        return ""
    }

    $out = "`t`$stubfunctions {`n"
    foreach ($sf in $nonVoidFuncs) {
        $sig    = "$($sf.ReturnType) $($sf.Name)($($sf.Parameters))"
        $retVal = Get-StubDefaultReturn -ReturnType $sf.ReturnType
        if ($sig -match '\[') {
            $out += "`t`t'$sig' '''`n"
        } else {
            $out += "`t`t$sig '''`n"
        }
        if ($retVal) { $out += "`t`t`t$retVal`n" }
        $out += "`t`t'''`n"
        Write-Host "[TESTOBJECT-STUB] $($sf.Name)() -> $($sf.ReturnType) [default]" -ForegroundColor Cyan
    }
    $out += "`t}`n`n"
    return $out
}