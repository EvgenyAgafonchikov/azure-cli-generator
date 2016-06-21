

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
. "$PSScriptRoot\Import-ParserFunction.ps1";

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
    # Options declaration
    #
    $option_str_items = @();
    $use_input_parameter_file = $false;

    $promptParametersNameList = @();
    $promptParametersNameList += $methodParamNameList;
    $paramDefinitions = Get-ParamsDefinition $cliPromptParams[$OperationName];
    $cmdOptions = "";
    $cliOperationParams[$OperationName] = $methodParamNameList + $cliOperationParams[$OperationName];
    for ($index = 0; $index -lt $cliOperationParams[$OperationName].Count; $index++)
    {
        [string]$optionParamName = $cliOperationParams[$OperationName][$index];
        $optionShorthandStr = $null;

        $cli_option_name = Get-CliOptionName $optionParamName;
        $cli_shorthand_str = Get-CliShorthandName $optionParamName $currentOperationNormalizedName;
        if ($cli_shorthand_str -ne '')
        {
            $cli_shorthand_str = "-" + $cli_shorthand_str + ", ";
        }
        $cli_option_help_text = "the ${cli_option_name} of ${cliOperationDescription}";
        if ($cli_option_name -like "*parameters")
        {
            $cli_option_name = "parameters-file";
        }
        $cmdOptions += "    .option('${cli_shorthand_str}--${cli_option_name} <${cli_option_name}>', `$('${cli_option_help_text}'))" + $NEW_LINE;
        $option_str_items += "--${cli_option_name} `$p${index}";
    }

    $commonOptions = Get-CommonOptions $cliMethodOption;

    # Prompting options
    $promptingOptions = Get-PromptingOptionsCode $promptParametersNameList $promptParametersNameList 6;
    $promptingOptionsCustom = Get-PromptingOptionsCode $cliPromptParams[$OperationName] $promptParametersNameList 6;

    #
    # API call using SDK
    #
    $cliMethodFuncName = $cliMethodName;
    if ($cliMethodFuncName -eq "delete")
    {
        $cliMethodFuncName += "Method";
    }
    $resultVarName = "result";
    $safeGet = Get-SafeGetFunction $componentNameInLowerCase $cliOperationName $methodParamNameList $resultVarName $cliOperationDescription;

    $treeProcessedList = @();
    $treeAnalysisResult = ""
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
                $commanderLast = Get-CommanderStyleOption $last;
                $currentPath = "parameters"
                for ($i = 0; $i -lt $paramPathSplit.Length - 1; $i += 1) {
                    $treeAnalysisResult += "        if(options.${last}) {" + $NEW_LINE;
                    $current = decapitalizeFirstLetter $paramPathSplit[$i];
                    $treeAnalysisResult += "          if(!${currentPath}.${current}) {" + $NEW_LINE;
                    $treeAnalysisResult += "            ${currentPath}.${current} = {};" + $NEW_LINE;
                    ${currentPath} += ".${current}";
                    $treeAnalysisResult += "          }" + $NEW_LINE;
                    $treeAnalysisResult += "        }" + $NEW_LINE;
                }
                $treeProcessedList += $last;

                $setValue = "null"
                if ($cliOperationParams[$OperationName] -contains $lastItem) {
                    $treeAnalysisResult += "        if(options.${commanderLast}) {" + $NEW_LINE;
                    if($paramType -ne $null -and $paramType -like "*List*") {
                        $setValue = "options." + $commanderLast+ ".split(',')";
                    } elseif($paramType -ne $null -and $paramType -like "*Nullable*")
                    {
                        $underlying =  [System.Nullable]::GetUnderlyingType($paramType);
                        if($underlying -like "*Int*")
                        {
                            $setValue = "parseInt(options.${commanderLast}, 10);"
                        }
                    }
                    else {
                        $setValue = "options." + $commanderLast;
                    }
                }
                $treeAnalysisResult += "          ${currentPath}.${last} = ${setValue};" + $NEW_LINE;
                $treeAnalysisResult += "        }" + $NEW_LINE;
            }
        }
    }

    $updateParametersCode = ""
    foreach($item in $cliOperationParams[$OperationName])
    {
        if (-not ($treeProcessedList -contains $item) -and $item -ne "parameters")
        {
            $updateParametersCode  += "        if(options.${item}) {" + $NEW_LINE;
            if($item -ne "tags")
            {
                $updateParametersCode  += "          parameters.${item} = options.${item};" + $NEW_LINE;
            }
            else
            {
                $updateParametersCode  += "          if (utils.argHasValue(options.tags)) {
            tagUtils.appendTags(parameters, options);
          }" + $NEW_LINE;
            }
            $updateParametersCode  += "        }" + $NEW_LINE;
        }
    }

    $parametersString = Get-ParametersString $methodParamNameList;
    $parsers = Get-SubnetParser;
    $template = Get-Content "$PSScriptRoot\templates\create.ps1" -raw;
    $code += Invoke-Expression $template;
    return $code;