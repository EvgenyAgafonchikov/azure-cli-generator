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

[CmdletBinding(DefaultParameterSetName = "ByTypeInfo")]
param
(
  [Parameter(Mandatory = $true, Position = 0, ParameterSetName = 'ByTypeInfo')]
  [System.Type]$TypeInfo = $null,

  [Parameter(Mandatory = $true, Position = 0, ParameterSetName = 'ByFullTypeNameAndDllPath')]
  [string]$TypeFullName = $null,

  [Parameter(Mandatory = $true, Position = 1, ParameterSetName = 'ByFullTypeNameAndDllPath')]
  [string]$DllFullPath = $null
)

function Create-ParameterObjectImpl
{
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Type]$typeInfo,
        
        [Parameter(Mandatory = $true)]
        [System.Collections.Hashtable]$typeList
    )

    if ([string]::IsNullOrEmpty($typeInfo.FullName) -or $typeList.ContainsKey($typeInfo.FullName))
    {
        return $null;
    }

    if ($typeInfo.FullName -like "Microsoft.*Azure.Management.*.*" -and (-not ($typeInfo.FullName -like "Microsoft.*Azure.Management.*.SubResource")))
    {
        $st = $typeList.Add($typeInfo.FullName, $typeInfo);
    }

    if ($typeInfo.FullName -eq 'System.String' -or $typeInfo.FullName -eq 'string')
    {
        $obj = '';
    }
    elseif ($typeInfo.FullName -eq 'System.Uri')
    {
        $obj = '' -as 'System.Uri';
    }
    elseif ($typeInfo.FullName -eq 'System.Boolean')
    {
        $obj = $false;
    }
    elseif ($typeInfo.FullName -eq 'System.Int32')
    {
        $obj = 0;
    }
    elseif ($typeInfo.FullName -eq 'System.UInt32')
    {
        $obj = 0;
    }
    elseif ($typeInfo.FullName -eq 'System.Byte[]')
    {
        $obj = New-Object -TypeName System.Byte[] -ArgumentList 0;
    }
    elseif ($typeInfo.FullName -like 'System.Collections.Generic.IList*' -or $typeInfo.FullName -like 'System.Collections.Generic.List*')
    {
        [System.Type]$itemType = $typeInfo.GetGenericArguments()[0];
        $itemObj = Create-ParameterObjectImpl $itemType $typeList;

        $typeName = "System.Collections.Generic.List[" + $itemType.FullName + "]";
        $listObj = New-Object -TypeName $typeName;
        $listObj.Add($itemObj);

        $obj = $listObj;
    }
    elseif ($typeInfo.FullName -like 'System.Collections.Generic.IDictionary*')
    {
        # Dictionary in client library always consists of string key & values.
        $obj = New-Object 'System.Collections.Generic.Dictionary[string,string]';
    }
    elseif ($typeInfo.FullName -like 'System.Nullable*Microsoft.*Azure.Management.*.*Types*')
    {
        $obj = $null;
    }
    elseif ($typeInfo.FullName -like 'Microsoft.*Azure.Management.*.*Types')
    {
        $obj = $null;
    }
    elseif ($typeInfo.FullName -like 'System.Nullable*')
    {
        $obj = $null;
    }
    else
    {
        $obj = New-Object $typeInfo.FullName;

        foreach ($item in $typeInfo.GetProperties())
        {
            $prop = [System.Reflection.PropertyInfo]$item;

            if (-not ($prop.CanWrite))
            {
                continue;
            }

            if ($prop.PropertyType.IsGenericType -and $prop.PropertyType.FullName -like 'System.Collections.Generic.*List*')
            {
                [System.Type]$itemType = $prop.PropertyType.GetGenericArguments()[0];
                $itemObj = Create-ParameterObjectImpl $itemType $typeList;
                $listTypeName = "System.Collections.Generic.List[" + $itemType.FullName + "]";

                $propObjList = New-Object -TypeName $listTypeName;
                $st = $propObjList.Add($itemObj);

                $st = $prop.SetValue($obj, $propObjList -as $listTypeName);
            }
            else
            {
                $propObj = Create-ParameterObjectImpl $prop.PropertyType $typeList;
                $st = $prop.SetValue($obj, $propObj);
            }
        }
    }

    $st = $typeList.Remove($typeInfo.FullName);

    return $obj;
}

if (($TypeFullName -ne $null) -and ($TypeFullName.Trim() -ne ''))
{
    . "$PSScriptRoot\Import-AssemblyFunction.ps1";
    $dll = Load-AssemblyFile $DllFullPath;
    $TypeInfo = $dll.GetType($TypeFullName);
}

Write-Output (Create-ParameterObjectImpl $TypeInfo @{});