[CmdletBinding()]
    Param(
    # e.g. C:\git\h\spec-dev
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$SpecRepoFolder,
    
    # e.g. C:\git\h\sdk-dev
    [Parameter(Mandatory = $true, Position = 1)]
    [string]$SdkRepoFolder,
    
    [Parameter(Mandatory = $false, Position = 2)]
    [string]$MSBuild = "C:\Windows\Microsoft.NET\Framework\v4.0.30319\msbuild.exe"
)

$oldErrorActionPreference = $ErrorActionPreference;

try
{
    $ErrorActionPreference = "Stop";

    $specComponent = 'Compute2';
    $sdkComponent = 'Compute';

    # e.g. C:\git\h\spec-dev\Compute2\Specification
    $destSpecFolder = "$SpecRepoFolder\$specComponent\Specification\";
    $srcSpecFolder = "$PSScriptRoot\$specComponent\Specification\";

    #1 Copy spec files to the target folder
    . $PSScriptRoot\CopyTo-HyakSpecFolder.ps1 -TargetPath $SpecRepoFolder;

    #2 MSBuild the spec project
    if (-not [string]::IsNullOrEmpty($MSBuild))
    {
        $projFile = (Get-Item "$destSpecFolder\Microsoft.Azure.Management.$sdkComponent.Specification.csproj").FullName;
        Write-Verbose "";
        Write-Verbose "==========================================";
        Write-Verbose "Building the spec project file: $projFile...";
        Write-Verbose "==========================================";
        Invoke-Expression -Command "$MSBuild $projFile";
        Write-Verbose "Done...";
    }

    #3 Copy generated code from spec repo to SDK folder
    $generatedFolder = (Get-Item "$destSpecFolder\Generated").FullName;
    $sdkScope = "ResourceManagement\$sdkComponent";
    $sdkCompFolder = "$SdkRepoFolder\src\$sdkScope\";
    $sdkProjFolder = "$sdkCompFolder\${sdkComponent}Management\";
    Write-Verbose "";
    Write-Verbose "==========================================";
    Write-Verbose "Copying the generated code files to $sdkProjFolder ...";
    Write-Verbose "==========================================";
    Remove-Item -Path "$sdkProjFolder\Generated" -Recurse -Force -Confirm:$false -Verbose;
    Copy-Item -Path $generatedFolder -destination $sdkProjFolder -Recurse -Force -Confirm:$false -Verbose;
    Write-Verbose "Done...";

    #4 Copy test code from source repo to SDK folder
    $testName = "$sdkComponent.Tests";
    $srcTestFolder = (Get-Item "$PSScriptRoot\..\$testName\").FullName;
    $dstTestFolder = (Get-Item "$sdkCompFolder\$testName\").FullName;
    Write-Verbose "";
    Write-Verbose "==========================================";
    Write-Verbose "Copying the test code files to $dstTestFolder...";
    Write-Verbose "==========================================";
    $skipFolders = @("bin", "obj", "objd", "Generated");
    foreach ($item in (Get-ChildItem -Path $srcTestFolder))
    {
        if ($skipFolders -icontains $item.Name) { continue; }
        if ($item.Attributes -eq 'Directory')
        {
            $dstItemName = "$dstTestFolder\" + $item.Name;
            if (Test-Path -Path $dstItemName)
            {
                Remove-Item -Path $dstItemName -Recurse -Force -Confirm:$false -Verbose;
                Copy-Item -Path $item.FullName -destination $dstTestFolder -Recurse -Force -Confirm:$false -Verbose;
            }
        }
    }
    Write-Verbose "Done...";

    #5 Build the Client and Test projects
    if (-not [string]::IsNullOrEmpty($MSBuild))
    {
        $sdkProjFile = (Get-Item "$sdkProjFolder\${sdkComponent}Management.csproj").FullName;
        Write-Verbose "";
        Write-Verbose "==========================================";
        Write-Verbose "Building the SDK project file: $sdkProjFile...";
        Write-Verbose "==========================================";
        Invoke-Expression -Command "$MSBuild $sdkProjFile";
        Write-Verbose "Done...";

        $testProjFile = (Get-Item "$dstTestFolder\${testName}.csproj").FullName;
        Write-Verbose "";
        Write-Verbose "==========================================";
        Write-Verbose "Building the Test project file: $testProjFile...";
        Write-Verbose "==========================================";
        Invoke-Expression -Command "$MSBuild $testProjFile";
        Write-Verbose "Done...";
        
        $buildProjFile = (Get-Item "$SdkRepoFolder\build.proj").FullName;
        Write-Verbose "";
        Write-Verbose "==========================================";
        Write-Verbose "Running test cases in the project: $buildProjFile...";
        Write-Verbose "==========================================";
        [Environment]::SetEnvironmentVariable('AZURE_TEST_MODE', 'Playback', 'Process');
        Invoke-Expression -Command "$MSBuild $buildProjFile /t:Build /p:Scope=`"$sdkScope`"";
        Invoke-Expression -Command "$MSBuild $buildProjFile /t:Test /p:Scope=`"$sdkScope`"";
        Write-Verbose "Done...";
    }
}
finally
{
    $ErrorActionPreference = $oldErrorActionPreference;
}
