

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
    #TODO: change to usuall array w/o hash;
    $cliOperationParams[$OperationName] = @();
    $cliPromptParams[$OperationName] = @();

    $cliCreateParams = @();
    $cliUpdateParams = @();
    $testCreateStr = "";
    $testUpdateStr = "";
    $inputTestCode = "";
    $assertCodeCreate = "";
    $assertCodeUpdate = "";

    foreach($paramItem in $cliOperationParamsRaw[$OperationName])
    {
        $name = $paramItem.name
        if($name )
        {
            $cliOperationParams[$OperationName] += $name;
        }
        else
        {
            Write-Warning "There is no name for one of the parameters inside of $OperationName config!"
        }
        if($paramItem.inCreateSet -eq $true)
        {
            $value = $paramItem.first;
            $testCreateStr += ("--" + (Get-CliOptionName $paramItem.name) + " {${name}} ");
            $inputTestCode += "  ${name}: '$value'," + $NEW_LINE;
            $cliCreateParams += $name;
        }
        if($paramItem.inUpdateSet -eq $true)
        {
            $value = $paramItem.second;
            $testUpdateStr += ("--" + (Get-CliOptionName $paramItem.name) + " {${name}New} ");
            $inputTestCode += "  ${name}New: '$value'," + $NEW_LINE;
            $cliUpdateParams += $name;
        }
        if($paramItem.required -eq $true)
        {
            $cliPromptParams[$OperationName] += $name;
        }
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
    $methodParams = $methodParams | Where-Object {$_.Name -notlike "*parameters"};;

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
                $assertValue = "null";
                $assertValueUpdate = "null";
                $assertionType = "equal";
                if ($cliOperationParams[$OperationName] -contains $lastItem) {
                    $treeAnalysisResult += "        if(options.${commanderLast}) {" + $NEW_LINE;
                    if($paramType -ne $null -and $paramType -like "*List*") {
                        $setValue = "options." + $commanderLast+ ".split(',')";
                        $assertValue = "${cliOperationName}.${last}"
                        $assertValueUpdate = "${cliOperationName}.${last}New"
                        $assertionType = "containEql";
                    } elseif($paramType -ne $null -and $paramType -like "*Nullable*")
                    {
                        $underlying =  [System.Nullable]::GetUnderlyingType($paramType);
                        if($underlying -like "*Int*")
                        {
                            $setValue = "parseInt(options.${commanderLast}, 10);"
                            $assertValue = "parseInt(${cliOperationName}.${last}, 10)"
                            $assertValueUpdate = "parseInt(${cliOperationName}.${last}New, 10)"
                        }
                    }
                    else {
                        $setValue = "options." + $commanderLast;
                        $assertValue = "${cliOperationName}.${last}"
                        $assertValueUpdate = "${cliOperationName}.${last}New"
                    }
                }
                $treeAnalysisResult += "          ${currentPath}.${last} = ${setValue};" + $NEW_LINE;
                $assertPath = $currentPath -replace "parameters", "output";
                if($cliCreateParams -contains $last)
                {
                    $assertCodeCreate += "            ${assertPath}.${last}.should.${assertionType}(${assertValue});" + $NEW_LINE;
                }
                if($cliUpdateParams -contains $last)
                {
                    $assertCodeUpdate += "            ${assertPath}.${last}.should.${assertionType}(${assertValueUpdate});" + $NEW_LINE;
                }
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
                if($item -ne $currentOperationNormalizedName -and $item -ne "resourceGroup" -and $cliCreateParams -contains $last)
                {
                    $assertCodeCreate += "            output.${item}.should.equal(${cliOperationName}.${item});" + $NEW_LINE;
                }
                if($item -ne $currentOperationNormalizedName -and $item -ne "resourceGroup" -and $item -ne "location" -and $cliUpdateParams -contains $last)
                {
                    $assertCodeUpdate += "            output.${item}.should.equal(${cliOperationName}.${item}New);" + $NEW_LINE;
                }
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
    $code += $NEW_LINE

    # Generate set command
    $cliMethodOption = "set";
    $template = Get-Content "$PSScriptRoot\templates\set.ps1" -raw;
    $code += Invoke-Expression $template;

#TODO: remove condition after tests generation will be ready for child items
    if (-not $parents[$OperationName])
    {
        $template = Get-Content "$PSScriptRoot\templates\test.ps1" -raw;
        $outTest = Invoke-Expression $template;
        Set-Content -Path "$PSScriptRoot\arm.network.${cliOperationNameInLowerCase}-tests.js" -Value $outTest -Encoding "UTF8" -Force;
    }

    return $code;