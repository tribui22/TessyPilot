# ============================================================================
# run_pipeline.ps1
# ============================================================================
# Runs Steps 00-10 in child PowerShell processes.
#
# After Step 06 succeeds, the pipeline pauses so the user can run Microsoft
# Copilot to generate/update the testcase-plan artifact. Press Enter to validate
# the artifact and continue with Steps 07-10.
#
# Examples:
#   .\run_pipeline.ps1
#   .\run_pipeline.ps1 -FromStep 0 -ToStep 10
#   .\run_pipeline.ps1 -FromStep 7 -ToStep 10
#   .\run_pipeline.ps1 -SkipCopilotPause
# ============================================================================

[CmdletBinding()]
param(
    [ValidateRange(0, 10)]
    [int]$FromStep = 0,

    [ValidateRange(0, 10)]
    [int]$ToStep = 10,

    [switch]$ContinueOnError,
    [switch]$SkipCopilotPause
)

$ErrorActionPreference = 'Stop'

if ($FromStep -gt $ToStep) {
    throw "FromStep ($FromStep) must be less than or equal to ToStep ($ToStep)."
}

# Repository layout:
# <project>\runner\run_pipeline.ps1
# <project>\helpers\config.ps1, common.ps1, logger.ps1
# <project>\steps\step00.ps1 ... step10.ps1
$runnerRoot   = $PSScriptRoot
$pipelineRoot = Split-Path -Parent $runnerRoot
$helpersRoot  = Join-Path $pipelineRoot 'helpers'
$stepsRoot    = Join-Path $pipelineRoot 'steps'

$configFile = Join-Path $helpersRoot 'config.ps1'
$commonFile = Join-Path $helpersRoot 'common.ps1'
$loggerFile = Join-Path $helpersRoot 'logger.ps1'

foreach ($file in @($configFile, $commonFile, $loggerFile)) {
    if (-not (Test-Path -LiteralPath $file)) {
        throw "Required framework file not found: $file"
    }
}

# The runner only needs config values to validate the Copilot artifact.
. $configFile

$steps = [ordered]@{
    0  = 'step00.ps1'
    1  = 'step01.ps1'
    2  = 'step02.ps1'
    3  = 'step03.ps1'
    4  = 'step04.ps1'
    5  = 'step05.ps1'
    6  = 'step06.ps1'
    7  = 'step07.ps1'
    8  = 'step08.ps1'
    9  = 'step09.ps1'
    10 = 'step10.ps1'
}

$powerShellExecutable = if (Get-Command 'pwsh.exe' -ErrorAction SilentlyContinue) {
    'pwsh.exe'
} elseif (Get-Command 'powershell.exe' -ErrorAction SilentlyContinue) {
    'powershell.exe'
} else {
    throw 'Neither pwsh.exe nor powershell.exe was found.'
}

function Wait-ForCopilotTestcasePlan {
    [CmdletBinding()]
    param()

    # No pause is needed when Step 07 is outside the requested range.
    if ($SkipCopilotPause -or $ToStep -lt 7) { return }

    $testObject = [string]$Config.TestObjects
    $workingDir = [string]$Config.WorkDir
    $planFile = Join-Path $workingDir "json_testcase\${testObject}_testcase_plan.json"

    Write-Host ''
    Write-Host ('=' * 80) -ForegroundColor Magenta
    Write-Host ' COPILOT CHECKPOINT - MANUAL TESTCASE GENERATION' -ForegroundColor Magenta
    Write-Host ('=' * 80) -ForegroundColor Magenta
    Write-Host ' Step 06 completed successfully.' -ForegroundColor Green
    Write-Host ' Run Microsoft Copilot now using the Step 06 prompt/guide.' -ForegroundColor Yellow
    Write-Host ' Copilot must create or update:' -ForegroundColor Yellow
    Write-Host "   $planFile" -ForegroundColor White
    Write-Host ''
    [void](Read-Host ' Press Enter after Copilot has finished')

    if (-not (Test-Path -LiteralPath $planFile)) {
        throw "Copilot testcase plan not found: $planFile"
    }

    try {
        $plan = Get-Content $planFile -Raw -Encoding UTF8 | ConvertFrom-Json
        $testCases = @($plan.TestCases)

        if ($testCases.Count -eq 0) {
            throw 'TestCases is empty.'
        }
        if ($null -ne $plan.TotalTestCases -and [int]$plan.TotalTestCases -ne $testCases.Count) {
            throw "TotalTestCases=$($plan.TotalTestCases), TestCases.Count=$($testCases.Count)."
        }

        Write-Host " [OK] Copilot plan validated: $($testCases.Count) testcase(s)." -ForegroundColor Green
        Write-Host ' Continuing with Step 07...' -ForegroundColor Cyan
        Write-Host ('=' * 80) -ForegroundColor Magenta
    } catch {
        throw "Invalid Copilot testcase plan '$planFile': $($_.Exception.Message)"
    }
}

function Invoke-OptionalReportAddOn {
    [CmdletBinding()]
    param()

    while ($true) {
        $answer = (Read-Host 'Run optional coverage report before the pipeline? [Y/N]').Trim()
        switch -Regex ($answer) {
            '^(?i:y|yes)$' {
                $reportRunner = Join-Path $runnerRoot 'run_report.ps1'
                if (-not (Test-Path -LiteralPath $reportRunner)) {
                    throw "Optional report runner not found: $reportRunner"
                }

                Write-Host "`n[ADD-ON] Running coverage report..." -ForegroundColor Magenta
                & $powerShellExecutable `
                    -NoLogo `
                    -NoProfile `
                    -ExecutionPolicy Bypass `
                    -File $reportRunner

                if ($LASTEXITCODE -ne 0) {
                    throw "Optional report add-on failed with exit code $LASTEXITCODE."
                }
                return
            }
            '^(?i:n|no)$' {
                Write-Host '[ADD-ON] Coverage report skipped.' -ForegroundColor DarkGray
                return
            }
            default {
                Write-Host 'Please enter Y or N.' -ForegroundColor Yellow
            }
        }
    }
}

$line = '=' * 80
$results = New-Object 'System.Collections.Generic.List[object]'
$pipelineStart = Get-Date

Write-Host ''
Write-Host $line -ForegroundColor Cyan
Write-Host " TESSY AUTOMATION PIPELINE: STEP $FromStep -> STEP $ToStep" -ForegroundColor Cyan
Write-Host " Root: $pipelineRoot" -ForegroundColor DarkGray
Write-Host " PowerShell: $powerShellExecutable" -ForegroundColor DarkGray
Write-Host $line -ForegroundColor Cyan

try {
    Invoke-OptionalReportAddOn
} catch {
    Write-Host "`n[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    exit 1
}

for ($stepNumber = $FromStep; $stepNumber -le $ToStep; $stepNumber++) {
    $scriptName = $steps[$stepNumber]
    $scriptPath = Join-Path $stepsRoot $scriptName

    if (-not (Test-Path -LiteralPath $scriptPath)) {
        $results.Add([PSCustomObject]@{
            Step=$stepNumber; Script=$scriptName; Status='MISSING'
            ExitCode=1; Duration=[TimeSpan]::Zero
        })
        Write-Host "`n[ERROR] Step script not found: $scriptPath" -ForegroundColor Red
        if (-not $ContinueOnError) { break }
        continue
    }

    Write-Host "`n$line" -ForegroundColor DarkCyan
    Write-Host " RUN STEP $stepNumber : $scriptName" -ForegroundColor DarkCyan
    Write-Host $line -ForegroundColor DarkCyan

    $stepStart = Get-Date
    & $powerShellExecutable `
        -NoLogo `
        -NoProfile `
        -ExecutionPolicy Bypass `
        -File $scriptPath

    $exitCode = $LASTEXITCODE
    $duration = (Get-Date) - $stepStart
    $status = if ($exitCode -eq 0) { 'PASSED' } else { 'FAILED' }

    $results.Add([PSCustomObject]@{
        Step=$stepNumber; Script=$scriptName; Status=$status
        ExitCode=$exitCode; Duration=$duration
    })

    if ($exitCode -ne 0) {
        Write-Host "`n[FAILED] STEP $stepNumber returned exit code $exitCode." -ForegroundColor Red
        if (-not $ContinueOnError) {
            Write-Host 'Pipeline stopped.' -ForegroundColor Yellow
            break
        }
        continue
    }

    Write-Host "`n[PASSED] STEP $stepNumber completed in $([Math]::Round($duration.TotalSeconds, 1)) second(s)." -ForegroundColor Green

    # Pause exactly after a successful Step 06, before Step 07.
    if ($stepNumber -eq 6) {
        try {
            Wait-ForCopilotTestcasePlan
        } catch {
            Write-Host "`n[ERROR] $($_.Exception.Message)" -ForegroundColor Red
            $results.Add([PSCustomObject]@{
                Step='6-AI'; Script='Microsoft Copilot checkpoint'; Status='FAILED'
                ExitCode=1; Duration=[TimeSpan]::Zero
            })
            break
        }
    }
}

$pipelineDuration = (Get-Date) - $pipelineStart
$failedSteps = @($results | Where-Object { $_.Status -ne 'PASSED' })

Write-Host "`n$line" -ForegroundColor Cyan
Write-Host ' PIPELINE SUMMARY' -ForegroundColor Cyan
Write-Host $line -ForegroundColor Cyan

foreach ($result in $results) {
    $color = if ($result.Status -eq 'PASSED') { 'Green' } elseif ($result.Status -eq 'MISSING') { 'Yellow' } else { 'Red' }
    Write-Host (" STEP {0}: {1,-8} Exit={2,-3} Duration={3,7:N1}s  {4}" -f `
        $result.Step, $result.Status, $result.ExitCode,
        $result.Duration.TotalSeconds, $result.Script) -ForegroundColor $color
}

Write-Host "`n Total duration: $([Math]::Round($pipelineDuration.TotalSeconds, 1)) second(s)." -ForegroundColor Cyan

if ($failedSteps.Count -gt 0) {
    Write-Host ' Pipeline failed or stopped before all requested steps completed.' -ForegroundColor Red
    exit 1
}

$expectedStepCount = $ToStep - $FromStep + 1
if ($results.Count -ne $expectedStepCount) {
    Write-Host ' Pipeline did not execute every requested step.' -ForegroundColor Red
    exit 1
}

Write-Host ' Pipeline completed successfully.' -ForegroundColor Green
exit 0
