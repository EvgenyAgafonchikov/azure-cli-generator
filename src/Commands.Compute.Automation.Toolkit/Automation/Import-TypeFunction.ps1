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

function Contains-OnlyStringFields
{
    param(
        [Parameter(Mandatory = $True)]
        [System.Type]$parameterType
    )

    if ($parameterType -eq $null -or $parameterType.BaseType -eq $null)
    {
        return $false;
    }

    if ((-not $parameterType.IsInterface) -and ($parameterType.BaseType -ne $null) -and $parameterType.BaseType.IsEquivalentTo([System.Enum]))
    {
        return $false;
    }

    $result = $true;

    foreach ($propItem in $parameterType.GetProperties())
    {
        if (-not ($propItem.PropertyType.IsEquivalentTo([string])))
        {
            $result = $false;
        }
    }

    return $result;
}

function Contains-OnlyStringList
{
    param(
        [Parameter(Mandatory = $True)]
        [System.Type]$parameterType
    )

    if ($parameterType -eq $null)
    {
        return $false;
    }
    
    if ($parameterType.IsEquivalentTo([System.Collections.Generic.IList[string]]))
    {
      return $true;
    }

    if ((-not $parameterType.IsInterface) -and ($parameterType.BaseType -ne $null) -and $parameterType.BaseType.IsEquivalentTo([System.Enum]))
    {
        return $false;
    }

    if ($parameterType.GetProperties().Count -ne 1)
    {
        return $false;
    }
    else
    {
        [System.Reflection.PropertyInfo]$propInfoItem = ($parameterType.GetProperties())[0];
        if ($propInfoItem.PropertyType.FullName.StartsWith("System.Collections.Generic.IList"))
        {
            [System.Type]$itemType = $propInfoItem.PropertyType.GenericTypeArguments[0];
            if ($itemType.IsEquivalentTo([string]))
            {
                return $true;
            }
        }

        return $false;
    }
}

function Contains-OnlySimpleFields
{
    param(
        [Parameter(Mandatory = $True)]
        [System.Type]$parameterType,

        [Parameter(Mandatory = $True)]
        [System.String]$namespace
    )

    if ($parameterType -eq $null)
    {
        return $false;
    }

    if ($parameterType.BaseType.IsEquivalentTo([System.Enum]))
    {
        return $false;
    }

    $result = $true;

    foreach ($propItem in $parameterType.GetProperties())
    {
        if ($propItem.PropertyType.Namespace -like "*$namespace*")
        {
            $result = $false;
        }

        if ($propItem.PropertyType.Namespace -like "System.Collections.Generic")
        {
            if ($propItem.PropertyType -like "*$namespace*")
            {
                $result = $false;
            }
        }
    }

    return $result;
}

function Contains-OnlyComplexFields
{
    param(
        [Parameter(Mandatory = $True)]
        [System.Type]$parameterType,

        [Parameter(Mandatory = $True)]
        [System.String]$namespace
    )

    if ($parameterType -eq $null)
    {
        return $false;
    }

    $result = $true;

    foreach ($propItem in $parameterType.GetProperties())
    {
        if ($propItem.PropertyType.Namespace -like "*$namespace*")
        {
            continue;
        }

        if ($propItem.PropertyType.FullName.StartsWith("System.Collections.Generic.IList"))
        {
            # List Type
            [System.Type]$listItemType = $propItem.PropertyType.GenericTypeArguments[0];
            if ($listItemType.Namespace -like "*$namespace*")
            {
                continue;
            }
        }

        $result = $false;
    }

    return $result;
}

function Get-SpecificSubNode
{
    param(
        [Parameter(Mandatory = $True)]
        $TreeNode,
        [Parameter(Mandatory = $True)]
        [System.String] $typeName
    )

    foreach ($subNode in $TreeNode.SubNodes)
    {
         Write-Verbose ('SpecificSubNode $subNode = ' + $subNode);
         if ($subNode.Name -eq $typeName)
         {
              return $subNode;
         }
    }

    return $null;
}

# This function returns the first descendant without a single comlex property.
# The returned node contains either more than one properties or single simple property.
function Get-NonSingleComplexDescendant
{
     param(
        [Parameter(Mandatory = $True)]
        $TreeNode,
        [Parameter(Mandatory = $True)]
        $chainArray
     )

     if ($TreeNode.OnlySimple)
     {
        return @{Node = $TreeNode;Chain = $chainArray};
     }

     if ($TreeNode.Properties.Count -eq 1)
     {
          $subNode = Get-SpecificSubNode $TreeNode $TreeNode.Properties[0]["Name"]

          $chainArray += $TreeNode.Name;
          $result = Get-NonSingleComplexDescendant $subNode $chainArray;

          return @{Node = $result["Node"];Chain = $result["Chain"]};
     }
     else
     {
         return @{Node = $TreeNode;Chain = $chainArray};
     }
}


function Get-NormalizedTypeName
{
    param(
        # Sample: 'System.String' => 'string', 'System.Boolean' => bool, etc.
        [Parameter(Mandatory = $true)]
        [System.Reflection.TypeInfo]$parameter_type
    )

    if ($parameter_type.IsGenericType -and $parameter_type.GenericTypeArguments.Count -eq 1)
    {
        $generic_item_type = $parameter_type.GenericTypeArguments[0];
        if (($generic_item_type.FullName -eq 'System.String') -or ($generic_item_type.Name -eq 'string'))
        {
            return 'System.Collections.Generic.IList<string>';
        }
    }

    [string]$inputName = $parameter_type.FullName;
    
    if ([string]::IsNullOrEmpty($inputName))
    {
        return $inputName;
    }

    $outputName = $inputName;
    $clientModelNameSpacePrefix = $clientModelNameSpace + '.';

    if ($inputName -eq 'System.String')
    {
        $outputName = 'string';
    }
    elseif ($inputName -eq 'System.Boolean')
    {
        $outputName = 'bool';
    }
    elseif ($inputName -eq 'System.DateTime')
    {
        return 'DateTime';
    }
    elseif ($inputName -eq 'System.Int32')
    {
        return 'int';
    }
    elseif ($inputName -eq 'System.UInt32')
    {
        return 'uint';
    }
    elseif ($inputName -eq 'System.Char')
    {
        return 'char';
    }
    elseif ($inputName.StartsWith($clientModelNameSpacePrefix))
    {
        $outputName = $inputName.Substring($clientModelNameSpacePrefix.Length);
    }

    $outputName = $outputName.Replace('+', '.');

    return $outputName;
}

function Is-ListStringType
{
    # This function returns $true if the given property info contains only a list of strings.
    param(
        [Parameter(Mandatory = $true)]
        [System.Reflection.TypeInfo]$parameter_type
    )

    if ($parameter_type.IsGenericType -and $parameter_type.GenericTypeArguments.Count -eq 1)
    {
        $generic_item_type = $parameter_type.GenericTypeArguments[0];
        if ($generic_item_type.FullName -eq 'System.String')
        {
            return $true;
        }
        elseif ($generic_item_type.Name -eq 'string')
        {
            return $true;
        }
    }
    
    [System.Reflection.PropertyInfo[]]$property_info_array = $parameter_type.GetProperties();
    if ($property_info_array.Count -eq 1)
    {
        if ($property_info_array[0].PropertyType.FullName -like '*List*System.String*')
        {
          return $true;
        }
        elseif ($property_info_array[0].PropertyType.FullName -eq 'System.String')
        {
          return $true;
        }
        
    }

    return $false;
}

function Get-StringTypes
{
    # This function returns an array of string types, if a given property info array contains only string types.
    # It returns $null, otherwise.
    param(
        [Parameter(Mandatory = $True)]
        [System.Reflection.TypeInfo]$parameter_type
    )
    
    if ($parameter_type.IsGenericType)
    {
        return $null;
    }

    [System.Reflection.PropertyInfo[]]$property_info_array = $parameter_type.GetProperties();
    $return_string_array = @();
    foreach ($prop in $property_info_array)
    {
         if ($prop.PropertyType.FullName -eq "System.String")
         {
              $return_string_array += $prop.Name;
         }
         else
         {
              return $null;
         }
    }

    return $return_string_array;
}


function Get-ConstructorCode
{
    param(
        # Sample: 'string' => 'string.Empty', 'HostedServiceCreateParameters' => 'new HostedServiceCreateParameters()', etc.
        [Parameter(Mandatory = $True)]
        [string]$InputName
    )

    if ([string]::IsNullOrEmpty($InputName))
    {
        return 'null';
    }

    if ($InputName -eq 'string')
    {
        $outputName = 'string.Empty';
    }
    else
    {
        if ($InputName.StartsWith($clientModelNameSpace + "."))
        {
            $InputName = $InputName.Replace($clientModelNameSpace + ".", '');
        }
        elseif ($InputName.StartsWith('System.Collections.Generic.'))
        {
            $InputName = $InputName.Replace('System.Collections.Generic.', '');
        }

        $outputName = 'new ' + $InputName + "()";
    }

    return $outputName;
}

# Sample: ServiceName, DeploymentName
function Is-PipingPropertyName
{
    param(
        [Parameter(Mandatory = $True)]
        [string]$parameterName
    )

    if ($parameterName.ToLower() -eq 'servicename')
    {
        return $true;
    }
    elseif ($parameterName.ToLower() -eq 'deploymentname')
    {
        return $true;
    }
    elseif ($parameterName.ToLower() -eq 'rolename')
    {
        return $true;
    }
    elseif ($parameterName.ToLower() -eq 'roleinstancename')
    {
        return $true;
    }
    elseif ($parameterName.ToLower() -eq 'vmimagename')
    {
        return $true;
    }
    elseif ($parameterName.ToLower() -eq 'imagename')
    {
        return $true;
    }
    elseif ($parameterName.ToLower() -eq 'diskname')
    {
        return $true;
    }

    return $false;
}

function Is-PipingPropertyTypeName
{
    param(
        [Parameter(Mandatory = $True)]
        [string]$parameterTypeName
    )
    
    if ($parameterTypeName.ToLower() -eq 'string')
    {
        return $true;
    }
    elseif ($parameterTypeName.ToLower() -eq 'system.string')
    {
        return $true;
    }

    return $false;
}

function Get-VerbTermNameAndSuffix
{
    param(
        [Parameter(Mandatory = $True)]
        [string]$MethodName
    )

    $found = $false;
    foreach ($key in $common_verb_mapping.Keys)
    {
        if ($MethodName.StartsWith($key))
        {
            $verb = $common_verb_mapping[$key];
            $suffix = $MethodName.Substring($key.Length);

            if ($MethodName.StartsWith('List'))
            {
                $suffix += 'List';
            }
            elseif ($MethodName.StartsWith('PowerOff'))
            {
                $suffix += "WithPowerOff";
            }
            $found = $true;
            break;
        }
    }

    if (-not $found)
    {
        $verb = "Set";
        $suffix = $MethodName;
    }

    Write-Output $verb;
    Write-Output $suffix;
}

function Get-ShortNounName
{
    param(
        [Parameter(Mandatory = $True)]
        [string]$inputNoun
    )

    $noun = $inputNoun;

    foreach ($key in $common_noun_mapping.Keys)
    {
        if ($noun -like ("*${key}*"))
        {
            $noun = $noun.Replace($key, $common_noun_mapping[$key]);
        }
    }

    Write-Output $noun;
}


function Get-ParameterTypeShortName
{
    param(
        [Parameter(Mandatory = $True)]
        $parameter_type_info,

        [Parameter(Mandatory = $false)]
        $is_list_type = $false
    )
    
    if (-not $is_list_type)
    {
        $param_type_full_name = $parameter_type_info.FullName;
        $param_type_full_name = $param_type_full_name.Replace('+', '.');

        $param_type_short_name = $parameter_type_info.Name;
        $param_type_short_name = $param_type_short_name.Replace('+', '.');
    }
    else
    {
        $itemType = $parameter_type_info.GetGenericArguments()[0];
        $itemTypeShortName = $itemType.Name;
        $itemTypeFullName = $itemType.FullName;
        $itemTypeNormalizedShortName = Get-NormalizedTypeName $itemType;;

        $param_type_full_name = "System.Collections.Generic.List<${itemTypeNormalizedShortName}>";
        $param_type_full_name = $param_type_full_name.Replace('+', '.');

        $param_type_short_name = "${itemTypeShortName}List";
        $param_type_short_name = $param_type_short_name.Replace('+', '.');
    }

    return $param_type_short_name;
}

function Get-ParameterTypeFullName
{
    param(
        [Parameter(Mandatory = $True)]
        $parameter_type_info,

        [Parameter(Mandatory = $false)]
        $is_list_type = $false
    )
    
    if (-not $is_list_type)
    {
        $param_type_full_name = $parameter_type_info.FullName;
        $param_type_full_name = $param_type_full_name.Replace('+', '.');
    }
    else
    {
        $itemType = $parameter_type_info.GetGenericArguments()[0];
        $itemTypeShortName = $itemType.Name;
        $itemTypeFullName = $itemType.FullName;
        $itemTypeNormalizedShortName = Get-NormalizedTypeName $itemType;

        $param_type_full_name = "System.Collections.Generic.List<${itemTypeNormalizedShortName}>";
        $param_type_full_name = $param_type_full_name.Replace('+', '.');
    }

    return $param_type_full_name;
}


# Sample: VirtualMachineCreateParameters
function Is-ClientComplexType
{
    param(
        [Parameter(Mandatory = $True)]
        $type_info
    )

    return ($type_info.Namespace -like "${client_name_space}.Model?") -and (-not $type_info.IsEnum);
}

# Sample: IList<ConfigurationSet>
function Is-ListComplexType
{
    param(
        [Parameter(Mandatory = $True)]
        $type_info
    )

    if ($type_info.IsGenericType)
    {
        $args = $list_item_type = $type_info.GetGenericArguments();

        if ($args.Count -eq 1)
        {
            $list_item_type = $type_info.GetGenericArguments()[0];

            if (Is-ClientComplexType $list_item_type)
            {
                return $true;
            }
        }
    }

    return $false;
}

# Sample: IList<ConfigurationSet> => ConfigurationSet
function Get-ListComplexItemType
{
    param(
        [Parameter(Mandatory = $True)]
        $type_info
    )

    if ($type_info.IsGenericType)
    {
        $args = $list_item_type = $type_info.GetGenericArguments();

        if ($args.Count -eq 1)
        {
            $list_item_type = $type_info.GetGenericArguments()[0];

            if (Is-ClientComplexType $list_item_type)
            {
                return $list_item_type;
            }
        }
    }

    return $null;
}

# Sample: VirtualMachines.Create(...) => VirtualMachineCreateParameters
function Get-MethodComplexParameter
{
    param(
        [Parameter(Mandatory = $True)]
        [System.Reflection.MethodInfo]$op_method_info,

        [Parameter(Mandatory = $True)]
        [string]$client_name_space
    )

    $method_param_list = $op_method_info.GetParameters();
    $paramsWithoutEnums = $method_param_list | where { -not $_.ParameterType.IsEnum };

    # Assume that each operation method has only one complext parameter type
    $param_info = $paramsWithoutEnums | where { $_.ParameterType.Namespace -like "${client_name_space}.Model?" } | select -First 1;

    return $param_info;
}

# Sample: VirtualMachineCreateParameters => ConfigurationSet, VMImageInput, ...
function Get-SubComplexParameterListFromType
{
    param
    (
        [Parameter(Mandatory = $true)]
        $type_info,

        [Parameter(Mandatory = $true)]
        [string]$client_name_space,

        [Parameter(Mandatory = $true)]
        $existingParamTypeList
    )

    $subParamTypeList = @();

    foreach ($ept in $existingParamTypeList)
    {
        if ($ept.FullName -eq $type_info.FullName)
        {
            return $subParamTypeList;
        }
    }

    # Not found, record the type
    $existingParamTypeList += $type_info;

    if (-not (Is-ClientComplexType $type_info))
    {
        return $subParamTypeList;
    }

    $paramProps = $type_info.GetProperties();
    foreach ($pp in $paramProps)
    {
        $isClientType = $false;
        if (Is-ClientComplexType $pp.PropertyType)
        {
            $subParamTypeList += $pp.PropertyType;
            $isClientType = $true;
        }
        elseif (Is-ListComplexType $pp.PropertyType)
        {
            $subParamTypeList += $pp.PropertyType;
            $subParamTypeList += Get-ListComplexItemType $pp.PropertyType;
            $isClientType = $true;
        }

        if ($isClientType)
        {
            $recursiveSubParamTypeList = Get-SubComplexParameterListFromType $pp.PropertyType $client_name_space $existingParamTypeList;
            foreach ($rsType in $recursiveSubParamTypeList)
            {
                $subParamTypeList += $rsType;
            }
        }
    }

    return $subParamTypeList;
}

# Sample: VirtualMachineCreateParameters => ConfigurationSet, VMImageInput, ...
function Get-SubComplexParameterList
{
    param(
        [Parameter(Mandatory = $True)]
        [System.Reflection.ParameterInfo]$param_info,

        [Parameter(Mandatory = $True)]
        [string]$client_name_space
    )

    return Get-SubComplexParameterListFromType $param_info.ParameterType $client_name_space @();
}

# Get proper type name
function Get-ProperTypeName
{
    param([System.Type] $itemType)

    if ($itemType.IsGenericType -and ($itemType.Name.StartsWith('IList') -or $itemType.Name.StartsWith('List')))
    {
        $typeStr = 'IList<' + $itemType.GenericTypeArguments[0].Name + '>';
    }
    elseif ($itemType.IsGenericType -and ($itemType.Name.StartsWith('IDictionary') -or $itemType.Name.StartsWith('Dictionary')))
    {
        $typeStr = 'IDictionary<' + $itemType.GenericTypeArguments[0].Name + ',' + $itemType.GenericTypeArguments[1].Name + '>';
    }
    elseif ($itemType.IsGenericType -and $itemType.Name.StartsWith('Nullable'))
    {
        $typeStr = $itemType.GenericTypeArguments[0].Name + '?';
    }
    else
    {
        $typeStr = $itemType.Name;
    }

    $typeStr = $typeStr.Replace("System.String", "string");
    $typeStr = $typeStr.Replace("String", "string");
    $typeStr = $typeStr.Replace("System.Boolean", "bool");
    $typeStr = $typeStr.Replace("Boolean", "bool");
    $typeStr = $typeStr.Replace("System.UInt32", "uint");
    $typeStr = $typeStr.Replace("UInt32", "uint");
    $typeStr = $typeStr.Replace("System.Int32", "int");
    $typeStr = $typeStr.Replace("Int32", "int");

    return $typeStr;
}

# Check if 2 methods have the same parameter list
function CheckIf-SameParameterList
{
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Reflection.MethodInfo]$methodInfo,
        
        [Parameter(Mandatory = $true)]
        [System.Reflection.MethodInfo]$friendMethodInfo
    )

    if ($methodInfo -eq $null -or $friendMethodInfo -eq $null)
    {
        return $false;
    }

    $myParams = $methodInfo.GetParameters();
    $friendParams = $friendMethodInfo.GetParameters();
    if ($myParams.Count -ne $friendParams.Count)
    {
        return $false;
    }

    for ($i = 0; $i -lt $myParams.Count -and $i -lt $friendParams.Count; $i++)
    {
        [System.Reflection.ParameterInfo]$paramInfo = $myParams[$i];
        [System.Reflection.ParameterInfo]$friendInfo = $friendParams[$i];
        if ($paramInfo.Name -ne $friendInfo.Name)
        {
            return $false;
        }
        elseif (-not $paramInfo.ParameterType.IsEquivalentTo($friendInfo.ParameterType))
        {
            return $false;
        }
    }

    return $true;
}

# Check if 2 methods are list-page relation
function CheckIf-ListAndPageMethods
{
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Reflection.MethodInfo]$listMethodInfo,
        
        [Parameter(Mandatory = $true)]
        [System.Reflection.MethodInfo]$pageMethodInfo
    )

    if ($listMethodInfo -eq $null -or $pageMethodInfo -eq $null)
    {
        return $false;
    }
    
    if (-not (($listMethodInfo.Name.Replace('Async', '') + 'Next') -eq $pageMethodInfo.Name.Replace('Async', '')))
    {
        return $false;
    }

    $pageParams = $pageMethodInfo.GetParameters();
    Write-Verbose ('pageParams = ' + $pageParams);
    # Skip the 1st 'operations' parameter, e.g.
    # 1. Microsoft.Azure.Management.Compute.IVirtualMachineScaleSetVMsOperations operations
    # 2. System.String nextPageLink
    if ($pageParams.Count -eq 2)
    {
        $paramInfo = $pageParams[1];
        if ($paramInfo.ParameterType.IsEquivalentTo([string]) -and $paramInfo.Name -eq 'nextPageLink')
        {
            return $true;
        }
    }

    return $false;
}

# Function Friend Finder
function Find-MatchedMethod
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$searchName,
        
        [Parameter(Mandatory = $true)]
        [System.Reflection.MethodInfo[]]$methodList,
        
        [Parameter(Mandatory = $false)]
        [System.Reflection.MethodInfo]$paramMatchedMethodInfo
    )

    foreach ($methodInfo in $methodList)
    {
        if ($methodInfo.Name -eq $searchName)
        {
            if ($paramMatchedMethodInfo -eq $null)
            {
                return $methodInfo;
            }
            elseif (CheckIf-SameParameterList $methodInfo $paramMatchedMethodInfo)
            {
                return $methodInfo;
            }
        }
    }
    
    return $null;
}

function CheckIf-PaginationMethod
{
    param
    (
        [Parameter(Mandatory = $true)]
        [System.Reflection.MethodInfo]$MethodInfo
    )
    
    if ($MethodInfo.Name -like "List*Next")
    {
        $methodParameters = $MethodInfo.GetParameters();
        if ($methodParameters.Count -eq 2 -and $methodParameters[1].ParameterType.IsEquivalentTo([string]))
        {
            return $true;
        }
    }
    
    return $false;
}