# ============================================================================
# STEP 2: Configure Test Interface Stubs (External + Local Functions)
# ============================================================================
param(
    [Parameter(Mandatory=$true)][string]$TestObject,
    [Parameter(Mandatory=$true)][string]$TessyProject,
    [Parameter(Mandatory=$true)][string]$TestCollection,
    [Parameter(Mandatory=$true)][string]$ScriptRoot,
    [Parameter(Mandatory=$true)][string]$ExportDir,
    [Parameter(Mandatory=$false)][string]$SourceDir = "",
    [Parameter(Mandatory=$false)][string]$ReportDir = "",
    [Parameter(Mandatory=$false)][string]$Module = "",
    [Parameter(Mandatory=$false)][string]$WorkingDir = ""
)

function Resolve-TessyReportDir {
    param(
        [string]$ScriptRoot,
        [string]$TestObject,
        [string]$PreferredReportDir = ""
    )

    $normalizedScriptRoot = [System.IO.Path]::GetFullPath($ScriptRoot)
    $scriptRootReport = Join-Path $normalizedScriptRoot "report"
    $projectRootReport = Join-Path (Split-Path -Parent $normalizedScriptRoot) "report"

    $candidates = @()
    if (-not [string]::IsNullOrWhiteSpace($PreferredReportDir)) {
        $candidates += [System.IO.Path]::GetFullPath($PreferredReportDir)
    }

    if ((Split-Path $normalizedScriptRoot -Leaf) -ieq "tessy") {
        $candidates += $projectRootReport
        $candidates += $scriptRootReport
    } else {
        $candidates += $scriptRootReport
        $candidates += $projectRootReport
    }

    $candidates = $candidates | Select-Object -Unique

    foreach ($candidate in $candidates) {
        if (-not (Test-Path $candidate)) { continue }
        if (Get-ChildItem -Path $candidate -Filter "TESSY_DetailsReport_${TestObject}*.html" -ErrorAction SilentlyContinue | Select-Object -First 1) {
            return $candidate
        }
        if (Get-ChildItem -Path $candidate -Filter "TESSY_DetailsReport_${TestObject}*.xml" -ErrorAction SilentlyContinue | Select-Object -First 1) {
            return $candidate
        }
    }

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) { return $candidate }
    }

    return $candidates[0]
}

$ReportDir = Resolve-TessyReportDir -ScriptRoot $ScriptRoot -TestObject $TestObject -PreferredReportDir $ReportDir

Write-Host "================================================================================" -ForegroundColor Cyan
Write-Host "  STEP 2: CONFIGURE TEST INTERFACE STUBS" -ForegroundColor Cyan
Write-Host "  Test Object: $TestObject" -ForegroundColor Cyan
Write-Host "  Report Dir: $ReportDir" -ForegroundColor DarkGray
Write-Host "================================================================================" -ForegroundColor Cyan

Set-Location $ScriptRoot

$ymlFolder = "$ExportDir\yml"
$yamlFile  = "$ymlFolder\${TestObject}_export.yml"
Write-Host "YAML will be exported to: $yamlFile" -ForegroundColor DarkGray

# Step 2a: Export YAML from Tessy
$step2aScript = Join-Path $PSScriptRoot "step2a_export_yaml.ps1"
if (-not (Test-Path $step2aScript)) { Write-Host "ERROR: Step 2a script not found: $step2aScript" -ForegroundColor Red; exit 1 }
Write-Host "`n[STEP 2a] Exporting YAML from Tessy..." -ForegroundColor Yellow
& $step2aScript -TestObject $TestObject -TessyProject $TessyProject -TestCollection $TestCollection -ScriptRoot $ScriptRoot -ExportDir $ExportDir
if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: Step 2a (YAML export) failed." -ForegroundColor Red; exit 1 }

# Step 2b: Parse HTML interface report
$step2bScript = Join-Path $PSScriptRoot "step2b_export_interface.ps1"
if (-not (Test-Path $step2bScript)) { Write-Host "ERROR: Step 2b script not found: $step2bScript" -ForegroundColor Red; exit 1 }
Write-Host "`n[STEP 2b] Parsing HTML interface report..." -ForegroundColor Yellow
& $step2bScript -TestObject $TestObject -ReportDir $ReportDir -OutputDir $ExportDir
if ($LASTEXITCODE -ne 0) { Write-Host "ERROR: Step 2b (interface export) failed." -ForegroundColor Red; exit 1 }

# Build stub function list from interface_info.txt (LOCAL + EXTERNAL)
$interfaceFile = "$ExportDir\interface\${TestObject}_interface_info.txt"
$interfaceText = Get-Content $interfaceFile -Raw
$stubFunctions = @()

if ($interfaceText -match "(?ms)^LOCAL FUNCTIONS:\r?\n-+\r?\n(.*?)(?=\r?\n(?-i)[A-Z]|\r?\n=)") {
    $sec = $Matches[1]
    $sec -split '\r?\n' | Where-Object { $_.Trim() -ne '' } | ForEach-Object {
        if ($_.Trim() -match '(\w+)\s*\([^)]*\)\s*$') {
            $fn = $Matches[1]
            if ($stubFunctions -notcontains $fn) { $stubFunctions += $fn }
        }
    }
    if ($stubFunctions.Count -gt 0) {
        Write-Host "  [LOCAL] Local functions added to YAML stubs: $($stubFunctions -join ', ')" -ForegroundColor DarkGray
    }
}

if ($interfaceText -match "(?ms)^EXTERNAL FUNCTIONS:\r?\n-+\r?\n(.*?)(?=\r?\n(?-i)[A-Z]|\r?\n=)") {
    $sec = $Matches[1]
    $before = $stubFunctions.Count
    $sec -split '\r?\n' | Where-Object { $_.Trim() -ne '' } | ForEach-Object {
        if ($_.Trim() -match '(\w+)\s*\([^)]*\)\s*$') {
            $fn = $Matches[1]
            if ($stubFunctions -notcontains $fn) { $stubFunctions += $fn }
        }
    }
    $added = $stubFunctions.Count - $before
    if ($added -gt 0) {
        Write-Host "  [EXTERNAL] External functions added to YAML stubs: $(($stubFunctions | Select-Object -Last $added) -join ', ')" -ForegroundColor DarkGray
    }
}

Write-Host "  [STUBS] Total: $($stubFunctions.Count) -- $($stubFunctions -join ', ')" -ForegroundColor Cyan

$yamlContent = Get-Content $yamlFile -Raw

Write-Host "`n[CONFIGURE] Ensuring Stubs section contains all functions..." -ForegroundColor Yellow

if (-not $stubFunctions -or $stubFunctions.Count -eq 0) {
    Write-Host "No stub functions detected - leaving YAML stubs unchanged." -ForegroundColor Green

} elseif ($yamlContent -match "(?ms)---\r?\nStubs:") {
    $stubsSection = ""
    if ($yamlContent -match "(?ms)---\r?\nStubs:\r?\n(.*?)(?=\r?\n---|\z)") { $stubsSection = $Matches[1] }
    $existingStubs = [System.Collections.Generic.List[string]]@()
    $existingStubBodies = @{}  # functionName -> existing stub body (preserve across rebuilds)
    $stubsSection -split "`n" | ForEach-Object {
        # Full row parse: - ['type', 'ver', FuncName, 'body']
        if ($_ -match "^\s*-\s*\['[^']*',\s*'[^']*',\s*([^,\]]+),\s*'(.*)'\s*\]") {
            $sn = $Matches[1].Trim()
            $existingStubs.Add($sn)
            $existingStubBodies[$sn] = $Matches[2].Trim()
        } elseif ($_ -match "'0'\s*,\s*'0'\s*,\s*([^,]+)\s*,") {
            $existingStubs.Add($Matches[1].Trim())
        }
    }
    $isMatch = ($existingStubs.Count -eq $stubFunctions.Count) -and
               (($stubFunctions | Where-Object { $existingStubs -notcontains $_ }).Count -eq 0)
    if (-not $isMatch) {
        $missing = $stubFunctions | Where-Object { $existingStubs -notcontains $_ }
        $extra   = $existingStubs  | Where-Object { $stubFunctions -notcontains $_ }
        if ($missing.Count -gt 0) { Write-Host "  Adding: $($missing -join ', ')" -ForegroundColor Yellow }
        if ($extra.Count -gt 0)   { Write-Host "  Removing: $($extra -join ', ')" -ForegroundColor Yellow }
        $sorted = $stubFunctions | Sort-Object
        $lines = ($sorted | ForEach-Object {
            $fn = $_; $body = ''
            # Preserve existing non-empty body; assign return 0; default for non-void new stubs
            if ($existingStubBodies.ContainsKey($fn) -and $existingStubBodies[$fn] -ne '') {
                $body = $existingStubBodies[$fn]
            } else {
                $esc = [regex]::Escape($fn)
                if ($interfaceText -match "(?m)^([\w][\w\s\*]*?)\s+\b${esc}\s*\(") {
                    if ($Matches[1].Trim() -ne 'void') { $body = 'return 0;' }
                }
            }
            "- ['0', '0', $fn, '$body']"
        }) -join "`r`n"
        $newBlock = "---`r`nStubs:`r`n" + $lines
        $yamlContent = $yamlContent -replace "(?ms)---\r?\nStubs:.*?(?=\r?\n---)", $newBlock
        [System.IO.File]::WriteAllText($yamlFile, $yamlContent, (New-Object System.Text.UTF8Encoding $false))
        Write-Host "Stubs section rebuilt." -ForegroundColor Green
    } else {
        Write-Host "All stubs already present." -ForegroundColor Green
    }

} else {
    Write-Host "No Stubs section found - creating new one." -ForegroundColor Yellow
    $sorted = $stubFunctions | Sort-Object
    $lines = ($sorted | ForEach-Object {
        $fn = $_; $body = ''
        $esc = [regex]::Escape($fn)
        if ($interfaceText -match "(?m)^([\w][\w\s\*]*?)\s+\b${esc}\s*\(") {
            if ($Matches[1].Trim() -ne 'void') { $body = 'return 0;' }
        }
        "- ['0', '0', $fn, '$body']"
    }) -join "`r`n"
    $section = "---`r`nStubs:`r`n" + $lines + "`r`n"
    if ($yamlContent -match "(?ms)---\r?\nValues:") {
        $yamlContent = $yamlContent -replace "(?ms)(---\r?\nValues:)", ($section + '$1')
        Write-Host "Stubs section inserted before Values block." -ForegroundColor Green
    } elseif ($yamlContent -match "(?ms)---\r?\nProperties:") {
        $yamlContent = $yamlContent -replace "(?ms)(---\r?\n(?:Properties:).*?\r?\n)(---\r?\n(?!Stubs:))", ('$1' + $section + '$2')
        Write-Host "Stubs section inserted after Properties block." -ForegroundColor Green
    } else {
        $yamlContent += "`r`n" + $section
        Write-Host "Stubs section appended to YAML." -ForegroundColor Green
    }
    [System.IO.File]::WriteAllText($yamlFile, $yamlContent, (New-Object System.Text.UTF8Encoding $false))
}

Write-Host "`n[IMPORT] Importing YAML (twice for reliability)..." -ForegroundColor Yellow
Write-Host "  YAML file: $yamlFile" -ForegroundColor DarkGray

Write-Host "`n--- Import attempt 1/2 ---" -ForegroundColor DarkCyan
Write-Host "  CMD: tessycmd import $yamlFile" -ForegroundColor DarkGray
$import1Output = tessycmd import $yamlFile 2>&1
$import1Exit = $LASTEXITCODE
if ($import1Output) { $import1Output | ForEach-Object { Write-Host "  [tessycmd] $_" -ForegroundColor Gray } } else { Write-Host "  [tessycmd] (no output)" -ForegroundColor DarkGray }
if ($import1Exit -eq 0) { $c1 = "Green" } else { $c1 = "Yellow" }
Write-Host "  Exit code: $import1Exit" -ForegroundColor $c1

Start-Sleep -Seconds 8

Write-Host "`n--- Import attempt 2/2 ---" -ForegroundColor DarkCyan
Write-Host "  CMD: tessycmd import $yamlFile" -ForegroundColor DarkGray
$import2Output = tessycmd import $yamlFile 2>&1
$importExit = $LASTEXITCODE
if ($import2Output) { $import2Output | ForEach-Object { Write-Host "  [tessycmd] $_" -ForegroundColor Gray } } else { Write-Host "  [tessycmd] (no output)" -ForegroundColor DarkGray }
if ($importExit -eq 0) { $c2 = "Green" } else { $c2 = "Yellow" }
Write-Host "  Exit code: $importExit" -ForegroundColor $c2

if ($importExit -eq 0) {
    Write-Host "Stub configuration imported successfully." -ForegroundColor Green
} else {
    Write-Host "WARNING: Import exit code $importExit (continuing)" -ForegroundColor Yellow
    $global:LASTEXITCODE = 0
}

Write-Host "`n================================================================================" -ForegroundColor Cyan
Write-Host "  STEP 2 COMPLETE" -ForegroundColor Cyan
Write-Host "  Next: Run step3_find_and_save_function_code.ps1" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan
exit 0