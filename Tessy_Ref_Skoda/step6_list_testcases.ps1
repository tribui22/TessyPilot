<#
.SYNOPSIS
    Step 6 - Generate test case plan using GitHub Copilot Agent.

.DESCRIPTION
    Reads STEP6_TESTCASE_GENERATION_GUIDE.md (the guideline) and
    <TestObject>_conditions_after_passing.c (the analysis input), then:

      1. If <TestObject>_testcase_plan.json already exists  -> skip, exit 0.
      2. Otherwise, build a Copilot Agent prompt file
         testObjectCode\<TestObject>_step34.prompt.md
         that combines the guideline + conditions content with precise
         instructions for Copilot Agent to generate the JSON.
      3. Print instructions for the user to run the prompt.
      4. Wait for the JSON to appear (optionally, with -Wait switch).

    The prompt.md file is formatted for GitHub Copilot Agent in VS Code:
    open it, press Ctrl+Enter (or click "Run") to have Copilot Agent
    analyze the conditions file and write the JSON output.

.PARAMETER TestObject
.PARAMETER WorkingDir
.PARAMETER Force
    Re-generate the prompt even if testcase_plan.json already exists.
.PARAMETER Wait
    After writing the prompt, poll every 5 s until the JSON appears (or 10 min timeout).
#>
param(
    [Parameter(Mandatory=$true)]  [string]$TestObject,
    [Parameter(Mandatory=$false)] [string]$WorkingDir = (Split-Path -Parent $MyInvocation.MyCommand.Path),
    [switch]$Force,
    [switch]$Wait
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------
$outDir       = Join-Path $WorkingDir "testObjectCode"
$jsonDir      = Join-Path $WorkingDir "json_testcase"
$condFile     = Join-Path $outDir "${TestObject}_conditions_after_passing.c"
$outJson      = Join-Path $jsonDir "${TestObject}_testcase_plan.json"
$guideFile    = Join-Path $WorkingDir "STEP6_TESTCASE_GENERATION_GUIDE.md"
$promptFile   = Join-Path $outDir "${TestObject}_step6.prompt.md"

Write-Host "`nStep 6 - Test Case Plan (Copilot Agent)" -ForegroundColor Cyan
Write-Host "Input  : $condFile" -ForegroundColor Gray
Write-Host "Output : $outJson" -ForegroundColor Gray

# ---------------------------------------------------------------------------
# 1. If JSON already exists and -Force not set -> done
# ---------------------------------------------------------------------------
if ((Test-Path $outJson) -and -not $Force) {
    $existing = Get-Content $outJson -Raw | ConvertFrom-Json
    Write-Host "testcase_plan.json already exists ($($existing.TotalTestCases) TCs). Skipping." -ForegroundColor Green
    exit 0
}

# ---------------------------------------------------------------------------
# 2. Validate inputs
# ---------------------------------------------------------------------------
if (-not (Test-Path $condFile)) {
    Write-Host "ERROR: Conditions file not found: $condFile" -ForegroundColor Red
    Write-Host "Run Step 5 first." -ForegroundColor Yellow
    exit 1
}
if (-not (Test-Path $guideFile)) {
    Write-Host "ERROR: Guideline not found: $guideFile" -ForegroundColor Red
    exit 1
}

$condContent  = Get-Content $condFile  -Raw -Encoding UTF8
$guideContent = Get-Content $guideFile -Raw -Encoding UTF8

# ---------------------------------------------------------------------------
# 3. Build the Copilot Agent prompt file
# ---------------------------------------------------------------------------
$relCondPath  = "testObjectCode\${TestObject}_conditions_after_passing.c"
$relJsonPath  = "json_testcase\${TestObject}_testcase_plan.json"

$prompt = @"
---
mode: agent
description: "Step 6 - Generate test case plan JSON for ${TestObject}"
---

# Step 6: Generate `${TestObject}_testcase_plan.json`

## Your task
Analyze the C source file below and produce a complete test case plan JSON file.
Save the result to: `${relJsonPath}`

---

## Guideline (follow exactly)

${guideContent}

---

## Input: C source to analyze

File: `${relCondPath}`

``````c
${condContent}
``````

---

## Output instructions

1. Walk the function body **top-to-bottom** following every rule in the Guideline above.
2. Build the complete `TestCases` array — **do not skip any decision point**.
3. Apply the Array Index Rule and Inheritance Rule everywhere.
4. Keep the JSON compact. Do **not** include `FunctionBodyAfterPassing` or any copied source text.
5. For `bool`, `boolean_t`, or enum returns/values, use symbolic labels like `TRUE`, `FALSE`, or the enum member name — not `1` / `0` when a symbolic label exists.
6. Write the result as valid JSON to `${relJsonPath}` with this exact top-level structure:

``````json
{
  "FunctionSignature": "<signature>",
  "TotalTestCases": <N>,
  "TestCases": [
    {
      "TCId": 1,
      "Description": "TC1: ...",
      "Target": "...",
            "SetValues": [
                {
                    "Path": "<var_or_path>",
                    "Value": "<value>"
                }
            ],
            "StubFunctions": [
                {
                    "Name": "<stub_name>",
                    "Return": "<enum_label_or_literal>"
                }
            ]
    }
  ]
}
``````

Save **only** the JSON file — no explanation needed.
"@

if (-not (Test-Path $outDir))  { New-Item -ItemType Directory -Path $outDir  -Force | Out-Null }
if (-not (Test-Path $jsonDir)) { New-Item -ItemType Directory -Path $jsonDir -Force | Out-Null }
[System.IO.File]::WriteAllText($promptFile, $prompt, [System.Text.Encoding]::UTF8)

Write-Host ""
Write-Host "Copilot Agent prompt written to:" -ForegroundColor Yellow
Write-Host "  $promptFile" -ForegroundColor White
Write-Host ""
Write-Host "To generate the test case plan:" -ForegroundColor Cyan
Write-Host "  1. Open VS Code -> open the file above" -ForegroundColor White
Write-Host "  2. Press Ctrl+Enter (or click the Run button in the prompt)" -ForegroundColor White
Write-Host "  3. Copilot Agent will analyze the conditions file and write:" -ForegroundColor White
Write-Host "     $outJson" -ForegroundColor White
Write-Host ""

# ---------------------------------------------------------------------------
# 4. Optionally wait for the JSON to appear
# ---------------------------------------------------------------------------
if ($Wait) {
    Write-Host "Waiting for $outJson to appear (timeout 10 min)..." -ForegroundColor Yellow
    $deadline = (Get-Date).AddMinutes(10)
    while ((Get-Date) -lt $deadline) {
        if (Test-Path $outJson) {
            try {
                $obj = Get-Content $outJson -Raw | ConvertFrom-Json
                Write-Host "JSON found: $($obj.TotalTestCases) TCs. Step 6 complete." -ForegroundColor Green
                exit 0
            } catch {
                Write-Host "  JSON found but not yet valid JSON, waiting..." -ForegroundColor Yellow
            }
        }
        Start-Sleep -Seconds 5
    }
    Write-Host "ERROR: Timeout waiting for $outJson" -ForegroundColor Red
    exit 1
}

# Exit 0 even without -Wait; orchestrator will proceed.
# If downstream step 4 finds the JSON missing it will warn.
exit 0