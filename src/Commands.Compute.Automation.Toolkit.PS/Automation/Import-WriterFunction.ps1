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

function Write-CmdletCodeFile
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$FilePath,
        
        [Parameter(Mandatory = $true)]
        [string]$CodeContent
    )

    # Write Header
    $code = '';
    $code += $code_common_header + $NEW_LINE;
    $code += $NEW_LINE;
    $code += $code_using_strs + $NEW_LINE;
    $code += $NEW_LINE;

    # Write Name Space & Starting Bracket
    $code += "namespace ${code_common_namespace}" + $NEW_LINE;
    $code += "{" + $NEW_LINE;

    # Write Content
    $code += $CodeContent + $NEW_LINE;

    # Write Ending Bracket
    $code += "}";

    $st = Set-FileContent -Path $FilePath -Value $code;
}

function Set-FileContent
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$Path,
        
        [Parameter(Mandatory = $true)]
        $Value
    )
    
    $iteration = 0;
    $maxIteration = 10;
    while ($iteration -lt $maxIteration)
    {
        $iteration = $iteration + 1;
        try
        {
            $iteration = Set-Content -Path $Path -Value $Value -Force;
        }
        catch
        {
            if (($_.Exception.Message -like "*Stream was not readable.") `
            -or ($_.Exception.Message -like "The process cannot access the file*"))
            {
                $fileName = Split-Path $Path -Leaf;
                [string]$message = $_.Exception.Message;
                [string]$shortMsg = $message.SubString(0, [System.Math]::Min(30, $message.Length));
                Write-Warning "#${iteration}:File=${fileName};Error=${shortMsg}...";
                sleep -Milliseconds 10;
            }
            else
            {
                Write-Error $_.Exception.Message;
                return;
            }
        }

        break;
    }

    if ($_ -ne $null -and $_.Exception -ne $null)
    {
        Write-Error $_.Exception.Message;
    }
}


function Write-PSArgumentFile
{
    param(
        [Parameter(Mandatory = $True)]
        [string]$file_full_path
    )

    $model_source_code_text =
@"
${code_common_header}

$code_using_strs

namespace ${code_model_namespace}
{
    public class PSArgument
    {
        public string Name { get; set; }

        public Type Type { get; set; }

        public object Value { get; set; }
    }
}
"@;

    $st = Set-FileContent -Path $file_full_path -Value $model_source_code_text;
}

function Write-BaseCmdletFile
{
    # e.g.
    # public abstract class ComputeAutomationBaseCmdlet : Microsoft.WindowsAzure.Commands.Utilities.Common.ServiceManagementBaseCmdlet
    param(
        [Parameter(Mandatory = $True)]
        [string]$file_full_path,

        [Parameter(Mandatory = $True)]
        $operation_name_list,

        [Parameter(Mandatory = $True)]
        $client_class_info
    )

    [System.Reflection.PropertyInfo[]]$propItems = $client_class_info.GetProperties();

    $operation_get_code = "";
    foreach ($operation_name in $operation_name_list)
    {
        # Write-Verbose ('Operation Name = ' + $operation_name);
        $opShortName = Get-OperationShortName $operation_name;
        $opPropName = $opShortName;
        foreach ($propItem in $propItems)
        {
            if ($propItem.PropertyType.Name -eq ('I' + $opShortName + 'Operations'))
            {
                $opPropName = $propItem.Name;
                break;
            }
        }

        $operation_get_template = 
@"
        public I${opShortName}Operations $($opShortName)Client
        {
            get
            {
                return ${baseClientFullName}.${opPropName};
            }
        }
"@;

        if (-not ($operation_get_code -eq ""))
        {
            $operation_get_code += ($NEW_LINE * 2);
        }

        $operation_get_code += $operation_get_template;
    }

    $cmdlet_source_code_text =
@"
${code_common_header}

$code_using_strs

namespace ${code_common_namespace}
{
    public abstract class ${component_name}AutomationBaseCmdlet : $baseCmdletFullName
    {
        protected static PSArgument[] ConvertFromObjectsToArguments(string[] names, object[] objects)
        {
            var arguments = new PSArgument[objects.Length];
            
            for (int index = 0; index < objects.Length; index++)
            {
                arguments[index] = new PSArgument
                {
                    Name = names[index],
                    Type = objects[index].GetType(),
                    Value = objects[index]
                };
            }

            return arguments;
        }

        protected static object[] ConvertFromArgumentsToObjects(object[] arguments)
        {
            if (arguments == null)
            {
                return null;
            }

            var objects = new object[arguments.Length];
            
            for (int index = 0; index < arguments.Length; index++)
            {
                if (arguments[index] is PSArgument)
                {
                    objects[index] = ((PSArgument)arguments[index]).Value;
                }
                else
                {
                    objects[index] = arguments[index];
                }
            }

            return objects;
        }

${operation_get_code}
    }
}
"@;

    $st = Set-FileContent -Path $file_full_path -Value $cmdlet_source_code_text;
}

# Write Invoke Compute Client Cmdlet
function Write-InvokeCmdletFile
{
    # e.g.
    # public partial class InvokeAzureComputeMethodCmdlet : ComputeAutomationBaseCmdlet, IDynamicParameters

    param(
        [Parameter(Mandatory = $True)]
        [string]$file_full_path,

        [Parameter(Mandatory = $True)]
        [string]$invoke_cmdlet_name,

        [Parameter(Mandatory = $True)]
        [string]$base_cmdlet_name,

        [Parameter(Mandatory = $True)]
        $client_class_info,

        [Parameter(Mandatory = $True)]
        $operation_type_list,

        [Parameter(Mandatory = $True)]
        $invoke_cmdlet_method_code,

        [Parameter(Mandatory = $True)]
        $dynamic_param_method_code,

        [Parameter(Mandatory = $false)]
        [bool] $generate_cmdlet = $true
    )

    $indents = " " * 8;
    $get_set_block = '{ get; set; }';

    $cmdlet_verb = "Invoke";
    $cmdlet_verb_code = $verbs_lifecycle_invoke;

    $cmdlet_file_name_suffix = 'Cmdlet'
    $cmdlet_class_name = $cmdlet_verb + $invoke_cmdlet_name.Replace($cmdlet_verb, '');
    $cmdlet_noun = $invoke_cmdlet_name.Replace($cmdlet_verb, '').Replace($cmdlet_file_name_suffix, '');

    $normalized_output_type_name = 'object';
    $all_method_names = @();

    foreach ($operation_type in $operation_type_list)
    {
        $op_short_name = Get-OperationShortName $operation_type.Name;
        $op_short_name = $op_short_name.Replace('ScaleSets', 'ScaleSet').Replace('ScaleSetVMs', 'ScaleSetVM');
        $operation_method_info_list = Get-OperationMethods $operation_type;

        foreach ($method in $operation_method_info_list)
        {
            if ($method.Name -like 'Begin*')
            {
                continue;
            }
            elseif ($method.Name -like '*Async')
            {
                continue;
            }

            $invoke_param_set_name = (Get-SingularNoun $op_short_name) + $method.Name.Replace('Async', '');
            $all_method_names += $invoke_param_set_name;
        }
    }

    $all_method_names_with_quotes = $all_method_names | foreach { "`"" + $_ + "`"" };
    $all_method_names_str = [string]::Join(',' + $NEW_LINE + (' ' * 12), $all_method_names_with_quotes);
    $validate_all_method_names_code =
@"
        [ValidateSet(
            $all_method_names_str
        )]
"@;

    $dynamic_param_set_name = "InvokeByDynamicParameters";
    $static_param_set_name = "InvokeByStaticParameters";
    $param_set_code +=
@"
        [Parameter(Mandatory = true, ParameterSetName = `"$dynamic_param_set_name`", Position = 0)]
        [Parameter(Mandatory = true, ParameterSetName = `"$static_param_set_name`", Position = 0)]
$validate_all_method_names_code
        public virtual string MethodName $get_set_block

"@;

    $dynamic_parameters_code = "";
    $operations_code = "";
    foreach ($method_name in $all_method_names)
    {
        $operation_code_template =
@"
                    case `"${method_name}`" :
                        Execute${method_name}Method(argumentList);
                        break;
"@;
        $operations_code += $operation_code_template + $NEW_LINE;

        
        $dynamic_param_code_template =
@"
                    case `"${method_name}`" : return Create${method_name}DynamicParameters();
"@;
        $dynamic_parameters_code += $dynamic_param_code_template + $NEW_LINE;
    }

    $execute_client_action_code =
@"
        protected object ParseParameter(object input)
        {
            if (input is PSObject)
            {
                return (input as PSObject).BaseObject;
            }
            else
            {
                return input;
            }
        }

        protected override void ProcessRecord()
        {
            base.ProcessRecord();
            ExecuteClientAction(() =>
            {
                if (ParameterSetName.StartsWith(`"$dynamic_param_set_name`"))
                {
                    argumentList = ConvertDynamicParameters(dynamicParameters);
                }
                else
                {
                    argumentList = ConvertFromArgumentsToObjects((object[])dynamicParameters[`"ArgumentList`"].Value);
                }

                switch (MethodName)
                {
${operations_code}                    default : WriteWarning(`"Cannot find the method by name = `'`" + MethodName + `"`'.`"); break;
                }
            });
        }
"@;

    # $invoke_cmdlet_method_code_content = ([string]::Join($NEW_LINE, $invoke_cmdlet_method_code));
    # $dynamic_param_method_code_content = ([string]::Join($NEW_LINE, $dynamic_param_method_code));

    if (-not $generate_cmdlet)
    {
        $skip = "//";
    }

    $cmdlet_source_code_text =
@"
${code_common_header}

$code_using_strs

namespace ${code_common_namespace}
{
    ${skip}[Cmdlet(${cmdlet_verb_code}, `"${cmdlet_noun}`", DefaultParameterSetName = `"$dynamic_param_set_name`")]
    [OutputType(typeof(${normalized_output_type_name}))]
    public partial class $cmdlet_class_name : $base_cmdlet_name, IDynamicParameters
    {
        protected RuntimeDefinedParameterDictionary dynamicParameters;
        protected object[] argumentList;

        protected static object[] ConvertDynamicParameters(RuntimeDefinedParameterDictionary parameters)
        {
            List<object> paramList = new List<object>();

            foreach (var param in parameters)
            {
                paramList.Add(param.Value.Value);
            }

            return paramList.ToArray();
        }

${param_set_code}
${execute_client_action_code}
$invoke_cmdlet_method_code_content

        public virtual object GetDynamicParameters()
        {
            switch (MethodName)
            {
${dynamic_parameters_code}                    default : break;
            }

            return null;
        }
$dynamic_param_method_code_content
    }
}
"@;

    $st = Set-FileContent -Path $file_full_path -Value $cmdlet_source_code_text;
}

# Write New Invoke Parameters Cmdlet
function Write-InvokeParameterCmdletFile
{
    param(
        [Parameter(Mandatory = $True)]
        [string]$file_full_path,

        [Parameter(Mandatory = $True)]
        [string]$parameter_cmdlet_name,

        [Parameter(Mandatory = $True)]
        [string]$base_cmdlet_name,

        [Parameter(Mandatory = $True)]
        $client_class_info,

        [Parameter(Mandatory = $True)]
        $operation_type_list,

        [Parameter(Mandatory = $True)]
        $parameter_cmdlet_method_code
    )

    $indents = " " * 8;
    $get_set_block = '{ get; set; }';

    $cmdlet_verb = "New";
    $cmdlet_verb_code = $verbs_common_new;

    $cmdlet_file_name_suffix = 'Cmdlet'
    $cmdlet_class_name = $cmdlet_verb + $parameter_cmdlet_name.Replace($cmdlet_verb, '');
    $cmdlet_noun = $parameter_cmdlet_name.Replace($cmdlet_verb, '').Replace($cmdlet_file_name_suffix, '');

    $normalized_output_type_name = 'object';
    $all_method_names = @();
    $all_param_type_names = @();
    $constructor_code_hashmap = @{};

    foreach ($operation_type in $operation_type_list)
    {
        $op_short_name = Get-OperationShortName $operation_type.Name;
        $operation_method_info_list = Get-OperationMethods $operation_type;
        $parameter_type_info_list = @();

        foreach ($method in $operation_method_info_list)
        {
            if ($method.Name -like 'Begin*')
            {
                continue;
            }
            elseif ($method.Name -like '*Async')
            {
                continue;
            }

            $invoke_param_set_name = (Get-SingularNoun $op_short_name) + $method.Name.Replace('Async', '');
            $all_method_names += $invoke_param_set_name;

            [System.Reflection.ParameterInfo]$parameter_type_info = (Get-MethodComplexParameter $method $clientNameSpace);

            if (($parameter_type_info -ne $null) -and (($parameter_type_info_list | where { $_.ParameterType.FullName -eq $parameter_type_info.FullName }).Count -eq 0))
            {
                $parameter_type_info_list += $parameter_type_info;

                $parameter_type_short_name = Get-ParameterTypeShortName $parameter_type_info.ParameterType;
                if (($parameter_type_short_name -like "${op_short_name}*") -and ($parameter_type_short_name.Length -gt $op_short_name.Length))
                {
                    # Remove the common part between the parameter type name and operation short name, e.g. 'VirtualMachineDisk'
                    $parameter_type_short_name = $parameter_type_short_name.Substring($op_short_name.Length);
                }
                $parameter_type_short_name = $op_short_name + $parameter_type_short_name;

                $parameter_type_full_name = Get-ParameterTypeFullName $parameter_type_info.ParameterType;
                if (-not($all_param_type_names -contains $parameter_type_short_name))
                {
                    $all_param_type_names += $parameter_type_short_name;
                    if (-not $constructor_code_hashmap.ContainsKey($parameter_type_short_name))
                    {
                        $st = $constructor_code_hashmap.Add($parameter_type_short_name, (Get-ConstructorCode $parameter_type_full_name));
                    }
                }
            }
        }
    }

    $all_method_names_with_quotes = $all_method_names | foreach { "`"" + $_ + "`"" };
    $all_method_names_str = [string]::Join(',' + $NEW_LINE + (' ' * 12), $all_method_names_with_quotes);
    $validate_all_method_names_code =
@"
        [ValidateSet(
            $all_method_names_str
        )]
"@;

    $param_set_of_create_by_method_name = "CreateParameterListByMethodName";

    $param_set_code +=
@"
        [Parameter(ParameterSetName = `"$param_set_of_create_by_method_name`", Mandatory = true, Position = 0)]
$validate_all_method_names_code
        public virtual string MethodName $get_set_block

"@;


    $operations_code = "";
    foreach ($method_name in $all_method_names)
    {
        $operation_code_template =
@"
                        case `"${method_name}`" : WriteObject(Create${method_name}Parameters(), true); break;
"@;
        $operations_code += $operation_code_template + $NEW_LINE;
    }

    $execute_client_action_code =
@"
        protected override void ProcessRecord()
        {
            base.ProcessRecord();
            ExecuteClientAction(() =>
            {
                if (ParameterSetName == `"CreateParameterListByMethodName`")
                {
                    switch (MethodName)
                    {
${operations_code}                        default : WriteWarning(`"Cannot find the method by name = `'`" + MethodName + `"`'.`"); break;
                    }
                }
            });
        }
"@;

    # $parameter_cmdlet_method_code_content = ([string]::Join($NEW_LINE, $parameter_cmdlet_method_code));

    $cmdlet_source_code_text =
@"
${code_common_header}

$code_using_strs

namespace ${code_common_namespace}
{
    [Cmdlet(${cmdlet_verb_code}, `"${cmdlet_noun}`", DefaultParameterSetName = `"$param_set_of_create_by_method_name`")]
    [OutputType(typeof(${normalized_output_type_name}))]
    public partial class $cmdlet_class_name : $base_cmdlet_name
    {
${param_set_code}
${execute_client_action_code}
$parameter_cmdlet_method_code_content
    }
}
"@;

    $st = Set-FileContent -Path $file_full_path -Value $cmdlet_source_code_text;
}


# Write New Parameter Object Cmdlet
function Write-NewParameterObjectCmdletFile
{
    param(
        [Parameter(Mandatory = $True)]
        [string]$file_full_path,

        [Parameter(Mandatory = $True)]
        [string]$new_object_cmdlet_class_name,

        [Parameter(Mandatory = $True)]
        [string]$base_cmdlet_name,

        [Parameter(Mandatory = $True)]
        $client_class_info,

        [Parameter(Mandatory = $True)]
        $operation_type_list,

        [Parameter(Mandatory = $True)]
        $parameter_cmdlet_method_code
    )

    $indents = " " * 8;
    $get_set_block = '{ get; set; }';

    $cmdlet_verb = "New";
    $cmdlet_verb_code = $verbs_common_new;

    $cmdlet_file_name_suffix = 'Cmdlet'
    $cmdlet_class_name = $cmdlet_verb + $new_object_cmdlet_class_name.Replace($cmdlet_verb, '');
    $cmdlet_noun = $new_object_cmdlet_class_name.Replace($cmdlet_verb, '').Replace($cmdlet_file_name_suffix, '');

    $normalized_output_type_name = 'object';
    $all_method_names = @();
    $all_param_type_names = @();
    $constructor_code_hashmap = @{};
    $all_param_full_type_names = @();

    foreach ($operation_type in $operation_type_list)
    {
        $op_short_name = Get-OperationShortName $operation_type.Name;
        $operation_method_info_list = Get-OperationMethods $operation_type;
        $parameter_type_info_list = @();

        foreach ($method in $operation_method_info_list)
        {
            if ($method.Name -like 'Begin*')
            {
                continue;
            }
            elseif ($method.Name -like '*Async')
            {
                continue;
            }

            $invoke_param_set_name = $op_short_name + $method.Name.Replace('Async', '');
            $all_method_names += $invoke_param_set_name;

            [System.Reflection.ParameterInfo]$parameter_type_info = (Get-MethodComplexParameter $method $clientNameSpace);

            if (($parameter_type_info -ne $null) -and (($parameter_type_info_list | where { $_.ParameterType.FullName -eq $parameter_type_info.FullName }).Count -eq 0))
            {
                $parameter_type_info_list += $parameter_type_info;

                $parameter_type_short_name = Get-ParameterTypeShortName $parameter_type_info.ParameterType;
                if (($parameter_type_short_name -like "${op_short_name}*") -and ($parameter_type_short_name.Length -gt $op_short_name.Length))
                {
                    # Remove the common part between the parameter type name and operation short name, e.g. 'VirtualMachineDisk'
                    $parameter_type_short_name = $parameter_type_short_name.Substring($op_short_name.Length);
                }
                $parameter_type_short_name = $op_short_name + $parameter_type_short_name;

                $parameter_type_full_name = Get-ParameterTypeFullName $parameter_type_info.ParameterType;
                if (-not($all_param_type_names -contains $parameter_type_short_name))
                {
                    $all_param_type_names += $parameter_type_short_name;
                    if (-not $constructor_code_hashmap.ContainsKey($parameter_type_short_name))
                    {
                        $st = $constructor_code_hashmap.Add($parameter_type_short_name, (Get-ConstructorCode $parameter_type_full_name));
                    }
                }

                if (-not($all_param_full_type_names -contains $parameter_type_full_name))
                {
                    $all_param_full_type_names += $parameter_type_full_name;
                    if (-not $constructor_code_hashmap.ContainsKey($parameter_type_full_name))
                    {
                        $st = $constructor_code_hashmap.Add($parameter_type_full_name, (Get-ConstructorCode $parameter_type_full_name));
                    }
                }

                # Run Through the Sub Parameter List
                $subParamTypeList = Get-SubComplexParameterList $parameter_type_info $clientNameSpace;

                if ($subParamTypeList.Count -gt 0)
                {
                    foreach ($sp in $subParamTypeList)
                    {
                        if (-not $sp.IsGenericType)
                        {
                            $parameter_type_short_name = Get-ParameterTypeShortName $sp;
                            if (($parameter_type_short_name -like "${op_short_name}*") -and ($parameter_type_short_name.Length -gt $op_short_name.Length))
                            {
                                # Remove the common part between the parameter type name and operation short name, e.g. 'VirtualMachineDisk'
                                $parameter_type_short_name = $parameter_type_short_name.Substring($op_short_name.Length);
                            }
                            $parameter_type_short_name = $op_short_name + $parameter_type_short_name;

                            $parameter_type_full_name = Get-ParameterTypeFullName $sp;
                            if (-not $constructor_code_hashmap.ContainsKey($parameter_type_short_name))
                            {
                                $st = $constructor_code_hashmap.Add($parameter_type_short_name, (Get-ConstructorCode $parameter_type_full_name));
                            }

                            if (-not $constructor_code_hashmap.ContainsKey($parameter_type_full_name))
                            {
                                $st = $constructor_code_hashmap.Add($parameter_type_full_name, (Get-ConstructorCode $parameter_type_full_name));
                            }
                        }
                        else
                        {
                            $parameter_type_short_name = Get-ParameterTypeShortName $sp $true;
                            if (($parameter_type_short_name -like "${op_short_name}*") -and ($parameter_type_short_name.Length -gt $op_short_name.Length))
                            {
                                # Remove the common part between the parameter type name and operation short name, e.g. 'VirtualMachineDisk'
                                $parameter_type_short_name = $parameter_type_short_name.Substring($op_short_name.Length);
                            }
                            $parameter_type_short_name = $op_short_name + $parameter_type_short_name;

                            $parameter_type_full_name = Get-ParameterTypeFullName $sp $true;
                            if (-not $constructor_code_hashmap.ContainsKey($parameter_type_short_name))
                            {
                                $st = $constructor_code_hashmap.Add($parameter_type_short_name, (Get-ConstructorCode $parameter_type_full_name));
                            }

                            if (-not $constructor_code_hashmap.ContainsKey($parameter_type_full_name))
                            {
                                $st = $constructor_code_hashmap.Add($parameter_type_full_name, (Get-ConstructorCode $parameter_type_full_name));
                            }
                        }

                        if (-not($all_param_type_names -contains $parameter_type_short_name))
                        {
                            $all_param_type_names += $parameter_type_short_name;
                        }
                        
                        if (-not($all_param_full_type_names -contains $parameter_type_full_name))
                        {
                            $all_param_full_type_names += $parameter_type_full_name;
                        }
                    }
                }
            }
        }
    }

    $all_param_type_names = $all_param_type_names | Sort;
    $all_param_type_names_with_quotes = $all_param_type_names | foreach { "`"" + $_ + "`"" };
    $all_param_names_str = [string]::Join(',' + $NEW_LINE + (' ' * 12), $all_param_type_names_with_quotes);
    $validate_all_param_names_code =
@"
        [ValidateSet(
            $all_param_names_str
        )]
"@;

    $all_param_full_type_names = $all_param_full_type_names | Sort;
    $all_param_full_type_names_with_quotes = $all_param_full_type_names | foreach { "`"" + $_ + "`"" };
    $all_param_full_names_str = [string]::Join(',' + $NEW_LINE + (' ' * 12), $all_param_full_type_names_with_quotes);
    $validate_all_param_full_names_code =
@"
        [ValidateSet(
            $all_param_full_names_str
        )]
"@;

    $param_set_of_create_by_type_name = "CreateParameterObjectByFriendlyName";
    $param_set_of_create_by_full_type_name = "CreateParameterObjectByFullName";

    $param_set_code +=
@"
        [Parameter(ParameterSetName = `"$param_set_of_create_by_type_name`", Mandatory = true, Position = 0)]
$validate_all_param_names_code
        public string FriendlyName $get_set_block

        [Parameter(ParameterSetName = `"$param_set_of_create_by_full_type_name`", Mandatory = true, Position = 0)]
$validate_all_param_full_names_code
        public string FullName $get_set_block

"@;


    $operations_code = "";
    foreach ($method_name in $all_method_names)
    {

        $operation_code_template =
@"
                        case `"${method_name}`" : WriteObject(Create${method_name}Parameters()); break;
"@;
        $operations_code += $operation_code_template + $NEW_LINE;
    }

    $type_operations_code = "";
    foreach ($type_name in $all_param_type_names)
    {
        $constructor_code = $constructor_code_hashmap.Get_Item($type_name);
        $type_code_template =
@"
                        case `"${type_name}`" : WriteObject(${constructor_code}); break;
"@;
        $type_operations_code += $type_code_template + $NEW_LINE;
    }

    $full_type_operations_code = "";
    foreach ($type_name in $all_param_full_type_names)
    {
        $constructor_code = $constructor_code_hashmap.Get_Item($type_name);
        $full_type_code_template =
@"
                        case `"${type_name}`" : WriteObject(${constructor_code}); break;
"@;
        $full_type_operations_code += $full_type_code_template + $NEW_LINE;
    }

    $execute_client_action_code =
@"
        protected override void ProcessRecord()
        {
            base.ProcessRecord();
            ExecuteClientAction(() =>
            {
                if (ParameterSetName == `"$param_set_of_create_by_type_name`")
                {
                    switch (FriendlyName)
                    {
${type_operations_code}                        default : WriteWarning(`"Cannot find the type by FriendlyName = `'`" + FriendlyName + `"`'.`"); break;
                    }
                }
                else if (ParameterSetName == `"$param_set_of_create_by_full_type_name`")
                {
                    switch (FullName)
                    {
${full_type_operations_code}                        default : WriteWarning(`"Cannot find the type by FullName = `'`" + FullName + `"`'.`"); break;
                    }
                }
            });
        }
"@;

    # $parameter_cmdlet_method_code_content = ([string]::Join($NEW_LINE, $parameter_cmdlet_method_code));

    $cmdlet_source_code_text =
@"
${code_common_header}

$code_using_strs

namespace ${code_common_namespace}
{
    [Cmdlet(${cmdlet_verb_code}, `"${cmdlet_noun}`", DefaultParameterSetName = `"$param_set_of_create_by_full_type_name`")]
    [OutputType(typeof(${normalized_output_type_name}))]
    public partial class $new_object_cmdlet_class_name : $base_cmdlet_name
    {
${param_set_code}
${execute_client_action_code}
$parameter_cmdlet_method_code_content
    }
}
"@;

    $st = Set-FileContent -Path $file_full_path -Value $cmdlet_source_code_text;
}

# Process the list return type
function Process-ListType
{
    param([Type] $rt, [System.String] $name)

    $result = $null;

    if ($rt -eq $null)
    {
        return $result;
    }

    $xml = '<Name>' + $rt.FullName + '</Name>';
    $xml += '<ViewSelectedBy><TypeName>' + $rt.FullName + '</TypeName></ViewSelectedBy>' + [System.Environment]::NewLine;
    $xml += '<ListControl><ListEntries><ListEntry><ListItems>' + [System.Environment]::NewLine;

    $itemLabel = $itemName = $rt.Name;
    $xml += "<ListItem><Label>${itemName}</Label><ScriptBlock>[Newtonsoft.Json.JsonConvert]::SerializeObject(" + "$" + "_,  [Newtonsoft.Json.Formatting]::Indented)</ScriptBlock></ListItem>" + [System.Environment]::NewLine;
    $xml += '</ListItems></ListEntry></ListEntries></ListControl>' + [System.Environment]::NewLine;
    $xml = '<View>' + [System.Environment]::NewLine + $xml + '</View>' + [System.Environment]::NewLine;

    # Write-Verbose ("Xml: " + $xml);

    return $xml;
}

# Process the return type
function Process-ReturnType
{
    param([Type] $rt, [System.Array] $allrt)

    $result = "";

    if ($rt -eq $null)
    {
        return @($result, $allrt);
    }

    if ($allrt.Contains($rt.Name))
    {
        return @($result, $allrt);
    }

    $allrt += $rt.Name;

    if ($rt.Name -like '*LongRunning*' -or $rt.Name -like ('*' + $component_name + 'OperationResponse*') -or $rt.Name -like '*AzureOperationResponse*')
    {
        return @($result, $allrt);
    }
    
    if ($rt.FullName -like "System.Collections.Generic.IEnumerable*")
    {
        $rt = $rt.GenericTypeArguments[0];
    }

    $xml = '<Name>' + $rt.FullName + '</Name>';
    $xml += '<ViewSelectedBy><TypeName>' + $rt.FullName + '</TypeName></ViewSelectedBy>' + [System.Environment]::NewLine;
    $xml += '<ListControl><ListEntries><ListEntry><ListItems>' + [System.Environment]::NewLine;

    $props = $rt.GetProperties([System.Reflection.BindingFlags]::Public -bor [System.Reflection.BindingFlags]::Instance -bor [System.Reflection.BindingFlags]::Static);

    foreach ($pr1 in $props)
    {        
        $typeStr = Get-ProperTypeName $pr1.PropertyType;
        $itemLabel = $itemName = $pr1.Name;

        if ($typeStr -eq 'string' `
        -or $typeStr -eq 'string[]' `
        -or $typeStr -eq 'uint' `
        -or $typeStr -eq 'uint?' `
        -or $typeStr -eq 'int' `
        -or $typeStr -eq 'int?' `
        -or $typeStr -eq 'bool' `
        -or $typeStr -eq 'bool?' `
        -or $typeStr -eq 'DateTime' `
        -or $typeStr -eq 'DateTime?' `
        -or $typeStr -eq 'DateTimeOffset' `
        -or $typeStr -eq 'DateTimeOffset?' `
        -or $typeStr -eq 'HttpStatusCode' )
        {
           $xml += "<ListItem><Label>${itemLabel}</Label><PropertyName>${itemName}</PropertyName></ListItem>" + [System.Environment]::NewLine;
        }
        elseif ($typeStr.StartsWith('IList') `
        -or $typeStr.StartsWith('IDictionary'))
        {
           $elementType = $pr1.PropertyType.GenericTypeArguments[0];

           if (-not $elementType.FullName.Contains("String"))
           {
                if (-not $allrt.Contains($elementType.Name))
                {
                     $allrt += $elementType.Name;
                     $addxml = Process-ListType -rt $pr1.PropertyType.GenericTypeArguments[0] -name ${itemName};
                }
           }

           $xml += "<ListItem><Label>${itemLabel}.Count</Label><ScriptBlock> if (" + "$" + "_.${itemName} -eq $" + "null) { 0 } else { $" + "_.${itemName}.Count }</ScriptBlock></ListItem>" + [System.Environment]::NewLine;
           $xml += "<ListItem><Label>${itemLabel}</Label><ScriptBlock> foreach ($" + "item in $" + "_.${itemName}) { [Newtonsoft.Json.JsonConvert]::SerializeObject(" + "$" + "item,  [Newtonsoft.Json.Formatting]::Indented) } </ScriptBlock></ListItem>" + [System.Environment]::NewLine;
        }
        else
        {
           $xml += "<ListItem><Label>${itemLabel}</Label><ScriptBlock>[Newtonsoft.Json.JsonConvert]::SerializeObject(" + "$" + "_." + ${itemName} + ",  [Newtonsoft.Json.Formatting]::Indented)</ScriptBlock></ListItem>" + [System.Environment]::NewLine;
        }
    }

    $xml += '</ListItems></ListEntry></ListEntries></ListControl>' + [System.Environment]::NewLine;
    $xml = '<View>' + [System.Environment]::NewLine + $xml + '</View>' + [System.Environment]::NewLine;

    if (-not [System.String]::IsNullOrEmpty($addxml))
    {
        $xml += $addxml;
    }

    # Write-Verbose ("Xml: " + $xml);

    return @($xml, $allrt)
}

# Get proper type name
function Format-XML ([xml]$xml, $indent = 2)
{
    $StringWriter = New-Object System.IO.StringWriter;
    $XmlWriter = New-Object System.XMl.XmlTextWriter $StringWriter;
    $xmlWriter.Formatting = "indented";
    $xmlWriter.Indentation = $Indent;
    $st = $xml.WriteContentTo($XmlWriter);
    $st = $XmlWriter.Flush();
    $st = $StringWriter.Flush();
    Write-Output $StringWriter.ToString();
}

function Write-XmlFormatFile
{
    param(
        [Parameter(Mandatory = $True)]
        $xmlFilePath
    )

    $xmlCommentHeader = '<!--' + [System.Environment]::NewLine;
    foreach ($cLine in $code_common_header)
    {
        $xmlCommentHeader += $cLine + [System.Environment]::NewLine;
    }
    $xmlCommentHeader += '-->' + [System.Environment]::NewLine;

    $xmlContent = [xml]($xmlCommentHeader + '<Configuration><ViewDefinitions>' + [System.Environment]::NewLine + $formatXml + '</ViewDefinitions></Configuration>' + [System.Environment]::NewLine);
    $node = $xmlContent.CreateXmlDeclaration('1.0', 'UTF-8', $null);
    $st = $xmlContent.InsertBefore($node, $xmlContent.ChildNodes[0]);

    $formattedXmlContent = Format-XML $xmlContent.OuterXml;
    $st = Set-FileContent -Path $xmlFilePath -Value $formattedXmlContent;
    # Write-Verbose($formattedXmlContent);
}

# Sample: NewAzureVirtualMachineCreateParameters.cs
function Write-CLICommandFile
{
    param
    (
        [Parameter(Mandatory = $true)]
        [string]$fileOutputFolder,

        [Parameter(Mandatory = $true)]
        $commandCodeLines,
        
        [Parameter(Mandatory = $true)]
        $sample_code_lines,

        [Parameter(Mandatory = $false)]
        [string]$componentName,

        [Parameter(Mandatory = $false)]
        [string]$operationName
    )

    $fileName = 'cli.js';
    $subFolder = '/';
    if ($operationName -ne $null)
    {
        $fileName = (Get-CamelCaseName $operationName $false) + '._js';
    }

    if ($componentName -ne $null)
    {
        $subFolder += (Get-CamelCaseName $componentName $false) + '/';
    }
    
    if (-not (Test-Path ($fileOutputFolder + $subFolder)))
    {
        mkdir -Force ($fileOutputFolder + $subFolder);
    }

    $fileFullPath = $fileOutputFolder + $subFolder + $fileName;

    Write-Verbose "=============================================";
    Write-Verbose "Writing CLI Command File: ";
    Write-Verbose $fileFullPath;
    Write-Verbose "=============================================";

    $import_fs = $false;
    $import_jsonpatch = $false;
    $define_beautify = $false;
    $define_display = $false;

    # Check Required Packages or Functions
    foreach ($code_line in $commandCodeLines)
    {
        if ($code_line -like "*fs.*")
        {
            $import_fs = $true;
        }

        if ($code_line -like "*jsonpatch.*")
        {
            $import_jsonpatch = $true;
        }
        
        if ($code_line -like "*beautify(*")
        {
            $define_beautify = $true;
        }
        
            if ($code_line -like "*display(*")
        {
            $define_display = $true;
        }
    }

    $codeContent = 
@"
/**
 * Copyright (c) Microsoft.  All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

// Warning: This code was generated by a tool.
// 
// Changes to this file may cause incorrect behavior and will be lost if the
// code is regenerated.

'use strict';


"@;

    if ($import_fs)
    {
        $codeContent += "var fs = require('fs');" + $NEW_LINE;
    }
    
    if ($import_jsonpatch)
    {
        $codeContent += "var jsonpatch = require('fast-json-patch');" + $NEW_LINE;
    }

    $codeContent +=
@"
var profile = require('../../../util/profile');
var utils = require('../../../util/utils');

"@
if($operationName -ne "usages" -and $operationName -ne "expressRouteServiceProviders")
{
    $codeContent +=
@"
var util = require('util');

"@
}
if($commandCodeLines -clike "*resourceUtils.*")
{
    $codeContent += "var resourceUtils = require('../resource/resourceUtils');
"
}
if($commandCodeLines -clike "*tagUtils*")
{
    $codeContent += "var tagUtils = require('../tag/tagUtils');
"
}
    $codeContent +=
@"
var $ = utils.getLocaleString;

"@;

    if ($define_beautify)
    {
        $codeContent +=
@"
function beautify(jsonText) {
  var obj = JSON.parse(jsonText);
  return JSON.stringify(obj, null, 2);
}

"@;
    }
    
    if ($define_display)
    {
        $codeContent +=
@"

function makeTuple(k, v, d) {
  return { key : k, value : v, depth : d };
}

"@;
    }

if($operationName -ne "usages" -and $operationName -ne "expressRouteServiceProviders")
{
    $codeContent +=
@"
var generatorUtils = require('../../../util/generatorUtils');

"@
}
    $codeContent+=
@"
exports.init = function (cli) {
$commandCodeLines
};

"@;

    $st = Set-FileContent -Path $fileFullPath -Value $codeContent;
}
