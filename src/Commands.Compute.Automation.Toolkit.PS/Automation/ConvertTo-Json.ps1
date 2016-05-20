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
  $inputObject = $null,

  [Parameter(Mandatory = $false)]
  [bool]$compress = $false,

  [Parameter(Mandatory = $false)]
  [int]$depth = 1000
)

if ($compress)
{
    $jsonText = ConvertTo-Json -Depth $depth -InputObject $inputObject -Compress;
}
else
{
    $jsonText = ConvertTo-Json -Depth $depth -InputObject $inputObject;
    
    # Re-format the JSON text
    [string]$newJsonText = "";
    [int]$indent = 0;
    $startQuote = $true;
    $semiColon = $false;
    for ($i = 0; $i -lt $jsonText.Length; $i++)
    {
        [char]$ch = $jsonText[$i];
        if ($ch -eq "[")
        {
            if ($semiColon -ne $true)
            {
                $newJsonText += " " * $indent;
            }

            $newJsonText += $ch;
            $indent += 2;
        }
        elseif ($ch -eq "]")
        {
            $indent -= 2;
            $newJsonText += " " * $indent;
            $newJsonText += $ch;
        }
        elseif ($ch -eq "{")
        {
            if ($semiColon -ne $true)
            {
                $newJsonText += " " * $indent;
            }

            $newJsonText += $ch;
            $indent += 2;
        }
        elseif ($ch -eq "}")
        {
            $indent -= 2;
            $newJsonText += " " * $indent;
            $newJsonText += $ch;
        }
        elseif ($ch -eq " " -or $ch -eq "`t")
        {
            # Skip Space Characters
        }
        elseif ($ch -eq "`"")
        {
            if ($startQuote -eq $true)
            {
                if ($semiColon -ne $true)
                {
                    $newJsonText += " " * $indent;
                }

                $startQuote = $false;
            }
            else
            {
                $startQuote = $true;
            }

            $newJsonText += $ch;
        }
        else
        {
            $newJsonText += $ch;
        }

        # Track Semicolon
        if ($ch -eq ":")
        {
            $semiColon = $true;
        }
        elseif ($ch -ne " ")
        {
            $semiColon = $false;
        }
    }

    $jsonText = $newJsonText.Replace("`r`n`r`n", "`r`n");
}

#$jsonText = $jsonText.Replace(":null", ":`"`"");
$jsonText = $jsonText.Replace(":0", ":`"`"");

# Change the JSON fields to use lower cases, e.g. {"Say":"Hello World!"} => {"say":"Hello World!"}
$lowerCaseJsonText = $jsonText;
$letterA = [int]([char]'A');
for ($i = 0; $i -lt 26; $i++)
{
    $ch = [char]($letterA + $i);
    $lowerCaseJsonText = $lowerCaseJsonText.Replace("`"" + $ch, "`"" + "$ch".ToLower());
}

Write-Output $lowerCaseJsonText;
