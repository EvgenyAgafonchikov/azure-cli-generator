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
        cli.output.warn(util.format(`$('A ${cliOperationDescription} with name `"%s`" not found in the resource group `"%s`"'), ${currentOperationNormalizedName}, resourceGroup));
      }
      var $childResultVarName = utils.findFirstCaseIgnore(${resultVarName}.${parentPath}, {name: ${currentOperationNormalizedName}});
      if(!$childResultVarName) {
        cli.output.warn(util.format(`$('${cliOperationDescription} with name `"%s`" not found in the ${parentName} `"%s`"'), ${currentOperationNormalizedName}, ${resultVarName}.name));
        return;
      }
      cli.interaction.formatOutput(${childResultVarName}, traverse);
    });"