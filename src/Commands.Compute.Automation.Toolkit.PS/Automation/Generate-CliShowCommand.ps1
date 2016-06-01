

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

    # Set Required Parameters
    $requireParams = @();
    $requireParamNormalizedNames = @();
	$require = Update-RequiredParameters $methodParamNameList $methodParamTypeDict $allStringFieldCheck;
	$requireParams = $require.requireParams;
	$requireParamNormalizedNames = $require.requireParamNormalizedNames;

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

	#
	# Command declaration
	#
    $code += 
	"${cliOperationName}.command('${cliMethodOption}${requireParamsString}')
	   .description(`$('Get a ${cliOperationDescription}'))
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
        $code += "       .option('${cli_shorthand_str}--${cli_option_name} <${cli_option_name}>', `$('${cli_option_help_text}'))" + $NEW_LINE;
        $option_str_items += "--${cli_option_name} `$p${index}";
    }

    $code += "       .option('-s, --subscription <subscription>', `$('the subscription identifier'))" + $NEW_LINE;
    $code += "       .execute(function(${optionParamString}options, _) {" + $NEW_LINE;

	# Prompting options
	$code += Get-PromptingOptionsCode $methodParamNameList;

    #
	# API call using SDK
	#
	$cliMethodFuncName = $cliMethodName;
    $code += "
         var subscription = profile.current.getSubscription(options.subscription);
         var ${componentNameInLowerCase}ManagementClient = utils.create${componentName}ManagementClient(subscription);

         var progress = cli.interaction.progress(util.format(`$('Looking up the ${cliOperationDescription} `"%s`"'), name));
         var result;"

$code +=
	"
    try {
      result = ${componentNameInLowerCase}ManagementClient.${cliOperationName}.${cliMethodFuncName}("
	$code += Get-ParametersString $methodParamNameList;
    $code += ", null, _);";

	$code+= "
    } catch (e) {
      if (e.statusCode === 404) {
		progress.end();
        cli.output.warn(util.format(`$('A public ip address with name `"%s`" not found in the resource group `"%s`"'), name, resourceGroup));
        return;
      }
      throw e;
    } finally {
      progress.end();
    }";

	#
	# Print publicIp to CLI
	#
	$code += "
         cli.interaction.formatOutput(result, function (result) {
		   for (var property in result) {
		     if (result.hasOwnProperty(property)) {
			   cli.output.nameValue(property, result[property]);
		     }
		   }
         });
    ";

    #
	# End of command declaration
	#
    $code += "  });";


    return $code;