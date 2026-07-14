import os
import re
import sys
import json
from pathlib import Path


def extract_block(text, keyword):
    """
    Finds keyword + optional space/argument + '{', and extracts everything up to the matching '}'.
    Handles nested braces correctly.
    """
    start_idx = text.find(keyword)
    if start_idx == -1:
        return None
    # Find the opening '{' for this keyword block
    brace_open_idx = text.find('{', start_idx + len(keyword))
    if brace_open_idx == -1:
        return None
    
    depth = 0
    for i in range(brace_open_idx, len(text)):
        char = text[i]
        if char == '{':
            depth += 1
        elif char == '}':
            depth -= 1
            if depth == 0:
                return text[brace_open_idx + 1:i]
    return None


def parse_assignments(block_text):
    """
    Parses key-value pairs from block text.
    """
    assignments = {}
    if not block_text:
        return assignments
    for line in block_text.splitlines():
        line = line.strip()
        if not line or line.startswith('$') or line.startswith('/') or line.startswith('*'):
            continue
        if '=' in line:
            parts = line.split('=', 1)
            key = parts[0].strip()
            val = parts[1].strip()
            # Strip comments
            val = re.sub(r'//.*$', '', val)
            val = re.sub(r'/\*.*?\*/', '', val)
            val = val.strip().rstrip(';')
            assignments[key] = val
    return assignments


def format_yaml_value(val):
    if val is None:
        return "''"
    val_str = str(val).strip()
    if not val_str:
        return "''"
    
    # If it is a step ID like tc1.1, it should not be quoted
    if re.match(r'^tc\d+\.\d+$', val_str):
        return val_str
    
    # If it's a known non-quoted symbol like target_config_ptr or other target_ variables
    if val_str.startswith('target_') and '[' not in val_str:
        return val_str
    
    # If it starts with a quote, keep it
    if (val_str.startswith("'") and val_str.endswith("'")) or (val_str.startswith('"') and val_str.endswith('"')):
        return val_str
        
    # If the value is a pure identifier (alphanumeric and underscore, doesn't start with a digit), leave unquoted
    if re.match(r'^[A-Za-z_][A-Za-z0-9_]*$', val_str):
        return val_str
        
    # Wrap in single quotes (escaping existing single quotes)
    escaped = val_str.replace("'", "''")
    return f"'{escaped}'"


def main():
    if len(sys.argv) < 5:
        print('Usage: python generate_tessy_import_yml.py <testobject> <module> <workdir> <scriptroot>')
        sys.exit(1)

    test_object = sys.argv[1]
    module = sys.argv[2]
    work_dir = Path(sys.argv[3])
    script_root = sys.argv[4]

    yml_dir = work_dir / 'yml'
    yml_dir.mkdir(parents=True, exist_ok=True)
    output_file = yml_dir / f'{test_object}_import.yml'

    plan_path = work_dir / 'json_testcase' / f'{test_object}_testcase_plan.json'
    script_path = work_dir / 'script_files' / f'{test_object}_testcase.script'
    if not plan_path.exists():
        # Fallback to legacy path if needed
        plan_path = work_dir / 'testObjectCode' / f'{test_object}_testcase_plan.json'
    if not plan_path.exists():
        raise SystemExit(f'Testcase plan not found: {plan_path}')
    if not script_path.exists():
        raise SystemExit(f'Testcase script not found: {script_path}')

    script_content = script_path.read_text(encoding='utf-8')

    # Parse stubs from testcase_plan.json or script_content
    stubs_dict = {}
    if plan_path.exists():
        try:
            plan = json.loads(plan_path.read_text(encoding='utf-8'))
            for tc in plan.get('TestCases', []):
                for stub in tc.get('StubFunctions', []):
                    name = stub.get('Name')
                    if name:
                        if 'Return' in stub and stub['Return']:
                            ret_val = str(stub['Return'])
                            if ret_val == 'TRUE':
                                ret_val = '1'
                            elif ret_val == 'FALSE':
                                ret_val = '0'
                            stubs_dict[name] = f"return {ret_val};"
                        else:
                            stubs_dict[name] = ""
        except Exception as e:
            print(f"Warning parsing plan json: {e}")

    # Parse stubs from script content using regex (restrict to $testobject-level $stubfunctions block)
    stubs_end_idx = script_content.find('$testcase')
    stubs_section = script_content[:stubs_end_idx] if stubs_end_idx != -1 else script_content

    stub_func_matches = re.finditer(
        r'(void|boolean_t|u32|u16|u8|u64|s32|s16|s8|s64|float|double|struct\s+\w+|[A-Za-z_][A-Za-z0-9_]*)\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(([^)]*)\)\s*\'\'\'(.*?)\'\'\'',
        stubs_section,
        re.DOTALL
    )
    for m in stub_func_matches:
        ret_type = m.group(1)
        name = m.group(2)
        body = m.group(4).strip()
        body_lines = [line.strip() for line in body.splitlines() if line.strip()]
        cleaned_body = " ".join(body_lines)
        if cleaned_body:
            stubs_dict[name] = cleaned_body
        elif name not in stubs_dict:
            stubs_dict[name] = ""

    # Fallback to general/known stubs:
    for name in list(stubs_dict.keys()):
        if name in ('ucDrv_FCCDone', 'ucDrv_ReadFCC'):
            if not stubs_dict[name]:
                stubs_dict[name] = 'return 0;'

    stub_lines = []
    # Sort stub names to be deterministic
    for stub_name in sorted(stubs_dict.keys()):
        body = stubs_dict[stub_name]
        stub_lines.append(f"- ['0', '0', {stub_name}, '{body}']")

    # Now parse teststeps dynamically
    teststeps = []
    # Find all occurrences of "$teststep"
    for m in re.finditer(r'\$teststep\s+([0-9\.]+)\s*\{', script_content):
        step_id = m.group(1)
        start_idx = m.start()
        step_body = extract_block(script_content[start_idx:], "$teststep")
        if step_body:
            teststeps.append((step_id, step_body))

    # Parse dynamic inputs and outputs from teststeps
    all_input_keys = set()
    all_output_keys = set()
    testcases_data = []

    for step_id, step_body in teststeps:
        inputs_body = extract_block(step_body, "$inputs")
        outputs_body = extract_block(step_body, "$outputs")
        
        inputs_dict = parse_assignments(inputs_body)
        outputs_dict = parse_assignments(outputs_body)
        
        all_input_keys.update(inputs_dict.keys())
        all_output_keys.update(outputs_dict.keys())
        
        testcases_data.append((step_id, inputs_dict, outputs_dict))

    # Helper function to check if a key should be prefixed with &
    def get_header_name(key):
        if key.startswith('target_') and '.' in key:
            return f"&{key}"
        return key

    # Format value rows correctly
    def normalize_row_value(val):
        if val.startswith('&'):
            val = val[1:]
        # Normalize target_xxx[0] -> target_xxx
        match = re.match(r'^(target_[A-Za-z0-9_]+)\[\d+\]$', val)
        if match:
            return match.group(1)
        return val

    # We want to separate input columns and output columns
    # Sort headers to be deterministic: target columns first, then other inputs, then outputs
    target_input_keys = sorted([k for k in all_input_keys if k.startswith('target_') and '.' in k])
    other_input_keys = sorted([k for k in all_input_keys if not (k.startswith('target_') and '.' in k)])
    output_keys = sorted(list(all_output_keys))

    final_headers_keys = target_input_keys + other_input_keys + output_keys
    final_headers_names = [get_header_name(k) for k in final_headers_keys]
    
    # Generate Types row
    types_row = []
    for k in final_headers_keys:
        if k in all_input_keys:
            types_row.append('i')
        else:
            types_row.append('o')

    # Generate values rows
    rows_lines = []
    for step_id, inputs_dict, outputs_dict in testcases_data:
        row_vals = [f"tc{step_id}"]
        for k in final_headers_keys:
            val_str = ""
            if k in inputs_dict:
                val_str = normalize_row_value(inputs_dict[k])
            elif k in outputs_dict:
                val_str = normalize_row_value(outputs_dict[k])
            
            # Format according to our format_yaml_value rules
            row_vals.append(format_yaml_value(val_str))
            
        rows_lines.append(f"- [{', '.join(row_vals)}]")

    lines = []
    lines.append(r"Tessy: {Version: 5.1.14, File Type: Import/Export}")
    lines.append('---')
    lines.append(f"General: {{Project: sk336_t2, Testobject: {test_object}, PDB File: '{work_dir.parent / 'test' / 'tessy' / 'tessy.pdbx'}', Tessy Version: 5.1.14, Export Date: '2026-07-10', Module: {module}}}")
    lines.append('---')
    lines.append('Properties:')
    lines.append("- ['1', '0', '', Dummy, '', '', '', '']")
    
    if stub_lines:
        lines.append('---')
        lines.append('Stubs:')
        lines.extend(stub_lines)
        
    lines.append('---')
    lines.append('Values:')
    # Headers line need to have quoted names if they are ampersanded or special strings
    headers_formatted = [f"'{h}'" if h.startswith('&') else h for h in final_headers_names]
    lines.append(f"- [{', '.join(headers_formatted)}]")
    lines.append(f"- [{', '.join(types_row)}]")
    lines.extend(rows_lines)

    output_file.write_text('\n'.join(lines) + '\n', encoding='utf-8')
    print(f'Generated Tessy import YAML: {output_file}')


if __name__ == '__main__':
    main()


if __name__ == '__main__':
    main()
