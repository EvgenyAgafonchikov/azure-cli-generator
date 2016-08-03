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
    $resourceGroupInit = "";
    if($OperationName -ne "usages" -and $OperationName -ne "ExpressRouteServiceProviders")
    {
        $resourceGroupInit = "      options.resourceGroup = resourceGroup;" + $NEW_LINE;
    }
    # Set Required Parameters
    $requireParams = @();
    $requireParamNormalizedNames = @();

    $methodParamNameListExtended = $methodParamNameList;
    if($artificallyExtracted -contains $OperationName)
    {
        $methodParamNameListExtended += ((Get-SingularNoun $parents[$OperationName]) + "Name");
        $optionParamString += ($parents[$OperationName] + "Name, ")
    }
    $require = Update-RequiredParameters $methodParamNameListExtended $methodParamTypeDict $allStringFieldCheck;
    $requireParams = $require.requireParams;
    $requireParamNormalizedNames = $require.requireParamNormalizedNames;
    $parentItem = $null;
    if($parents[$OperationName])
    {
        if($operationMappings[$parents[$OperationName]])
        {
            $parentItem = $operationMappings[$parents[$OperationName]];
        }
    }
    $requireParams = Get-MappedOptionsArray $requireParams $OperationName $parents[$OperationName] $parentItem ;
    $requireParamNormalizedNames = Get-MappedParametersArray $requireParamNormalizedNames $OperationName $parents[$OperationName] $parentItem;

    $requireParamsString = $null;
    $usageParamsString = $null;
    $optionParamString = $null;
    $requireParamsString = Get-RequireParamsString $requireParams;
    $usageParamsString = Get-UsageParamsString $requireParams;
    if ($requireParamNormalizedNames.Length)
    {
        $optionParamString = ([string]::Join(", ", $requireParamNormalizedNames)) + ", ";
    }
    else
    {
        $optionParamString  = "";
    }

    #
    # Options declaration
    #
    $option_str_items = @();
    $use_input_parameter_file = $false;
    $cmdOptions = "";
    for ($index = 0; $index -lt $methodParamNameListExtended.Count; $index++)
    {
        [string]$optionParamName = $methodParamNameListExtended[$index];
        $optionShorthandStr = $null;

        $cli_option_name = Get-CliOptionName $optionParamName;
        $cli_shorthand_str = (Get-CliShorthandName $optionParamName "" @()).name;
        if ($cli_shorthand_str -ne '')
        {
            $cli_shorthand_str = "-" + $cli_shorthand_str + ", ";
        }
        $cli_option_help_text = "the ${cli_option_name} of ${cliOperationDescription}";
        $cli_option_name = Get-MappedOption $cli_option_name $OperationName $parents[$OperationName] $parentItem;
        $cmdOptions += "    .option('${cli_shorthand_str}--${cli_option_name} <${cli_option_name}>', `$('${cli_option_help_text}'))" + $NEW_LINE;
        $option_str_items += "--${cli_option_name} `$p${index}";
    }

    $commonOptions = Get-CommonOptions $cliMethodOption

    #
    # API call using SDK
    #
    $cliMethodFuncName = $cliMethodName;
    $resultVarName = "result";

    $promptingCode = Get-PromptingOptionsCode $methodParamNameList $methodParamNameList $parentItem 12;
    $methodParamNameListNoRes = $methodParamNameList -ne "resourceGroup";
    $promptingCodeNoResource = Get-PromptingOptionsCode $methodParamNameListNoRes $methodParamNameListNoRes $parentItem 12;
    if($artificallyExtracted -contains $OperationName)
    {
        $artificalOperation = $artificalOperations | Where-Object { $_.Name -eq $OperationName };
        $methodParamNameListExtendedOptions = $methodParamNameList;
        $methodParamNameListExtendedOptions += ("options." + $parents[$OperationName] + "Name");
        $artificalOperationCliName = Get-CommanderStyleOption $artificalOperation.parent;
        $safeGet = Get-SafeGetFunction $componentNameInLowerCase $artificalOperationCliName $methodParamNameListExtended $resultVarName $cliOperationDescription;
        $promptParentCode = Get-PromptingOptionsCode $methodParamNameListExtended $methodParamNameListExtended $parentItem 6;
        $template = Get-Content "$PSScriptRoot\templates\list_child.ps1" -raw;
    }
    else
    {
        $template = Get-Content "$PSScriptRoot\templates\list.ps1" -raw;
    }
    $code += Invoke-Expression $template;
    return $code;
