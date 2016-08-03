#
# Helpers.ps1
#
. "$PSScriptRoot\Import-StringFunction.ps1";
. "$PSScriptRoot\Import-TypeFunction.ps1";

function Get-ParametersNames($methodParameters)
{
    $methodParamIndex = 0;
    foreach ($paramItem in $methodParameters)
    {
        [System.Type]$paramType = $paramItem.ParameterType;
        if (($paramType.Name -like "I*Operations") -and ($paramItem.Name -eq 'operations'))
        {
            continue;
        }
        elseif($paramItem.Name -like "expand")
        {
            continue;
        }
        else
        {
            # Record the Normalized Parameter Name, i.e. 'vmName' => 'VMName', 'resourceGroup' => 'ResourceGroup', etc.
            $methodParamName = (Get-CamelCaseName $paramItem.Name);
            if($methodParamName -eq $currentOperationNormalizedName -or
               ($parents[$cliOperationName] -and $methodParamName -eq ((Get-SingularNoun $parents[$cliOperationName]) + "Name")) -or
               $methodParamName  -like "circuit*")
            {
                $methodParamName = Get-CommanderStyleOption $methodParamName;
            }
            else
            {
                $methodParamName = (Get-CliMethodMappedParameterName $methodParamName $methodParamIndex);
            }
            $methodParamNameList += $methodParamName;
            $methodParamTypeDict.Add($paramItem.Name, $paramType);
            $allStringFields = Contains-OnlyStringFields $paramType;
            $allStringFieldCheck.Add($paramItem.Name, $allStringFields);
            $oneStringList = Contains-OnlyStringList $paramType;
            $oneStringListCheck.Add($paramItem.Name, $oneStringList);

            if ($paramType.Namespace -like $ModelNameSpace)
            {
                # If the namespace is like 'Microsoft.Azure.Management.*.Models', generate commands for the complex parameter
                # 3.1.1 Create the Parameter Object, and convert it to JSON code text format
                $param_object = (. $PSScriptRoot\Create-ParameterObject.ps1 -typeInfo $paramType);
                $param_object_comment = (. $PSScriptRoot\ConvertTo-Json.ps1 -inputObject $param_object -compress $true);
                $param_object_comment_no_compress = (. $PSScriptRoot\ConvertTo-Json.ps1 -inputObject $param_object);
                
                # 3.1.2 Create a parameter tree that represents the complext object
                $cmdlet_tree = (. $PSScriptRoot\Create-ParameterTree.ps1 -TypeInfo $paramType -NameSpace $ModelNameSpace -ParameterName $paramType.Name);

                # 3.1.3 Generate the parameter command according to the parameter tree
                $cmdlet_tree_code = (. $PSScriptRoot\Generate-ParameterCommand.ps1 -CmdletTreeNode $cmdlet_tree -Operation $opShortName -ModelNameSpace $ModelNameSpace -MethodName $methodName -OutputFolder $FileOutputFolder);
            }
        }
        $methodParamIndex += 1;
    }
    [hashtable]$Return = @{};
    $Return.methodParamNameList = $methodParamNameList;
    $Return.methodParamTypeDict = $methodParamTypeDict;
    $Return.allStringFieldCheck = $allStringFieldCheck;
    return $Return;
}

function Update-RequiredParameters($methodParamNameList, $methodParamTypeDict, $allStringFieldCheck)
{
    $requireParams = @();
    $requireParamNormalizedNames = @()
    for ($index = 0; $index -lt $methodParamNameList.Count; $index++)
    {
        # Parameter Declaration - For Each Method Parameter
        [string]$optionParamName = $methodParamNameList[$index];
        if ($optionParamName -like "*parameters") {
            continue;
        }
        if ($allStringFieldCheck[$optionParamName])
        {
            [System.Type]$optionParamType = $methodParamTypeDict[$optionParamName];
            foreach ($propItem in $optionParamType.GetProperties())
            {
                [System.Reflection.PropertyInfo]$propInfoItem = $propItem;
                $cli_option_name = Get-CliOptionName $propInfoItem.Name;
                $requireParams += $cli_option_name;
                $requireParamNormalizedNames += (Get-CliNormalizedName $propInfoItem.Name);
            }
        }
        else
        {
            $cli_option_name = Get-CliOptionName $optionParamName;
            $requireParams += $cli_option_name;
            $requireParamNormalizedNames += (Get-CliNormalizedName $optionParamName);
        }
    }
    [hashtable]$Return = @{};
    $Return.requireParams = $requireParams;
    $Return.requireParamNormalizedNames = $requireParamNormalizedNames;
    return $Return;
}

function Get-PromptingOptionsCode($methodParamNameList, $functionArgsList, $parentItem, $spaceLength)
{
    $result = "";
    for ($index = 0; $index -lt $methodParamNameList.Count; $index++)
    {
        [string]$optionParamName = $methodParamNameList[$index];
        [string]$cli_option_name = Get-CliOptionName $optionParamName;
        $cli_option_name  = $cli_option_name -replace "parameters", "parameters-file (press enter to skip and use options)"

        $cli_param_name = Get-CliNormalizedName $optionParamName;
        $mappedParamName = Get-MappedParameterName $cli_param_name $OperationName $parents[$OperationName] $parentItem;
        $conditionStr = "";
        if($functionArgsList -contains "parameters")
        {
            $conditionStr += "!parameters";
        }
        if($cli_param_name -ne "parameters")
        {
            if($conditionStr -ne "")
            {
                $conditionStr += " && ";
            }
            $conditionStr += "!options.${mappedParamName}";
            $result += (" " * $spaceLength) + "if(${conditionStr}) {" + $NEW_LINE;
        } else
        {
            if ($conditionStr -ne "")
            {
                $result += (" " * $spaceLength) + "if(${conditionStr} && options.length < 1) {" + $NEW_LINE;
            }
        }
        $result += (" " * ($spaceLength + 2));
        if($functionArgsList -contains $cli_param_name)
        {
            $result += "${mappedParamName} = cli.interaction.promptIfNotGiven(`$('${cli_option_name} : '), ${mappedParamName}, _);" + $NEW_LINE;
        }
        else
        {
            $result += "options.${mappedParamName} = cli.interaction.promptIfNotGiven(`$('${cli_option_name} : '), options.${mappedParamName}, _);" + $NEW_LINE;
        }
        if ($conditionStr -ne "")
        {
            $result += (" " * $spaceLength) + "}" + $NEW_LINE;
        }
    }
    return $result;
}

function Get-MappedParameterName($parameterName, $OperationName, $paramParent, $parentShort)
{
    $replaceNameParam = ((Get-SingularNoun $OperationName) + "Name") -replace "ExpressRouteCircuit","";
    $replaceNameParam = ((Get-SingularNoun $OperationName) + "Name") -replace "ExpressRoute","";
    if($parameterName -eq $replaceNameParam)
    {
        return "name";
    }
    elseif($parameterName -eq "peeringName" -or $parameterName -eq "authorizationName")
    {
        return "name";
    }
    elseif($paramParent -and $parameterName -eq ((Get-SingularNoun $paramParent) + "Name"))
    {
        if($parentShort)
        {
            return "${parentShort}Name";
        }
        else
        {
            return (decapitalizeFirstLetter (Get-SingularNoun $paramParent)) + "Name";
        }
    }
    elseif($parameterName -eq "remoteVirtualNetworkId")
    {
        return "remoteVnetId";
    }
    elseif($parameterName -eq "gatewayIpAddress")
    {
        return "ipAddress";
    }
    elseif($parameterName -eq "subnetVirtualNetworkName" -and $OperationName -eq "VirtualNetworkGateways")
    {
        return "vnetName";
    }
    elseif($parameterName -eq "primaryPeerAddressPrefix")
    {
        return "primaryAddressPrefix";
    }
    elseif($parameterName -eq "secondaryPeerAddressPrefix")
    {
        return "secondaryAddressPrefix";
    }
    else
    {
        return $parameterName;
    }
}

function Get-ParametersString($methodParamNameList, $parentItem)
{
    $str ="";
    for ($index = 0; $index -lt $methodParamNameList.Count; $index++)
    {
        # Function Call - For Each Method Parameter
        $cli_param_name = Get-CliNormalizedName $methodParamNameList[$index];
        $cli_param_name = Get-MappedParameterName $cli_param_name $OperationName $parents[$OperationName] $parentItem;
        $str += "${cli_param_name}";
        if ($index -lt $methodParamNameList.Count - 1)
        {
            $str+= ", ";
        }
    }
    return $str;
}

function Get-SafeGetFunction($componentNameInLowerCase, $cliOperationName, $methodParamNameList, $resultVarName, $cliOperationDescription)
{
    $replaceNameParam = ((Get-SingularNoun $cliOperationName) + "Name") -replace "ExpressRouteCircuit","";
    $check = $methodParamNameList | Where-Object {$_ -eq $replaceNameParam}
    $nameVar = "name";
    if($check)
    {
        if($artificallyExtracted -notcontains $OperationName)
        {
            $methodParamNameList = $methodParamNameList -replace $check,"name";
        }
        else
        {
            $replacer = $operationMappings[$cliOperationName];
            $methodParamNameList = $methodParamNameList -replace $check,"${replacer}Name";
            $nameVar = "'in ' + ${replacer}Name";
        }
    }
    $tempCode = "
      var progress = cli.interaction.progress(util.format(`$('Looking up the ${cliOperationDescription} `"%s`"'), ${nameVar}));
      try {
        ${resultVarName} = ${componentNameInLowerCase}ManagementClient.${cliOperationName}.get("
    $tempCode += (Get-ParametersString $methodParamNameList $parentItem) -replace ", parameters", "";
    $tempCode += ", null, _);";

    $tempCode += "
      } catch (e) {
        if (e.statusCode === 404) {
          ${resultVarName} = null;
        } else {
          throw e;
        }
      } finally {
        progress.end();
      }";
    return $tempCode
}

function Get-CommonOptions($cliMethodOption) {
    $tempCode = "";
    if ($cliMethodOption.ToLower() -like "delete") {
        $tempCode += "    .option('-q, --quiet', `$('quiet mode, do not ask for delete confirmation'))" + $NEW_LINE;
    }
    $tempCode += "    .option('-s, --subscription <subscription>', `$('the subscription identifier'))" + $NEW_LINE;
    return $tempCode;
}

function Get-RequireParamsString($requireParams)
{
    if ($requireParams.Count -gt 0)
    {
        $requireParamsJoinStr = "] [";
        $requireParamsString = " [" + ([string]::Join($requireParamsJoinStr, $requireParams)) + "]";
        $requireParamsString = $requireParamsString -replace "parameters", "parameters-file";
        return $requireParamsString;
    }
    return "";
}

function Get-UsageParamsString($requireParams)
{
    if ($requireParams.Count -gt 0)
    {
        $usageParamsJoinStr = "> <";
        $usageParamsString = " <" + ([string]::Join($usageParamsJoinStr, $requireParams)) + ">";
        $usageParamsString = $usageParamsString -replace "parameters", "parameters-file";
        return $usageParamsString;
    }
    return "";
}

function Get-ParamsDefinition($inputParams)
{
    if ($inputParams.Count -gt 0)
    {
        $out = [string]::Join(",", $inputParams)
        $out = "var " + $out + ";"
        return $out
    }
    return "";
}

function IsSimpleType ($type)
{
    return ($type.IsPrimitive -or $type.FullName -eq "System.String");
}

function Search-TreeElement($path, $obj, $target) {
    $found = $false;
    foreach ($k in $obj.psobject.properties) {
        $simpleType = "";
        if ($k.Value -ne $null)
        {
            $simpleType = IsSimpleType $k.Value.GetType();
        }
        if ($k.Name -eq $target)
        {
            $value = $path + "." + $k.Name
            $type = $k.TypeNameOfValue; #Value.GetType();
            if ($value -notlike "*subnet*" -or ($value -notlike "*subnets*" -and $target -eq "subnet"))
            {
                return @{path = $value; type = $type};
            }
        }
        elseif ($k.Value -ne $null -and -not $simpleType) {
            $result = $null;
            if($k.Value.GetType() -like "*List*")
            {
                $currentPath = $path + "." + $k.Name + "[index]";
                $result = Search-TreeElement $currentPath $k.Value[0] $target;
            }
            else
            {
                $currentPath = $path + "." + $k.Name;
                $result = Search-TreeElement $currentPath $k.Value $target;
            }
            if ($result)
            {
                $pathVal = $result;
                $typeVal = $k.Value.GetType()
                if($result.GetType().Name -eq "Hashtable")
                {
                    $pathVal = $result.path
                    $typeVal = $result.type
                }
                if ($pathVal -notlike "*subnet*" -or ($pathVal -notlike "*subnets*" -and $target -eq "subnet"))
                {
                return @{path = $pathVal; type = $typeVal};
                }
            }
        }
    }
    return $false;
}

function decapitalizeFirstLetter($inStr)
{
    if ($inStr -ne "")
    {
        return $inStr.Substring(0,1).ToLower() + $inStr.Substring(1);
    }
    else
    {
        return $inStr;
    }
}

function Get-CommanderStyleOption($inStr)
{
    if ($inStr.Contains("IP"))
    {
        $inStr = $inStr -creplace "IP", "Ip";
    }
    elseif ($inStr.Contains("ASN"))
    {
        $inStr = $inStr -creplace "ASN", "Asn";
    }
    if($inStr -eq "expressRouteCircuit")
    {
        $inStr = $inStr -replace "expressRoute", "";
    }
    elseif($inStr -ne "circuitName")
    {
        $inStr = $inStr -replace "expressRouteCircuit", "";
    }

    return (decapitalizeFirstLetter $inStr);
}

function Get-WrappedAs($type, $inputString)
{
    if($type -eq "list")
    {
        return "('${inputString}').split(',')";
    }
    elseif($type -eq "string")
    {
        return "'${inputString}'";
    }
    elseif($type -eq "int")
    {
        return "parseInt('${inputString}', 10)";
    }
    elseif($type -eq "bool")
    {
        return "utils.parseBool('${inputString}')";
    }
    return "${inputString}"
}

function GetPlural($inStr)
{
    if ($inStr.toLower().EndsWith("address"))
    {
        return $inStr + "es";
    }
    else
    {
        return $inStr + "s";
    }
}

function Get-MappedOption($optionName, $opName, $parentNameOption, $parentItem)
{
    if($optionName -eq (((Get-CliOptionName (Get-SingularNoun $opName)) + "-name") -replace "express-route-circuit-",""))
    {
        $optionName = "name";
    }
    elseif($optionName -eq (((Get-CliOptionName (Get-SingularNoun $opName)) + "-name") -replace "express-route-",""))
    {
        $optionName = "name";
    }
    elseif($parentNameOption -and $optionName -eq (((Get-CliOptionName (Get-SingularNoun $parentNameOption)) + "-name") -replace "express-route-circuit-",""))
    {
        if($parentItem)
        {
            $optionName = "${parentItem}-name"
        }
    }
    return $optionName;
}

function Get-MappedOptionsArray($inArray, $opName, $parentNameInput, $parentShortnameOption)
{
    $replaceNameOption = ((Get-CliOptionName (Get-SingularNoun $opName)) + "-name") -replace "express-route-circuit-","";
    $replaceNameOption = ((Get-CliOptionName (Get-SingularNoun $opName)) + "-name") -replace "express-route-","";
    $checkOption = $inArray | Where-Object {$_ -eq $replaceNameOption};
    $checkParent = $null;
    if($parentNameInput)
    {
        $replaceNameParentOption = ((Get-CliOptionName (Get-SingularNoun $parentNameInput)) + "-name") -replace "express-route-circuit-","";
        $replaceNameParentOption = ((Get-CliOptionName (Get-SingularNoun $parentNameInput)) + "-name") -replace "express-route-","";
        $checkParentOption = $inArray | Where-Object {$_ -eq $replaceNameParentOption};
    }
    if($checkOption)
    {
        $inArray = $inArray -replace $checkOption,"name";
    }
    if($checkParentOption)
    {
        if($parentShortnameOption)
        {
            $parentShortnameOption = Get-CliOptionName (Get-SingularNoun $parentShortnameOption);
            $inArray = $inArray -replace $checkParentOption,"${parentShortnameOption}-name";
        }
    }
    if($inArray -contains "authorization-name")
    {
        $inArray = $inArray -replace "authorization-name","name";
    }
    if($inArray -contains "peering-name")
    {
        $inArray = $inArray -replace "peering-name","name";
    }
    return $inArray;
}

function Get-MappedParametersArray($inArray, $opName, $parentNameInput, $parentShortname)
{
    $replaceNameParam = ((Get-SingularNoun $opName) + "Name") -replace "ExpressRouteCircuit","";
    $replaceNameParam = ((Get-SingularNoun $opName) + "Name") -replace "ExpressRoute","";
    $check = $inArray | Where-Object {$_ -eq $replaceNameParam};
    $checkParent = $null;
    if($parentNameInput)
    {
        $replaceNameParent = ((Get-SingularNoun $parentNameInput) + "Name") -replace "ExpressRouteCircuit","";
        $replaceNameParam = ((Get-SingularNoun $opName) + "Name") -replace "ExpressRoute","";
        $checkParent = $inArray | Where-Object {$_ -eq $replaceNameParent};
    }
    if($check)
    {
        $inArray = $inArray -replace $check,"name";
    }
    if($checkParent)
    {
        if($parentShortname)
        {
            $inArray = $inArray -replace $checkParent,"${parentShortname}Name";
        }
    }
    if($inArray -contains "authorizationName")
    {
        $inArray = $inArray -replace "authorizationName","name";
    }
    if($inArray -contains "peeringName")
    {
        $inArray = $inArray -replace "peeringName","name";
    }
    return $inArray;
}

function Get-CustomMapping($inputStr)
{
    if($inputStr -eq "VirtualNetworkName")
    {
        return "VnetName";
    }
    else
    {
        return $inputStr;
    }
}