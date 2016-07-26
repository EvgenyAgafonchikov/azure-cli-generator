"  ${cliOperationName}.command(`'${cliMethodOption}${requireParamsString}`')
    .description(`$('List a ${cliOperationDescription}'))
    .usage('[options]${usageParamsString}')
${cmdOptions}${commonOptions}    .execute(function(${optionParamString}options, _) {
${promptParentCode}      var subscription = profile.current.getSubscription(options.subscription);
      var ${componentNameInLowerCase}ManagementClient = utils.create${componentName}ManagementClient(subscription);

      var ${resultVarName} = null;
${safeGet}
      var items = ${resultVarName}.${parentPath};
      if (items.length === 0) {
        cli.output.warn(`$('No ${cliOperationDescription} found'));
      } else {
        cli.output.table(items, function (row, item) {
          row.cell(`$('Name'), item.name);
          var resInfo = resourceUtils.getResourceInformation(item.id);
          row.cell(`$('Resource group'), resInfo.resourceGroup);
          row.cell(`$('Provisioning state'), item.provisioningState);
        });
      }
    });"
