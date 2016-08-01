"  ${cliOperationName}.command(`'${cliMethodOption}${requireParamsString}`')
    .description(`$('Show a ${cliOperationDescription}'))
    .usage('[options]${usageParamsString}')
${cmdOptions}${commonOptions}    .execute(function(${optionParamString}options, _) {
${promptingOptions}
      var subscription = profile.current.getSubscription(options.subscription);
      var ${componentNameInLowerCase}ManagementClient = utils.create${componentName}ManagementClient(subscription);
      var ${resultVarName};

${safeGet}
      if (!${resultVarName}) {
        cli.output.warn(util.format(`$('A ${cliOperationDescription} with name `"%s`" not found in the resource group `"%s`"'), name, resourceGroup));
      }
      cli.interaction.formatOutput(${resultVarName}, traverse);
    });"