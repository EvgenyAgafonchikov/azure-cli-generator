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

param(
    [Parameter(Mandatory = $true)]
    $CmdletTreeNode,
    
    # VirtualMachine, VirtualMachineScaleSet, etc.
    [Parameter(Mandatory = $true)]
    [string]$OperationName,

    [Parameter(Mandatory = $false)]
    [string]$MethodName = $null,

    [Parameter(Mandatory = $false)]
    [string]$ModelNameSpace = $null,

    # CLI commands or PS cmdlets
    [Parameter(Mandatory = $false)]
    [string]$ToolType = "CLI",

    [Parameter(Mandatory = $false)]
    [string]$OutputFolder = $null,

    [Parameter(Mandatory = $false)]
    [string]$CmdletNounPrefix = "Azure"
)

$NEW_LINE = "`r`n";
. "$PSScriptRoot\Import-StringFunction.ps1";

$CLI_HELP_MSG = "         There are two sets of commands:\r\n" `
              + "           1) function commands that are used to manage Azure resources in the cloud, and \r\n" `
              + "           2) parameter commands that generate & edit input files for the other set of commands.\r\n" `
              + "         For example, \'vmss get/list/stop\' are the function commands that call get, list and stop operations of \r\n" `
              + "         virtual machine scale set, whereas \'vmss create-or-update-parameters * generate/set/remove/add\' commands \r\n" `
              + "         are used to configure the input parameter file. The \'vmss create-or-update\' command takes a parameter \r\n" `
              + "         file as for the VM scale set configuration, and creates it online.";

function Get-ParameterCommandCategoryDescription
{
    param
    (
        # e.g. 'virtual machine scale set'
        [Parameter(Mandatory = $true)]
        [string]$OperationName,
        
        # e.g. 'create-or-update-parameters'
        [Parameter(Mandatory = $true)]
        [string]$FunctionParamName,

        # e.g. 'os-profile'
        [Parameter(Mandatory = $true)]
        [string]$SubParameterName
    )

    $description = "Commands to set/remove/add ${SubParameterName} ";
    $description += "of ${OperationName} in ${FunctionParamName} file.";

    return $description;
}

function Generate-CliParameterCommandImpl
{
    param(
        [Parameter(Mandatory = $true)]
        $TreeNode
    )

    if ($TreeNode -eq $null)
    {
        return $null;
    }

    $paramSuffix = $OperationName + $TreeNode.Name;
    $cli_method_option_name = Get-CliOptionName $TreeNode.Name;
    $cli_op_description = Get-CliOptionName $OperationName;
    $category_name = Get-CliCategoryName $OperationName;
    $params_category_name = (Get-CliCategoryName $MethodName) + '-parameters';
    $params_category_var_name_prefix = 'parameters';
    $cli_param_name = 'parameters';

    # 0. Construct Path to Node
    $pathToTreeNode = "";
    $parentNode = $TreeNode;
    $indexerParamList = @();
    while ($parentNode -ne $null)
    {
        [string]$nodeName = Get-CliNormalizedName $parentNode.Name.Trim();
        [string]$pathName = $nodeName;
        # Skip this for AutoRest, as the parameter names are always matched.
        # if ($pathName.ToLower().StartsWith('ip'))
        # {
        #    $pathName = 'iP' + $pathName.Substring(2);
        # }

        if ($parentNode.Parent -ne $null)
        {
            if ($parentNode.IsListItem)
            {
                if ($nodeName -eq $TreeNode.Name)
                {
                    $indexerName = "index";
                    $pathToTreeNode = "/$pathName`' + (options.${indexerName} ? ('/' + options.${indexerName}) : '')";
                }
                else
                {
                    $indexerName = "${nodeName}Index";
                    $pathToTreeNode = "/$pathName/`' + options.${indexerName} + `'" + $pathToTreeNode;
                }

                $indexerParamList += $indexerName;
            }
            else
            {
                $pathToTreeNode = "/$pathName" + $pathToTreeNode;
            }
        }

        $parentNode = $parentNode.Parent;
    }

    if ($TreeNode.IsListItem)
    {
        $pathToTreeNode = "`'${pathToTreeNode}";
    }
    else
    {
        $pathToTreeNode = "`'${pathToTreeNode}`'";
    }

    if ($ModelNameSpace -like "*.WindowsAzure.*")
    {
        # 0.1 Use Invoke Category for RDFE APIs
        $invoke_category_desc = "Commands to invoke service management operations.";
        $invoke_category_code = ".category('invoke').description('${invoke_category_desc}')";
    }
    
    # 0.2 Construct Sample JSON Parameter Body for Help Messages
    $paramObject = (. $PSScriptRoot\Create-ParameterObject.ps1 -typeInfo $TreeNode.TypeInfo);
    $paramObjText = (. $PSScriptRoot\ConvertTo-Json.ps1 -inputObject $paramObject);
    if ($TreeNode.Parent -eq $null)
    {
        $sampleJsonText = $paramObjText.Replace("`r`n", "\r\n");
    }
    else
    {
        $padding = "         ";
        $sampleJsonText = $padding + "{\r\n";
        $sampleJsonText += $padding + "  ...\r\n";
        $sampleJsonText += $padding + "  `"" + (Get-CliNormalizedName $TreeNode.Name) + "`" : ";
        $sampleJsonText += ($paramObjText.Replace("`r`n", "\r\n" + $padding + "  ")) + "\r\n";
        $sampleJsonText += $padding + "  ...\r\n";
        $sampleJsonText += $padding + "}\r\n";
    }

    if ($TreeNode.Properties.Count -gt 0 -or ($TreeNode.IsListItem))
    {
        # 1. Parameter Set Command
        $params_category_var_name = $params_category_var_name_prefix + $MethodName + $paramSuffix + "0";
        $cat_params_category_var_name = 'cat' + $params_category_var_name;
        $params_generate_category_name = 'set';
        $params_generate_category_var_name = $params_generate_category_name + $params_category_var_name;
        $code = "  //$params_category_name set ${cli_method_option_name}" + $NEW_LINE;
        $code += "  var ${cat_params_category_var_name} = cli${invoke_category_code}.category('${category_name}');" + $NEW_LINE;
        $code += "  var ${params_category_var_name} = ${cat_params_category_var_name}.category('${params_category_name}')" + $NEW_LINE;
        $code += "  .description(`$('Commands to manage parameter for your ${cli_op_description}.'));" + $NEW_LINE;
        $code += "  var ${params_generate_category_var_name} = ${params_category_var_name}.category('${cli_method_option_name}')" + $NEW_LINE;
        $code += "  .description(`$('" + (Get-ParameterCommandCategoryDescription $cli_op_description $params_category_name $cli_method_option_name) +"'));" + $NEW_LINE;
        $code += "  ${params_generate_category_var_name}.command('${params_generate_category_name}')" + $NEW_LINE;
        $code += "  .description(`$('Set ${cli_method_option_name} in ${params_category_name} string or files, e.g. \r\n${sampleJsonText}\r\n" + $CLI_HELP_MSG + "'))" + $NEW_LINE;
        $code += "  .usage('[options]')" + $NEW_LINE;
        $code += "  .option('--parameter-file <parameter-file>', `$('The parameter file path.'))" + $NEW_LINE;

        # 1.1 For List Item
        if ($indexerParamList.Count -gt 0)
        {
            foreach ($indexerParamName in $indexerParamList)
            {
                $indexerOptionName = Get-CliOptionName $indexerParamName;
                $code += "  .option('--$indexerOptionName <$indexerOptionName>', `$('Indexer: $indexerOptionName.'))" + $NEW_LINE;
            }
            
            if ($indexerParamList -contains 'index')
            {
                $code += "  .option('--value <value>', `$('The input string value for the indexed item.'))" + $NEW_LINE;
            }
        }
        $code += "  .option('--parse', `$('Parse the input value string to a JSON object.'))" + $NEW_LINE;

        # 1.2 For Each Property, Set the Option
        foreach ($propertyItem in $TreeNode.Properties)
        {
            $code += "  .option('--" + (Get-CliOptionName $propertyItem["Name"]);
            $code += " <" + (Get-CliNormalizedName $propertyItem["Name"]);
            $code += ">', `$('Set the " + (Get-CliOptionName $propertyItem["Name"]);
            $code += " value.'))" + $NEW_LINE;
        }

        $code += "  .execute(function(options, _) {" + $NEW_LINE;
        $code += "    cli.output.verbose(JSON.stringify(options), _);" + $NEW_LINE;
        $code += "    if (options.parse && options.value) {" + $NEW_LINE;
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
    
        $code += "    options.operation = 'replace';" + $NEW_LINE;
        $code += "    options.path = ${pathToTreeNode};" + $NEW_LINE;
            
        # 1.3 For List Item
        if ($TreeNode.IsListItem)
        {
            $code += "    if (options.value) {" + $NEW_LINE;
            $code += "      jsonpatch.apply(${cli_param_name}Obj, [{op: options.operation, path: options.path, value: options.value}]);" + $NEW_LINE;
            $code += "    }" + $NEW_LINE;
        }
        
        # 1.4 For Each Property, Apply the Change if Any
        $isFirstDefinition = $true;
        foreach ($propertyItem in $TreeNode.Properties)
        {
            if ($isFirstDefinition)
            {
                $isFirstDefinition = $false;
                $defTypePrefix = "var ";
            }
            else
            {
                $defTypePrefix = "";
            }

            $paramName = (Get-CliNormalizedName $propertyItem["Name"]);
            $code += "    ${defTypePrefix}paramPath = " + "options.path" + " + `'/`' + " + "`'" + ${paramName} + "`';" + $NEW_LINE;
            $code += "    cli.output.verbose(`'================================================`');" + $NEW_LINE;
            $code += "    cli.output.verbose(`'JSON Parameters Path:`' + paramPath);" + $NEW_LINE;
            $code += "    cli.output.verbose(`'================================================`');" + $NEW_LINE;
            $code += "    if (options.${paramName}) {" + $NEW_LINE;
            $code += "      if (options.parse && options.${paramName}) {" + $NEW_LINE;
            $code += "        options.${paramName} = JSON.parse(options.${paramName});" + $NEW_LINE;
            $code += "      }" + $NEW_LINE;
            
            if ($propertyItem["IsPrimitive"])
            {
                $code += "        options.${paramName} = JSON.parse(options.${paramName});" + $NEW_LINE;
            }
            
            $code += "      jsonpatch.apply(${cli_param_name}Obj, [{op: options.operation, path: paramPath, value: options.${paramName}}]);" + $NEW_LINE;
            $code += "    }" + $NEW_LINE;
        }

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
        $code += "" + $NEW_LINE;
    }

    # 2. Parameter Remove Command
    $params_category_var_name = $params_category_var_name_prefix + $MethodName + $paramSuffix + "1";
    $cat_params_category_var_name = 'cat' + $params_category_var_name;
    $params_generate_category_name = 'remove';
    $params_generate_category_var_name = $params_generate_category_name + $params_category_var_name;
    $code += "  //$params_category_name ${params_generate_category_name} ${cli_method_option_name}" + $NEW_LINE;
    $code += "  var ${cat_params_category_var_name} = cli${invoke_category_code}.category('${category_name}');" + $NEW_LINE;
    $code += "  var ${params_category_var_name} = ${cat_params_category_var_name}.category('${params_category_name}')" + $NEW_LINE;
    $code += "  .description(`$('Commands to manage parameter for your ${cli_op_description}.'));" + $NEW_LINE;
    $code += "  var ${params_generate_category_var_name} = ${params_category_var_name}.category('${cli_method_option_name}')" + $NEW_LINE;
    $code += "  .description(`$('" + (Get-ParameterCommandCategoryDescription $cli_op_description $params_category_name $cli_method_option_name) +"'));" + $NEW_LINE;
    $code += "  ${params_generate_category_var_name}.command('${params_generate_category_name}')" + $NEW_LINE;
    $code += "  .description(`$('Remove ${cli_method_option_name} in ${params_category_name} string or files, e.g. \r\n${sampleJsonText}\r\n" + $CLI_HELP_MSG + "'))" + $NEW_LINE;
    $code += "  .usage('[options]')" + $NEW_LINE;
    $code += "  .option('--parameter-file <parameter-file>', `$('The parameter file path.'))" + $NEW_LINE;

    # 2.1 For List Item
    if ($indexerParamList.Count -gt 0)
    {
        foreach ($indexerParamName in $indexerParamList)
        {
            $indexerOptionName = Get-CliOptionName $indexerParamName;
            $code += "  .option('--$indexerOptionName <$indexerOptionName>', `$('Indexer: $indexerOptionName.'))" + $NEW_LINE;
        }
    }

    # 2.2 For Each Property, Append the Option for Removal
    foreach ($propertyItem in $TreeNode.Properties)
    {
        $code += "  .option('--" + (Get-CliOptionName $propertyItem["Name"]) + "',";
        $code += " `$('Remove the " + (Get-CliOptionName $propertyItem["Name"]);
        $code += " value.'))" + $NEW_LINE;
    }

    # 2.3 Function Definition
    $code += "  .execute(function(options, _) {" + $NEW_LINE;
    $code += "    cli.output.verbose(JSON.stringify(options), _);" + $NEW_LINE;
    $code += "    cli.output.verbose(`'=====================================`');" + $NEW_LINE;
    $code += "    cli.output.verbose(`'Reading file content from: \`"`' + options.parameterFile + `'\`"`');" + $NEW_LINE;
    $code += "    cli.output.verbose(`'=====================================`');" + $NEW_LINE;
    $code += "    var fileContent = fs.readFileSync(options.parameterFile, 'utf8');" + $NEW_LINE;
    $code += "    var ${cli_param_name}Obj = JSON.parse(fileContent);" + $NEW_LINE;
    $code += "    cli.output.verbose(`'JSON object:`');" + $NEW_LINE;
    $code += "    cli.output.verbose(JSON.stringify(${cli_param_name}Obj));" + $NEW_LINE;
    $code += "    options.operation = 'remove';" + $NEW_LINE;
    $code += "    options.path = ${pathToTreeNode};" + $NEW_LINE;

    if ($TreeNode.Properties.Count -gt 0)
    {
        # 2.3.1 For Any Sub-Item Removal
        $code += "    var anySubItem = false";
        foreach ($propertyItem in $TreeNode.Properties)
        {
            $code += " || options." + (Get-CliNormalizedName $propertyItem["Name"]);
        }
        $code += ";" + $NEW_LINE;

        # 2.3.2 For Removal of the Entire Item
        $code += "    if (anySubItem) {" + $NEW_LINE;
        $code += "      var subItemPath = null;" + $NEW_LINE;
        foreach ($propertyItem in $TreeNode.Properties)
        {
            $code += "      if (options." + (Get-CliNormalizedName $propertyItem["Name"]) + ") {" + $NEW_LINE;
            $code += "        subItemPath = options.path + '/" + (Get-CliNormalizedName $propertyItem["Name"]) + "';" + $NEW_LINE;
            $code += "        jsonpatch.apply(${cli_param_name}Obj, [{op: options.operation, path: subItemPath}]);" + $NEW_LINE;
            $code += "      }" + $NEW_LINE;
        }
    
        $code += "    }" + $NEW_LINE;
        $code += "    else {" + $NEW_LINE;
        $code += "      jsonpatch.apply(${cli_param_name}Obj, [{op: options.operation, path: options.path}]);" + $NEW_LINE;
        $code += "    }" + $NEW_LINE;
    }
    elseif ($indexerParamList.Count -gt 0)
    {
        $code += "    jsonpatch.apply(${cli_param_name}Obj, [{op: options.operation, path: options.path}]);" + $NEW_LINE;
    }
    
    $code += "    " + $NEW_LINE;
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
    
    # 3. Parameter Add Command
    $params_category_var_name = $params_category_var_name_prefix + $MethodName + $paramSuffix + "2";
    $cat_params_category_var_name = 'cat' + $params_category_var_name;
    $params_generate_category_name = 'add';
    $params_generate_category_var_name = $params_generate_category_name + $params_category_var_name;
    $code += "  //$params_category_name ${params_generate_category_name} ${cli_method_option_name}" + $NEW_LINE;
    $code += "  var ${cat_params_category_var_name} = cli${invoke_category_code}.category('${category_name}');" + $NEW_LINE;
    $code += "  var ${params_category_var_name} = ${cat_params_category_var_name}.category('${params_category_name}')" + $NEW_LINE;
    $code += "  .description(`$('Commands to manage the parameter input file for your ${cli_op_description}.'));" + $NEW_LINE;
    $code += "  var ${params_generate_category_var_name} = ${params_category_var_name}.category('${cli_method_option_name}')" + $NEW_LINE;
    $code += "  .description(`$('" + (Get-ParameterCommandCategoryDescription $cli_op_description $params_category_name $cli_method_option_name) +"'));" + $NEW_LINE;
    $code += "  ${params_generate_category_var_name}.command('${params_generate_category_name}')" + $NEW_LINE;
    $code += "  .description(`$('Add ${cli_method_option_name} in ${params_category_name} string or files, e.g. \r\n${sampleJsonText}\r\n" + $CLI_HELP_MSG + "'))" + $NEW_LINE;
    $code += "  .usage('[options]')" + $NEW_LINE;
    $code += "  .option('--parameter-file <parameter-file>', `$('The parameter file path.'))" + $NEW_LINE;
    $code += "  .option('--key <key>', `$('The JSON key.'))" + $NEW_LINE;
    $code += "  .option('--value <value>', `$('The JSON value.'))" + $NEW_LINE;
    $code += "  .option('--parse', `$('Parse the input value string to a JSON object.'))" + $NEW_LINE;

    # For Each Property, Add the Option
    foreach ($propertyItem in $TreeNode.Properties)
    {
        $code += "  .option('--" + (Get-CliOptionName $propertyItem["Name"]);
        $code += " <" + (Get-CliNormalizedName $propertyItem["Name"]);
        $code += ">', `$('Add the " + (Get-CliOptionName $propertyItem["Name"]);
        $code += " value.'))" + $NEW_LINE;
    }

    $code += "  .execute(function(options, _) {" + $NEW_LINE;
    $code += "    cli.output.verbose(JSON.stringify(options), _);" + $NEW_LINE;
    $code += "    if (options.parse && options.value) {" + $NEW_LINE;
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
    
    $code += "    options.operation = 'add';" + $NEW_LINE;
    $code += "    options.path = ${pathToTreeNode} + `'/`' + options.key;" + $NEW_LINE;
    $code += "    cli.output.verbose(`'options.path = `' + options.path);" + $NEW_LINE;
    $code += "    jsonpatch.apply(${cli_param_name}Obj, [{op: options.operation, path: options.path, value: options.value}]);" + $NEW_LINE;

    # For Each Property, Apply the Change if Any
    $isFirstDefinition = $true;
    foreach ($propertyItem in $TreeNode.Properties)
    {
        if ($isFirstDefinition)
        {
            $isFirstDefinition = $false;
            $defTypePrefix = "var ";
        }
        else
        {
            $defTypePrefix = "";
        }

        $paramName = (Get-CliNormalizedName $propertyItem["Name"]);
        $code += "    ${defTypePrefix}paramPath = ${pathToTreeNode} + `'/`' + `'${paramName}`';" + $NEW_LINE;
        $code += "    cli.output.verbose(`'================================================`');" + $NEW_LINE;
        $code += "    cli.output.verbose(`'JSON Parameters Path:`' + paramPath);" + $NEW_LINE;
        $code += "    cli.output.verbose(`'================================================`');" + $NEW_LINE;
        $code += "    if (options.${paramName}) {" + $NEW_LINE;
        $code += "      if (options.parse && options.${paramName}) {" + $NEW_LINE;
        $code += "        options.${paramName} = JSON.parse(options.${paramName});" + $NEW_LINE;
        $code += "      }" + $NEW_LINE;

        if ($propertyItem["IsPrimitive"])
        {
            $code += "        options.${paramName} = JSON.parse(options.${paramName});" + $NEW_LINE;
        }

        $code += "      jsonpatch.apply(${cli_param_name}Obj, [{op: options.operation, path: paramPath, value: options.${paramName}}]);" + $NEW_LINE;
        $code += "    }" + $NEW_LINE;
    }

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
    $code += "" + $NEW_LINE;

    # 4. Recursive Calls for All Sub-Nodes
    foreach ($subNode in $TreeNode.SubNodes)
    {
        if ($null -ne $subNode)
        {
            $code += Generate-CliParameterCommandImpl $subNode;
        }
    }

    return $code;
}

function AddTo-HashTable
{
    param(
        [Parameter(Mandatory = $true)]
        $hashTable,
        [Parameter(Mandatory = $true)]
        $newKey,
        [Parameter(Mandatory = $true)]
        $newValue
    )


    if ($hashTable[$newKey] -eq $null)
    {
        $hashTable += @{$newKey =$newValue};
    }
    return $hashTable;
}

function Merge-HashTables
{
    param(
        [Parameter(Mandatory = $true)]
        $hashTable1,
        [Parameter(Mandatory = $true)]
        $hashTable2
    )

    foreach ($key in $hashTable2.Keys)
    {
        $hashTable1 = AddTo-HashTable $hashTable1 $key $hashTable2.$key;
    }
    return $hashTable1;
}

function Generate-PowershellParameterCommandImpl
{
    param(
        [Parameter(Mandatory = $true)]
        $TreeNode,

        [Parameter(Mandatory = $false)]
        [string] $fileOutputFolder = $null
    )

    $powershell_object_name = Get-SingularNoun $OperationName;

    if ($TreeNode -eq $null)
    {
        return $null;
    }

    $paramSuffix = $powershell_object_name + $TreeNode.Name;
    $category_name = Get-PowershellCategoryName $powershell_object_name;

    # 0. Construct Path to Node
    $pathToTreeNode = @();
    $pathFromRoot =@();

    $parentNode = $TreeNode;
    $indexerParamList = @();
    $type_binding = @{};

    while ($parentNode -ne $null)
    {
        if ($type_binding[$parentNode.Name] -eq $null)
        {
            if ($parentNode.IsListItem)
            {
                $binding_type = "Array:"+$parentNode.TypeInfo;
            }
            else
            {
                $binding_type = $parentNode.TypeInfo;
            }

            $type_binding.Add($parentNode.Name, $binding_type);
        }

        [string]$nodeName = $parentNode.Name.Trim();

        if ($parentNode.Parent -ne $null)
        {
            $pathToTreeNode += $nodeName;
            $rootNode = $parentNode.Parent;
        }

        $parentNode = $parentNode.Parent;
    }

    if (($rootNode.Name -ne $powershell_object_name) -and ($TreeNode.Name -ne $powershell_object_name))
    {
         return;
    }

    for ($i = $pathToTreeNode.Count - 1; $i -ge 0; $i--)
    {
        $pathFromRoot += $pathToTreeNode[$i];
    }

    $parameters = @();

    if ($TreeNode.Properties.Count -gt 0 -or ($TreeNode.IsListItem))
    {
        foreach ($propertyItem in $TreeNode.Properties)
        {
            if (-not ($propertyItem["Type"] -like "*$ModelNameSpace*"))
            {
                $property_type = Get-ProperTypeName $propertyItem["Type"];
                if ($propertyItem["CanWrite"])
                {
                    $param_name = Get-SingularNoun $propertyItem["Name"];
                    $param = @{Name = $param_name; Type = $property_type; OriginalName = $propertyItem["Name"]; Chain = $pathFromRoot};
                    $parameters += $param;
                }
            }
            else
            {
               Write-Verbose("Skip this property: " + $propertyItem["Name"]);
            }
        }

        foreach ($subNode in $TreeNode.SubNodes)
        {
            $nonSingleSubNodeResult = Get-NonSingleComplexDescendant $subNode $pathFromRoot;
            $nonSingleSubNode = $nonSingleSubNodeResult["Node"];

            if (-not $nonSingleSubNode.IsListItem)
            {
                foreach ($propertyItem in $nonSingleSubNode.Properties)
                {
                    if ($propertyItem["CanWrite"])
                    {
                        $property_type = Get-ProperTypeName $propertyItem["Type"];
                        $chain = $nonSingleSubNodeResult["Chain"];
                        $chain += $nonSingleSubNode.Name;
                        $type_binding = AddTo-HashTable $type_binding $nonSingleSubNode.Name $nonSingleSubNode.TypeInfo;

                        if ($nonSingleSubNode.OnlySimple)
                        {
                            $param_name = Get-SingularNoun ($nonSingleSubNode.Name + $propertyItem["Name"]);
                            $param = @{Name = $param_name; Type = $property_type; OriginalName = $propertyItem["Name"]; Chain = $chain};
                            $parameters += $param;
                        }
                        else
                        {
                            if ($propertyItem["Type"] -like "*$ModelNameSpace*")
                            {

                                $subsub = Get-SpecificSubNode $nonSingleSubNode $propertyItem["Name"];
                                $nonSingleComlexResult = Get-NonSingleComplexDescendant $subsub $chain;
                                $realsubsub = $nonSingleComlexResult["Node"];
                                $chain = $nonSingleComlexResult["Chain"];

                                if ($realsubsub.Properties.Count -eq 1)
                                {
                                    $parameter = $realsubsub.Properties[0];
                                    $property_type = $parameter["Type"];

                                    if ($realsubsub.IsListItem)
                                    {
                                        $paramterType = "Array:" + $property_type;
                                        $bindingType =  "Array:" + $realsubsub.TypeInfo;
                                    }
                                    else
                                    {
                                        $paramterType = $property_type;
                                        $bindingType =  $realsubsub.TypeInfo;
                                    }

                                    $chain += $realsubsub.Name;
                                    $type_binding = AddTo-HashTable $type_binding $realsubsub.Name $bindingType;

                                    if ($propertyItem["CanWrite"])
                                    {
                                        $param_name = Get-SingularNoun $propertyItem["Name"];
                                        $param = @{Name = $param_name; Type = $paramterType; OriginalName = $parameter["Name"]; Chain = $chain};
                                        $parameters += $param;
                                    }
                                }
                                else
                                {
                                    if ($realsubsub.IsListItem)
                                    {
                                        $property_type = Get-ProperTypeName $realsubsub.TypeInfo;
                                        $paramterType = "Array:" + $property_type;
                                    }
                                    else
                                    {
                                        $property_type = Get-ProperTypeName $realsubsub.TypeInfo;
                                        $paramterType = $property_type;
                                    }
                                    $param_name = Get-SingularNoun $realsubsub.Name;
                                    $param = @{Name = $param_name; Type = $paramterType; OriginalName = $realsubsub.Name; Chain = $chain};
                                    $parameters += $param;

                                    $binding = Generate-PowershellParameterCommandImpl $realsubsub $fileOutputFolder;
                                    $type_binding = Merge-HashTables $type_binding $binding;
                                }
                            }
                            else
                            {
                                $param_name = Get-SingularNoun $propertyItem["Name"];
                                $param = @{Name = $param_name; Type = $property_type; OriginalName = $propertyItem["Name"]; Chain = $chain};
                                $parameters += $param;
                            }
                        }
                    }
                }
            }
            elseif ($nonSingleSubNode.Properties.Count -eq 1)
            {
                $onlyProperty = $nonSingleSubNode.Properties[0];
                $chain = $nonSingleSubNodeResult["Chain"];
                $chain += $nonSingleSubNode.Name;
                $type_info = "Array:" + $nonSingleSubNode.TypeInfo;
                $type_binding = AddTo-HashTable $type_binding $nonSingleSubNode.Name $type_info;
                $property_type = Get-ProperTypeName $onlyProperty["Type"];
                if ($onlyProperty["CanWrite"])
                {
                    $param_name = Get-SingularNoun ($nonSingleSubNode.Name + $onlyProperty["Name"]);
                    $param = @{Name = $param_name; Type = "Array:" + $property_type; OriginalName = $onlyProperty["Name"]; Chain = $chain};
                    $parameters += $param;
                }
            }
            else
            {
                $chain = $nonSingleSubNodeResult["Chain"];
                $property_type = Get-ProperTypeName $nonSingleSubNode.TypeInfo;

                $param_name = Get-SingularNoun $nonSingleSubNode.Name;
                $param = @{Name = $param_name; Type = "Array:" + $property_type; OriginalName = $nonSingleSubNode.Name; Chain = $chain};
                $parameters += $param;
                $binding = Generate-PowershellParameterCommandImpl $nonSingleSubNode $fileOutputFolder;
                $type_binding = Merge-HashTables $type_binding $binding;
            }
        }

        (. $PSScriptRoot\Generate-PowershellParameterCmdlet.ps1 -OutputFolder $OutputFolder -TreeNode $TreeNode -Parameters $parameters -ModelNameSpace $ModelNameSpace -ObjectName $powershell_object_name -TypeBinding $type_binding);
    }

    return $type_binding;
}

$ignore_this_output = Generate-PowershellParameterCommandImpl $CmdletTreeNode $OutputFolder;

if ($ToolType -eq 'CLI')
{
    Write-Output (Generate-CliParameterCommandImpl $CmdletTreeNode);
}
