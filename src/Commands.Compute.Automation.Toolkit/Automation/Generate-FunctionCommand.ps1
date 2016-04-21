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

# azure vm get
function Generate-CliFunctionCommandImpl
{
    param
    (
        # VirtualMachine, VirtualMachineScaleSet, etc.
        [Parameter(Mandatory = $true)]
        [string]$OperationName,

        [Parameter(Mandatory = $true)]
        [System.Reflection.MethodInfo]$MethodInfo,
    
        [Parameter(Mandatory = $true)]
        [string]$ModelNameSpace,

        [Parameter(Mandatory = $false)]
        [string]$FileOutputFolder = $null
    )

    # Skip Pagination Function
    if (CheckIf-PaginationMethod $MethodInfo)
    {
        return;
    }

    $methodParameters = $MethodInfo.GetParameters();
    $methodName = ($MethodInfo.Name.Replace('Async', ''));
    
    $methodParamNameList = @();
    $methodParamTypeDict = @{};
    $allStringFieldCheck = @{};
    $oneStringListCheck = @{};

    $componentName = Get-ComponentName $ModelClassNameSpace;
    $componentNameInLowerCase = $componentName.ToLower();
    
    # i.e. --virtual-machine-scale-set
    $opCliOptionName = Get-CliOptionName $OperationName;

    # 3. CLI Code
    # 3.1 Types
    $methodParamIndex = 0;
    foreach ($paramItem in $methodParameters)
    {
        [System.Type]$paramType = $paramItem.ParameterType;
        if (($paramType.Name -like "I*Operations") -and ($paramItem.Name -eq 'operations'))
        {
            continue;
        }
        elseif ($paramType.FullName.EndsWith('CancellationToken'))
        {
            continue;
        }
        elseif ($paramItem.Name -eq 'odataQuery')
        {
            continue;
        }
        elseif ($paramType.IsEquivalentTo([string]) -and $paramItem.Name -eq 'select')
        {
            continue;
        }
        else
        {
            # Record the Normalized Parameter Name, i.e. 'vmName' => 'VMName', 'resourceGroup' => 'ResourceGroup', etc.
            $methodParamName = (Get-CamelCaseName $paramItem.Name);
            # Limit the changes only for ACS for now
            if ($OperationName -like "ContainerService*")
            {
                $methodParamName = (Get-CliMethodMappedParameterName $methodParamName $methodParamIndex);
            }
            $methodParamNameList += $methodParamName;
            $methodParamTypeDict.Add($paramItem.Name, $paramType);
            $allStringFields = Contains-OnlyStringFields $paramType;
            $allStringFieldCheck.Add($paramItem.Name, $allStringFields);
            $oneStringList = Contains-OnlyStringList $paramType;
            $oneStringListCheck.Add($paramItem.Name, $oneStringList);

            if ($paramType.Namespace -like $ModelNameSpace)
            {
                # If the namespace is like 'Microsoft.Azure.Management.*.Models', generate commands for the complex parameter
                
                # 3.1.1 Create the Parameter Object, and convert it to JSON code text format
                $param_object = (. $PSScriptRoot\Create-ParameterObject.ps1 -typeInfo $paramType);
                $param_object_comment = (. $PSScriptRoot\ConvertTo-Json.ps1 -inputObject $param_object -compress $true);
                $param_object_comment_no_compress = (. $PSScriptRoot\ConvertTo-Json.ps1 -inputObject $param_object);
                
                # 3.1.2 Create a parameter tree that represents the complext object
                $cmdlet_tree = (. $PSScriptRoot\Create-ParameterTree.ps1 -TypeInfo $paramType -NameSpace $ModelNameSpace -ParameterName $paramType.Name);

                # 3.1.3 Generate the parameter command according to the parameter tree
                $cmdlet_tree_code = (. $PSScriptRoot\Generate-ParameterCommand.ps1 -CmdletTreeNode $cmdlet_tree -Operation $opShortName -ModelNameSpace $ModelNameSpace -MethodName $methodName -OutputFolder $FileOutputFolder);
            }
        }
        $methodParamIndex += 1;
    }
    
    # 3.2 Functions
    
    # 3.2.1 Compute the CLI Category Name, i.e. VirtualMachineScaleSet => vmss, VirtualMachineScaleSetVM => vmssvm
    $cliCategoryName = Get-CliCategoryName $OperationName;
    
    # 3.2.2 Compute the CLI Operation Name, i.e. VirtualMachineScaleSets => virtualMachineScaleSets, VirtualMachineScaleSetVM => virtualMachineScaleSetVMs
    $cliOperationName = Get-CliNormalizedName $OperationName;
    
    # 3.2.3 Normalize the CLI Method Name, i.e. CreateOrUpdate => createOrUpdate, ListAll => listAll
    $cliMethodName = Get-CliNormalizedName $methodName;
    $cliCategoryVarName = $cliOperationName + $methodName;
    # Use Mapped CLI Method Name for ACS for now
    if ($OperationName -like "ContainerService*")
    {
        $mappedMethodName = Get-CliMethodMappedFunctionName $methodName;
    }
    else
    {
        $mappedMethodName = $methodName;
    }
    $cliMethodOption = Get-CliOptionName $mappedMethodName;

    # 3.2.4 Compute the CLI Command Description, i.e. VirtualMachineScaleSet => virtual machine scale set
    $cliOperationDescription = (Get-CliOptionName $OperationName).Replace('-', ' ');
    
    # 3.2.5 Generate the CLI Command Comment
    $cliOperationComment = "/*" + $NEW_LINE;
    $cliOperationComment += "  " + $OperationName + " " + $methodName + $NEW_LINE;
    for ($index = 0; $index -lt $methodParamNameList.Count; $index++)
    {
        $cli_option_name = Get-CliOptionName $methodParamNameList[$index];
        $cliOperationComment += "  --" + (Get-CliOptionName $methodParamNameList[$index]) + $NEW_LINE;
    }

    if ($param_object_comment_no_compress -ne $null -and $param_object_comment_no_compress.Trim() -ne '')
    {
        $cliOperationComment += $BAR_LINE + $NEW_LINE;
        $cliOperationComment += $param_object_comment_no_compress + $NEW_LINE;
    }

    $cliOperationComment += "*/" + $NEW_LINE;
    
    # 3.2.6 Generate the CLI Command Code
    $code = "";
    $code += $cliOperationComment;

    if ($ModelNameSpace -like "*.WindowsAzure.*")
    {
        # Use Invoke Category for RDFE APIs
        $invoke_category_desc = "Commands to invoke service management operations.";
        $invoke_category_code = ".category('invoke').description('${invoke_category_desc}')";
    }
    
    $code += "  var $cliCategoryVarName = cli${invoke_category_code}.category('${cliCategoryName}')" + $NEW_LINE;

    # 3.2.7 Description Text
    $desc_text = "Commands to manage your ${cliOperationDescription}.";
    $desc_text_lines = Get-SplitTextLines $desc_text 80;
    $code += "  .description(`$('";
    $code += [string]::Join("'" + $NEW_LINE + "  + '", $desc_text_lines);
    $code += "  '));" + $NEW_LINE;

    # Set Required Parameters
    $requireParams = @();
    $requireParamNormalizedNames = @();
    for ($index = 0; $index -lt $methodParamNameList.Count; $index++)
    {
        # Parameter Declaration - For Each Method Parameter
        [string]$optionParamName = $methodParamNameList[$index];
        if ($allStringFieldCheck[$optionParamName])
        {
            [System.Type]$optionParamType = $methodParamTypeDict[$optionParamName];
            foreach ($propItem in $optionParamType.GetProperties())
            {
                [System.Reflection.PropertyInfo]$propInfoItem = $propItem;
                $cli_option_name = Get-CliOptionName $propInfoItem.Name;
                $requireParams += $cli_option_name;
                $requireParamNormalizedNames += (Get-CliNormalizedName $propInfoItem.Name);
            }
        }
        else
        {
            $cli_option_name = Get-CliOptionName $optionParamName;
            $requireParams += $cli_option_name;
            $requireParamNormalizedNames += (Get-CliNormalizedName $optionParamName);
        }
    }

    $requireParamsString = $null;
    $usageParamsString = $null;
    $optionParamString = $null;
    if ($requireParams.Count -gt 0)
    {
        $requireParamsJoinStr = "] [";
        $requireParamsString = " [" + ([string]::Join($requireParamsJoinStr, $requireParams)) + "]";
        
        $usageParamsJoinStr = "> <";
        $usageParamsString = " <" + ([string]::Join($usageParamsJoinStr, $requireParams)) + ">";
        $optionParamString = ([string]::Join(", ", $requireParamNormalizedNames)) + ", ";
    }

    if ($xmlDocItems -ne $null)
    {
        $xmlHelpText = "";
        foreach ($helpItem in $xmlDocItems)
        {
            $helpSearchStr = "M:${ClientNameSpace}.${OperationName}OperationsExtensions.${methodName}(*)";
            if ($helpItem.name -like $helpSearchStr)
            {
                $helpLines = $helpItem.summary.Split("`r").Split("`n");
                foreach ($helpLine in $helpLines)
                {
                    $xmlHelpText += (' ' + $helpLine.Trim());
                }
                $xmlHelpText = $xmlHelpText.Trim();
                break;
            }
        }
    }

    $code += "  ${cliCategoryVarName}.command('${cliMethodOption}${requireParamsString}')" + $NEW_LINE;
    #$code += "  .description(`$('Commands to manage your $cliOperationDescription by the ${cliMethodOption} method.${xmlHelpText}'))" + $NEW_LINE;
    $code += "  .description(`$('${xmlHelpText}'))" + $NEW_LINE;
    $code += "  .usage('[options]${usageParamsString}')" + $NEW_LINE;
    $option_str_items = @();
    $use_input_parameter_file = $false;
    for ($index = 0; $index -lt $methodParamNameList.Count; $index++)
    {
        # Parameter Declaration - For Each Method Parameter
        [string]$optionParamName = $methodParamNameList[$index];
        $optionShorthandStr = $null;
        if ($allStringFieldCheck[$optionParamName])
        {
            [System.Type]$optionParamType = $methodParamTypeDict[$optionParamName];
            $subIndex = 0;
            foreach ($propItem in $optionParamType.GetProperties())
            {
                [System.Reflection.PropertyInfo]$propInfoItem = $propItem;
                $cli_option_name = Get-CliOptionName $propInfoItem.Name;
                $cli_shorthand_str = Get-CliShorthandName $propInfoItem.Name;
                if ($cli_shorthand_str -ne '')
                {
                    $cli_shorthand_str = "-" + $cli_shorthand_str + ", ";
                }
                $code += "  .option('${cli_shorthand_str}--${cli_option_name} <${cli_option_name}>', `$('${cli_option_name}'))" + $NEW_LINE;
                $option_str_items += "--${cli_option_name} `$p${index}${subIndex}";
                $subIndex++;
            }
        }
        else
        {
            $cli_option_name = Get-CliOptionName $optionParamName;
            $cli_shorthand_str = Get-CliShorthandName $optionParamName;
            if ($cli_shorthand_str -ne '')
            {
                $cli_shorthand_str = "-" + $cli_shorthand_str + ", ";
            }
            $cli_option_help_text = $cli_option_name;
            if ($cli_option_name -eq 'parameters')
            {
                $cli_option_help_text = 'A string of parameters in JSON format';
                $use_input_parameter_file = $true;
            }
            $code += "  .option('${cli_shorthand_str}--${cli_option_name} <${cli_option_name}>', `$('${cli_option_help_text}'))" + $NEW_LINE;
            $option_str_items += "--${cli_option_name} `$p${index}";
        }
    }

    if ($use_input_parameter_file)
    {
        $code += "  .option('--parameter-file <parameter-file>', `$('The text file that contains input parameter object in JSON format'))" + $NEW_LINE;
        $option_str_items += "--parameter-file `$f";
    }
    $code += "  .option('-s, --subscription <subscription>', `$('The subscription identifier'))" + $NEW_LINE;
    $code += "  .execute(function(${optionParamString}options, _) {" + $NEW_LINE;

    for ($index = 0; $index -lt $methodParamNameList.Count; $index++)
    {
        # Parameter Assignment - For Each Method Parameter
        [string]$optionParamName = $methodParamNameList[$index];
        [string]$cli_option_name = Get-CliOptionName $optionParamName;

        if ($allStringFieldCheck[$optionParamName])
        {
            [System.Type]$optionParamType = $methodParamTypeDict[$optionParamName];
            $cli_param_name = Get-CliNormalizedName $optionParamName;

            $code += "    var ${cli_param_name}Obj = null;" + $NEW_LINE;
            $code += "    if (options.parameterFile) {" + $NEW_LINE;
            $code += "      cli.output.verbose(`'Reading file content from: \`"`' + options.parameterFile + `'\`"`');" + $NEW_LINE;
            $code += "      var ${cli_param_name}FileContent = fs.readFileSync(options.parameterFile, 'utf8');" + $NEW_LINE;
            $code += "      ${cli_param_name}Obj = JSON.parse(${cli_param_name}FileContent);" + $NEW_LINE;
            $code += "    }" + $NEW_LINE;
            $code += "    else {" + $NEW_LINE;
            $code += "      ${cli_param_name}Obj = {};" + $NEW_LINE;
            
            foreach ($propItem in $optionParamType.GetProperties())
            {
                [System.Reflection.PropertyInfo]$propInfoItem = $propItem;
                $cli_op_param_name = Get-CliNormalizedName $propInfoItem.Name;
                $code += "      cli.output.verbose('${cli_op_param_name} = ' + ${cli_op_param_name});" + $NEW_LINE;
                $code += "      ${cli_param_name}Obj.${cli_op_param_name} = ${cli_op_param_name};" + $NEW_LINE;
            }

            $code += "    }" + $NEW_LINE;
            $code += "    cli.output.verbose('${cli_param_name}Obj = ' + JSON.stringify(${cli_param_name}Obj));" + $NEW_LINE;
        }
        else
        {
            $cli_param_name = Get-CliNormalizedName $optionParamName;
            if ((${cli_param_name} -eq 'Parameters') -or (${cli_param_name} -like '*InstanceIds'))
            {
                $code += "    cli.output.verbose('${cli_param_name} = ' + ${cli_param_name});" + $NEW_LINE;
                $code += "    var ${cli_param_name}Obj = null;" + $NEW_LINE;
                $code += "    if (options.parameterFile) {" + $NEW_LINE;
                $code += "      cli.output.verbose(`'Reading file content from: \`"`' + options.parameterFile + `'\`"`');" + $NEW_LINE;
                $code += "      var fileContent = fs.readFileSync(options.parameterFile, 'utf8');" + $NEW_LINE;
                $code += "      ${cli_param_name}Obj = JSON.parse(fileContent);" + $NEW_LINE;
                $code += "    }" + $NEW_LINE;
                $code += "    else {" + $NEW_LINE;
                    
                if ($oneStringListCheck[$optionParamName])
                {
                    $code += "      var ${cli_param_name}ValArr = ${cli_param_name} ? ${cli_param_name}.split(',') : [];" + $NEW_LINE;
                    $code += "      cli.output.verbose(`'${cli_param_name} : `' + ${cli_param_name}ValArr);" + $NEW_LINE;
                    #$code += "      ${cli_param_name}Obj = {};" + $NEW_LINE;
                    #$code += "      ${cli_param_name}Obj.instanceIDs = ${cli_param_name}ValArr;" + $NEW_LINE;
                    $code += "      ${cli_param_name}Obj = [];" + $NEW_LINE;
                    $code += "      for (var item in ${cli_param_name}ValArr) {" + $NEW_LINE;
                    $code += "        ${cli_param_name}Obj.push(${cli_param_name}ValArr[item]);" + $NEW_LINE;
                    $code += "      }" + $NEW_LINE;

                    if ($cliMethodName -like "Start" -or `
                        $cliMethodName -like "Restart" -or `
                        $cliMethodName -like "PowerOff" -or `
                        $cliMethodName -like "Deallocate" -or `
                        $cliMethodName -like "Stop")
                    {
                        $code += "      ${cli_param_name}Obj = { '${cli_param_name}' : ${cli_param_name}Obj};" + $NEW_LINE;
                    }
                }
                else
                {
                    $code += "      ${cli_param_name}Obj = JSON.parse(${cli_param_name});" + $NEW_LINE;
                }

                $code += "    }" + $NEW_LINE;
                $code += "    cli.output.verbose('${cli_param_name}Obj = ' + JSON.stringify(${cli_param_name}Obj));" + $NEW_LINE;
            }
            else
            {
                # Prompt Users If Required Parameters Not Specified
                $code += "    if (!${cli_param_name}) {" + $NEW_LINE;
                $code += "      ${cli_param_name} = cli.interaction.promptIfNotGiven(`$('${cli_option_name} : '), ${cli_param_name}, _);" + $NEW_LINE;
                $code += "    }" + $NEW_LINE;
                $code += $NEW_LINE;
                $code += "    cli.output.verbose('${cli_param_name} = ' + ${cli_param_name});" + $NEW_LINE;
            }
        }
    }
    $code += "    var subscription = profile.current.getSubscription(options.subscription);" + $NEW_LINE;

    if ($ModelNameSpace.Contains(".WindowsAzure."))
    {
        $code += "    var ${componentNameInLowerCase}ManagementClient = utils.create${componentName}Client(subscription);" + $NEW_LINE;
    }
    else
    {
        $code += "    var ${componentNameInLowerCase}ManagementClient = utils.create${componentName}ManagementClient(subscription);" + $NEW_LINE;
    }

    if ($cliMethodName -eq 'delete')
    {
        $cliMethodFuncName = $cliMethodName + 'Method';
    }
    else
    {
        $cliMethodFuncName = $cliMethodName;
    }

    if ($cliOperationName -like "containerService*" -or $cliOperationName -like "usage*")
    {
        $code += "    var result = ${componentNameInLowerCase}ManagementClient.${cliOperationName}Operations.${cliMethodFuncName}(";
    }
    else
    {
        $code += "    var result = ${componentNameInLowerCase}ManagementClient.${cliOperationName}.${cliMethodFuncName}(";
    }

    for ($index = 0; $index -lt $methodParamNameList.Count; $index++)
    {
        # Function Call - For Each Method Parameter
        $cli_param_name = Get-CliNormalizedName $methodParamNameList[$index];
        if ((${cli_param_name} -eq 'Parameters') -or (${cli_param_name} -like '*InstanceIds'))
        {
            $code += "${cli_param_name}Obj";
        }
        else
        {
            $code += "${cli_param_name}";
        }

        $code += ", ";
    }

    $code += "_);" + $NEW_LINE;

    if ($PageMethodInfo -ne $null)
    {
        $code += "    var nextPageLink = result.nextPageLink;" + $NEW_LINE;
        $code += "    while (nextPageLink) {" + $NEW_LINE;
        $code += "      var pageResult = ${componentNameInLowerCase}ManagementClient.${cliOperationName}.${cliMethodFuncName}Next(nextPageLink, _);" + $NEW_LINE;
        $code += "      pageResult.forEach(function(item) {" + $NEW_LINE;
        $code += "        result.push(item);" + $NEW_LINE;
        $code += "      });" + $NEW_LINE;
        $code += "      nextPageLink = pageResult.nextPageLink;" + $NEW_LINE;
        $code += "    }" + $NEW_LINE;
        $code += "" + $NEW_LINE;
    }

    if ($PageMethodInfo -ne $null -and $methodName -ne 'ListSkus')
    {
        $code += "    if (cli.output.format().json) {" + $NEW_LINE;
        $code += "      cli.output.json(result);" + $NEW_LINE;
        $code += "    }" + $NEW_LINE;
        $code += "    else {" + $NEW_LINE;
        $code += "      cli.output.table(result, function (row, item) {" + $NEW_LINE;
        $code += "        var rgName = item.id ? utils.parseResourceReferenceUri(item.id).resourceGroupName : null;" + $NEW_LINE;
        $code += "        row.cell(`$('ResourceGroupName'), rgName);" + $NEW_LINE;
        $code += "        row.cell(`$('Name'), item.name);" + $NEW_LINE;
        $code += "        row.cell(`$('ProvisioningState'), item.provisioningState);" + $NEW_LINE;
        $code += "        row.cell(`$('Location'), item.location);" + $NEW_LINE;
        $code += "      });" + $NEW_LINE;
        $code += "    }" + $NEW_LINE;
    }  
    elseif ($methodName -eq 'Get' -or $methodName -eq 'GetInstanceView')
    {
        $code += "    if (cli.output.format().json) {" + $NEW_LINE;
        $code += "      cli.output.json(result);" + $NEW_LINE;
        $code += "    }" + $NEW_LINE;
        $code += "    else {" + $NEW_LINE;
        $code += "      display(cli, result);" + $NEW_LINE;
        $code += "    }" + $NEW_LINE;
    }
    else
    {
        $code += "    if (result) {" + $NEW_LINE;
        $code += "      cli.output.json(result);" + $NEW_LINE;
        $code += "    }" + $NEW_LINE;
    }
    $code += "  });" + $NEW_LINE;

    # 3.2.8 Sample Code;
    $global:cli_sample_code_lines += "azure ${cliCategoryName} ${cliMethodOption} ${NEW_LINE}" + ([string]::Join($NEW_LINE, $option_str_items)) + $NEW_LINE;
    $global:cli_sample_code_lines += $NEW_LINE;

    # 3.3 Parameters
    for ($index = 0; $index -lt $methodParamNameList.Count; $index++)
    {
        [string]$optionParamName = $methodParamNameList[$index];
        if ($allStringFieldCheck[$optionParamName])
        {
            # Skip all-string parameters that are already handled in the function command.
            continue;
        }

        $cli_param_name = Get-CliNormalizedName $methodParamNameList[$index];
        if ($cli_param_name -eq 'Parameters')
        {
            if ($cliMethodOption -eq "create-or-update" -or $cliMethodOption -eq "create")
            {
                $cliParamCmdSubCatName = 'config';
            }
            else
            {
                $cliParamCmdSubCatName = $cliMethodOption + '-parameters';
            }

            $params_category_var_name = "${cliCategoryVarName}${cliMethodName}Parameters" + $index;
            if ($OperationName -like "ContainerService*")
            {
                $action_category_name = 'create';
            }
            else
            {
                $action_category_name = 'generate';
            }
            $params_generate_category_var_name = "${cliCategoryVarName}${cliMethodName}Generate" + $index;

            # 3.3.1 Parameter Generate Command
            $code += "  var ${params_category_var_name} = ${cliCategoryVarName}.category('${cliParamCmdSubCatName}')" + $NEW_LINE;
            #$code += "  .description(`$('Commands to generate parameter input file for your ${cliOperationDescription}.'));" + $NEW_LINE;
            $code += "  .description(`$('Commands to manage configuration of ${opCliOptionName} in the parameter file.'));" + $NEW_LINE;

            $code += "  ${params_category_var_name}.command('${action_category_name}')" + $NEW_LINE;
            $code += "  .description(`$('Generate ${cliCategoryVarName} parameter string or files.'))" + $NEW_LINE;
            $code += "  .usage('[options]')" + $NEW_LINE;
            $code += "  .option('--parameter-file <parameter-file>', `$('The parameter file path.'))" + $NEW_LINE;
            $code += "  .execute(function(options, _) {" + $NEW_LINE;

            $output_content = $param_object_comment.Replace("`"", "\`"");
            $code += "    cli.output.verbose(`'" + $output_content + "`', _);" + $NEW_LINE;

            $file_content = $param_object_comment_no_compress.Replace($NEW_LINE, "\r\n").Replace("`r", "\r").Replace("`n", "\n");
            $file_content = $file_content.Replace("`"", "\`"").Replace(' ', '');
            $code += "    var filePath = `'${cliCategoryVarName}_${cliMethodName}.json`';" + $NEW_LINE;
            $code += "    if (options.parameterFile) {" + $NEW_LINE;
            $code += "      filePath = options.parameterFile;" + $NEW_LINE;
            $code += "    }" + $NEW_LINE;
            $code += "    fs.writeFileSync(filePath, beautify(`'" + $file_content + "`'));" + $NEW_LINE;
            $code += "    cli.output.verbose(`'=====================================`');" + $NEW_LINE;
            $code += "    cli.output.verbose(`'Parameter file output to: `' + filePath);" + $NEW_LINE;
            $code += "    cli.output.verbose(`'=====================================`');" + $NEW_LINE;
            $code += "  });" + $NEW_LINE;
            $code += $NEW_LINE;

            # 3.3.2 Parameter Patch Command
            $code += "  ${params_category_var_name}.command('patch')" + $NEW_LINE;
            $code += "  .description(`$('Command to patch ${cliCategoryVarName} parameter JSON file.'))" + $NEW_LINE;
            $code += "  .usage('[options]')" + $NEW_LINE;
            $code += "  .option('--parameter-file <parameter-file>', `$('The parameter file path.'))" + $NEW_LINE;
            $code += "  .option('--operation <operation>', `$('The JSON patch operation: add, remove, or replace.'))" + $NEW_LINE;
            $code += "  .option('--path <path>', `$('The JSON data path, e.g.: \`"foo/1\`".'))" + $NEW_LINE;
            $code += "  .option('--value <value>', `$('The JSON value.'))" + $NEW_LINE;
            $code += "  .option('--parse', `$('Parse the JSON value to object.'))" + $NEW_LINE;
            $code += "  .execute(function(options, _) {" + $NEW_LINE;
            $code += "    cli.output.verbose(options.parameterFile, _);" + $NEW_LINE;
            $code += "    cli.output.verbose(options.operation);" + $NEW_LINE;
            $code += "    cli.output.verbose(options.path);" + $NEW_LINE;
            $code += "    cli.output.verbose(options.value);" + $NEW_LINE;
            $code += "    cli.output.verbose(options.parse);" + $NEW_LINE;
            $code += "    if (options.parse) {" + $NEW_LINE;
            $code += "      options.value = JSON.parse(options.value);" + $NEW_LINE;
            $code += "    }" + $NEW_LINE;
            $code += "    cli.output.verbose(options.value);" + $NEW_LINE;
            $code += "    cli.output.verbose(`'=====================================`');" + $NEW_LINE;
            $code += "    cli.output.verbose(`'Reading file content from: \`"`' + options.parameterFile + `'\`"`');" + $NEW_LINE;
            $code += "    cli.output.verbose(`'=====================================`');" + $NEW_LINE;
            $code += "    var fileContent = fs.readFileSync(options.parameterFile, 'utf8');" + $NEW_LINE;
            $code += "    var ${cli_param_name}Obj = JSON.parse(fileContent);" + $NEW_LINE;
            $code += "    cli.output.verbose(`'JSON object:`');" + $NEW_LINE;
            $code += "    cli.output.verbose(JSON.stringify(${cli_param_name}Obj));" + $NEW_LINE;
            $code += "    if (options.operation == 'add') {" + $NEW_LINE;
            $code += "      jsonpatch.apply(${cli_param_name}Obj, [{op: options.operation, path: options.path, value: options.value}]);" + $NEW_LINE;
            $code += "    }" + $NEW_LINE;
            $code += "    else if (options.operation == 'remove') {" + $NEW_LINE;
            $code += "      jsonpatch.apply(${cli_param_name}Obj, [{op: options.operation, path: options.path}]);" + $NEW_LINE;
            $code += "    }" + $NEW_LINE;
            $code += "    else if (options.operation == 'replace') {" + $NEW_LINE;
            $code += "      jsonpatch.apply(${cli_param_name}Obj, [{op: options.operation, path: options.path, value: options.value}]);" + $NEW_LINE;
            $code += "    }" + $NEW_LINE;
            $code += "    var updatedContent = JSON.stringify(${cli_param_name}Obj);" + $NEW_LINE;
            $code += "    cli.output.verbose(`'=====================================`');" + $NEW_LINE;
            $code += "    cli.output.verbose(`'JSON object (updated):`');" + $NEW_LINE;
            $code += "    cli.output.verbose(JSON.stringify(${cli_param_name}Obj));" + $NEW_LINE;
            $code += "    cli.output.verbose(`'=====================================`');" + $NEW_LINE;
            $code += "    fs.writeFileSync(options.parameterFile, beautify(updatedContent));" + $NEW_LINE;
            $code += "    cli.output.verbose(`'=====================================`');" + $NEW_LINE;
            $code += "    cli.output.verbose(`'Parameter file updated at: `' + options.parameterFile);" + $NEW_LINE;
            $code += "    cli.output.verbose(`'=====================================`');" + $NEW_LINE;
            $code += "  });" + $NEW_LINE;
            $code += $NEW_LINE;

            # 3.3.3 Parameter Commands
            $code += $cmdlet_tree_code + $NEW_LINE;
            
            # 3.3.4 Parameter Sample Commands
            $global:cli_sample_code_lines += "azure ${cliCategoryName} ${cliParamCmdSubCatName} generate ${NEW_LINE}--parameter-file `$f" + $NEW_LINE;
            $global:cli_sample_code_lines += $NEW_LINE;
            $global:cli_sample_code_lines += "azure ${cliCategoryName} ${cliParamCmdSubCatName} patch ${NEW_LINE}--parameter-file `$f" + $NEW_LINE;
            $global:cli_sample_code_lines += $NEW_LINE;

            break;
        }
    }

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
    $code = Generate-CliFunctionCommandImpl $OperationName $MethodInfo $ModelClassNameSpace $FileOutputFolder;
    return '' + $code;
}