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

function Get-HyakOperationShortName
{
    param(
        # Sample #1: 'IVirtualMachineOperations' => 'VirtualMachine'
        # Sample #2: 'IDeploymentOperations' => 'Deployment'
        [Parameter(Mandatory = $true)]
        [string]$opFullName,

        [Parameter(Mandatory = $false)]
        [string]$prefix = 'I',

        [Parameter(Mandatory = $false)]
        [string]$suffix = 'Operations'
    )

    $opShortName = $opFullName;
    if ($opFullName.StartsWith($prefix) -and $opShortName.EndsWith($suffix))
    {
        $lenOpShortName = ($opShortName.Length - $prefix.Length - $suffix.Length);
        $opShortName = $opShortName.Substring($prefix.Length, $lenOpShortName);
    }

    return $opShortName;
}

function Get-AutoRestOperationShortName
{
    param(
        # Sample #1: 'VirtualMachineOperationsExtensions' => 'VirtualMachine'
        # Sample #2: 'DeploymentOperationsExtensions' => 'Deployment'
        [Parameter(Mandatory = $True)]
        [string]$opFullName
    )

    $prefix = '';
    $suffix = 'OperationsExtensions';
    $result = Get-HyakOperationShortName $opFullName $prefix $suffix;

    return $result;
}

function Get-OperationShortName
{
    param(
        # Sample #1: 'VirtualMachineOperationsExtensions' => 'VirtualMachine'
        # Sample #2: 'DeploymentOperationsExtensions' => 'Deployment'
        [Parameter(Mandatory = $true)]
        [string]$opFullName,
        
        # Hyak or AutoRest
        [Parameter(Mandatory = $false)]
        [bool]$isHyakMode = $false
    )
    # $isHyakMode = $isHyakMode -or ($client_library_namespace -like "Microsoft.WindowsAzure.*.*");
    # if ($isHyakMode)
    # {
    #   return Get-AutoRestOperationShortName $opFullName;
    # }
    # else
    # {
    #   return Get-AutoRestOperationShortName $opFullName;
    # }
    return Get-AutoRestOperationShortName $opFullName;
}

function Match-OperationFilter
{
    param(
        [Parameter(Mandatory = $true)]
        [string]$operation_full_name,

        [Parameter(Mandatory = $true)]
        [string[]]$operation_name_filter)

    if ($operation_name_filter -eq $null)
    {
        return $true;
    }

    if ($operation_name_filter -eq '*')
    {
        return $true;
    }

    $op_short_name = Get-AutoRestOperationShortName $operation_full_name;
    if ($operation_name_filter -ccontains $op_short_name)
    {
        return $true;
    }

    return $false;
}

function Get-OperationMethods
{
    param(
        [Parameter(Mandatory = $true)]
        $operation_type
    )

    $method_binding_flags = [System.Reflection.BindingFlags]::Public -bor [System.Reflection.BindingFlags]::Static -bor [System.Reflection.BindingFlags]::DeclaredOnly;
    $methods = $operation_type.GetMethods($method_binding_flags);
    return ($methods | Sort-Object -Property Name -Unique);
}

# Get Filtered Operation Types from all DLL Types
function Get-FilteredOperationTypes
{
    param(
        [Parameter(Mandatory = $true)]
        $all_assembly_types,

        [Parameter(Mandatory = $true)]
        $dll_name,
        
        [Parameter(Mandatory = $false)]
        $operation_name_filter = $null
    )

    $op_types = $all_assembly_types | where { $_.Namespace -eq $dll_name -and $_.Name -like '*OperationsExtensions' };
    $op_types_add = $all_assembly_types | where { $_.Namespace -eq "${dll_name}.Models" -and $operation_name_filter -contains $_.Name };
    $op_types += $op_types_add;

    Write-Verbose $BAR_LINE;
    Write-Verbose 'List All Operation Types:';
    foreach ($op_type in $op_types)
    {
        Write-Verbose ('[' + $op_type.Namespace + '] ' + $op_type.Name);
    }

    $op_filtered_types = $op_types;
    if ($operation_name_filter -ne $null)
    {
        $op_filtered_types = $op_filtered_types | where { Match-OperationFilter $_.Name $operation_name_filter };
    }

    Write-Verbose $BAR_LINE;
    Write-Verbose ('Operation Name Filter : "' + $operation_name_filter + '"');
    Write-Verbose 'Filtered Operation Types : ';
    foreach ($op_type in $op_filtered_types)
    {
        Write-Verbose ('[' + $op_type.Namespace + '] ' + $op_type.Name);
    }

    Write-Verbose $BAR_LINE;

    return $op_filtered_types;
}
