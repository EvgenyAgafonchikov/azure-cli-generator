#
# CommonVars.ps1
#

. "$PSScriptRoot\Import-StringFunction.ps1";
. "$PSScriptRoot\Helpers.ps1";

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

    # 3.2 Functions
    # 3.2.1 Compute the CLI Category Name, i.e. VirtualMachineScaleSet => vmss, VirtualMachineScaleSetVM => vmssvm
    $cliCategoryName = Get-CliCategoryName $OperationName;
    # 3.2.2 Compute the CLI Operation Name, i.e. VirtualMachineScaleSets => virtualMachineScaleSets, VirtualMachineScaleSetVM => virtualMachineScaleSetVMs
    $cliOperationName = Get-CliNormalizedName $OperationName;
    $currentOperationNormalizedName = (Get-CommanderStyleOption (Get-SingularNoun $cliOperationName)) + "Name";

    # 3. CLI Code
    # 3.1 Types
    $params = Get-ParametersNames $methodParameters;
    $methodParamNameList = $params.methodParamNameList;
    $methodParamTypeDict = $params.methodParamTypeDict;
    $allStringFieldCheck = $params.allStringFieldCheck;

    # 3.2.3 Normalize the CLI Method Name, i.e. CreateOrUpdate => createOrUpdate, ListAll => listAll
    $cliMethodName = Get-CliNormalizedName $methodName;
    $cliCategoryVarName = $cliOperationName + $methodName;
    $mappedMethodName = Get-CliMethodMappedFunctionName $methodName;
    $cliMethodOption = Get-CliOptionName $mappedMethodName;

    # 3.2.4 Compute the CLI Command Description, i.e. VirtualMachineScaleSet => virtual machine scale set
    $cliOperationDescription = (Get-CliOptionName $OperationName).Replace('-', ' ');
    if ($cliMethodOption -notlike "list")
    {
        $cliOperationDescription = Get-SingularNoun $cliOperationDescription;
    }
