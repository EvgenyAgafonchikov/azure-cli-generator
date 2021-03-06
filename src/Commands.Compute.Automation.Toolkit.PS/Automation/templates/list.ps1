"  ${cliOperationName}.command(`'${cliMethodOption}${requireParamsString}`')
    .description(`$('List a ${cliOperationDescription}'))
    .usage('[options]${usageParamsString}')
${cmdOptions}${commonOptions}    .execute(function(${optionParamString}options, _) {
${resourceGroupInit}      var subscription = profile.current.getSubscription(options.subscription);
      var ${componentNameInLowerCase}ManagementClient = utils.create${componentName}ManagementClient(subscription);

      var ${resultVarName} = null;

      var progress;
      try {
        if(typeof ${componentNameInLowerCase}ManagementClient.${cliOperationName}.listAll != 'function') {
${promptingCode}
          progress = cli.interaction.progress(`$('Getting the ${cliOperationDescription}'));
          ${resultVarName} = ${componentNameInLowerCase}ManagementClient.${cliOperationName}.list(${optionParamString} _);
        } else {
          if(options.resourceGroup) {
${promptingCode}
            progress = cli.interaction.progress(`$('Getting the $cliOperationDescription'));
            ${resultVarName} = ${componentNameInLowerCase}ManagementClient.${cliOperationName}.list(${optionParamString} _);
          } else {
${promptingCodeNoResource}
            progress = cli.interaction.progress(`$('Getting the ${cliOperationDescription}'));
            ${resultVarName} = ${componentNameInLowerCase}ManagementClient.${cliOperationName}.listAll(${optionParamString} _);
          }
        }
      } finally {
        progress.end();
      }

      if (${resultVarName}.length === 0) {
        cli.output.warn(`$('No ${cliOperationDescription} found'));
      } else {
"
if ($cliOperationName -eq "usages")
{
"       cli.output.table(result, function (row, item) {
          row.cell(`$('Name'), item.name.localizedValue);
          row.cell(`$('Unit'), item.unit);
          row.cell(`$('Current Value'), item.currentValue);
          row.cell(`$('Limit'), item.limit);
        });
"
}
elseif($cliOperationName -eq "ExpressRouteServiceProviders")
{
"       cli.output.table(result, function (row, provider) {
          row.cell(`$('Name'), provider.name);
          var bandwidths = provider.bandwidthsOffered.map(function (b) {
            return b.offerName;
          });
          row.cell(`$('Bandwidths offered'), bandwidths);
          row.cell(`$('Peering locations'), provider.peeringLocations.join());
        });
"
}
else
{
"       cli.output.table(${resultVarName}, function (row, item) {
          row.cell(`$('Name'), item.name);"
    if(-not $parents[$OperationName])
    {
    "
          row.cell(`$('Location'), item.location);"
    }
"
          var resInfo = resourceUtils.getResourceInformation(item.id);
          row.cell(`$('Resource group'), resInfo.resourceGroup);
          row.cell(`$('Provisioning state'), item.provisioningState);
        });
"
}
"      }
    });"
