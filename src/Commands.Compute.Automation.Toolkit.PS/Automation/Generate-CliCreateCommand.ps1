

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
. "$PSScriptRoot\CommonVars.ps1";
. "$PSScriptRoot\Helpers.ps1";

    # Skip Pagination Function
    if (CheckIf-PaginationMethod $MethodInfo)
    {
        return;
    }
    $methodParams = $MethodInfo.GetParameters();
    $additionalOptions = @();
    foreach ($param in $methodParams)
    {
        if($param.Name -like "*parameters")
        {
            $paramType = $param.ParameterType;
            $param_object = (. $PSScriptRoot\Create-ParameterObject.ps1 -typeInfo $paramType);
        }
    }

    $code = $NEW_LINE;

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

    # Set Required Parameters
    $requireParams = @();
    $requireParamNormalizedNames = @();
    $require = Update-RequiredParameters $methodParamNameList $methodParamTypeDict $allStringFieldCheck;
    $requireParams = $require.requireParams;
    $requireParamNormalizedNames = $require.requireParamNormalizedNames;

    $requireParamsString = $null;
    $usageParamsString = $null;
    $optionParamString = $null;

    $requireParamsString = Get-RequireParamsString $requireParams;
    $usageParamsString = Get-UsageParamsString $requireParams;
    $optionParamString = ([string]::Join(", ", $requireParamNormalizedNames)) + ", ";

    #
    # Command declaration
    #
    $code +=
    "  ${cliOperationName}.command('${cliMethodOption}${requireParamsString}')
    .description(`$('Create a ${cliOperationDescription}'))
    .usage('[options]${usageParamsString}')" + $NEW_LINE;

    #
    # Options declaration
    #
    $option_str_items = @();
    $use_input_parameter_file = $false;

    $promptParametersNameList = @();
    $promptParametersNameList += $methodParamNameList;
    $paramDefinitions = Get-ParamsDefinition $cliPromptParams[$OperationName];

    $cliOperationParams[$OperationName] = $cliOperationParams[$OperationName] + $methodParamNameList;
    for ($index = 0; $index -lt $cliOperationParams[$OperationName].Count; $index++)
    {
        [string]$optionParamName = $cliOperationParams[$OperationName][$index];
        $optionShorthandStr = $null;

        $cli_option_name = Get-CliOptionName $optionParamName;
        $cli_shorthand_str = Get-CliShorthandName $optionParamName;
        if ($cli_shorthand_str -ne '')
        {
            $cli_shorthand_str = "-" + $cli_shorthand_str + ", ";
        }
        $cli_option_help_text = "the ${cli_option_name} of ${cliOperationDescription}";
        if ($cli_option_name -like "*parameters")
        {
            $cli_option_name = "parameters-file"; #$cli_option_name -replace "parameters", "parameters-file";
        }
        $code += "    .option('${cli_shorthand_str}--${cli_option_name} <${cli_option_name}>', `$('${cli_option_help_text}'))" + $NEW_LINE;
        $option_str_items += "--${cli_option_name} `$p${index}";
    }

    $code += Get-CommonOptions $cliMethodOption;
    $code += "    .execute(function(${optionParamString}options, _) {" + $NEW_LINE;

    # Prompting options
    $code += Get-PromptingOptionsCode $promptParametersNameList $promptParametersNameList 6;
    $code += "      " + $paramDefinitions + $NEW_LINE;
    $code += Get-PromptingOptionsCode $cliPromptParams[$OperationName] $promptParametersNameList 6;

    #
    # API call using SDK
    #
    $cliMethodFuncName = $cliMethodName;
    if ($cliMethodFuncName -eq "delete")
    {
        $cliMethodFuncName += "Method";
    }
    $resultVarName = "result";
    $code += "
      var subscription = profile.current.getSubscription(options.subscription);
      var ${componentNameInLowerCase}ManagementClient = utils.create${componentName}ManagementClient(subscription);

      var ${resultVarName};"
    $code += Get-SafeGetFunction $componentNameInLowerCase $cliOperationName $methodParamNameList $resultVarName $cliOperationDescription;

    $code += "
      if (${resultVarName}) {
        throw new Error(util.format(`$('A ${cliOperationDescription} with name `"%s`" already exists in the resource group `"%s`"'), name, resourceGroup));
      }

      if (parameters) {
        var contents = fs.readFileSync(parameters, 'utf8');
        parameters = JSON.parse(contents);
      } else {
        parameters = {};" + $NEW_LINE;

    $treeProcessedList = @();
    foreach($param in $cliOperationParams[$OperationName]) {
        if($param -ne "location" -and $param -ne "tags" -and $param -ne "name")
        {
            $paramPathHash = Search-TreeElement "root" $param_object $param;
            if ($paramPathHash)
            {
                $paramPath = $paramPathHash.path;
                $paramType = $paramPathHash.type;
                $paramPath = $paramPath -replace "root.", "";
                $paramPathSplit = $paramPath.Split(".");
                $lastItem =  $paramPathSplit[$paramPathSplit.Length - 1];
                $last = decapitalizeFirstLetter $lastItem;
                $currentPath = "parameters"
                for ($i = 0; $i -lt $paramPathSplit.Length - 1; $i += 1) {
                    $code += "        if(options.${last}) {" + $NEW_LINE;
                    $current = decapitalizeFirstLetter $paramPathSplit[$i];
                    $code += "          if(!${currentPath}.${current}) {" + $NEW_LINE;
                    $code += "            ${currentPath}.${current} = {};" + $NEW_LINE;
                    ${currentPath} += ".${current}";
                    $code += "          }" + $NEW_LINE;
                    $code += "        }" + $NEW_LINE;
                }
                $treeProcessedList += $last;

                $setValue = "null"
                if ($cliOperationParams[$OperationName] -contains $lastItem) {
                    $code += "        if(options.${last}) {" + $NEW_LINE;
                    if($paramType -ne $null -and $paramType -like "*List*") {
                        $setValue = "options." + $last + ".split(',')";
                    }
                    else {
                        $setValue = "options." + $last;
                    }
                }
                $code += "          ${currentPath}.${last} = ${setValue};" + $NEW_LINE;
                $code += "        }" + $NEW_LINE;
            }
        }
    }

    foreach($item in $cliOperationParams[$OperationName])
    {
        if (-not ($treeProcessedList -contains $item) -and $item -ne "parameters")
        {
            $code += "        if(options.${item}) {" + $NEW_LINE;
            if($item -ne "tags")
            {
                $code += "          parameters.${item} = options.${item};" + $NEW_LINE;
            }
            else
            {
                $code += "          if (utils.argHasValue(options.tags)) {
            tagUtils.appendTags(parameters, options);
          }" + $NEW_LINE;
            }
            $code += "        }" + $NEW_LINE;
        }
    }

    $code +=
"      }
      var progress = cli.interaction.progress(util.format(`$('Creating $cliOperationDescription `"%s`"'), name));
      try {
        ${resultVarName} = ${componentNameInLowerCase}ManagementClient.${cliOperationName}.${cliMethodFuncName}(";
    $code += Get-ParametersString $methodParamNameList;
    $code += ", _);";

    $code += "
      } finally {
        progress.end();
      }" + $NEW_LINE;

    $code += "
      cli.interaction.formatOutput(${resultVarName}, traverse);"  + $NEW_LINE;

    #
    # End of command declaration
    #
    $code += "  });" + $NEW_LINE;

    return $code;