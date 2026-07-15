# ============================================================================
# common.ps1
# ============================================================================
# Common utilities for Tessy Automation Framework
# ============================================================================

. "$PSScriptRoot\helpers\config.ps1"
. "$PSScriptRoot\helpers\logger.ps1"

# ----------------------------------------------------------------------------
# Banner
# ----------------------------------------------------------------------------

function Show-Banner
{
    param(
        [string]$Title
    )

    $line = "=" * 80

    Write-Host ""
    Write-Host $line -ForegroundColor Cyan
    Write-Host " $Title" -ForegroundColor Cyan
    Write-Host $line -ForegroundColor Cyan
}

# ----------------------------------------------------------------------------
# Connect
# ----------------------------------------------------------------------------

function Connect-Tessy
{
    param(
        [string]$Step
    )

    Write-Info `
        -Step $Step `
        -Message "Connecting to Tessy..." `
        -Command "connect"

    Set-Location $Config.ScriptRoot

    tessycmd connect 2>&1 | Out-Null

    if($LASTEXITCODE -ne 0)
    {
        Write-ErrorLog `
            -Step $Step `
            -Message "Failed to connect to Tessy." `
            -Command "connect" `
            -ExitCode $LASTEXITCODE

        exit 1
    }

    Write-Info `
        -Step $Step `
        -Message "Connected."
}

# ----------------------------------------------------------------------------
# Disconnect
# ----------------------------------------------------------------------------

function Disconnect-Tessy
{
    param(
        [string]$Step
    )

    Write-Info `
        -Step $Step `
        -Message "Disconnect Tessy." `
        -Command "disconnect"

    Set-Location $Config.ScriptRoot

    tessycmd disconnect 2>&1 | Out-Null
}

# ----------------------------------------------------------------------------
# Execute Tessy Command
# ----------------------------------------------------------------------------

function Invoke-Tessy
{
    param(

        [string]$Step,

        [string]$Command,

        [string[]]$Arguments = @(),

        [string]$ErrorMessage = "Tessy command failed."

    )

    Set-Location $Config.ScriptRoot

    & tessycmd $Command @Arguments 2>&1 | Out-Null

    if($LASTEXITCODE -ne 0)
    {
        Write-ErrorLog `
            -Step $Step `
            -Message $ErrorMessage `
            -Command "$Command $($Arguments -join ' ')" `
            -ExitCode $LASTEXITCODE

        exit 1
    }
}

# ----------------------------------------------------------------------------
# Execute Tessy Command (Capture Output)
# ----------------------------------------------------------------------------

function Invoke-TessyOutput
{
    param(

        [string]$Step,

        [string]$Command,

        [string[]]$Arguments = @(),

        [string]$ErrorMessage = "Tessy command failed."

    )

    Set-Location $Config.ScriptRoot

    $output = & tessycmd $Command @Arguments 2>&1

    if($LASTEXITCODE -ne 0)
    {
        Write-ErrorLog `
            -Step $Step `
            -Message $ErrorMessage `
            -Command "$Command $($Arguments -join ' ')" `
            -ExitCode $LASTEXITCODE

        exit 1
    }

    return $output
}

# ----------------------------------------------------------------------------
# Select Project
# ----------------------------------------------------------------------------

function Select-Project
{
    param(
        [string]$Step
    )

    Write-Info `
        -Step $Step `
        -Message "Select Project : $($Config.TessyProject)"

    Invoke-Tessy `
        -Step $Step `
        -Command "select-project" `
        -Arguments @($Config.TessyProject) `
        -ErrorMessage "Failed to select project '$($Config.TessyProject)'."
}

# ----------------------------------------------------------------------------
# Select Test Collection
# ----------------------------------------------------------------------------

function Select-TestCollection
{
    param(
        [string]$Step
    )

    Write-Info `
        -Step $Step `
        -Message "Select Test Collection : $($Config.TestCollection)"

    Invoke-Tessy `
        -Step $Step `
        -Command "select-test-collection" `
        -Arguments @($Config.TestCollection) `
        -ErrorMessage "Failed to select test collection '$($Config.TestCollection)'."
}

# ----------------------------------------------------------------------------
# Select Folder
# ----------------------------------------------------------------------------

function Select-Folder
{
    param(
        [string]$Step
    )

    if([string]::IsNullOrWhiteSpace($Config.Folder) -or $Config.Folder -eq ".")
    {
        return
    }

    foreach($folder in ($Config.Folder -split '[/\\]'))
    {
        Write-Info `
            -Step $Step `
            -Message "Select Folder : $folder"

        Invoke-Tessy `
            -Step $Step `
            -Command "select-folder" `
            -Arguments @($folder) `
            -ErrorMessage "Failed to select folder '$folder'."
    }
}

# ----------------------------------------------------------------------------
# Select Module
# ----------------------------------------------------------------------------

function Select-Module
{
    param(
        [string]$Step
    )

    $moduleName = $Config.Module -replace '\.c$',''

    Write-Info `
        -Step $Step `
        -Message "Select Module : $($Config.Module)"

    Set-Location $Config.ScriptRoot

    tessycmd select-module "$($Config.Module)" 2>&1 | Out-Null

    if($LASTEXITCODE -eq 0)
    {
        return
    }

    Write-Info `
        -Step $Step `
        -Message "Retry without .c"

    tessycmd select-module "$moduleName" 2>&1 | Out-Null

    if($LASTEXITCODE -ne 0)
    {
        Write-ErrorLog `
            -Step $Step `
            -Message "Failed to select module '$($Config.Module)'." `
            -Command "select-module $($Config.Module)" `
            -ExitCode $LASTEXITCODE

        exit 1
    }
}

# ----------------------------------------------------------------------------
# Select Test Object
# ----------------------------------------------------------------------------

function Select-TestObject
{
    param(
        [string]$Step,
        [string]$TestObject
    )

    Write-Info `
        -Step $Step `
        -Message "Select Test Object : $TestObject"

    Invoke-Tessy `
        -Step $Step `
        -Command "select-test-object" `
        -Arguments @($TestObject) `
        -ErrorMessage "Failed to select test object '$TestObject'."
}

# ----------------------------------------------------------------------------
# Select Test Object
# ----------------------------------------------------------------------------

function Select-TestObject
{
    param(
        [string]$Step,
        [string]$TestObject
    )

    Write-Info `
        -Step $Step `
        -Message "Select Test Object : $TestObject"

    Invoke-Tessy `
        -Step $Step `
        -Command "select-test-object" `
        -Arguments @($TestObject) `
        -ErrorMessage "Failed to select test object '$TestObject'."
}

# ----------------------------------------------------------------------------
# Delete Old Reports
# ----------------------------------------------------------------------------

function Clear-TestObjectReports
{
    param(

        [string]$ReportDir,

        [string]$TestObject

    )

    if(!(Test-Path $ReportDir))
    {
        New-Item `
            -ItemType Directory `
            -Path $ReportDir `
            -Force | Out-Null
    }

    Get-ChildItem `
        -Path $ReportDir `
        -Filter "TESSY_DetailsReport_${TestObject}*.html" `
        -ErrorAction SilentlyContinue |

    ForEach-Object{

        Remove-Item $_.FullName -Force

        Write-Host "Deleted : $($_.Name)" -ForegroundColor DarkGray

    }
}

# ----------------------------------------------------------------------------
# Read Coverage Report
# ----------------------------------------------------------------------------

function Read-CoverageReport
{
    param(
        [string]$HtmlReport
    )

    $result = [ordered]@{

        C0 = 0

        C1 = 0

        Total = 0

        Passed = 0

        Failed = 0

    }

    if(!(Test-Path $HtmlReport))
    {
        return [PSCustomObject]$result
    }

    $html = Get-Content $HtmlReport -Raw

    $patterns = @{

        C0     = 'Statement \(C0\) Coverage.{1,400}?<div[^>]*>(\d+\.?\d*)\s*%</div>'

        C1     = 'Branch \(C1\) Coverage.{1,400}?<div[^>]*>(\d+\.?\d*)\s*%</div>'

        Total  = 'Total Testcases.{1,400}?<div[^>]*>(\d+)</div>'

        Passed = 'Successful</div>.{1,400}?<div[^>]*>(\d+)</div>'

        Failed = 'Failed</div>.{1,400}?<div[^>]*>(\d+)</div>'

    }

    foreach($key in $patterns.Keys)
    {
        $m = [regex]::Match(
            $html,
            $patterns[$key],
            [System.Text.RegularExpressions.RegexOptions]::Singleline
        )

        if($m.Success)
        {
            $result[$key] = $m.Groups[1].Value
        }
    }

    if($result.Total -gt 0 -and
       $result.Passed -eq 0 -and
       $result.Failed -eq 0)
    {
        $result.Passed = $result.Total
    }

    return [PSCustomObject]$result
}

# ----------------------------------------------------------------------------
# Save Coverage Status
# ----------------------------------------------------------------------------

function Save-CoverageStatus
{
    param(

        [string]$WorkingDir,

        [string]$TestObject,

        [string]$Module,

        [object]$Coverage

    )

    $jsonDir = Join-Path $WorkingDir "json_files"

    if(!(Test-Path $jsonDir))
    {
        New-Item `
            -ItemType Directory `
            -Path $jsonDir `
            -Force | Out-Null
    }

    $statusFile = Join-Path `
        $jsonDir `
        "${TestObject}_coverage_status.json"

    [ordered]@{

        TestObject = $TestObject

        Module = $Module

        C0 = $Coverage.C0

        C1 = $Coverage.C1

        Total = $Coverage.Total

        Passed = $Coverage.Passed

        Failed = $Coverage.Failed

    } |

    ConvertTo-Json -Depth 5 |

    Out-File `
        -FilePath $statusFile `
        -Encoding UTF8

    return $statusFile
}

# ----------------------------------------------------------------------------
# Export Existing Script
# ----------------------------------------------------------------------------

function Export-TestScript
{
    param(

        [string]$WorkingDir,

        [string]$TestObject

    )

    $scriptDir = Join-Path $WorkingDir "script_files"

    if(!(Test-Path $scriptDir))
    {
        New-Item `
            -ItemType Directory `
            -Path $scriptDir `
            -Force | Out-Null
    }

    Invoke-Tessy `
        -Step "EXPORT" `
        -Command "export" `
        -Arguments @(
            "-format","script",
            "-expected",
            "-file","${TestObject}_testcase.script",
            $scriptDir
        ) `
        -ErrorMessage "Failed to export testcase script."

    return (Join-Path $scriptDir "${TestObject}_testcase.script")
}

# ----------------------------------------------------------------------------
# Select Entire Context
# ----------------------------------------------------------------------------

function Select-TessyContext
{
    param(
        [string]$Step
    )

    Select-Project $Step
    Select-TestCollection $Step
    Select-Folder $Step
    Select-Module $Step
}

function Resolve-TessyReportDir
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptRoot
    )

    return (Join-Path $ScriptRoot "reports")
}

# ----------------------------------------------------------------------------
# Create Tessy Interface Report Batch File
# ----------------------------------------------------------------------------

function New-TessyInterfaceReportBatch
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$TestObject,

        [Parameter(Mandatory = $true)]
        [string]$Module,

        [AllowNull()]
        [AllowEmptyString()]
        [string]$Folder,

        [Parameter(Mandatory = $true)]
        [string]$TestCollection,

        [Parameter(Mandatory = $true)]
        [string]$ReportDir,

        [Parameter(Mandatory = $true)]
        [string]$WorkingDir
    )

    $folderXml = ""
    $closingTags = ""

    if(-not [string]::IsNullOrWhiteSpace($Folder) -and $Folder -ne ".")
    {
        foreach($folderLevel in ($Folder -split '[/\\]'))
        {
            $escapedFolder = [System.Security.SecurityElement]::Escape($folderLevel)
            $folderXml += "            <folder name=`"$escapedFolder`">`n"
            $closingTags = "            </folder>`n" + $closingTags
        }
    }

    $moduleName = $Module -replace '\.c$',''
    $escapedCollection = [System.Security.SecurityElement]::Escape($TestCollection)
    $escapedModule = [System.Security.SecurityElement]::Escape($moduleName)
    $escapedTestObject = [System.Security.SecurityElement]::Escape($TestObject)
    $escapedReportDir = [System.Security.SecurityElement]::Escape($ReportDir)

    $batchContentHtml = @"
<?xml version="1.0" encoding="UTF-8"?>
<batchtest>
    <operations>
        <operation key="executeTest">
            <options>
                <option key="checkInterface" value="true"/>
                <option key="generateDriver" value="true"/>
                <option key="run" value="true"/>
                <option key="runNoInstrumentationTest" value="false"/>
                <option key="runPatternTest" value="false"/>
                <option key="runMutationTest" value="false"/>
                <option key="createNewTestRun" value="true"/>
                <option key="retryAbortedExecution" value="false"/>
                <option key="instrumentationType" value="TESTOBJECT_ONLY"/>
                <option key="defaultCoverage" value="false"/>
                <option key="defaultCoveragePerTestObject" value="false"/>
                <option key="abortOnMissingStubCode" value="true"/>
                <option key="preAnalyzeScript" value=""/>
                <option key="preExecuteScript" value=""/>
                <option key="postExecuteScript" value=""/>
            </options>
            <coverageTypes>
                <coverageType name="STATEMENT"/>
                <coverageType name="BRANCH"/>
            </coverageTypes>
        </operation>
        <operation key="generateTestReport">
            <options>
                <option key="reportOutputDirectory" value="$escapedReportDir"/>
                <option key="reportFileNamePattern" value="TESSY_DetailsReport_`$(TESTOBJECT)"/>
                <option key="reportOutputFormat" value="html"/>
            </options>
            <arguments>
                <argument name="OPT_TESTDATA_ONLY_MODE" value="false"/>
                <argument name="OPT_SHOW_PROPERTIES" value="true"/>
                <argument name="OPT_SHOW_USER_AND_HOST" value="false"/>
                <argument name="OPT_SHOW_COVERAGE" value="true"/>
                <argument name="OPT_SHOW_INTERFACE" value="true"/>
                <argument name="OPT_SHOW_METRICS" value="true"/>
                <argument name="OPT_SHOW_ATTRIBUTES" value="true"/>
                <argument name="OPT_SHOW_COMMENTS" value="true"/>
                <argument name="OPT_SHOW_CTE" value="true"/>
                <argument name="OPT_SHOW_USERCODE" value="true"/>
                <argument name="OPT_SHOW_TS_DETAILS" value="true"/>
                <argument name="OPT_SHOW_REQUIREMENT_TEXT" value="false"/>
                <argument name="OPT_SHOW_FAULT_INJECTION_TCS" value="true"/>
                <argument name="OPT_SHOW_FAULT_INJECTIONS" value="true"/>
                <argument name="OPT_HIDE_NONE_VALUES" value="true"/>
                <argument name="OPT_SHOW_NOTES" value="true"/>
                <argument name="OPT_SHOW_UUID" value="false"/>
                <argument name="OPT_HIDE_TESTSTEPS" value="false"/>
                <argument name="OPT_SHOW_VARIANT_INFO" value="true"/>
                <argument name="OPT_SHOW_LAST_MODIFIED_TIME" value="false"/>
            </arguments>
        </operation>
    </operations>
    <elements>
        <testcollection name="$escapedCollection">
$folderXml                <module name="$escapedModule"><testobject name="$escapedTestObject"/></module>
$closingTags        </testcollection>
    </elements>
</batchtest>
"@

    $tbsDir = Join-Path $WorkingDir "tbs_files"

    if(!(Test-Path $tbsDir))
    {
        New-Item `
            -ItemType Directory `
            -Path $tbsDir `
            -Force | Out-Null
    }

    $batchFile = Join-Path $tbsDir "generate_report_${TestObject}_html.tbs"
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    [System.IO.File]::WriteAllText(
        $batchFile,
        $batchContentHtml,
        $utf8NoBom
    )

    return $batchFile
}

# ----------------------------------------------------------------------------
# Execute Tessy Batch File
# ----------------------------------------------------------------------------

function Invoke-TessyBatch
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$Step,

        [Parameter(Mandatory = $true)]
        [string]$BatchFile
    )

    if(!(Test-Path $BatchFile))
    {
        Write-ErrorLog `
            -Step $Step `
            -Message "Tessy batch file not found: $BatchFile" `
            -Command "-animate exec-test $BatchFile" `
            -ExitCode 1

        exit 1
    }

    Write-Info `
        -Step $Step `
        -Message "Execute Tessy batch: $BatchFile" `
        -Command "-animate exec-test $BatchFile"

    Set-Location $Config.ScriptRoot

    & tessycmd "-animate" "exec-test" $BatchFile 2>&1 | Out-Null

    if($LASTEXITCODE -ne 0)
    {
        Write-ErrorLog `
            -Step $Step `
            -Message "Tessy batch execution failed." `
            -Command "-animate exec-test $BatchFile" `
            -ExitCode $LASTEXITCODE

        exit 1
    }
}

# ----------------------------------------------------------------------------
# Export Existing Script Without Stopping Pipeline
# ----------------------------------------------------------------------------

function Export-TestScriptNonFatal
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$Step,

        [Parameter(Mandatory = $true)]
        [string]$WorkingDir,

        [Parameter(Mandatory = $true)]
        [string]$TestObject
    )

    $scriptDir = Join-Path $WorkingDir "script_files"

    if(!(Test-Path $scriptDir))
    {
        New-Item `
            -ItemType Directory `
            -Path $scriptDir `
            -Force | Out-Null
    }

    $scriptFile = Join-Path $scriptDir "${TestObject}_testcase.script"

    Write-Info `
        -Step $Step `
        -Message "Export existing testcase script: $scriptFile" `
        -Command "export -format script -expected"

    Set-Location $Config.ScriptRoot

    & tessycmd `
        "export" `
        "-format" "script" `
        "-expected" `
        "-file" "${TestObject}_testcase.script" `
        $scriptDir 2>&1 | Out-Null

    if($LASTEXITCODE -ne 0)
    {
        Write-WarningLog `
            -Step $Step `
            -Message "Test script export failed; continue pipeline." `
            -Command "export -format script -expected -file ${TestObject}_testcase.script $scriptDir" `
            -ExitCode $LASTEXITCODE

        return $null
    }

    return $scriptFile
}


# ----------------------------------------------------------------------------
# Resolve Report Directory for a Specific Test Object
# ----------------------------------------------------------------------------

function Resolve-TessyReportDirForTestObject
{
    param(
        [string]$ScriptRoot,
        [string]$TestObject,
        [string]$PreferredReportDir = ""
    )

    $normalizedScriptRoot = [System.IO.Path]::GetFullPath($ScriptRoot)
    $scriptRootReport = Join-Path $normalizedScriptRoot "report"
    $projectRootReport = Join-Path (Split-Path -Parent $normalizedScriptRoot) "report"

    $candidates = @()

    if(-not [string]::IsNullOrWhiteSpace($PreferredReportDir))
    {
        $candidates += [System.IO.Path]::GetFullPath($PreferredReportDir)
    }

    if((Split-Path $normalizedScriptRoot -Leaf) -ieq "tessy")
    {
        $candidates += $projectRootReport
        $candidates += $scriptRootReport
    }
    else
    {
        $candidates += $scriptRootReport
        $candidates += $projectRootReport
    }

    $candidates = @($candidates | Select-Object -Unique)

    foreach($candidate in $candidates)
    {
        if(-not (Test-Path $candidate)) { continue }

        $htmlReport = Get-ChildItem `
            -Path $candidate `
            -Filter "TESSY_DetailsReport_${TestObject}*.html" `
            -ErrorAction SilentlyContinue | Select-Object -First 1

        if($htmlReport) { return $candidate }

        $xmlReport = Get-ChildItem `
            -Path $candidate `
            -Filter "TESSY_DetailsReport_${TestObject}*.xml" `
            -ErrorAction SilentlyContinue | Select-Object -First 1

        if($xmlReport) { return $candidate }
    }

    foreach($candidate in $candidates)
    {
        if(Test-Path $candidate) { return $candidate }
    }

    if($candidates.Count -eq 0)
    {
        return $scriptRootReport
    }

    return $candidates[0]
}

# ----------------------------------------------------------------------------
# Execute a Child PowerShell Step
# ----------------------------------------------------------------------------

function Invoke-ChildPowerShellStep
{
    param(
        [string]$Step,
        [string]$Name,
        [string]$ScriptPath,
        [hashtable]$Arguments = @{}
    )

    if(-not (Test-Path $ScriptPath))
    {
        Write-ErrorLog `
            -Step $Step `
            -Message "Child script not found: $ScriptPath" `
            -Command $Name `
            -ExitCode 1

        exit 1
    }

    Write-Info -Step $Step -Message $Name -Command $ScriptPath

    & $ScriptPath @Arguments
    $exitCode = $LASTEXITCODE

    if($exitCode -ne 0)
    {
        Write-ErrorLog `
            -Step $Step `
            -Message "$Name failed." `
            -Command $ScriptPath `
            -ExitCode $exitCode

        exit 1
    }
}

# ----------------------------------------------------------------------------
# Read LOCAL + EXTERNAL Stub Functions from Interface Information
# ----------------------------------------------------------------------------

function Get-TessyStubFunctionsFromInterface
{
    param(
        [string]$Step,
        [string]$InterfaceFile
    )

    if(-not (Test-Path $InterfaceFile))
    {
        Write-ErrorLog `
            -Step $Step `
            -Message "Interface information file not found: $InterfaceFile" `
            -Command "Get-Content" `
            -ExitCode 1

        exit 1
    }

    $interfaceText = Get-Content $InterfaceFile -Raw
    $localFunctions = @()
    $externalFunctions = @()

    $sections = @(
        @{ Name = "LOCAL FUNCTIONS"; Target = "Local" },
        @{ Name = "EXTERNAL FUNCTIONS"; Target = "External" }
    )

    foreach($section in $sections)
    {
        $pattern = "(?ms)^$([regex]::Escape($section.Name)):\r?\n-+\r?\n(.*?)(?=\r?\n(?-i)[A-Z]|\r?\n=)"

        if($interfaceText -match $pattern)
        {
            $functions = @(
                $Matches[1] -split '\r?\n' |
                    Where-Object { $_.Trim() -ne '' } |
                    ForEach-Object {
                        if($_.Trim() -match '(\w+)\s*\([^)]*\)\s*$')
                        {
                            $Matches[1]
                        }
                    } |
                    Where-Object { $_ } |
                    Select-Object -Unique
            )

            if($section.Target -eq "Local")
            {
                $localFunctions = $functions
            }
            else
            {
                $externalFunctions = $functions
            }
        }
    }

    $allFunctions = @(
        @($localFunctions) + @($externalFunctions) |
            Select-Object -Unique
    )

    if($localFunctions.Count -gt 0)
    {
        Write-Info -Step $Step -Message "Local stub functions: $($localFunctions -join ', ')"
    }

    if($externalFunctions.Count -gt 0)
    {
        Write-Info -Step $Step -Message "External stub functions: $($externalFunctions -join ', ')"
    }

    return [PSCustomObject]@{
        Local    = @($localFunctions)
        External = @($externalFunctions)
        All      = @($allFunctions)
    }
}

# ----------------------------------------------------------------------------
# Create One YAML Stub Row
# ----------------------------------------------------------------------------

function New-TessyYamlStubRow
{
    param(
        [string]$FunctionName,
        [string]$InterfaceText,
        [hashtable]$ExistingStubBodies
    )

    $body = ''

    if($ExistingStubBodies.ContainsKey($FunctionName) -and
       $ExistingStubBodies[$FunctionName] -ne '')
    {
        $body = $ExistingStubBodies[$FunctionName]
    }
    else
    {
        $escapedName = [regex]::Escape($FunctionName)

        if($InterfaceText -match "(?m)^([\w][\w\s\*]*?)\s+\b${escapedName}\s*\(")
        {
            if($Matches[1].Trim() -ne 'void')
            {
                $body = 'return 0;'
            }
        }
    }

    return "- ['0', '0', $FunctionName, '$body']"
}

# ----------------------------------------------------------------------------
# Ensure YAML Stubs Match Interface Functions
# ----------------------------------------------------------------------------

function Update-TessyYamlStubs
{
    param(
        [string]$Step,
        [string]$YamlFile,
        [string]$InterfaceFile,
        [string[]]$StubFunctions
    )

    if(-not (Test-Path $YamlFile))
    {
        Write-ErrorLog `
            -Step $Step `
            -Message "YAML file not found: $YamlFile" `
            -Command "Get-Content" `
            -ExitCode 1

        exit 1
    }

    $yamlContent = Get-Content $YamlFile -Raw
    $interfaceText = Get-Content $InterfaceFile -Raw

    if(-not $StubFunctions -or $StubFunctions.Count -eq 0)
    {
        Write-Info -Step $Step -Message "No stub functions detected; YAML remains unchanged."
        return
    }

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)

    if($yamlContent -match "(?ms)---\r?\nStubs:")
    {
        $stubsSection = ""

        if($yamlContent -match "(?ms)---\r?\nStubs:\r?\n(.*?)(?=\r?\n---|\z)")
        {
            $stubsSection = $Matches[1]
        }

        $existingStubs = [System.Collections.Generic.List[string]]@()
        $existingStubBodies = @{}

        $stubsSection -split "`n" | ForEach-Object {
            if($_ -match "^\s*-\s*\['[^']*',\s*'[^']*',\s*([^,\]]+),\s*'(.*)'\s*\]")
            {
                $stubName = $Matches[1].Trim()
                $existingStubs.Add($stubName)
                $existingStubBodies[$stubName] = $Matches[2].Trim()
            }
            elseif($_ -match "'0'\s*,\s*'0'\s*,\s*([^,]+)\s*,")
            {
                $existingStubs.Add($Matches[1].Trim())
            }
        }

        $isMatch = ($existingStubs.Count -eq $StubFunctions.Count) -and
                   (($StubFunctions | Where-Object { $existingStubs -notcontains $_ }).Count -eq 0)

        if($isMatch)
        {
            Write-Info -Step $Step -Message "All YAML stubs are already present."
            return
        }

        $missing = @($StubFunctions | Where-Object { $existingStubs -notcontains $_ })
        $extra = @($existingStubs | Where-Object { $StubFunctions -notcontains $_ })

        if($missing.Count -gt 0)
        {
            Write-Info -Step $Step -Message "Add YAML stubs: $($missing -join ', ')"
        }

        if($extra.Count -gt 0)
        {
            Write-Info -Step $Step -Message "Remove YAML stubs: $($extra -join ', ')"
        }

        $lines = @(
            $StubFunctions | Sort-Object | ForEach-Object {
                New-TessyYamlStubRow `
                    -FunctionName $_ `
                    -InterfaceText $interfaceText `
                    -ExistingStubBodies $existingStubBodies
            }
        ) -join "`r`n"

        $newBlock = "---`r`nStubs:`r`n" + $lines
        $yamlContent = $yamlContent -replace "(?ms)---\r?\nStubs:.*?(?=\r?\n---)", $newBlock

        [System.IO.File]::WriteAllText($YamlFile, $yamlContent, $utf8NoBom)
        Write-Info -Step $Step -Message "YAML Stubs section rebuilt."
        return
    }

    Write-Info -Step $Step -Message "No Stubs section found; create a new section."

    $emptyBodies = @{}
    $lines = @(
        $StubFunctions | Sort-Object | ForEach-Object {
            New-TessyYamlStubRow `
                -FunctionName $_ `
                -InterfaceText $interfaceText `
                -ExistingStubBodies $emptyBodies
        }
    ) -join "`r`n"

    $section = "---`r`nStubs:`r`n" + $lines + "`r`n"

    if($yamlContent -match "(?ms)---\r?\nValues:")
    {
        $yamlContent = $yamlContent -replace "(?ms)(---\r?\nValues:)", ($section + '$1')
        Write-Info -Step $Step -Message "Stubs section inserted before Values block."
    }
    elseif($yamlContent -match "(?ms)---\r?\nProperties:")
    {
        $yamlContent = $yamlContent -replace `
            "(?ms)(---\r?\n(?:Properties:).*?\r?\n)(---\r?\n(?!Stubs:))", `
            ('$1' + $section + '$2')

        Write-Info -Step $Step -Message "Stubs section inserted after Properties block."
    }
    else
    {
        $yamlContent += "`r`n" + $section
        Write-Info -Step $Step -Message "Stubs section appended to YAML."
    }

    [System.IO.File]::WriteAllText($YamlFile, $yamlContent, $utf8NoBom)
}

# ----------------------------------------------------------------------------
# Import YAML Twice; Final Failure Is Non-Fatal
# ----------------------------------------------------------------------------

function Import-TessyYamlTwice
{
    param(
        [string]$Step,
        [string]$YamlFile,
        [int]$DelaySeconds = 8
    )

    if(-not (Test-Path $YamlFile))
    {
        Write-ErrorLog `
            -Step $Step `
            -Message "YAML import file not found: $YamlFile" `
            -Command "import $YamlFile" `
            -ExitCode 1

        exit 1
    }

    Set-Location $Config.ScriptRoot

    for($attempt = 1; $attempt -le 2; $attempt++)
    {
        Write-Info `
            -Step $Step `
            -Message "Import YAML attempt $attempt/2: $YamlFile" `
            -Command "import $YamlFile"

        $output = & tessycmd "import" $YamlFile 2>&1
        $exitCode = $LASTEXITCODE

        if($output)
        {
            $output | ForEach-Object {
                Write-Host "  [tessycmd] $_" -ForegroundColor Gray
            }
        }
        else
        {
            Write-Host "  [tessycmd] (no output)" -ForegroundColor DarkGray
        }

        Write-Info -Step $Step -Message "Import attempt $attempt exit code: $exitCode"

        if($attempt -eq 1)
        {
            Start-Sleep -Seconds $DelaySeconds
        }
    }

    if($exitCode -eq 0)
    {
        Write-Info -Step $Step -Message "Stub configuration imported successfully."
    }
    else
    {
        Write-WarningLog `
            -Step $Step `
            -Message "Final YAML import returned exit code $exitCode; continue pipeline." `
            -Command "import $YamlFile" `
            -ExitCode $exitCode

        $global:LASTEXITCODE = 0
    }
}

function Get-TessyArrayDimension
{
    param([string]$Declaration)

    if($Declaration -match '\[(\d+)\]')
    {
        return [int]$Matches[1]
    }

    return 0
}

function Format-TessyVariableHierarchy
{
    param(
        $Variable,
        [int]$IndentLevel = 0
    )

    $indent = '    ' * $IndentLevel
    $output = "$indent$($Variable.Declaration) [Passing: $($Variable.Passing)]"

    if($Variable.ArrayDim -gt 0)
    {
        $output += " [ArrayLength: $($Variable.ArrayDim)]"
    }

    foreach($member in $Variable.Members)
    {
        $output += "`n" + (Format-TessyVariableHierarchy `
            -Variable $member `
            -IndentLevel ($IndentLevel + 1))
    }

    return $output
}

function Get-TessyHtmlInterfaceRows
{
    param([string]$Section)

    $pattern = @'
<tr[^>]*>.*?<div\s+class="style_59"\s+style="\s*margin-left:\s*(\d+)pt;">([^<]+)</div>.*?</td>.*?<td[^>]*>.*?<div\s+class="style_59">([^<]*)</div>
'@

    return [regex]::Matches(
        $Section,
        $pattern.Trim(),
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )
}

function Get-TessyFunctionsFromHtmlSection
{
    param(
        [string]$HtmlContent,
        [string]$SectionTitle,
        [string[]]$NextSectionTitles
    )

    if([string]::IsNullOrWhiteSpace($HtmlContent) -or
       [string]::IsNullOrWhiteSpace($SectionTitle))
    {
        return @()
    }

    $startPattern = '>' + [regex]::Escape($SectionTitle) + '</div>'
    $startMatch = [regex]::Match(
        $HtmlContent,
        $startPattern,
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    if(-not $startMatch.Success)
    {
        return @()
    }

    $startIndex = $startMatch.Index + $startMatch.Length
    $endIndex = $HtmlContent.Length

    foreach($title in $NextSectionTitles)
    {
        if([string]::IsNullOrWhiteSpace($title)) { continue }

        $nextPattern = '>' + [regex]::Escape($title) + '</div>'
        $nextMatch = [regex]::Match(
            $HtmlContent,
            $nextPattern,
            [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
        )

        if($nextMatch.Success -and
           $nextMatch.Index -gt $startIndex -and
           $nextMatch.Index -lt $endIndex)
        {
            $endIndex = $nextMatch.Index
        }
    }

    if($endIndex -le $startIndex)
    {
        return @()
    }

    $section = $HtmlContent.Substring($startIndex, $endIndex - $startIndex)
    $result = @()

    $lineMatches = [regex]::Matches(
        $section,
        '<div[^>]*style="[^"]*margin-left:\s*10pt;?[^"]*"[^>]*>(.*?)</div>',
        [System.Text.RegularExpressions.RegexOptions]::Singleline -bor
        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase
    )

    foreach($lineMatch in $lineMatches)
    {
        $signature = (
            $lineMatch.Groups[1].Value `
                -replace '<br\s*/?>', '' `
                -replace '&#xa0;|&#x20;|&nbsp;', ' ' `
                -replace '\s+', ' '
        ).Trim()

        if($signature -match '^([a-zA-Z_][a-zA-Z0-9_\s\*]+?)\s+([a-zA-Z_][a-zA-Z0-9_]*)\s*\(([^)]*)\)\s*$')
        {
            $returnType = ($Matches[1] -replace '\s+', ' ').Trim()
            $name = $Matches[2].Trim()
            $arguments = ($Matches[3] -replace '\s+', ' ').Trim()
            $result += "$returnType $name($arguments)"
        }
    }

    return @($result | Select-Object -Unique)
}

function Resolve-TessyDetailsReportPath
{
    param(
        [string]$TestObject,
        [string]$PreferredReportDir,
        [string]$OutputDir
    )

    $fileName = "TESSY_DetailsReport_${TestObject}.html"
    $candidates = @()

    if(-not [string]::IsNullOrWhiteSpace($PreferredReportDir))
    {
        $preferred = [System.IO.Path]::GetFullPath($PreferredReportDir)
        $candidates += $preferred

        $preferredParent = Split-Path -Parent $preferred
        if(-not [string]::IsNullOrWhiteSpace($preferredParent))
        {
            $candidates += (Join-Path $preferredParent "report")
            $candidates += (Join-Path $preferredParent "bin\report")
        }
    }

    if(-not [string]::IsNullOrWhiteSpace($OutputDir))
    {
        $normalizedOutput = [System.IO.Path]::GetFullPath($OutputDir)
        $candidates += (Join-Path $normalizedOutput "report")
    }

    if(-not [string]::IsNullOrWhiteSpace($env:TESSY_BIN_DIR))
    {
        $tessyBin = [System.IO.Path]::GetFullPath($env:TESSY_BIN_DIR)
        $candidates += (Join-Path $tessyBin "report")

        $tessyParent = Split-Path -Parent $tessyBin
        if(-not [string]::IsNullOrWhiteSpace($tessyParent))
        {
            $candidates += (Join-Path $tessyParent "report")
        }
    }

    foreach($directory in ($candidates |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        Select-Object -Unique))
    {
        if(-not (Test-Path $directory)) { continue }

        $candidate = Join-Path $directory $fileName
        if(Test-Path $candidate)
        {
            return $candidate
        }
    }

    return $null
}

function ConvertTo-TessyVariableList
{
    param(
        $RowMatches,
        [string]$Label,
        [string]$Step = "STEP2B"
    )

    $list = @()
    $stack = @()
    $typeKeywords = @(
        'void','char','short','int','long','float','double',
        'u8','u16','u32','u64','s8','s16','s32','s64',
        'bool','boolean','uint8_t','uint16_t','uint32_t','uint64_t',
        'int8_t','int16_t','int32_t','int64_t'
    )

    foreach($match in $RowMatches)
    {
        $indentPoint = [int]$match.Groups[1].Value
        $declaration = (
            $match.Groups[2].Value.Trim() `
                -replace '&#xa0;|&#x20;|&nbsp;', ' ' `
                -replace '\s+', ' '
        )

        $passing = if($match.Groups[3].Value.Trim() -ne '')
        {
            $match.Groups[3].Value.Trim()
        }
        else
        {
            'UNKNOWN'
        }

        $level = [int](($indentPoint / 10) - 1)
        $lastWord = ($declaration -split '\s+')[-1]

        if($lastWord -and
           ($typeKeywords -contains $lastWord) -and
           $passing -eq 'OUT')
        {
            Write-WarningLog `
                -Step $Step `
                -Message "Skip return-type row: $declaration [$passing]"
            continue
        }

        if($declaration -match '^\s*(union|struct)\s*$')
        {
            if($level -lt $stack.Count)
            {
                $stack = @($stack[0..$level])
            }

            $proxy = @{
                Declaration = $declaration
                Passing = $passing
                ArrayDim = 0
                IsStruct = $true
                IsUnion = ($declaration -match '^union')
                IsAnonymous = $true
                Members = @()
                IndentLevel = $level
            }

            if($level -ge $stack.Count) { $stack += $proxy }
            else { $stack[$level] = $proxy }

            continue
        }

        $variable = @{
            Declaration = $declaration
            Passing = $passing
            ArrayDim = Get-TessyArrayDimension $declaration
            IsStruct = ($declaration -match '^struct\s+') -or
                       ($declaration -match '^union\s+')
            IsUnion = $declaration -match '^union\s+'
            Members = @()
            IndentLevel = $level
        }

        if($level -lt $stack.Count)
        {
            $stack = @($stack[0..$level])
        }

        $effectiveLevel = $level

        while($effectiveLevel -gt 0 -and
              $stack.Count -ge $effectiveLevel -and
              $stack[$effectiveLevel - 1].ContainsKey('IsAnonymous') -and
              $stack[$effectiveLevel - 1].IsAnonymous)
        {
            $effectiveLevel--
        }

        if($effectiveLevel -gt 0 -and $stack.Count -ge $effectiveLevel)
        {
            $stack[$effectiveLevel - 1].Members += $variable
        }
        else
        {
            $list += $variable
        }

        if($variable.IsStruct)
        {
            if($level -ge $stack.Count) { $stack += $variable }
            else { $stack[$level] = $variable }
        }
    }

    return $list
}

function Export-TessyInterfaceInfo
{
    param(
        [string]$Step,
        [string]$TestObject,
        [string]$ReportDir,
        [string]$OutputDir
    )

    $htmlReportPath = Resolve-TessyDetailsReportPath `
        -TestObject $TestObject `
        -PreferredReportDir $ReportDir `
        -OutputDir $OutputDir

    if([string]::IsNullOrWhiteSpace($htmlReportPath) -or
       -not (Test-Path $htmlReportPath))
    {
        Write-ErrorLog `
            -Step $Step `
            -Message "HTML report not found for test object '$TestObject'." `
            -Command "Resolve-TessyDetailsReportPath" `
            -ExitCode 1
        exit 1
    }

    Write-Info -Step $Step -Message "Parse Tessy report: $htmlReportPath"

    $html = Get-Content $htmlReportPath -Raw
    $data = @{
        ExternalFunctions = @()
        LocalFunctions = @()
        ExternalVariables = @()
        GlobalVariables = @()
        Parameters = @()
        ReturnType = ''
    }

    $data.ExternalFunctions = Get-TessyFunctionsFromHtmlSection `
        -HtmlContent $html `
        -SectionTitle 'External Functions' `
        -NextSectionTitles @(
            'Local Functions','External Variables','Static/Global Variables',
            'Global Variables','Parameters','Parameter','Return'
        )

    $data.LocalFunctions = Get-TessyFunctionsFromHtmlSection `
        -HtmlContent $html `
        -SectionTitle 'Local Functions' `
        -NextSectionTitles @(
            'External Variables','Static/Global Variables','Global Variables',
            'Parameters','Parameter','Return'
        )

    $externalPattern = '(?s)>External Variables</div>.*?(<tr[^>]*valign="top"[^>]*>.*?)(?=<tr[^>]*>\s*<td[^>]*>\s*<div[^>]*>(?:Static/Global Variables|Global Variables|Parameters|Parameter|$))'
    if($html -match $externalPattern)
    {
        $rows = Get-TessyHtmlInterfaceRows -Section $Matches[1]
        $variables = ConvertTo-TessyVariableList `
            -RowMatches $rows `
            -Label 'External Variable' `
            -Step $Step

        $seen = @{}
        foreach($variable in $variables)
        {
            $name = if($variable.Declaration -match '\b(\w+)(?:\s*\[|$)')
            {
                $Matches[1]
            }
            else
            {
                $variable.Declaration
            }

            if(-not $seen.ContainsKey($name))
            {
                $seen[$name] = $true
                $data.ExternalVariables += $variable
            }
        }
    }

    $globalPattern = '(?s)>(?:Static/Global Variables|Global Variables)</div>.*?(<tr[^>]*valign="top"[^>]*>.*?)(?=</table>|<tr[^>]*>\s*<td[^>]*>\s*<div[^>]*>(?:Parameters|Parameter|Return))'
    if($html -match $globalPattern)
    {
        $rows = Get-TessyHtmlInterfaceRows -Section $Matches[1]
        $data.GlobalVariables = ConvertTo-TessyVariableList `
            -RowMatches $rows `
            -Label 'Global Variable' `
            -Step $Step
    }

    $parameterPattern = '(?s)>(?:Parameters|Parameter)</div>.*?(<tr[^>]*valign="top"[^>]*>.*?)(?=>Return</div>|<tr\s+class="style_72"|</table>)'
    if($html -match $parameterPattern)
    {
        $rows = Get-TessyHtmlInterfaceRows -Section $Matches[1]
        $data.Parameters = ConvertTo-TessyVariableList `
            -RowMatches $rows `
            -Label 'Parameter' `
            -Step $Step
    }

    $returnPattern = '(?s)>Return</div>.*?(<tr[^>]*valign="top"[^>]*>.*?)(?=<tr\s+class="style_72"|</table>)'
    if($html -match $returnPattern)
    {
        $rows = Get-TessyHtmlInterfaceRows -Section $Matches[1]
        if($rows.Count -gt 0)
        {
            $returnDeclaration = (
                $rows[0].Groups[2].Value.Trim() `
                    -replace '&#xa0;|&#x20;|&nbsp;', ' ' `
                    -replace '\s+', ' '
            )

            $returnPassing = if($rows[0].Groups[3].Value.Trim() -ne '')
            {
                $rows[0].Groups[3].Value.Trim()
            }
            else
            {
                'OUT'
            }

            $data.ReturnType = "$returnDeclaration [Passing: $returnPassing]"
        }
    }

    # XML fallback for global variables. Preserve the original top-level logic.
    if($data.GlobalVariables.Count -eq 0)
    {
        $xmlPath = Join-Path $ReportDir "TESSY_DetailsReport_${TestObject}.xml"

        if(Test-Path $xmlPath)
        {
            Write-WarningLog `
                -Step $Step `
                -Message "No global variables found in HTML; parse XML fallback: $xmlPath"

            $xml = [System.IO.File]::ReadAllText($xmlPath)
            $knownNames = @{}

            foreach($variable in $data.ExternalVariables)
            {
                if($variable.Declaration -match '\b(\w+)\s*(?:\[|$)')
                {
                    $knownNames[$Matches[1]] = $true
                }
            }

            foreach($parameter in $data.Parameters)
            {
                if($parameter.Declaration -match '\b(\w+)\s*(?:\[|$)')
                {
                    $knownNames[$Matches[1]] = $true
                }
            }

            foreach($function in $data.ExternalFunctions)
            {
                if($function -match '\b(\w+)\s*\(')
                {
                    $knownNames[$Matches[1]] = $true
                }
            }

            $elementPattern = '<element\s+indent="(\d+)"\s+kind="interface"\s+name="([^"]+)"(?:[^>]+passing="([^"]+)")?'
            $elements = [regex]::Matches($xml, $elementPattern)
            $globalList = @()
            $stack = @()
            $skipGroup = $false

            foreach($element in $elements)
            {
                $indent = [int]$element.Groups[1].Value
                $name = $element.Groups[2].Value.Trim()
                $passing = if($element.Groups[3].Success -and
                              $element.Groups[3].Value -ne '')
                {
                    $element.Groups[3].Value.Trim()
                }
                else
                {
                    ''
                }

                $variableName = if($name -match '\b(\w+)\s*(?:\[|\(|$)')
                {
                    $Matches[1]
                }
                else
                {
                    $name
                }

                if($indent -eq 1)
                {
                    $stack = @()
                    $skipGroup = $knownNames.ContainsKey($variableName) -or $passing -eq ''

                    if(-not $skipGroup)
                    {
                        $variable = @{
                            Declaration = $name
                            Passing = $passing
                            ArrayDim = Get-TessyArrayDimension $name
                            IsStruct = ($name -match '^struct\s+') -or
                                       ($name -match '^union\s+')
                            IsUnion = $name -match '^union\s+'
                            Members = @()
                            IndentLevel = 0
                        }

                        $globalList += $variable
                        $stack += $variable
                    }
                }
                elseif(-not $skipGroup -and $passing -ne '')
                {
                    while($stack.Count -gt 0 -and
                          $stack[-1].IndentLevel -ge ($indent - 1))
                    {
                        if($stack.Count -eq 1) { $stack = @() }
                        else { $stack = $stack[0..($stack.Count - 2)] }
                    }

                    if($stack.Count -gt 0)
                    {
                        $member = @{
                            Declaration = $name
                            Passing = $passing
                            ArrayDim = Get-TessyArrayDimension $name
                            IsStruct = ($name -match '^struct\s+') -or
                                       ($name -match '^union\s+')
                            IsUnion = $name -match '^union\s+'
                            Members = @()
                            IndentLevel = $indent - 1
                        }

                        $stack[-1].Members += $member
                        $stack += $member
                    }
                }
            }

            $data.GlobalVariables = $globalList
        }
    }

    $unknownPassing = @()

    $data.ExternalVariables | ForEach-Object {
        if($_.Passing -eq 'UNKNOWN')
        {
            $unknownPassing += "External Variable: $($_.Declaration)"
        }
    }

    $data.GlobalVariables | ForEach-Object {
        if($_.Passing -eq 'UNKNOWN')
        {
            $unknownPassing += "Global Variable: $($_.Declaration)"
        }
    }

    $data.Parameters | ForEach-Object {
        if($_.Passing -eq 'UNKNOWN')
        {
            $unknownPassing += "Parameter: $($_.Declaration)"
        }
    }

    if($unknownPassing.Count -gt 0)
    {
        Write-ErrorLog `
            -Step $Step `
            -Message "UNKNOWN passing direction: $($unknownPassing -join '; ')" `
            -Command "Export-TessyInterfaceInfo" `
            -ExitCode 1
        exit 1
    }

    $interfaceFolder = Join-Path $OutputDir "interface"
    if(-not (Test-Path $interfaceFolder))
    {
        New-Item -ItemType Directory -Path $interfaceFolder -Force | Out-Null
    }

    $interfaceFile = Join-Path $interfaceFolder "${TestObject}_interface_info.txt"
    $externalVariablesText = ($data.ExternalVariables | ForEach-Object {
        Format-TessyVariableHierarchy -Variable $_
    }) -join "`n"

    $globalVariablesText = ($data.GlobalVariables | ForEach-Object {
        Format-TessyVariableHierarchy -Variable $_
    }) -join "`n"

    $parametersText = ($data.Parameters | ForEach-Object {
        Format-TessyVariableHierarchy -Variable $_
    }) -join "`n"

    $externalFunctionsText = $data.ExternalFunctions -join "`n"
    $localFunctionsText = $data.LocalFunctions -join "`n"

    $content = @"
================================================================================
TESSY INTERFACE INFORMATION - $TestObject
Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
================================================================================

EXTERNAL FUNCTIONS:
-------------------
$externalFunctionsText

LOCAL FUNCTIONS:
----------------
$localFunctionsText

EXTERNAL VARIABLES:
-------------------
$externalVariablesText

GLOBAL VARIABLES:
-----------------
$globalVariablesText

PARAMETERS:
-----------
$parametersText

RETURN TYPE:
------------
$($data.ReturnType)
================================================================================
"@

    $content | Out-File $interfaceFile -Encoding UTF8

    Write-Info `
        -Step $Step `
        -Message "Interface exported: $interfaceFile. ExternalFunctions=$($data.ExternalFunctions.Count), LocalFunctions=$($data.LocalFunctions.Count), ExternalVariables=$($data.ExternalVariables.Count), GlobalVariables=$($data.GlobalVariables.Count), Parameters=$($data.Parameters.Count)"

    return $interfaceFile
}


function Find-CFunctionDefinitionMatch
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceContent,

        [Parameter(Mandatory = $true)]
        [string]$FunctionName
    )

    $escapedFunctionName = [regex]::Escape($FunctionName)
    $pattern = "(?ms)([a-zA-Z_][a-zA-Z0-9_]*\s*\*?)\s+${escapedFunctionName}\s*\(([^)]*)\)"
    $matches = [regex]::Matches($SourceContent, $pattern)

    foreach($match in $matches)
    {
        $afterMatch = $SourceContent.Substring($match.Index + $match.Length)

        if($afterMatch -match '^\s*(/\*.*?\*/)?\s*\{')
        {
            return $match
        }
    }

    return $null
}

# ----------------------------------------------------------------------------
# Extract Complete C Function Text by Brace Counting
# ----------------------------------------------------------------------------

function Get-CFunctionText
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourceContent,

        [Parameter(Mandatory = $true)]
        $FunctionMatch
    )

    $signatureEnd = $FunctionMatch.Index + $FunctionMatch.Length
    $remainingContent = $SourceContent.Substring($signatureEnd)

    if($remainingContent -notmatch '^\s*(/\*.*?\*/)?\s*\{')
    {
        return $null
    }

    $braceStart = $Matches[0].Length
    $braceDepth = 1
    $index = $braceStart

    while($index -lt $remainingContent.Length -and $braceDepth -gt 0)
    {
        $character = $remainingContent[$index]

        if($character -eq '{')
        {
            $braceDepth++
        }
        elseif($character -eq '}')
        {
            $braceDepth--
        }

        $index++
    }

    if($braceDepth -ne 0)
    {
        return $null
    }

    $length = $signatureEnd + $index - $FunctionMatch.Index
    return $SourceContent.Substring($FunctionMatch.Index, $length)
}

# ----------------------------------------------------------------------------
# Find Function Source and Save Raw Function Code
# ----------------------------------------------------------------------------

function Export-TestObjectFunctionCode
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$Step,

        [Parameter(Mandatory = $true)]
        [string]$TestObject,

        [Parameter(Mandatory = $true)]
        [string]$Module,

        [Parameter(Mandatory = $true)]
        [string]$SourceDir,

        [Parameter(Mandatory = $true)]
        [string]$WorkingDir
    )

    if(-not (Test-Path $SourceDir))
    {
        Write-ErrorLog `
            -Step $Step `
            -Message "Source directory not found: $SourceDir" `
            -Command "Get-ChildItem $SourceDir" `
            -ExitCode 1

        exit 1
    }

    $moduleBase = $Module -replace '\.c$',''
    $sourceFile = Get-ChildItem `
        -Path $SourceDir `
        -Recurse `
        -Filter "${moduleBase}.c" `
        -File `
        -ErrorAction SilentlyContinue |
        Select-Object -First 1

    if(-not $sourceFile)
    {
        Write-ErrorLog `
            -Step $Step `
            -Message "Could not find source file '${moduleBase}.c' in '$SourceDir'." `
            -Command "Get-ChildItem -Recurse -Filter ${moduleBase}.c" `
            -ExitCode 1

        exit 1
    }

    Write-Info -Step $Step -Message "Read module source: $($sourceFile.FullName)"

    $sourceContent = Get-Content $sourceFile.FullName -Raw
    $functionMatch = Find-CFunctionDefinitionMatch `
        -SourceContent $sourceContent `
        -FunctionName $TestObject

    $foundInFile = $sourceFile.FullName

    # Preserve the original fallback: scan every other C source file.
    if(-not $functionMatch)
    {
        Write-Info `
            -Step $Step `
            -Message "Function '$TestObject' not found in '${moduleBase}.c'; scan all C files."

        $allCFiles = Get-ChildItem `
            -Path $SourceDir `
            -Recurse `
            -Filter "*.c" `
            -File `
            -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -ne $sourceFile.FullName }

        foreach($candidateFile in $allCFiles)
        {
            $candidateContent = Get-Content $candidateFile.FullName -Raw
            $candidateMatch = Find-CFunctionDefinitionMatch `
                -SourceContent $candidateContent `
                -FunctionName $TestObject

            if($candidateMatch)
            {
                $functionMatch = $candidateMatch
                $sourceContent = $candidateContent
                $foundInFile = $candidateFile.FullName
                break
            }
        }
    }

    if(-not $functionMatch)
    {
        Write-ErrorLog `
            -Step $Step `
            -Message "Could not find function definition for '$TestObject'." `
            -Command "Find-CFunctionDefinitionMatch" `
            -ExitCode 1

        exit 1
    }

    Write-Info -Step $Step -Message "Function source found: $foundInFile"
    Write-Info `
        -Step $Step `
        -Message "Function position=$($functionMatch.Index); ReturnType=$($functionMatch.Groups[1].Value.Trim()); Parameters=$($functionMatch.Groups[2].Value.Trim())"

    $functionText = Get-CFunctionText `
        -SourceContent $sourceContent `
        -FunctionMatch $functionMatch

    if([string]::IsNullOrWhiteSpace($functionText))
    {
        Write-ErrorLog `
            -Step $Step `
            -Message "Could not extract complete function body for '$TestObject'." `
            -Command "Get-CFunctionText" `
            -ExitCode 1

        exit 1
    }

    $outputDirectory = Join-Path $WorkingDir "testObjectCode"

    if(-not (Test-Path $outputDirectory))
    {
        New-Item `
            -ItemType Directory `
            -Path $outputDirectory `
            -Force | Out-Null
    }

    $outputFile = Join-Path $outputDirectory "${TestObject}.c"
    $functionText | Out-File -FilePath $outputFile -Encoding UTF8

    if(-not (Test-Path $outputFile))
    {
        Write-ErrorLog `
            -Step $Step `
            -Message "Function code output was not created: $outputFile" `
            -Command "Out-File $outputFile" `
            -ExitCode 1

        exit 1
    }

    return [PSCustomObject]@{
        OutputFile = $outputFile
        SourceFile = $foundInFile
        Position = $functionMatch.Index
        ReturnType = $functionMatch.Groups[1].Value.Trim()
        Parameters = $functionMatch.Groups[2].Value.Trim()
    }
}

# ----------------------------------------------------------------------------
# Strip Function Body to Condition-Relevant Code
# ----------------------------------------------------------------------------

function ConvertTo-ConditionRelevantFunction
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$FunctionSignature,

        [AllowEmptyString()]
        [string]$FunctionBody
    )

    # Remove metadata comments and coverage markers.
    $clean = $FunctionBody
    $clean = $clean -replace '(?s)/\*#\[.*?\*/', ''
    $clean = $clean -replace '/\*#\]\s*\*/', ''
    $clean = $clean -replace '/\*[^*]*\bGUID\b[^*]*\*/', ''
    $clean = $clean -replace '/\*\s*PRQA\s+S\s+\d[^*]*\*/', ''
    $clean = $clean -replace '/\*\s*-->DDC=FCT[^*]*\*/', ''
    $clean = $clean -replace '/\*\s*polyspace[^*]*\*/', ''
    $clean = $clean -replace '/\*\s*Metric:[^*]*\*/', ''
    $clean = $clean -replace '//[^\n]*LCOV[^\n]*', ''
    $clean = $clean -replace '/\*[^*]*LCOV[^*]*\*/', ''

    # Collect identifiers used by conditions.
    $conditionVariables = [System.Collections.Generic.HashSet[string]]::new()

    foreach($match in [regex]::Matches(
        $clean,
        '\bif\s*\(((?:[^()]+|\([^()]*\))*)\)'
    ))
    {
        foreach($identifier in [regex]::Matches(
            $match.Groups[1].Value,
            '\b([a-zA-Z_]\w*)\b'
        ))
        {
            [void]$conditionVariables.Add($identifier.Groups[1].Value)
        }
    }

    foreach($match in [regex]::Matches(
        $clean,
        '\bwhile\s*\(((?:[^()]+|\([^()]*\))*)\)'
    ))
    {
        foreach($identifier in [regex]::Matches(
            $match.Groups[1].Value,
            '\b([a-zA-Z_]\w*)\b'
        ))
        {
            [void]$conditionVariables.Add($identifier.Groups[1].Value)
        }
    }

    foreach($match in [regex]::Matches($clean, '\bswitch\s*\(([^)]+)\)'))
    {
        foreach($identifier in [regex]::Matches(
            $match.Groups[1].Value,
            '\b([a-zA-Z_]\w*)\b'
        ))
        {
            [void]$conditionVariables.Add($identifier.Groups[1].Value)
        }
    }

    $keywords = @(
        'if','else','while','for','do','switch','case','default','break',
        'continue','return','NULL','TRUE','FALSE','void','u8','u16','u32',
        'u64','s8','s16','s32','boolean_t','int','char','static','const',
        'unsigned','signed','sizeof','0U','1U','0','1'
    )

    foreach($keyword in $keywords)
    {
        [void]$conditionVariables.Remove($keyword)
    }

    # Join C physical lines ending with a backslash.
    $clean = [regex]::Replace($clean, '\\\s*\r?\n\s*', ' ')

    $lines = $clean -split "`r?`n"
    $resultLines = @()
    $braceDepth = 0

    $isReferencedLater = {
        param(
            [string]$VariableName,
            [int]$CurrentLineIndex
        )

        $escapedName = [regex]::Escape($VariableName)

        for($scanIndex = $CurrentLineIndex + 1;
            $scanIndex -lt $lines.Count;
            $scanIndex++)
        {
            $scanLine = $lines[$scanIndex].Trim()

            if(-not $scanLine) { continue }

            if($scanLine -match '^(if|else(\s+if)?|switch|while|for)\b' -and
               $scanLine -match "\b$escapedName\b")
            {
                return $true
            }
        }

        return $false
    }

    for($lineIndex = 0; $lineIndex -lt $lines.Count; $lineIndex++)
    {
        $rawLine = $lines[$lineIndex]
        $trimmed = $rawLine.Trim()

        if($trimmed -eq '')
        {
            $resultLines += ''
            continue
        }

        if($trimmed -match '^/\*\s*\*/\s*$' -or
           $trimmed -match '^//' -or
           $trimmed -match '^/\*[^*]*\*/\s*$')
        {
            continue
        }

        if($trimmed -match '^(if|else(\s+if)?|switch|while|do|for)\b')
        {
            $resultLines += $rawLine

            $openCount = ($rawLine.ToCharArray() |
                Where-Object { $_ -eq '(' } |
                Measure-Object).Count

            $closeCount = ($rawLine.ToCharArray() |
                Where-Object { $_ -eq ')' } |
                Measure-Object).Count

            while($openCount -gt $closeCount -and
                  ($lineIndex + 1) -lt $lines.Count)
            {
                $lineIndex++
                $continuation = $lines[$lineIndex]
                $resultLines += $continuation

                $openCount += ($continuation.ToCharArray() |
                    Where-Object { $_ -eq '(' } |
                    Measure-Object).Count

                $closeCount += ($continuation.ToCharArray() |
                    Where-Object { $_ -eq ')' } |
                    Measure-Object).Count
            }

            continue
        }

        if($trimmed -match '^case[\s(]' -or
           $trimmed -match '^default\s*:')
        {
            $resultLines += $rawLine
            continue
        }

        if($trimmed -match '^(break|continue)\s*;')
        {
            $resultLines += $rawLine
            continue
        }

        # Return statements intentionally remain excluded, matching Step 04.
        if($trimmed -eq '{')
        {
            $resultLines += $rawLine
            $braceDepth++
            continue
        }

        if($trimmed -eq '}')
        {
            $braceDepth--
            $resultLines += $rawLine
            continue
        }

        $keepLine = $false

        foreach($variableName in $conditionVariables)
        {
            $escapedName = [regex]::Escape($variableName)
            $isConditionInput = $false

            if($trimmed -match "(?:[\w\s\*]+)\s*\*?$escapedName\s*[=;]")
            {
                $isConditionInput = $true
            }
            elseif($trimmed -match "^$escapedName\s*[\[=]")
            {
                $isConditionInput = $true
            }
            elseif($trimmed -match "^$escapedName\s*(\+\+|--|[+\-\*/%&|^]=)")
            {
                $isConditionInput = $true
            }
            elseif($trimmed -match "^(\+\+|--)\s*$escapedName\b")
            {
                $isConditionInput = $true
            }
            elseif($trimmed -match "^$escapedName\s*[.\-]")
            {
                $isConditionInput = $true
            }

            if(-not $isConditionInput) { continue }

            if($braceDepth -eq 0 -or
               (& $isReferencedLater $variableName $lineIndex))
            {
                $keepLine = $true
                break
            }
        }

        if($keepLine)
        {
            $resultLines += $rawLine
        }
    }

    # Collapse consecutive blank lines.
    $finalLines = @()
    $previousBlank = $false

    foreach($line in $resultLines)
    {
        $isBlank = $line.Trim() -eq ''

        if($isBlank -and $previousBlank) { continue }

        $finalLines += $line
        $previousBlank = $isBlank
    }

    $strippedBody = ($finalLines -join "`n").Trim()
    return ($FunctionSignature + "`n{`n" + $strippedBody + "`n}`n")
}

# ----------------------------------------------------------------------------
# Parse Raw Function Text into Signature and Body
# ----------------------------------------------------------------------------

function Split-CFunctionText
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$FunctionText
    )

    $signatureMatch = [regex]::Match(
        $FunctionText,
        '(?ms)^(.+?\))\s*(?:/\*[^*]*\*/)?\s*\{'
    )

    if(-not $signatureMatch.Success)
    {
        return $null
    }

    $bodyMatch = [regex]::Match(
        $FunctionText,
        '(?ms)\{(.*)\}',
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )

    return [PSCustomObject]@{
        Signature = $signatureMatch.Groups[1].Value.Trim()
        Body = if($bodyMatch.Success) { $bodyMatch.Groups[1].Value } else { '' }
    }
}

# ----------------------------------------------------------------------------
# Create Condition-Relevant Test Object Source
# ----------------------------------------------------------------------------

function Export-TestObjectConditionCode
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$Step,

        [Parameter(Mandatory = $true)]
        [string]$TestObject,

        [Parameter(Mandatory = $true)]
        [string]$Module,

        [Parameter(Mandatory = $true)]
        [string]$SourceDir,

        [Parameter(Mandatory = $true)]
        [string]$WorkingDir
    )

    $codeDirectory = Join-Path $WorkingDir 'testObjectCode'
    $rawFunctionFile = Join-Path $codeDirectory "${TestObject}.c"

    if(Test-Path $rawFunctionFile)
    {
        Write-Info `
            -Step $Step `
            -Message "Use Step 03 function source: $rawFunctionFile"
    }
    else
    {
        Write-Info `
            -Step $Step `
            -Message "Step 03 output is missing; extract function directly from source."

        # Reuse the Step 03 API and preserve its module-first/all-C-files fallback.
        $extraction = Export-TestObjectFunctionCode `
            -Step $Step `
            -TestObject $TestObject `
            -Module $Module `
            -SourceDir $SourceDir `
            -WorkingDir $WorkingDir

        $rawFunctionFile = $extraction.OutputFile
    }

    if(-not (Test-Path $rawFunctionFile))
    {
        Write-ErrorLog `
            -Step $Step `
            -Message "Raw function source not found: $rawFunctionFile" `
            -Command "Get-Content $rawFunctionFile" `
            -ExitCode 1

        exit 1
    }

    $rawFunctionText = Get-Content $rawFunctionFile -Raw
    $function = Split-CFunctionText -FunctionText $rawFunctionText

    if(-not $function)
    {
        Write-ErrorLog `
            -Step $Step `
            -Message "Could not parse function signature and body: $rawFunctionFile" `
            -Command "Split-CFunctionText" `
            -ExitCode 1

        exit 1
    }

    $strippedText = ConvertTo-ConditionRelevantFunction `
        -FunctionSignature $function.Signature `
        -FunctionBody $function.Body

    if(-not (Test-Path $codeDirectory))
    {
        New-Item `
            -ItemType Directory `
            -Path $codeDirectory `
            -Force | Out-Null
    }

    $outputFile = Join-Path $codeDirectory "${TestObject}_conditions.c"
    $strippedText | Out-File -FilePath $outputFile -Encoding UTF8

    if(-not (Test-Path $outputFile))
    {
        Write-ErrorLog `
            -Step $Step `
            -Message "Condition source file was not created: $outputFile" `
            -Command "Out-File $outputFile" `
            -ExitCode 1

        exit 1
    }

    return [PSCustomObject]@{
        InputFile = $rawFunctionFile
        OutputFile = $outputFile
        Content = $strippedText
    }
}

function Get-TessySourceIndex
{
    param([string]$SourceDir)

    if(-not (Test-Path $SourceDir))
    {
        return @()
    }

    return @(Get-ChildItem `
        -Path $SourceDir `
        -Recurse `
        -Include '*.h','*.c' `
        -File `
        -ErrorAction SilentlyContinue)
}

function Get-TessyCachedSourceContent
{
    param(
        [string]$Path,
        [hashtable]$Cache
    )

    if(-not $Cache.ContainsKey($Path))
    {
        $Cache[$Path] = Get-Content $Path -Raw -ErrorAction SilentlyContinue
    }

    return $Cache[$Path]
}

function Find-TessyDefineLine
{
    param(
        [string]$Token,
        [object[]]$SourceFiles,
        [hashtable]$Cache
    )

    $escapedToken = [regex]::Escape($Token)

    foreach($sourceFile in $SourceFiles)
    {
        $content = Get-TessyCachedSourceContent -Path $sourceFile.FullName -Cache $Cache
        if(-not $content) { continue }

        if($content -match "(?m)^\s*(#\s*define\s+$escapedToken\b[^\r\n]*)")
        {
            return $Matches[1].Trim()
        }
    }

    return $null
}

function Get-TessyBracedBlockEnd
{
    param(
        [string]$Content,
        [int]$OpenBraceIndex
    )

    $depth = 1
    $index = $OpenBraceIndex + 1

    while($index -lt $Content.Length -and $depth -gt 0)
    {
        if($Content[$index] -eq '{') { $depth++ }
        elseif($Content[$index] -eq '}') { $depth-- }
        $index++
    }

    if($depth -ne 0) { return -1 }
    return $index
}

function Find-TessyTypeBlock
{
    param(
        [string]$TypeName,
        [object[]]$SourceFiles,
        [hashtable]$Cache,
        [string]$ModuleFile = ''
    )

    $escapedType = [regex]::Escape($TypeName)
    $files = @($SourceFiles | Where-Object { $_.Extension -eq '.h' })

    if($ModuleFile -and (Test-Path $ModuleFile))
    {
        $files += Get-Item $ModuleFile
    }

    foreach($sourceFile in $files)
    {
        $content = Get-TessyCachedSourceContent -Path $sourceFile.FullName -Cache $Cache
        if(-not $content -or $content -notmatch "\b$escapedType\b") { continue }

        foreach($match in [regex]::Matches(
            $content,
            '(?ms)typedef\s+(?:enum|struct|union)\b[^\{]*\{'
        ))
        {
            $openBrace = $content.IndexOf('{', $match.Index)
            $endBrace = Get-TessyBracedBlockEnd -Content $content -OpenBraceIndex $openBrace
            if($endBrace -lt 0) { continue }

            $tail = $content.Substring(
                $endBrace,
                [Math]::Min(100, $content.Length - $endBrace)
            )

            if($tail -match "^\s*$escapedType\s*;")
            {
                $semicolon = $tail.IndexOf(';')
                return $content.Substring(
                    $match.Index,
                    $endBrace + $semicolon + 1 - $match.Index
                ).Trim()
            }
        }

        foreach($match in [regex]::Matches(
            $content,
            "(?ms)enum\s+$escapedType\s*\{"
        ))
        {
            $openBrace = $content.IndexOf('{', $match.Index)
            $endBrace = Get-TessyBracedBlockEnd -Content $content -OpenBraceIndex $openBrace
            if($endBrace -lt 0) { continue }

            $tail = $content.Substring(
                $endBrace,
                [Math]::Min(20, $content.Length - $endBrace)
            )

            if($tail -match '^\s*;')
            {
                return $content.Substring(
                    $match.Index,
                    $endBrace + $tail.IndexOf(';') + 1 - $match.Index
                ).Trim()
            }
        }
    }

    return $null
}

function Remove-TessyTypeNoise
{
    param([string]$Block)

    $clean = $Block
    $clean = $clean -replace '/\*\s*PRQA\s+S\s+\d[^*]*\*/', ''
    $clean = $clean -replace '/\*##[^*]*\*/', ''
    $clean = $clean -replace '(?s)/\*\*.*?\*/', ''
    $clean = $clean -replace '/\*\s*polyspace[^*]*\*/', ''
    $clean = $clean -replace '/\*\s*LCOV_EXCL[^*]*\*/', ''
    $clean = $clean -replace '/\*\s*-->DDC=FCT[^*]*\*/', ''

    return (($clean -split "`r?`n") |
        Where-Object { $_.Trim() -ne '' }) -join "`n"
}

function Remove-CSourceComments
{
    param([string]$Text)

    $clean = [regex]::Replace(
        $Text,
        '/\*.*?\*/',
        '',
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )

    $clean = [regex]::Replace($clean, '//[^\r\n]*', '')

    return (($clean -split "`r?`n") |
        Where-Object { $_.Trim() -ne '' }) -join "`n"
}

function Find-TessyConstVariableBlock
{
    param(
        [string]$VariableName,
        [object[]]$SourceFiles,
        [hashtable]$Cache
    )

    $escapedName = [regex]::Escape($VariableName)

    foreach($sourceFile in $SourceFiles)
    {
        $content = Get-TessyCachedSourceContent -Path $sourceFile.FullName -Cache $Cache
        if(-not $content -or
           $content -notmatch '\bconst\b' -or
           $content -notmatch "\b$escapedName\b")
        {
            continue
        }

        $declaration = [regex]::Match(
            $content,
            "(?m)^[^\r\n]*\bconst\b[^\r\n]*\b$escapedName\b[^\r\n]*"
        )

        if(-not $declaration.Success) { continue }

        $start = $declaration.Index
        $afterDeclaration = $declaration.Index + $declaration.Length
        $lookAhead = $content.Substring(
            $afterDeclaration,
            [Math]::Min(300, $content.Length - $afterDeclaration)
        )

        $braceRelative = $lookAhead.IndexOf('{')
        $semicolonRelative = $lookAhead.IndexOf(';')

        if($braceRelative -lt 0 -or
           ($semicolonRelative -ge 0 -and $semicolonRelative -lt $braceRelative))
        {
            if($semicolonRelative -ge 0 -and
               $lookAhead.Substring(0, $semicolonRelative) -match '=')
            {
                return $content.Substring(
                    $start,
                    $afterDeclaration - $start + $semicolonRelative + 1
                ).Trim()
            }

            continue
        }

        $openBrace = $afterDeclaration + $braceRelative
        $endBrace = Get-TessyBracedBlockEnd `
            -Content $content `
            -OpenBraceIndex $openBrace

        if($endBrace -lt 0) { continue }

        $tail = $content.Substring(
            $endBrace,
            [Math]::Min(20, $content.Length - $endBrace)
        )

        if($tail -match '^\s*;')
        {
            return $content.Substring(
                $start,
                $endBrace + $tail.IndexOf(';') + 1 - $start
            ).Trim()
        }
    }

    return $null
}

function Get-TessyReferencedTypeNames
{
    param(
        [string]$InterfaceText,
        [string]$ConditionText,
        [string[]]$ConditionLines
    )

    $types = [System.Collections.Generic.HashSet[string]]::new()

    if($InterfaceText)
    {
        $inFunctionSection = $false
        $inVariableSection = $false

        foreach($line in ($InterfaceText -split "`r?`n"))
        {
            if($line -match '^\s*(?:EXTERNAL|LOCAL) FUNCTIONS:')
            {
                $inFunctionSection = $true
                $inVariableSection = $false
                continue
            }

            if($line -match '^\s*(?:EXTERNAL VARIABLES|GLOBAL VARIABLES|PARAMETERS|RETURN TYPE):')
            {
                $inFunctionSection = $false
                $inVariableSection = $true
                continue
            }

            if($inVariableSection)
            {
                if($line -notmatch '\[Passing:\s*(?:IN(?:/OUT)?|INOUT|OUT)\]')
                {
                    continue
                }
            }

            if($inFunctionSection -and
               $line -match '(?:void|[\w\*]+)\s+(\w+)\s*\(')
            {
                $functionName = $Matches[1]
                if($ConditionText -notmatch "\b$([regex]::Escape($functionName))\b")
                {
                    continue
                }
            }

            foreach($match in [regex]::Matches(
                $line,
                '\b(?:enum|union|struct)\s+(\w+)'
            ))
            {
                [void]$types.Add($match.Groups[1].Value)
            }
        }
    }

    $primitives = @(
        'void','u8','u16','u32','u64','s8','s16','s32','int','char',
        'unsigned','signed','float','double','long','short','static',
        'const','boolean_t'
    )

    foreach($match in [regex]::Matches(
        $ConditionText,
        '\b([a-z]\w+_(?:t|un|en))\b'
    ))
    {
        if($match.Groups[1].Value -notin $primitives)
        {
            [void]$types.Add($match.Groups[1].Value)
        }
    }

    foreach($line in $ConditionLines)
    {
        $cleanLine = $line.Trim() -replace `
            '^((?:static|extern|volatile|const|register)\s+)+', ''

        $declaration = [regex]::Match(
            $cleanLine,
            '^([a-zA-Z_]\w+)\s+\w+\s*[=;\[]'
        )

        if($declaration.Success)
        {
            $typeName = $declaration.Groups[1].Value
            if($typeName -notin $primitives -and $typeName -notmatch '^[A-Z_]+$')
            {
                [void]$types.Add($typeName)
            }
        }
    }

    return @($types)
}

function Get-TessyMacroDefinitions
{
    param(
        [string]$ConditionText,
        [object[]]$SourceFiles,
        [hashtable]$Cache
    )

    $definitions = [ordered]@{}

    foreach($match in [regex]::Matches(
        $ConditionText,
        '\b([a-z][a-zA-Z0-9_]*)\s*\('
    ))
    {
        $name = $match.Groups[1].Value
        if($definitions.Contains($name)) { continue }

        $escapedName = [regex]::Escape($name)

        foreach($sourceFile in ($SourceFiles | Where-Object { $_.Extension -eq '.h' }))
        {
            $content = Get-TessyCachedSourceContent `
                -Path $sourceFile.FullName `
                -Cache $Cache

            if(-not $content) { continue }

            $definition = [regex]::Match(
                $content,
                "(?m)^\s*#\s*define\s+$escapedName\s*\([^\r\n]*"
            )

            if($definition.Success)
            {
                $definitions[$name] = $definition.Value.Trim()

                # Preserve the related cfgRomContainer macro definition.
                if($definition.Value -match '(cfgRomContainerMacro\w+)')
                {
                    $containerName = $Matches[1]
                    $escapedContainer = [regex]::Escape($containerName)
                    $containerDefinition = [regex]::Match(
                        $content,
                        "(?m)^\s*#\s*define\s+$escapedContainer\s*\([^\r\n]*"
                    )

                    if($containerDefinition.Success -and
                       -not $definitions.Contains($containerName))
                    {
                        $definitions[$containerName] = $containerDefinition.Value.Trim()
                    }
                }

                break
            }
        }
    }

    return $definitions
}

function Export-AnnotatedConditionCode
{
    param(
        [string]$Step,
        [string]$TestObject,
        [string]$Module,
        [string]$SourceDir,
        [string]$WorkingDir
    )

    $conditionFile = Join-Path `
        $WorkingDir `
        "testObjectCode\${TestObject}_conditions.c"

    $interfaceFile = Join-Path `
        $WorkingDir `
        "interface\${TestObject}_interface_info.txt"

    if(-not (Test-Path $conditionFile))
    {
        Write-ErrorLog `
            -Step $Step `
            -Message "Conditions file not found: $conditionFile. Run Step 04 first." `
            -Command "Get-Content $conditionFile" `
            -ExitCode 1
        exit 1
    }

    $conditionLines = @(Get-Content $conditionFile)
    $conditionText = $conditionLines -join "`n"
    $interfaceText = if(Test-Path $interfaceFile)
    {
        Get-Content $interfaceFile -Raw
    }
    else
    {
        Write-WarningLog `
            -Step $Step `
            -Message "Interface information not found: $interfaceFile"
        ''
    }

    $sourceFiles = Get-TessySourceIndex -SourceDir $SourceDir
    $cache = @{}

    $moduleFilter = if($Module -match '\.c$') { $Module } else { "$Module.c" }
    $moduleFile = Get-ChildItem `
        -Path $SourceDir `
        -Recurse `
        -Filter $moduleFilter `
        -File `
        -ErrorAction SilentlyContinue |
        Select-Object -First 1

    $modulePath = if($moduleFile) { $moduleFile.FullName } else { '' }

    $typeNames = Get-TessyReferencedTypeNames `
        -InterfaceText $interfaceText `
        -ConditionText $conditionText `
        -ConditionLines $conditionLines

    $typeBlocks = [ordered]@{}
    foreach($typeName in ($typeNames | Sort-Object))
    {
        $block = Find-TessyTypeBlock `
            -TypeName $typeName `
            -SourceFiles $sourceFiles `
            -Cache $cache `
            -ModuleFile $modulePath

        if($block)
        {
            $typeBlocks[$typeName] = Remove-TessyTypeNoise -Block $block
        }
    }

    $skipTokens = [System.Collections.Generic.HashSet[string]]@(
        'TRUE','FALSE','NULL','INOUT','IN','OUT','IRRELEVANT','VOID',
        'LCOV_EXCL_BR_LINE'
    )

    $defineLines = [ordered]@{}
    foreach($line in $conditionLines)
    {
        foreach($match in [regex]::Matches($line, '\b([A-Z][A-Z0-9_]{3,})\b'))
        {
            $token = $match.Groups[1].Value
            if($skipTokens.Contains($token) -or $defineLines.Contains($token))
            {
                continue
            }

            $definition = Find-TessyDefineLine `
                -Token $token `
                -SourceFiles $sourceFiles `
                -Cache $cache

            if($definition)
            {
                $defineLines[$token] = $definition
            }
        }
    }

    # Mixed-case enum members and macro constants fallback.
    foreach($match in [regex]::Matches(
        $conditionText,
        '\b([A-Z][a-zA-Z0-9_]+)\b'
    ))
    {
        $token = $match.Groups[1].Value
        if($skipTokens.Contains($token) -or $defineLines.Contains($token))
        {
            continue
        }

        $definition = Find-TessyDefineLine `
            -Token $token `
            -SourceFiles $sourceFiles `
            -Cache $cache

        if($definition)
        {
            $defineLines[$token] = $definition
        }
    }

    $localNames = [System.Collections.Generic.HashSet[string]]::new()
    foreach($line in $conditionLines)
    {
        $signature = [regex]::Match(
            $line.Trim(),
            '^\w[\w\.\*\[\]]*\s+\w+\s*\(([^)]*)\)'
        )

        if($signature.Success)
        {
            foreach($parameter in ($signature.Groups[1].Value -split ','))
            {
                $name = [regex]::Match($parameter.Trim(), '\b(\w+)\s*$')
                if($name.Success) { [void]$localNames.Add($name.Groups[1].Value) }
            }
        }

        $variable = [regex]::Match(
            $line.Trim(),
            '^(?:(?:static|extern|volatile|const)\s+)*[a-zA-Z_]\w*\s+(\w+)\s*[=;]'
        )

        if($variable.Success)
        {
            [void]$localNames.Add($variable.Groups[1].Value)
        }
    }

    $constBlocks = [ordered]@{}
    foreach($match in [regex]::Matches(
        $conditionText,
        '(?<![\.>])\b([a-zA-Z_]\w+)\s*\['
    ))
    {
        $name = $match.Groups[1].Value
        if($localNames.Contains($name) -or $constBlocks.Contains($name))
        {
            continue
        }

        $block = Find-TessyConstVariableBlock `
            -VariableName $name `
            -SourceFiles $sourceFiles `
            -Cache $cache

        if($block)
        {
            $constBlocks[$name] = $block
        }
    }

    $macroDefinitions = Get-TessyMacroDefinitions `
        -ConditionText $conditionText `
        -SourceFiles $sourceFiles `
        -Cache $cache

    $builder = [System.Text.StringBuilder]::new()

    if($interfaceText)
    {
        [void]$builder.AppendLine('/*')
        $skipIndent = -1

        foreach($line in ($interfaceText -split "`r?`n"))
        {
            $indent = 0
            if($line -match '^(\s+)') { $indent = $Matches[1].Length }

            if($skipIndent -ge 0)
            {
                if($indent -gt $skipIndent) { continue }
                $skipIndent = -1
            }

            if($line -match '\[Passing:\s*IRRELEVANT\]')
            {
                $skipIndent = $indent
                continue
            }

            [void]$builder.AppendLine(" * $line")
        }

        [void]$builder.AppendLine(' */')
        [void]$builder.AppendLine()
    }

    foreach($definition in $defineLines.Values)
    {
        [void]$builder.AppendLine(
            ([regex]::Replace($definition, '/\*.*?\*/', '')).TrimEnd()
        )
    }

    if($defineLines.Count -gt 0) { [void]$builder.AppendLine() }

    foreach($block in $typeBlocks.Values)
    {
        [void]$builder.AppendLine()
        [void]$builder.AppendLine((Remove-CSourceComments -Text $block))
    }

    foreach($block in $constBlocks.Values)
    {
        [void]$builder.AppendLine()
        [void]$builder.AppendLine((Remove-CSourceComments -Text $block))
    }

    foreach($definition in $macroDefinitions.Values)
    {
        [void]$builder.AppendLine(
            ([regex]::Replace($definition, '/\*.*?\*/', '')).TrimEnd()
        )
    }

    if($macroDefinitions.Count -gt 0) { [void]$builder.AppendLine() }

    [void]$builder.AppendLine()
    [void]$builder.Append((Remove-CSourceComments -Text $conditionText))

    $outputDirectory = Join-Path $WorkingDir 'testObjectCode'
    if(-not (Test-Path $outputDirectory))
    {
        New-Item -ItemType Directory -Path $outputDirectory -Force | Out-Null
    }

    $outputFile = Join-Path `
        $outputDirectory `
        "${TestObject}_conditions_after_passing.c"

    [System.IO.File]::WriteAllText(
        $outputFile,
        $builder.ToString(),
        [System.Text.Encoding]::UTF8
    )

    if(-not (Test-Path $outputFile))
    {
        Write-ErrorLog `
            -Step $Step `
            -Message "Annotated condition file was not created: $outputFile" `
            -Command "WriteAllText $outputFile" `
            -ExitCode 1
        exit 1
    }

    return [PSCustomObject]@{
        OutputFile = $outputFile
        DefineCount = $defineLines.Count
        TypeCount = $typeBlocks.Count
        ConstCount = $constBlocks.Count
        MacroCount = $macroDefinitions.Count
    }
}

function Test-Step6TestcasePlan
{
    param(
        [Parameter(Mandatory = $true)][string]$JsonFile,
        [switch]$ThrowOnError
    )

    try
    {
        if(-not (Test-Path $JsonFile))
        {
            throw "Testcase plan not found: $JsonFile"
        }

        $plan = Get-Content $JsonFile -Raw -Encoding UTF8 | ConvertFrom-Json

        if([string]::IsNullOrWhiteSpace([string]$plan.FunctionSignature))
        {
            throw "FunctionSignature is missing."
        }

        if($null -eq $plan.TestCases -or @($plan.TestCases).Count -eq 0)
        {
            throw "TestCases is missing or empty."
        }

        $actualCount = @($plan.TestCases).Count
        if([int]$plan.TotalTestCases -ne $actualCount)
        {
            throw "TotalTestCases=$($plan.TotalTestCases), but TestCases.Count=$actualCount."
        }

        $expectedId = 1
        foreach($testCase in @($plan.TestCases))
        {
            if([int]$testCase.TCId -ne $expectedId)
            {
                throw "Expected TCId=$expectedId, found TCId=$($testCase.TCId)."
            }

            foreach($requiredProperty in @('Description','Target','SetValues','StubFunctions'))
            {
                if($testCase.PSObject.Properties.Name -notcontains $requiredProperty)
                {
                    throw "TCId=$expectedId is missing '$requiredProperty'."
                }
            }

            $expectedId++
        }

        return $plan
    }
    catch
    {
        if($ThrowOnError) { throw }
        return $null
    }
}

function New-Step6CopilotPrompt
{
    param(
        [Parameter(Mandatory = $true)][string]$Step,
        [Parameter(Mandatory = $true)][string]$TestObject,
        [Parameter(Mandatory = $true)][string]$WorkingDir,
        [Parameter(Mandatory = $true)][string]$GuideFile,
        [Parameter(Mandatory = $true)][string]$TemplateFile,
        [switch]$Force
    )

    $codeDir = Join-Path $WorkingDir "testObjectCode"
    $jsonDir = Join-Path $WorkingDir "json_testcase"
    $conditionFile = Join-Path $codeDir "${TestObject}_conditions_after_passing.c"
    $jsonFile = Join-Path $jsonDir "${TestObject}_testcase_plan.json"
    $promptFile = Join-Path $codeDir "${TestObject}_step6.prompt.md"

    if((Test-Path $jsonFile) -and -not $Force)
    {
        $existingPlan = Test-Step6TestcasePlan -JsonFile $jsonFile -ThrowOnError

        return [PSCustomObject]@{
            Status = "EXISTS"
            PromptFile = $promptFile
            JsonFile = $jsonFile
            TotalTestCases = $existingPlan.TotalTestCases
        }
    }

    foreach($inputFile in @($conditionFile, $GuideFile, $TemplateFile))
    {
        if(-not (Test-Path $inputFile))
        {
            Write-ErrorLog `
                -Step $Step `
                -Message "Required Step 06 input not found: $inputFile" `
                -Command "Test-Path $inputFile" `
                -ExitCode 1
            exit 1
        }
    }

    foreach($directory in @($codeDir, $jsonDir))
    {
        if(-not (Test-Path $directory))
        {
            New-Item -ItemType Directory -Path $directory -Force | Out-Null
        }
    }

    $guide = Get-Content $GuideFile -Raw -Encoding UTF8
    $conditionSource = Get-Content $conditionFile -Raw -Encoding UTF8
    $template = Get-Content $TemplateFile -Raw -Encoding UTF8

    $relativeConditionPath = "testObjectCode\${TestObject}_conditions_after_passing.c"
    $relativeJsonPath = "json_testcase\${TestObject}_testcase_plan.json"

    $prompt = $template
    $prompt = $prompt.Replace('{{TEST_OBJECT}}', $TestObject)
    $prompt = $prompt.Replace('{{CONDITION_FILE_PATH}}', $relativeConditionPath)
    $prompt = $prompt.Replace('{{OUTPUT_JSON_PATH}}', $relativeJsonPath)
    $prompt = $prompt.Replace('{{GENERATION_GUIDE}}', $guide)
    $prompt = $prompt.Replace('{{CONDITION_SOURCE}}', $conditionSource)

    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($promptFile, $prompt, $utf8NoBom)

    if(-not (Test-Path $promptFile))
    {
        Write-ErrorLog `
            -Step $Step `
            -Message "Step 06 prompt was not created: $promptFile" `
            -Command "WriteAllText $promptFile" `
            -ExitCode 1
        exit 1
    }

    return [PSCustomObject]@{
        Status = "PROMPT_CREATED"
        PromptFile = $promptFile
        JsonFile = $jsonFile
        TotalTestCases = 0
    }
}

function Wait-Step6TestcasePlan
{
    param(
        [Parameter(Mandatory = $true)][string]$Step,
        [Parameter(Mandatory = $true)][string]$JsonFile,
        [ValidateRange(1, 120)][int]$TimeoutMinutes = 10,
        [ValidateRange(1, 60)][int]$PollSeconds = 5
    )

    $deadline = (Get-Date).AddMinutes($TimeoutMinutes)

    Write-Info `
        -Step $Step `
        -Message "Wait for testcase plan: $JsonFile; Timeout=${TimeoutMinutes}min; Poll=${PollSeconds}s"

    while((Get-Date) -lt $deadline)
    {
        if(Test-Path $JsonFile)
        {
            $plan = Test-Step6TestcasePlan -JsonFile $JsonFile
            if($plan) { return $plan }

            Write-WarningLog `
                -Step $Step `
                -Message "Testcase plan exists but is not complete or valid yet: $JsonFile"
        }

        Start-Sleep -Seconds $PollSeconds
    }

    Write-ErrorLog `
        -Step $Step `
        -Message "Timeout waiting for a valid testcase plan: $JsonFile" `
        -Command "Wait-Step6TestcasePlan" `
        -ExitCode 1
    exit 1
}

function Get-ObjectPropertyValue {
    param(
        [Parameter(Mandatory)]$InputObject,
        [Parameter(Mandatory)][string[]]$Names
    )

    foreach ($name in $Names) {
        if ($InputObject.PSObject.Properties.Name -contains $name) {
            return $InputObject.$name
        }
    }
    return $null
}

function ConvertTo-FunctionInfo {
    param(
        [Parameter(Mandatory)]$InputObject,
        [string]$FallbackName = ''
    )

    $name = [string](Get-ObjectPropertyValue $InputObject @('Name'))
    if ([string]::IsNullOrWhiteSpace($name)) { $name = $FallbackName }

    $returnType = [string](Get-ObjectPropertyValue $InputObject @('ReturnType'))
    if ([string]::IsNullOrWhiteSpace($returnType)) { $returnType = 'int' }

    $parameters = [string](Get-ObjectPropertyValue $InputObject @('Parameters'))
    if ([string]::IsNullOrWhiteSpace($parameters)) { $parameters = 'void' }

    [PSCustomObject]@{
        Name       = $name.Trim()
        ReturnType = $returnType.Trim()
        Parameters = $parameters.Trim()
    }
}

function ConvertTo-NormalizedReturnValue {
    param(
        [string]$ReturnType,
        [AllowNull()][string]$Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $result = (($Value -replace '^\s*return\s+', '') -replace ';\s*$', '').Trim()

    if ($ReturnType -match '\b(bool|boolean_t)\b') {
        if ($result -match '^(?i:true|1(?:U|UL|L)?)$')  { return '1' }
        if ($result -match '^(?i:false|0(?:U|UL|L)?)$') { return '0' }
    }
    return $result
}

function Invoke-TessyCommand {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [string]$FailureMessage = 'Tessy command failed.',
        [switch]$ShowOutput,
        [switch]$AllowFailure
    )

    $output = & $Executable @Arguments 2>&1
    $exitCode = $LASTEXITCODE

    if ($ShowOutput -and $output) {
        $output | ForEach-Object { Write-Host $_ }
    }

    if ($exitCode -ne 0 -and -not $AllowFailure) {
        throw "$FailureMessage ExitCode=$exitCode; Command=$Executable $($Arguments -join ' ')"
    }

    return [PSCustomObject]@{
        ExitCode = $exitCode
        Output   = @($output)
    }
}

function Select-TessyContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][string]$Project,
        [Parameter(Mandatory = $true)][string]$TestCollection,
        [AllowEmptyString()][string]$Folder = '',
        [Parameter(Mandatory = $true)][string]$Module,
        [Parameter(Mandatory = $true)][string]$TestObject
    )

    Invoke-TessyCommand $Executable @('select-project', $Project) `
        "Cannot select Tessy project '$Project'." | Out-Null

    Invoke-TessyCommand $Executable @('select-test-collection', $TestCollection) `
        "Cannot select test collection '$TestCollection'." | Out-Null

    $folderParts = @($Folder -split '[/\\]' | Where-Object { $_ })
    for ($index = 0; $index -lt $folderParts.Count; $index++) {
        $arguments = if ($index -eq 0) {
            @('select-folder', '-collection', $folderParts[$index])
        } else {
            @('select-folder', $folderParts[$index])
        }

        Invoke-TessyCommand $Executable $arguments `
            "Cannot select folder '$($folderParts[$index])' from '$Folder'." | Out-Null
    }

    $moduleName = $Module -replace '\.c$', ''
    $arguments = if ($folderParts.Count -gt 0) {
        @('select-module', $Module)
    } else {
        @('select-module', '-c', $Module)
    }

    $moduleResult = Invoke-TessyCommand $Executable $arguments `
        "Cannot select module '$Module'." -AllowFailure

    if ($moduleResult.ExitCode -ne 0) {
        $fallbackArguments = if ($folderParts.Count -gt 0) {
            @('select-module', $moduleName)
        } else {
            @('select-module', '-c', $moduleName)
        }

        Invoke-TessyCommand $Executable $fallbackArguments `
            "Cannot select module '$Module' or '$moduleName'." | Out-Null
    }

    Invoke-TessyCommand $Executable @('select-test-object', $TestObject) `
        "Cannot select test object '$TestObject'." | Out-Null
}

function Assert-RequiredFiles {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string[]]$Paths)

    foreach ($path in $Paths) {
        if (-not (Test-Path $path)) {
            throw "Required file not found: $path"
        }
    }
}


function Find-FirstExistingPath {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string[]]$Paths)

    foreach ($path in $Paths) {
        if ($path -and (Test-Path $path)) { return $path }
    }
    return $null
}

function Get-RegexGroupValue {
    [CmdletBinding()]
    param(
        [AllowEmptyString()][string]$Text,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [int]$Group = 1,
        [System.Text.RegularExpressions.RegexOptions]$Options =
            [System.Text.RegularExpressions.RegexOptions]::Singleline
    )

    if ([string]::IsNullOrEmpty($Text)) { return $null }
    $match = [regex]::Match($Text, $Pattern, $Options)
    if ($match.Success) { return $match.Groups[$Group].Value }
    return $null
}

function Write-Utf8NoBom {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
    )

    $parent = Split-Path -Parent $Path
    if ($parent -and -not (Test-Path $parent)) {
        New-Item $parent -ItemType Directory -Force | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
}

function Get-ConfigSetting {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$ConfigObject,
        [Parameter(Mandatory = $true)][string]$Name,
        $DefaultValue = $null
    )

    if ($ConfigObject -is [System.Collections.IDictionary]) {
        if ($ConfigObject.Contains($Name)) { return $ConfigObject[$Name] }
        return $DefaultValue
    }

    if ($ConfigObject.PSObject.Properties.Name -contains $Name) {
        return $ConfigObject.$Name
    }

    return $DefaultValue
}

function Read-JsonFile {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path $Path)) {
        throw "JSON file not found: $Path"
    }

    try {
        return Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        throw "Invalid JSON file '$Path': $($_.Exception.Message)"
    }
}


