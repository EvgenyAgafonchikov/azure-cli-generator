"  ${cliOperationName}.command(`'${cliMethodOption}${requireParamsString}`')
    .description(`$('Update a ${cliOperationDescription}'))
    .usage('[options]${usageParamsString}')
${cmdOptionsSet}${commonOptions}    .execute(function(${optionParamString}options, _) {
      var useDefaults = false;
${promptingOptions}
${promptingOptionsCustom}
      var subscription = profile.current.getSubscription(options.subscription);
      var ${componentNameInLowerCase}ManagementClient = utils.create${componentName}ManagementClient(subscription);
      var ${resultVarName};
${safeGet}
      if (!${resultVarName}) {
        throw new Error(util.format(`$('A ${cliOperationDescription} with name `"%s`" not found in the resource group `"%s`"'), ${parentName}, resourceGroup));
      }
      var $childResultVarName = utils.findFirstCaseIgnore(${resultVarName}.${parentPath}, {name: ${currentOperationNormalizedName}});
      var index = utils.indexOfCaseIgnore(${resultVarName}.${parentPath}, {name: ${currentOperationNormalizedName}});
      if(!$childResultVarName) {
        throw new Error(util.format(`$('${cliOperationDescription} with name `"%s`" not found in the ${parentName} `"%s`"'), ${currentOperationNormalizedName}, ${resultVarName}.name))
      }
        var parameters = ${resultVarName};
${treeAnalysisResult}
${updateParametersCode}
${skuNameCode}
      removeEmptyObjects(parameters);
      var progress = cli.interaction.progress(util.format(`$('Updating ${cliOperationDescription} `"%s`"'), ${currentOperationNormalizedName}));
      try {
        ${resultVarName} = ${componentNameInLowerCase}ManagementClient.${parentPlural}.${cliMethodFuncName}(${parametersString}, ${resultVarName}, _);
      } finally {
        progress.end();
      }
      cli.interaction.formatOutput(${resultVarName}, traverse);
    });
"
