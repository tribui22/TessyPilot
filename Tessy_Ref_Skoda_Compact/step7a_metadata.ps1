# ============================================================================
# STEP 4a: TC Metadata Generator (Plan-based)
# Defines: Build-TCMetadata
# Dot-sourced by step7_generate_testcases.ps1
# Uses script-level: $TestObject
# Parameters: -TcNum, -TCDescription, -TCTarget
# Source: _testcase_plan.json "Description" and "Target" fields
#
# $specification and $description are built from the plan Description/Target.
# ============================================================================

function Build-TCMetadata {
    param(
        [int]$TcNum,
        [string]$TCDescription,
        [string]$TCTarget
    )

    $tcNumPadded = '{0:D2}' -f $TcNum
    $out = ""

    # ---- Extract readable condition summary from Description ----
    # Format examples:
    #   "TC5: if TRUE -- 0U != controlFlags_un.flags_st.ChipModeInitOrFailsafe_b1 AND ..."
    #   "TC12: if FALSE -- ..."
    $condSummary = $TCDescription
    if ($TCDescription -match '^TC\d+:\s*(.*?)$') {
        $condSummary = $Matches[1].Trim()
    }
    # Replace non-ASCII characters that break Tessy's Latin-1 script parser
    $condSummary = $condSummary -replace [char]0x2014, '--'  # em dash — -> --
    $condSummary = $condSummary -replace [char]0x2013, '--'  # en dash – -> --
    $condSummary = $condSummary -replace [char]0x2192, '->'  # → -> ->
    $condSummary = $condSummary -replace [char]0x2190, '<-'  # ← -> <-
    $condSummary = $condSummary -replace '[^\x00-\x7E]', '?'  # any remaining non-ASCII -> ?

    # Extract just the signal description part (before long function-body text)
    $shortCondition = $condSummary
    if ($condSummary -match '^(if\s+(?:TRUE|FALSE)\s+--\s+.{1,200})') {
        $shortCondition = $Matches[1].Trim()
    } elseif ($condSummary.Length -gt 200) {
        $shortCondition = $condSummary.Substring(0, 200).Trim() + "..."
    }

    # Sanitize TCTarget for Latin-1 output
    $TCTarget = $TCTarget -replace [char]0x2014, '--'
    $TCTarget = $TCTarget -replace [char]0x2013, '--'
    $TCTarget = $TCTarget -replace [char]0x2192, '->'
    $TCTarget = $TCTarget -replace [char]0x2190, '<-'
    $TCTarget = $TCTarget -replace '[^\x00-\x7E]', '?'

    # Determine branch direction for readable text
    $noBranches = $shortCondition -match 'no branches|empty body|entry.?exit'
    $branchLabel = if ($TCTarget -match 'TRUE|if-body|then') { "TRUE" } elseif ($noBranches) { $null } else { "FALSE" }

    # ---- Build $specification content ----
    if ($null -eq $branchLabel) {
        $testGoal    = "Verify that $TestObject executes correctly: $shortCondition"
        $precondText = "None"
        $testDesc    = "Execute $TestObject() targeting: $shortCondition. Expected outcome: $TCTarget."
        $expectedResults = "Output match expected results which specified in test steps`n" +
            "`t`t`t`t- Function completes (Target: $TCTarget)`n" +
            "`t`t`t`t- Correct branch statements execute (C0 + C1 coverage met)`n" +
            "`t`t`t`t- Function completes without errors or unexpected side-effects"
    } else {
        $testGoal    = "Verify that $TestObject correctly takes the $branchLabel branch: $shortCondition"
        $precondText = "Set input variables so that the following condition evaluates to $branchLabel`: $shortCondition"
        $testDesc    = "Execute $TestObject() targeting: $shortCondition. Expected outcome: $TCTarget."
        $expectedResults = "Output match expected results which specified in test steps`n" +
            "`t`t`t`t- Condition evaluates to $branchLabel (Target: $TCTarget)`n" +
            "`t`t`t`t- Correct branch statements execute (C0 + C1 coverage met)`n" +
            "`t`t`t`t- Function completes without errors or unexpected side-effects"
    }
    $briefDesc = $shortCondition

    # ---- Build test case block ----
    $out += "`t`$testcase $TcNum {`n"
    $out += "`t`t`$name `"$TestObject. Test case $tcNumPadded`"`n"
    $out += "`t`t`$specification `"`"`"`n"
    $out += "`t`t`t[Test Goal]`n"
    $out += "`t`t`t`t$testGoal`n"
    $out += "`t`t`t[Precondition]`n"
    $out += "`t`t`t`t$precondText`n"
    $out += "`t`t`t[Test Description]`n"
    $out += "`t`t`t`t$testDesc`n"
    $out += "`t`t`t[Expected Result]`n"
    $out += "`t`t`t`t$expectedResults`n"
    $out += "`t`t`t[Post Condition]`n"
    $out += "`t`t`t`tNone`n"
    $out += "`t`t`t[Test Type]`n"
    $out += "`t`t`t`tTessy`n"
    $out += "`t`t`t[Priority]`n"
    $out += "`t`t`t`tMedium`n"
    $out += "`t`t`"`"`"`n"
    $out += "`t`t`$description `"`"`"`n"
    $out += "`t`t`t$briefDesc`n"
    $out += "`t`t`"`"`"`n"
    $out += "`n"

    return $out
}

# ============================================================================
# Build-TestCaseHeader
# Generates a single $testcase 1 { header block (called ONCE before the
# $teststep loop). All test steps live inside this one testcase block.
# ============================================================================
function Build-TestCaseHeader {
    $out  = "`t`$testcase 1 {`n"
    $out += "`t`t`$name `"$TestObject`"`n"
    $out += "`t`t`$specification `"`"`"`n"
    $out += "`t`t`t[Test Goal]`n"
    $out += "`t`t`t`tVerify module design of $TestObject.`n"
    $out += "`t`t`t[Precondition]`n"
    $out += "`t`t`t`tInput values as specified in test step.`n"
    $out += "`t`t`t[Test Description]`n"
    $out += "`t`t`t`tTest $TestObject in case Function is called.`n"
    $out += "`t`t`t[Expected Result]`n"
    $out += "`t`t`t`tOutput match expected results which specified in test steps.`n"
    $out += "`t`t`t[Post Condition]`n"
    $out += "`t`t`t`tNone`n"
    $out += "`t`t`t[Test Type]`n"
    $out += "`t`t`t`tTessy`n"
    $out += "`t`t`t[Priority]`n"
    $out += "`t`t`t`tMedium`n"
    $out += "`t`t`"`"`"`n"
    $out += "`n"
    return $out
}