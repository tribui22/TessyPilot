# ============================================================================
# STEP 5: Build Annotated Conditions File from Interface Info
# ============================================================================
# Configuration is loaded by common.ps1.
# ============================================================================

[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

. (Join-Path $PSScriptRoot "..\helpers\common.ps1")

$STEP       = "STEP5"
$TestObject = $Config.TestObjects
$Module     = $Config.Module
$SourceDir  = $Config.SourceDir
$WorkingDir = $Config.WorkDir

function Add-MissingExternalFunctions {
    param(
        [Parameter(Mandatory)][string]$RawSourceFile,
        [Parameter(Mandatory)][string]$AnnotatedFile,
        [Parameter(Mandatory)][string]$SourceRoot
    )

    $sourceText = Get-Content -LiteralPath $RawSourceFile -Raw -Encoding UTF8
    $annotatedText = Get-Content -LiteralPath $AnnotatedFile -Raw -Encoding UTF8

    $sectionPattern = '(?ms)(?<Header>^\s*\*\s*EXTERNAL FUNCTIONS:\s*\r?\n\s*\*\s*-+\s*\r?\n)(?<Body>.*?)(?=^\s*\*\s*LOCAL FUNCTIONS:)'
    $sectionMatch = [regex]::Match($annotatedText, $sectionPattern)

    if (-not $sectionMatch.Success) {
        throw "EXTERNAL FUNCTIONS section not found: $AnnotatedFile"
    }

    $sectionBody = $sectionMatch.Groups['Body'].Value
    $existingNames = @(
        [regex]::Matches(
            $sectionBody,
            '(?m)^\s*\*\s*.+?\s+([A-Za-z_]\w*)\s*\('
        ) |
        ForEach-Object { $_.Groups[1].Value } |
        Select-Object -Unique
    )

    # Exclude functions implemented as static functions in the test-object file.
    # They belong to LOCAL FUNCTIONS, not EXTERNAL FUNCTIONS.
    $localFunctionNames = @(
        [regex]::Matches(
            $sourceText,
            '(?m)^\s*static\s+.+?\s+([A-Za-z_]\w*)\s*\('
        ) |
        ForEach-Object { $_.Groups[1].Value } |
        Select-Object -Unique
    )

    $scanText = [regex]::Replace(
        $sourceText,
        '/\*.*?\*/',
        ' ',
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
    $scanText = [regex]::Replace(
        $scanText,
        '//.*?$',
        ' ',
        [System.Text.RegularExpressions.RegexOptions]::Multiline
    )
    $scanText = [regex]::Replace($scanText, '"(?:\\.|[^"\\])*"', ' ')

    $keywords = @(
        'if', 'else', 'switch', 'case', 'while', 'for', 'return',
        'sizeof', 'do', 'break', 'continue'
    )

    $calledNames = @(
        [regex]::Matches($scanText, '\b([A-Za-z_]\w*)\s*\(') |
        ForEach-Object { $_.Groups[1].Value } |
        Where-Object {
            $_ -ne $TestObject -and
            $keywords -notcontains $_ -and
            $localFunctionNames -notcontains $_
        } |
        Select-Object -Unique
    )

    $sourceFiles = @()
    if ($SourceRoot -and (Test-Path -LiteralPath $SourceRoot)) {
        $sourceFiles = @(
            Get-ChildItem `
                -Path $SourceRoot `
                -Recurse `
                -File `
                -Include '*.h','*.c' `
                -ErrorAction SilentlyContinue
        )
    }

    $missingLines = @()

    foreach ($functionName in $calledNames) {
        if ($existingNames -contains $functionName) { continue }

        $escapedName = [regex]::Escape($functionName)
        $signatureLine = $null

        foreach ($sourceFile in $sourceFiles) {
            $content = Get-Content `
                -LiteralPath $sourceFile.FullName `
                -Raw `
                -ErrorAction SilentlyContinue

            if (-not $content) { continue }

            $signatureMatch = [regex]::Match(
                $content,
                "(?ms)^[ \t]*(?!static\b)(?<ReturnType>[A-Za-z_][A-Za-z0-9_\s\*]*?)\s+\**$escapedName\s*\((?<Parameters>[^;{}()]*)\)\s*(?:;|\{)"
            )

            if ($signatureMatch.Success) {
                $returnType = ($signatureMatch.Groups['ReturnType'].Value -replace '\s+', ' ').Trim()
                $parameters = ($signatureMatch.Groups['Parameters'].Value -replace '\s+', ' ').Trim()
                if (-not $parameters) { $parameters = 'void' }

                $signatureLine = " * $returnType $functionName($parameters)"
                break
            }
        }

        # Safe fallback only for an external standalone zero-argument call.
        if (-not $signatureLine -and $sourceText -match "(?m)^\s*$escapedName\s*\(\s*\)\s*;") {
            $signatureLine = " * void $functionName(void)"
        }

        if ($signatureLine) {
            $missingLines += $signatureLine
            $existingNames += $functionName
            Write-Info -Step $STEP -Message "Recovered missing external function: $($signatureLine.Trim())"
        } else {
            Write-WarningLog -Step $STEP -Message "Could not resolve external function signature: $functionName"
        }
    }

    if ($missingLines.Count -eq 0) {
        Write-Info -Step $STEP -Message "External function interface is complete."
        return
    }

    # Keep every function inside the EXTERNAL FUNCTIONS list. Remove only the
    # trailing blank comment lines, append functions, then restore one blank line.
    $cleanBody = $sectionBody -replace '(?ms)(?:^\s*\*\s*\r?\n)+\s*$', ''
    $cleanBody = $cleanBody.TrimEnd("`r", "`n")

    $newBody =
        $cleanBody + "`r`n" +
        ($missingLines -join "`r`n") +
        "`r`n *`r`n`r`n"

    $replacement = $sectionMatch.Groups['Header'].Value + $newBody
    $updatedText =
        $annotatedText.Substring(0, $sectionMatch.Index) +
        $replacement +
        $annotatedText.Substring($sectionMatch.Index + $sectionMatch.Length)

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($AnnotatedFile, $updatedText, $utf8NoBom)

    Write-Info `
        -Step $STEP `
        -Message "Added $($missingLines.Count) missing external function(s): $AnnotatedFile"
}

Show-Banner "STEP 5 : BUILD ANNOTATED CONDITIONS FILE"
Write-StepStart $STEP

Write-Info -Step $STEP -Message "Test Object: $TestObject"
Write-Info -Step $STEP -Message "Module: $Module"
Write-Info -Step $STEP -Message "Source Directory: $SourceDir"

$result = Export-AnnotatedConditionCode `
    -Step $STEP `
    -TestObject $TestObject `
    -Module $Module `
    -SourceDir $SourceDir `
    -WorkingDir $WorkingDir

Write-Info -Step $STEP -Message "Annotated condition file saved: $($result.OutputFile)"
Write-Info `
    -Step $STEP `
    -Message "Resolved Defines=$($result.DefineCount), Types=$($result.TypeCount), ConstVariables=$($result.ConstCount), Macros=$($result.MacroCount)"

$rawSourceFile = Join-Path $WorkingDir "testObjectCode\${TestObject}.c"

Add-MissingExternalFunctions `
    -RawSourceFile $rawSourceFile `
    -AnnotatedFile $result.OutputFile `
    -SourceRoot $SourceDir

Write-Host ""
Write-Host "Annotated condition content:" -ForegroundColor Cyan
Write-Host ("-" * 80) -ForegroundColor Gray
Get-Content $result.OutputFile | ForEach-Object { Write-Host $_ }
Write-Host ("-" * 80) -ForegroundColor Gray

Write-StepEnd $STEP

Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host "STEP 5 COMPLETE" -ForegroundColor Cyan
Write-Host "Next -> Run Step 6: list testcases" -ForegroundColor Cyan
Write-Host ("=" * 80) -ForegroundColor Cyan

exit 0
