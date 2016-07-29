$script:indent = 0;
function AddDependenciesCode($isDefaultsTest)
{
    $depIndex = 0;
    if($isDefaultsTest)
    {
        $depIndex += $global:js_indent_length;
    }
    if($dependencies[$OperationName])
    {
        foreach($dependency in $dependencies[$OperationName])
        {
            $parentCmd = "";
            $parentRef = "";
            if($parents[$dependency])
            {
                $depParent = $parents[$dependency];
                $parentCmd = Get-CliOptionName $parents[$dependency];
                if($operationMappings[$parents[$dependency]])
                {
                    $parentCmd = $operationMappings[$parents[$dependency]];
                    $depParent = Get-SingularNoun $parents[$dependency];
                }
                $parentRef = "--${parentCmd}-name ${depParent}Name";
                $parentCmd = " ${parentCmd}";
            }
            $outResult = "";
            $depCliOption = Get-SingularNoun (Get-CliOptionName $dependency);
            if($operationMappings[$dependency])
            {
                $depCliOption = Get-SingularNoun $operationMappings[$dependency];
            }
            $depResultVarName = (decapitalizeFirstLetter (Get-SingularNoun $dependency));
            $depCliName = $depResultVarName + "Name";
            if($depCliName -eq "subnetName" -and $OperationName -eq "VirtualNetworkGateways")
            {
                $depCliName = "GatewaySubnet";
            }
            if($inputTestCode -like "*${depCliName}*")
            {
                $depCliName = "{${depCliName}}";
            }
            " " * $depIndex + "          var cmd = ('${componentNameInLowerCase}-autogen${parentCmd} ${depCliOption} create -g {group} -n ${depCliName} ${parentRef} ' +";
            foreach($param in $cliOperationParamsRaw[$dependency])
            {
                if($param.required -eq $true)
                {
                    " " * $depIndex + "            '--" + ((Get-CliOptionName $param.name) -replace "express-route-","") + " " + $param.createTestValue + " ' +" ;
                }
                if($param.name -eq "location" -and $inputTestCode -notlike "*location*")
                {
                    $inputTestCode += "  location: '" +  $param.createTestValue + "',";
                }
            }
            " " * $depIndex + "            '--json').formatArgs(${cliOperationName})";
            " " * $depIndex + "          testUtils.executeCommand(suite, retry, cmd, function (${depResultVarName}) {";
            " " * $depIndex + "            ${depResultVarName}.exitStatus.should.equal(0);";
            " " * $depIndex + "            ${depResultVarName} = JSON.parse(${depResultVarName}.text);";
            $depIndex += $global:js_indent_length;
        }
        $script:indent = $depIndex
        if($isDefaultsTest)
        {
          $script:indent -= $global:js_indent_length;
        }
    }
}

"/**
 * Copyright (c) Microsoft.  All rights reserved.
 *
 * Licensed under the Apache License, Version 2.0 (the `"License`");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an `"AS IS`" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

'use strict';

var should = require('should');
var util = require('util');
var _ = require('underscore');

var testUtils = require('../../../util/util');
var CLITest = require('../../../framework/arm-cli-test');
var utils = require('../../../../lib/util/utils');
var NetworkTestUtil = require('../../../util/networkTestUtil');
var tagUtils = require('../../../../lib/commands/arm/tag/tagUtils');
var networkUtil = new NetworkTestUtil();

var testPrefix = 'arm-${componentNameInLowerCase}-autogen-${cliOperationNameInLowerCase}-tests',
  groupName = 'xplat-test-${opCliOptionName}',
  location;
var index = 0;

var ${cliOperationName} = {
${inputTestCode}"
if($cliOperationName -ne "expressRouteCircuitPeerings")
{
  "  name: '${cliOperationName}Name'
"
}
else
{
  "  name: 'AzurePrivatePeering'
"
}
"};

var requiredEnvironment = [{
  name: 'AZURE_VM_TEST_LOCATION',
  defaultValue: 'westus'
}];

describe('arm', function () {
  describe('${componentNameInLowerCase}-autogen', function () {
    var suite, retry = 5;
    var hour = 60 * 60000;

    before(function (done) {
      suite = new CLITest(this, testPrefix, requiredEnvironment);
      suite.setupSuite(function () {
        location = ${cliOperationName}.location || process.env.AZURE_VM_TEST_LOCATION;
        groupName = suite.isMocked ? groupName : suite.generateId(groupName, null);
        ${cliOperationName}.location = location;
        ${cliOperationName}.group = groupName;
        ${cliOperationName}.name = suite.isMocked ? ${cliOperationName}.name : suite.generateId(${cliOperationName}.name, null);
        done();
      });
    });
    after(function (done) {
      this.timeout(hour);
      networkUtil.deleteGroup(groupName, suite, function () {
        suite.teardownSuite(done);
      });
    });
    beforeEach(function (done) {
      suite.setupTest(done);
    });
    afterEach(function (done) {
      suite.teardownTest(done);
    });

    describe('${cliOperationNameInLowerCase}', function () {
      this.timeout(hour);
      it('create should create ${cliOperationNameInLowerCase}', function (done) {
        networkUtil.createGroup(groupName, location, suite, function () {
"
AddDependenciesCode $false
" " * $script:indent + "          var cmd = '${componentNameInLowerCase}-autogen ${parentOp}${opCliOptionNameSingular} create -g {group} -n {name} ${testCreateStr}${additionalOptionsCreate}--json'.formatArgs(${cliOperationName});"
" " * $script:indent + "          testUtils.executeCommand(suite, retry, cmd, function (result) {"
" " * $script:indent + "            result.exitStatus.should.equal(0);"
" " * $script:indent + "            var output = JSON.parse(result.text);"
" " * $script:indent + "            output.name.should.equal(${cliOperationName}.name);"
$assertCodeCreate.Split("`r`n") | foreach { if($_) { " " * $script:indent + $_ } }
$assertIdCodeCreate.Split("`r`n") | foreach { if($_) { " " * $script:indent + $_ } }
" " * $script:indent + "            done();"
" " * $script:indent + "          });"
for($i = $script:indent; $i -gt 0; $i -= $global:js_indent_length)
{
    " " * $i + "        });";
}
"        });
      });
      it('show should display ${cliOperationNameInLowerCase} details', function (done) {
        var cmd = '${componentNameInLowerCase}-autogen ${parentOp}${opCliOptionNameSingular} show -g {group} -n {name} ${additionalOptionsCommon}--json'.formatArgs(${cliOperationName});
        testUtils.executeCommand(suite, retry, cmd, function (result) {
          result.exitStatus.should.equal(0);
          var output = JSON.parse(result.text);
          output.name.should.equal(${cliOperationName}.name);
${assertCodeCreate}
          done();
        });
      });
      it('set should update ${cliOperationNameInLowerCase}', function (done) {
        var cmd = '${componentNameInLowerCase}-autogen ${parentOp}${opCliOptionNameSingular} set -g {group} -n {name} ${testUpdateStr}${additionalOptionsCommon}--json'.formatArgs(${cliOperationName});
        networkUtil.createGroup(groupName, location, suite, function () {
          testUtils.executeCommand(suite, retry, cmd, function (result) {
            result.exitStatus.should.equal(0);
            var output = JSON.parse(result.text);
            output.name.should.equal(${cliOperationName}.name);
${assertCodeUpdate}
            done();
          });
        });
      });
      it('list should display all ${cliOperationNameInLowerCase} in resource group', function (done) {
        var cmd = '${componentNameInLowerCase}-autogen ${parentOp}${opCliOptionNameSingular} list -g {group} ${additionalOptionsCommon}--json'.formatArgs(${cliOperationName});
        testUtils.executeCommand(suite, retry, cmd, function (result) {
          result.exitStatus.should.equal(0);
          var outputs = JSON.parse(result.text);
          _.some(outputs, function (output) {
            return output.name === ${cliOperationName}.name;
          }).should.be.true;
          done();
        });
      });
      it('delete should delete ${cliOperationNameInLowerCase}', function (done) {
        var cmd = '${componentNameInLowerCase}-autogen ${parentOp}${opCliOptionNameSingular} delete -g {group} -n {name} --quiet ${additionalOptionsCommon}--json'.formatArgs(${cliOperationName});
        testUtils.executeCommand(suite, retry, cmd, function (result) {
          result.exitStatus.should.equal(0);

          cmd = '${componentNameInLowerCase}-autogen ${parentOp}${opCliOptionNameSingular} show -g {group} -n {name} ${additionalOptionsCommon}--json'.formatArgs(${cliOperationName});
          testUtils.executeCommand(suite, retry, cmd, function (result) {
            result.exitStatus.should.equal(0);
            var output = JSON.parse(result.text);
            output.should.be.empty;
            done();
          });
        });
      });"
if ($cliDefaults.Length -gt 0)
{
"
      it('create with defaults should create ${cliOperationNameInLowerCase} with default values', function (done) {
        this.timeout(hour);
        networkUtil.deleteGroup(groupName, suite, function () {
          networkUtil.createGroup(groupName, location, suite, function () {"
AddDependenciesCode $true
$script:indent += $global:js_indent_length;
" " * $script:indent + "          var cmd = '${componentNameInLowerCase}-autogen ${parentOp}${opCliOptionNameSingular} create -g {group} -n {name} ${testCreateDefaultStr}${additionalOptionsCreate}--json'.formatArgs(${cliOperationName});"
" " * $script:indent + "          testUtils.executeCommand(suite, retry, cmd, function (result) {"
" " * $script:indent + "            result.exitStatus.should.equal(0);"
" " * $script:indent + "            var output = JSON.parse(result.text);"
" " * $script:indent + "            output.name.should.equal(${cliOperationName}.name);"
$assertCodeCreateDefault.Split("`r`n") | foreach { if($_) {" " * $script:indent + $_} }
" " * $script:indent + "            done();"
" " * $script:indent + "          });"
$script:indent -= $global:js_indent_length;
for($i = $script:indent; $i -gt 0; $i -= $global:js_indent_length)
{
    " " * $i + "        });";
}
"          });
        });
      });"
}
"    });
  });
});"