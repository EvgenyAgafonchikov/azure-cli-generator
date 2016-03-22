[CmdletBinding()]
    Param(
    [Parameter(Mandatory=$True, Position=0)]
    [string]$TargetPath
)


function Remove-ReadOnlyProperty
{
    param([string] $filePath)
    
    Write-Verbose ("Removing 'ReadOnly' from the file: " + $filePath);
    Set-ItemProperty $filePath -Name 'IsReadOnly' -Value $false;
}


$service = 'Compute2';

$srcSpecFolder = "$PSScriptRoot\$service\Specification\";

#e.g. C:\git\h\spec-dev
$repoDest = $TargetPath;

#e.g. C:\git\h\spec-dev\Compute2\*
$serviceDest = ($repoDest + "\$service\*");
$specFolder = $repoDest + "\$service\Specification";

$files = Get-Item -Path $serviceDest | select -ExpandProperty Name;
$check = ($files -contains "Specification");
$check = $check -and ($files.Count -eq 1);
if ($check)
{
    $hyakFilePath = $specFolder + "\hyak.xml";
    $hyakFile = Get-Item -Path $hyakFilePath | select -ExpandProperty Name;
    $check = $check -and ($hyakFile.Count -eq 1);
}

if (-not $check)
{
    $errMsg =  "Make sure '$serviceDest' hosts only the 'Specification' folder, and it contains the 'hyak.xml' file.";
    Write-Error $errMsg;
}
else
{
    $skipFolders = @("bin", "obj", "objd", "Generated");

    Write-Verbose "==========================================";
    Write-Verbose "Removing all folders from $specFolder ...";
    Write-Verbose "==========================================";
    foreach ($item in (Get-ChildItem -Path $specFolder))
    {
        if ($skipFolders -icontains $item.Name) { continue; }
        if ($item.Attributes -eq 'Directory')
        {
            Write-Verbose ("Removing folder '" + $item.FullName + "'...");
            Remove-Item $item.FullName -Recurse -Force -Confirm:$false;
        }
    }
    Write-Verbose "Done...";
    
    Write-Verbose "";
    Write-Verbose "==========================================";
    Write-Verbose "Copying the folders & files to $specFolder ...";
    Write-Verbose "==========================================";
    foreach ($srcItem in (Get-ChildItem -Path $srcSpecFolder))
    {
        if ($skipFolders -icontains $srcItem.Name) { continue; }
        if ($srcItem.Attributes -eq 'Directory')
        {
            $itemFolder = $srcItem.FullName;
            Write-Verbose "Copying $itemFolder\*.* to $specFolder...";
            Copy-Item -Path $itemFolder -destination $specFolder -Recurse -Force -Confirm:$false;
        }
    }
    Write-Verbose "Done...";

    # Remove read-only flags
    $srcItems = Get-ChildItem -Path $srcSpecFolder;
    $destItems = Get-ChildItem -Path $specFolder;
    Write-Verbose "Clearing read-only flags from the folders and files from $specFolder...";
    foreach ($item in $destItems)
    {
        if ($skipFolders -icontains $srcItem.Name) { continue; }

        $found = $false;
        foreach ($sItem in $srcItems)
        {
            if ($item.Name -eq $sItem.Name)
            {
                $found = $true;
                break;
            }
        }
        
        Write-Verbose "";
        Write-Verbose "==========================================";
        Write-Verbose ($item.FullName + ' found in source folder? ' + $found);
        Write-Verbose "==========================================";
        if ($found)
        {

            if ($item.Attributes -ne 'Directory')
            {
                Remove-ReadOnlyProperty $item.FullName;
            }
            else
            {
                $files = Get-ChildItem -Path $item.FullName -Recurse;
                foreach ($file in $files)
                {
                    if ($file.Attributes -ne 'Directory')
                    {
                        Remove-ReadOnlyProperty $file.FullName;
                    }
                }            
            }
        }
    }
    Write-Verbose "Done...";
}
