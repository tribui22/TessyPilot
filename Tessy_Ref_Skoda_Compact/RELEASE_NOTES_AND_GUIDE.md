# Tessy 10-Step C0/C1 Coverage Automation — Release Notes & User Guide

**Version:** 1.0
**Date:** 2026-03-23

---

## What This Release Provides

A fully automated C0/C1 coverage workflow for Tessy, driven by a single
GitHub Copilot Agent prompt file.
The workflow is split into 3 phases and 10 numbered steps:

| Phase | Steps | Engine |
|-------|-------|--------|
| Phase 1 | 1 – 5 | PowerShell (`run_batch_steps1to5.ps1`) |
| Phase 2 | 6 | GitHub Copilot Agent (inline, no PowerShell) |
| Phase 3 | 7 – 10 | PowerShell (`run_batch_steps7to10.ps1`) |

---

## Prerequisites

| Requirement | Details |
|-------------|---------|
| Tessy | Installed, licensed, and **running** before Step 1 |
| `tessycmd` | Must be on the system PATH |
| VS Code | With GitHub Copilot Extension (Agent mode enabled) |
| PowerShell | Version 5.1 or later |
| Source code | Present at the configured `<SourceDir>` |
| Tessy project | Target project open with the correct test collection available |

---

## Configuration Parameters

All parameters are set in the Configuration table at the top of the prompt file:

`.github\prompts\run_10steps_coverage.prompt.md`

To run for a different test object, **update only that table** — no other file needs to be changed.

| Parameter | Type | Description |
|-----------|------|-------------|
| `<TestObject>` | string | Tessy test object name — must match exactly as shown in the Tessy project |
| `<Module>` | string | C source filename including `.c` extension (e.g. `mymodule.c`) |
| `<Folder>` | string | Module folder path inside the Tessy project tree (e.g. `SubSystem\MyDriver`) |
| `<TessyProject>` | string | Tessy project name as shown in the Tessy GUI |
| `<TestCollection>` | string | Tessy test collection name to execute |
| `<WorkDir>` | path | Absolute path to the `50_Tessy_Auto_10_Steps` working folder |
| `<ScriptRoot>` | path | Absolute path to the Tessy runtime folder that contains `tessycmd.exe` |
| `<SourceDir>` | path | Absolute path to the C source root folder |
| `<MaxIterations>` | int | Maximum correction loop iterations for Steps 7–10. Use `1` for first run, `2` to allow one auto-correction pass |
| `<C0Target>` | float | Required statement (C0) coverage percentage, e.g. `100.0` |
| `<C1Target>` | float | Required branch (C1) coverage percentage, e.g. `100.0` |
| `<ForceRegenerateTestcases>` | bool | `$true` = always regenerate the Tessy script in Step 7; `$false` = reuse existing script if present |

### Example

```
TestObject               = infineonDrvHandleOneChip
Module                   = infineon_drv.c
Folder                   = SmartLedDrv\InfineonDrv
TessyProject             = Chery_A_Variant
TestCollection           = Chery_A_Variant_ASW
WorkDir                  = C:\Data\Project\206_TessyCheryAVariantWithCopilot\50_Tessy_Auto_10_Steps
ScriptRoot               = C:\Data\Project\112_Code_Chery_A_Variant_Tessy\tessy
SourceDir                = C:\Data\Project\206_TessyCheryAVariantWithCopilot\25_Impl\30_Source
MaxIterations            = 1
C0Target                 = 100.0
C1Target                 = 100.0
ForceRegenerateTestcases = $false
```

---

## How to Run

1. **Open Tessy** and ensure the target project is loaded and connected.
2. **Open VS Code** in this workspace.
3. **Open the prompt file:**
   `.github\prompts\run_10steps_coverage.prompt.md`
4. **Edit the Configuration table** (if needed) to set the correct `<TestObject>` and paths.
5. **Run with Copilot Agent:**
   Press `Ctrl+Enter` (or click the ▶ Run button) to start the agent.
6. **Wait** — the agent runs all 10 steps automatically without user input.
7. **Check the final output** in the terminal — either:
   - `SUCCESS! 100% COVERAGE ACHIEVED!` — done.
   - An error message if a step failed — see Troubleshooting.

> **Do not** interact with the terminal or Tessy while the workflow is running.

---

## Step-by-Step Description

### Step 1 — Connect & Generate Report
Connects to Tessy, selects `<TestObject>` inside `<TessyProject>` /
`<TestCollection>`, runs any existing tests, and generates the `.tbs` batch
file used later in Step 8.

**Script:** `step1_connect_and_generate_report.ps1`
**Output:** `tbs_files\generate_report_<TestObject>_html.tbs`

---

### Step 2 — Configure Stubs
Exports the YAML interface definition (Step 2a) and the interface info text
(Step 2b) for `<TestObject>`.

**Scripts:**
- `step2_configure_stubs.ps1` (orchestrates)
  - `step2a_export_yaml.ps1` — exports YAML
  - `step2b_export_interface.ps1` — exports interface text

**Output:**
- `yml\<TestObject>_export.yml`
- `interface\<TestObject>_interface_info.txt`

---

### Step 3 — Find & Save Function Code
Searches `<SourceDir>` for `<Module>` and extracts the full body of
`<TestObject>` from the C source.

**Script:** `step3_find_and_save_function_code.ps1`
**Output:** `testObjectCode\<TestObject>.c`

---

### Step 4 — Strip Conditions
Rewrites the extracted function, removing implementation bodies and keeping
only the conditional structure (if / else-if / else / switch / ternary).

**Script:** `step4_strip_conditions.ps1`
**Output:** `testObjectCode\<TestObject>_conditions.c`

---

### Step 5 — Resolve #defines
Substitutes `#define` constants with their numeric values throughout the
conditions file, producing the final annotated file that Step 6 reads.

**Script:** `step5_resolve_defines.ps1`
**Output:** `testObjectCode\<TestObject>_conditions_after_passing.c`

---

### Step 6 — Generate Test Case Plan (Copilot Agent, inline)
The Copilot Agent reads **only**
`testObjectCode\<TestObject>_conditions_after_passing.c`
and generates the JSON test case plan by walking the function top-to-bottom.

**Rules applied:**

| Construct | Rule |
|-----------|------|
| Ternary `(COND) ? A : B` | 2 TCs — one for TRUE arm, one for FALSE arm |
| `if / else-if / else` | 1 TC per arm |
| `switch / case` | 1 TC per `case` label |
| `array[param]` | Set `param = 0` |
| `array[stub()]` | Set stub return to `0` |
| Nested / child branches | Inherit all parent `SetValues` and `StubFunctions` |

**Output:** `json_testcase\<TestObject>_testcase_plan.json`

> **Important:** If `_conditions_after_passing.c` is missing, the agent stops
> and reports an error. Always run Steps 1–5 before Step 6.

---

### Step 7 — Generate Tessy Test Script
Converts the JSON test case plan into a Tessy `.script` file using the
interface info from Step 2b.

**Script:** `step7_generate_testcases.ps1`
(dot-sources `step7a_metadata.ps1`, `step7b_stubs.ps1`,
`step7c_inputs_outputs.ps1`)

**Input:** `json_testcase\<TestObject>_testcase_plan.json`
**Output:** `script_files\<TestObject>_testcase.script`

---

### Step 8 — Execute Tests
Imports the `.script` file into Tessy and runs the test cases, generating the
HTML coverage report.

**Script:** `step8_execute_tests.ps1`
**Input:** `script_files\<TestObject>_testcase.script`,
`tbs_files\generate_report_<TestObject>_html.tbs`
**Output:** HTML report in `<ScriptRoot>\..\report\`

---

### Step 9 — Analyze Results
Reads the HTML report, extracts C0/C1 coverage percentages and pass/fail
counts, compares Actual vs Expected output values, and writes the coverage
status and corrections files.

**Script:** `step9_analyze_results.ps1`
**Output:**
- `json_files\<TestObject>_coverage_status.json`
- `json_files\<TestObject>_corrections.csv`

---

### Step 10 — Verify Coverage
Checks whether `C0 ≥ <C0Target>%`, `C1 ≥ <C1Target>%`, and `Failed = 0`.

| Exit code | Meaning | Next action |
|-----------|---------|-------------|
| `0` | All targets met | Workflow ends — SUCCESS |
| `2` | Coverage 100% but output values differ from Expected | Increase `<MaxIterations>` to `2` to allow a correction pass |
| `1` | Coverage targets not met | Review test cases; check error details |

**Script:** `step10_verify_coverage.ps1`

---

## Output Files Summary

| File | Produced by Step | Consumed by Step |
|------|-----------------|-----------------|
| `tbs_files\<TestObject>_html.tbs` | 1 | 8 |
| `yml\<TestObject>_export.yml` | 2a | 2 |
| `interface\<TestObject>_interface_info.txt` | 2b | 7 |
| `testObjectCode\<TestObject>.c` | 3 | 4 |
| `testObjectCode\<TestObject>_conditions.c` | 4 | 5 |
| `testObjectCode\<TestObject>_conditions_after_passing.c` | 5 | **6 (agent)** |
| `json_testcase\<TestObject>_testcase_plan.json` | 6 | 7 |
| `script_files\<TestObject>_testcase.script` | 7 | 8 |
| HTML report in `<ScriptRoot>\..\report\` | 8 | 9 |
| `json_files\<TestObject>_coverage_status.json` | 9 | 10 |
| `json_files\<TestObject>_corrections.csv` | 9 | (manual review) |

---

## Troubleshooting

| Symptom | Likely Cause | Action |
|---------|-------------|--------|
| Step 1 exits with non-zero code | Tessy not running or project not loaded | Start Tessy and open the project before running the prompt |
| `_conditions_after_passing.c` missing | Steps 3–5 did not run or failed | Check Step 3/4/5 terminal output; re-run Phase 1 |
| Step 8 exits with non-zero code | `.tbs` file missing or Tessy context lost | Re-run from Step 1 to regenerate the `.tbs` file |
| Coverage reads 0% after Step 9 | Stale `.c0.txt` / `.c1.txt` files from a prior run | Delete old files from `<ScriptRoot>\..\report\` and re-run Step 8 |
| Step 10 exits with code `2` | Tests pass coverage but output Expected values are wrong | Set `<MaxIterations>` to `2` in the prompt to allow auto-correction |
| Step 7 reuses old script | `ForceRegenerateTestcases = $false` and script already exists | Set `ForceRegenerateTestcases` to `$true` for one run |
| `testcase_plan.json` already exists | Previous Step 6 left the file | Delete `json_testcase\<TestObject>_testcase_plan.json` to force regeneration |

---

## File Structure Reference

```
50_Tessy_Auto_10_Steps\
│
│  ── Entry-point batch runners ──
├── run_batch_steps1to5.ps1              Phase 1 entry point
├── run_batch_steps7to10.ps1             Phase 3 entry point
│
│  ── Individual step scripts ──
├── step1_connect_and_generate_report.ps1
├── step2_configure_stubs.ps1
├── step2a_export_yaml.ps1
├── step2b_export_interface.ps1
├── step3_find_and_save_function_code.ps1
├── step4_strip_conditions.ps1
├── step5_resolve_defines.ps1
├── step6_list_testcases.ps1    (generates a prompt file; NOT used in automated flow)
├── step7_generate_testcases.ps1
├── step7a_metadata.ps1         (dot-sourced by step 7)
├── step7b_stubs.ps1            (dot-sourced by step 7)
├── step7c_inputs_outputs.ps1   (dot-sourced by step 7)
├── step8_execute_tests.ps1
├── step9_analyze_results.ps1
├── step10_verify_coverage.ps1
│
│  ── Working data folders ──
├── interface\         Step 2b output — interface info text files
├── json_files\        Step 9 output — coverage status JSON and corrections CSV
├── json_testcase\     Step 6 output — test case plan JSON
├── script_files\      Step 7 output — Tessy .script files
├── tbs_files\         Step 1 output — Tessy batch files
├── testObjectCode\    Steps 3–5 intermediate C files; Step 6 input
├── yml\               Step 2a output — YAML exports
│
│  ── Copilot Agent prompt ──
└── .github\prompts\run_10steps_coverage.prompt.md
```

---

## Known Limitations

- **`MaxIterations = 1`** — only one pass is made. If Step 10 exits with
  code `2` (coverage OK but output mismatches), set `MaxIterations = 2` to
  allow the auto-correction pass to run.
- **`ForceRegenerateTestcases = $false`** — if `<TestObject>_testcase.script`
  already exists, Step 7 is skipped on the first iteration. Set to `$true`
  after any Step 6 update to force a fresh script.
- **HTML report format dependency** — Step 9 extracts coverage data using
  regex patterns matched to the Tessy HTML report format. If the Tessy version
  is updated and the report format changes, the patterns in
  `step9_analyze_results.ps1` may need to be updated.

---

## Release History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-03-23 | Initial release of 10-step automated coverage workflow |
| | | Fixed console step labels in Steps 8, 9, 10 (were showing wrong step numbers) |
| | | Step 8 now propagates `tessycmd exec-test` exit code instead of always exiting 0 |
