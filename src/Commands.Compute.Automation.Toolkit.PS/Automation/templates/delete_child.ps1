"  ${cliOperationName}.command(`'${cliMethodOption}${requireParamsString}`')
    .description(`$('Delete a ${cliOperationDescription}'))
    .usage('[options]${usageParamsString}')
${cmdOptions}${commonOptions}    .execute(function(${optionParamString}options, _) {
${promptingOptions}
      var subscription = profile.current.getSubscription(options.subscription);
      var ${componentNameInLowerCase}ManagementClient = utils.create${componentName}ManagementClient(subscription);
      var ${resultVarName};

${safeGet}
      if (!${resultVarName}) {
        throw new Error(util.format(`$('A ${cliOperationDescription} with name `"%s`" not found in the resource group `"%s`"'), ${currentOperationNormalizedName}, resourceGroup));
      }
      var index = utils.indexOfCaseIgnore(${resultVarName}.${parentPath}, {name: ${currentOperationNormalizedName}});
      if (index === -1) {
        throw new Error(util.format(`$('${cliOperationDescription} with name `"%s`" not found in the ${parentName} `"%s`"'), ${currentOperationNormalizedName}, ${resultVarName}.name));
      }
      
      if (!options.quiet && !cli.interaction.confirm(util.format(`$('Delete ${cliOperationDescription} `"%s`"? [y/n] '), ${currentOperationNormalizedName}), _)) {
        return;
      }
      ${resultVarName}.${parentPath}.splice(index, 1);
      var progress = cli.interaction.progress(util.format(`$('Deleting ${cliOperationDescription} `"%s`"'), ${currentOperationNormalizedName}));
      try {
        ${resultVarName} = ${componentNameInLowerCase}ManagementClient.${parentPlural}.createOrUpdate(${parametersString}, ${resultVarName}, _);
      } finally {
        progress.end();
      }
    });"