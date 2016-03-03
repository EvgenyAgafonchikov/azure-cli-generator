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

function Load-AssemblyFile
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$dllPath
    )

    $assembly = [System.Reflection.Assembly]::LoadFrom($dllPath);
    $st = [System.Reflection.Assembly]::LoadWithPartialName("System.Collections.Generic");
    return $assembly;
}

function Get-AzureNameSpace
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$dllPath
    )

    [System.Reflection.Assembly]$assembly = Load-AssemblyFile $dllPath;

    $clientNameSpace = $null;
    foreach ($type in $assembly.GetTypes())
    {
        [System.Type]$type = $type;
        if ($type.Namespace -like "Microsoft.*Azure.Management.*" -and `
            $type.Namespace -notlike "Microsoft.*Azure.Management.*.Model*")
        {
            $clientNameSpace = $type.Namespace;
            break;
        }
    }

    return $clientNameSpace;
}
