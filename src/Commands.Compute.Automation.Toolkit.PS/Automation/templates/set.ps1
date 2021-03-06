"  ${cliOperationName}.command(`'${cliMethodOption}${requireParamsString}`')
    .description(`$('Update a ${cliOperationDescription}'))
    .usage('[options]${usageParamsString}')
${cmdOptionsSet}${commonOptions}    .execute(function(${optionParamString}options, _) {
      var useDefaults = false;
      var index = 0;
${promptingOptions}
      var subscription = profile.current.getSubscription(options.subscription);
      var ${componentNameInLowerCase}ManagementClient = utils.create${componentName}ManagementClient(subscription);

      var ${resultVarName};
${safeGet}
      if (!${resultVarName}) {
        throw new Error(util.format(`$('A ${cliOperationDescription} with name `"%s`" not found in the resource group `"%s`"'), ${currentOperationNormalizedName}, resourceGroup));
      }

        var parameters = ${resultVarName};
${treeAnalysisResult}
${updateParametersCode}
${skuNameCode}
      removeEmptyObjects(parameters);
      var progress = cli.interaction.progress(util.format(`$('Updating ${cliOperationDescription} `"%s`"'), ${currentOperationNormalizedName}));
      try {
        ${resultVarName} = ${componentNameInLowerCase}ManagementClient.${cliOperationName}.${cliMethodFuncName}(${parametersString}, parameters, _);
      } finally {
        progress.end();
      }
      cli.interaction.formatOutput(${resultVarName}, traverse);
    });
"
