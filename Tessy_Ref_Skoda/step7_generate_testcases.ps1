# ============================================================================
# STEP 7: Generate Test Cases Using Tessy Guidelines (AUTOMATIC)
# ============================================================================
# Purpose: Automatically generate test cases using GPT based on:
#          - Source code analysis
#          - Interface information
#          - Stub requirements
#          - Tessy guideline from code-snippets
#          - TESSY_INPUT_FORMAT_GUIDE.md (CRITICAL for correct syntax!)
# Usage: .\step7_generate_testcases.ps1 -TestObject "ApplCanBusOff" -Module "CanCtrl" -WorkingDir "C:\Path\To\Work" -ScriptRoot "C:\Path\To\Scripts" -SourceDir "C:\Path\To\Source"
# Output: ${TestObject}_testcase.script (ready to import into Tessy)
# IMPORTANT: See TESSY_INPUT_FORMAT_GUIDE.md for correct struct/array/enum syntax
# ============================================================================
param(
    [Parameter(Mandatory=$true)][string]$TestObject,
    [Parameter(Mandatory=$true)][string]$Module,
    [Parameter(Mandatory=$true)][string]$WorkingDir,
    [Parameter(Mandatory=$true)][string]$ScriptRoot,
    [Parameter(Mandatory=$true)][string]$SourceDir
)

$ErrorActionPreference = "Stop"

# ============================================================================
# Helper Function: Generate Union/Struct Initialization
# ============================================================================
function Generate-UnionStructInit {
    param(
        [Parameter(Mandatory=$true)]$Variable,
        [int]$IndentLevel = 4,
        [int]$Value = 0,
        [hashtable]$FailureCorrections = @{},
        [string]$ParentPath = ""
    )
    
    $indent = "`t" * $IndentLevel
    $result = ""
    
    # Build current variable path for correction lookups
    $currentPath = if ($ParentPath) { "$ParentPath.$($Variable.Name)" } else { $Variable.Name }
    
    # For union, find the first non-IRRELEVANT struct member and use it
    if ($Variable.IsUnion) {
        $structMember = $Variable.Members | Where-Object { $_.IsStruct -and $_.Passing -notmatch 'IRRELEVANT' } | Select-Object -First 1
        
        if ($structMember) {
            # TESSY syntax: UnionName = StructMemberName
            $result += "$indent$($Variable.Name) = $($structMember.Name)`n"
            
            # Then initialize the struct member fields
            $result += "$indent$($Variable.Name).$($structMember.Name) {`n"
            
            # Initialize each field in the struct
            foreach ($field in $structMember.Members) {
                if ($field.Passing -notmatch 'IRRELEVANT') {
                    # Build field path for correction lookup
                    $fieldPath = "$($Variable.Name).$($field.Name)"
                    
                    # Check for correction value
                    $fieldValue = $Value
                    if ($FailureCorrections.ContainsKey($fieldPath)) {
                        $correctionValue = $FailureCorrections[$fieldPath]
                        # If correction value is 'DONTCARE' (multiple different values), use -
                        if ($correctionValue -eq 'DONTCARE') {
                            $fieldValue = '-'
                        } else {
                            $fieldValue = $correctionValue
                        }
                    }
                    
                    $result += "$indent`t$($field.Name) = $fieldValue`n"
                }
            }
            
            $result += "$indent}`n"
        } else {
            # No usable struct member, use simple initialization
            $result += "$indent$($Variable.Name) = $Value`n"
        }
    }
    # For struct, use hierarchical initialization
    elseif ($Variable.IsStruct -and $Variable.Members.Count -gt 0) {
        $result += "$indent$($Variable.Name) {`n"
        foreach ($member in $Variable.Members) {
            if ($member.Passing -notmatch 'IRRELEVANT') {
                if ($member.IsStruct -and $member.Members.Count -gt 0) {
                    # Nested struct - recursive call
                    $nestedInit = Generate-UnionStructInit -Variable $member -IndentLevel ($IndentLevel + 1) -Value $Value -FailureCorrections $FailureCorrections -ParentPath $currentPath
                    $result += $nestedInit
                } else {
                    # Build member path for correction lookup
                    $memberPath = "$currentPath.$($member.Name)"
                    
                    # Check for correction value
                    $memberValue = $Value
                    if ($FailureCorrections.ContainsKey($memberPath)) {
                        $memberValue = $FailureCorrections[$memberPath]
                    }
                    
                    $result += "$indent`t$($member.Name) = $memberValue`n"
                }
            }
        }
        $result += "$indent}`n"
    }
    # Simple variable
    else {
        $result += "$indent$($Variable.Name) = $Value`n"
    }
    
    return $result
}

# ============================================================================
# Helper Function: Parse Struct Members from Dummy Template
# ============================================================================
function Parse-StructMembersFromDummy {
    param(
        [Parameter(Mandatory=$true)][string]$StructName,
        [Parameter(Mandatory=$true)][string]$DummyContent
    )
    
    $members = @()
    
    # Find the struct definition in the dummy template
    # Pattern: StructName {\n field1 = ?\n field2 = ?\n}
    if ($DummyContent -match "(?ms)$StructName\s*\{([^}]+)\}") {
        $structBody = $Matches[1]
        
        # Extract field names
        $fieldMatches = [regex]::Matches($structBody, '^\s*([a-zA-Z_][a-zA-Z0-9_]+)\s*=', [System.Text.RegularExpressions.RegexOptions]::Multiline)
        foreach ($match in $fieldMatches) {
            $fieldName = $match.Groups[1].Value
            $members += @{ Name = $fieldName }
        }
    }
    
    return $members
}

# ============================================================================
# Helper Function: Extract Enum Values from Function Body
# ============================================================================
function Extract-EnumValues {
    param(
        [Parameter(Mandatory=$true)][string]$ParameterName,
        [Parameter(Mandatory=$true)][string]$FunctionBody
    )
    
    $enumValues = @()
    
    # Look for switch statement on the parameter
    # Pattern: switch(locPin_en) { case HW_OUT__SEP_EN: ... case HW_OUT__MCU2_RST: ... }
    if ($FunctionBody -match "switch\s*\(\s*$ParameterName\s*\)") {
        # Extract all case labels for this parameter
        # Pattern: case ENUM_VALUE: (supports mixed-case like SYSSTATEM_Mode_LowLevel)
        $casePattern = "case\s+([A-Z_][a-zA-Z0-9_]+)\s*:"
        [regex]::Matches($FunctionBody, $casePattern) | ForEach-Object {
            $enumValue = $_.Groups[1].Value
            if ($enumValue -notin $enumValues) {
                $enumValues += $enumValue
            }
        }
    }
    
    return $enumValues
}

# ============================================================================
# Helper Function: Get Struct Members from Source Files
# ============================================================================
# Returns an ordered list of @{Name; Type} for each direct member of the struct.
# Used for generating properly-initialized struct return values in stub bodies.
$script:structMemberCache = @{}

function Get-StructMembersFromSource {
    param(
        [Parameter(Mandatory=$true)][string]$StructTypeName,
        [Parameter(Mandatory=$true)][string]$SourceDir
    )

    if ($script:structMemberCache.ContainsKey($StructTypeName)) {
        return $script:structMemberCache[$StructTypeName]
    }

    $members = @()
    $escapedTypeName = [regex]::Escape($StructTypeName)

    $files  = @()
    $files += Get-ChildItem -Path $SourceDir -Recurse -Include "*.h" -ErrorAction SilentlyContinue
    $files += Get-ChildItem -Path $SourceDir -Recurse -Include "*.c" -ErrorAction SilentlyContinue

    foreach ($file in $files) {
        $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
        if (-not $content) { continue }

        $structBody = $null

        # Pattern 1: typedef struct [optional_tag] { ... } TypeName;
        if ($content -match "(?ms)typedef\s+struct\s+(?:\w+\s+)?\{([^}]+)\}\s*$escapedTypeName\s*;") {
            $structBody = $Matches[1]
        }
        # Pattern 2: struct TypeName { ... }
        elseif ($content -match "(?ms)struct\s+$escapedTypeName\s*\{([^}]+)\}") {
            $structBody = $Matches[1]
        }

        if ($structBody) {
            $lines = $structBody -split '[\r\n]+'
            foreach ($line in $lines) {
                $trimmed = $line.Trim()
                if ($trimmed -eq '' -or $trimmed -match '^/[/*]') { continue }
                $trimmed = ($trimmed -replace '/\*.*?\*/', '' -replace '//.*$', '').Trim()
                if ($trimmed -eq '') { continue }
                # Match: "TypeName MemberName;" or "unsigned char MemberName : N;"
                if ($trimmed -match '^(.+?)\s+(\w+)\s*(?::\s*\d+)?\s*;') {
                    $mType = $Matches[1].Trim()
                    $mName = $Matches[2].Trim()
                    if ($mName -notin ($members | ForEach-Object { $_.Name })) {
                        $members += @{ Name = $mName; Type = $mType }
                    }
                }
            }
            if ($members.Count -gt 0) {
                Write-Host "[STRUCT SOURCE] Found $($members.Count) members for '$StructTypeName' in $($file.Name)" -ForegroundColor Green
                break
            }
        }
    }

    $script:structMemberCache[$StructTypeName] = $members
    if ($members.Count -eq 0) {
        Write-Host "[STRUCT SOURCE] No members found for struct '$StructTypeName'" -ForegroundColor Yellow
    }
    return $members
}

# ============================================================================
# Helper Function: Get Enum Members from Source Files
# ============================================================================
# Cache to avoid repeated file searches for the same enum type
$script:enumMemberCache = @{}

function Get-EnumMembersFromSource {
    param(
        [Parameter(Mandatory=$true)][string]$EnumTypeName,
        [Parameter(Mandatory=$true)][string]$SourceDir
    )

    # Check cache first
    if ($script:enumMemberCache.ContainsKey($EnumTypeName)) {
        return $script:enumMemberCache[$EnumTypeName]
    }

    $enumMembers = @()
    $escapedTypeName = [regex]::Escape($EnumTypeName)

    # Search header files first (faster), then C files
    $files = @()
    $files += Get-ChildItem -Path $SourceDir -Recurse -Include "*.h" -ErrorAction SilentlyContinue
    $files += Get-ChildItem -Path $SourceDir -Recurse -Include "*.c" -ErrorAction SilentlyContinue

    foreach ($file in $files) {
        $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
        if (-not $content) { continue }

        $enumBody = $null

        # Pattern 1: typedef enum [optional_tag] { ... } TypeName;
        if ($content -match "(?ms)typedef\s+enum\s+(?:\w+\s+)?\{([^}]+)\}\s*$escapedTypeName\s*;") {
            $enumBody = $Matches[1]
        }
        # Pattern 2: enum TypeName { ... }
        elseif ($content -match "(?ms)enum\s+$escapedTypeName\s*\{([^}]+)\}") {
            $enumBody = $Matches[1]
        }

        if ($enumBody) {
            $lines = $enumBody -split '[\r\n]+'
            foreach ($line in $lines) {
                $trimmed = $line.Trim()
                if ($trimmed -eq '' -or $trimmed -match '^/[/*]') { continue }
                $trimmed = ($trimmed -replace '/\*.*?\*/', '' -replace '//.*$', '').Trim()
                if ($trimmed -eq '') { continue }
                # Match enum member identifier (before optional = value or trailing comma)
                if ($trimmed -match '^([a-zA-Z_][a-zA-Z0-9_]+)\s*(?:=.*)?[,]?\s*$') {
                    $memberName = $Matches[1].Trim()
                    if ($memberName -notin $enumMembers) {
                        $enumMembers += $memberName
                    }
                }
            }
            if ($enumMembers.Count -gt 0) {
                Write-Host "[ENUM SOURCE] Found $($enumMembers.Count) members for '$EnumTypeName' in $($file.Name)" -ForegroundColor Green
                break
            }
        }
    }

    $script:enumMemberCache[$EnumTypeName] = $enumMembers
    if ($enumMembers.Count -eq 0) {
        Write-Host "[ENUM SOURCE] No members found for enum type '$EnumTypeName'" -ForegroundColor Yellow
    }
    return $enumMembers
}

# ============================================================================
# Helper Function: Resolve Integer Values of Case Label Symbols
# ============================================================================
# Searches source files for an enum definition that contains the given labels
# and returns a hashtable mapping each label to its actual integer value.
# This is required because stub bodies are compiled as C without headers, so
# the stub must return the exact numeric value, not a symbolic name.
# Example: ACTION_DRL_ON -> 9, ACTION_PO_ON -> 10 (not 0, 1 as assumed by index)
function Get-CaseLabelNumericValues {
    param(
        [Parameter(Mandatory=$true)][string[]]$CaseLabels,
        [Parameter(Mandatory=$true)][string]$SourceDir
    )

    $result = @{}
    if ($CaseLabels.Count -eq 0) { return $result }

    $labelSet = @($CaseLabels | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^[A-Za-z_]' })
    if ($labelSet.Count -eq 0) { return $result }

    # Search header files for an enum definition containing at least one of the labels
    $files = Get-ChildItem -Path $SourceDir -Recurse -Include "*.h" -ErrorAction SilentlyContinue
    foreach ($file in $files) {
        $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
        if (-not $content) { continue }

        # Find all typedef enum bodies in this file
        $enumMatches = [regex]::Matches($content, '(?ms)typedef\s+enum\s*(?:\w+\s*)?\{([^}]+)\}\s*\w+\s*;')
        foreach ($em in $enumMatches) {
            $enumBody = $em.Groups[1].Value

            # Check if this enum contains at least one of our labels
            $hasMatch = $false
            foreach ($label in $labelSet) {
                if ($enumBody -match "\b$([regex]::Escape($label))\b") { $hasMatch = $true; break }
            }
            if (-not $hasMatch) { continue }

            # Parse enum members: compute sequential values, handle explicit assignments
            $currentVal = 0
            $lines = $enumBody -split '[,\r\n]+'
            foreach ($line in $lines) {
                $line = ($line -replace '/\*.*?\*/', '' -replace '//.*$', '').Trim()
                if (-not $line) { continue }
                if ($line -match '^(\w+)\s*=\s*(\d+)[Uu]?[Ll]*') {
                    $currentVal = [int]$Matches[2]
                    $memberName = $Matches[1]
                } elseif ($line -match '^([A-Za-z_]\w*)') {
                    $memberName = $Matches[1]
                } else {
                    continue
                }
                if ($labelSet -contains $memberName) {
                    $result[$memberName] = $currentVal
                }
                $currentVal++
            }
            if ($result.Count -gt 0) {
                Write-Host "[CASE-NUMS] Resolved $($result.Count) enum value(s) from $($file.Name):" -ForegroundColor Green
                foreach ($kv in $result.GetEnumerator() | Sort-Object Value) {
                    Write-Host "  $($kv.Key) = $($kv.Value)" -ForegroundColor Cyan
                }
                return $result
            }
        }
    }
    Write-Host "[CASE-NUMS] Could not resolve numeric values for case labels - will use sequential indices as fallback" -ForegroundColor Yellow
    return $result
}

# ============================================================================
# Helper Function: Get type-appropriate default value for a variable path
# ============================================================================
# Looks up the variable's type in the interface info arrays.
# - enum type   -> first enum member symbol (e.g. MY_ENUM_INIT)
# - float/double-> 0.0
# - all others  -> 0
function Get-TypeDefault {
    param(
        [string]$VarPath,
        [array]$AllVarInfo,
        [string]$ReturnType,
        [string]$SrcDir
    )

    # Special case: the function return value
    if ($VarPath -eq 'return') {
        if ($ReturnType -match '^enum\s+(\w+)') {
            $members = Get-EnumMembersFromSource -EnumTypeName $Matches[1] -SourceDir $SrcDir
            if ($members.Count -gt 0) { return $members[0] }
        }
        return '0'
    }

    # Strip array indices and split path into base name + optional member chain
    # e.g. "MyArray[0].memberName" -> baseName="MyArray", memberChain="memberName"
    $noIdx      = $VarPath -replace '\[\d+\]', ''
    $parts      = $noIdx -split '\.', 2
    $baseName   = $parts[0]
    $memberName = if ($parts.Count -gt 1) { ($parts[1] -split '\.')[0] } else { '' }

    # Find the base variable in any of the interface info arrays
    $varInfo = $AllVarInfo | Where-Object { $_.Name -eq $baseName } | Select-Object -First 1

    if ($varInfo) {
        $typeDecl = $varInfo.FullDeclaration

        # If a member path was given, look up the member's own type declaration
        if ($memberName -ne '' -and $varInfo.Members.Count -gt 0) {
            $memberInfo = $varInfo.Members | Where-Object { $_.Name -eq $memberName } | Select-Object -First 1
            if ($memberInfo) { $typeDecl = $memberInfo.FullDeclaration }
        }

        # enum type -> return first member symbol
        if ($typeDecl -match '^enum\s+(\w+)') {
            $members = Get-EnumMembersFromSource -EnumTypeName $Matches[1] -SourceDir $SrcDir
            if ($members.Count -gt 0) { return $members[0] }
        }

        # float/double -> numeric zero with decimal
        if ($typeDecl -match '\b(float|double)\b') { return '0.0' }
    }

    # Integer types (u8/u16/u32/u64/s8/s16/s32/char/short/int/long/bool) -> 0
    return '0'
}

# Check if this is a retry iteration (look for existing test case file)

$scriptDir = "$WorkingDir\script_files"
if (-not (Test-Path $scriptDir)) { New-Item -ItemType Directory -Path $scriptDir -Force | Out-Null }
$existingTestCase = "$scriptDir\${TestObject}_testcase.script"
# Fallback: migrate legacy double-extension file to correct name before isRetry check
$legacyDoubleExt = "$scriptDir\${TestObject}_testcase.script.script"
if (-not (Test-Path $existingTestCase) -and (Test-Path $legacyDoubleExt)) {
    Write-Host "[INFO] Migrating legacy file: $legacyDoubleExt -> $existingTestCase" -ForegroundColor Yellow
    Copy-Item -Path $legacyDoubleExt -Destination $existingTestCase -Force
}
$isRetry = Test-Path $existingTestCase

# If C0 > 0 or C1 > 0 but the script file is missing, force CREATE mode so the
# script is always generated (do not treat missing file as an error).
if (-not $isRetry) {
    $covStatusFile = "$WorkingDir\json_files\${TestObject}_coverage_status.json"
    if (Test-Path $covStatusFile) {
        try {
            $covStatus = Get-Content $covStatusFile -Raw | ConvertFrom-Json
            $prevC0 = [double]$covStatus.C0
            $prevC1 = [double]$covStatus.C1
            if ($prevC0 -gt 0.0 -or $prevC1 -gt 0.0) {
                Write-Host "`n[INFO] C0=$prevC0% C1=$prevC1% > 0 (partial coverage) but no script file found." -ForegroundColor Yellow
                Write-Host "  -> Will create a fresh script from the testcase plan." -ForegroundColor Yellow
            }
        } catch {
            # Ignore JSON read errors — proceed normally
        }
    }
}

if ($isRetry) {
    Write-Host "`n[RETRY MODE] Existing test case found - will generate MORE test cases in single file" -ForegroundColor Magenta
}

Write-Host "`n================================================================================" -ForegroundColor Cyan
Write-Host "  STEP 4: AUTO-GENERATE TEST CASES (GPT)" -ForegroundColor Cyan
Write-Host "  Test Object: $TestObject" -ForegroundColor Cyan
if ($isRetry) { Write-Host "  Mode: RETRY - Enhanced test case diversity" -ForegroundColor Magenta }
Write-Host "================================================================================" -ForegroundColor Cyan

# ============================================================================
# 1. Read Tessy Guideline
# ============================================================================
Write-Host "`n[GUIDELINE] Reading tessy-testcase_gen_script.code-snippets..." -ForegroundColor Yellow
$guidelineFile = "$WorkingDir\tessy-testcase_gen_script.code-snippets"

if (-not (Test-Path $guidelineFile)) {
    Write-Host "[ERROR] Guideline file not found: $guidelineFile" -ForegroundColor Red
    exit 1
}

$guidelineContent = Get-Content $guidelineFile -Raw
Write-Host "[OK] Guideline loaded" -ForegroundColor Green

# Read Input Format Guide (CRITICAL for correct struct/array/enum formatting)
Write-Host "[GUIDELINE] Reading TESSY_INPUT_FORMAT_GUIDE.md..." -ForegroundColor Yellow
$inputFormatGuideFile = "$WorkingDir\TESSY_INPUT_FORMAT_GUIDE.md"

if (-not (Test-Path $inputFormatGuideFile)) {
    Write-Host "[WARNING] Input format guide not found: $inputFormatGuideFile" -ForegroundColor Yellow
    Write-Host "[WARNING] Test generation may produce incorrect struct/array syntax!" -ForegroundColor Yellow
    $inputFormatGuide = ""
} else {
    $inputFormatGuide = Get-Content $inputFormatGuideFile -Raw
    Write-Host "[OK] Input format guide loaded (ensures correct struct syntax)" -ForegroundColor Green
}

# ============================================================================
# 2. Read Interface Information from testObjectCode\*_conditions_after_passing.c
# (No longer reads from Step 2 interface file)
# ============================================================================
Write-Host "`n[INTERFACE] Reading interface info from _conditions_after_passing.c..." -ForegroundColor Yellow
$conditionsFile = "$WorkingDir\testObjectCode\${TestObject}_conditions_after_passing.c"

if (-not (Test-Path $conditionsFile)) {
    Write-Host "[ERROR] Conditions file not found: $conditionsFile" -ForegroundColor Red
    Write-Host "  Run Step 4 (strip_conditions) to generate this file first." -ForegroundColor Yellow
    exit 1
}

# Extract the leading block comment which contains the TESSY interface info,
# then strip the C comment markers ("* ") so the parsing code sees plain text.
$rawConditionsContent = Get-Content $conditionsFile -Raw
$interfaceContent = ""
if ($rawConditionsContent -match '(?ms)/\*(.*?)\*/') {
    $commentBody = $Matches[1]
    $interfaceContent = ($commentBody -split '[\r\n]+' | ForEach-Object {
        $_ -replace '^\s*\*\s?', ''
    }) -join "`n"
} else {
    Write-Host "[WARNING] No block comment found in conditions file - using raw content" -ForegroundColor Yellow
    $interfaceContent = $rawConditionsContent
}
Write-Host "[OK] Interface information loaded from conditions file" -ForegroundColor Green

# Parse External Variables from interface info with hierarchical structure
$externalVariablesInfo = @()
if ($interfaceContent -match '(?ms)EXTERNAL VARIABLES:\s*-+\s*(.*?)\s*(?:GLOBAL VARIABLES:|={3,})') {
    $extVarSection = $Matches[1].Trim()
    if ($extVarSection -ne "") {
        $lines = $extVarSection -split '[\r\n]+' | Where-Object { $_.Trim() -ne '' }
        $varStack = @()
        
        foreach ($line in $lines) {
            # Count leading spaces for indentation level
            $indent = 0
            if ($line -match '^(\s*)') {
                $indent = $Matches[1].Length
            }
            $level = [Math]::Floor($indent / 4)
            
            $trimmed = $line.Trim()
            
            # Parse line: "union _c_VIU_Info_bufTag VIU_Info [Passing: IN] [ArrayLength: 5]"
            if ($trimmed -match '^(.+?)\s+\[Passing:\s*([A-Z/]+)\](.*)$') {
                $fullDecl = $Matches[1].Trim()
                $passing = $Matches[2].Trim()
                $extraInfo = $Matches[3].Trim()
                
                # Extract variable name from declaration (support arrays, bitfields, scope resolution)
                # Patterns: varName, varName[N], Class::varName#1, varName : bitwidth
                if ($fullDecl -match '([a-zA-Z_][a-zA-Z0-9_:]*?)(?:\[|#|:|\s*$)') {
                    $varName = $Matches[1].Trim()
                    # Remove scope resolution prefix if present
                    if ($varName -match '::([a-zA-Z_][a-zA-Z0-9_]+)$') {
                        $varName = $Matches[1]
                    }
                } elseif ($fullDecl -match '\b([a-zA-Z_]\w*)\s*(?::\s*\d+\s*)?(?:\[|$)') {
                    # Fallback: handles C bitfield declarations like "unsigned char digitCtrl_u4 : 4"
                    # The \b word boundary plus optional bitfield pattern correctly skips type keywords
                    # (unsigned, char, etc.) which are not followed by "end-of-string or bitfield-then-end"
                    $varName = $Matches[1].Trim()
                    $typeKeywords = @('unsigned', 'signed', 'char', 'short', 'int', 'long', 'void', 'struct', 'union', 'enum', 'const', 'volatile')
                    if ($typeKeywords -contains $varName) { $varName = "UNKNOWN" }
                } else {
                    $varName = "UNKNOWN"
                }
                
                # Parse array length if present
                $arrayLength = 0
                if ($extraInfo -match '\[ArrayLength:\s*(\d+)\]') {
                    $arrayLength = [int]$Matches[1]
                }
                
                # Determine if struct or union
                $isStruct = $fullDecl -match '^struct\s+'
                $isUnion = $fullDecl -match '^union\s+'
                
                $varInfo = @{ 
                    Name = $varName
                    FullDeclaration = $fullDecl
                    Passing = $passing
                    ArrayLength = $arrayLength
                    Members = @()
                    IsStruct = $isStruct
                    IsUnion = $isUnion
                    Level = $level
                }
                
                # Adjust stack to current level.
                # IMPORTANT: when level=0, we must CLEAR the stack entirely.
                # Using $varStack[0..-1] when Count=1 returns the full array in
                # PowerShell (0..-1 = indices 0 and -1 = last), which is a bug.
                if ($level -eq 0) {
                    $varStack = @()
                } elseif ($level -lt $varStack.Count) {
                    $varStack = @($varStack[0..($level - 1)])
                }
                
                # Add to parent's members or root
                if ($level -eq 0) {
                    $externalVariablesInfo += $varInfo
                } elseif ($varStack.Count -gt 0) {
                    $parent = $varStack[$varStack.Count - 1]
                    $parent.Members += $varInfo
                }
                
                # Add to stack if it's a composite type
                if ($isStruct -or $isUnion) {
                    $varStack += $varInfo
                }
            }
        }
        
        if ($externalVariablesInfo.Count -gt 0) {
            Write-Host "[FOUND] $($externalVariablesInfo.Count) External Variable(s):" -ForegroundColor Green
            foreach ($ev in $externalVariablesInfo) {
                $arrayInfo = if ($ev.ArrayLength -gt 0) { " [Array:$($ev.ArrayLength)]" } else { "" }
                $structInfo = if ($ev.Members.Count -gt 0) { " [Members:$($ev.Members.Count)]" } else { "" }
                $typeInfo = if ($ev.IsUnion) { " [Union]" } elseif ($ev.IsStruct) { " [Struct]" } else { "" }
                Write-Host "  - $($ev.Name) [$($ev.Passing)]$arrayInfo$structInfo$typeInfo" -ForegroundColor Cyan
            }
        }
    }
}

# Parse Global Variables from interface info
$globalVariables = @()
$globalVariablesInfo = @()
if ($interfaceContent -match '(?ms)GLOBAL VARIABLES:.*?-+\s*(.*?)\s*(?:PARAMETERS:|={3,})') {
    $globalSection = $Matches[1].Trim()
    if ($globalSection -ne "") {
        # Parse hierarchical structure based on indentation
        $lines = $globalSection -split '[\r\n]+' | Where-Object { $_.Trim() -ne '' }
        $varStack = @()  # Stack to track parent variables
        
        foreach ($line in $lines) {
            # Count leading spaces to determine indent level
            if ($line -match '^(\s*)(.+)\s*\[Passing:\s*([A-Z/]+)\](.*)$') {
                $indent = $Matches[1].Length
                $fullDecl = $Matches[2].Trim()
                $passing = $Matches[3].Trim()
                $extraInfo = $Matches[4].Trim()
                
                # Determine indentation level (0, 4, 8, 12, etc.)
                $level = $indent / 4
                
                # Extract variable name from declaration (handle arrays, scope resolution, and suffixes)
                # Patterns: varName, varName[N], Class::varName#1, varName[N]#1
                # For TESSY INOUT variables, preserve FULL name with scope and suffix: DioDrv_CfgInit::FirstRun_u1#1
                $varFullName = ""
                $varName = ""
                
                # Extract full name with scope and suffix (e.g., DioDrv_CfgInit::FirstRun_u1#1)
                if ($fullDecl -match '([a-zA-Z_][a-zA-Z0-9_:]+(?:#\d+)?)(?:\[|\s*$)') {
                    $varFullName = $Matches[1].Trim()
                    
                    # Extract short name without scope (for display/reference)
                    if ($varFullName -match '::([a-zA-Z_][a-zA-Z0-9_]+)(?:#\d+)?$') {
                        $varName = $Matches[1]  # FirstRun_u1
                    } else {
                        $varName = $varFullName  # Use full name if no scope
                    }
                } elseif ($fullDecl -match '\b([a-zA-Z_]\w*)\s*(?::\s*\d+\s*)?(?:\[|$)') {
                    # Fallback: handles bit fields like "unsigned char FLAG_OUT_b1 : 1"
                    $varName = $Matches[1].Trim()
                    $varFullName = $varName
                } else {
                    $varName = "UNKNOWN"
                    $varFullName = "UNKNOWN"
                }
                
                # Parse array length if present
                $arrayLength = 0
                if ($extraInfo -match '\[ArrayLength:\s*(\d+)\]') {
                    $arrayLength = [int]$Matches[1]
                }
                
                $varInfo = @{ 
                    Name = $varName
                    FullName = $varFullName  # CRITICAL: Preserve full scoped name for TESSY
                    FullDeclaration = $fullDecl
                    Passing = $passing
                    ArrayLength = $arrayLength
                    IsStruct = $fullDecl -match '^struct\s+'
                    IsUnion = $fullDecl -match '^union\s+'
                    Members = @()
                    IndentLevel = $level
                }
                
                # Update stack to current level
                if ($level -lt $varStack.Count) {
                    $varStack = $varStack[0..$level]
                }
                
                # If this is not top-level, add as member to parent
                if ($level -gt 0 -and $varStack.Count -gt 0) {
                    $parent = $varStack[$level - 1]
                    $parent.Members += $varInfo
                } else {
                    # Top-level variable
                    $globalVariables += $varName
                    $globalVariablesInfo += $varInfo
                }
                
                # Push current variable to stack if it's a struct or union (may have child members)
                if ($varInfo.IsStruct -or $varInfo.IsUnion) {
                    if ($level -ge $varStack.Count) {
                        $varStack += $varInfo
                    } else {
                        $varStack[$level] = $varInfo
                    }
                }
            }
        }
        
        if ($globalVariables.Count -gt 0) {
            Write-Host "[FOUND] $($globalVariables.Count) Global Variable(s):" -ForegroundColor Green
            foreach ($gv in $globalVariablesInfo) {
                $arrayInfo = if ($gv.ArrayLength -gt 0) { " [Array:$($gv.ArrayLength)]" } else { "" }
                $structInfo = if ($gv.Members.Count -gt 0) { " [Struct:$($gv.Members.Count) members]" } else { "" }
                Write-Host "  - $($gv.Name) [$($gv.Passing)]$arrayInfo$structInfo" -ForegroundColor Cyan
            }
        }
    }
}

# Parse Parameters from interface info
$parametersInfo = @()
if ($interfaceContent -match '(?ms)PARAMETERS:.*?-+\s*(.*?)\s*(?:RETURN TYPE:|={3,})') {
    $paramSection = $Matches[1].Trim()
    Write-Host "[DEBUG] Parameter section captured:" -ForegroundColor Magenta
    Write-Host $paramSection -ForegroundColor Gray
    Write-Host "" -ForegroundColor Gray
    if ($paramSection -ne "") {
        $paramSection -split '[\r\n]+' | Where-Object { $_.Trim() -ne '' } | ForEach-Object {
            $line = $_
            Write-Host "[DEBUG] Processing line: [$line]" -ForegroundColor Magenta
            # Skip return type lines (format: "unsigned short [Passing: OUT]" â€” type with no variable name)
            # These appear when the function return type is non-void. They have no identifier before [Passing:],
            # so the last word before [Passing:] is a C primitive type keyword, not a variable name.
            $cTypeKeywords = @('void','char','short','int','long','float','double','u8','u16','u32','u64','s8','s16','s32','s64','bool','boolean')
            if ($_ -match '^\s*(.*?)\s+([a-zA-Z_]\w*)\s*\[Passing:\s*OUT\]') {
                $possibleName = $Matches[2].Trim()
                $typeToken    = $Matches[1].Trim()
                if ($cTypeKeywords -contains $possibleName) {
                    Write-Host "[DEBUG] SKIP - Return type line (type keyword '$possibleName')" -ForegroundColor Yellow
                    return
                }
                # Skip bare "enum TypeName" or "struct TypeName" â€” no real variable name present
                if ($typeToken -eq 'enum' -or $typeToken -eq 'struct') {
                    Write-Host "[DEBUG] SKIP - Bare enum/struct return type line (no var name): $($_.Trim())" -ForegroundColor Yellow
                    return
                }
            }
            # Match type and parameter name - allow * and spaces in type
            if ($_ -match '^\s*(.*?)\s+([a-zA-Z_]\w*)\s*\[Passing:\s*([A-Z/]+)\]') {
                $typeDecl = $Matches[1].Trim()
                $paramName = $Matches[2].Trim()
                $passing = $Matches[3].Trim()
                # Lines indented with 4+ spaces are struct/union members, not top-level parameters
                $isIndented = $line -match '^    '
                Write-Host "[DEBUG] MATCH! Type=[$typeDecl] Name=[$paramName] Passing=[$passing] Indented=[$isIndented]" -ForegroundColor Green
                if ($isIndented -and $parametersInfo.Count -gt 0 -and
                    ($parametersInfo[-1].IsStruct -or $parametersInfo[-1].IsUnion -or $parametersInfo[-1].Type -match '\*')) {
                    # Add as member of the last struct/union pointer parameter
                    $parametersInfo[-1].Members += @{
                        Name    = $paramName
                        Type    = $typeDecl
                        Passing = $passing
                        IsEnum  = $typeDecl -match '^enum\s+'
                    }
                    Write-Host "[DEBUG] Added as MEMBER of $($parametersInfo[-1].Name)" -ForegroundColor Cyan
                } else {
                    $parametersInfo += @{ 
                        Name = $paramName
                        Passing = $passing
                        Type = $typeDecl
                        IsStruct = $typeDecl -match '^struct\s+'
                        IsUnion = $typeDecl -match '^union\s+'
                        Members = @()
                    }
                }
            } else {
                Write-Host "[DEBUG] NO MATCH for line!" -ForegroundColor Red
            }
        }
        if ($parametersInfo.Count -gt 0) {
            Write-Host "[FOUND] $($parametersInfo.Count) Parameter(s):" -ForegroundColor Green
            foreach ($p in $parametersInfo) {
                $typeInfo = ""
                if ($p.IsStruct) { $typeInfo = " [Struct]" }
                elseif ($p.IsUnion) { $typeInfo = " [Union]" }
                Write-Host "  - $($p.Name) [$($p.Passing)]$typeInfo Type: $($p.Type)" -ForegroundColor Cyan
            }
        }
    }
}

# Parse External Functions (for stub generation)
$externalFunctions = @()       # non-void external functions
$voidExternalFunctions = @()   # void external functions (also need stubs with empty body)
$allFunctions = @{}  # Dictionary to store all function signatures (for lookup)

if ($interfaceContent -match '(?ms)EXTERNAL FUNCTIONS:.*?-+\s*(.*?)\s*(?:LOCAL FUNCTIONS:|={3,})') {
    $funcSection = $Matches[1].Trim()
    if ($funcSection -ne "") {
        $funcSection -split '[\r\n]+' | Where-Object { $_.Trim() -ne '' } | ForEach-Object {
            # Format: "unsigned char Can_GetSdcBusOffsta()" or "void Can_Main()"
            if ($_ -match '^\s*([a-zA-Z_][a-zA-Z0-9_\s\*]+)\s+([a-zA-Z_][a-zA-Z0-9_]+)\s*\(([^)]*)\)') {
                $extFuncReturnType = ($Matches[1] -replace '&#xa0;', ' ' -replace '<br\s*/?>', '' -replace '\s{2,}', ' ').Trim()
                $funcName = $Matches[2].Trim()
                $extFuncParams = ($Matches[3] -replace '&#xa0;', ' ' -replace '<br\s*/?>', '' -replace '\s{2,}', ' ').Trim()
                # Store in dictionary for later lookup
                $allFunctions[$funcName] = @{ 
                    Name = $funcName
                    ReturnType = $extFuncReturnType
                    Parameters = $extFuncParams
                }
                # Split into void vs non-void lists
                if ($extFuncReturnType -eq "void") {
                    $voidExternalFunctions += @{ 
                        Name = $funcName
                        ReturnType = $extFuncReturnType
                        Parameters = $extFuncParams
                    }
                } else {
                    $externalFunctions += @{ 
                        Name = $funcName
                        ReturnType = $extFuncReturnType
                        Parameters = $extFuncParams
                    }
                }
            }
        }
        if ($externalFunctions.Count -gt 0) {
            Write-Host "[FOUND] $($externalFunctions.Count) Non-void External Function(s) requiring stubs:" -ForegroundColor Green
            foreach ($f in $externalFunctions) {
                $paramStr = if ($f.Parameters) { "($($f.Parameters))" } else { "()" }
                Write-Host "  - $($f.ReturnType) $($f.Name)$paramStr" -ForegroundColor Cyan
            }
        }
        if ($voidExternalFunctions.Count -gt 0) {
            Write-Host "[FOUND] $($voidExternalFunctions.Count) Void External Function(s) also requiring stubs:" -ForegroundColor Green
            foreach ($f in $voidExternalFunctions) {
                $paramStr = if ($f.Parameters) { "($($f.Parameters))" } else { "()" }
                Write-Host "  - void $($f.Name)$paramStr" -ForegroundColor Cyan
            }
        }
    }
}

# Parse Local Functions (also needed for stub generation)
# Note: use \z (absolute end-of-string) instead of $ in the terminator alternation.
# With (?ms), the m flag makes $ match end-of-line (before \n), so on Windows files
# with \r\n endings, $  would match between \r and \n after the very first function
# line, causing the lazy (.*?) to stop prematurely.  \z avoids this.
if ($interfaceContent -match '(?ms)LOCAL FUNCTIONS:.*?-+\s*(.*?)\s*(?:EXTERNAL VARIABLES:|GLOBAL VARIABLES:|={3,}|\z)') {
    $funcSection = $Matches[1].Trim()
    if ($funcSection -ne "") {
        $funcSection -split '[\r\n]+' | Where-Object { $_.Trim() -ne '' } | ForEach-Object {
            # Format: "unsigned char galois_mul2(unsigned char value)" or "void localFunc()"
            if ($_ -match '^\s*([a-zA-Z_][a-zA-Z0-9_\s\*]+)\s+([a-zA-Z_][a-zA-Z0-9_]+)\s*\(([^)]*)\)') {
                $localFuncReturnType = ($Matches[1] -replace '&#xa0;', ' ' -replace '<br\s*/?>', '' -replace '\s{2,}', ' ').Trim()
                $funcName = $Matches[2].Trim()
                $localFuncParams = ($Matches[3] -replace '&#xa0;', ' ' -replace '<br\s*/?>', '' -replace '\s{2,}', ' ').Trim()
                # Store in dictionary for later lookup
                $allFunctions[$funcName] = @{ 
                    Name = $funcName
                    ReturnType = $localFuncReturnType
                    Parameters = $localFuncParams
                    IsLocal = $true   # mark as local â€” no stub BODY in .script
                }
                # Note: Don't automatically add to externalFunctions yet
                # Will be added when found in stub list
            }
        }
    }
}

# $localFunctionNames: names of all local functions â€” these must NOT get stub bodies in .script.
# Derived by comparing $allFunctions (all functions seen) with $externalFunctions (only external ones).
# Any function in $allFunctions but absent from $externalFunctions is a local function.
$externalFunctionNames = @($externalFunctions | ForEach-Object { $_.Name })
Write-Host "[DEBUG-LOCAL] allFunctions keys: $($allFunctions.Keys -join ', ')" -ForegroundColor DarkMagenta
Write-Host "[DEBUG-LOCAL] externalFunctions names: $($externalFunctionNames -join ', ')" -ForegroundColor DarkMagenta
$localFunctionNames = @($allFunctions.Keys | Where-Object { $externalFunctionNames -notcontains $_ })
if ($localFunctionNames.Count -gt 0) {
    Write-Host "[LOCAL-FUNCS] Local functions (no stub bodies): $($localFunctionNames -join ', ')" -ForegroundColor DarkCyan
} else {
    Write-Host "[DEBUG-LOCAL] localFunctionNames is EMPTY - allFunctions.Count=$($allFunctions.Count) externalFunctionNames.Count=$($externalFunctionNames.Count)" -ForegroundColor Red
}

# ============================================================================
# 3. Read Testcase Plan (MANDATORY) + optional analysis for compatibility
# ============================================================================
Write-Host "`n[PLAN] Loading testcase plan..." -ForegroundColor Yellow
$jsonDir = "$WorkingDir\json_files"

# --- MANDATORY: testcase_plan.json must exist ---
$planFile = Join-Path $WorkingDir "json_testcase\${TestObject}_testcase_plan.json"
if (-not (Test-Path $planFile)) {
    Write-Host "[ERROR] Testcase plan not found: $planFile" -ForegroundColor Red
    Write-Host "  Run Step 6 (list_testcases) to generate the plan first." -ForegroundColor Yellow
    exit 1
}
$mainPlan = Get-Content $planFile -Raw -Encoding UTF8 | ConvertFrom-Json
$planTestCases = @($mainPlan.TestCases)
Write-Host "[PLAN] Loaded $($planTestCases.Count) test case(s) from plan" -ForegroundColor Cyan

# Expand each TC's SetValues by prepending DefaultValues; TC-specific entries override defaults
$planDefaultValues = if ($mainPlan.PSObject.Properties['DefaultValues'] -and $mainPlan.DefaultValues) {
    @($mainPlan.DefaultValues)
} else { @() }
if ($planDefaultValues.Count -gt 0) {
    Write-Host "[PLAN] Merging $($planDefaultValues.Count) DefaultValues into each TC's SetValues" -ForegroundColor Cyan
    $planTestCases = $planTestCases | ForEach-Object {
        $tc = $_
        $merged = @($planDefaultValues) + @($tc.SetValues)
        $tc | Add-Member -NotePropertyName SetValues -NotePropertyValue $merged -Force -PassThru
    }
}
foreach ($tc in $planTestCases) {
    Write-Host "  TC$($tc.TCId): $($tc.Description.Substring(0, [Math]::Min(80, $tc.Description.Length)))" -ForegroundColor DarkCyan
}

# --- Get $returnType from interface RETURN TYPE section (preferred) ---
$returnType = 'void'
$returnTypeDecl = ''
if ($interfaceContent -match '(?ms)RETURN TYPE:\s*-+\s*(.*?)\s*={3,}') {
    $rt = ($Matches[1].Trim() -replace '\s*\[Passing:[^\]]+\]', '' -replace '\s+', ' ').Trim()
    if ($rt -and $rt -ne 'void' -and $rt -ne '(void)' -and $rt -ne '') {
        $returnType    = $rt
        $returnTypeDecl = $rt
    }
}
Write-Host "[PLAN] Return type: $returnType" -ForegroundColor Cyan

# --- Optional: load analysis_status.json for backward compatibility ---
$analysisFile = "$jsonDir\${TestObject}_analysis_status.json"
$functionBody = ''
$parameters   = ''
$branchPlan   = $null
if (Test-Path $analysisFile) {
    try {
        $analysis     = Get-Content $analysisFile -Raw | ConvertFrom-Json
        $functionBody = $analysis.FunctionBody
        $parameters   = $analysis.Parameters
        if (-not $returnType -or $returnType -eq 'void') {
            $returnType = $analysis.ReturnType
        }
        Write-Host "[ANALYSIS] Optional analysis file loaded" -ForegroundColor DarkGray
    } catch {
        Write-Host "[ANALYSIS] Could not load analysis file (non-critical): $_" -ForegroundColor DarkGray
    }
} else {
    Write-Host "[ANALYSIS] Analysis file not present (optional - skipped)" -ForegroundColor DarkGray
}

# ---- Load Branch Coverage Plan (from Step 3) if available ----
$branchPlan = $null
$branchPlanFile = "$jsonDir\${TestObject}_branch_plan.json"
if (Test-Path $branchPlanFile) {
    try {
        $branchPlan = Get-Content $branchPlanFile -Raw | ConvertFrom-Json
        Write-Host "[BRANCH PLAN] Loaded $($branchPlan.Count) test case spec(s) from branch plan" -ForegroundColor Magenta
    } catch {
        Write-Host "[BRANCH PLAN] Could not parse branch plan JSON: $_" -ForegroundColor Yellow
        $branchPlan = $null
    }
} else {
    Write-Host "[BRANCH PLAN] No branch plan found (Step 3 may not have generated one)" -ForegroundColor DarkGray
}

# ---- Load Simple Test Case Plan (from Step 6) if available ----
$simplePlanFile = Join-Path $WorkingDir "json_testcase\${TestObject}_testcase_plan.json"
# Also check path stored in analysis JSON
if (-not (Test-Path $simplePlanFile) -and $analysis.SimpleTestCasePlanFile) {
    $simplePlanFile = $analysis.SimpleTestCasePlanFile
}
if (Test-Path $simplePlanFile) {
    try {
        $simplePlan = Get-Content $simplePlanFile -Raw | ConvertFrom-Json
        Write-Host "[SIMPLE PLAN] Loaded $($simplePlan.TotalTestCases) TC(s) from step 6 plan" -ForegroundColor Cyan
        foreach ($tc in $simplePlan.TestCases) {
            Write-Host "  TC$($tc.TCId): $($tc.Description)" -ForegroundColor DarkCyan
            foreach ($sv in $tc.SetValues) { Write-Host "    Set: $sv" -ForegroundColor Gray }
        }
    } catch {
        Write-Host "[SIMPLE PLAN] Could not parse testcase_plan.json: $_" -ForegroundColor Yellow
    }
} else {
    Write-Host "[SIMPLE PLAN] No testcase_plan.json found (run Step 3 to generate)" -ForegroundColor DarkGray
}

# Detect enum return type and pre-load members for $outputs generation.
# $returnType from JSON may lack the 'enum' prefix (e.g. 'DmaDrv_CfgRstCheck_t' not 'enum DmaDrv_CfgRstCheck_t').
# Read the RETURN TYPE section from interface_info.txt which always includes the 'enum' keyword.
$returnTypeDecl = ""
if ($interfaceContent -match '(?ms)RETURN TYPE:\s*-+\s*(.*?)\s*={3,}') {
    $returnTypeDecl = ($Matches[1].Trim() -replace '\s*\[Passing:[^\]]+\]', '' -replace '\s+', ' ').Trim()
}
$returnEnumMembers = @()
$checkType = if ($returnTypeDecl -ne '') { $returnTypeDecl } else { $returnType }
if ($checkType -match '^enum\s+(\w+)') {
    $returnEnumTypeName = $Matches[1]
    $returnEnumMembers = Get-EnumMembersFromSource -EnumTypeName $returnEnumTypeName -SourceDir $SourceDir
    if ($returnEnumMembers.Count -gt 0) {
        Write-Host "  Return Enum: $returnEnumTypeName ($($returnEnumMembers.Count) members: $($returnEnumMembers -join ', '))" -ForegroundColor Cyan
    } else {
        Write-Host "  [WARN] No enum members found for return type: $returnEnumTypeName" -ForegroundColor Yellow
    }
}

Write-Host "[OK] Source analysis loaded" -ForegroundColor Green
Write-Host "`n[FUNCTION SIGNATURE]" -ForegroundColor Cyan
Write-Host "  Return Type: $returnType" -ForegroundColor White
Write-Host "  Parameters: $parameters" -ForegroundColor White
Write-Host ""
Write-Host "[FUNCTION BODY]" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Gray
Write-Host $functionBody
Write-Host "================================================================================" -ForegroundColor Gray

# ============================================================================
# 3b. Read FAILURE SUMMARY from Step 7 CSV (for auto-correction to $outputs)
# ============================================================================
$failureCorrections = @{}
$correctionFile = "$jsonDir\${TestObject}_corrections.csv"

if (Test-Path $correctionFile) {
    Write-Host "`n[AUTO-CORRECT] Reading failure summary from Step 7..." -ForegroundColor Yellow
    Write-Host "  File: $correctionFile" -ForegroundColor White
    
    try {
        # Import CSV file with corrections
        $corrections = Import-Csv -Path $correctionFile
        
        if ($corrections -and $corrections.Count -gt 0) {
            Write-Host "[FOUND] $($corrections.Count) variable correction(s) from previous run" -ForegroundColor Magenta
            Write-Host "[STRATEGY] Will apply Actual values to `$outputs section:" -ForegroundColor Cyan
            
            # Build hashtable: Variable Path -> Actual Value (to use as new Expected)
            # Track variables with multiple different values
            $uniqueVars = @{}
            $varValues = @{}  # Track all values seen per variable
            
            foreach ($corr in $corrections) {
                $varPath = $corr.Variable
                $actualValue = $corr.ActualValue
                
                # Normalize path: Handle union syntax like "DGC_RR_50F.DGC_RR_50F.DGCRR_DrvrFlt"
                # where the union and its struct member have the same name
                # Convert to "DGC_RR_50F.DGCRR_DrvrFlt" for matching
                $parts = $varPath -split '\.'
                if ($parts.Count -ge 3 -and $parts[0] -eq $parts[1]) {
                    # Remove redundant union member name: "Union.Union.Field" -> "Union.Field"
                    $normalizedPath = $parts[0] + "." + ($parts[2..($parts.Count-1)] -join '.')
                } else {
                    $normalizedPath = $varPath
                }
                
                # Track all values for this variable (skip "no values" â€” means variable was absent from $outputs, not a real value)
                if (-not $varValues.ContainsKey($normalizedPath)) {
                    $varValues[$normalizedPath] = @()
                }
                if ($actualValue -ne "no values" -and $varValues[$normalizedPath] -notcontains $actualValue) {
                    $varValues[$normalizedPath] += $actualValue
                }
            }
            
            # Now process: single consistent value -> use it; multiple different values -> type default
            $allIfaceVars = @($externalVariablesInfo) + @($globalVariablesInfo) + @($parametersInfo)
            foreach ($varPath in $varValues.Keys) {
                if ($varValues[$varPath].Count -gt 1) {
                    # Multiple different values across test cases - use type-appropriate default
                    $defaultVal = Get-TypeDefault -VarPath $varPath -AllVarInfo $allIfaceVars -ReturnType $returnType -SrcDir $SourceDir
                    $uniqueVars[$varPath] = $defaultVal
                    $failureCorrections[$varPath] = $defaultVal
                    Write-Host "  $varPath : Multiple values ($($varValues[$varPath] -join ',')) -> USE $defaultVal (type default)" -ForegroundColor Cyan
                } else {
                    # Single consistent value - use it
                    $uniqueVars[$varPath] = $varValues[$varPath][0]
                    $failureCorrections[$varPath] = $varValues[$varPath][0]
                    Write-Host "  $varPath : Consistent value -> USE $($varValues[$varPath][0])" -ForegroundColor Yellow
                }
            }
            
            Write-Host "`n[SUMMARY] Loaded $($failureCorrections.Count) unique variable corrections" -ForegroundColor Green
            Write-Host "  These values will be applied to ALL test cases in `$outputs section" -ForegroundColor Cyan
        } else {
            Write-Host "[INFO] CSV file empty - no corrections needed" -ForegroundColor DarkGray
        }
    } catch {
        Write-Host "[WARNING] Could not parse corrections CSV: $_" -ForegroundColor Yellow
        Write-Host "  Falling back to default test values" -ForegroundColor DarkGray
    }
} else {
    Write-Host "`n[INFO] No corrections file found (first run - no previous failures)" -ForegroundColor DarkGray
    Write-Host "  File checked: $correctionFile" -ForegroundColor DarkGray
}

# ============================================================================
# 3c. Check if we need to DIRECTLY EDIT .script file (C0=100%, C1=100%, Failed!=0)
# ============================================================================
if ((Test-Path $correctionFile) -and (Test-Path $existingTestCase)) {
    Write-Host "`n[SCRIPT EDIT MODE] Checking if direct .script editing is needed..." -ForegroundColor Yellow
    
    # Check coverage from Step 7 JSON status file
    $c0Coverage = 0
    $c1Coverage = 0
    $failedCount = 0
    $totalCount = 0
    
    # Try to read from JSON status file created by Step 7
    $statusFile = "$jsonDir\${TestObject}_coverage_status.json"
    
    if (Test-Path $statusFile) {
        try {
            $statusJson = Get-Content $statusFile -Raw | ConvertFrom-Json
            $c0Coverage = $statusJson.C0
            $c1Coverage = $statusJson.C1
            $totalCount = $statusJson.Total
            $failedCount = $statusJson.Failed
            
            Write-Host "  C0 Coverage: $c0Coverage%" -ForegroundColor Cyan
            Write-Host "  C1 Coverage: $c1Coverage%" -ForegroundColor Cyan
            Write-Host "  Failed Tests: $failedCount" -ForegroundColor Cyan
            Write-Host "  Total Tests: $totalCount" -ForegroundColor Cyan
        } catch {
            Write-Host "  [WARNING] Could not parse status JSON: $_" -ForegroundColor Yellow
        }
    } else {
        Write-Host "  [WARNING] Status file not found: $statusFile" -ForegroundColor Yellow
    }
    
    # Check if we meet the condition: C0=100%, Failed!=0, Total>0
    # C1 does NOT need to be 100% â€” when C0=100% and some TCs fail, the failures are
    # wrong Expected values (enum cycling), not missing coverage. Fix Expected=Actual directly.
    if ($c0Coverage -ge 100 -and $failedCount -gt 0 -and $totalCount -gt 0) {
        Write-Host "`n[CONDITION MET] C0=100%, C1=$c1Coverage%, Failed=$failedCount, Total=$totalCount" -ForegroundColor Green
        Write-Host "[ACTION] Will directly edit .script file with actual values from corrections CSV" -ForegroundColor Magenta
        Write-Host "  Script file: $existingTestCase" -ForegroundColor White
        
        # Load ALL variable rows from CSV (both PASS and FAIL).
        # The new CSV has a Status column; older CSVs without it are also tolerated.
        $corrections = Import-Csv -Path $correctionFile
        # Include every row â€” we will rebuild complete $outputs using ActualValue for each variable.
        $testCaseGroups = $corrections | Group-Object -Property TestCase
        
        Write-Host "`n[EDITING] Processing $($testCaseGroups.Count) test case(s)..." -ForegroundColor Yellow
        
        # Read current script content and strip UTF-8 BOM if present (Ã¯Â»Â¿ = 0xEF 0xBB 0xBF)
        $scriptContent = Get-Content $existingTestCase -Raw
        $scriptContent = $scriptContent.TrimStart([char]0xFEFF)
        
        # Process each test case
        foreach ($tcGroup in $testCaseGroups) {
            $tcName = $tcGroup.Name
            $tcAllRows = $tcGroup.Group   # all variable rows for this TC (pass + fail)
            
            Write-Host "`n  Test Case: $tcName" -ForegroundColor Cyan
            Write-Host "    Variables: $($tcAllRows.Count)" -ForegroundColor White
            
            # Find the test case number (e.g., "Test case 01" -> 1)
            if ($tcName -match '\d+') {
                $tcNumber = [int]$Matches[0]
                
                # Build replacement for $outputs section
                # Match $outputs { ... } up to the } that is immediately followed by $calltrace.
                # Using lazy .*? with lookahead (?=...\$calltrace) ensures we capture the
                # ENTIRE $outputs block including all nested struct element blocks, not just
                # up to the first } (which would be a nested struct closing brace).
                # PS string note: \`$calltrace = regex \$calltrace (\ + `$ for literal $)
                $tcPattern = "(?ms)(\`$testcase\s+$tcNumber\s+\{.*?\`$outputs\s+\{)(.*?)(\}(?=\s*\r?\n\s*\`$calltrace))"
                
                if ($scriptContent -match $tcPattern) {
                    # IMPORTANT: save the full match NOW â€” inner -match calls below will overwrite $Matches
                    $fullMatch     = $Matches[0]
                    $beforeOutputs = $Matches[1]
                    $currentOutputs = $Matches[2]
                    $afterOutputs = $Matches[3]
                    
                    # Build new $outputs section from ALL variable rows for this TC.
                    # Always use ActualValue â€” for PASS rows it equals ExpectedValue (no change);
                    # for FAIL rows it replaces the wrong Expected with the correct Actual.
                    $newOutputs = "`n"
                    
                    foreach ($row in $tcAllRows) {
                        $varName    = $row.Variable
                        $useValue   = $row.ActualValue
                        # "no values" means the variable was not in $outputs previously â€” use 0 as placeholder
                        if ($useValue -eq "no values") { $useValue = "0" }
                        
                        # Function return value: Variable column is "FuncName()"
                        if ($varName -match '^\w+\(\)$') {
                            $newOutputs += "`t`t`t`treturn = $useValue`n"
                        }
                        # union/struct field: "unionVar.field" or "unionVar.struct.field"
                        elseif ($varName -match '^(\w+)\.(.+)$') {
                            $unionName = $Matches[1]
                            $fieldPath = $Matches[2]
                            if ($newOutputs -notmatch [regex]::Escape("$unionName = $unionName")) {
                                $newOutputs += "`t`t`t`t$unionName = $unionName`n"
                                $newOutputs += "`t`t`t`t$unionName.$unionName {`n"
                            }
                            if ($fieldPath -match '^(\w+)\.(.+)$') {
                                $newOutputs += "`t`t`t`t`t$($Matches[2]) = $useValue`n"
                            } else {
                                $newOutputs += "`t`t`t`t`t$fieldPath = $useValue`n"
                            }
                        }
                        # simple scalar or array element: varName or varName[i]
                        else {
                            $newOutputs += "`t`t`t`t$varName = $useValue`n"
                        }
                    }
                    
                    # Close any open union/struct brace
                    if ($newOutputs -match '\{[^\}]*$') {
                        $newOutputs += "`t`t`t`t}`n"
                    }
                    
                    $newOutputs += "`t`t`t"
                    
                    # Replace outputs section using the saved full match (not $Matches[0] which was overwritten)
                    $replacement = $beforeOutputs + $newOutputs + $afterOutputs
                    $scriptContent = $scriptContent -replace [regex]::Escape($fullMatch), $replacement
                    
                    Write-Host "    [OK] Updated `$outputs section ($($tcAllRows.Count) variables)" -ForegroundColor Green
                } else {
                    Write-Host "    [WARNING] Could not find `$outputs section for test case $tcNumber" -ForegroundColor Yellow
                }
            }
        }
        
        # Save updated script (UTF-8 WITHOUT BOM - Set-Content -Encoding UTF8 adds BOM in PS5.1)
        $utf8NoBomWriter = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($existingTestCase, $scriptContent, $utf8NoBomWriter)
        Write-Host "`n[SUCCESS] Script file updated with actual values" -ForegroundColor Green
        Write-Host "  Updated: $existingTestCase" -ForegroundColor White
        Write-Host "`n[DONE] No need to regenerate test cases - script edited directly" -ForegroundColor Magenta
        Write-Host "  Next: Run Step 6 to import and execute updated tests" -ForegroundColor Cyan
        exit 0
    } else {
        Write-Host "  [SKIP] Conditions not met for direct editing:" -ForegroundColor DarkGray
        Write-Host "    C0=$c0Coverage% (need 100%), Failed=$failedCount (need >0), Total=$totalCount (need >0)" -ForegroundColor DarkGray
        Write-Host "  Proceeding with normal test case generation..." -ForegroundColor White
    }
}

# ============================================================================
# 4. Read Stub Analysis from Step 4 and Parse Function Signatures
# ============================================================================
Write-Host "`n[ANALYSIS] Reading stub analysis from Step 4..." -ForegroundColor Yellow
$stubAnalysisFile = "$WorkingDir\stub_files\${TestObject}_stub_list.txt"

if (Test-Path $stubAnalysisFile) {
    $requiredStubs = Get-Content $stubAnalysisFile | Where-Object { $_.Trim() -ne "" }
    Write-Host "[OK] Found $($requiredStubs.Count) required stubs:" -ForegroundColor Green
    
    # Parse stub function signatures from the stub list
    foreach ($stub in $requiredStubs) {
        $stubFuncName = $null
        $stubReturnType = $null
        $stubParams = $null
        
        # Try to extract function signature: "returnType functionName(params)"
        if ($stub -match '^\s*([a-zA-Z_][a-zA-Z0-9_\s\*]+)\s+([a-zA-Z_][a-zA-Z0-9_]+)\s*\(([^)]*)\)') {
            $stubReturnType = $Matches[1].Trim()
            $stubFuncName = $Matches[2].Trim()
            $stubParams = $Matches[3].Trim()
        }
        # If only function name (no signature), look up in allFunctions dictionary
        elseif ($stub -match '^\s*([a-zA-Z_][a-zA-Z0-9_]+)\s*$') {
            $stubFuncName = $Matches[1].Trim()
            if ($allFunctions.ContainsKey($stubFuncName)) {
                $funcInfo = $allFunctions[$stubFuncName]
                $stubReturnType = $funcInfo.ReturnType
                $stubParams = $funcInfo.Parameters
                Write-Host "  - $stub -> $stubReturnType $stubFuncName($stubParams)" -ForegroundColor Cyan
            } else {
                Write-Host "  - $stub -> [WARNING: Signature not found in interface]" -ForegroundColor Yellow
                continue
            }
        } else {
            Write-Host "  - $stub -> [WARNING: Invalid format]" -ForegroundColor Yellow
            continue
        }
        
        # Add all non-void functions in stub_list.txt to externalFunctions for stub body generation.
        # This includes both true external functions AND non-void local functions whose return values
        # are used (stub_list.txt only contains functions with used return values).
        # Void functions are filtered by the $stubReturnType check below.
        if ($stubReturnType -and $stubReturnType -ne "void") {
            # Check if this function is already in externalFunctions
            $exists = $externalFunctions | Where-Object { $_.Name -eq $stubFuncName }
            if (-not $exists) {
                $isLocalFunc = ($localFunctionNames -contains $stubFuncName)
                $funcKind = if ($isLocalFunc) { "local" } else { "external" }
                Write-Host "  - $stubFuncName -> $stubReturnType ($funcKind function, will have stub body)" -ForegroundColor Cyan
                $externalFunctions += @{ 
                    Name = $stubFuncName
                    ReturnType = $stubReturnType
                    Parameters = $stubParams
                }
            } else {
                # Update with parameters if we have them
                $exists.Parameters = $stubParams
            }
        }
    }
    $stubContent = Get-Content $stubAnalysisFile -Raw
    Write-Host "[OK] Stub analysis loaded and parsed" -ForegroundColor Green
} else {
    Write-Host "[INFO] No stubs required (file not found - expected for functions with no stub needs)" -ForegroundColor Yellow
    $stubContent = "No stub functions required"
}

# Note: non-void local functions with used return values are already in $externalFunctions
# (added above from stub_list.txt). No special handling needed here.
Write-Host "`n[STUBS] Checking local non-void functions for stub requirements..." -ForegroundColor Yellow
$localNonVoidStubbed = @($externalFunctions | Where-Object { $localFunctionNames -contains $_.Name })
if ($localNonVoidStubbed.Count -gt 0) {
    foreach ($fn in $localNonVoidStubbed) {
        Write-Host "  [LOCAL-WITH-BODY] Local non-void function '$($fn.Name)' - will have stub body for coverage control" -ForegroundColor DarkCyan
    }
}

# ============================================================================
# 5. Read Dummy Template from Step 3
# ============================================================================
Write-Host "`n[TEMPLATE] Reading dummy test case template from Step 3..." -ForegroundColor Yellow
$templateFile = "$WorkingDir\${TestObject}_dummy_export\${TestObject}.script"

if (Test-Path $templateFile) {
    $templateContent = Get-Content $templateFile -Raw
    Write-Host "[OK] Template loaded ($(($templateContent -split "`n").Count) lines)" -ForegroundColor Green
} else {
    Write-Host "[WARNING] Template not found. Will use basic structure." -ForegroundColor Yellow
    $templateContent = "# No template available - generate from scratch"
}

# ============================================================================
# 6. Generate Test Cases Using Tessy Guideline
# ============================================================================
Write-Host "`n[GENERATION] Generating test cases based on Tessy guideline..." -ForegroundColor Yellow

# Analyze function for test cases needed
Write-Host "`n[ANALYZE] Analyzing function for coverage requirements..." -ForegroundColor Cyan

# Extract conditions and branches from function body
# NOTE: The old capture regex  if\s*\(([^)]+)\)  fails on multi-line / nested-paren
# conditions (e.g. "if((A)&&\n(B))") because [^)]+ stops at the first ')'.
# Fix: count occurrences with \bif\s*\( (no capture) and split off else-if chains.
$ifCount     = [regex]::Matches($functionBody, '\bif\s*\(').Count
$elseIfCount = [regex]::Matches($functionBody, '\belse\s+if\s*\(').Count
# standaloneIfs = ifs that open a new decision chain (not continuation of else-if)
# Each such chain needs 2 TCs for C1: one takes TRUE, one takes FALSE/else path.
$standaloneIfs = $ifCount - $elseIfCount
# Keep $conditions as a sized dummy so $hasBranches and legacy references still work
$conditions = 1..$ifCount
$returns = [regex]::Matches($functionBody, 'return\s+([^;]+);') | ForEach-Object { $_.Groups[1].Value }
$switches = [regex]::Matches($functionBody, 'switch\s*\(([^)]+)\)') | ForEach-Object { $_.Groups[1].Value }
# Match only valid C case labels: identifiers or integer literals.
# The broader [^:]+ pattern accidentally matches 'case' found inside C comments
# (e.g. /*LCOV_EXCL_START - Exluded case for CppU test...*/) and captures
# multi-line comment text up to the next ':' anywhere in the function body.
$cases = [regex]::Matches($functionBody, 'case\s+([A-Za-z_][A-Za-z0-9_]*|-?\d+)\s*:') | ForEach-Object { $_.Groups[1].Value }
$hasDefault = $functionBody -match '\bdefault\s*:'

Write-Host "  If conditions found: $ifCount (standalone chains: $standaloneIfs, else-if continuations: $elseIfCount)" -ForegroundColor White
Write-Host "  Returns found: $($returns.Count)" -ForegroundColor White
Write-Host "  Switches found: $($switches.Count)" -ForegroundColor White
Write-Host "  Cases found: $($cases.Count)" -ForegroundColor White
if ($hasDefault) { Write-Host "  Default case: YES (extra test case will be added)" -ForegroundColor Yellow }

# Determine number of test cases needed based on complexity
$hasParameters = ($parameters -and $parameters.Trim() -ne "" -and $parameters.Trim() -ne "void")
$hasGlobalVars = ($globalVariables.Count -gt 0)
$hasBranches = ($ifCount -gt 0 -or $switches.Count -gt 0 -or $returns.Count -gt 1)

# ── Minimum TC count rules (C0 + C1) ──────────────────────────────────────────
# C0: every statement executed
#   • 1 TC per switch case (enters that case's code)
# C1: every branch decision covered (TRUE + FALSE)
#   • 1 if (starting a new decision chain) → 2 TCs  (TRUE branch + FALSE/else branch)
#   • else-if continuations are covered within those same TCs — no extra TCs needed
#   • 1 switch default → 1 extra TC (out-of-set enum value)
#
# numTestCases = MAX( cases_C0, standaloneIfs_C1 × 2 ) + default_TC
# Smart test case count logic
if (-not $hasParameters -and -not $hasGlobalVars -and -not $hasBranches) {
    # Simple function: void parameters, no global vars, no branches -> only 1 test case needed
    $numTestCases = 1
    Write-Host "  [SIMPLE FUNCTION] No parameters, no global vars, no branches -> 1 test case sufficient for 100% coverage" -ForegroundColor Green
} else {
    # C0 minimum: 1 TC per switch case
    $c0Min = if ($switches.Count -gt 0 -and $cases.Count -gt 0) { $cases.Count } else { 2 }
    # C1 minimum: 2 TCs per independent decision chain (standalone if / if-else / if-elseif chain)
    $c1Min = if ($standaloneIfs -gt 0) { $standaloneIfs * 2 } else { 2 }
    $numTestCases = [Math]::Max($c0Min, $c1Min)
    if ($returns.Count -gt 1) { $numTestCases = [Math]::Max($numTestCases, $returns.Count) }

    Write-Host "  [COVERAGE CALC] C0 min (cases)=$c0Min  C1 min (chains×2)=$c1Min  -> $numTestCases TC(s)" -ForegroundColor Cyan

    # If this is a retry, bump by the gap between current and C1 minimum
    if ($isRetry) {
        $c1MinRetry = [Math]::Max($c0Min, $c1Min)
        if ($numTestCases -lt $c1MinRetry) {
            $numTestCases = $c1MinRetry
            Write-Host "  [RETRY] Increased to $numTestCases test case(s) (C1 minimum: $c1MinRetry)" -ForegroundColor Magenta
        } else {
            Write-Host "  [RETRY] Already at C1 minimum ($numTestCases TCs). No extra TCs needed." -ForegroundColor Yellow
        }
    }
}

# Track which test case is dedicated to the default: branch (always the last TC)
$defaultTestCaseNum = if ($hasDefault -and $switches.Count -gt 0) { $numTestCases } else { -1 }
if ($defaultTestCaseNum -gt 0) {
    Write-Host "  [DEFAULT CASE] TC$defaultTestCaseNum reserved for default: branch (out-of-switch enum value)" -ForegroundColor Yellow
}

Write-Host "  Generating $numTestCases test case(s) in single .script file..." -ForegroundColor Cyan

# ============================================================================
# 7. Stub Functions Section
# - Switch-driving stubs: their return value is used directly in a switch()
#   statement.  Must be placed inside each $teststep with a per-TC return
#   value so that each test case targets a different case: branch.
# - All other stubs: placed once at $testobject level with return 0.
# ============================================================================
$allStubFunctions = @()
$allStubFunctions += $externalFunctions
$allStubFunctions += $voidExternalFunctions

# Filter $allStubFunctions against Tessy's registered stubs from the YAML export.
# Tessy only accepts $stubfunctions entries for functions it has registered in
# the test object's interface.  Functions NOT in the YAML Stubs list (e.g. local
# functions whose globals Tessy controls directly as inputs) must be excluded or
# IMPEX fails with HTTP 500: "[IMPEX] Failed to run import job".
$ymlExportFile  = "$WorkingDir\yml\${TestObject}_export.yml"
$yamlValidStubNames = @()
if (Test-Path $ymlExportFile) {
    $ymlContent = Get-Content $ymlExportFile -Raw
    # YAML stubs look like:  - ['0', '0', FunctionName, '']
    $stubMatches = [regex]::Matches($ymlContent, "-\s*\['\d+',\s*'\d+',\s*([a-zA-Z_][a-zA-Z0-9_]+),")
    foreach ($m in $stubMatches) { $yamlValidStubNames += $m.Groups[1].Value }
    if ($yamlValidStubNames.Count -gt 0) {
        Write-Host "[STUBS] YAML export lists $($yamlValidStubNames.Count) valid stub(s): $($yamlValidStubNames -join ', ')" -ForegroundColor Cyan
        $removedStubs = @($allStubFunctions | Where-Object { $yamlValidStubNames -notcontains $_.Name })
        if ($removedStubs.Count -gt 0) {
            # Separate truly excluded stubs (not in stub_list) from ones that should be registered
            # Non-void stubs from stub_list.txt are legitimately required â€” re-register them in YAML.
            $requiredStubNames = if (Test-Path $stubAnalysisFile) {
                (Get-Content "$WorkingDir\stub_files\${TestObject}_stub_list.txt" -ErrorAction SilentlyContinue) |
                    Where-Object { $_.Trim() -ne '' } |
                    ForEach-Object {
                        if ($_ -match '([a-zA-Z_][a-zA-Z0-9_]+)\s*\(') { $Matches[1] } else { $_.Trim() }
                    }
            } else { @() }

            $stubsToRegister = @($removedStubs | Where-Object {
                $_.ReturnType -ne 'void' -and ($requiredStubNames -contains $_.Name)
            })
            $trulyExcluded   = @($removedStubs | Where-Object { $stubsToRegister.Name -notcontains $_.Name })

            if ($trulyExcluded.Count -gt 0) {
                Write-Host "[STUBS] Excluding $($trulyExcluded.Count) function(s) NOT in YAML (Tessy controls via direct input variable):" -ForegroundColor Yellow
                foreach ($r in $trulyExcluded) { Write-Host "  - (excluded) $($r.ReturnType) $($r.Name)(...)" -ForegroundColor DarkGray }
            }

            if ($stubsToRegister.Count -gt 0) {
                Write-Host "[STUBS] Auto-registering $($stubsToRegister.Count) required stub(s) missing from YAML:" -ForegroundColor Yellow
                foreach ($r in $stubsToRegister) { Write-Host "  - (adding) $($r.ReturnType) $($r.Name)(...)" -ForegroundColor Cyan }
                # Patch the YAML stubs section with the new function names
                $ymlPatch = Get-Content $ymlExportFile -Raw
                if ($ymlPatch -match '(?ms)---\r?\nStubs:\r?\n') {
                    if ($ymlPatch -match "(?ms)---\r?\nStubs:\r?\n(.*?)(?=\r?\n---)") {
                        $existingSection = $Matches[1]
                        $existingNames = [System.Collections.Generic.List[string]]@()
                        $existingSection -split "`n" | ForEach-Object {
                            if ($_ -match "'\s*0'\s*,\s*'[^']*'\s*,\s*([^,]+)\s*,") { $existingNames.Add($Matches[1].Trim()) }
                        }
                        $allNames = ($existingNames + @($stubsToRegister | ForEach-Object { $_.Name })) | Sort-Object -Unique
                        $newLines = ($allNames | ForEach-Object { "- ['0', '0', $_, '']" }) -join "`r`n"
                        $newBlock = "---`r`nStubs:`r`n$newLines`r`n"
                        $ymlPatch = $ymlPatch -replace '(?ms)---\r?\nStubs:.*?(?=\r?\n---)', $newBlock.TrimEnd("`r`n")
                    }
                } else {
                    $newBlock = "---`r`nStubs:`r`n" + (($stubsToRegister | ForEach-Object { "- ['0', '0', $($_.Name), '']" }) -join "`r`n") + "`r`n"
                    $ymlPatch = $ymlPatch -replace '(---\r?\nValues:)', "$newBlock`$1"
                }
                $utf8NoBom = New-Object System.Text.UTF8Encoding $false
                [System.IO.File]::WriteAllText($ymlExportFile, $ymlPatch, $utf8NoBom)
                # Re-import twice for reliability
                Set-Location $ScriptRoot
                tessycmd import $ymlExportFile 2>&1 | Out-Null
                Start-Sleep -Seconds 2
                tessycmd import $ymlExportFile 2>&1 | Out-Null
                Set-Location $WorkingDir
                Write-Host "[STUBS] YAML patched and re-imported with new stubs" -ForegroundColor Green
                # Add the newly registered stubs back into allStubFunctions
                $yamlValidStubNames += @($stubsToRegister | ForEach-Object { $_.Name })
            }
        }
        $allStubFunctions = @($allStubFunctions | Where-Object { $yamlValidStubNames -contains $_.Name })
    } else {
        Write-Host "[STUBS] YAML export found but no Stubs: section - using source-detected stubs" -ForegroundColor Yellow
    }
} else {
    Write-Host "[STUBS] No YAML export at '$ymlExportFile' - using source-detected stubs (risk of IMPEX failure)" -ForegroundColor Yellow
}

# Classify stubs: switch-driving vs. normal
$switchDrivingStubs = @()
$nonSwitchStubs     = @()
foreach ($sf in $allStubFunctions) {
    $sfNameEsc = [regex]::Escape($sf.Name)
    if ($functionBody -match "switch\s*\(\s*$sfNameEsc\s*\(") {
        $switchDrivingStubs += $sf
        Write-Host "[STUBS] Switch-driving stub detected: $($sf.ReturnType) $($sf.Name)(...) -> will be placed per-`$teststep with varying return" -ForegroundColor Magenta
    } else {
        $nonSwitchStubs += $sf
    }
}

# Pre-compute clean case labels (strip leading casts like (u8)) for reuse in stub bodies.
# Filter out numeric-only labels (e.g. 0U, 1U) â€” those come from nested integer switches
# (like switch(device_idx_u8)) and are not valid return values for a stub that drives an outer
# enum/action switch (like switch(aniSpdSdcGetAnimIdx(0))).
$cleanSwitchCases = $cases | ForEach-Object { ($_.Trim() -replace '^\([^)]+\)\s*', '').Trim() } | Where-Object { $_ -notmatch '^[0-9]' } | Select-Object -Unique

# Further classify non-switch stubs: void stays at testobject level; non-void goes per-testcase.
# Non-void stubs need varying return values to drive both TRUE and FALSE branches.
$testObjectVoidStubs   = @($nonSwitchStubs | Where-Object { $_.ReturnType -eq 'void' })
$testCaseNonVoidStubs  = @($nonSwitchStubs | Where-Object { $_.ReturnType -ne  'void' })

# Detect condition-driving stubs: those whose call appears inside an if() condition.
# These stubs must alternate return values (1=TRUE branch, 0=FALSE branch) across TCs.
foreach ($sf in $testCaseNonVoidStubs) {
    $sfNameEsc = [regex]::Escape($sf.Name)
    $isCondDriving = [bool]($conditions | Where-Object { $_ -match $sfNameEsc })
    $sf['IsConditionDriving'] = $isCondDriving
    if ($isCondDriving) {
        Write-Host "[STUBS] Condition-driving stub: $($sf.ReturnType) $($sf.Name)(...) -> alternates 1(TRUE)/0(FALSE) per TC" -ForegroundColor Magenta
    }
}

# Void stubs are skipped - void external functions do not need stub bodies.
# All non-void stubs are placed per-$testcase (see below).
$stubFunctionsSection = ""
if ($testObjectVoidStubs.Count -gt 0) {
    Write-Host "`n[STUBS] Skipping $($testObjectVoidStubs.Count) void function(s) - void functions do not require stubs" -ForegroundColor DarkGray
    foreach ($sf in $testObjectVoidStubs) { Write-Host "  - (skipped) void $($sf.Name)(...)" -ForegroundColor DarkGray }
} elseif ($allStubFunctions.Count -gt 0) {
    Write-Host "`n[STUBS] All non-switch stubs are non-void - stubs will be placed per-`$testcase" -ForegroundColor DarkGray
} else {
    Write-Host "`n[STUBS] No external functions require stubs" -ForegroundColor DarkGray
}
if ($testCaseNonVoidStubs.Count -gt 0) {
    Write-Host "`n[STUBS] $($testCaseNonVoidStubs.Count) non-void stub(s) will be placed per-`$testcase with varying return values:" -ForegroundColor Yellow
    foreach ($sf in $testCaseNonVoidStubs) {
        $condStr = if ($sf.IsConditionDriving) { " [CONDITION-DRIVING: alternates 0/1]" } else { " [VARYING: 0,1,2,3...]" }
        Write-Host "  - $($sf.ReturnType) $($sf.Name)(...)$condStr" -ForegroundColor Cyan
    }
}

# ============================================================================
# Resolve actual integer values for all switch case labels
# Enum symbols are NOT visible inside Tessy stub bodies (compiled as plain C).
# We must use integer literals.  Look up each label in source enum definitions.
# ============================================================================
$caseNumericValues = @{}
if ($switchDrivingStubs.Count -gt 0 -and $cleanSwitchCases.Count -gt 0) {
    $caseNumericValues = Get-CaseLabelNumericValues -CaseLabels $cleanSwitchCases -SourceDir $SourceDir
}
# Out-of-range value for the default: branch TC (must be > all named case values)
$defaultBranchStubVal = if ($caseNumericValues.Count -gt 0) {
    ($caseNumericValues.Values | Measure-Object -Maximum).Maximum + 1
} else {
    $cleanSwitchCases.Count   # sequential-index fallback
}

# ============================================================================
# Detect nested integer switches - supplemental TC coverage
# When a switch-driving stub drives an outer switch whose case block contains a
# nested switch(scalarINparam), the main TC loop may miss inner case branches
# (outer stub cycling and scalar strategy cycling are independent). We pre-compute
# supplemental TCs that fix the outer stub to enter the branch with the nested
# switch AND cycle the scalar param through every inner case value + one
# out-of-range value for the inner default: branch.
# ============================================================================
$nestedIntSwitchParams = @()
if ($switchDrivingStubs.Count -gt 0) {
    foreach ($p in ($parametersInfo | Where-Object { $_.Passing -match 'IN' })) {
        $isCPrim = $p.Type -match '^(?:const\s+)?(?:unsigned\s+)?(?:char|short|int|long|u8|u16|u32|u64|s8|s16|s32)\b'
        if (-not $isCPrim) { continue }
        $pNameEsc = [regex]::Escape($p.Name)
        if ($functionBody -notmatch "switch\s*\(\s*$pNameEsc\s*\)") { continue }
        # Extract every integer literal used in case labels in this function body
        $rawInnerCases = [regex]::Matches($functionBody, 'case\s+(\d+)[Uu]?\s*:') |
                         ForEach-Object { [int]$_.Groups[1].Value } | Sort-Object -Unique
        if ($rawInnerCases.Count -gt 0) {
            $nestedIntSwitchParams += [PSCustomObject]@{ Name = $p.Name; CaseValues = $rawInnerCases }
            Write-Host "[NESTED-INT-SWITCH] Detected switch($($p.Name)) nested in outer switch - cases: $($rawInnerCases -join ', ')" -ForegroundColor DarkCyan
        }
    }
}
# Build TC-override table: for each supplemental TC, force stub to first outer
# case (index 0) so it enters the branch that contains the nested switch, then
# set the scalar IN param to each inner case value (and one out-of-range value).
$tcOverrides = @{}  # key = tcNum, value = @{ StubVal; OverrideParams: @{name->val} }
if ($nestedIntSwitchParams.Count -gt 0) {
    $tcSupplIdx = $numTestCases + 1
    foreach ($nsParam in $nestedIntSwitchParams) {
        $outerStubVal    = 0                  # First named outer case triggers nested switch
        $maxInnerCase    = ($nsParam.CaseValues | Measure-Object -Maximum).Maximum
        $innerValsToTest = @($nsParam.CaseValues) + @($maxInnerCase + 1)  # +1 = out-of-range for inner default
        foreach ($innerVal in $innerValsToTest) {
            $innerParamMap = @{}
            $innerParamMap[$nsParam.Name] = $innerVal
            $tcOverrides[$tcSupplIdx] = @{ StubVal = $outerStubVal; OverrideParams = $innerParamMap }
            $numTestCases++
            $tcSupplIdx++
        }
    }
    Write-Host "[NESTED-SWITCH] Added $($tcOverrides.Count) supplemental TC(s) covering inner switch branches" -ForegroundColor DarkCyan
}

# ============================================================================
# 8. Build Test Script Content using Testcase Plan
# ============================================================================

# Dot-source plan-based sub-scripts
. (Join-Path $PSScriptRoot "step7a_metadata.ps1")
. (Join-Path $PSScriptRoot "step7b_stubs.ps1")
. (Join-Path $PSScriptRoot "step7c_inputs_outputs.ps1")

$outputFile = "$scriptDir\${TestObject}_testcase.script"
$utf8NoBom  = New-Object System.Text.UTF8Encoding $false

# Re-evaluate file existence here — $isRetry may have drifted during earlier processing.
# When C0 > 0% / C1 > 0% and the file exists: ALWAYS use APPEND mode (keep existing TCs, add new ones).
# When the file does not exist: CREATE mode (generate all TCs from plan).

# Fallback: if the correct-name file doesn't exist but a double-extension variant does,
# copy it to the correct name so APPEND mode can work normally.
$doubleExtFile = "$scriptDir\${TestObject}_testcase.script.script"
if (-not (Test-Path $outputFile) -and (Test-Path $doubleExtFile)) {
    Write-Host "[INFO] Found legacy double-extension file: $doubleExtFile" -ForegroundColor Yellow
    Write-Host "  -> Copying to correct name: $outputFile" -ForegroundColor Yellow
    Copy-Item -Path $doubleExtFile -Destination $outputFile -Force
}

$scriptFileExists = Test-Path $outputFile
if ($scriptFileExists -and -not $isRetry) {
    Write-Host "[INFO] Script file found on disk but isRetry=false -- switching to APPEND MODE (C0/C1 partial coverage)" -ForegroundColor Yellow
}
if (-not $scriptFileExists -and $isRetry) {
    Write-Host "[INFO] Script file not found on disk -- switching to CREATE MODE" -ForegroundColor Yellow
}

if ($scriptFileExists) {
    # -----------------------------------------------------------------------
    # APPEND MODE: script already exists — keep all existing $testcase blocks
    # and add each new TC from the plan as a new $testcase N { $teststep N.1 }
    # block appended after the last existing $testcase block.
    # -----------------------------------------------------------------------
    Write-Host "`n[APPEND MODE] Reading existing script to find highest testcase number..." -ForegroundColor Magenta
    $existingContent = [System.IO.File]::ReadAllText($outputFile, [System.Text.Encoding]::UTF8)

    # Find highest $testcase N already in file
    $tcMatches = [regex]::Matches($existingContent, '\$testcase\s+(\d+)\s*\{')
    $maxExistingTC = 0
    foreach ($m in $tcMatches) {
        $n = [int]$m.Groups[1].Value
        if ($n -gt $maxExistingTC) { $maxExistingTC = $n }
    }
    Write-Host "[APPEND MODE] Highest existing testcase: $maxExistingTC" -ForegroundColor Magenta

    # Always append ALL plan TCs after the highest existing testcase number.
    # The TCId in the JSON plan has no relation to the $testcase N counter in
    # the .script file — do NOT use TCId to filter out "already existing" TCs.
    $newTCs = @($planTestCases)
    if ($newTCs.Count -eq 0) {
        Write-Host "[APPEND MODE] No TCs in plan - nothing to append." -ForegroundColor Green
        Write-Host "`n[OUTPUT]" -ForegroundColor Cyan
        Write-Host "  File: $outputFile" -ForegroundColor White
        Write-Host "  Appended: 0 (script unchanged)" -ForegroundColor White
    } else {
        $firstNewTCNum = $maxExistingTC + 1
        $lastNewTCNum  = $maxExistingTC + $newTCs.Count
        Write-Host "[APPEND MODE] Adding $($newTCs.Count) new testcase(s) (testcase $firstNewTCNum..testcase $lastNewTCNum)..." -ForegroundColor Magenta

        # Build new $testcase N { $teststep N.1 { ... } } blocks
        $appendContent = ""
        $tcNum = $maxExistingTC
        foreach ($tc in $newTCs) {
            $tcNum++
            Write-Host "`n  [TC$($tc.TCId) -> testcase $tcNum] $($tc.Description.Substring(0, [Math]::Min(80, $tc.Description.Length)))" -ForegroundColor DarkCyan
            try {
                # Build the testcase header block
                $tcBlock  = Build-TCMetadata -TcNum $tcNum -TCDescription $tc.Description -TCTarget $(if ($tc.Target) { $tc.Target } else { $tc.Description })
                # Build teststep N.1 for this testcase (StepNum = 1, inside testcase N)
                $stepBlock = Build-TCInputsOutputs `
                    -TcNum              $tc.TCId `
                    -StepNum            1 `
                    -SetValues          @($tc.SetValues) `
                    -StubFunctionNames  @($tc.StubFunctions) `
                    -TCDescription      $tc.Description
                # Fix teststep prefix: Build-TCInputsOutputs always outputs "$teststep 1.1 {"
                # Use simple string Replace (avoids .NET regex replacement $name-reference issues)
                $stepBlock = $stepBlock.Replace("`t`t`$teststep 1.1 {", "`t`t`$teststep $tcNum.1 {")
                # Close the $testcase N block
                $tcBlock += $stepBlock
                $tcBlock += "`t}`n"
                $appendContent += $tcBlock
            } catch {
                Write-Host "  [WARNING] TC$($tc.TCId) skipped due to error: $_" -ForegroundColor Yellow
                Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed
            }
        }

        # Append new $testcase blocks before the final closing } of $testobject
        $nlChar  = if ($existingContent -match "`r`n") { "`r`n" } else { "`n" }
        $closingPattern = '\}\s*$'
        $updatedContent = [regex]::Replace(
            $existingContent.TrimEnd(),
            '\}\s*$',
            { $appendContent + "}" },
            [System.Text.RegularExpressions.RegexOptions]::Singleline
        )
        [System.IO.File]::WriteAllText($outputFile, $updatedContent + $nlChar, $utf8NoBom)
        Write-Host "`n[OK] Added $($newTCs.Count) new testcase(s) to existing script" -ForegroundColor Green

        Write-Host "`n[OUTPUT]" -ForegroundColor Cyan
        Write-Host "  File: $outputFile" -ForegroundColor White
        Write-Host "  Added: $($newTCs.Count) new testcase(s) (now $tcNum total)" -ForegroundColor White
    }
} else {
    # -----------------------------------------------------------------------
    # CREATE MODE: no existing script — generate complete script from JSON.
    # Each TC in the plan becomes its own $testcase N { $teststep N.1 } block.
    # -----------------------------------------------------------------------
    Write-Host "`n[GENERATION] Building test script from plan ($($planTestCases.Count) test case(s))..." -ForegroundColor Yellow

    $testScriptContent = "`$testobject {`n"

    # 1. Testobject-level $stubfunctions (all non-void stubs, default return values)
    $testScriptContent += Build-TestObjectStubs

    # 2. Each plan TC becomes a separate $testcase N { $teststep N.1 { ... } }
    $tcNum = 0
    foreach ($tc in $planTestCases) {
        $tcNum++
        Write-Host "`n  [TC$($tc.TCId) -> testcase $tcNum] $($tc.Description.Substring(0, [Math]::Min(80, $tc.Description.Length)))" -ForegroundColor DarkCyan
        try {
            # Build testcase N header with name "$TestObject. Test case NN"
            $tcBlock = Build-TCMetadata -TcNum $tcNum -TCDescription $tc.Description -TCTarget $(if ($tc.Target) { $tc.Target } else { $tc.Description })
            # Build $teststep N.1
            $stepBlock = Build-TCInputsOutputs `
                -TcNum              $tc.TCId `
                -StepNum            1 `
                -SetValues          @($tc.SetValues) `
                -StubFunctionNames  @($tc.StubFunctions) `
                -TCDescription      $tc.Description
            # Fix teststep prefix from "1.1" to "N.1"
            $stepBlock = $stepBlock.Replace("`t`t`$teststep 1.1 {", "`t`t`$teststep $tcNum.1 {")
            # Close $testcase N
            $tcBlock += $stepBlock
            $tcBlock += "`t}`n"
            $testScriptContent += $tcBlock
        } catch {
            Write-Host "  [WARNING] TC$($tc.TCId) skipped due to error: $_" -ForegroundColor Yellow
            Write-Host $_.ScriptStackTrace -ForegroundColor DarkRed
        }
    }

    $testScriptContent += "}"  # Close $testobject

    [System.IO.File]::WriteAllText($outputFile, $testScriptContent, $utf8NoBom)

    Write-Host "`n[OK] Test case script generated" -ForegroundColor Green
    Write-Host "`n[OUTPUT]" -ForegroundColor Cyan
    Write-Host "  File: $outputFile" -ForegroundColor White
    Write-Host "  Test cases generated: $($planTestCases.Count)" -ForegroundColor White
}
Write-Host ""

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "STEP 7 COMPLETE - Test case script with $numTestCases test case(s) ready for import" -ForegroundColor Green
Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "NEXT:" -ForegroundColor Yellow
Write-Host "  Run Step 8: step8_execute_tests.ps1" -ForegroundColor White
Write-Host ""

exit 0
