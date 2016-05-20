

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

. "$PSScriptRoot\Import-StringFunction.ps1";
. "$PSScriptRoot\Import-TypeFunction.ps1";
. "$PSScriptRoot\Import-WriterFunction.ps1";

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
            $methodParamName = (Get-CliMethodMappedParameterName $methodParamName $methodParamIndex);
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
    $mappedMethodName = Get-CliMethodMappedFunctionName $methodName;
    $cliMethodOption = Get-CliOptionName $mappedMethodName;

    # 3.2.4 Compute the CLI Command Description, i.e. VirtualMachineScaleSet => virtual machine scale set
    $cliOperationDescription = (Get-CliOptionName $OperationName).Replace('-', ' ');
    
    
    # 3.2.6 Generate the CLI Command Code
    $code = "";

    if ($ModelNameSpace -like "*.WindowsAzure.*")
    {
        # Use Invoke Category for RDFE APIs
        $invoke_category_desc = "Commands to invoke service management operations.";
        $asmTopCatName = Get-CliCategoryName $componentName;
        if ($asmTopCatName -eq 'compute')
        {
            $asmTopCatName = 'service';
        }
        $invoke_category_code = ".category('" + $asmTopCatName + "').description('${invoke_category_desc}')";
        if ($componentName -eq 'Network')
        {
            $cliCategoryName = 'vnet';
        }
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

    
    if ($ModelNameSpace.Contains(".WindowsAzure."))
    {
        $code += "    var result = ${componentNameInLowerCase}ManagementClient.${cliOperationName}s.${cliMethodFuncName}(";
    }
    else
    {
        if ($cliOperationName -like "containerService*" -or $cliOperationName -like "usage*")
        {
            $code += "    var result = ${componentNameInLowerCase}ManagementClient.${cliOperationName}Operations.${cliMethodFuncName}(";
        }
        else
        {
            $code += "    var result = ${componentNameInLowerCase}ManagementClient.${cliOperationName}.${cliMethodFuncName}(";
        }
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
            $action_category_name = 'create';
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
	$code += "
	/* >>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>>> CREATE COMMAND CODE STUFF <<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<<< */
	";
    return $code;