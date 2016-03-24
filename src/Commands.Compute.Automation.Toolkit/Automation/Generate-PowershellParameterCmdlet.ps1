# ----------------------------------------------------------------------------------
#
# Copyright Microsoft Corporation
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# http://www.apache.org/licenses/LICENSE-2.0
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ----------------------------------------------------------------------------------

param(
    [Parameter(Mandatory = $true)]
    [string]$OutputFolder,

    [Parameter(Mandatory = $true)]
    $TreeNode,

    [Parameter(Mandatory = $true)]
    $Parameters,

    [Parameter(Mandatory = $true)]
    [string]$ModelNameSpace,

    # VirtualMachine, VirtualMachineScaleSet, etc.
    [Parameter(Mandatory = $true)]
    [string]$ObjectName,

    [Parameter(Mandatory = $true)]
    $TypeBinding
)

function Does-Contain
{
    param(
        [Parameter(Mandatory = $True)]
        $arrayOfArray,
        [Parameter(Mandatory = $True)]
        $element
    )

    foreach($a in $arrayOfArray)
    {
        $check = Compare-Object -ReferenceObject $a -DifferenceObject $element

        if ($check -eq $null)
        {
            return $True;
        }
    }

    return $false;
}

function Get-ParameterChainSet
{

    param(
        [Parameter(Mandatory = $True)]
        $parameters
    )

    $chainSet = @();
    foreach ($p in $parameters)
    {
        if (-not [System.String]::IsNullOrEmpty($p["Chain"]))
        {
            if (-not (Does-Contain $chainSet $p["Chain"]))
            {
                $chainSet += , $p["Chain"];
            }
        }
    }
    return ,$chainSet;
}

function Get-ArrayType
{
    param(
        [Parameter(Mandatory = $True)]
        [string] $type
    )

    if ($type.StartsWith("Array:"))
    {
        $type = $type.Replace("Array:", "") + " []";
    }
    if ($type.StartsWith("IList<"))
    {
        $type = $type.Replace("IList<", "").Replace(">", "") + " []";
    }
    return $type;
}

function Get-ListType
{
    param(
        [Parameter(Mandatory = $True)]
        [string] $type
    )

    if ($type.StartsWith("Array:"))
    {
        $type = $type.Replace("Array:", "List<") + ">";
    }
    if ($type.StartsWith("IList<"))
    {
        $type = $type.Replace("IList<", "List<") + ">";
    }
    return $type;
}

function Is-ValueType
{
    param(
        [Parameter(Mandatory = $True)]
        [string] $type
    )

    if ($type.Equals("bool"))
    {
        return $True;
    }
    if ($type.Contains("int") -and (-not $type.EndsWith("?")))
    {
        return $True;
    }
    return $false;
}

function Is-DictionaryType
{
    param(
        [Parameter(Mandatory = $True)]
        [string] $type
    )

    if ($type.StartsWith("IDictionary") -or $type.StartsWith("Dictionary"))
    {
        $start = $type.IndexOf("<")+1;
        $end = $type.IndexOf(">");
        return $type.Substring($start, $end-$start);
    }
    return $null;
}

function Get-AssignCode
{
    param(
        [Parameter(Mandatory = $True)]
        $parameter,
        [Parameter(Mandatory = $false)]
        $nullCheck = $True
    )

    $dic = Is-DictionaryType $parameter["Type"];
    $property_name = $parameter["Name"];
    if ($dic -eq $null)
    {
        $assign_code = "this." + $property_name;
    }
    else
    {
        $key_value_pair_type = $dic.Split(",");
        $assign_code = "this.${property_name}.Cast<DictionaryEntry>().ToDictionary(ht => (" + $key_value_pair_type[0]+ ")ht.Key, ht => (" + $key_value_pair_type[1]+ ")ht.Value)";
        if ($nullCheck)
        {
            $assign_code = "(this.${property_name} == null) ? null : " + $assign_code;
        }
    }
    return $assign_code;
}


function Get-SingleType
{
    param(
        [Parameter(Mandatory = $True)]
        [string] $type
    )

    if ($type.StartsWith("Array:"))
    {
        $type = $type.Replace("Array:", "");
    }
    if ($type.StartsWith("IList<"))
    {
        $type = $type.Replace("IList<", "").Replace(">", "");
    }
    return $type;
}


function Get-SortedUsings
{
    param(
        [Parameter(Mandatory = $True)]
        $usings_array
    )

    $sorted_usings = $usings_array | Sort-Object -Unique | foreach { "using ${_};" };

    $text = [string]::Join($NEW_LINE, $sorted_usings);

    return $text;
}

function Get-SimpleNoun
{
    param(
        [Parameter(Mandatory = $True)]
        [string] $noun
    )
    if ($noun.Equals("VirtualMachineScaleSet"))
    {
        return "Vmss";
    }
    else
    {
        return $noun;
    }
}

function Get-ArrayParent
{
    param(
        [Parameter(Mandatory = $True)]
        $chain
    )

    if ($chain -eq $null)
    {
        return "";
    }
    $result = "";
    for ($i = $chain.Length - 1; $i -ge 0 ; $i--)
    {
        $c = $chain[$i];
        if ($i -eq $chain.Length - 1)
        {
            $result = $c;
        }
        else
        {
            $result = $c + "." + $result;
        }

        $t = $TypeBinding[$c];

        if ($t.ToString().StartsWith("Array:"))
        {
            return $result;
        }
    }
    return "";
}

function Get-ParameterCode
{
    param(
        [Parameter(Mandatory = $True)]
        $parameter,

        [Parameter(Mandatory = $True)]
        [int] $index,

        [Parameter(Mandatory = $false)]
        [bool] $make_null = $false,

        [Parameter(Mandatory = $false)]
        [bool] $mandatory = $false
    )

    $p_type = Get-ArrayType $parameter["Type"];

    if ($make_null -and (Is-ValueType $p_type))
    {
        $p_type += "?";
    }
    if ((Is-DictionaryType $p_type) -ne $null)
    {
        $p_type = "Hashtable";
    }

    $p_name = $parameter["Name"];
    $is_mandatory = $mandatory.ToString().ToLower();

    $return_code =
@"

        [Parameter(
            Mandatory = $is_mandatory,
            Position = $index,
            ValueFromPipelineByPropertyName = true)]
        public $p_type $p_name { get; set; }

"@;

    return $return_code;
}

function Get-PropertyFromChain
{
    param(
        [Parameter(Mandatory = $True)]
        $array
    )

    $result = $array[0];

    for ($i = 1; $i -lt $array.Count ; $i++)
    {
        $result += "." + $array[$i];
    }

    return $result;
}

function Get-VariableName
{
    param(
        [Parameter(Mandatory = $True)]
        $array
    )

    $result = "v" + (Get-PropertyFromChain $array);
    return $result;
}

function Get-NewObjectCode
{
    param(
        [Parameter(Mandatory = $True)]
        $chain,

        [Parameter(Mandatory = $false)]
        [int] $left_space  = 0
    )

    $return_string = "`r`n";
    $new_obj = ${ObjectName};

    for ($i = 0; $i -lt $chain.Count; $i++)
    {
        $c = $chain[$i];
        $new_obj += "." + $c;
        $single_type = Get-SingleType $TypeBinding[$c];
        $type = Get-ListType $TypeBinding[$c];

        $left_pad = " " * $left_space;
        $left_deep_pad = " " * ($left_space + 4);
        $right_pad = "`r`n";

        $return_string += $left_pad + "// ${c}" + $right_pad;
        $return_string += $left_pad + "if (this.${new_obj} == null)" + $right_pad;
        $return_string += $left_pad + "{" + $right_pad;
        $return_string += $left_deep_pad + "this.${new_obj} = new ${type}();" + $right_pad;
        $return_string += $left_pad + "}" + $right_pad;
    }
    return $return_string;
}

function Write-PowershellCmdlet
{
    param(
    [Parameter(Mandatory = $true)]
    [string]$cmdlet_verb,

    [Parameter(Mandatory = $true)]
    [string]$OutputFolder,

    [Parameter(Mandatory = $true)]
    $TreeNode,

    [Parameter(Mandatory = $true)]
    $Parameters,

    [Parameter(Mandatory = $true)]
    [string]$ModelNameSpace,

    # VirtualMachine, VirtualMachineScaleSet, etc.
    [Parameter(Mandatory = $true)]
    [string]$ObjectName,

    [Parameter(Mandatory = $true)]
    $TypeBinding
    )

    $library_namespace = $ModelNameSpace.Substring(0, $ModelNameSpace.LastIndexOf('.'));

    $ps_cmdlet_namespace = ($library_namespace.Replace('.Management.', '.Commands.'));
    $ps_generated_cmdlet_namespace = $ps_cmdlet_namespace + '.Automation';
    $ps_generated_model_namespace = $ps_cmdlet_namespace + '.Automation.Models';
    $ps_common_namespace = $ps_cmdlet_namespace.Substring(0, $ps_cmdlet_namespace.LastIndexOf('.'));

    $parameter_cmdlet_usings = @(
        'System',
        'System.Collections',
        'System.Collections.Generic',
        'System.Linq',
        'System.Management.Automation'
        );

    $parameter_cmdlet_usings += $ModelNameSpace;

    $cmdlet_noun = "AzureRm";
    $cmdlet_noun += Get-SimpleNoun $ObjectName;

    if ($TreeNode.Name -ne ${ObjectName})
    {
        $cmdlet_noun += Get-SingularNoun $TreeNode.Name;
    }

    if ($cmdlet_verb.Equals("New"))
    {
        if ($cmdlet_noun.EndsWith("Configuration"))
        {
            $cmdlet_noun = $cmdlet_noun.Replace("Configuration", "Config");
        }
        else
        {
            $cmdlet_noun += "Config";
        }
    }

    if (($cmdlet_verb.Equals("Add") -or $cmdlet_verb.Equals("Remove")) -and $cmdlet_noun.EndsWith('s'))
    {
        $cmdlet_noun = $cmdlet_noun.Substring(0, $cmdlet_noun.Length - 1);
    }

    $cmdlet_noun = Get-PowershellNoun $objectName $cmdlet_noun;
    $cmdlet_class_name = $cmdlet_verb + $cmdlet_noun + "Command";
    $cmdlet_class_code =
@"

namespace ${ps_generated_cmdlet_namespace}
{
    [Cmdlet(`"${cmdlet_verb}`", `"${cmdlet_noun}`")]
    [OutputType(typeof(${ObjectName}))]
    public class $cmdlet_class_name : $ps_common_namespace.ResourceManager.Common.AzureRMCmdlet
    {
"@;

    if ($cmdlet_verb.Equals("New"))
    {
        for($i = 0; $i -lt $Parameters.Count ; $i++)
        {
            $cmdlet_class_code += Get-ParameterCode $Parameters[$i] $i;
        }
    }
    else
    {
        $cmdlet_class_code +=
@"

        [Parameter(
            Mandatory = true,
            Position = 0,
            ValueFromPipeline = true,
            ValueFromPipelineByPropertyName = true)]
        public ${ObjectName} ${ObjectName} { get; set; }

"@;


        for($i = 0; $i -lt $Parameters.Count ; $i++)
        {
            $j = $i + 1;
            if ($cmdlet_verb.Equals("Remove"))
            {
                if ($Parameters[$i].Name -eq "Name")
                {
                    $cmdlet_class_code += Get-ParameterCode $Parameters[$i] $j $true $true;
                }
                else
                {
                    Write-Verbose("Skipping this parameter for Remove: " + $Parameters[$i].Name);
                }
            }
            else
            {
                $cmdlet_class_code += Get-ParameterCode $Parameters[$i] $j;
            }
        }
    }

    if ($TreeNode -eq $null)
    {
        return $null;
    }

    $chain_set = (Get-ParameterChainSet $Parameters);
    $object_list = @();
    $cmdlet_complex_parameter_code = "";
    $cmdlet_new_object_code = "";
    $cmdlet_new_single_object_code = @{};
    $cmdlet_add_single_object_code = @{};
    $cmdlet_code_add_body = "";


    if ($cmdlet_verb.Equals("New") -and ($TreeNode.Name -eq ${ObjectName}))
    {
        foreach($chain in $chain_set)
        {
            $new_obj = $chain[0];
            $var_name = "v" + $new_obj;

            if(-not $object_list.Contains($new_obj))
            {
                $object_list += $new_obj;
                $type = $TypeBinding[$new_obj];

                $cmdlet_new_object_code +=
@"

            // ${new_obj}
            var ${var_name} = new ${type}();

"@;

                $cmdlet_complex_parameter_code +=
@"

                ${new_obj} = ${var_name},
"@;
            }


            for ($i = 1; $i -lt $chain.Count; $i++)
            {
                $c = $chain[$i];

                $new_obj += "." + $c;
                $var_name = "v" + $new_obj;

                if(-not $object_list.Contains($new_obj))
                {
                    $object_list += $new_obj;
                    $type = $TypeBinding[$c];

                    $cmdlet_new_object_code +=
@"

            // ${c}
            ${var_name} = new ${type}();

"@;
                }
            }
        }
    }
    elseif ($cmdlet_verb.Equals("New"))
    {
        foreach($chain in $chain_set)
        {
            $is_parent_list = $null;

            $start = $false;

            for ($i = 0; $i -lt $chain.Count; $i++)
            {
                $c = $chain[$i];
                Write-Verbose ("Chain["+$i + "]: " + $c);

                if ($c -eq $TreeNode.Name)
                {
                    $start = $True;
                    $new_obj = "";
                }

                if ($start)
                {
                    $new_obj += "." + $c;

                    if(-not $object_list.Contains($new_obj))
                    {
                        $object_list += $new_obj;
                        $single_type = Get-SingleType $TypeBinding[$c];
                        $type = Get-ListType $TypeBinding[$c];

                        if ($is_parent_list -ne $null)
                        {
                            $cmdlet_code_add_body +=
@"

            // ${c}
            v${is_parent_list}.${c} = new ${type}();

"@;

                        }

                        if ($TypeBinding[$c].ToString().StartsWith("Array:"))
                        {
                            $new_code = "var v${c} = new ${single_type}();";

                            $cmdlet_new_single_object_code.Add($c, $new_code);
                        }

                    }

                    if ($TypeBinding[$c].ToString().StartsWith("Array:"))
                    {
                        $is_parent_list = $c;
                    }

                }
            }
        }
    }
    elseif ($cmdlet_verb.Equals("Remove"))
    {
        $remove_object = $null;
        foreach($chain in $chain_set)
        {
            $new_obj = $chain[0];
            $is_parent_list = $null;

            for ($i = 0; $i -lt $chain.Count; $i++)
            {
                if ($remove_object -eq $null)
                {

                    $c = $chain[$i];
                    $array_parent = Get-ArrayParent $chain;

                    if ($i -ne 0)
                    {
                        $new_obj += "." + $c;
                    }

                    if(-not $object_list.Contains($new_obj))
                    {
                        $object_list += $new_obj;
                        $single_type = Get-SingleType $TypeBinding[$c];
                        $type = Get-ListType $TypeBinding[$c];

                        $cmdlet_new_object_code +=
@"

            // ${c}
            if (this.${ObjectName}.${new_obj} == null)
            {
                WriteObject(this.${ObjectName});
                return;
            }

"@;
                    }

                    if ($TypeBinding[$c].ToString().StartsWith("Array:"))
                    {
                        $is_parent_list = $c;
                    }

                    if ($TypeBinding[$c].ToString().StartsWith("Array:") -and $array_parent.StartsWith(${c}))
                    {
                        $cmdlet_new_object_code +=
@"
            var v${c} = this.${ObjectName}.${new_obj}.First
                (e =>
"@;

                        $cmdlet_remove_object_code =
@"
            if (v${c} != null)
            {
                this.${ObjectName}.${new_obj}.Remove(v${c});
            }

            if (this.${ObjectName}.${new_obj}.Count == 0)
            {
                this.${ObjectName}.${new_obj} = null;
            }
"@;
                        $remove_object = $c;
                    }
                }
            }
        }
    }
    elseif ($cmdlet_verb.Equals("Add"))
    {
    # Set,Add
        foreach($chain in $chain_set)
        {
            $new_obj = $chain[0];
            $is_parent_list = $null;

            for ($i = 0; $i -lt $chain.Count; $i++)
            {
                $c = $chain[$i];

                if ($i -ne 0)
                {
                    $new_obj += "." + $c;
                }

                if(-not $object_list.Contains($new_obj))
                {
                    $object_list += $new_obj;
                    $single_type = Get-SingleType $TypeBinding[$c];
                    $type = Get-ListType $TypeBinding[$c];

                    if ($is_parent_list -ne $null)
                    {
                        $cmdlet_code_add_body +=
@"

            // ${c}
            v${is_parent_list}.${c} = new ${type}();

"@;

                    }
                    else
                    {
                        $cmdlet_new_object_code +=
@"

            // ${c}
            if (this.${ObjectName}.${new_obj} == null)
            {
                this.${ObjectName}.${new_obj} = new ${type}();
            }

"@;
                    }

                    if ($TypeBinding[$c].ToString().StartsWith("Array:"))
                    {
                        $new_code = "var v${c} = new ${single_type}();";

                        if ($is_parent_list -eq $null)
                        {
                            $add_code = "this.${ObjectName}.${new_obj}.Add(v${c});";
                        }
                        else
                        {
                            $add_code = "v${is_parent_list}.${c}.Add(v${c});";
                        }

                        $cmdlet_new_single_object_code.Add($c, $new_code);
                        $cmdlet_add_single_object_code.Add($c, $add_code);
                    }
                }

                if ($TypeBinding[$c].ToString().StartsWith("Array:"))
                {
                    $is_parent_list = $c;
                }
            }
        }
    }

    #
    # New config cmdlet
    #
    if ($cmdlet_verb.Equals("New") -and ($TreeNode.Name -eq ${ObjectName}))
    {
        $cmdlet_code_body =
@"
        protected override void ProcessRecord()
        {
"@;

        $cmdlet_code_body += $cmdlet_new_object_code;

        foreach($p in $Parameters)
        {
            if (-not [System.String]::IsNullOrEmpty($p["Chain"]))
            {
                $var_name = Get-VariableName $p["Chain"];
                $property = $p["OriginalName"];
                $thisProperty = $p["Name"];
                $assign = Get-AssignCode $p;

                $cmdlet_code_body +=
@"
            ${var_name}.${property} = ${assign};

"@;
            }
        }

        $cmdlet_code_body +=
@"

            var v${ObjectName} = new ${ObjectName}
            {
"@;

        foreach($p in $Parameters)
        {
            if ([System.String]::IsNullOrEmpty($p["Chain"]))
            {
                $property = $p["OriginalName"];
                $thisProperty = $p["Name"];
                $assign = Get-AssignCode $p;

                $cmdlet_code_body +=
@"

                ${property} = ${assign},
"@;
            }
        }

        $cmdlet_code_body += $cmdlet_complex_parameter_code;
        $cmdlet_code_body +=
@"

            };

            WriteObject(v${ObjectName});
        }
    }
}

"@;
    }
    elseif ($cmdlet_verb.Equals("New"))
    {
        $cmdlet_code_body =
@"
        protected override void ProcessRecord()
        {
"@;
        $cmdlet_code_body += $cmdlet_new_object_code;

        foreach($p in $Parameters)
        {
            $chain = $p["Chain"];
            $var_name = $chain[$chain.Length - 1];
            $type = $TypeBinding[$var_name];
            $single_type = $type.ToString().Replace("Array:", "");

            if (-not [System.String]::IsNullOrEmpty($p["Chain"]))
            {
                $property = $p["OriginalName"];
                $thisProperty = $p["Name"];
                $thisType = $p["Type"];
                $array_parent = Get-ArrayParent $chain;
                $assign = Get-AssignCode $p;

                if ($thisType.ToString().StartsWith("Array:") -and ($array_parent -ne $TreeNode.Name))
                {
                    $new_code = $cmdlet_new_single_object_code[$array_parent];
                    $cmdlet_new_single_object_code.Remove($array_parent);
                    $cmdlet_add_single_object_code.Remove($array_parent);

                    $var_name = $chain[$chain.Length - 2] + "." + ${var_name};
                    $cmdlet_code_add_body +=
@"

            if (this.${thisProperty} != null)
            {
                foreach (var element in this.${thisProperty})
                {
                    ${new_code}
                    v${array_parent}.${property} = element;
                }
            }

"@;
                }
                else
                {
                    $cmdlet_code_add_body +=
@"

            v${array_parent}.${property} = ${assign};
"@;
                }
            }
        }

        foreach ($key in $cmdlet_new_single_object_code.Keys)
        {
            $new_code = $cmdlet_new_single_object_code[$key];
            $cmdlet_code_body +=
@"

            ${new_code}

"@;
        }

        $cmdlet_code_body += $cmdlet_code_add_body;

        $write_object = "v" + $TreeNode.Name;

        $cmdlet_code_body +=
@"

            WriteObject($write_object);
        }
    }
}

"@;
    }
    elseif ($cmdlet_verb.Equals("Set"))
    {
        $cmdlet_code_body =
@"
        protected override void ProcessRecord()
        {
"@;

        $cmdlet_code_body += $cmdlet_new_object_code;

        foreach($p in $Parameters)
        {
            if (-not [System.String]::IsNullOrEmpty($p["Chain"]))
            {
                $my_chain = $p["Chain"];
                $var_name = Get-PropertyFromChain $my_chain;
                $property = $p["OriginalName"];
                $assign = Get-AssignCode $p;
                if (-not $p["Enum"])
                {
                    $create_object_code = Get-NewObjectCode $my_chain 16;
                    $cmdlet_code_body +=
@"

            if (${assign} != null)
            {

"@
                $cmdlet_code_body += ${create_object_code};
                $cmdlet_code_body +=
@"
                this.${ObjectName}.${var_name}.${property} = ${assign};
            }

"@
                }
                else
                {
                    $create_object_code = Get-NewObjectCode $my_chain 12;
                    $cmdlet_code_body += ${create_object_code};
                    $cmdlet_code_body +=
@"
            this.${ObjectName}.${var_name}.${property} = ${assign};

"@
                }
            }
        }

        $cmdlet_code_body +=
@"

            WriteObject(this.${ObjectName});
        }
    }
}

"@;
    }
    elseif ($cmdlet_verb.Equals("Remove"))
    {
        $cmdlet_code_body =
@"
        protected override void ProcessRecord()
        {
"@;
        $cmdlet_code_body += $cmdlet_new_object_code;

        $cmdlet_code_remove_body = "";

        for($i = 0; $i -lt $Parameters.Count ; $i++)
        {
            $p = $Parameters[$i];
            $chain = $p["Chain"];
            $var_name = $chain[$chain.Length - 1];

            if (-not [System.String]::IsNullOrEmpty($p["Chain"]))
            {
                $property = $p["OriginalName"];
                $thisProperty = $p["Name"];
                $array_parent = Get-ArrayParent $chain;
                $assign = Get-AssignCode $p $false;

                if ($thisProperty -eq "Name")
                {

                    if ($array_parent -ne $TreeNode.Name)
                    {
                        $middle = $array_parent.TrimStart($TreeNode.Name);

                        if ($i -eq 0)
                        {
                            $cmdlet_code_remove_body +=
@"

                    (e${middle}.${property} == ${assign})

"@;
                        }
                        else
                        {

                            $cmdlet_code_remove_body +=
@"
                    && (e${middle}.${property} == ${assign})

"@;
                        }
                    }
                    else
                    {
                        if ($i -eq 0)
                        {
                            $cmdlet_code_remove_body +=
@"

                    (e.${property} == ${assign})

"@;
                        }
                        else
                        {
                            $cmdlet_code_remove_body +=
@"
                    && (e.${property} == ${assign})

"@;
                        }
                    }
                }
            }
        }

        $cmdlet_code_remove_body +=
@"
                );

$cmdlet_remove_object_code
"@;

        $cmdlet_code_body += $cmdlet_code_remove_body;

        $cmdlet_code_body +=
@"

            WriteObject(this.${ObjectName});
        }
    }
}

"@;
    }
    else
    { # "Add"
        $cmdlet_code_body =
@"
        protected override void ProcessRecord()
        {
"@;
        $cmdlet_code_body += $cmdlet_new_object_code;

        foreach($p in $Parameters)
        {
            $chain = $p["Chain"];

            if (-not [System.String]::IsNullOrEmpty($chain))
            {
                $property = $p["OriginalName"];
                $thisProperty = $p["Name"];
                $array_parent = Get-ArrayParent $chain;
                $assign = Get-AssignCode $p;

                $cmdlet_code_add_body +=
@"

            v${array_parent}.${property} = ${assign};
"@;

            }
        }

        foreach ($key in $cmdlet_new_single_object_code.Keys)
        {
            $new_code = $cmdlet_new_single_object_code[$key];
            $cmdlet_code_body +=
@"

            ${new_code}

"@;
        }

        $cmdlet_code_body += $cmdlet_code_add_body;

        foreach ($key in $cmdlet_add_single_object_code.Keys)
        {
            $add_code = $cmdlet_add_single_object_code[$key];
            $cmdlet_code_body +=
@"

            ${add_code}
"@;
        }

        $cmdlet_code_body +=
@"

            WriteObject(this.${ObjectName});
        }
    }
}

"@;
    }

    $code_usings = Get-SortedUsings $parameter_cmdlet_usings;

    $OutputFolder += "/Config/";

    if (-not (Test-Path -Path $OutputFolder))
    {
        mkdir $OutputFolder -Force;
    }

    $fileFullPath = $OutputFolder + $cmdlet_class_name + ".cs";
    $full_code = $code_common_header + "`r`n`r`n" + $code_usings + "`r`n" + $cmdlet_class_code + "`r`n" + $cmdlet_code_body;

    Set-FileContent -Path $fileFullPath -Value $full_code;
}

# Decide the name of cmdlet verb
if ($TreeNode.Name.Equals($ObjectName))
{
    $verb =  "New";
}
elseif ($TreeNode.IsListItem)
{
    $parent_node = $TreeNode.Parent;
    $add_cmdlet = $True;
    while (($parent_node -ne $null) -or ($parent_node.Name -eq $ObjectName))
    {
        if ($parent_node.IsListItem)
        {
            $add_cmdlet = $false;
        }
        $parent_node = $parent_node.Parent;
    }

    if ($add_cmdlet)
    {
        $verb =  "Add";
    }
    else
    {
        $verb =  "New";
    }
}
else
{
    $verb =  "Set";
}

Write-PowershellCmdlet $verb $OutputFolder $TreeNode $Parameters $ModelNameSpace $ObjectName $TypeBinding;

if ($verb.Equals("Add"))
{
    if ($TreeNode.Name.Equals("AdditionalUnattendContent") -or $TreeNode.Name.Equals("Listeners") -or $TreeNode.Name.Equals("Secrets") -or $TreeNode.Name.Equals("PublicKeys"))
    {
        Write-Verbose("Skipping to generate Remove- cmdlets for this object: " + $TreeNode.Name);
    }
    else
    {
        Write-PowershellCmdlet "Remove" $OutputFolder $TreeNode $Parameters $ModelNameSpace $ObjectName $TypeBinding;
    }
}
