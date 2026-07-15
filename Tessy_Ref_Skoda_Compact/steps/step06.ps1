# ============================================================================
# STEP 6: Prepare Copilot Testcase-Generation Request
# ============================================================================
# Responsibilities of this script:
#   - Load centralized configuration.
#   - Validate the Step 05 analysis input, generation guide, and prompt template.
#   - Build a TestObject-specific Copilot Agent prompt.
#   - Optionally wait for and validate testcase_plan.json.
#
# The reasoning rules remain outside PowerShell in:
#   STEP6_TESTCASE_GENERATION_GUIDE.md
#
# The Copilot task wording remains outside PowerShell in:
#   STEP6_AGENT_PROMPT_TEMPLATE.md
# ============================================================================

[CmdletBinding()]
param(
    [switch]$Force,
    [switch]$Wait,
    [ValidateRange(1, 120)][int]$TimeoutMinutes = 10,
    [ValidateRange(1, 60)][int]$PollSeconds = 5
)

. (Join-Path $PSScriptRoot "..\common.ps1")

$STEP       = "STEP6"
$TestObject = $Config.TestObjects
$WorkingDir = $Config.WorkDir

$guideFile = Join-Path $WorkingDir "STEP6_TESTCASE_GENERATION_GUIDE.md"
$templateFile = Join-Path $WorkingDir "STEP6_AGENT_PROMPT_TEMPLATE.md"

Show-Banner "STEP 6 : PREPARE COPILOT TESTCASE GENERATION"
Write-StepStart $STEP

$result = New-Step6CopilotPrompt `
    -Step $STEP `
    -TestObject $TestObject `
    -WorkingDir $WorkingDir `
    -GuideFile $guideFile `
    -TemplateFile $templateFile `
    -Force:$Force

if($result.Status -eq "EXISTS")
{
    Write-Info `
        -Step $STEP `
        -Message "Testcase plan already exists: $($result.JsonFile); TotalTestCases=$($result.TotalTestCases)"

    Write-StepEnd $STEP
    exit 0
}

Write-Info -Step $STEP -Message "Copilot Agent prompt created: $($result.PromptFile)"
Write-Host ""
Write-Host "Run the Copilot generation phase:" -ForegroundColor Cyan
Write-Host "  1. Open this prompt in VS Code:" -ForegroundColor White
Write-Host "     $($result.PromptFile)" -ForegroundColor Yellow
Write-Host "  2. Run the prompt with GitHub Copilot Agent." -ForegroundColor White
Write-Host "  3. Copilot must create:" -ForegroundColor White
Write-Host "     $($result.JsonFile)" -ForegroundColor Yellow
Write-Host ""

if($Wait)
{
    $plan = Wait-Step6TestcasePlan `
        -Step $STEP `
        -JsonFile $result.JsonFile `
        -TimeoutMinutes $TimeoutMinutes `
        -PollSeconds $PollSeconds

    Write-Info `
        -Step $STEP `
        -Message "Testcase plan ready: $($result.JsonFile); TotalTestCases=$($plan.TotalTestCases)"
}
else
{
    Write-WarningLog `
        -Step $STEP `
        -Message "Prompt preparation completed. Copilot reasoning is a separate manual/agent phase; testcase JSON has not been awaited."
}

Write-StepEnd $STEP
exit 0
