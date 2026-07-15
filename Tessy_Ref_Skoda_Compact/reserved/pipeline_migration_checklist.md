TESSY AUTOMATION PIPELINE - FULL RUN GUIDE (STEP 00 TO STEP 05)
================================================================

PURPOSE
-------
This checklist explains how to prepare, validate, and run the refactored Tessy
automation pipeline from Step 00 through Step 05.

The intended execution flow is:

    Step 00 - Discover Tessy test objects
        |
    Step 01 - Generate report, analyze coverage, export existing test script
        |
    Step 02 - Export YAML, parse interface, configure stubs, import YAML
        |
    Step 03 - Extract the complete function under test from source
        |
    Step 04 - Keep condition-relevant function code
        |
    Step 05 - Resolve defines, types, const data, and macro definitions


1. REQUIRED FILE STRUCTURE
--------------------------
Place the following files in the same framework directory:

    Tessy_Ref_Skoda_Compact\
    |
    +-- config.ps1
    +-- logger.ps1
    +-- common.ps1
    +-- run_pipeline.ps1
    |
    +-- step00.ps1
    +-- step01.ps1
    +-- step02.ps1
    +-- step03.ps1
    +-- step04.ps1
    +-- step05.ps1
    |
    +-- logs\
    +-- yml\
    +-- interface\
    +-- json_files\
    +-- script_files\
    +-- tbs_files\
    +-- testObjectCode\

The output folders may be created automatically by the scripts. They do not
all need to exist before the first run.

Recommended final step files:

    step00.ps1  = existing Step 00
    step01.ps1  = final Step 01 with corrected module-selection logic
    step02.ps1  = integrated Step 02 containing Step 2a and Step 2b flow
    step03.ps1  = refactored Step 03
    step04.ps1  = refactored Step 04
    step05.ps1  = refactored Step 05

Rename downloaded TXT files to PS1 before running them.

Example:

    Rename-Item .\step03_refactored.txt step03.ps1
    Rename-Item .\step04_refactored.txt step04.ps1
    Rename-Item .\step05_refactored.txt step05.ps1
    Rename-Item .\run_pipeline.txt run_pipeline.ps1


2. PREPARE COMMON.PS1
---------------------
Do not remove, rename, or modify existing common.ps1 APIs because Step 00 and
other scripts may already depend on them.

Append the refactor additions to the END of common.ps1 in this order:

    1. Existing common.ps1 content
    2. Step 01 additions
    3. Step 02 additions
    4. Step 2b interface-parser additions
    5. Step 03 additions
    6. Step 04 additions
    7. Step 05 additions

Important dependency:

    Step 04 uses Export-TestObjectFunctionCode from the Step 03 additions.

Do not dot-source the addition TXT files at runtime. Copy their function
content into common.ps1 so every step loads one common API file.

No logger.ps1 changes are required if these functions already exist:

    Write-Log
    Write-Info
    Write-WarningLog
    Write-ErrorLog
    Write-StepStart
    Write-StepEnd


3. CONFIG.PS1 REQUIREMENTS
--------------------------
The centralized config object must provide at least these properties:

    $Config.TessyProject
    $Config.TestCollection
    $Config.Folder
    $Config.Module
    $Config.TestObjects
    $Config.ScriptRoot
    $Config.WorkDir
    $Config.SourceDir

Example configuration:

    $Config = [PSCustomObject]@{
        TessyProject  = "sk336_t2"
        TestCollection = "SK336_TC"
        Folder         = "BSW"
        Module         = "ucDrv_2E_Cfg"
        TestObjects    = "ucDrv_CfgErrReport"

        ScriptRoot = "C:\Data\_DevTools\razorcat\TESSY_5.1\bin"

        WorkDir = "C:\Users\buimi1\Documents\03_repos\TessyPilot\Tessy_Ref_Skoda_Compact"

        SourceDir = "C:\Path\To\Project\Source"
    }

Configuration notes:

    - TessyProject must exactly match the project name in Tessy.
    - TestCollection must exactly match the Tessy test collection.
    - Folder may be "." or empty when the module is directly under the test
      collection.
    - Module must match the Tessy module name. Do not add .c unless Tessy uses
      .c in the registered module name.
    - TestObjects is currently treated as ONE test-object name by Steps 01-05.
    - ScriptRoot must be the location where tessycmd can be executed.
    - WorkDir must be the framework/output directory.
    - SourceDir must be the source-code root containing the relevant .c and .h
      files. Steps 03-05 search SourceDir recursively.


4. STEP 02 INTEGRATION CHECK
----------------------------
The final step02.ps1 should execute both former child flows internally:

    Step 2a:
        Export <TestObject>_export.yml from Tessy.

    Step 2b:
        Call Export-TessyInterfaceInfo from common.ps1 to parse the HTML/XML
        report and create <TestObject>_interface_info.txt.

The integrated Step 02 must not call these files in the main pipeline:

    step2a_export_yaml.ps1
    step2b_export_interface.ps1

Those old files may be retained only for standalone debugging.

The integrated Step 02 should create an initial import YAML automatically when
the testcase plan is not available:

    yml\<TestObject>_export.yml
        -> copied to
    yml\<TestObject>_import.yml

Do not create a fake testcase plan JSON. The dedicated YAML generator may be
used later when a valid testcase plan exists.


5. EXPECTED OUTPUT CHAIN
------------------------
Step 00:

    Discovers test objects from the selected Tessy context.

Step 01:

    report or reports\TESSY_DetailsReport_<TestObject>.html
    json_files\<TestObject>_coverage_status.json
    tbs_files\generate_report_<TestObject>_html.tbs
    script_files\<TestObject>_testcase.script       when C0 > 0

Step 02:

    yml\<TestObject>_export.yml
    yml\<TestObject>_import.yml
    interface\<TestObject>_interface_info.txt

Step 03:

    testObjectCode\<TestObject>.c

Step 04:

    testObjectCode\<TestObject>_conditions.c

Step 05:

    testObjectCode\<TestObject>_conditions_after_passing.c


6. PRE-RUN VALIDATION
---------------------
Open PowerShell in the framework directory:

    Set-Location "C:\Users\buimi1\Documents\03_repos\TessyPilot\Tessy_Ref_Skoda_Compact"

Confirm the required files:

    $required = @(
        "config.ps1",
        "logger.ps1",
        "common.ps1",
        "run_pipeline.ps1",
        "step00.ps1",
        "step01.ps1",
        "step02.ps1",
        "step03.ps1",
        "step04.ps1",
        "step05.ps1"
    )

    $required | ForEach-Object {
        if(Test-Path $_) {
            Write-Host "[OK] $_" -ForegroundColor Green
        }
        else {
            Write-Host "[MISSING] $_" -ForegroundColor Red
        }
    }

Load config and inspect the effective values:

    . .\config.ps1
    $Config | Format-List

Verify important paths:

    Test-Path $Config.ScriptRoot
    Test-Path $Config.WorkDir
    Test-Path $Config.SourceDir

Verify tessycmd:

    Set-Location $Config.ScriptRoot
    Get-Command tessycmd -ErrorAction Stop
    tessycmd connect

Return to the framework directory:

    Set-Location $Config.WorkDir

Optional PowerShell syntax validation:

    $files = @(
        ".\common.ps1",
        ".\step00.ps1",
        ".\step01.ps1",
        ".\step02.ps1",
        ".\step03.ps1",
        ".\step04.ps1",
        ".\step05.ps1",
        ".\run_pipeline.ps1"
    )

    foreach($file in $files) {
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile(
            (Resolve-Path $file),
            [ref]$tokens,
            [ref]$errors
        )

        if($errors.Count -eq 0) {
            Write-Host "[SYNTAX OK] $file" -ForegroundColor Green
        }
        else {
            Write-Host "[SYNTAX ERROR] $file" -ForegroundColor Red
            $errors | Format-List
        }
    }

Do not run the full pipeline while syntax errors remain.


7. RUN THE FULL PIPELINE
------------------------
From the framework directory, run:

    .\run_pipeline.ps1

This executes:

    Step 00 -> Step 01 -> Step 02 -> Step 03 -> Step 04 -> Step 05

Default behavior is fail-fast:

    - If a step returns exit code 0, the next step starts.
    - If a step returns a non-zero exit code, the pipeline stops.
    - The runner prints a summary and returns exit code 1.


8. RUN A PARTIAL PIPELINE
-------------------------
Run Step 01 through Step 05:

    .\run_pipeline.ps1 -FromStep 1 -ToStep 5

Run only Step 02:

    .\run_pipeline.ps1 -FromStep 2 -ToStep 2

Rerun source-processing Steps 03-05:

    .\run_pipeline.ps1 -FromStep 3 -ToStep 5

Rerun Step 04 and Step 05:

    .\run_pipeline.ps1 -FromStep 4 -ToStep 5

Continue after a failed step for debugging independent behavior:

    .\run_pipeline.ps1 -ContinueOnError

Use ContinueOnError only for debugging. Later steps normally depend on output
from earlier steps, so continuing may produce secondary errors.


9. RUN AN INDIVIDUAL STEP
-------------------------
The refactored steps read config.ps1 through common.ps1, so no command-line
parameters are required.

Examples:

    .\step00.ps1
    .\step01.ps1
    .\step02.ps1
    .\step03.ps1
    .\step04.ps1
    .\step05.ps1

Because each step uses exit 0 or exit 1, run_pipeline.ps1 executes every step
in a child PowerShell process. This prevents a step's exit statement from
terminating the runner process.


10. RECOMMENDED FIRST RUN
-------------------------
Run one step at a time during the first migration check:

    .\run_pipeline.ps1 -FromStep 0 -ToStep 0
    .\run_pipeline.ps1 -FromStep 1 -ToStep 1
    .\run_pipeline.ps1 -FromStep 2 -ToStep 2
    .\run_pipeline.ps1 -FromStep 3 -ToStep 3
    .\run_pipeline.ps1 -FromStep 4 -ToStep 4
    .\run_pipeline.ps1 -FromStep 5 -ToStep 5

After every step passes individually, run the full pipeline:

    .\run_pipeline.ps1


11. DEBUGGING CHECKLIST
-----------------------
Step 00 failure:

    - Verify Tessy is running or tessycmd can connect.
    - Verify TessyProject, TestCollection, Folder, and Module.
    - Run the selection commands manually in the same order.

Step 01 module-selection failure:

    - Compare the logged command with the manual command.
    - Confirm whether Tessy expects:

          tessycmd select-module <Module>

      or:

          tessycmd select-module -c <Module>

    - Do not retry "without .c" when the configured module has no .c suffix.

Step 01 report failure:

    - Verify the generated TBS file.
    - Verify report/report(s) path consistency.
    - Check Tessy batch execution output and exit code.

Step 02 failure:

    - Confirm export.yml exists.
    - Confirm the Step 01 HTML report exists.
    - Confirm interface_info.txt is generated.
    - Inspect UNKNOWN Passing errors and correct the Tessy interface manually.
    - Confirm both YAML import attempts and their exit codes.

Step 03 failure:

    - Verify SourceDir.
    - Verify <Module>.c exists somewhere under SourceDir.
    - Verify the TestObject name matches the C function definition exactly.
    - The fallback scans every .c file under SourceDir.

Step 04 failure:

    - Verify testObjectCode\<TestObject>.c exists.
    - If it does not exist, verify the Step 03 APIs are appended to common.ps1.
    - Inspect signature parsing and brace matching.

Step 05 failure:

    - Verify testObjectCode\<TestObject>_conditions.c exists.
    - Verify interface\<TestObject>_interface_info.txt exists.
    - Verify SourceDir contains the necessary .h and .c definitions.
    - Check unresolved type, define, const-array, enum-member, and macro logs.


12. LOGS AND PIPELINE RESULT
----------------------------
Logger output is stored under:

    logs\TessyPilot_<timestamp>.log

The pipeline also prints a final summary similar to:

    STEP 0: PASSED
    STEP 1: PASSED
    STEP 2: PASSED
    STEP 3: PASSED
    STEP 4: PASSED
    STEP 5: PASSED

    Pipeline completed successfully.

Check the runner exit code after completion:

    .\run_pipeline.ps1
    $LASTEXITCODE

Expected value:

    0  = all requested steps passed
    1  = one or more steps failed, were missing, or were not completed


13. FINAL GO/NO-GO CHECKLIST
----------------------------
Before the full run, confirm every item:

    [ ] All TXT scripts were renamed to PS1.
    [ ] Step files use the standard names step00.ps1 through step05.ps1.
    [ ] Existing common.ps1 functions were not removed or renamed.
    [ ] All Step 01-05 additions were appended to common.ps1.
    [ ] Step 03 additions appear before Step 04 additions.
    [ ] config.ps1 contains every required property.
    [ ] TessyProject and TestCollection are correct.
    [ ] Folder and Module match the Tessy project hierarchy.
    [ ] ScriptRoot can execute tessycmd.
    [ ] SourceDir exists and contains project source code.
    [ ] WorkDir points to the framework/output directory.
    [ ] Step 02 contains integrated Step 2a and Step 2b logic.
    [ ] PowerShell syntax validation passes for every PS1 file.
    [ ] Each step passes individually on the first migration run.
    [ ] Full pipeline returns exit code 0.

FULL RUN COMMAND
----------------

    Set-Location "C:\Users\buimi1\Documents\03_repos\TessyPilot\Tessy_Ref_Skoda_Compact"
    .\run_pipeline.ps1

================================================================
END OF GUIDE
================================================================
