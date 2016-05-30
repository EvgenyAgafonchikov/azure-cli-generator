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
            $methodParamName = (Get-CliMethodMappedParameterName $methodParamName $methodParamIndex);
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
    for ($index = 0; $index -lt $methodParamNameList.Count; $index++)
    {
        # Parameter Declaration - For Each Method Parameter
        [string]$optionParamName = $methodParamNameList[$index];
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

function Get-PromptingOptionsCode($methodParamNameList)
{
	$result = "";
    for ($index = 0; $index -lt $methodParamNameList.Count; $index++)
    {
        [string]$optionParamName = $methodParamNameList[$index];
        [string]$cli_option_name = Get-CliOptionName $optionParamName;

        $cli_param_name = Get-CliNormalizedName $optionParamName;
        $result +=  "		${cli_param_name} = cli.interaction.promptIfNotGiven(`$('${cli_option_name} : '), ${cli_param_name}, _);" + $NEW_LINE;
    }
	return $result;
}

function Get-ParametersString($methodParamNameList)
{
	$str ="";
	for ($index = 0; $index -lt $methodParamNameList.Count; $index++)
	{
		# Function Call - For Each Method Parameter
		$cli_param_name = Get-CliNormalizedName $methodParamNameList[$index];
		$str += "${cli_param_name}";
		if ($index -lt $methodParamNameList.Count - 1)
		{
			$str+= ", ";
		}
	}
	return $str;
}