"  ${cliOperationName}.command(`'${cliMethodOption}${requireParamsString}`')
    .description(`$('Create a ${cliOperationDescription}'))
    .usage('[options]${usageParamsString}')
${cmdOptions}${commonOptions}    .execute(function(${optionParamString}options, _) {
${promptingOptions}
${promptingOptionsCustom}
      var subscription = profile.current.getSubscription(options.subscription);
      var ${componentNameInLowerCase}ManagementClient = utils.create${componentName}ManagementClient(subscription);

      nsgCrud = new Nsg(cli, networkManagementClient);
      routeTableCrud = new RouteTable(cli, networkManagementClient);
      var ${resultVarName};
${safeGet}
      if (${resultVarName}) {
        throw new Error(util.format(`$('A ${cliOperationDescription} with name `"%s`" already exists in the resource group `"%s`"'), ${currentOperationNormalizedName}, resourceGroup));
      }

        var parameters = {};
        _parseSubnet(resourceGroup, parameters, options, _);
${treeAnalysisResult}
${updateParametersCode}
      var progress = cli.interaction.progress(util.format(`$('Creating ${cliOperationDescription} `"%s`"'), ${currentOperationNormalizedName}));
      try {
        ${resultVarName} = ${componentNameInLowerCase}ManagementClient.${cliOperationName}.${cliMethodFuncName}(${parametersString}, parameters, _);
      } finally {
        progress.end();
      }
      traverse(${resultVarName}, 0);
    });

${parsers}"
