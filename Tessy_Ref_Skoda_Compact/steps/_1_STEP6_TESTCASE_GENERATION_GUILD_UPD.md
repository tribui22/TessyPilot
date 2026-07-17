# Step 6 — Test Case Generation Guide

## Purpose

Read:

```text
<TestObject>_conditions_after_passing.c
```

and create:

```text
<TestObject>_testcase_plan.json
```

This guide defines the testcase-plan workspace contract. The workspace may be imported into GitHub Copilot when testcase generation is needed. Step 6 itself only prepares the workspace; testcase generation is performed separately by the user.

---

## Required workflow

Do not write JSON immediately after seeing the first decisions. Complete the following workflow in order.

1. Read the complete interface header and function body.
2. Build a decision inventory for every reachable:
   - `if`
   - `else if`
   - `else`
   - `while`
   - `do/while`
   - `for` condition
   - ternary expression
   - `switch` case label
   - `switch default`
   - short-circuit `&&` and `||` operand path
3. Record the full parent path required to reach every nested decision.
4. Identify all external function calls whose returned values control a decision.
5. Generate testcases for every required outcome and switch entry label.
6. Perform the mandatory completeness verification in this guide.
7. Write JSON only after every inventory item maps to at least one testcase.

Do not calculate a coverage percentage. Instead, guarantee structural completeness from the source code.

---

## Core rules

### Primary-target rule

Each testcase has one primary coverage target.

A testcase may set multiple values when those values are required to reach the primary target. For nested decisions, inherit all required parent-path values and change only the value that controls the target decision.

Do not combine unrelated targets merely to reduce testcase count. Coverage obtained naturally while reaching the primary target is valid and does not require an unnecessary duplicate testcase.

### Reachability rule

A testcase is valid only if execution reaches its declared `Target`.

Setting a nested condition without setting the parent path required to reach that condition is invalid.

Example:

```c
if (A)
{
    if (B)
    {
        statement;
    }
}
```

The testcase targeting `B = TRUE` must set:

```text
A = TRUE
B = TRUE
```

### Scope rule

Set only:

- values required to reach the target path;
- values that directly control the target decision;
- values required to terminate a loop safely;
- pointer members required to create a valid initialized pointed object.

Do not set every interface variable in every testcase. Step 7 supplies type-safe neutral defaults only for variables unrelated to target reachability. Do not rely on Step 7 to infer values needed to reach a branch.

### Compact JSON rule

Output only data required by Step 7. Do not copy the source function body into JSON.

### Pointer safety rule

For every pointer-to-struct `IN` or `INOUT` input, use pointer-object format containing:

- `PointerName`
- `Allocate`
- `DynamicObject`
- recursive `Members`

Do not emit flat paths such as:

```text
config_ptr->member
config_ptr.member
```

when pointer-object format is available.

### Symbolic-value rule

For `bool`, `boolean_t`, and enum values, use symbolic labels whenever available:

```text
TRUE
FALSE
STATE_ACTIVE
STATE_IDLE
```

Do not use `1` or `0` when an interface-visible symbolic value exists.

### Interface-driven rule

Only use variables, members, function signatures, and enum labels visible in the interface or resolvable from the supplied workspace.

Never invent a member path or external function signature.

---

## Inheritance and override rules

A child testcase inherits the effective parent-path state.

When a child changes a value:

- replace the inherited value with the new value;
- do not keep duplicate `Path` entries;
- key pointer objects by `PointerName`;
- key stub behavior by function `Name`;
- keep one final effective value per path and one final behavior per stub name.

`DefaultValues` contains values shared by most testcases. `SetValues` contains only per-testcase differences from `DefaultValues`.

For pointer-backed structures, place common initialized members in `DefaultValues` whenever the same pointed-object state is shared by most testcases.

---

## Stub classification

Do not treat every function-like token as an external stub.

| Classification | Action |
|---|---|
| Function listed under `EXTERNAL FUNCTIONS` | Eligible Tessy stub |
| Function listed under `LOCAL FUNCTIONS` | Never emit as external stub |
| Function under test | Never emit as stub |
| C keyword, cast, macro, `sizeof` | Not a stub |
| External `void` function | May use an empty stub body; no return value |
| External non-void function affecting target path | Emit explicit `Return` or `Body` |
| External non-void function unrelated to target path | May use the Step 7 default |

Use the exact signature from the interface. Never synthesize `int Function(void)` when a real signature is available.

---

## General value rules

| Pattern | Required value |
|---|---|
| `array[param]` | Set `param = 0` unless another valid index is required |
| `array[stub()]` | Set stub return to `0` unless another valid index is required |
| unsigned/signed integer TRUE | `1` |
| unsigned/signed integer FALSE | `0` |
| `bool` / `boolean_t` TRUE | `TRUE` |
| `bool` / `boolean_t` FALSE | `FALSE` |
| `float` / `double` TRUE | `1.0` |
| `float` / `double` FALSE | `0.0` |
| allocated pointer | Pointer object with `Allocate=true` and initialized members |
| null/deallocated pointer | Pointer object with `Allocate=false` |
| enum | Exact symbolic enum label |
| local static variable | Full interface notation, for example `FunctionName::varName#1[0]` |

---

## Decision rules

### `if (C)`

Generate at least:

1. A reachable testcase with `C = TRUE`.
2. A reachable testcase with `C = FALSE`.

### `else if (C)`

Both testcases must first make all preceding conditions in the chain false so execution reaches the `else if`.

Generate:

1. preceding path false + `C = TRUE`;
2. preceding path false + `C = FALSE`.

### `else`

Generate one testcase where every preceding condition in the chain is false.

### Nested decisions

Inherit the complete parent path. Do not create a testcase for a nested decision without the parent values needed to reach it.

### Ternary expression

For:

```c
v = C ? A : B;
```

Generate:

1. `C = TRUE`, selecting `A`;
2. `C = FALSE`, selecting `B`.

---

## Compound and short-circuit conditions

### `A && B`

Generate the reachable evaluation paths:

1. `A = FALSE` — decision false; `B` is not evaluated.
2. `A = TRUE`, `B = FALSE` — decision false; `B` is evaluated.
3. `A = TRUE`, `B = TRUE` — decision true.

### `A || B`

Generate:

1. `A = TRUE` — decision true; `B` is not evaluated.
2. `A = FALSE`, `B = TRUE` — decision true; `B` is evaluated.
3. `A = FALSE`, `B = FALSE` — decision false.

For longer chains, preserve left-to-right short-circuit evaluation and generate enough testcases so every operand is evaluated in the paths where evaluation is reachable.

---

## Loop rules

For every `while`, `do/while`, or `for` condition, generate safe terminating paths.

### Simple loop

Generate:

1. zero iterations;
2. at least one iteration when the body is reachable.

### Compound loop condition

For:

```c
while (A && B)
{
    body;
}
```

Generate at minimum:

1. `A = FALSE` — zero iterations;
2. `A = TRUE`, `B = FALSE` — zero iterations through the second operand;
3. `A = TRUE`, `B = TRUE` initially — body executes, then a later value terminates the loop.

### Stub-driven loop termination

If termination requires a stub to change value across calls, use a `Body` override.

Example:

```json
{
  "Name": "ucDrv_FCCDone",
  "Body": "static int callCount = 0; if (callCount++ == 0) { return FALSE; } return TRUE;"
}
```

Never generate a testcase that can run forever.

---

## Switch rules

### Single `case LABEL:`

Generate one parent testcase setting the switch expression to `LABEL`. Generate child testcases for decisions inside that case body using the case parent path.

### Fall-through group

For consecutive labels sharing one body:

```c
case A:
case B:
case C:
{
    body;
    break;
}
```

Generate one top-level testcase per label:

- switch value = `A`
- switch value = `B`
- switch value = `C`

The body is shared, but every label is a separate entry point.

Generate child testcases for inner decisions from one representative parent path unless a label changes behavior before reaching the shared body.

### `default:`

Generate one testcase using an unused value that does not match any explicit case label. Use a valid out-of-set value suitable for the switch data type.

### New case scope

Each new case starts from the effective defaults plus values required to select that case. Do not accidentally inherit a different case label from the previous case.

---

## Bit-field union rules

A union overlays a raw value and bit-field members. For an 8-bit raw value:

| Bit | Numeric contribution |
|---:|---:|
| 0 | 1 |
| 1 | 2 |
| 2 | 4 |
| 3 | 8 |
| 4 | 16 |
| 5 | 32 |
| 6 | 64 |
| 7 | 128 |

Use the sum of all required bit values. Use `0` to clear all bits.

### Global union

Check the GLOBAL VARIABLES interface first.

- If the raw byte member is listed, set the raw byte member.
- If only struct/bit-field members are listed, set the full listed struct-member paths.
- Never reference a member absent from the interface.

Examples:

```text
GlobalUnion[0].RawByte = 5
```

or:

```text
GlobalUnion[0].flags.FLAG_A = 1
GlobalUnion[0].flags.FLAG_B = 0
```

### Local union filled by a stub

Use only stub return behavior:

```json
{
  "Name": "ReadStatus",
  "Return": "5"
}
```

Do not attempt to set local union members through `SetValues`.

---

## Pointer-object rules

Use this shape for pointer inputs:

```json
{
  "PointerName": "config_ptr",
  "Allocate": true,
  "DynamicObject": "target_config_ptr",
  "Members": [
    {
      "Name": "memberA",
      "Value": "1"
    },
    {
      "Name": "nested",
      "Members": [
        {
          "Name": "memberB",
          "Value": "FALSE"
        }
      ]
    }
  ]
}
```

Rules:

- `PointerName` exactly matches the interface variable.
- `DynamicObject` is normally `target_<PointerName>`.
- `Allocate=true` creates the pointed object.
- `Allocate=false` keeps the pointer deallocated.
- `Members` recursively initializes the pointed object.
- Do not duplicate the same pointer object in one testcase.

---

## Mandatory final verification

Perform this verification before writing JSON.

### Decision completeness

- Every reachable `if` has TRUE and FALSE outcomes.
- Every reachable `else if` has TRUE and FALSE outcomes after preceding conditions are false.
- Every `else` has a testcase where all preceding conditions are false.
- Every ternary has TRUE and FALSE selections.
- Every loop has zero-iteration and safe entered-loop coverage when reachable.
- Every `&&` and `||` has all required short-circuit paths.
- Every explicit switch label has a testcase.
- Every fall-through label has its own testcase.
- Every `default` has an unused-value testcase.

### Reachability completeness

- Every nested target includes its complete parent path.
- Every testcase reaches its declared `Target`.
- No testcase claims coverage for code that its values cannot reach.

### Stub completeness

- Every decision-controlling external function has explicit behavior.
- Every stub name exists in `EXTERNAL FUNCTIONS`.
- No `LOCAL FUNCTIONS` entry is emitted as an external stub.
- No return value is assigned to a `void` function.
- Loop-controlling stubs terminate safely.

### Data completeness

- Pointer inputs use pointer-object format.
- Every pointer allocated by a testcase has required members initialized through defaults or overrides.
- Symbolic bool/enum labels are used when available.
- No path references an interface member that does not exist.
- No duplicate effective path exists in one testcase.
- No duplicate effective stub name exists in one testcase.

### JSON completeness

- `TCId` values are unique and sequential from 1.
- `TotalTestCases` exactly equals `TestCases.Count`.
- Every testcase has `Description`, `Target`, `SetValues`, and `StubFunctions`.
- `DefaultValues` contains shared state only.
- `SetValues` contains testcase-specific overrides only.
- JSON is valid and contains no comments or trailing commas.

If any verification item fails, fix the testcase inventory before writing the file.

---

## Output JSON contract

```json
{
  "FunctionSignature": "<return_type> <FunctionName>(<params>)",
  "TotalTestCases": 3,
  "DefaultValues": [
    {
      "Path": "<shared_variable_or_member_path>",
      "Value": "<value>"
    },
    {
      "PointerName": "<pointer_variable_name>",
      "Allocate": true,
      "DynamicObject": "target_<pointer_variable_name>",
      "Members": [
        {
          "Name": "<member_name>",
          "Value": "<value>"
        }
      ]
    }
  ],
  "TestCases": [
    {
      "TCId": 1,
      "Description": "<primary target and outcome>",
      "Target": "<reachable branch, decision, loop path, or case label>",
      "SetValues": [
        {
          "Path": "<variable_path>",
          "Value": "<value>"
        },
        {
          "PointerName": "<pointer_variable_name>",
          "Allocate": true,
          "DynamicObject": "target_<pointer_variable_name>",
          "Members": [
            {
              "Name": "<member_name>",
              "Value": "<value>"
            }
          ]
        }
      ],
      "StubFunctions": [
        {
          "Name": "<external_stub_name>",
          "Return": "<symbolic_label_or_literal>"
        }
      ]
    }
  ]
}
```

### Stub body form

Use `Body` instead of `Return` when behavior must vary across calls:

```json
{
  "Name": "<external_stub_name>",
  "Body": "<valid C statements>"
}
```

Do not emit both `Return` and `Body` for the same stub entry.

---

## Completion rule

Set `TotalTestCases` only after the final testcase array is complete.

The generated plan is complete only when:

1. every mandatory verification item passes;
2. `TotalTestCases` equals the actual array length;
3. the JSON is saved to the exact requested path;
4. Step 7 can consume the plan without inventing reachability values or stub signatures.
