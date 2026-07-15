# ============================================================================
# logger.ps1
# ============================================================================
# Central logging utilities for Tessy Automation Framework
# ============================================================================

# ----------------------------------------------------------------------------
# Initialize log folder / file
# ----------------------------------------------------------------------------

$LogFolder = Join-Path $PSScriptRoot "logs"

if (!(Test-Path $LogFolder))
{
    New-Item `
        -ItemType Directory `
        -Path $LogFolder `
        -Force | Out-Null
}

$Global:LogFile = Join-Path `
    $LogFolder `
    ("TessyPilot_" + (Get-Date -Format "yyyyMMdd_HHmmss") + ".log")

# ----------------------------------------------------------------------------
# Internal helper
# ----------------------------------------------------------------------------

function Write-Log
{
    param(

        [ValidateSet("INFO","WARN","ERROR")]
        [string]$Level,

        [string]$Step,

        [string]$Message,

        [string]$Command = "",

        [int]$ExitCode = 0,

        [int]$Timeout = 0

    )

    $caller = (Get-PSCallStack)[1]

    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

    $text = @"

========================================================================
TIME       : $time
LEVEL      : $Level
STEP       : $Step
FILE       : $($caller.ScriptName)
LINE       : $($caller.ScriptLineNumber)
FUNCTION   : $($caller.FunctionName)
COMMAND    : $Command
EXITCODE   : $ExitCode
TIMEOUT    : $Timeout
MESSAGE    : $Message
========================================================================

"@

    Add-Content `
        -Path $Global:LogFile `
        -Value $text

    switch($Level)
    {
        "INFO"
        {
            Write-Host $Message -ForegroundColor Green
        }

        "WARN"
        {
            Write-Host $Message -ForegroundColor Yellow
        }

        "ERROR"
        {
            Write-Host $Message -ForegroundColor Red
        }
    }

}

# ----------------------------------------------------------------------------
# INFO
# ----------------------------------------------------------------------------

function Write-Info
{
    param(

        [string]$Step,

        [string]$Message,

        [string]$Command = ""

    )

    Write-Log `
        -Level INFO `
        -Step $Step `
        -Message $Message `
        -Command $Command
}

# ----------------------------------------------------------------------------
# WARNING
# ----------------------------------------------------------------------------

function Write-WarningLog
{
    param(

        [string]$Step,

        [string]$Message,

        [string]$Command = ""

    )

    Write-Log `
        -Level WARN `
        -Step $Step `
        -Message $Message `
        -Command $Command
}

# ----------------------------------------------------------------------------
# ERROR
# ----------------------------------------------------------------------------

function Write-ErrorLog
{
    param(

        [string]$Step,

        [string]$Message,

        [string]$Command,

        [int]$ExitCode,

        [int]$Timeout = 0

    )

    Write-Log `
        -Level ERROR `
        -Step $Step `
        -Message $Message `
        -Command $Command `
        -ExitCode $ExitCode `
        -Timeout $Timeout
}

# ----------------------------------------------------------------------------
# STEP START
# ----------------------------------------------------------------------------

function Write-StepStart
{
    param(

        [string]$Step

    )

    Write-Info `
        -Step $Step `
        -Message "Started."
}

# ----------------------------------------------------------------------------
# STEP END
# ----------------------------------------------------------------------------

function Write-StepEnd
{
    param(

        [string]$Step

    )

    Write-Info `
        -Step $Step `
        -Message "Completed successfully."
}