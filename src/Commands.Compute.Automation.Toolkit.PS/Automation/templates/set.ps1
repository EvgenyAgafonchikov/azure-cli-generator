"  ${cliOperationName}.command(`'${cliMethodOption}${requireParamsString}`')
    .description(`$('Update a ${cliOperationDescription}'))
    .usage('[options]${usageParamsString}')
${cmdOptionsSet}${commonOptions}    .execute(function(${optionParamString}options, _) {"
if ($cliDefaults.Length -gt 0)
{
"
      var useDefaults = false;"
}
if($indexVarRequired )
{
"
      var index = 0;"
}
"
${promptingOptions}
      var subscription = profile.current.getSubscription(options.subscription);
      var ${componentNameInLowerCase}ManagementClient = utils.create${componentName}ManagementClient(subscription);

      var ${resultVarName};
${safeGet}
      if (!${resultVarName}) {
        throw new Error(util.format(`$('A ${cliOperationDescription} with name `"%s`" not found in the resource group `"%s`"'), name, resourceGroup));
      }

        var parameters = ${resultVarName};
${treeAnalysisResult}
${updateParametersCode}
${skuNameCode}
      generatorUtils.removeEmptyObjects(parameters);
      progress = cli.interaction.progress(util.format(`$('Updating ${cliOperationDescription} `"%s`"'), name));
      try {
        ${resultVarName} = ${componentNameInLowerCase}ManagementClient.${cliOperationName}.${cliMethodFuncName}(${parametersString}, parameters, _);
      } finally {
        progress.end();
      }
      cli.interaction.formatOutput(${resultVarName}, generatorUtils.traverse);
    });
"
