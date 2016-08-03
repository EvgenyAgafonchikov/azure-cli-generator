"  ${cliOperationName}.command(`'${cliMethodOption}${requireParamsString}`')
    .description(`$('Create a ${cliOperationDescription}'))
    .usage('[options]${usageParamsString}')
${cmdOptions}${commonOptions}    .execute(function(${optionParamString}options, _) {"
if ($cliDefaults.Length -gt 0)
{
"
      var useDefaults = true;"
}
if($indexVarRequired )
{
"
      var index = 0;"
}
"
${promptingOptions}
${promptingOptionsCustom}
      var subscription = profile.current.getSubscription(options.subscription);
      var ${componentNameInLowerCase}ManagementClient = utils.create${componentName}ManagementClient(subscription);

      var ${resultVarName};
${safeGet}
      if (${resultVarName}) {
        throw new Error(util.format(`$('A ${cliOperationDescription} with name `"%s`" already exists in the resource group `"%s`"'), name, resourceGroup));
      }

        var parameters = {};
${treeAnalysisResult}
${updateParametersCode}
${skuNameCode}
      generatorUtils.removeEmptyObjects(parameters);
      progress = cli.interaction.progress(util.format(`$('Creating ${cliOperationDescription} `"%s`"'), name));
      try {
        ${resultVarName} = ${componentNameInLowerCase}ManagementClient.${cliOperationName}.${cliMethodFuncName}(${parametersString}, parameters, _);
      } finally {
        progress.end();
      }
      cli.interaction.formatOutput(${resultVarName}, generatorUtils.traverse);
    });
"
