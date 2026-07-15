# ============================================================================
# run_step.ps1
# ============================================================================
# Run exactly one pipeline entry-point script.
#
# Usage:
#   .\run_step.ps1 -Step 0
#   .\run_step.ps1 -Step 7
# ============================================================================

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateRange(0, 10)]
    [int]$Step
)

$ErrorActionPreference = "Stop"

$stepMap = @{
    0 = "step00.ps1"
    1 = "step01.ps1"
    2 = "step02.ps1"
    3 = "step03.ps1"
    4 = "step04.ps1"
    5 = "step05.ps1"
    6 = "step06.ps1"
    7 = "step07.ps1"
    8 = "step08.ps1"
    9 = "step09.ps1"
    10 = "step10.ps1"
}

if(-not $stepMap.ContainsKey($Step))
{
    Write-Host "ERROR: Unsupported step: $Step" -ForegroundColor Red
    exit 1
}

$scriptName = $stepMap[$Step]
$scriptPath = Join-Path $PSScriptRoot "..\steps\$scriptName"

if(-not (Test-Path $scriptPath))
{
    Write-Host "ERROR: Step entry point not found:" -ForegroundColor Red
    Write-Host "  $scriptPath" -ForegroundColor Yellow
    exit 1
}

Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host "Running $scriptName" -ForegroundColor Green
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host ""

# Run in a child process because step files use exit 0 / exit 1.
$powerShellExecutable = if(
    Get-Command "pwsh.exe" -ErrorAction SilentlyContinue
)
{
    "pwsh.exe"
}
elseif(
    Get-Command "powershell.exe" -ErrorAction SilentlyContinue
)
{
    "powershell.exe"
}
else
{
    Write-Host "ERROR: PowerShell executable not found." -ForegroundColor Red
    exit 1
}

& $powerShellExecutable `
    -NoLogo `
    -NoProfile `
    -ExecutionPolicy Bypass `
    -File $scriptPath

$stepExitCode = $LASTEXITCODE

if($stepExitCode -ne 0)
{
    Write-Host ""
    Write-Host "STEP $Step FAILED. Exit code: $stepExitCode" `
        -ForegroundColor Red

    exit $stepExitCode
}

Write-Host ""
Write-Host "STEP $Step COMPLETED SUCCESSFULLY." `
    -ForegroundColor Green

exit 0