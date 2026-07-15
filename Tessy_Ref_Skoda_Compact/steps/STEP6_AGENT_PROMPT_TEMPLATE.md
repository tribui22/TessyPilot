---
mode: agent
description: "Step 6 - Generate test case plan JSON for {{TEST_OBJECT}}"
---

# Step 6: Generate `{{TEST_OBJECT}}_testcase_plan.json`

## Task

Analyze the supplied condition-relevant C source and generate a complete testcase plan.

Write the result to:

`{{OUTPUT_JSON_PATH}}`

Do not modify the generation guide, source input, PowerShell scripts, or unrelated files.

## Required inputs

- Test object: `{{TEST_OBJECT}}`
- Analysis source: `{{CONDITION_FILE_PATH}}`
- Generation rules: embedded below

---

## Testcase-generation guide

{{GENERATION_GUIDE}}

---

## Condition-relevant C input

Source file: `{{CONDITION_FILE_PATH}}`

```c
{{CONDITION_SOURCE}}
```

---

## Execution requirements

1. Walk the function body top-to-bottom and apply every rule from the guide.
2. Emit one testcase per required decision outcome; do not skip a decision point.
3. Apply index, inheritance, fall-through, interface-driven union, local-static, and pointer-object rules.
4. Use symbolic labels for boolean and enum values whenever available.
5. Fully initialize pointer-to-struct IN/INOUT inputs through pointer-object entries.
6. Put values shared by most testcases in `DefaultValues`; put only testcase deltas in `SetValues`.
7. Keep the JSON compact. Do not copy source text into the JSON.
8. Set `TotalTestCases` to the final number of elements in `TestCases`.
9. Validate the JSON syntax before finishing.
10. Save only the requested JSON artifact; do not add an explanation file.

## Required top-level JSON shape

```json
{
  "FunctionSignature": "<signature>",
  "TotalTestCases": 0,
  "DefaultValues": [],
  "TestCases": [
    {
      "TCId": 1,
      "Description": "TC1: ...",
      "Target": "...",
      "SetValues": [],
      "StubFunctions": []
    }
  ]
}
```

## Completion check

Before completing, verify:

- `TestCases` is not empty.
- `TotalTestCases` equals `TestCases.Count`.
- Every `TCId` is unique and sequential from 1.
- Every test case contains `Description`, `Target`, `SetValues`, and `StubFunctions`.
- Pointer entries use `PointerName`, `Allocate`, `DynamicObject`, and recursive `Members`.
- Output exists at `{{OUTPUT_JSON_PATH}}` and parses as valid JSON.
