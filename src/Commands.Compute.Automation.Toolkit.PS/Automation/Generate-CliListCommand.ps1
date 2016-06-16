

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

. "$PSScriptRoot\CommonVars.ps1"
. "$PSScriptRoot\Import-StringFunction.ps1";
. "$PSScriptRoot\Import-TypeFunction.ps1";
. "$PSScriptRoot\Import-WriterFunction.ps1";
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
    .description(`$('List a ${cliOperationDescription}'))
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
        $code += "    .option('${cli_shorthand_str}--${cli_option_name} <${cli_option_name}>', `$('${cli_option_help_text}'))" + $NEW_LINE;
        $option_str_items += "--${cli_option_name} `$p${index}";
    }

    $code += Get-CommonOptions $cliMethodOption;
    $code += "    .execute(function(${optionParamString}options, _) {" + $NEW_LINE;

    # Prompting options
    #$code += Get-PromptingOptionsCode $methodParamNameList 6;
    $code += "      options.resourceGroup = resourceGroup;" + $NEW_LINE;

    #
    # API call using SDK
    #
    $cliMethodFuncName = $cliMethodName;
    $resultVarName = "result";

    $code += "
      var subscription = profile.current.getSubscription(options.subscription);
      var ${componentNameInLowerCase}ManagementClient = utils.create${componentName}ManagementClient(subscription);

      var ${resultVarName} = null;"

    $promptingCode = Get-PromptingOptionsCode $methodParamNameList $methodParamNameList 12;
    $methodParamNameListNoRes = $methodParamNameList -ne "resourceGroup";
    $promptingCodeNoResource = Get-PromptingOptionsCode $methodParamNameListNoRes $methodParamNameListNoRes 12;
    $code += "
      var progress;
      try {
        if(typeof ${componentNameInLowerCase}ManagementClient.${cliOperationName}.listAll != 'function') {
${promptingCode}
          progress = cli.interaction.progress(`$('Getting the $cliOperationDescription'));
          ${resultVarName} = ${componentNameInLowerCase}ManagementClient.${cliOperationName}.list(${optionParamString} _);
        } else {
          if(options.resourceGroup) {
${promptingCode}
            progress = cli.interaction.progress(`$('Getting the $cliOperationDescription'));
            ${resultVarName} = ${componentNameInLowerCase}ManagementClient.${cliOperationName}.list(${optionParamString} _);
          } else {
${promptingCodeNoResource}
            progress = cli.interaction.progress(`$('Getting the $cliOperationDescription'));
            ${resultVarName} = ${componentNameInLowerCase}ManagementClient.${cliOperationName}.listAll(${optionParamString} _);
          }
        }
      } finally {
        progress.end();
      }" + $NEW_LINE;

    $code += "
      if (${resultVarName}.length === 0) {
        cli.output.warn(`$('No $cliOperationDescription found'));
      } else {
        cli.output.table(result, function (row, item) {
          row.cell(`$('Name'), item.name);
          row.cell(`$('Location'), item.location);
          var resInfo = resourceUtils.getResourceInformation(item.id);
          row.cell(`$('Resource group'), resInfo.resourceGroup);
          row.cell(`$('Provisioning state'), item.provisioningState);
        });
      }" + $NEW_LINE;

    $code += "    });";

    return $code;