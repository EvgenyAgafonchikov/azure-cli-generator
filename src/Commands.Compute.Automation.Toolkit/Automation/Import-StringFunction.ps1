# ----------------------------------------------------------------------------------
#
# Copyright Microsoft Corporation
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ----------------------------------------------------------------------------------

function Get-CamelCaseName
{
    param
    (
        # Sample: 'vmName' => 'VMName', 'resourceGroup' => 'ResourceGroup', etc.
        [Parameter(Mandatory = $true)]
        [string]$inputName,

        [Parameter(Mandatory = $false)]
        [bool]$upperCase = $true
    )

    if ([string]::IsNullOrEmpty($inputName))
    {
        return $inputName;
    }

    $prefix = '';
    $suffix = '';

    if ($inputName.StartsWith('vm'))
    {
        $prefix = 'vm';
        $suffix = $inputName.Substring($prefix.Length);
    }
    elseif ($inputName.StartsWith('IP'))
    {
        $prefix = 'ip';
        $suffix = $inputName.Substring($prefix.Length);
    }
    elseif ($inputName.StartsWith('DNS'))
    {
        $prefix = 'dns';
        $suffix = $inputName.Substring($prefix.Length);
    }
    else
    {
        $prefix = $inputName.Substring(0, 1);
        $suffix = $inputName.Substring(1);
    }

    if ($upperCase)
    {
        $prefix = $prefix.ToUpper();
    }
    else
    {
        $prefix = $prefix.ToLower();
    }

    $outputName = $prefix + $suffix;

    return $outputName;
}

function Get-CliMethodMappedParameterName
{
    param
    (
        # Sample: 'resourceGroupName' => 'resourceGroup', 'containerServiceName' => 'name', etc.
        [Parameter(Mandatory = $true)]
        [string]$inputName,

        [Parameter(Mandatory = $false)]
        [int]$index = -1
    )

    if ($inputName -eq 'resourceGroupName')
    {
        return 'resourceGroup';
    }
    elseif ($inputName -notlike 'VMName' -and $inputName -like "*name" -and $index -eq 1)
    {
        return 'name';
    }
    else
    {
        return $inputName;
    }
}

function Get-CliMethodMappedFunctionName
{
    param
    (
        # Sample: 'createOrUpdate' => 'create', 'get' => 'show', etc.
        [Parameter(Mandatory = $true)]
        [string]$inputName
    )

    if ($inputName -eq 'createOrUpdate')
    {
        return 'create';
    }
    elseif ($inputName -eq 'get')
    {
        return 'show';
    }
    else
    {
        return $inputName;
    }
}

function Get-CliNormalizedName
{
    # Samples: 'VMName' to 'vmName', 
    #          'VirtualMachine' => 'virtualMachine',
    #          'InstanceIDs' => 'instanceIds',
    #          'ResourceGroup' => 'resourceGroup', etc.
    param
    (
        [Parameter(Mandatory = $True)]
        [string]$inName
    )

    $outName = Get-CamelCaseName $inName $false;

    if ($outName.EndsWith('IDs'))
    {
        $outName = $outName.Substring(0, $outName.Length - 3) + 'Ids';
    }

    return $outName;
}


function Get-CliCategoryName
{
    # Sample: 'VirtualMachineScaleSetVM' => 'vmssvm', 'VirtualMachineScaleSet' => 'vmss', etc.
    param(
        [Parameter(Mandatory = $True)]
        [string]$inName
    )

    if ($inName -eq 'VirtualMachineScaleSet')
    {
        $outName = 'vmss';
    }
    elseif ($inName -eq 'VirtualMachineScaleSetVM')
    {
        $outName = 'vmssvm';
    }
    if ($inName -eq 'VirtualMachineScaleSets')
    {
        $outName = 'vmss';
    }
    elseif ($inName -eq 'VirtualMachineScaleSetVMs')
    {
        $outName = 'vmssvm';
    }
    elseif ($inName -eq 'VirtualMachines')
    {
        $outName = 'vm';
    }
    else
    {
        $inName = Get-MappedNoun $inName $inName;
        $outName = Get-CliOptionName $inName;
    }

    return $outName;
}

function Get-PowershellCategoryName
{
    # Sample: 'VirtualMachineScaleSetVM' => 'VmssVm', 'VirtualMachineScaleSet' => 'Vmss', etc.
    param(
        [Parameter(Mandatory = $True)]
        [string]$inName
    )

    if ($inName -eq 'VirtualMachineScaleSet')
    {
        $outName = 'Vmss';
    }
    elseif ($inName -eq 'VirtualMachineScaleSetVM')
    {
        $outName = 'VmssVm';
    }
    else
    {
        $outName = Get-CliOptionName $inName;
    }

    return $outName;
}


function Get-CliOptionName
{
    # Sample: 'VMName' to 'vmName', 'VirtualMachine' => 'virtual-machine', 'ResourceGroup' => 'resource-group', etc.
    param(
        [Parameter(Mandatory = $True)]
        [string]$inName
    )

    if ([string]::IsNullOrEmpty($inName))
    {
        return $inName;
    }

    [string]$varName = Get-CliNormalizedName $inName;
    [string]$outName = $null;

    $i = 0;
    while ($i -lt $varName.Length)
    {
        if ($i -eq 0 -or [char]::IsUpper($varName[$i]))
        {
            if ($i -gt 0)
            {
                # Sample: "parameter-..."
                $outName += '-';
            }

            [string[]]$abbrWords = @('VM', 'IP', 'RM', 'OS', 'NAT', 'IDs', 'DNS');
            $matched = $false;
            foreach ($matchedAbbr in $abbrWords)
            {
                if ($varName.Substring($i) -like ("${matchedAbbr}*"))
                {
                    $matched = $true;
                    break;
                }
            }

            if ($matched)
            {
                $outName += $matchedAbbr.ToLower();
                $i = $i + $matchedAbbr.Length;
            }
            else
            {
                $j = $i + 1;
                while (($j -lt $varName.Length) -and [char]::IsLower($varName[$j]))
                {
                    $j++;
                }

                $outName += $varName.Substring($i, $j - $i).ToLower();
                $i = $j;
            }
        }
        else
        {
            $i++;
        }
    }

    return $outName;
}

function Get-CliShorthandName
{
    # Sample: 'ResourceGroupName' => '-g', 'Name' => '-n', etc.
    param(
        [Parameter(Mandatory = $True)]
        [string]$inName
    )

    if ($inName -eq 'ResourceGroupName' -or $inName -eq 'ResourceGroup')
    {
        $outName = 'g';
    }
    elseif ($inName -eq 'Name')
    {
        $outName = 'n';
    }
    elseif ($inName -eq 'VMName')
    {
        $outName = 'n';
    }
    elseif ($inName -eq 'VMScaleSetName')
    {
        $outName = 'n';
    }
    elseif ($inName -eq 'VirtualMachineScaleSetName')
    {
        $outName = 'n';
    }
    elseif ($inName -eq 'instanceId')
    {
        $outName = 'd';
    }
    elseif ($inName -eq 'vmInstanceIDs')
    {
        $outName = 'D';
    }
    elseif ($inName -eq 'parameters')
    {
        $outName = 'p';
    }
    elseif ($inName -eq 'ExpandExpression')
    {
        $outName = 'e';
    }
    elseif ($inName -eq 'FilterExpression')
    {
        $outName = 't';
    }
    elseif ($inName -eq 'SelectExpression')
    {
        $outName = 'c';
    }
    else
    {
        $outName = '';
    }

    return $outName;
}

function Get-SplitTextLines
{
    # Sample: 'A Very Long Text.' => @('A Very ', 'Long Text.');
    param(
        [Parameter(Mandatory = $true)]
        [string]$text,
        
        [Parameter(Mandatory = $false)]
        [int]$lineWidth
    )

    if ($text -eq '' -or $text -eq $null -or $text.Length -le $lineWidth)
    {
        return $text;
    }

    $lines = @();

    while ($text.Length -gt $lineWidth)
    {
        $lines += $text.Substring(0, $lineWidth);
        $text = $text.Substring($lineWidth);
    }
    
    if ($text -ne '' -and $text -ne $null)
    {
        $lines += $text;
    }

    return $lines;
}

function Get-SingularNoun
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$noun
    )

    if ($noun -eq $null)
    {
        return $noun;
    }
    if ($noun.ToLower().EndsWith("address"))
    {
        return $noun;
    }
    if ($noun.EndsWith("ses"))
    {
        return $noun.Substring(0, $noun.Length - 2);
    }
    if ($noun.EndsWith("s"))
    {
        return $noun.Substring(0, $noun.Length - 1);
    }
    return $noun;
}

function Get-ComponentName
{
    # Sample: "Microsoft.Azure.Management.Compute" => "Compute";
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$clientNS
    )
    
    if ($clientNS.EndsWith('.Model') -or $clientNS.EndsWith('.Models'))
    {
        $clientNS = $clientNS.Substring(0, $clientNS.LastIndexOf('.'));
    }
    
    return $clientNS.Substring($clientNS.LastIndexOf('.') + 1);
}

function Get-MappedNoun
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$operationName,

        [Parameter(Mandatory = $true)]
        [string]$originalNoun
    )

    $returnNoun = $originalNoun;
    foreach($nounMap in $configJsonObject.nounMappings)
    {
        $returnNoun = $returnNoun.Replace($nounMap.from, $nounMap.to);
    }
    foreach ($op in $configJsonObject.operations)
    {
        $objectName = Get-SingularNoun $op.name;
        if ($operationName.Equals($op.name) -or $operationName.Equals($objectName))
        {
            foreach($nounMap in $op.nounMappings)
            {
                $returnNoun = $returnNoun.Replace($nounMap.from, $nounMap.to);
            }
        }
    }
    return $returnNoun
}
