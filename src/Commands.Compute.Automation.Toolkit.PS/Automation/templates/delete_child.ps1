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
        throw new Error(util.format(`$('A ${cliOperationDescription} with name `"%s`" not found in the resource group `"%s`"'), name, resourceGroup));
      }
      var index = utils.indexOfCaseIgnore(${resultVarName}.${parentPath}, {name: name});
      if (index === -1) {
        throw new Error(util.format(`$('${cliOperationDescription} with name `"%s`" not found in the ${parentName} `"%s`"'), name, ${resultVarName}.name));
      }
      
      if (!options.quiet && !cli.interaction.confirm(util.format(`$('Delete ${cliOperationDescription} `"%s`"? [y/n] '), name), _)) {
        return;
      }
      ${resultVarName}.${parentPath}.splice(index, 1);
      progress = cli.interaction.progress(util.format(`$('Deleting ${cliOperationDescription} `"%s`"'), name));
      try {
        ${resultVarName} = ${componentNameInLowerCase}ManagementClient.${parentPlural}.createOrUpdate(${parametersString}, ${resultVarName}, _);
      } finally {
        progress.end();
      }
    });"