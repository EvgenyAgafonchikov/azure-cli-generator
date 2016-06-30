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
${treeAnalysisResult}
${updateParametersCode}
${skuNameCode}
      var progress = cli.interaction.progress(util.format(`$('Creating ${cliOperationDescription} `"%s`"'), ${currentOperationNormalizedName}));
      try {
        ${resultVarName} = ${componentNameInLowerCase}ManagementClient.${cliOperationName}.${cliMethodFuncName}(${parametersString}, parameters, _);
      } finally {
        progress.end();
      }
      cli.interaction.formatOutput(${resultVarName}, traverse);
    });
"
