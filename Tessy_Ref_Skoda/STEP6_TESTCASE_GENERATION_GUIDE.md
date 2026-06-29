# Step 6 — Test Case Generation Guide

## Goal
Read `<TestObject>_conditions_after_passing.c` → write `<TestObject>_testcase_plan.json`.
Walk the function body **once, top-to-bottom**. Emit TCs as you go. Write JSON immediately after scanning — no pre-counting pass.

> **Speed rule: Do NOT think about C0/C1 coverage. Do NOT check if TCs will pass coverage. Your only job: set values so each condition evaluates to TRUE or FALSE. Done → next condition.**

> **Scope rule: Only set values for variables/stubs that directly control the condition of THIS test case. Do NOT set values for all variables — Step 7 handles the remaining variables.**

> **Compact JSON rule: Output only the data Step 7 needs. Do NOT copy the full function body into the JSON.**

---

## Rules (always apply)

| Rule | Action |
|------|--------|
| **Index** | `array[param]` → `param = 0`. `array[stub()]` → stub returns `0`. |
| **Stub** | Every function call is a stub. Set its return to satisfy TRUE or FALSE. |
| **Symbolic enum** | For `bool`, `boolean_t`, or any enum return/value, use the enum label directly (`TRUE`, `FALSE`, `STATE_X`) — **never** `1` / `0` when a symbolic label exists. |
| **Inherit** | Each TC copies ALL SetValues + StubFunctions from its parent, then only changes what the new condition requires. |
| **New scope** | Each `case LABEL:` resets to: `<index_param> = 0` + `<state>[0] = LABEL` + all stubs = 0. |
| **1 TC = 1 condition** | One condition TRUE or FALSE per TC. Never combine unrelated decisions. |

---

## Decision Point → TC count

| Pattern | TCs |
|---------|-----|
| `v = (C) ? A : B` | 2: C=TRUE → v=A; C=FALSE → v=B |
| `if (C)` | 2: C=TRUE; C=FALSE |
| `else if (C)` | 2: inherit FALSE-path so far + C=TRUE; same + C=FALSE |
| `else` | 1: inherit all prior FALSE-path values |
| `case LABEL:` (single label) | 1 parent TC (fresh scope), then child TCs for each decision inside the case body |
| `case A:` / `case B:` / `case C:` … `{ break; }` (fall-through group) | **1 TC per case label** — each label is a separate entry point that must be covered independently. All labels in the group share the same body, but Tessy counts coverage per entry point. Example: `case MCU_DRL_PO_ON:` `case TI_DRL_PO_OFF:` `case DRL_PO_OFF:` `case DRL_ON:` `{ … break; }` → **4 TCs**, one for each label. |
| `default:` | 1: state = any unused value (e.g. 99) |
| nested `if` inside a branch | inherit parent TRUE-path, add new condition |

> **Fall-through rule (critical for C0/C1)**: When N consecutive `case` labels share one `{ … break; }` body, you MUST generate N separate TCs — one per label. Each TC sets the switch variable to that specific label's value. Child TCs for inner decisions inside the shared body are generated once from the first (or any representative) parent, but **each label still needs its own top-level TC**.

---

## SetValue by data type

| Data type | TRUE / non-zero value | FALSE / zero value |
|---|---|---|
| `uint8_t` / `uint16_t` / `uint32_t` / `uint64_t` | `1` | `0` |
| `int8_t` / `int16_t` / `int32_t` / `int64_t` | `1` | `0` |
| `bool` / `boolean_t` | `TRUE` | `FALSE` |
| `float` / `double` | `1.0` | `0.0` |
| pointer type | `1` (non-NULL) | `0` (NULL) |
| `enum` | use the enum label directly (e.g. `STATE_ACTIVE`) | use the label for the "off/idle" value |
| bit-field inside union | → use stub return (see section below) | → stub returns `0` |
| array index param | always `0` | — |
| **local static variable** | `FunctionName::varName#1[0] = <value>` | same format, value = 0/FALSE |

> **Local static rule**: If the interface lists a variable as `FunctionName::varName#1[N]`, it is a local static. Always use the full `FunctionName::varName#1[0]` notation in SetValues — never just `varName`.

---

## Bit-field (union) — how N maps to bit fields

A union overlays a raw byte and a bit-field struct on the same memory.  
Setting the byte member `<union>.<byte_field> = N` sets all bit fields simultaneously:

| Bit | Value | Effect |
|-----|-------|--------|
| 0 | 1 | bit-field at position 0 = 1 |
| 1 | 2 | bit-field at position 1 = 1 |
| 2 | 4 | bit-field at position 2 = 1 |
| 3 | 8 | bit-field at position 3 = 1 |
| 4 | 16 | bit-field at position 4 = 1 |
| 5 | 32 | bit-field at position 5 = 1 |
| 6 | 64 | bit-field at position 6 = 1 |
| 7 | 128 | bit-field at position 7 = 1 |

**N = sum of values for all bits you need set to 1. N = 0 clears all bits.**

---

## Bit-field (union) — global vs local

| Case | How to set |
|------|-----------|
| **Global union — interface lists the raw byte member** | SetValues: `<globalUnion>[0].<byte_member> = N` |
| **Global union — interface lists only struct/bit-field members** | SetValues: `<globalUnion>[0].<struct_member>.<field_name> = <value>` for each listed field |
| **Local union** filled by a stub call | StubFunctions only: `<StubName> returns N` — **never use SetValues** |

> **Interface-driven rule**: Always check the GLOBAL VARIABLES section of `_conditions_after_passing.c` first.
> - If the raw byte member (e.g. `StatusFlag0Register_u8`) **appears in the interface** → use `union[0].<byte_member> = N`.
> - If it does **NOT appear** and only struct fields are listed (e.g. `struct flags_st → FLAG_OUT_b1`) → use the full struct path: `union[0].<struct_member>.<field_name> = 1/0`.
> - **Never reference members that are absent from the interface.** The raw byte and struct member access the same memory, but Tessy only knows about what the interface declares.

For local unions: the stub's return byte fills `<byte_field>` and sets all bit fields simultaneously. You cannot access local variables from SetValues.

---

## Output JSON

```json
{
  "FunctionSignature": "<return_type> <FunctionName>(<params>)",
  "TotalTestCases": <N>,
  "TestCases": [
    {
      "TCId": 1,
      "Description": "<decision_type> TRUE: <what_it_covers>",
      "Target": "<branch or decision reached>",
      "SetValues": [
        {
          "Path": "<param_or_variable_path>",
          "Value": "<value>"
        }
      ],
      "StubFunctions": [
        {
          "Name": "<StubName>",
          "Return": "<enum_label_or_literal>"
        }
      ]
    },
    {
      "TCId": 2,
      "Description": "<decision_type> FALSE: <what_it_covers>",
      "Target": "<branch or decision reached>",
      "SetValues": [
        {
          "Path": "<param_or_variable_path>",
          "Value": "<value>"
        }
      ],
      "StubFunctions": []
    }
  ]
}
```

Use the object form above for `SetValues` and `StubFunctions`. It is faster and less error-prone for Step 7 to consume. Legacy string entries are tolerated, but Step 6 should not generate them.

Set `TotalTestCases` to the actual count of TCs in the array after writing them all.
