

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
        if (($paramType.Name -like "I*Operations") -or ($paramItem.Name -eq 'expand'))
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
    $mappedMethodName = Get-CliMethodMappedFunctionName $methodName;
    $cliMethodOption = Get-CliOptionName $mappedMethodName;

    # 3.2.4 Compute the CLI Command Description, i.e. VirtualMachineScaleSet => virtual machine scale set
    $cliOperationDescription = (Get-CliOptionName $OperationName).Replace('-', ' ');
    
	#
	# Category declaration
	#
    $code += "
	 var network = cli.category(`'network-autogen`')
       .description(`$('Commands to manage network resources'));

	";

    $code +=
	 "var $cliOperationName = network.category('${cliCategoryName}')
	   .description(`$('Commands to manage ${cliOperationDescription}'));
	 
	 ";

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

	#
	# Prompting options
	#
    for ($index = 0; $index -lt $methodParamNameList.Count; $index++)
    {
        [string]$optionParamName = $methodParamNameList[$index];
        [string]$cli_option_name = Get-CliOptionName $optionParamName;

        $cli_param_name = Get-CliNormalizedName $optionParamName;         
        $code +=  "         ${cli_param_name} = cli.interaction.promptIfNotGiven(`$('${cli_option_name} : '), ${cli_param_name}, _);" + $NEW_LINE;        
    }

    #
	# API call using SDK
	#
	$cliMethodFuncName = $cliMethodName;
    $code += "         
         var subscription = profile.current.getSubscription(options.subscription);
         var ${componentNameInLowerCase}ManagementClient = utils.create${componentName}ManagementClient(subscription);
		
         var progress = cli.interaction.progress(util.format(`$('Looking up the ${cliOperationDescription} `"%s`"'), name));
         var result = ${componentNameInLowerCase}ManagementClient.${cliOperationName}.${cliMethodFuncName}(";

    for ($index = 0; $index -lt $methodParamNameList.Count; $index++)
    {
        # Function Call - For Each Method Parameter
        $cli_param_name = Get-CliNormalizedName $methodParamNameList[$index];
        $code += "${cli_param_name}";
        $code += ", ";
    }
    $code += "_);";

	#
	# Print result to CLI
	#

	$code += " 
         progress.end();

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
    $code += "  });" + $NEW_LINE;


    return $code;