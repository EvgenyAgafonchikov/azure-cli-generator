﻿# ----------------------------------------------------------------------------------
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

param
(
    # VirtualMachine, VirtualMachineScaleSet, etc.
    [Parameter(Mandatory = $true)]
    [string]$OperationName,

    [Parameter(Mandatory = $true)]
    [System.Reflection.MethodInfo]$MethodInfo,
    
    [Parameter(Mandatory = $true)]
    [string]$ModelClassNameSpace,
    
    [Parameter(Mandatory = $true)]
    [string]$FileOutputFolder,

    [Parameter(Mandatory = $false)]
    [string]$FunctionCmdletFlavor = 'None',

    [Parameter(Mandatory = $false)]
    [string]$CliOpCommandFlavor = 'Verb',

    [Parameter(Mandatory = $false)]
    [System.Reflection.MethodInfo]$FriendMethodInfo = $null,
    
    [Parameter(Mandatory = $false)]
    [System.Reflection.MethodInfo]$PageMethodInfo = $null,
    
    [Parameter(Mandatory = $false)]
    [bool]$CombineGetAndList = $false,
    
    [Parameter(Mandatory = $false)]
    [bool]$CombineGetAndListAll = $false,

    [Parameter(Mandatory = $false)]
    [bool]$CombineDeleteAndDeleteInstances = $false,

    [Parameter(Mandatory = $false)]
    [bool]$GenerateArgumentListParameter = $false
)

. "$PSScriptRoot\Import-StringFunction.ps1";
. "$PSScriptRoot\Import-TypeFunction.ps1";
. "$PSScriptRoot\Import-WriterFunction.ps1";

# Sample: VirtualMachineGetMethod.cs
function Generate-PsFunctionCommandImpl
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$OperationName,

        [Parameter(Mandatory = $true)]
        [System.Reflection.MethodInfo]$MethodInfo,

        [Parameter(Mandatory = $true)]
        [string]$FileOutputFolder,

        [Parameter(Mandatory = $false)]
        [System.Reflection.MethodInfo]$FriendMethodInfo = $null
    )

    # e.g. Compute
    $componentName = Get-ComponentName $ModelClassNameSpace;
    # e.g. CreateOrUpdate, Get, ...
    $methodName = ($MethodInfo.Name.Replace('Async', ''));
    # e.g. VirtualMachine, System.Void, ...
    $returnTypeInfo = $MethodInfo.ReturnType;
    $normalizedOutputTypeName = Get-NormalizedTypeName $returnTypeInfo;
    $nounPrefix = 'Azure';
    $nounSuffix = 'Method';
    # e.g. VirtualMachines => VirtualMachine
    $opSingularName = Get-SingularNoun $OperationName;
    # e.g. AzureVirtualMachineGetMethod
    $cmdletNoun = $nounPrefix + $opSingularName + $methodName + $nounSuffix;
    # e.g. InvokeAzureVirtualMachineGetMethod
    $invokeVerb = "Invoke";
    $invokeCmdletName = $invokeVerb + $cmdletNoun;
    $invokeParamSetName = $opSingularName + $methodName;
    # e.g. Generated/InvokeAzureVirtualMachineGetMethod.cs
    $fileNameExt = $invokeParamSetName + $nounSuffix + '.cs';
    $fileFullPath = $FileOutputFolder + '/' + $fileNameExt;

    # The folder and files shall be removed beforehand.
    # It will exist, if the target file already exists.
    if (Test-Path $fileFullPath)
    {
        return;
    }
    
    # Common Variables
    $indents_8 = ' ' * 8;
    $getSetCodeBlock = '{ get; set; }';

    # Iterate through Param List
    $methodParamList = $MethodInfo.GetParameters();
    $positionIndex = 1;
    foreach ($methodParam in $methodParamList)
    {
        # Filter Out Helper Parameters
        if (($methodParam.ParameterType.Name -like "I*Operations") -and ($methodParam.Name -eq 'operations'))
        {
            continue;
        }
        elseif ($methodParam.ParameterType.Name.EndsWith('CancellationToken'))
        {
            continue;
        }

        # e.g. vmName => VMName, resourceGroup => ResourceGroup, etc.
        $paramName = Get-CamelCaseName $methodParam.Name;
        $paramTypeName = Get-NormalizedTypeName $methodParam.ParameterType;
        $paramCtorCode = Get-ConstructorCode -InputName $paramTypeName;
    }

    # Construct Code
    $code = '';
    $part1 = Get-InvokeMethodCmdletCode -ComponentName $componentName -OperationName $OperationName -MethodInfo $MethodInfo;
    $part2 = Get-ArgumentListCmdletCode -ComponentName $componentName -OperationName $OperationName -MethodInfo $MethodInfo;

    $code += $part1;
    $code += $NEW_LINE;
    $code += $part2;

    if ($FunctionCmdletFlavor -eq 'Verb')
    {
        # If the Cmdlet Flavor is 'Verb', generate the Verb-based cmdlet code
        $part3 = Get-VerbNounCmdletCode -ComponentName $componentName -OperationName $OperationName -MethodInfo $MethodInfo;
        $code += $part3;
    }

    # Write Code to File
    Write-CmdletCodeFile $fileFullPath $code;
    Write-Output $part1;
    Write-Output $part2;
    Write-Output $part3;
}

# Get Partial Code for Invoke Method
function Get-InvokeMethodCmdletCode
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$ComponentName,
        
        [Parameter(Mandatory = $true)]
        [string]$OperationName,

        [Parameter(Mandatory = $true)]
        [System.Reflection.MethodInfo]$MethodInfo
    )

    # e.g. CreateOrUpdate, Get, ...
    $methodName = ($MethodInfo.Name.Replace('Async', ''));
    # e.g. VirtualMachines => VirtualMachine
    $opSingularName = Get-SingularNoun $OperationName;
    # e.g. InvokeAzureComputeMethodCmdlet
    $invoke_cmdlet_class_name = 'InvokeAzure' + $ComponentName + 'MethodCmdlet';
    $invoke_param_set_name = $opSingularName + $methodName;
    $method_return_type = $MethodInfo.ReturnType;
    $invoke_input_params_name = 'invokeMethodInputParameters';

    # 1. Start
    $code = "";
    $code += "    public partial class ${invoke_cmdlet_class_name} : ${ComponentName}AutomationBaseCmdlet" + $NEW_LINE;
    $code += "    {" + $NEW_LINE;

    # 2. Iterate through Param List
    $methodParamList = $MethodInfo.GetParameters();
    [System.Collections.ArrayList]$paramNameList = @();
    [System.Collections.ArrayList]$paramLocalNameList = @();
    [System.Collections.ArrayList]$pruned_params = @();
    foreach ($methodParam in $methodParamList)
    {
        # Filter Out Helper Parameters
        if (($methodParam.ParameterType.Name -like "I*Operations") -and ($methodParam.Name -eq 'operations'))
        {
            continue;
        }
        elseif ($methodParam.ParameterType.Name.EndsWith('CancellationToken'))
        {
            continue;
        }

        # e.g. vmName => VMName, resourceGroup => ResourceGroup, etc.
        $paramName = Get-CamelCaseName $methodParam.Name;
        # Save the parameter's camel name (in upper case) and local name (in lower case).
        $paramNameList += $paramName;
        $paramLocalNameList += $methodParam.Name;

        # Update Pruned Parameter List
        if (-not ($paramName -eq 'ODataQuery'))
        {
            $st = $pruned_params.Add($methodParam);
        }
    }

    $invoke_params_join_str = [string]::Join(', ', $paramLocalNameList.ToArray());

    # 2.1 Dynamic Parameter Assignment
    $dynamic_param_assignment_code_lines = @();
    $param_index = 1;
    foreach ($pt in $pruned_params)
    {
        $param_type_full_name = $pt.ParameterType.FullName;
        if (($param_type_full_name -like "I*Operations") -and ($param_type_full_name -eq 'operations'))
        {
            continue;
        }
        elseif ($param_type_full_name.EndsWith('CancellationToken'))
        {
            continue;
        }

        $is_string_list = Is-ListStringType $pt.ParameterType;
        $does_contain_only_strings = Get-StringTypes $pt.ParameterType;

        $param_name = Get-CamelCaseName $pt.Name;
        $expose_param_name = $param_name;
        $is_manatory = (-not $pt.IsOptional).ToString().ToLower();

        $param_type_full_name = Get-NormalizedTypeName $pt.ParameterType;

        if ($expose_param_name -like '*Parameters')
        {
            $expose_param_name = $invoke_param_set_name + $expose_param_name;
        }

        $expose_param_name = Get-SingularNoun $expose_param_name;

        if (($does_contain_only_strings -eq $null) -or ($does_contain_only_strings.Count -eq 0))
        {
            # Complex Class Parameters
             $dynamic_param_assignment_code_lines +=
@"
            var p${param_name} = new RuntimeDefinedParameter();
            p${param_name}.Name = `"${expose_param_name}`";
"@;

             if ($is_string_list)
             {
                  $dynamic_param_assignment_code_lines += "            p${param_name}.ParameterType = typeof(string[]);";
             }
             else
             {
                  $dynamic_param_assignment_code_lines += "            p${param_name}.ParameterType = typeof($param_type_full_name);";
             }

             $dynamic_param_assignment_code_lines +=
@"
            p${param_name}.Attributes.Add(new ParameterAttribute
            {
                ParameterSetName = "InvokeByDynamicParameters",
                Position = $param_index,
                Mandatory = $is_manatory
            });
            p${param_name}.Attributes.Add(new AllowNullAttribute());
            dynamicParameters.Add(`"${expose_param_name}`", p${param_name});

"@;
            $param_index += 1;
        }
        else
        {
            # String Parameters
             foreach ($s in $does_contain_only_strings)
             {
                  $s = Get-SingularNoun $s;
                  $dynamic_param_assignment_code_lines +=
@"
            var p${s} = new RuntimeDefinedParameter();
            p${s}.Name = `"${s}`";
            p${s}.ParameterType = typeof(string);
            p${s}.Attributes.Add(new ParameterAttribute
            {
                ParameterSetName = "InvokeByDynamicParameters",
                Position = $param_index,
                Mandatory = false
            });
            p${s}.Attributes.Add(new AllowNullAttribute());
            dynamicParameters.Add(`"${s}`", p${s});

"@;
                  $param_index += 1;
             }
        }
    }

    $param_name = $expose_param_name = 'ArgumentList';
    $param_type_full_name = 'object[]';
    $dynamic_param_assignment_code_lines +=
@"
            var p${param_name} = new RuntimeDefinedParameter();
            p${param_name}.Name = `"${expose_param_name}`";
            p${param_name}.ParameterType = typeof($param_type_full_name);
            p${param_name}.Attributes.Add(new ParameterAttribute
            {
                ParameterSetName = "InvokeByStaticParameters",
                Position = $param_index,
                Mandatory = true
            });
            p${param_name}.Attributes.Add(new AllowNullAttribute());
            dynamicParameters.Add(`"${expose_param_name}`", p${param_name});

"@;

    $dynamic_param_assignment_code = [string]::Join($NEW_LINE, $dynamic_param_assignment_code_lines);

    # 2.2 Create Dynamic Parameter Function
    $dynamic_param_source_template =
@"
        protected object Create${invoke_param_set_name}DynamicParameters()
        {
            dynamicParameters = new RuntimeDefinedParameterDictionary();
$dynamic_param_assignment_code
            return dynamicParameters;
        }
"@;

    $code += $dynamic_param_source_template + $NEW_LINE;

    # 2.3 Execute Method
    $position_index = 1;
    $indents = ' ' * 8;
    $has_properties = $false;
    foreach ($pt in $methodParamList)
    {
        # Filter Out Helper Parameters
        if (($pt.ParameterType.Name -like "I*Operations") -and ($pt.Name -eq 'operations'))
        {
            continue;
        }
        elseif ($pt.ParameterType.Name.EndsWith('CancellationToken'))
        {
            continue;
        }

        $paramTypeNormalizedName = Get-NormalizedTypeName $pt.ParameterType;
        $normalized_param_name = Get-CamelCaseName $pt.Name;

        $has_properties = $true;
        $is_string_list = Is-ListStringType $pt.ParameterType;
        $does_contain_only_strings = Get-StringTypes $pt.ParameterType;
        $only_strings = (($does_contain_only_strings -ne $null) -and ($does_contain_only_strings.Count -ne 0));

        $param_index = $position_index - 1;
        if ($only_strings)
        {
                # Case 1: the parameter type contains only string types.
                $invoke_local_param_definition = $indents + (' ' * 4) + "var " + $pt.Name + " = new ${paramTypeNormalizedName}();" + $NEW_LINE;

                foreach ($param in $does_contain_only_strings)
                {
                    $invoke_local_param_definition += $indents + (' ' * 4) + "var p${param} = (string) ParseParameter(${invoke_input_params_name}[${param_index}]);" + $NEW_LINE;
                    $invoke_local_param_definition += $indents + (' ' * 4) + $pt.Name + ".${param} = string.IsNullOrEmpty(p${param}) ? null : p${param};" + $NEW_LINE;
                    $param_index += 1;
                    $position_index += 1;
                }
        }
        elseif ($is_string_list)
        {
            # Case 2: the parameter type contains only a list of strings.
            $list_of_strings_property = ($pt.ParameterType.GetProperties())[0].Name;

            $invoke_local_param_definition = $indents + (' ' * 4) + "${paramTypeNormalizedName} " + $pt.Name + " = null;"+ $NEW_LINE;
            $invoke_local_param_definition += $indents + (' ' * 4) + "if (${invoke_input_params_name}[${param_index}] != null)" + $NEW_LINE;
            $invoke_local_param_definition += $indents + (' ' * 4) + "{" + $NEW_LINE;
            $invoke_local_param_definition += $indents + (' ' * 8) + "var inputArray${param_index} = Array.ConvertAll((object[]) ParseParameter(${invoke_input_params_name}[${param_index}]), e => e.ToString());" + $NEW_LINE;                
            if ($paramTypeNormalizedName -like 'System.Collections.Generic.IList*')
            {
                $invoke_local_param_definition += $indents + (' ' * 8) + $pt.Name + " = inputArray${param_index}.ToList();" + $NEW_LINE;
            }
            else
            {
                $invoke_local_param_definition += $indents + (' ' * 8) + $pt.Name + " = new ${paramTypeNormalizedName}();" + $NEW_LINE;
                $invoke_local_param_definition += $indents + (' ' * 8) + $pt.Name + ".${list_of_strings_property} = inputArray${param_index}.ToList();" + $NEW_LINE;
            }
            $invoke_local_param_definition += $indents + (' ' * 4) + "}" + $NEW_LINE;
        }
        else
        {
            # Case 3: this is the most general case.
            if ($normalized_param_name -eq 'ODataQuery')
            {
                $paramTypeNormalizedName = "Microsoft.Rest.Azure.OData.ODataQuery<${opSingularName}>";
            }
            $invoke_local_param_definition = $indents + (' ' * 4) + "${paramTypeNormalizedName} " + $pt.Name + " = (${paramTypeNormalizedName})ParseParameter(${invoke_input_params_name}[${param_index}]);" + $NEW_LINE;
        }

        $invoke_local_param_code_content += $invoke_local_param_definition;
        $position_index += 1;
    }

    $invoke_cmdlt_source_template = '';

    if ($methodName -eq 'DeleteInstances' -and $ModelClassNameSpace -like "*.Azure.Management.*Model*")
    {
        # Only for ARM Cmdlets
        [System.Collections.ArrayList]$paramLocalNameList2 = @();
        for ($i2 = 0; $i2 -lt $paramLocalNameList.Count - 1; $i2++)
        {
            $item2 = $paramLocalNameList[$i2];
            $paramLocalNameList2 += $item2;
        }
        $invoke_cmdlt_source_template =  "        protected void Execute${invoke_param_set_name}Method(object[] ${invoke_input_params_name})" + $NEW_LINE;
        $invoke_cmdlt_source_template += "        {" + $NEW_LINE;
        $invoke_cmdlt_source_template += "${invoke_local_param_code_content}" + $NEW_LINE;
        $invoke_cmdlt_source_template += "            if ("
        for ($i2 = 0; $i2 -lt $paramLocalNameList.Count; $i2++)
        {
            if ($paramLocalNameList[$i2] -ne 'instanceIds')
            {
                if ($i2 -gt 0)
                {
                    $invoke_cmdlt_source_template += " && ";
                }
                $invoke_cmdlt_source_template += "!string.IsNullOrEmpty(" + $paramLocalNameList[$i2] + ")"
            }
            else
            {
            if ($i2 -gt 0)
                {
                    $invoke_cmdlt_source_template += " && ";
                }
                $invoke_cmdlt_source_template += $paramLocalNameList[$i2] + " != null";
            }
        }
        $invoke_cmdlt_source_template += ")" + $NEW_LINE;
        $invoke_cmdlt_source_template += "            {" + $NEW_LINE;
        $invoke_cmdlt_source_template += "                ${OperationName}Client.${methodName}(${invoke_params_join_str});" + $NEW_LINE;
        $invoke_cmdlt_source_template += "            }" + $NEW_LINE;

        if ($CombineDeleteAndDeleteInstances)
        {
            $invoke_params_join_str_for_list = [string]::Join(', ', $paramLocalNameList2.ToArray());
            $invoke_cmdlt_source_template += "            else" + $NEW_LINE;
            $invoke_cmdlt_source_template += "            {" + $NEW_LINE;
            $invoke_cmdlt_source_template += "                ${OperationName}Client.Delete($invoke_params_join_str_for_list);" + $NEW_LINE;
            $invoke_cmdlt_source_template += "            }" + $NEW_LINE;
        }
        $invoke_cmdlt_source_template += "        }" + $NEW_LINE;
    }
    elseif ($method_return_type.FullName -eq 'System.Void')
    {
        $invoke_cmdlt_source_template =
@"
        protected void Execute${invoke_param_set_name}Method(object[] ${invoke_input_params_name})
        {
${invoke_local_param_code_content}
            ${OperationName}Client.${methodName}(${invoke_params_join_str});
        }
"@;
    }
    elseif ($PageMethodInfo -ne $null)
    {
        $invoke_cmdlt_source_template =
@"
        protected void Execute${invoke_param_set_name}Method(object[] ${invoke_input_params_name})
        {
${invoke_local_param_code_content}
            var result = ${OperationName}Client.${methodName}(${invoke_params_join_str});
            var resultList = result.ToList();
            var nextPageLink = result.NextPageLink;
            while (!string.IsNullOrEmpty(nextPageLink))
            {
                var pageResult = ${OperationName}Client.${methodName}Next(nextPageLink);
                foreach (var pageItem in pageResult)
                {
                    resultList.Add(pageItem);
                }
                nextPageLink = pageResult.NextPageLink;
            }
            WriteObject(resultList, true);
        }
"@;
    }
    elseif ($methodName -eq 'Get' -and $ModelClassNameSpace -like "*.Azure.Management.*Model*")
    {
        # Only for ARM Cmdlets
        [System.Collections.ArrayList]$paramLocalNameList2 = @();
        for ($i2 = 0; $i2 -lt $paramLocalNameList.Count - 1; $i2++)
        {
            $item2 = $paramLocalNameList[$i2];

            if ($item2 -eq 'vmName' -and $OperationName -eq 'VirtualMachines')
            {
                continue;
            }

            $paramLocalNameList2 += $item2;
        }
        $invoke_cmdlt_source_template =  "        protected void Execute${invoke_param_set_name}Method(object[] ${invoke_input_params_name})" + $NEW_LINE;
        $invoke_cmdlt_source_template += "        {" + $NEW_LINE;
        $invoke_cmdlt_source_template += "${invoke_local_param_code_content}" + $NEW_LINE;
        $invoke_cmdlt_source_template += "            if ("
        for ($i2 = 0; $i2 -lt $paramLocalNameList.Count; $i2++)
        {
            if ($paramLocalNameList[$i2] -ne 'expand')
            {
                if ($i2 -gt 0)
                {
                    $invoke_cmdlt_source_template += " && ";
                }
                $invoke_cmdlt_source_template += "!string.IsNullOrEmpty(" + $paramLocalNameList[$i2] + ")"
            }
        }
        $invoke_cmdlt_source_template += ")" + $NEW_LINE;
        $invoke_cmdlt_source_template += "            {" + $NEW_LINE;
        $invoke_cmdlt_source_template += "                var result = ${OperationName}Client.${methodName}(${invoke_params_join_str});" + $NEW_LINE;
        $invoke_cmdlt_source_template += "                WriteObject(result);" + $NEW_LINE;
        $invoke_cmdlt_source_template += "            }" + $NEW_LINE;

        if ($CombineGetAndList)
        {
            $invoke_params_join_str_for_list = [string]::Join(', ', $paramLocalNameList2.ToArray());
            $invoke_cmdlt_source_template += "            else if ("
            for ($i2 = 0; $i2 -lt $paramLocalNameList2.Count; $i2++)
            {
                if ($i2 -gt 0)
                {
                    $invoke_cmdlt_source_template += " && ";
                }
                $invoke_cmdlt_source_template += "!string.IsNullOrEmpty(" + $paramLocalNameList2[$i2] + ")"
            }
            $invoke_cmdlt_source_template += ")" + $NEW_LINE;
            $invoke_cmdlt_source_template += "            {" + $NEW_LINE;
            $invoke_cmdlt_source_template += "                var result = ${OperationName}Client.List(${invoke_params_join_str_for_list});" + $NEW_LINE;
            $invoke_cmdlt_source_template += "                WriteObject(result);" + $NEW_LINE;
            $invoke_cmdlt_source_template += "            }" + $NEW_LINE;
        }

        if ($CombineGetAndListAll)
        {
            $invoke_cmdlt_source_template += "            else" + $NEW_LINE;
            $invoke_cmdlt_source_template += "            {" + $NEW_LINE;
            $invoke_cmdlt_source_template += "                var result = ${OperationName}Client.ListAll();" + $NEW_LINE;
            $invoke_cmdlt_source_template += "                WriteObject(result);" + $NEW_LINE;
            $invoke_cmdlt_source_template += "            }" + $NEW_LINE;
        }

        $invoke_cmdlt_source_template += "        }" + $NEW_LINE;
    }
    else
    {
        $invoke_cmdlt_source_template =
@"
        protected void Execute${invoke_param_set_name}Method(object[] ${invoke_input_params_name})
        {
${invoke_local_param_code_content}
            var result = ${OperationName}Client.${methodName}(${invoke_params_join_str});
            WriteObject(result);
        }
"@;
    }

    $code += $NEW_LINE;
    $code += $invoke_cmdlt_source_template + $NEW_LINE;

    # End
    $code += "    }" + $NEW_LINE;

    return $code;
}

# Get Partial Code for Creating New Argument List
function Get-ArgumentListCmdletCode
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$ComponentName,

        [Parameter(Mandatory = $true)]
        [string]$OperationName,

        [Parameter(Mandatory = $true)]
        [System.Reflection.MethodInfo]$MethodInfo
    )

    # e.g. CreateOrUpdate, Get, ...
    $methodName = ($MethodInfo.Name.Replace('Async', ''));
    # e.g. VirtualMachines => VirtualMachine
    $opSingularName = Get-SingularNoun $OperationName;
    $indents = ' ' * 8;

    # 1. Construct Code - Starting
    $code = "";
    $code += "    public partial class NewAzure${ComponentName}ArgumentListCmdlet : ${ComponentName}AutomationBaseCmdlet" + $NEW_LINE;
    $code += "    {" + $NEW_LINE;
    $code += "        protected PSArgument[] Create" + $opSingularName + $methodName + "Parameters()" + $NEW_LINE;
    $code += "        {" + $NEW_LINE;

    # 2. Iterate through Param List
    $methodParamList = $MethodInfo.GetParameters();
    $paramNameList = @();
    $paramLocalNameList = @();
    $has_properties = $false;
    foreach ($methodParam in $methodParamList)
    {
        # Filter Out Helper Parameters
        if (($methodParam.ParameterType.Name -like "I*Operations") -and ($methodParam.Name -eq 'operations'))
        {
            continue;
        }
        elseif ($methodParam.ParameterType.Name.EndsWith('CancellationToken'))
        {
            continue;
        }
        
        $has_properties = $true;
        
        # e.g. vmName => VMName, resourceGroup => ResourceGroup, etc.
        $paramName = Get-CamelCaseName $methodParam.Name;

        # i.e. System.Int32 => int, Microsoft.Azure.Management.Compute.VirtualMachine => VirtualMachine
        $paramTypeName = Get-NormalizedTypeName $methodParam.ParameterType;
        $paramCtorCode = Get-ConstructorCode -InputName $paramTypeName;

        $isStringList = Is-ListStringType $methodParam.ParameterType;
        $strTypeList = Get-StringTypes $methodParam.ParameterType;
        $containsOnlyStrings = ($strTypeList -ne $null) -and ($strTypeList.Count -ne 0);

        # Save the parameter's camel name (in upper case) and local name (in lower case).
        if (-not $containsOnlyStrings)
        {
            $paramNameList += $paramName;
            $paramLocalNameList += $methodParam.Name;
        }

        # 2.1 Construct Code - Local Constructor Initialization
        if ($containsOnlyStrings)
        {
            # Case 2.1.1: the parameter type contains only string types.
            foreach ($param in $strTypeList)
            {
                $code += $indents + (' ' * 4) + "var p${param} = string.Empty;" + $NEW_LINE;
                $param_index += 1;
                $position_index += 1;
                $paramNameList += ${param};
                $paramLocalNameList += "p${param}";
            }
        }
        elseif ($isStringList)
        {
            # Case 2.1.2: the parameter type contains only a list of strings.
            $code += "            var " + $methodParam.Name + " = new string[0];" + $NEW_LINE;
        }
        elseif ($paramName -eq 'ODataQuery')
        {
            # Case 2.1.3: ODataQuery.
            $paramTypeName = "Microsoft.Rest.Azure.OData.ODataQuery<${opSingularName}>";
            $code += "            ${paramTypeName} " + $methodParam.Name + " = new ${paramTypeName}();" + $NEW_LINE;
        }
        elseif ($paramTypeName.EndsWith('?'))
        {
            # Case 2.1.4: Nullable type
            $code += "            ${paramTypeName} " + $methodParam.Name + " = (${paramTypeName}) null;" + $NEW_LINE;
        }
        else
        {
            # Case 2.1.5: Most General Constructor Case
            $code += "            ${paramTypeName} " + $methodParam.Name + " = ${paramCtorCode};" + $NEW_LINE;
        }
    }

    # Construct Code - 2.2 Return Argument List
    if ($has_properties)
    {
        $code += $NEW_LINE;
        $code += "            return ConvertFromObjectsToArguments(" + $NEW_LINE;
        $code += "                 new string[] { `"" + ([string]::Join("`", `"", $paramNameList)) + "`" }," + $NEW_LINE;
        $code += "                 new object[] { " + ([string]::Join(", ", $paramLocalNameList)) + " });" + $NEW_LINE;
    }
    else
    {
        $code += "            return ConvertFromObjectsToArguments(new string[0], new object[0]);" + $NEW_LINE;
    }

    # Construct Code - Ending
    $code += "        }" + $NEW_LINE;
    $code += "    }";

    return $code;
}

# Get Partial Code for Verb-Noun Cmdlet
function Get-VerbNounCmdletCode
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$ComponentName,
        
        [Parameter(Mandatory = $true)]
        [string]$OperationName,

        [Parameter(Mandatory = $true)]
        [System.Reflection.MethodInfo]$MethodInfo
    )

    # e.g. CreateOrUpdate, Get, ...
    $methodName = ($MethodInfo.Name.Replace('Async', ''));
    # e.g. VirtualMachines => VirtualMachine
    $opSingularName = Get-SingularNoun $OperationName;
    $invoke_param_set_name = $opSingularName + $methodName;
    if ($FriendMethodInfo -ne $null)
    {
        $friendMethodName = ($FriendMethodInfo.Name.Replace('Async', ''));
        $invoke_param_set_name_for_friend = $opSingularName + $friendMethodName;
    }

    # Variables
    $return_vals = Get-VerbTermNameAndSuffix $methodName;
    $mapped_verb_name = $return_vals[0];
    $mapped_verb_term_suffix = $return_vals[1];
    $shortNounName = Get-ShortNounName $opSingularName;

    $mapped_noun_str = 'AzureRm' + $shortNounName + $mapped_verb_term_suffix;
    $mapped_noun_str = Get-MappedNoun $OperationName $mapped_noun_str;
    $verb_cmdlet_name = $mapped_verb_name + $mapped_noun_str;

    # 1. Start
    $code = "";
    
    # 2. Body
    # Iterate through Param List
    $methodParamList = $MethodInfo.GetParameters();
    $paramNameList = @();
    $paramLocalNameList = @();
    [System.Collections.ArrayList]$pruned_params = @();
    foreach ($methodParam in $methodParamList)
    {
        # Filter Out Helper Parameters
        if (($methodParam.ParameterType.Name -like "I*Operations") -and ($methodParam.Name -eq 'operations'))
        {
            continue;
        }
        elseif ($methodParam.ParameterType.Name.EndsWith('CancellationToken'))
        {
            continue;
        }

        # e.g. vmName => VMName, resourceGroup => ResourceGroup, etc.
        $paramName = Get-CamelCaseName $methodParam.Name;
        # Save the parameter's camel name (in upper case) and local name (in lower case).
        $paramNameList += $paramName;
        $paramLocalNameList += $methodParam.Name;

        # Update Pruned Parameter List
        if (-not ($paramName -eq 'ODataQuery'))
        {
            $st = $pruned_params.Add($methodParam);
        }
    }

    $invoke_params_join_str = [string]::Join(', ', $paramLocalNameList);

    # 2.1 Dynamic Parameter Assignment
    $dynamic_param_assignment_code_lines = @();
    $param_index = 1;
    foreach ($pt in $pruned_params)
    {
        $param_type_full_name = $pt.ParameterType.FullName;
        if (($param_type_full_name -like "I*Operations") -and ($param_type_full_name -eq 'operations'))
        {
            continue;
        }
        elseif ($param_type_full_name.EndsWith('CancellationToken'))
        {
            continue;
        }

        $is_string_list = Is-ListStringType $pt.ParameterType;
        $does_contain_only_strings = Get-StringTypes $pt.ParameterType;

        $param_name = Get-CamelCaseName $pt.Name;
        $expose_param_name = $param_name;
        if ($MethodInfo.Name.ToString() -eq "Get")
        {
            $is_manatory = "false";
        }
        elseif (($MethodInfo.Name.ToString() -eq "DeleteInstances") -and ($param_name -eq "InstanceIds"))
        {
            $is_manatory = "false";
        }
        else
        {
            $is_manatory = (-not $pt.IsOptional).ToString().ToLower();
        }
        $param_type_full_name = Get-NormalizedTypeName $pt.ParameterType;

        if ($expose_param_name -like '*Parameters')
        {
            $expose_param_name = $invoke_param_set_name + $expose_param_name;
        }

        $expose_param_name = Get-SingularNoun $expose_param_name;

        if (($does_contain_only_strings -eq $null) -or ($does_contain_only_strings.Count -eq 0))
        {
            # Complex Class Parameters
            $dynamic_param_assignment_code_lines +=
@"
            var p${param_name} = new RuntimeDefinedParameter();
            p${param_name}.Name = `"${expose_param_name}`";
"@;

            if ($is_string_list)
            {
                 $dynamic_param_assignment_code_lines += "            p${param_name}.ParameterType = typeof(string[]);";
            }
            else
            {
                 $dynamic_param_assignment_code_lines += "            p${param_name}.ParameterType = typeof($param_type_full_name);";
            }

            $allow_piping = ($param_type_full_name -eq $opSingularName).ToString().ToLower();

            $dynamic_param_assignment_code_lines +=
@"
            p${param_name}.Attributes.Add(new ParameterAttribute
            {
                ParameterSetName = "InvokeByDynamicParameters",
                Position = $param_index,
                Mandatory = $is_manatory,
                ValueFromPipeline = $allow_piping
            });
"@;
            if ($FriendMethodInfo -ne $null)
            {
                $dynamic_param_assignment_code_lines +=
@"
            p${param_name}.Attributes.Add(new ParameterAttribute
            {
                ParameterSetName = "InvokeByDynamicParametersForFriendMethod",
                Position = $param_index,
                Mandatory = $is_manatory,
                ValueFromPipeline = $allow_piping
            });
"@;
            }

            $dynamic_param_assignment_code_lines +=
@"
            p${param_name}.Attributes.Add(new AllowNullAttribute());
            dynamicParameters.Add(`"${expose_param_name}`", p${param_name});

"@;
            $param_index += 1;
        }
        else
        {
            # String Parameters
             foreach ($s in $does_contain_only_strings)
             {
                  $s = Get-SingularNoun $s;
                  $dynamic_param_assignment_code_lines +=
@"
            var p${s} = new RuntimeDefinedParameter();
            p${s}.Name = `"${s}`";
            p${s}.ParameterType = typeof(string);
            p${s}.Attributes.Add(new ParameterAttribute
            {
                ParameterSetName = "InvokeByDynamicParameters",
                Position = $param_index,
                Mandatory = false
            });
"@;
                  if ($FriendMethodInfo -ne $null)
                  {
                      $dynamic_param_assignment_code_lines +=
@"
            p${s}.Attributes.Add(new ParameterAttribute
            {
                ParameterSetName = "InvokeByDynamicParametersForFriendMethod",
                Position = $param_index,
                Mandatory = false
            });
"@;
                  }
                  $dynamic_param_assignment_code_lines +=
@"
            p${s}.Attributes.Add(new AllowNullAttribute());
            dynamicParameters.Add(`"${s}`", p${s});

"@;
                  $param_index += 1;
             }
        }
    }

    if ($GenerateArgumentListParameter)
    {
        $param_name = $expose_param_name = 'ArgumentList';
        $param_type_full_name = 'object[]';
        $dynamic_param_assignment_code_lines +=
@"
            var p${param_name} = new RuntimeDefinedParameter();
            p${param_name}.Name = `"${expose_param_name}`";
            p${param_name}.ParameterType = typeof($param_type_full_name);
            p${param_name}.Attributes.Add(new ParameterAttribute
            {
                ParameterSetName = "InvokeByStaticParameters",
                Position = $param_index,
                Mandatory = true
            });
"@;
        if ($FriendMethodInfo -ne $null)
        {
            $dynamic_param_assignment_code_lines +=
@"
            p${param_name}.Attributes.Add(new ParameterAttribute
            {
                ParameterSetName = "InvokeByStaticParametersForFriendMethod",
                Position = $param_index,
                Mandatory = true
            });
"@;
        }
        $dynamic_param_assignment_code_lines +=
@"
            p${param_name}.Attributes.Add(new AllowNullAttribute());
            dynamicParameters.Add(`"${expose_param_name}`", p${param_name});

"@;
    }

    $dynamic_param_assignment_code = [string]::Join($NEW_LINE, $dynamic_param_assignment_code_lines);
    if ($methodName -eq "Reimage")
    {
        $add_switch_param_code = "";
        $param_name = $expose_param_name = $methodName;
        $param_type_full_name = 'SwitchParameter';
        $add_switch_param_code +=
@"
            var p${param_name} = new RuntimeDefinedParameter();
            p${param_name}.Name = `"${expose_param_name}`";
            p${param_name}.ParameterType = typeof($param_type_full_name);
            p${param_name}.Attributes.Add(new ParameterAttribute
            {
                ParameterSetName = "InvokeByDynamicParameters",
                Position = $param_index,
                Mandatory = true
            });
            p${param_name}.Attributes.Add(new AllowNullAttribute());
            dynamicParameters.Add(`"${expose_param_name}`", p${param_name});

"@;
        $dynamic_param_assignment_code += $NEW_LINE;
        $dynamic_param_assignment_code += $add_switch_param_code;
    }

    if ($FriendMethodInfo -ne $null)
    {
        $friend_code = "";
        if ($FriendMethodInfo.Name -eq 'PowerOff')
        {
            $param_name = $expose_param_name = 'StayProvisioned';
        }
        else
        {
            $param_name = $expose_param_name = $FriendMethodInfo.Name.Replace($methodName, '');
        }

        $param_type_full_name = 'SwitchParameter';
        $static_param_index = $param_index + 1;
        $friend_code +=
@"
            var p${param_name} = new RuntimeDefinedParameter();
            p${param_name}.Name = `"${expose_param_name}`";
            p${param_name}.ParameterType = typeof($param_type_full_name);
            p${param_name}.Attributes.Add(new ParameterAttribute
            {
                ParameterSetName = "InvokeByDynamicParametersForFriendMethod",
                Position = $param_index,
                Mandatory = true
            });
            p${param_name}.Attributes.Add(new ParameterAttribute
            {
                ParameterSetName = "InvokeByStaticParametersForFriendMethod",
                Position = ${static_param_index},
                Mandatory = true
            });
            p${param_name}.Attributes.Add(new AllowNullAttribute());
            dynamicParameters.Add(`"${expose_param_name}`", p${param_name});

"@;

        $dynamic_param_assignment_code += $NEW_LINE;
        $dynamic_param_assignment_code += $friend_code;
    }

    $code +=
@"


    [Cmdlet(`"${mapped_verb_name}`", `"${mapped_noun_str}`", DefaultParameterSetName = `"InvokeByDynamicParameters`")]
    public partial class $verb_cmdlet_name : ${invoke_cmdlet_class_name}
    {
        public $verb_cmdlet_name()
        {
        }

        public override string MethodName { get; set; }

        protected override void ProcessRecord()
        {
"@;
    if ($FriendMethodInfo -ne $null)
    {
        $code += $NEW_LINE;
        $code += "            if (this.ParameterSetName == `"InvokeByDynamicParameters`")" + $NEW_LINE;
        $code += "            {" + $NEW_LINE;
        $code += "                this.MethodName = `"$invoke_param_set_name`";" + $NEW_LINE;
        $code += "            }" + $NEW_LINE;
        $code += "            else" + $NEW_LINE;
        $code += "            {" + $NEW_LINE;
        $code += "                this.MethodName = `"$invoke_param_set_name_for_friend`";" + $NEW_LINE;
        $code += "            }" + $NEW_LINE;
    }
    else
    {
        $code += $NEW_LINE;
        $code += "            this.MethodName = `"$invoke_param_set_name`";" + $NEW_LINE;
    }

    $code +=
@"
            base.ProcessRecord();
        }

        public override object GetDynamicParameters()
        {
            dynamicParameters = new RuntimeDefinedParameterDictionary();
$dynamic_param_assignment_code
            return dynamicParameters;
        }
    }
"@;

    # 3. End
    $code += "";
    if ($methodName -eq "CreateOrUpdate")
    {
        $update_code = $code.Replace("New", "Update");
    }
    $code += $update_code

    return $code;
}

Generate-PsFunctionCommandImpl $OperationName $MethodInfo $FileOutputFolder $FriendMethodInfo;

# CLI Function Command Code
$opItem = $cliOperationSettings[$OperationName];
if ($opItem -contains $MethodInfo.Name)
{
    return '';
}
else
{
    switch ($MethodInfo.Name) {
         "CreateOrUpdate" {
             $code = (. $PSScriptRoot\Generate-CliCreateCommand.ps1 -OperationName $OperationName `
                                                                          -MethodInfo $MethodInfo `
                                                                          -ModelNameSpace $ModelClassNameSpace  `
                                                                          -FileOutputFolder $FileOutputFolder);
             break;
         }

         "Get" {
             $code = (. $PSScriptRoot\Generate-CliShowCommand.ps1 -OperationName $OperationName `
                                                                          -MethodInfo $MethodInfo `
                                                                          -ModelNameSpace $ModelClassNameSpace  `
                                                                          -FileOutputFolder $FileOutputFolder);
             break;
         }
        "Delete" {
             $code = (. $PSScriptRoot\Generate-CliDeleteCommand.ps1 -OperationName $OperationName `
                                                                          -MethodInfo $MethodInfo `
                                                                          -ModelNameSpace $ModelClassNameSpace  `
                                                                          -FileOutputFolder $FileOutputFolder);
             break;
         }
        "List" {
             $code = (. $PSScriptRoot\Generate-CliListCommand.ps1 -OperationName $OperationName `
                                                                          -MethodInfo $MethodInfo `
                                                                          -ModelNameSpace $ModelClassNameSpace  `
                                                                          -FileOutputFolder $FileOutputFolder);
             break;
         }
         default {
             return ""
         }
     }



    return '' + $code;
}