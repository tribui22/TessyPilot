# ============================================================================
# STEP 4: Strip Function to Condition-Relevant Code Only
# ============================================================================
# Purpose: Read the raw function saved by step 3 (or re-extract it from
#          source), remove all metadata noise, and keep only the code that
#          matters for test-case reasoning:
#            - if / else / switch / case / while / do / for structures
#            - Variable declarations and assignments for every variable that
#              appears in a condition or in a return statement
#            - Function calls whose return value feeds into a condition
#          Saves the result to:
#              <WorkingDir>\testObjectCode\<TestObject>_conditions.c
#
# Usage:
#   .\step4_strip_conditions.ps1 `
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

# ============================================================================
# Helper: Strip function body to condition-relevant code only.
# Removes: metadata comments (PRQA, GUID, /*#[...]*/, DDC, polyspace),
#          void side-effect calls not used in any condition.
# Keeps:   if/else/switch/case/while/do/for structures, variable declarations
#          and assignments for variables that appear in conditions or returns,
#          function calls whose return value feeds into conditions.
# Returns: cleaned function text (signature + stripped body).
# ============================================================================
function Strip-FunctionToConditions {
    param(
        [string]$FuncSignature,   # Function signature (return type + name + params)
        [string]$FuncBody         # Function body content (between { and }, exclusive)
    )

    # --- Step 1: Remove metadata comments from body ---
    $clean = $FuncBody
    $clean = $clean -replace '(?s)/\*#\[.*?\*/', ''               # /*#[ ... */ Rhapsody markers
    $clean = $clean -replace '/\*#\]\s*\*/', ''                   # /*#]*/ end markers
    $clean = $clean -replace '/\*[^*]*\bGUID\b[^*]*\*/', ''      # GUID comments
    $clean = $clean -replace '/\*\s*PRQA\s+S\s+\d[^*]*\*/', ''   # PRQA inline comments
    $clean = $clean -replace '/\*\s*-->DDC=FCT[^*]*\*/', ''       # DDC=FCT comments
    $clean = $clean -replace '/\*\s*polyspace[^*]*\*/', ''        # polyspace comments
    $clean = $clean -replace '/\*\s*Metric:[^*]*\*/', ''          # Metric comments
    $clean = $clean -replace '//[^\n]*LCOV[^\n]*', ''             # LCOV_EXCL lines
    $clean = $clean -replace '/\*[^*]*LCOV[^*]*\*/', ''           # /*LCOV_EXCL_BR_LINE*/ inline

    # --- Step 2: Collect variable names from conditions and return statements ---
    $condVarSet = [System.Collections.Generic.HashSet[string]]::new()

    # Variables in if-conditions (handle nested parens one level deep)
    foreach ($m in [regex]::Matches($clean, '\bif\s*\(((?:[^()]+|\([^()]*\))*)\)')) {
        foreach ($vm in [regex]::Matches($m.Groups[1].Value, '\b([a-zA-Z_]\w*)\b')) {
            [void]$condVarSet.Add($vm.Groups[1].Value)
        }
    }
    # Variables in while-conditions
    foreach ($m in [regex]::Matches($clean, '\bwhile\s*\(((?:[^()]+|\([^()]*\))*)\)')) {
        foreach ($vm in [regex]::Matches($m.Groups[1].Value, '\b([a-zA-Z_]\w*)\b')) {
            [void]$condVarSet.Add($vm.Groups[1].Value)
        }
    }
    # Variables in switch expression
    foreach ($m in [regex]::Matches($clean, '\bswitch\s*\(([^)]+)\)')) {
        foreach ($vm in [regex]::Matches($m.Groups[1].Value, '\b([a-zA-Z_]\w*)\b')) {
            [void]$condVarSet.Add($vm.Groups[1].Value)
        }
    }
    # Remove C keywords / type names that are not variable names
    $keywords = @('if','else','while','for','do','switch','case','default','break','continue','return',
        'NULL','TRUE','FALSE','void','u8','u16','u32','u64','s8','s16','s32','boolean_t',
        'int','char','static','const','unsigned','signed','sizeof','0U','1U','0','1')
    foreach ($kw in $keywords) { [void]$condVarSet.Remove($kw) }

    # --- Step 3: Join line-continuation lines (trailing \) before processing ---
    # C allows a logical line to span multiple physical lines using '\' at end.
    # Join them so the full condition is visible to the pattern matching below.
    $clean = [regex]::Replace($clean, '\\\s*\r?\n\s*', ' ')

    # --- Step 4: Process body line by line ---
    $lines       = $clean -split "`r?`n"
    $resultLines = @()
    $braceDepth  = 0   # tracks nesting inside the function body

    $isVarReferencedInLaterCondition = {
        param(
            [string]$VarName,
            [int]$CurrentLineIndex
        )

        $esc = [regex]::Escape($VarName)
        for ($scanIndex = $CurrentLineIndex + 1; $scanIndex -lt $lines.Count; $scanIndex++) {
            $scanLine = $lines[$scanIndex].Trim()
            if (-not $scanLine) { continue }
            if ($scanLine -match "^(if|else(\s+if)?|switch|while|for)\b" -and
                $scanLine -match "\b$esc\b") {
                return $true
            }
        }
        return $false
    }

    for ($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++) {
        $rawLine = $lines[$lineIndex]
        $trimmed = $rawLine.Trim()

        # Always keep empty lines (normalised later)
        if ($trimmed -eq '') { $resultLines += ''; continue }

        # Skip lines that became pure/empty comments after cleaning
        if ($trimmed -match '^/\*\s*\*/\s*$') { continue }
        if ($trimmed -match '^//') { continue }
        if ($trimmed -match '^/\*[^*]*\*/\s*$') { continue }

        # Keep control-flow keywords (always, regardless of nesting depth)
        if ($trimmed -match '^(if|else(\s+if)?|switch|while|do|for)\b') {
            $resultLines += $rawLine
            # If the condition spans multiple lines (unbalanced parens), consume continuation lines
            $openCount  = ($rawLine.ToCharArray() | Where-Object { $_ -eq '(' } | Measure-Object).Count
            $closeCount = ($rawLine.ToCharArray() | Where-Object { $_ -eq ')' } | Measure-Object).Count
            while ($openCount -gt $closeCount -and ($lineIndex + 1) -lt $lines.Count) {
                $lineIndex++
                $contLine = $lines[$lineIndex]
                $resultLines += $contLine
                $openCount  += ($contLine.ToCharArray() | Where-Object { $_ -eq '(' } | Measure-Object).Count
                $closeCount += ($contLine.ToCharArray() | Where-Object { $_ -eq ')' } | Measure-Object).Count
            }
            continue
        }
        if ($trimmed -match '^case[\s(]' -or $trimmed -match '^default\s*:') {
            $resultLines += $rawLine; continue
        }
        if ($trimmed -match '^(break|continue)\s*;') {
            $resultLines += $rawLine; continue
        }
        # return statements are dropped - not needed for condition analysis

        # Track opening brace: emit, then increase depth
        if ($trimmed -eq '{') {
            $resultLines += $rawLine
            $braceDepth++
            continue
        }
        # Track closing brace: decrease depth, then emit
        if ($trimmed -eq '}') {
            $braceDepth--
            $resultLines += $rawLine
            continue
        }

        # Keep declarations / assignments that feed a later condition.
        # This matters inside loops and nested blocks, for example:
        #   deviceId_u8 = chipaddress[deviceCnt_u8];
        #   if (TPS_DRV_CFG_MAX_DEVICE_ID >= deviceId_u8)
        # Terminal side-effects that do not influence any later condition are dropped.
        $keepLine = $false
        foreach ($cv in $condVarSet) {
            $esc = [regex]::Escape($cv)
            $isConditionInputLine = $false

            # Declaration:  "type* cv = ..." or "type cv;" or "type cv = ..."
            if ($trimmed -match "(?:[\w\s\*]+)\s\*?$esc\s*[=;]") {
                $isConditionInputLine = $true
            }
            # Simple assignment or array assignment: "cv = ..." or "cv[...] = ..."
            elseif ($trimmed -match "^$esc\s*[\[=]") {
                $isConditionInputLine = $true
            }
            # Increment / decrement: "cv++" or "cv--" or "cv += ..." or "cv -= ..."
            elseif ($trimmed -match "^$esc\s*(\+\+|--|[+\-\*/%&|^]=)") {
                $isConditionInputLine = $true
            }
            # Prefix increment/decrement: "++cv" or "--cv"
            elseif ($trimmed -match "^(\+\+|--)\s*$esc\b") {
                $isConditionInputLine = $true
            }
            # Member / pointer assignment: "cv.member = ..." or "cv->member = ..."
            elseif ($trimmed -match "^$esc\s*[.\-]") {
                $isConditionInputLine = $true
            }

            if (-not $isConditionInputLine) { continue }

            if ($braceDepth -eq 0 -or (& $isVarReferencedInLaterCondition $cv $lineIndex)) {
                $keepLine = $true
                break
            }
        }
        if ($keepLine) { $resultLines += $rawLine; continue }

        # Everything else: dropped (void calls, unrelated assignments, etc.)
    }

    # Normalise: collapse consecutive blank lines to one
    $finalLines = @()
    $prevBlank  = $false
    foreach ($line in $resultLines) {
        $isBlank = ($line.Trim() -eq '')
        if ($isBlank -and $prevBlank) { continue }
        $finalLines += $line
        $prevBlank   = $isBlank
    }

    $strippedBody = ($finalLines -join "`n").Trim()
    return ($FuncSignature + "`n{`n" + $strippedBody + "`n}`n")
}

# ============================================================================
# Main
# ============================================================================

Write-Host "`n================================================================================" -ForegroundColor Cyan
Write-Host "  STEP 4: STRIP FUNCTION TO CONDITION-RELEVANT CODE" -ForegroundColor Cyan
Write-Host "  Test Object : $TestObject" -ForegroundColor Cyan
Write-Host "  Module      : $Module" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Prefer reading from step 3 output; fall back to extracting fromom source
# ---------------------------------------------------------------------------
$testObjectCodeDir = "$WorkingDir\testObjectCode"
$step31File        = "$testObjectCodeDir\${TestObject}.c"

if (Test-Path $step31File) {
    Write-Host "`n[READ] Using step 3 output: $step31File" -ForegroundColor Yellow
    $rawFunctionText = Get-Content $step31File -Raw
} else {
    Write-Host "`n[INFO] Step 3 file not found - extracting from source directly..." -ForegroundColor Yellow

    $ModuleBase = $Module -replace '\.c$', ''
    $sourcePath = Get-ChildItem -Path $SourceDir -Recurse -Filter "${ModuleBase}.c" -ErrorAction SilentlyContinue |
                  Select-Object -First 1

    if (-not $sourcePath) {
        Write-Host "[ERROR] Could not find source file: ${ModuleBase}.c in $SourceDir" -ForegroundColor Red
        exit 1
    }

    Write-Host "[READ] $($sourcePath.FullName)" -ForegroundColor Yellow
    $sourceContent = Get-Content $sourcePath.FullName -Raw

    $pattern    = "(?ms)([a-zA-Z_][a-zA-Z0-9_]*\s*\*?)\s+${TestObject}\s*\(([^)]*)\)"
    $allMatches = [regex]::Matches($sourceContent, $pattern)

    $functionMatch = $null
    foreach ($match in $allMatches) {
        $afterMatch = $sourceContent.Substring($match.Index + $match.Length)
        if ($afterMatch -match '^\s*(/\*.*?\*/)?\s*\{') { $functionMatch = $match; break }
    }

    # Fallback: search all .c files if not found in module-named file
    if (-not $functionMatch) {
        Write-Host "[INFO] Function not found in ${ModuleBase}.c - scanning all .c files in SourceDir..." -ForegroundColor Yellow
        $allCFiles = Get-ChildItem -Path $SourceDir -Recurse -Filter "*.c" -ErrorAction SilentlyContinue |
                     Where-Object { $_.FullName -ne $sourcePath.FullName }
        foreach ($cFile in $allCFiles) {
            $candidateContent = Get-Content $cFile.FullName -Raw
            $candidateMatches = [regex]::Matches($candidateContent, $pattern)
            foreach ($match in $candidateMatches) {
                $afterMatch = $candidateContent.Substring($match.Index + $match.Length)
                if ($afterMatch -match '^\s*(/\*.*?\*/)?\s*\{') {
                    $functionMatch = $match
                    $sourceContent = $candidateContent
                    Write-Host "[READ] $($cFile.FullName)" -ForegroundColor Yellow
                    break
                }
            }
            if ($functionMatch) { break }
        }
    }

    if (-not $functionMatch) {
        Write-Host "[ERROR] Could not find function definition for: $TestObject" -ForegroundColor Red
        exit 1
    }

    $signatureEnd     = $functionMatch.Index + $functionMatch.Length
    $remainingContent = $sourceContent.Substring($signatureEnd)

    if ($remainingContent -notmatch '^\s*(/\*.*?\*/)?\s*\{') {
        Write-Host "[ERROR] No opening brace found after function signature" -ForegroundColor Red
        exit 1
    }

    $braceStart = $Matches[0].Length
    $braceDepth = 1; $i = $braceStart

    while ($i -lt $remainingContent.Length -and $braceDepth -gt 0) {
        $c = $remainingContent[$i]
        if ($c -eq '{') { $braceDepth++ } elseif ($c -eq '}') { $braceDepth-- }
        $i++
    }

    if ($braceDepth -ne 0) {
        Write-Host "[ERROR] Could not find matching closing brace for: $TestObject" -ForegroundColor Red
        exit 1
    }

    $rawFunctionText = $sourceContent.Substring($functionMatch.Index, $signatureEnd + $i - $functionMatch.Index)
}

# ---------------------------------------------------------------------------
# Split: signature = everything up to and including the first {
#        body      = everything between the outer { and }
# ---------------------------------------------------------------------------
$sigMatch = [regex]::Match($rawFunctionText, '(?ms)^(.+?\))\s*(?:/\*[^*]*\*/)?\s*\{')
if (-not $sigMatch.Success) {
    Write-Host "[ERROR] Could not parse signature from function text" -ForegroundColor Red
    exit 1
}

$signature = $sigMatch.Groups[1].Value.Trim()

# Body: strip outer braces
$bodyMatch = [regex]::Match($rawFunctionText, '(?ms)\{(.*)\}', [System.Text.RegularExpressions.RegexOptions]::Singleline)
$funcBody  = if ($bodyMatch.Success) { $bodyMatch.Groups[1].Value } else { '' }

Write-Host "`n[STRIP] Applying condition filter..." -ForegroundColor Yellow
$strippedText = Strip-FunctionToConditions -FuncSignature $signature -FuncBody $funcBody

# ---------------------------------------------------------------------------
# Save to testObjectCode/<TestObject>_conditions.c
# ---------------------------------------------------------------------------
if (-not (Test-Path $testObjectCodeDir)) {
    New-Item -ItemType Directory -Path $testObjectCodeDir -Force | Out-Null
}

$outputFile = "$testObjectCodeDir\${TestObject}_conditions.c"
$strippedText | Out-File -FilePath $outputFile -Encoding UTF8

Write-Host "[SAVED] $outputFile" -ForegroundColor Green
Write-Host "`n  Content:" -ForegroundColor Cyan
Write-Host "--------------------------------------------------------------------------------" -ForegroundColor Gray
Write-Host $strippedText
Write-Host "--------------------------------------------------------------------------------" -ForegroundColor Gray

Write-Host "`n================================================================================" -ForegroundColor Cyan
Write-Host "  STEP 4 COMPLETE" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "NEXT STEP:" -ForegroundColor Yellow
Write-Host "  Run step5_resolve_defines.ps1" -ForegroundColor White
Write-Host ""

exit 0
