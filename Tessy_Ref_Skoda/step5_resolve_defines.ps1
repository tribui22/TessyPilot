# ============================================================================
# STEP 5: Build Annotated Conditions File from Interface Info
# ============================================================================
# Purpose:
#   1. Copy <TestObject>_interface_info.txt as a comment header above the function.
#   2. Find every ALL_CAPS token in conditions.c that is a #define constant.
#      Add the full #define line at the top of the output.
#   3. Find every enum/union/struct type name referenced in interface_info.txt
#      (or declared in conditions.c). Extract the full typedef block from
#      source headers and add it at the top.
#   Saves result to:
#       <WorkingDir>\testObjectCode\<TestObject>_conditions_after_passing.c
#
# Usage:
#   .\step5_resolve_defines.ps1 `
#       -TestObject "infineonDrvGetMaxOutCurrValPtr" `
#       -Module     "infineon_drv" `
#       -SourceDir  "C:\Path\To\Source" `
#       -WorkingDir "C:\Path\To\Work"
# ============================================================================

param(
    [Parameter(Mandatory=$true)][string]$TestObject,
    [Parameter(Mandatory=$true)][string]$Module,
    [Parameter(Mandatory=$true)][string]$SourceDir,
    [Parameter(Mandatory=$true)][string]$WorkingDir
)

# ---------------------------------------------------------------------------
# File content cache (avoid re-reading the same file repeatedly)
# ---------------------------------------------------------------------------
$script:_srcFiles   = $null
$script:_fileCache  = @{}
$script:_moduleFile = $null   # resolved path to the module .c file under test

function Get-SrcFiles {
    if ($null -eq $script:_srcFiles) {
        $script:_srcFiles = Get-ChildItem -Path $SourceDir -Recurse -Include '*.h','*.c' -ErrorAction SilentlyContinue
    }
    return $script:_srcFiles
}

function Get-CachedFile {
    param([string]$Path)
    if (-not $script:_fileCache.ContainsKey($Path)) {
        $script:_fileCache[$Path] = Get-Content $Path -Raw -ErrorAction SilentlyContinue
    }
    return $script:_fileCache[$Path]
}

# ---------------------------------------------------------------------------
# Find the full #define line for an ALL_CAPS token.
# Returns the raw "#define TOKEN ..." line, or $null if not found.
# ---------------------------------------------------------------------------
function Find-DefineLine {
    param([string]$Token)
    $esc = [regex]::Escape($Token)
    foreach ($sf in (Get-SrcFiles)) {
        $txt = Get-CachedFile $sf.FullName
        if (-not $txt) { continue }
        if ($txt -match "(?m)^\s*(#\s*define\s+$esc\b[^\r\n]*)") {
            return $Matches[1].Trim()
        }
    }
    return $null
}

# ---------------------------------------------------------------------------
# Find the full typedef/enum block for a type name in all header files,
# and also in the specific .c file containing the function under test.
# Handles:  typedef enum   { ... } Name;
#           typedef struct { ... } Name;
#           typedef union  { ... } Name;
#           enum Name { ... };              (non-typedef enums)
# Returns the block text, or $null.
# ---------------------------------------------------------------------------
function Find-TypeBlock {
    param([string]$TypeName)
    $esc = [regex]::Escape($TypeName)

    # Build the list of files to search: all .h files + the module .c file
    $filesToSearch = (Get-SrcFiles) | Where-Object { $_.Extension -eq '.h' }
    if ($script:_moduleFile -and (Test-Path $script:_moduleFile)) {
        $moduleItem = Get-Item $script:_moduleFile -ErrorAction SilentlyContinue
        if ($moduleItem) { $filesToSearch = @($filesToSearch) + @($moduleItem) }
    }

    foreach ($sf in $filesToSearch) {
        $txt = Get-CachedFile $sf.FullName
        if (-not $txt -or $txt -notmatch "\b$esc\b") { continue }

        # Try: typedef (enum|struct|union) ... { ... } TypeName ;
        foreach ($km in [regex]::Matches($txt, "(?ms)(typedef\s+(?:enum|struct|union)\b[^{]*)(\{)")) {
            $startIdx  = $km.Index
            $afterOpen = $km.Index + $km.Length
            $depth = 1; $idx = $afterOpen
            while ($idx -lt $txt.Length -and $depth -gt 0) {
                if     ($txt[$idx] -eq '{') { $depth++ }
                elseif ($txt[$idx] -eq '}') { $depth-- }
                $idx++
            }
            $tail = $txt.Substring($idx, [Math]::Min(80, $txt.Length - $idx))
            if ($tail -match "^\s*$esc\s*;") {
                $endIdx = $idx + $tail.IndexOf(';') + 1
                return $txt.Substring($startIdx, $endIdx - $startIdx).Trim()
            }
        }

        # Try: enum TypeName { ... };  (no typedef prefix)
        foreach ($km in [regex]::Matches($txt, "(?ms)(enum\s+$esc\s*)(\{)")) {
            $startIdx  = $km.Index
            $afterOpen = $km.Index + $km.Length
            $depth = 1; $idx = $afterOpen
            while ($idx -lt $txt.Length -and $depth -gt 0) {
                if     ($txt[$idx] -eq '{') { $depth++ }
                elseif ($txt[$idx] -eq '}') { $depth-- }
                $idx++
            }
            $tail = $txt.Substring($idx, [Math]::Min(10, $txt.Length - $idx))
            if ($tail -match '^\s*;') {
                $endIdx = $idx + $tail.IndexOf(';') + 1
                return $txt.Substring($startIdx, $endIdx - $startIdx).Trim()
            }
        }
    }
    return $null
}

# ---------------------------------------------------------------------------
# Strip noise comments from a C type block (PRQA, ##attribute, polyspace,
# LCOV, single-line doc comments /**  */).  Leaves the type structure clean.
# ---------------------------------------------------------------------------
function Clean-TypeBlock {
    param([string]$Block)
    $b = $Block
    $b = $b -replace '/\*\s*PRQA\s+S\s+\d[^*]*\*/', ''      # /* PRQA S ... */
    $b = $b -replace '/\*##[^*]*\*/', ''                       # /*## attribute ... */
    $b = $b -replace '(?s)/\*\*.*?\*/', ''                    # /** multi-line doc block */
    $b = $b -replace '/\*\s*polyspace[^*]*\*/', ''            # /* polyspace ... */
    $b = $b -replace '/\*\s*LCOV_EXCL[^*]*\*/', ''            # /* LCOV_EXCL... */
    $b = $b -replace '/\*\s*-->DDC=FCT[^*]*\*/', ''           # /* -->DDC=FCT... */
    # Remove lines that became empty or whitespace-only after comment removal
    $lines = ($b -split "`r?`n") | Where-Object { $_.Trim() -ne '' }
    return ($lines -join "`n")
}

# ---------------------------------------------------------------------------
# Find the full definition of a const variable or const array in source files.
# Handles:  static const Type Name[dim1][dim2] = { ... };
#           const Type Name = scalar;
# Returns the definition text, or $null.
# NOTE: Avoids (?ms) to prevent catastrophic backtracking on large files.
# ---------------------------------------------------------------------------
function Find-ConstVarBlock {
    param([string]$VarName)
    $esc = [regex]::Escape($VarName)

    foreach ($sf in (Get-SrcFiles)) {
        $txt = Get-CachedFile $sf.FullName
        if (-not $txt) { continue }
        if ($txt -notmatch '\bconst\b' -or $txt -notmatch "\b$esc\b") { continue }

        # Find declaration line: uses [^\r\n]* so regex cannot cross lines (no backtracking)
        $m1 = [regex]::Match($txt, "(?m)^[^\r\n]*\bconst\b[^\r\n]*\b$esc\b[^\r\n]*")
        if (-not $m1.Success) { continue }

        $startIdx  = $m1.Index
        $afterDecl = $m1.Index + $m1.Length

        # Look ahead up to 300 chars for { or ; (covers same-line and next-line brace)
        $lookahead = $txt.Substring($afterDecl, [Math]::Min(300, $txt.Length - $afterDecl))
        $braceRel  = $lookahead.IndexOf('{')
        $semiRel   = $lookahead.IndexOf(';')

        if ($braceRel -lt 0 -or ($semiRel -ge 0 -and $semiRel -lt $braceRel)) {
            # Case 2: scalar assignment — verify '=' appears before ';'
            if ($semiRel -ge 0 -and $lookahead.Substring(0, $semiRel) -match '=') {
                return $txt.Substring($startIdx, $afterDecl - $startIdx + $semiRel + 1).Trim()
            }
            continue
        }

        # Case 1: brace initializer — walk brace depth
        $depth = 1; $idx = $afterDecl + $braceRel + 1
        while ($idx -lt $txt.Length -and $depth -gt 0) {
            if     ($txt[$idx] -eq '{') { $depth++ }
            elseif ($txt[$idx] -eq '}') { $depth-- }
            $idx++
        }
        $tail = $txt.Substring($idx, [Math]::Min(10, $txt.Length - $idx))
        if ($tail -match '^\s*;') {
            $endIdx = $idx + $tail.IndexOf(';') + 1
            return $txt.Substring($startIdx, $endIdx - $startIdx).Trim()
        }
    }
    return $null
}

# ============================================================================
# Main
# ============================================================================

Write-Host "`n================================================================================" -ForegroundColor Cyan
Write-Host "  STEP 5: BUILD ANNOTATED CONDITIONS FILE" -ForegroundColor Cyan
Write-Host "  Test Object : $TestObject" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

# --- Input files ---
$condFile      = "$WorkingDir\testObjectCode\${TestObject}_conditions.c"
$interfaceFile = "$WorkingDir\interface\${TestObject}_interface_info.txt"

if (-not (Test-Path $condFile)) {
    Write-Host "[ERROR] Conditions file not found: $condFile" -ForegroundColor Red
    Write-Host "        Run step 4 first." -ForegroundColor Yellow
    exit 1
}

Write-Host "`n[READ] $condFile" -ForegroundColor Yellow
$condLines = Get-Content $condFile
$condText  = $condLines -join "`n"

# Resolve the module .c file path so Find-TypeBlock can also search it
$moduleMatches = Get-ChildItem -Path $SourceDir -Recurse -Filter $Module -ErrorAction SilentlyContinue
if ($moduleMatches) {
    $script:_moduleFile = $moduleMatches[0].FullName
    Write-Host "[MODULE] $($script:_moduleFile)" -ForegroundColor Yellow
} else {
    Write-Host "[WARN] Module file not found in SourceDir: $Module" -ForegroundColor DarkYellow
}

$interfaceText = ""
if (Test-Path $interfaceFile) {
    $interfaceText = Get-Content $interfaceFile -Raw
    Write-Host "[READ] $interfaceFile" -ForegroundColor Yellow
} else {
    Write-Host "[WARN] Interface info not found: $interfaceFile" -ForegroundColor DarkYellow
}

# ---------------------------------------------------------------------------
# Step A — Collect type names from interface_info.txt and conditions.c
# ---------------------------------------------------------------------------
Write-Host "`n[A] Collecting type names..." -ForegroundColor Yellow

$typeNames = [System.Collections.Generic.HashSet[string]]::new()

# From interface_info.txt: every "enum X", "union X", "struct X" — skip IRRELEVANT lines
# (IRRELEVANT variables don't need their types resolved; also avoids treating
#  variable names like internalState_st / bits_st as type names)
# For EXTERNAL FUNCTIONS: only collect types from signatures of functions that
# are actually called in conditions.c (the function body). If the function is
# listed as external but never called (e.g. because the function body is empty)
# its parameter types are not needed.
if ($interfaceText) {
    $inExternalFunctions = $false
    $inLocalFunctions    = $false
    $inVarSection        = $false  # covers GLOBAL VARIABLES, EXTERNAL VARIABLES, PARAMETERS, RETURN TYPE
    foreach ($ln in ($interfaceText -split "`r?`n")) {
        if     ($ln -match '^\s*EXTERNAL FUNCTIONS:\s*$') {
            $inExternalFunctions = $true;  $inLocalFunctions = $false; $inVarSection = $false; continue
        }
        elseif ($ln -match '^\s*LOCAL FUNCTIONS:') {
            $inLocalFunctions = $true; $inExternalFunctions = $false; $inVarSection = $false; continue
        }
        elseif ($ln -match '^\s*(?:EXTERNAL VARIABLES|GLOBAL VARIABLES|PARAMETERS|RETURN TYPE):') {
            $inExternalFunctions = $false; $inLocalFunctions = $false; $inVarSection = $true; continue
        }

        # For variable/parameter/return sections: only collect types when passing is IN, INOUT, IN/OUT, or OUT.
        # Lines without a [Passing: ...] tag (section separators, empty lines) are skipped.
        if ($inVarSection) {
            if ($ln -match '\[Passing:') {
                if ($ln -notmatch '\[Passing:\s*(?:IN(?:/OUT)?|INOUT|OUT)\]') { continue }
            } else {
                continue
            }
        }

        # For function sections (EXTERNAL or LOCAL): only resolve types if the
        # function is actually called in conditions.c (i.e., it needs a stub).
        # Functions not called do not need their parameter/return types resolved.
        if ($inExternalFunctions -or $inLocalFunctions) {
            if ($ln -match '\b(?:enum|union|struct)\s+\w+') {
                $fnName = $null
                if ($ln -match '(?:void|[\w*]+)\s+(\w+)\s*\(') { $fnName = $Matches[1] }
                if ($fnName -and $condText -notmatch "\b$([regex]::Escape($fnName))\b") {
                    Write-Host "  [SKIP] Types from uncalled function: $fnName" -ForegroundColor DarkGray
                    continue
                }
            }
        }

        foreach ($m in [regex]::Matches($ln, '\b(?:enum|union|struct)\s+(\w+)')) {
            [void]$typeNames.Add($m.Groups[1].Value)
        }
    }
}

# From conditions.c declaration lines AND any _t/_un/_en type names used
$primitives = @('void','u8','u16','u32','u64','s8','s16','s32','int','char',
                'unsigned','signed','float','double','long','short','static','const','boolean_t')
$storageQualifiers = 'static|extern|volatile|const|register'
# Scan full conditions text for typedef-suffix names (_t / _un / _en only).
# _st is intentionally excluded: in this codebase _st is used for both struct
# type names AND struct variable instance names, making it ambiguous. All
# relevant _st types are already captured from the interface_info.txt scan above.
foreach ($m3 in [regex]::Matches($condText, '\b([a-z]\w+_(?:t|un|en))\b')) {
    $tn3 = $m3.Groups[1].Value
    if ($tn3 -notin $primitives) {
        [void]$typeNames.Add($tn3)
    }
}
foreach ($line in $condLines) {
    # Strip leading storage-class / type-qualifier keywords so that:
    #   "static boolean_t isDiag..." -> "boolean_t isDiag..."  (extracts boolean_t, not static)
    $trim = $line.Trim() -replace "^($storageQualifiers)(\s+($storageQualifiers))*\s+", ''
    # Try declaration pattern: TypeName varName[...]; or TypeName varName = ...
    $m2 = [regex]::Match($trim, '^([a-zA-Z_]\w+)\s+\w+\s*[=;\[]')
    if ($m2.Success) {
        $tn = $m2.Groups[1].Value
        if ($tn -notin $primitives -and $tn -notmatch '^[A-Z_]+$') {
            [void]$typeNames.Add($tn)
        }
    }
}

Write-Host "  Types to resolve: $($typeNames -join ', ')" -ForegroundColor White

# ---------------------------------------------------------------------------
# Step B — Find typedef/enum blocks for each type name
# ---------------------------------------------------------------------------
Write-Host "`n[B] Looking up typedef blocks in source headers..." -ForegroundColor Yellow

$typeBlocks = [ordered]@{}
foreach ($tn in ($typeNames | Sort-Object)) {
    Write-Host "  -> $tn " -ForegroundColor White -NoNewline
    $block = Find-TypeBlock -TypeName $tn
    if ($block) {
        $cleaned = Clean-TypeBlock -Block $block
        $typeBlocks[$tn] = $cleaned
        Write-Host "[FOUND $($cleaned.Split("`n").Count) lines]" -ForegroundColor Green
    } else {
        Write-Host "[not found]" -ForegroundColor Gray
    }
}

# ---------------------------------------------------------------------------
# Step C — Find #define lines for ALL_CAPS tokens in conditions.c
# ---------------------------------------------------------------------------
Write-Host "`n[C] Resolving #define constants from conditions.c..." -ForegroundColor Yellow

$skipTokens = [System.Collections.Generic.HashSet[string]]@(
    'TRUE','FALSE','NULL','INOUT','IN','OUT','IRRELEVANT','VOID','LCOV_EXCL_BR_LINE'
)
$defineLines = [ordered]@{}

foreach ($line in $condLines) {
    foreach ($m in [regex]::Matches($line, '\b([A-Z][A-Z0-9_]{3,})\b')) {
        $token = $m.Groups[1].Value
        if ($skipTokens.Contains($token)) { continue }
        if ($defineLines.Contains($token)) { continue }
        $def = Find-DefineLine -Token $token
        if ($def) {
            $defineLines[$token] = $def
            Write-Host "  $def" -ForegroundColor Green
        }
    }
}

if ($defineLines.Count -eq 0) {
    Write-Host "  (none found)" -ForegroundColor Gray
}

# ---------------------------------------------------------------------------
# Step D — Find const variable/array definitions referenced in conditions.c
# ---------------------------------------------------------------------------
Write-Host "`n[D] Resolving const variable/array definitions..." -ForegroundColor Yellow

# Collect locally declared identifiers: function params + local variable names
# Process line-by-line to avoid cross-line \s backtracking on multiline $condText.
$localNames = [System.Collections.Generic.HashSet[string]]::new()

foreach ($line in $condLines) {
    $trim = $line.Trim()
    if (-not $trim) { continue }

    # Function signature: ReturnType FuncName(params...) — capture param names
    $sig = [regex]::Match($trim, '^\w[\w.*\[\]]*\s+\w+\s*\(([^)]*)\)')
    if ($sig.Success) {
        foreach ($param in ($sig.Groups[1].Value -split ',')) {
            $lw = [regex]::Match($param.Trim(), '\b(\w+)\s*$')
            if ($lw.Success) { [void]$localNames.Add($lw.Groups[1].Value) }
        }
    }

    # Local variable declaration: [qualifiers] Type VarName [= ...] ;
    $mv = [regex]::Match($trim, '^(?:(?:static|extern|volatile|const)\s+)*[a-zA-Z_]\w*\s+(\w+)\s*[=;]')
    if ($mv.Success) { [void]$localNames.Add($mv.Groups[1].Value) }
}

# Find identifiers used as arrays (name[...]) that are not locally declared
$constVarCandidates = [System.Collections.Generic.HashSet[string]]::new()
foreach ($m5 in [regex]::Matches($condText, '(?<![.>])\b([a-zA-Z_]\w+)\s*\[')) {
    $id = $m5.Groups[1].Value
    if (($id -cmatch '^[a-z_]') -and (-not $localNames.Contains($id))) {
        [void]$constVarCandidates.Add($id)
    }
}

Write-Host "  Candidates: $(($constVarCandidates | Sort-Object) -join ', ')" -ForegroundColor White

$constVarBlocks = [ordered]@{}
foreach ($id in ($constVarCandidates | Sort-Object)) {
    Write-Host "  -> $id " -ForegroundColor White -NoNewline
    $block = Find-ConstVarBlock -VarName $id
    if ($block) {
        $constVarBlocks[$id] = $block
        Write-Host "[FOUND $($block.Split("`n").Count) lines]" -ForegroundColor Green
    } else {
        Write-Host "[not found]" -ForegroundColor Gray
    }
}

if ($constVarBlocks.Count -eq 0) {
    Write-Host "  (none found)" -ForegroundColor Gray
}

# ---------------------------------------------------------------------------
# Step C2 — Enum-member identifiers: PascalCase/MixedCase identifiers
# (e.g. DRL_Activate, PO_Activate, TI_Open) that are enum members from a
# typedef NOT listed in the interface info.  For each:
#   1. Find the containing typedef enum in source headers.
#   2. Add its full typedef block to $typeBlocks.
#   3. Compute each member's numeric value and add  #define MEMBER value
#      entries to $defineLines so Step 6 knows exact integer values.
# This is required because these identifiers are used as bit-position
# arguments to aniSpdApplGetInputMaskBit() and similar macros — their
# numeric values determine which bit of the mask variable to test.
# ---------------------------------------------------------------------------
Write-Host "`n[C2] Resolving enum-member identifiers (PascalCase + ALL_CAPS not found as #define) from conditions.c..." -ForegroundColor Yellow

# Collect:
#   - PascalCase/MixedCase identifiers (may contain lowercase) — classic enum members
#   - ALL_CAPS identifiers that Step C could NOT resolve as a #define macro
#     (e.g. WEL_PWM_BIT1, WEL_PWM_BIT2 which are enum values, not #define constants)
$enumMemberCandidates = [System.Collections.Generic.HashSet[string]]::new()
foreach ($m in [regex]::Matches($condText, '\b([A-Z][a-zA-Z0-9_]+)\b')) {
    $id = $m.Groups[1].Value
    if ($skipTokens.Contains($id))         { continue }
    if ($defineLines.Contains($id))        { continue }  # already resolved (fixed: ContainsKey -> Contains)
    if ($localNames.Contains($id))         { continue }  # local var/param
    # ALL_CAPS tokens already resolved by Step C are skipped above; unresolved ones fall through here
    [void]$enumMemberCandidates.Add($id)
}
Write-Host "  Candidates: $(($enumMemberCandidates | Sort-Object) -join ', ')" -ForegroundColor White

$enumMemberResolvedTypes = [System.Collections.Generic.HashSet[string]]::new()
foreach ($candidate in ($enumMemberCandidates | Sort-Object)) {
    $esc  = [regex]::Escape($candidate)
    $found = $false
    foreach ($sf in ((Get-SrcFiles) | Where-Object { $_.Extension -eq '.h' })) {
        $txt = Get-CachedFile $sf.FullName
        if (-not $txt -or $txt -notmatch "\b$esc\b") { continue }

        # Walk all typedef enum blocks in this header to find the one containing $candidate
        foreach ($km in [regex]::Matches($txt, '(?ms)(typedef\s+enum\b[^{]*)(\{)')) {
            $afterOpen = $km.Index + $km.Length
            $depth = 1; $idx = $afterOpen
            while ($idx -lt $txt.Length -and $depth -gt 0) {
                if     ($txt[$idx] -eq '{') { $depth++ }
                elseif ($txt[$idx] -eq '}') { $depth-- }
                $idx++
            }
            $closingSlice = $txt.Substring($idx, [Math]::Min(80, $txt.Length - $idx))
            if ($closingSlice -notmatch '^\s*(\w+)\s*;') { continue }
            $enumTypeName = $Matches[1]
            $enumBody     = $txt.Substring($afterOpen, $idx - $afterOpen - 1)
            if ($enumBody -notmatch "\b$esc\b") { continue }

            # Found the containing enum typedef — only add the typedef block if the type
            # name itself is referenced in conditions.c (e.g. as a cast or variable type).
            # If only a member value is used, the #define entries below are sufficient.
            $typeNameEsc2 = [regex]::Escape($enumTypeName)
            if (-not $typeBlocks.Contains($enumTypeName) -and $condText -match "\b$typeNameEsc2\b") {
                $block = Find-TypeBlock -TypeName $enumTypeName
                if ($block) {
                    $typeBlocks[$enumTypeName] = Clean-TypeBlock -Block $block
                    Write-Host "  [+TYPEDEF] $enumTypeName  (contains member $candidate)" -ForegroundColor Green
                }
            }

            # Resolve every member value of this enum -> add as #define lines
            if (-not $enumMemberResolvedTypes.Contains($enumTypeName)) {
                [void]$enumMemberResolvedTypes.Add($enumTypeName)
                $curVal = 0
                foreach ($eLine in ($enumBody -split '[\r\n]+')) {
                    $eClean = ($eLine -replace '/\*.*?\*/', '' -replace '//[^\r\n]*', '').Trim().TrimEnd(',').Trim()
                    if ($eClean -eq '' -or $eClean -match '^/') { continue }
                    if ($eClean -match '^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+)$') {
                        $mName  = $Matches[1]
                        $mExpr  = ($Matches[2].Trim() -replace '[UuLl]+$', '' -replace '\s', '')
                        try { $curVal = [int]$mExpr } catch { }
                        if (-not $defineLines.Contains($mName)) {
                            $defineLines[$mName] = "#define $mName  $curVal  /* $enumTypeName */"
                        }
                        $curVal++
                    } elseif ($eClean -match '^([A-Za-z_][A-Za-z0-9_]*)$') {
                        $mName = $Matches[1]
                        if (-not $defineLines.Contains($mName)) {
                            $defineLines[$mName] = "#define $mName  $curVal  /* $enumTypeName */"
                        }
                        $curVal++
                    }
                }
                Write-Host "  [+DEFINES] ${enumTypeName}: $curVal member values resolved" -ForegroundColor DarkGreen
            }
            $found = $true
            break
        }
        if ($found) { break }
    }
    if (-not $found) {
        # Fallback: identifier may be a mixed-case #define constant (e.g. DioDrv_Level_High)
        # that Step C missed because its regex only catches ALL_CAPS tokens.
        $def = Find-DefineLine -Token $candidate
        if ($def) {
            $defineLines[$candidate] = $def
            Write-Host "  [+DEFINE fallback] $def" -ForegroundColor Green
        } else {
            Write-Host "  [?] $candidate not found in any enum or #define" -ForegroundColor DarkGray
        }
    }
}
if ($enumMemberCandidates.Count -eq 0) { Write-Host "  (none found)" -ForegroundColor Gray }

# ---------------------------------------------------------------------------
# Step E — Detect macro functions called in conditions.c and resolve them
#           to their backing cfgRomContainerROM_DS* array access.
#
# Pattern in cfg_inc*.h (USE_SECTION_ROM_CONTAINER variant):
#   #define cfgGetXxx_u8()        ... cfgRomContainerMacroROM_DS1...(a,b,c,d,e,f) ...
#   #define cfgRomContainerMacroROM_DS1...(a,b,c,d,e,f) cfgRomContainerROM_DS1[(d)+(e)+(f)]
#
# Resolution:
#   1. Find all camelCase function-like calls in conditions.c.
#   2. For each, search header files for a matching #define NAME( line.
#   3. From that expansion, extract the cfgRomContainerMacro* call and its
#      literal arguments a,b,c,d,e,f.
#   4. Find the cfgRomContainerMacro* definition to know which DSn array is used
#      and which argument slots form the index (e.g. [(d)+(e)+(f)]).
#   5. Substitute the literal values into the index expression (collapse zeros).
#   6. Output a human-readable comment + simplified #define into the file.
# ---------------------------------------------------------------------------
Write-Host "`n[E] Resolving macro functions called in conditions.c..." -ForegroundColor Yellow

# Helper: Given a cfgRomContainerMacro definition line, return (arrayName, indexExpr)
# e.g.  cfgRomContainerROM_DS1[(d)+(e)+(f)]   ->  ("cfgRomContainerROM_DS1", "(d)+(e)+(f)")
function Parse-ContainerMacroDef {
    param([string]$DefLine)
    $m = [regex]::Match($DefLine, '(cfgRomContainer\w+)\s*\[([^\]]+)\]')
    if ($m.Success) {
        return $m.Groups[1].Value, $m.Groups[2].Value
    }
    return $null, $null
}

# Helper: Substitute literal arg values into an index expression like "(d)+(e)+(f)"
# argMap: hashtable  a->val, b->val, c->val, d->val, e->val, f->val
# Handles cases like (x)*2U inside e-slot that already came substituted.
function Resolve-IndexExpr {
    param([string]$Expr, [hashtable]$ArgMap)
    $r = $Expr
    # Replace each named slot with its value (longest names first to avoid partial match)
    foreach ($k in ($ArgMap.Keys | Sort-Object { $_.Length } -Descending)) {
        $v = $ArgMap[$k]
        if ($v -match '^\(') { $r = $r -replace "\b$k\b", $v }
        else                  { $r = $r -replace "\b$k\b", "($v)" }
    }
    # Strip all U/u suffixes from numeric literals
    $r = $r -replace '(?<=\d)[Uu]+', ''
    # Remove (unsigned_t) casts that may remain
    $r = $r -replace '\(unsigned_t\)\s*', ''
    # Flatten redundant outer parens iteratively
    for ($pass = 0; $pass -lt 10; $pass++) {
        $prev = $r
        # Unwrap single numeric: (0) -> 0
        $r = [regex]::Replace($r, '\((\d+)\)', '$1')
        # Evaluate pure numeric multiplications: (N*M) or N*M
        $r = [regex]::Replace($r, '\((\d+)\*(\d+)\)', { param($m2) [string]([int]$m2.Groups[1].Value * [int]$m2.Groups[2].Value) })
        # Remove zero addition terms
        $r = $r -replace '\+\s*\(0\)', ''
        $r = $r -replace '\(0\)\s*\+', ''
        $r = $r -replace '\+\s*0\b', ''
        $r = $r -replace '\b0\s*\+', ''
        # Strip outermost wrapping parens if entire expression is one balanced group
        if ($r.Length -ge 2 -and $r[0] -eq '(') {
            $d = 0; $earlyClose = $false
            for ($i = 0; $i -lt $r.Length; $i++) {
                if ($r[$i] -eq '(') { $d++ }
                elseif ($r[$i] -eq ')') { $d--; if ($d -eq 0 -and $i -lt ($r.Length - 1)) { $earlyClose = $true; break } }
            }
            if (-not $earlyClose -and $d -eq 0) { $r = $r.Substring(1, $r.Length - 2) }
        }
        if ($r -eq $prev) { break }
    }
    $r = $r.Trim('+', ' ').Trim()
    if ($r -match '^[\(\)0\+\s]+$') { return '0' }
    return $r
}

# Collect all camelCase function-like calls in conditions.c (not ALL_CAPS, not local vars)
$macroFuncCalls = [System.Collections.Generic.HashSet[string]]::new()
foreach ($m in [regex]::Matches($condText, '\b([a-z][a-zA-Z0-9_]*)\s*\(')) {
    [void]$macroFuncCalls.Add($m.Groups[1].Value)
}
# Remove names that are local variables or primitives
foreach ($loc in $localNames) { [void]$macroFuncCalls.Remove($loc) }

$macroFuncResolutions = [ordered]@{}         # name -> verbatim #define line
$containerMacroVerbatimLines = [ordered]@{}   # containerMacroName -> verbatim #define line

foreach ($name in ($macroFuncCalls | Sort-Object)) {
    $esc = [regex]::Escape($name)

    # Search all headers for:  #define <name>( ...
    $macroDefLine = $null
    $macroDefFile = $null
    foreach ($sf in (Get-SrcFiles)) {
        if ($sf.Extension -ne '.h') { continue }
        $txt2 = Get-CachedFile $sf.FullName
        if (-not $txt2) { continue }
        $mDef = [regex]::Match($txt2, "(?m)^\s*#\s*define\s+$esc\s*\(([^)]*)\)\s+(.+)")
        if ($mDef.Success) {
            $macroDefLine = $mDef.Value.Trim()
            $macroDefFile = $sf.FullName
            break
        }
    }

    if (-not $macroDefLine) {
        # Not a macro — real function, skip
        continue
    }

    Write-Host "  [MACRO] $name" -ForegroundColor Cyan
    Write-Host "          $macroDefLine" -ForegroundColor DarkGray

    # Extract the formal parameter list and expansion body
    $mParsed = [regex]::Match($macroDefLine, "#\s*define\s+$esc\s*\(([^)]*)\)\s+(.*)")
    if (-not $mParsed.Success) {
        Write-Host "          [SKIP] Cannot parse macro definition." -ForegroundColor Yellow
        continue
    }
    $formalParams = ($mParsed.Groups[1].Value -split ',') | ForEach-Object { $_.Trim() }
    $expansion    = $mParsed.Groups[2].Value.Trim()

    # Find cfgRomContainerMacro* call inside the expansion.
    # Use brace-depth walking to extract the full argument list (args contain parens).
    $mContName = [regex]::Match($expansion, 'cfgRomContainerMacro\w+')
    if (-not $mContName.Success) {
        # Simple utility macro (not cfgRomContainer) — copy verbatim so Step 6 can see the expansion.
        Write-Host "          [SIMPLE MACRO] copied verbatim" -ForegroundColor DarkGreen
        $macroFuncResolutions[$name] = $macroDefLine.Trim()
        continue
    }
    $containerMacroName = $mContName.Value

    # Find the opening '(' of the macro call and walk to the matching ')'
    $callStart = $expansion.IndexOf($containerMacroName)
    $openIdx   = $expansion.IndexOf('(', $callStart + $containerMacroName.Length)
    if ($openIdx -lt 0) {
        Write-Host "          [SKIP] Cannot find arg list for $containerMacroName." -ForegroundColor Yellow
        continue
    }
    $depth3 = 1; $idx3 = $openIdx + 1
    while ($idx3 -lt $expansion.Length -and $depth3 -gt 0) {
        if     ($expansion[$idx3] -eq '(') { $depth3++ }
        elseif ($expansion[$idx3] -eq ')') { $depth3-- }
        $idx3++
    }
    $rawContainerArgs = $expansion.Substring($openIdx + 1, $idx3 - $openIdx - 2)

    # Parse the 6 literal args (a..f) — split on commas not inside parens
    $argTokens = @()
    $depth2 = 0; $cur = ''
    foreach ($ch in $rawContainerArgs.ToCharArray()) {
        if     ($ch -eq '(') { $depth2++; $cur += $ch }
        elseif ($ch -eq ')') { $cur += $ch; $depth2-- }
        elseif ($ch -eq ',' -and $depth2 -eq 0) { $argTokens += $cur.Trim(); $cur = '' }
        else   { $cur += $ch }
    }
    if ($cur.Trim()) { $argTokens += $cur.Trim() }

    # Strip casts and trailing U/u from each arg token
    $cleanArgs = $argTokens | ForEach-Object {
        $a = $_ -replace '/\*[^*]*\*/', ''            # strip /* ... */ inline comments
        $a = $a -replace '\(unsigned_t\)\s*', ''      # strip (unsigned_t) cast
        $a = $a -replace '\(unsigned\s+int\)\s*', ''  # strip (unsigned int) cast
        $a = $a.Trim()
        # Strip outer parens wrapping a single token: ((x)*2) stays, (0) -> 0
        if ($a -match '^\(([^()]+)\)$') { $a = $Matches[1].Trim() }
        # Strip trailing U or u suffix from numeric literals
        $a = $a -replace '(?<=\d)[Uu]+$', ''
        $a = $a -replace '(?<=\d)[Uu](?=\*)', ''     # e.g. 2U* -> 2*
        $a.Trim()
    }

    # Map formal params of the cfgRomContainerMacro (always a,b,c,d,e,f) to the literal values
    $slots = 'a','b','c','d','e','f'
    $argMap = @{}
    for ($i = 0; $i -lt [Math]::Min($slots.Count, $cleanArgs.Count); $i++) {
        $argMap[$slots[$i]] = $cleanArgs[$i]
    }

    # Substitute the macro's formal param (e.g. "x") into each arg slot value
    # so that  e = "(x)*2"  with formalParams=@("x") becomes available for later substitution
    # (we keep it symbolic — actual slot value may still contain "x")

    # Find the cfgRomContainerMacro definition to know DSn and index slots.
    # Prefer the definition that resolves to a plain cfgRomContainerROM_DS* array
    # (i.e. the USE_SECTION_ROM_CONTAINER variant).  If not found, fall back to first match.
    $containerDefLine = $null
    $containerVerbatimLine = $null
    foreach ($sf in (Get-SrcFiles)) {
        if ($sf.Extension -ne '.h') { continue }
        $txt3 = Get-CachedFile $sf.FullName
        if (-not $txt3) { continue }
        $escCM = [regex]::Escape($containerMacroName)
        foreach ($mCD in [regex]::Matches($txt3, "(?m)^\s*#\s*define\s+$escCM\s*\(a,b,c,d,e,f\)\s+(.+)")) {
            $candidate = $mCD.Groups[1].Value.Trim()
            # Prefer a definition whose array name is exactly cfgRomContainerROM_DS1/DS2/DS3
            # (no further suffix like LE_ARLC_xxx) — that is the USE_SECTION_ROM_CONTAINER form
            if ($candidate -match 'cfgRomContainerROM_DS\d\s*\[') {
                $containerDefLine = $candidate
                $containerVerbatimLine = $mCD.Value.Trim()
                break
            }
            # Keep as fallback if nothing better found yet
            if (-not $containerDefLine) {
                $containerDefLine = $candidate
                $containerVerbatimLine = $mCD.Value.Trim()
            }
        }
        if ($containerDefLine -match 'cfgRomContainerROM_DS\d\s*\[') { break }
    }
    # Save verbatim container macro definition (deduplicated by name)
    if ($containerVerbatimLine -and -not $containerMacroVerbatimLines.Contains($containerMacroName)) {
        $containerMacroVerbatimLines[$containerMacroName] = $containerVerbatimLine
    }

    if (-not $containerDefLine) {
        Write-Host "          [SKIP] Cannot find definition of $containerMacroName." -ForegroundColor Yellow
        continue
    }

    $arrayName, $indexExpr = Parse-ContainerMacroDef -DefLine $containerDefLine
    if (-not $arrayName) {
        Write-Host "          [SKIP] Cannot parse container macro: $containerDefLine" -ForegroundColor Yellow
        continue
    }

    # Resolve index expression with known literal values (d, e, f etc.)
    $resolvedIndex = Resolve-IndexExpr -Expr $indexExpr -ArgMap $argMap

    # Determine if macro has parameters (i.e. it's parametric like cfgGetXxx_u16(x))
    $hasParam     = ($formalParams.Count -gt 0 -and $formalParams[0] -ne '')
    $paramName    = if ($hasParam) { $formalParams[0] } else { '' }

    # Log the resolution for diagnostic purposes
    $resolution = "${arrayName}[${resolvedIndex}]"
    Write-Host "          -> $resolution" -ForegroundColor Green

    # Store the verbatim #define line from the header
    $macroFuncResolutions[$name] = $macroDefLine.Trim()
}

if ($macroFuncResolutions.Count -eq 0) {
    Write-Host "  (none found)" -ForegroundColor Gray
}

# ---------------------------------------------------------------------------
# Helper: strip all C inline comments (/* ... */ and // ...) from a text block.
# Used when writing sections of _after_passing.c to reduce output tokens.
# ---------------------------------------------------------------------------
function Strip-CComments {
    param([string]$Text)
    # Remove multi-line /* ... */ comments (non-greedy)
    $Text = [regex]::Replace($Text, '/\*.*?\*/', '', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    # Remove single-line // ... comments
    $Text = [regex]::Replace($Text, '//[^\r\n]*', '')
    # Collapse lines that became blank after comment removal
    $lines = ($Text -split "`r?`n") | Where-Object { $_.Trim() -ne '' }
    return ($lines -join "`n")
}

# ---------------------------------------------------------------------------
# Assemble output file
# ---------------------------------------------------------------------------
$sb = [System.Text.StringBuilder]::new()

# 1. Interface info as a comment header — skip any line tagged [Passing: IRRELEVANT]
#    Also skip all indented child lines that belong to an IRRELEVANT parent.
if ($interfaceText) {
    [void]$sb.AppendLine("/*")
    $skipChildrenBelowIndent = -1   # indentation level of the skipped IRRELEVANT parent
    foreach ($ln in ($interfaceText -split "`r?`n")) {
        # Measure leading-space indent of this line
        $lineIndent = 0
        if ($ln -match '^(\s+)') { $lineIndent = $Matches[1].Length }

        # If we are inside a skipped IRRELEVANT parent block, skip all deeper-indented children
        if ($skipChildrenBelowIndent -ge 0) {
            if ($lineIndent -gt $skipChildrenBelowIndent) { continue }
            else { $skipChildrenBelowIndent = -1 }   # back to same or lower level — stop skipping
        }

        # Skip this line and remember its indent so children are also skipped
        if ($ln -match '\[Passing:\s*IRRELEVANT\]') {
            $skipChildrenBelowIndent = $lineIndent
            continue
        }

        [void]$sb.AppendLine(" * $ln")
    }
    [void]$sb.AppendLine(" */")
    [void]$sb.AppendLine()
}

# 2. #define constants (strip inline comments from each line)
if ($defineLines.Count -gt 0) {
    foreach ($kv in $defineLines.GetEnumerator()) {
        $defLine = [regex]::Replace($kv.Value, '/\*.*?\*/', '').TrimEnd()
        [void]$sb.AppendLine($defLine)
    }
    [void]$sb.AppendLine()
}

# 3. typedef / enum blocks (strip inline comments)
if ($typeBlocks.Count -gt 0) {
    foreach ($kv in $typeBlocks.GetEnumerator()) {
        [void]$sb.AppendLine()
        [void]$sb.AppendLine((Strip-CComments -Text $kv.Value))
    }
    [void]$sb.AppendLine()
}

# 4. Const variable and array definitions (strip inline comments)
if ($constVarBlocks.Count -gt 0) {
    foreach ($kv in $constVarBlocks.GetEnumerator()) {
        [void]$sb.AppendLine()
        [void]$sb.AppendLine((Strip-CComments -Text $kv.Value))
    }
    [void]$sb.AppendLine()
}

# 5. Macro function resolutions — verbatim #define lines copied from header
if ($macroFuncResolutions.Count -gt 0) {
    foreach ($kv in $containerMacroVerbatimLines.GetEnumerator()) {
        $defLine = [regex]::Replace($kv.Value, '/\*.*?\*/', '').TrimEnd()
        [void]$sb.AppendLine($defLine)
    }
    foreach ($kv in $macroFuncResolutions.GetEnumerator()) {
        $defLine = [regex]::Replace($kv.Value, '/\*.*?\*/', '').TrimEnd()
        [void]$sb.AppendLine($defLine)
    }
    [void]$sb.AppendLine()
}

# 6. Function code — strip inline comments
[void]$sb.AppendLine()
[void]$sb.Append((Strip-CComments -Text $condText))

# ---------------------------------------------------------------------------
# Save
# ---------------------------------------------------------------------------
$outDir = "$WorkingDir\testObjectCode"
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Path $outDir -Force | Out-Null }

$outputFile = "$outDir\${TestObject}_conditions_after_passing.c"
[System.IO.File]::WriteAllText($outputFile, $sb.ToString(), [System.Text.Encoding]::UTF8)

Write-Host "`n[SAVED] $outputFile" -ForegroundColor Green
Write-Host "`n  Content:" -ForegroundColor Cyan
Write-Host "--------------------------------------------------------------------------------" -ForegroundColor Gray
Get-Content $outputFile | ForEach-Object { Write-Host $_ }
Write-Host "--------------------------------------------------------------------------------" -ForegroundColor Gray

Write-Host "`n================================================================================" -ForegroundColor Cyan
Write-Host "  STEP 5 COMPLETE" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "NEXT STEP:" -ForegroundColor Yellow
Write-Host "  Run step6_list_testcases.ps1" -ForegroundColor White
Write-Host ""

exit 0
