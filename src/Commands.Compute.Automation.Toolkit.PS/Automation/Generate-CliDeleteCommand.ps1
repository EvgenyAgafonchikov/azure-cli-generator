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

. "$PSScriptRoot\CommonVars.ps1";
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
    $methodParamNameListExtended = $methodParamNameList;
    [array]$requiredAddons = ($cliOperationParamsRaw[$OperationName] | Where-Object { $_.isChildName -eq $true}).name
    if($requiredAddons)
    {
        for ($i = 0; $i -lt $requiredAddons.Length; $i++)
        {
            $requiredAddons[$i] = Get-CommanderStyleOption $requiredAddons[$i];
        }
        $methodParamNameListExtended += $requiredAddons ;
    }
    $require = Update-RequiredParameters $methodParamNameListExtended $methodParamTypeDict $allStringFieldCheck;
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
    $cmdOptions = "";
    for ($index = 0; $index -lt $methodParamNameListExtended.Count; $index++)
    {
        [string]$optionParamName = $methodParamNameListExtended[$index];
        $optionShorthandStr = $null;

        $cli_option_name = Get-CliOptionName $optionParamName;
        $cli_shorthand_str = (Get-CliShorthandName $optionParamName $currentOperationNormalizedName @()).name;
        if ($cli_shorthand_str -ne '')
        {
            $cli_shorthand_str = "-" + $cli_shorthand_str + ", ";
        }
        $cli_option_help_text = "the ${cli_option_name} of ${cliOperationDescription}";
        $cmdOptions += "    .option('${cli_shorthand_str}--${cli_option_name} <${cli_option_name}>', `$('${cli_option_help_text}'))" + $NEW_LINE;
        $option_str_items += "--${cli_option_name} `$p${index}";
    }

    $commonOptions = Get-CommonOptions $cliMethodOption
    # Prompting options
    $promptingOptions = Get-PromptingOptionsCode $methodParamNameListExtended $methodParamNameListExtended 6;

    #
    # API call using SDK
    #
    $cliMethodFuncName = $cliMethodName;
    if ($cliMethodFuncName -eq "delete")
    {
        $cliMethodFuncName += "Method";
    }
    $resultVarName = "result";
    $childResultVarName = "childResult";
    $template = "";
    if($artificallyExtracted -contains $OperationName)
    {
        $artificalOperation = $artificalOperations | Where-Object { $_.Name -eq $OperationName };
        $artificalOperationParent = GetPlural $artificalOperation.parent;
        $safeGet = Get-SafeGetFunction $componentNameInLowerCase $artificalOperationParent $methodParamNameList $resultVarName $cliOperationDescription;
        $template = Get-Content "$PSScriptRoot\templates\delete_child.ps1" -raw;
    }
    else
    {
        $safeGet = Get-SafeGetFunction $componentNameInLowerCase $cliOperationName $methodParamNameList $resultVarName $cliOperationDescription;
        $template = Get-Content "$PSScriptRoot\templates\delete.ps1" -raw;
    }

    $parametersString = Get-ParametersString $methodParamNameList;
    $code += Invoke-Expression $template;
    return $code;