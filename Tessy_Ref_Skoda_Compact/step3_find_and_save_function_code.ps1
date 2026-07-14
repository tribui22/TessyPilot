# ============================================================================
# STEP 3: Find Function in Source and Save to testObjectCode/
# ============================================================================
# Purpose: Locate the function under test by name inside a source file and
#          save the complete, unmodified function text to:
#              <WorkingDir>\testObjectCode\<TestObject>.c
#          This file is the raw source reference for step 4, step 5, etc.
#
# Usage:
#   .\step3_find_and_save_function_code.ps1 `
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

Write-Host "`n================================================================================" -ForegroundColor Cyan
Write-Host "  STEP 3: FIND FUNCTION AND SAVE FULL FUNCTION CODE" -ForegroundColor Cyan
Write-Host "  Test Object : $TestObject" -ForegroundColor Cyan
Write-Host "  Module      : $Module" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

# ---------------------------------------------------------------------------
# Find source file
# ---------------------------------------------------------------------------
$ModuleBase = $Module -replace '\.c$', ''
$sourcePath = Get-ChildItem -Path $SourceDir -Recurse -Filter "${ModuleBase}.c" -ErrorAction SilentlyContinue |
              Select-Object -First 1

if (-not $sourcePath) {
    Write-Host "[ERROR] Could not find source file: ${ModuleBase}.c in $SourceDir" -ForegroundColor Red
    exit 1
}

Write-Host "`n[READ] $($sourcePath.FullName)" -ForegroundColor Yellow
$sourceContent = Get-Content $sourcePath.FullName -Raw

# ---------------------------------------------------------------------------
# Find the function definition (with opening brace, not the declaration with ;)
# Matches any return type including pointer types (e.g. u8*, u16*, void)
# ---------------------------------------------------------------------------
$pattern   = "(?ms)([a-zA-Z_][a-zA-Z0-9_]*\s*\*?)\s+${TestObject}\s*\(([^)]*)\)"
$allMatches = [regex]::Matches($sourceContent, $pattern)

$functionMatch = $null
foreach ($match in $allMatches) {
    $afterMatch = $sourceContent.Substring($match.Index + $match.Length)
    if ($afterMatch -match '^\s*(/\*.*?\*/)?\s*\{') {
        $functionMatch = $match
        break
    }
}

# ---------------------------------------------------------------------------
# Fallback: if not found in the module-named file, search all .c files
# ---------------------------------------------------------------------------
$foundInFile = $sourcePath.FullName
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
                $functionMatch  = $match
                $sourceContent  = $candidateContent
                $foundInFile    = $cFile.FullName
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

Write-Host "[READ] $foundInFile" -ForegroundColor Yellow

Write-Host "[FOUND] Function at position $($functionMatch.Index)" -ForegroundColor Green
Write-Host "  Return type : $($functionMatch.Groups[1].Value.Trim())" -ForegroundColor White
Write-Host "  Parameters  : $($functionMatch.Groups[2].Value.Trim())" -ForegroundColor White

# ---------------------------------------------------------------------------
# Extract the complete function text by brace counting
# ---------------------------------------------------------------------------
$signatureEnd     = $functionMatch.Index + $functionMatch.Length
$remainingContent = $sourceContent.Substring($signatureEnd)

if ($remainingContent -notmatch '^\s*(/\*.*?\*/)?\s*\{') {
    Write-Host "[ERROR] No opening brace found after function signature" -ForegroundColor Red
    exit 1
}

$braceStart = $Matches[0].Length
$braceDepth = 1
$i          = $braceStart

while ($i -lt $remainingContent.Length -and $braceDepth -gt 0) {
    $c = $remainingContent[$i]
    if     ($c -eq '{') { $braceDepth++ }
    elseif ($c -eq '}') { $braceDepth-- }
    $i++
}

if ($braceDepth -ne 0) {
    Write-Host "[ERROR] Could not find matching closing brace for: $TestObject" -ForegroundColor Red
    exit 1
}

# Full text = from signature start up to and including the closing brace
$fullFunctionText = $sourceContent.Substring($functionMatch.Index, $signatureEnd + $i - $functionMatch.Index)

# ---------------------------------------------------------------------------
# Save to testObjectCode/<TestObject>.c
# ---------------------------------------------------------------------------
$testObjectCodeDir = "$WorkingDir\testObjectCode"
if (-not (Test-Path $testObjectCodeDir)) {
    New-Item -ItemType Directory -Path $testObjectCodeDir -Force | Out-Null
}

$outputFile = "$testObjectCodeDir\${TestObject}.c"
$fullFunctionText | Out-File -FilePath $outputFile -Encoding UTF8

Write-Host "`n[SAVED] $outputFile" -ForegroundColor Green

Write-Host "`n================================================================================" -ForegroundColor Cyan
Write-Host "  STEP 3 COMPLETE" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "NEXT STEP:" -ForegroundColor Yellow
Write-Host "  Run step3_find_and_save_function_code.ps1 or step4_strip_conditions.ps1" -ForegroundColor White
Write-Host ""

exit 0
