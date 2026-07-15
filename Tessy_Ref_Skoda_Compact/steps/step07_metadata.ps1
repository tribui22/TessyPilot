# ============================================================================
# STEP 7A: Testcase Metadata Renderer
# ============================================================================
# Dot-sourced by step07_engine.ps1.
# Specialized Step 07 rendering logic; do not append to common.ps1.
#
# Public functions:
#   Build-TCMetadata
#   Build-TestCaseHeader
# ============================================================================

function ConvertTo-TessyAsciiText
{
    param(
        [AllowNull()]
        [string]$Text,

        [int]$MaximumLength = 0
    )

    if($null -eq $Text)
    {
        return ""
    }

    $result = $Text
    $result = $result -replace [char]0x2014, '--'
    $result = $result -replace [char]0x2013, '--'
    $result = $result -replace [char]0x2192, '->'
    $result = $result -replace [char]0x2190, '<-'
    $result = $result -replace '[^\x00-\x7E]', '?'
    $result = $result.Trim()

    if($MaximumLength -gt 0 -and $result.Length -gt $MaximumLength)
    {
        return $result.Substring(0, $MaximumLength).Trim() + "..."
    }

    return $result
}

function Get-TessyConditionSummary
{
    param(
        [AllowNull()]
        [string]$Description
    )

    $summary = ConvertTo-TessyAsciiText -Text $Description

    if($summary -match '^TC\d+:\s*(.*?)$')
    {
        $summary = $Matches[1].Trim()
    }

    if($summary -match '^(if\s+(?:TRUE|FALSE)\s+--\s+.{1,200})')
    {
        return $Matches[1].Trim()
    }

    return (ConvertTo-TessyAsciiText -Text $summary -MaximumLength 200)
}

function Get-TessyBranchLabel
{
    param(
        [string]$ConditionSummary,
        [string]$Target
    )

    if($ConditionSummary -match 'no branches|empty body|entry.?exit')
    {
        return $null
    }

    if($Target -match 'TRUE|if-body|then')
    {
        return 'TRUE'
    }

    return 'FALSE'
}

function Build-TCMetadata
{
    param(
        [Parameter(Mandatory = $true)]
        [ValidateRange(1, [int]::MaxValue)]
        [int]$TcNum,

        [Parameter(Mandatory = $true)]
        [string]$TCDescription,

        [AllowEmptyString()]
        [string]$TCTarget = "",

        # The existing engine can continue omitting this argument because it
        # defines $TestObject before dot-sourcing this helper.
        [string]$TestObjectName = $script:TestObject
    )

    if([string]::IsNullOrWhiteSpace($TestObjectName))
    {
        throw "Build-TCMetadata requires TestObjectName or script-level TestObject."
    }

    $testObjectText = ConvertTo-TessyAsciiText -Text $TestObjectName
    $conditionSummary = Get-TessyConditionSummary -Description $TCDescription
    $targetText = ConvertTo-TessyAsciiText -Text $TCTarget -MaximumLength 300

    if([string]::IsNullOrWhiteSpace($targetText))
    {
        $targetText = $conditionSummary
    }

    $branchLabel = Get-TessyBranchLabel `
        -ConditionSummary $conditionSummary `
        -Target $targetText

    if($null -eq $branchLabel)
    {
        $testGoal = "Verify that $testObjectText executes correctly: $conditionSummary"
        $precondition = "None"
        $testDescription = "Execute $testObjectText() targeting: $conditionSummary. Expected outcome: $targetText."
        $expectedResult = @(
            "Output match expected results which specified in test steps"
            "- Function completes (Target: $targetText)"
            "- Correct branch statements execute (C0 + C1 coverage met)"
            "- Function completes without errors or unexpected side-effects"
        )
    }
    else
    {
        $testGoal = "Verify that $testObjectText correctly takes the $branchLabel branch: $conditionSummary"
        $precondition = "Set input variables so that the following condition evaluates to ${branchLabel}: $conditionSummary"
        $testDescription = "Execute $testObjectText() targeting: $conditionSummary. Expected outcome: $targetText."
        $expectedResult = @(
            "Output match expected results which specified in test steps"
            "- Condition evaluates to $branchLabel (Target: $targetText)"
            "- Correct branch statements execute (C0 + C1 coverage met)"
            "- Function completes without errors or unexpected side-effects"
        )
    }

    $testGoal = ConvertTo-TessyAsciiText -Text $testGoal
    $precondition = ConvertTo-TessyAsciiText -Text $precondition
    $testDescription = ConvertTo-TessyAsciiText -Text $testDescription
    $expectedResult = @($expectedResult | ForEach-Object {
        ConvertTo-TessyAsciiText -Text $_
    })

    $tcNumber = '{0:D2}' -f $TcNum
    $builder = [System.Text.StringBuilder]::new()

    [void]$builder.AppendLine("`t`$testcase $TcNum {")
    [void]$builder.AppendLine("`t`t`$name `"$testObjectText. Test case $tcNumber`"")
    [void]$builder.AppendLine("`t`t`$specification `"`"`"")
    [void]$builder.AppendLine("`t`t`t[Test Goal]")
    [void]$builder.AppendLine("`t`t`t`t$testGoal")
    [void]$builder.AppendLine("`t`t`t[Precondition]")
    [void]$builder.AppendLine("`t`t`t`t$precondition")
    [void]$builder.AppendLine("`t`t`t[Test Description]")
    [void]$builder.AppendLine("`t`t`t`t$testDescription")
    [void]$builder.AppendLine("`t`t`t[Expected Result]")

    foreach($line in $expectedResult)
    {
        [void]$builder.AppendLine("`t`t`t`t$line")
    }

    [void]$builder.AppendLine("`t`t`t[Post Condition]")
    [void]$builder.AppendLine("`t`t`t`tNone")
    [void]$builder.AppendLine("`t`t`t[Test Type]")
    [void]$builder.AppendLine("`t`t`t`tTessy")
    [void]$builder.AppendLine("`t`t`t[Priority]")
    [void]$builder.AppendLine("`t`t`t`tMedium")
    [void]$builder.AppendLine("`t`t`"`"`"")
    [void]$builder.AppendLine("`t`t`$description `"`"`"")
    [void]$builder.AppendLine("`t`t`t$conditionSummary")
    [void]$builder.AppendLine("`t`t`"`"`"")
    [void]$builder.AppendLine()

    return $builder.ToString()
}

# Legacy API retained for compatibility with older Step 07 generation paths.
# The current plan-based engine uses Build-TCMetadata instead.
function Build-TestCaseHeader
{
    param(
        [string]$TestObjectName = $script:TestObject
    )

    if([string]::IsNullOrWhiteSpace($TestObjectName))
    {
        throw "Build-TestCaseHeader requires TestObjectName or script-level TestObject."
    }

    $testObjectText = ConvertTo-TessyAsciiText -Text $TestObjectName
    $builder = [System.Text.StringBuilder]::new()

    [void]$builder.AppendLine("`t`$testcase 1 {")
    [void]$builder.AppendLine("`t`t`$name `"$testObjectText`"")
    [void]$builder.AppendLine("`t`t`$specification `"`"`"")
    [void]$builder.AppendLine("`t`t`t[Test Goal]")
    [void]$builder.AppendLine("`t`t`t`tVerify module design of $testObjectText.")
    [void]$builder.AppendLine("`t`t`t[Precondition]")
    [void]$builder.AppendLine("`t`t`t`tInput values as specified in test step.")
    [void]$builder.AppendLine("`t`t`t[Test Description]")
    [void]$builder.AppendLine("`t`t`t`tTest $testObjectText in case Function is called.")
    [void]$builder.AppendLine("`t`t`t[Expected Result]")
    [void]$builder.AppendLine("`t`t`t`tOutput match expected results which specified in test steps.")
    [void]$builder.AppendLine("`t`t`t[Post Condition]")
    [void]$builder.AppendLine("`t`t`t`tNone")
    [void]$builder.AppendLine("`t`t`t[Test Type]")
    [void]$builder.AppendLine("`t`t`t`tTessy")
    [void]$builder.AppendLine("`t`t`t[Priority]")
    [void]$builder.AppendLine("`t`t`t`tMedium")
    [void]$builder.AppendLine("`t`t`"`"`"")
    [void]$builder.AppendLine()

    return $builder.ToString()
}
