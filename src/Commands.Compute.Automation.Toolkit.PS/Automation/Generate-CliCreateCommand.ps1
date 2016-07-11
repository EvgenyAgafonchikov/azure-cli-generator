

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

    $cliOperationParams = @();
    $cliPromptParams = @();
    $cliDefaults = @();

    $cliCreateParams = @();
    $cliUpdateParams = @();
    $testCreateStr = "";
    $testCreateDefaultStr = "";
    $testUpdateStr = "";

    $inputTestCode = "";
    $assertCodeCreate = "";
    $assertCodeCreateDefault = "";
    $assertIdCodeCreate = "";
    $assertCodeUpdate = "";

    foreach($paramItem in $cliOperationParamsRaw[$OperationName])
    {
        $name = $paramItem.name
        if($name)
        {
            $cliOperationParams += $name;
        }
        else
        {
            Write-Warning "There is no name for one of the parameters inside of $OperationName config!"
        }
        if($paramItem.createValue)
        {
            $value = $paramItem.createValue;
            $testCreateStr += ("--" + (Get-CliOptionName $paramItem.name) + " {${name}} ");
            $inputTestCode += "  ${name}: '$value'," + $NEW_LINE;
            $cliCreateParams += $name;
        }
        if($paramItem.setValue)
        {
            $value = $paramItem.setValue;
            $testUpdateStr += ("--" + (Get-CliOptionName $paramItem.name) + " {${name}New} ");
            $inputTestCode += "  ${name}New: '$value'," + $NEW_LINE;
            $cliUpdateParams += $name;
        }
        if($paramItem.required -eq $true)
        {
            $cliPromptParams += $name;
            if(-not $paramItem.default)
            {
                $testCreateDefaultStr += ("--" + (Get-CliOptionName $paramItem.name) + " {${name}} ");
            }
        }
        if($paramItem.default)
        {
            $cliDefaults += $name;
        }
    }

    $methodParams = $MethodInfo.GetParameters();
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
    $paramDefinitions = Get-ParamsDefinition $cliPromptParams;
    $cmdOptions = "";
    $cmdOptionsSet = "";
    $cliOperationParams = $methodParamNameList + $cliOperationParams;
    for ($index = 0; $index -lt $cliOperationParams.Count; $index++)
    {
        [string]$optionParamName = $cliOperationParams[$index];
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
        if($cli_option_name -ne "location")
        {
            $cmdOptionsSet += "    .option('${cli_shorthand_str}--${cli_option_name} <${cli_option_name}>', `$('${cli_option_help_text}'))" + $NEW_LINE;
        }
        $option_str_items += "--${cli_option_name} `$p${index}";
    }

    # Collect data about 'param-name' and 'param-id' alternatives
    $alternativesArray = @();
    foreach ($item in $cliOperationParams)
    {
        if ($item -clike "*Id")
        {
            $cutItem = $item -creplace "Id", "";
            if($cliOperationParams -contains ($cutItem + "Name"))
            {
                $alternativesArray += $cutItem;
            }
        }
    }

    $commonOptions = Get-CommonOptions $cliMethodOption;

    # Prompting options
    $promptingOptions = Get-PromptingOptionsCode $promptParametersNameList $promptParametersNameList 6;
    $promptingOptionsCustom = Get-PromptingOptionsCode $cliPromptParams $promptParametersNameList 6;

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
    $treeAnalysisResult = "";
    $skuNameMergeRequired = $false;
    $skuNameCode = "";
    foreach($param in $cliOperationParams) {
        $conversion = "";
        $wrapType = "";
        if($param -ne "location" -and $param -ne "tags" -and $param -ne "name")
        {
            $searchParam = $param;
            if($param -like "*Name")
            {
                $tmp = $param -replace "Name", "";
                if($alternativesArray -contains $tmp)
                {
                    $searchParam = $tmp;
                }
            }
            elseif($param -like "*Id")
            {
                $tmp = $param -replace "Id", "";
                if($alternativesArray -contains $tmp)
                {
                    $searchParam = $tmp;
                }
            }
            $paramPathHash = Search-TreeElement "root" $param_object $searchParam;
            if ($paramPathHash)
            {
                $paramPath = $paramPathHash.path;
                if($paramPath -like "*.sku.*")
                {
                    $skuNameMergeRequired = $true;
                }
                $paramType = $paramPathHash.type;
                $paramPath = $paramPath -replace "root.", "";
                $paramPathSplit = $paramPath.Split(".");

                if($param -like "*Name" -and $alternativesArray -contains ($param -replace "Name", ""))
                {
                    continue;
                }
                elseif($param -like "*Id" -and $alternativesArray -contains ($param -replace "Id", ""))
                {
                    $paramPathSplit[$paramPathSplit.Length - 1] += "Id";
                }
                $lastItem =  $paramPathSplit[$paramPathSplit.Length - 1];
                $last = decapitalizeFirstLetter $lastItem;
                $commanderLast = Get-CommanderStyleOption $last;
                $currentPath = "parameters"
                for ($i = 0; $i -lt $paramPathSplit.Length - 1; $i += 1) {
                    $current = decapitalizeFirstLetter $paramPathSplit[$i];

                    if($current -like "*[0]*")
                    {
                        $currentArray = "${currentPath}.${current}" -replace "\[0\]","";
                        $treeAnalysisResult += "        if(!$currentArray) {" + $NEW_LINE;
                        $treeAnalysisResult += "          ${currentArray} = [];" + $NEW_LINE;
                        $treeAnalysisResult += "        }" + $NEW_LINE;
                    }

                    $treeAnalysisResult += "        if(!${currentPath}.${current}) {" + $NEW_LINE;
                    $treeAnalysisResult += "          ${currentPath}.${current} = {};" + $NEW_LINE;
                    if ($current -eq "ipConfigurations[0]")
                    {
                        $treeAnalysisResult += "          ${currentPath}.${current}.name = 'default';" + $NEW_LINE;
                    }
                    ${currentPath} += ".${current}";
                    $treeAnalysisResult += "        }" + $NEW_LINE;
                }

                $treeProcessedList += $last;

                $setValue = "null"
                $assertValue = "null";
                $assertValueUpdate = "null";
                $assertionType = "equal";
                if ($cliOperationParams -contains $lastItem) {
                    $treeAnalysisResult += "        if(options.${commanderLast}) {" + $NEW_LINE;
                    if($paramType -ne $null -and $paramType -like "*List*") {
                        if($last -eq "loadBalancerBackendAddressPools" -or $last -eq "loadBalancerInboundNatRules")
                        {
                            $setValue = "options." + $commanderLast + ".split(',').map(function(item) { return { id: item } })";
                        }
                        else
                        {
                            $setValue = "options." + $commanderLast + ".split(',')";
                            $assertValue = "${cliOperationName}.${last}";
                            $assertValueUpdate = "${cliOperationName}.${last}New";
                            $assertionType = "containEql";
                        }
                            $wrapType = "list";
                    }
                    elseif($paramType -ne $null -and $paramType -like "*Nullable*")
                    {
                        $underlying =  [System.Nullable]::GetUnderlyingType($paramType);
                        if($underlying -like "*Int*")
                        {
                            $setValue = "parseInt(options.${commanderLast}, 10);";
                            $assertValue = "parseInt(${cliOperationName}.${last}, 10)";
                            $assertValueUpdate = "parseInt(${cliOperationName}.${last}New, 10)";
                            $wrapType = "int";
                        }
                        elseif($underlying.Name -like "*Boolean*")
                        {
                            $setValue = "utils.parseBool(options.${commanderLast});";
                            $assertValue = "utils.parseBool(${cliOperationName}.${last})";
                            $assertValueUpdate = "utils.parseBool(${cliOperationName}.${last}New)";
                            $wrapType = "bool";
                        }
                    }
                    elseif($paramType -ne $null -and $paramType -like "*String*") {
                        $setValue = "options." + $commanderLast;
                        $conversion = ".toLowerCase()";
                        $assertValue = "${cliOperationName}.${last}";
                        $assertValueUpdate = "${cliOperationName}.${last}New";
                        $wrapType = "string";
                    }
                    else {
                        $setValue = "options." + $commanderLast;
                        $assertValue = "${cliOperationName}.${last}"
                        $assertValueUpdate = "${cliOperationName}.${last}New";
                    }
                }

                    if($last -clike "*Id" -and $alternativesArray -contains ($param -replace "Id", ""))
                    {
                        $itemStrippedId = $last -creplace "Id","";
                        $itemStrippedComander = Get-CommanderStyleOption $itemStrippedId;
                        if ($alternativesArray -contains $itemStrippedId)
                        {
                            $treeAnalysisResult += "          ${currentPath}.${itemStrippedId} = {};" + $NEW_LINE;
                            $treeAnalysisResult += "          ${currentPath}.${itemStrippedId}.id = options.${last};" + $NEW_LINE;
                            $treeAnalysisResult += "        } else if (options.${itemStrippedComander}Name) {" + $NEW_LINE;
                            $treeAnalysisResult += "          ${currentPath}.${itemStrippedId} = {};" + $NEW_LINE;
                            $cliOptionToGetIdByName = Get-CliNormalizedName $itemStrippedId;
                            if ($cliOptionToGetIdByName.toLower().EndsWith("address"))
                            {
                                $cliOptionToGetIdByName += "es";
                            }
                            else
                            {
                                $cliOptionToGetIdByName += "s";
                            }

                            if($itemStrippedId -ne "subnet")
                            {
                                $treeAnalysisResult +=
"          var idContainer = ${componentNameInLowerCase}ManagementClient.${cliOptionToGetIdByName}.get(resourceGroup, options.${itemStrippedComander}Name, _);"
                            }
                            else
                            {
                                $treeAnalysisResult +=
"          var idContainer = ${componentNameInLowerCase}ManagementClient.${cliOptionToGetIdByName}.get(resourceGroup, options.subnetVirtualNetworkName, options.${itemStrippedComander}Name, _);"
                            }
$treeAnalysisResult +=
"
          ${currentPath}.${itemStrippedId}.id = idContainer.id;
"
                        }
                    }
                    else
                    {
                        $treeAnalysisResult += "          ${currentPath}.${last} = ${setValue};";
                        if($last -eq "privateIPAddress")
                        {
                            $treeAnalysisResult += $NEW_LINE + "          ${currentPath}.privateIPAllocationMethod = 'Static';";
                        }
                    }

                    $assertPath = $currentPath -replace "parameters", "output";
                    if($cliDefaults -contains $last)
                    {
                        $def = $cliOperationParamsRaw[$OperationName] | Where-Object -Property name -eq $last;
                        $defValue = (Get-WrappedAs $wrapType $def.default);
                        $defAssertValue = "'{0}'" -f $def.default;
                        if($wrapType -ne "list")
                        {
                            $defAssertValue = $defValue;
                        }
                        $treeAnalysisResult += $NEW_LINE + "        } else if (useDefaults) {" + $NEW_LINE;
                        $treeAnalysisResult += "          ${currentPath}.${last} = ${defValue};";
                        $assertCodeCreateDefault += "            ${assertPath}.${last}${conversion}.should.${assertionType}(${defAssertValue}${conversion});" + $NEW_LINE;
                    }
                    $treeAnalysisResult += $NEW_LINE;
                    if($cliCreateParams -contains $last -and $last -notlike "*Id" -and $item -notmatch ".+name")
                    {
                        $assertCodeCreate += "            ${assertPath}.${last}${conversion}.should.${assertionType}(${assertValue}${conversion});" + $NEW_LINE;
                    }
                    if($cliUpdateParams -contains $last -and $last -notlike "*Id" -and $item -notmatch ".+name")
                    {
                        $assertCodeUpdate += "            ${assertPath}.${last}${conversion}.should.${assertionType}(${assertValueUpdate}${conversion});" + $NEW_LINE;
                    }
                    $treeAnalysisResult += "        }" + $NEW_LINE;
            }
        }
    }

    if($skuNameMergeRequired)
    {
        $skuNameCode = "      if (parameters.sku.tier && parameters.sku.family) {
        parameters.sku.name = parameters.sku.tier + '_' + parameters.sku.family;
      }
"
    }

    $updateParametersCode = ""
    foreach($item in $cliOperationParams)
    {
        if (-not ($treeProcessedList -contains $item) -and $item -ne "parameters")
        {
            if($item -cnotlike "*Id" -and $item -cnotlike "*Name")
            {
                $updateParametersCode  += "        if(options.${item}) {" + $NEW_LINE;
            }
            elseif($alternativesArray -notcontains ($item -creplace "Id","") -and $alternativesArray -notcontains ($item -creplace "Name",""))
            {
                $updateParametersCode  += "        if(options.${item}) {" + $NEW_LINE;
            }
            if($item -ne "tags")
            {
                if($item -ne $currentOperationNormalizedName -and
                    $item -ne "resourceGroup" -and
                   $item -notmatch ".+name")
                {
                    if($item -clike "*Id")
                    {
                        $itemStrippedId = $item -creplace "Id","";
                        if ($alternativesArray -contains $itemStrippedId)
                        {
                            $updateParametersCode += "        if (options.${item}) {" + $NEW_LINE;
                            $updateParametersCode += "          parameters.${itemStrippedId} = {};" + $NEW_LINE;
                            $updateParametersCode += "          parameters.${itemStrippedId}.id = options.${item};" + $NEW_LINE;
                            $updateParametersCode += "        } else if (options.${itemStrippedId}Name) {" + $NEW_LINE;
                            $updateParametersCode += "          parameters.${itemStrippedId} = {};" + $NEW_LINE;
                            $cliOptionToGetIdByName = Get-CliNormalizedName $itemStrippedId;
                            if ($cliOptionToGetIdByName.toLower().EndsWith("address"))
                            {
                                $cliOptionToGetIdByName += "es";
                            }
                            else
                            {
                                $cliOptionToGetIdByName += "s";
                            }
                            $updateParametersCode +=
"          var idContainer = ${componentNameInLowerCase}ManagementClient.${cliOptionToGetIdByName}.get(resourceGroup, options.${itemStrippedId}Name, _);
          parameters.${itemStrippedId}.id = idContainer.id;
"
                            $updateParametersCode += "        }" + $NEW_LINE;
                            if($cliCreateParams -contains $item -or $cliCreateParams -contains ($itemStrippedId + "Name"))
                            {
                                $assertIdCodeCreate += "            output.${itemStrippedId}.id.should.equal(${itemStrippedId}.id);" + $NEW_LINE;
                            }
                        }
                    }
                    else
                    {
                        $assertCodeCreate += "            output.${item}.should.equal(${cliOperationName}.${item});" + $NEW_LINE;
                    }
                }
                if($item -ne $currentOperationNormalizedName -and
                    $item -ne "resourceGroup" -and
                    $item -ne "location" -and
                    $cliUpdateParams -contains $item -and
                    $item -notlike "*Id" -and
                    $item -notmatch ".+name")
                {
                    $assertCodeUpdate += "            output.${item}.should.equal(${cliOperationName}.${item}New);" + $NEW_LINE;
                }
                if($item -cnotlike "*Id" -and $item -cnotlike "*Name")
                {
                    $updateParametersCode  += "          parameters.${item} = options.${item};" + $NEW_LINE;
                }
                elseif($alternativesArray -notcontains ($item -creplace "Id","") -and $alternativesArray -notcontains ($item -creplace "Name",""))
                {
                    $updateParametersCode  += "          parameters.${item} = options.${item};" + $NEW_LINE;
                }
            }
            else
            {
                $updateParametersCode  += "          if (utils.argHasValue(options.tags)) {
            tagUtils.appendTags(parameters, options);
          }" + $NEW_LINE;
            $assertCodeCreate += "            tagUtils.getTagsInfo(output.${item}).should.equal(${cliOperationName}.${item});";
            $assertCodeUpdate += "            if (${cliOperationName}.${item}New) {
              tagUtils.getTagsInfo(output.${item}).should.equal(${cliOperationName}.${item} + ';' + ${cliOperationName}.${item}New);
            }" + $NEW_LINE;
            }
            if($item -cnotlike "*Id" -and $item -cnotlike "*Name")
            {
                $updateParametersCode  += "        }" + $NEW_LINE;
            }
            elseif($alternativesArray -notcontains ($item -creplace "Id","") -and $alternativesArray -notcontains ($item -creplace "Name",""))
            {
                $updateParametersCode  += "        }" + $NEW_LINE;
            }
        }
    }

    $depsCode = "";
    $additionalOptionsCommon = "";
    $additionalOptionsCreate = "";
    $closingBraces = "";
    if($dependencies[$OperationName])
    {
        foreach($dependency in $dependencies[$OperationName])
        {
            $parentCmd = "";
            $parentRef = "";
            if($parents[$dependency])
            {
                $depParent = $parents[$dependency];
                $parentCmd = Get-CliOptionName $parents[$dependency];
                $parentRef = "--${parentCmd}-name ${depParent}Name";
                $parentCmd = " ${parentCmd}";
            }
            $outResult = "";
            $depCliOption = Get-SingularNoun (Get-CliOptionName $dependency);
            $depResultVarName = (decapitalizeFirstLetter (Get-SingularNoun $dependency));
            $depCliName = $depResultVarName + "Name";
            if($inputTestCode -like "*${depCliName}*")
            {
                $depCliName = "{${depCliName}}";
            }
            $outResult += "          var cmd = '${componentNameInLowerCase}-autogen${parentCmd} ${depCliOption} create -g {group} -n ${depCliName} ${parentRef} ";
            foreach($param in $cliOperationParamsRaw[$dependency])
            {
                if($param.required -eq $true)
                {
                    $outResult += " --" + ((Get-CliOptionName $param.name) -replace "express-route-","") + " " + $param.createValue;
                }
                if($param.name -eq "location" -and $inputTestCode -notlike "*location*")
                {
                    $inputTestCode += "  location: '" +  $param.createValue + "'," + $NEW_LINE;
                }
            }
            $outResult += " --json'.formatArgs(${cliOperationName})" + $NEW_LINE;
            $outResult += "testUtils.executeCommand(suite, retry, cmd, function (${depResultVarName}) {"
            $depsCode += $outResult + $NEW_LINE
            $depsCode += "${depResultVarName}.exitStatus.should.equal(0);" + $NEW_LINE;
            $depsCode += "${depResultVarName} = JSON.parse(${depResultVarName}.text);" + $NEW_LINE;
            if($testCreateStr -notlike "*${depCliOption}*")
            {
                $depCliOption = $depCliOption -replace "express-route-","";
                $additionalOptionsValue = " --${depCliOption}-name ${depCliName} ";
                if($OperationName -eq "NetworkInterfaces")
                {
                    $additionalOptionsValue = $additionalOptionsValue -creplace "virtual-network-name","subnet-virtual-network-name";
                }
                if($parents[$OperationName] -eq (Get-SingularNoun $dependency) -or $dependency -eq "ExpressRouteCircuits")
                {
                    $additionalOptionsCommon += $additionalOptionsValue;
                }
                $additionalOptionsCreate +=  $additionalOptionsValue;
            }
            $closingBraces += "});" + $NEW_LINE;
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

    if (-not $parents[$OperationName])
    {
        $parentOp = "";
    }
    else
    {
        $parentOp = (Get-CliOptionName $parents[$OperationName]) + " ";
    }
    $template = Get-Content "$PSScriptRoot\templates\test.ps1" -raw;
    $outTest = Invoke-Expression $template;
    Set-Content -Path "$PSScriptRoot\arm.network.${cliOperationNameInLowerCase}-tests.js" -Value $outTest -Encoding "UTF8" -Force;

    return $code;