"  ${cliOperationName}.command(`'${cliMethodOption}${requireParamsString}`')
    .description(`$('Create a ${cliOperationDescription}'))
    .usage('[options]${usageParamsString}')
${cmdOptions}${commonOptions}    .execute(function(${optionParamString}options, _) {
      var useDefaults = true;
${promptingOptions}
${promptingOptionsCustom}
      var subscription = profile.current.getSubscription(options.subscription);
      var ${componentNameInLowerCase}ManagementClient = utils.create${componentName}ManagementClient(subscription);
      var index = 0;
      var ${resultVarName};
${safeGet}
      if (!${resultVarName}) {
        throw new Error(util.format(`$('A ${cliOperationDescription} with name `"%s`" not found in the resource group `"%s`"'), ${parentName}, resourceGroup));
      }

      if(utils.findFirstCaseIgnore(${resultVarName}.${parentPath}, {name: ${currentOperationNormalizedName}})) {
        throw new Error(util.format(`$('${cliOperationDescription} with name `"%s`" already exists in the ${parentName} `"%s`"'), ${currentOperationNormalizedName}, ${resultVarName}.name));
      }
        var parameters = {};
${treeAnalysisResult}
${updateParametersCode}
${skuNameCode}
      ${resultVarName}.${parentPath}.push(parameters.${parentPath}[index]);
      removeEmptyObjects(parameters);
      var progress = cli.interaction.progress(util.format(`$('Creating ${cliOperationDescription} `"%s`"'), ${parentName}));
      try {
        ${resultVarName} = ${componentNameInLowerCase}ManagementClient.${parentPlural}.${cliMethodFuncName}(${parametersString}, ${resultVarName}, _);
      } finally {
        progress.end();
      }
      cli.interaction.formatOutput(${resultVarName}, traverse);
    });
"
