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
      if (!options.quiet && !cli.interaction.confirm(util.format(`$('Delete ${cliOperationDescription} `"%s`"? [y/n] '), ${currentOperationNormalizedName}), _)) {
        return;
      }

      var progress = cli.interaction.progress(util.format(`$('Deleting ${cliOperationDescription} `"%s`"'), ${currentOperationNormalizedName}));
      try {
        ${componentNameInLowerCase}ManagementClient.${cliOperationName}.${cliMethodFuncName}(${parametersString}, _);
      } finally {
        progress.end();
      }
    });"