"  ${cliOperationName}.command(`'${cliMethodOption}${requireParamsString}`')
    .description(`$('Update a ${cliOperationDescription}'))
    .usage('[options]${usageParamsString}')
${cmdOptions}${commonOptions}    .execute(function(${optionParamString}options, _) {
${promptingOptions}
      var subscription = profile.current.getSubscription(options.subscription);
      var ${componentNameInLowerCase}ManagementClient = utils.create${componentName}ManagementClient(subscription);

      nsgCrud = new Nsg(cli, networkManagementClient);
      routeTableCrud = new RouteTable(cli, networkManagementClient);
      var ${resultVarName};
${safeGet}
      if (!${resultVarName}) {
        throw new Error(util.format(`$('A ${cliOperationDescription} with name `"%s`" not found in the resource group `"%s`"'), ${currentOperationNormalizedName}, resourceGroup));
      }

        var parameters = ${resultVarName};
        _parseSubnet(resourceGroup, parameters, options, _);
${treeAnalysisResult}
${updateParametersCode}
      var progress = cli.interaction.progress(util.format(`$('Updating ${cliOperationDescription} `"%s`"'), ${currentOperationNormalizedName}));
      try {
        ${resultVarName} = ${componentNameInLowerCase}ManagementClient.${cliOperationName}.${cliMethodFuncName}(${parametersString}, parameters, _);
      } finally {
        progress.end();
      }
      cli.interaction.formatOutput(${resultVarName}, traverse);
    });

${parsers}"
