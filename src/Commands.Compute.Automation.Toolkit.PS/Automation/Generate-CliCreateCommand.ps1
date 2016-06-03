

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
    for ($index = 0; $index -lt $methodParamNameList.Count; $index++)
    {
        [string]$optionParamName = $methodParamNameList[$index];
        $optionShorthandStr = $null;

        $cli_option_name = Get-CliOptionName $optionParamName;
        $cli_shorthand_str = Get-CliShorthandName $optionParamName;
        if ($cli_shorthand_str -ne '')
        {
            $cli_shorthand_str = "-" + $cli_shorthand_str + ", ";
        }
        $cli_option_help_text = "the ${cli_option_name} of ${cliOperationDescription}";
        if ($cli_option_name -eq "parameters")
        {
            $cli_option_name = $cli_option_name -replace "parameters", "parameters-file";
        }
        $code += "    .option('${cli_shorthand_str}--${cli_option_name} <${cli_option_name}>', `$('${cli_option_help_text}'))" + $NEW_LINE;
        $option_str_items += "--${cli_option_name} `$p${index}";
    }

    #TODO: Generate list using reflection
#	$code += Get-CreatePublucIPOptions;
    $code += Get-CommonOptions $cliMethodOption;
    $code += "    .execute(function(${optionParamString}options, _) {" + $NEW_LINE;

    # Prompting options
    $code += Get-PromptingOptionsCode $methodParamNameList 6;

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
        throw new Error(util.format(`$('A public ip address with name `"%s`" already exists in the resource group `"%s`"'), name, resourceGroup));
      }

      var contents = fs.readFileSync(parameters, 'utf8');
      parameters = JSON.parse(contents);
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