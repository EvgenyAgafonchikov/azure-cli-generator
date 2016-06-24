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
var NetworkTestUtil = require('../../../util/networkTestUtil');
var networkUtil = new NetworkTestUtil();

var testPrefix = 'arm-${componentNameInLowerCase}-autogen-${cliOperationNameInLowerCase}-tests',
  groupName = 'xplat-test-${opCliOptionName}',
  location;

var ${cliOperationName} = {
${inputTestCode}  name: '${cliOperationName}Name'
};

var requiredEnvironment = [{
  name: 'AZURE_VM_TEST_LOCATION',
  defaultValue: 'westus'
}];

describe('arm', function () {
  describe('${componentNameInLowerCase}-autogen', function () {
    var suite, retry = 5;

    before(function (done) {
      suite = new CLITest(this, testPrefix, requiredEnvironment);
      suite.setupSuite(function () {
        location = process.env.AZURE_VM_TEST_LOCATION;
        groupName = suite.isMocked ? groupName : suite.generateId(groupName, null);
        ${cliOperationName}.location = location;
        ${cliOperationName}.group = groupName;
        ${cliOperationName}.name = suite.isMocked ? ${cliOperationName}.name : suite.generateId(${cliOperationName}.name, null);
        done();
      });
    });
    after(function (done) {
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
      it('create should create ${cliOperationNameInLowerCase}', function (done) {
        var cmd = '${componentNameInLowerCase}-autogen ${opCliOptionNameSingular} create -g {group} -n {name} ${testCreateStr}--json'.formatArgs(${cliOperationName});
        networkUtil.createGroup(groupName, location, suite, function () {
          testUtils.executeCommand(suite, retry, cmd, function (result) {
            result.exitStatus.should.equal(0);
            var output = JSON.parse(result.text);
            output.name.should.equal(${cliOperationName}.name);
${assertCodeCreate}
            done();
          });
        });
      });
      it('show should display ${cliOperationNameInLowerCase} details', function (done) {
        var cmd = '${componentNameInLowerCase}-autogen ${opCliOptionNameSingular} show -g {group} -n {name} --json'.formatArgs(${cliOperationName});
        testUtils.executeCommand(suite, retry, cmd, function (result) {
          result.exitStatus.should.equal(0);
          var output = JSON.parse(result.text);
${assertCodeCreate}
          done();
        });
      });
      it('set should update ${cliOperationNameInLowerCase}', function (done) {
        var cmd = '${componentNameInLowerCase}-autogen ${opCliOptionNameSingular} set -g {group} -n {name} ${testUpdateStr}--json'.formatArgs(${cliOperationName});
        networkUtil.createGroup(groupName, location, suite, function () {
          testUtils.executeCommand(suite, retry, cmd, function (result) {
            result.exitStatus.should.equal(0);
            var output = JSON.parse(result.text);
${assertCodeUpdate}
            done();
          });
        });
      });
      it('list should display all ${cliOperationNameInLowerCase} in resource group', function (done) {
        var cmd = '${componentNameInLowerCase}-autogen ${opCliOptionNameSingular} list -g {group} --json'.formatArgs(${cliOperationName});
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
        var cmd = '${componentNameInLowerCase}-autogen ${opCliOptionNameSingular} delete -g {group} -n {name} --quiet --json'.formatArgs(${cliOperationName});
        testUtils.executeCommand(suite, retry, cmd, function (result) {
          result.exitStatus.should.equal(0);

          cmd = '${componentNameInLowerCase}-autogen ${opCliOptionNameSingular} show -g {group} -n {name} --json'.formatArgs(${cliOperationName});
          testUtils.executeCommand(suite, retry, cmd, function (result) {
            result.exitStatus.should.equal(0);
            var output = JSON.parse(result.text);
            output.should.be.empty;
            done();
          });
        });
      });
    });
  });
});"