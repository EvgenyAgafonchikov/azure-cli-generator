#
# Import_ParserFunction.ps1
#
function Get-SubnetParser()
{
return "
  function _parseSubnet(resourceGroupName, subnet, options, _) {
    if (options.addressPrefix) {
      subnet.addressPrefix = validation.isCIDR(options.addressPrefix, '--address-prefix');
    }

    if (options.networkSecurityGroupId) {
      if (options.networkSecurityGroupName) cli.output.warn(`$('--network-security-group-name parameter will be ignored because --network-security-group-id and --network-security-group-name parameters are mutually exclusive'));
      if (utils.argHasValue(options.networkSecurityGroupId)) {
        subnet.networkSecurityGroup = {
          id: options.networkSecurityGroupId
        };
      } else {
        delete subnet.networkSecurityGroup;
      }
    } else if (options.networkSecurityGroupName) {
      if (utils.argHasValue(options.networkSecurityGroupName)) {
        var nsg = nsgCrud.get(resourceGroupName, options.networkSecurityGroupName, _);
        if (!nsg) {
          throw new Error(util.format(`$('A network security group with name `"%s`" not found in the resource group `"%s`"'), options.networkSecurityGroupName, resourceGroupName));
        }
        subnet.networkSecurityGroup = {
          id: nsg.id
        };
      } else {
        delete subnet.networkSecurityGroup;
      }
    }

    if (options.routeTableId) {
      if (options.routeTableName) cli.output.warn(`$('--route-table-name parameter will be ignored because --route-table-id and --route-table-name parameters are mutually exclusive'));
      if (utils.argHasValue(options.routeTableId)) {
        subnet.routeTable = {
          id: options.routeTableId
        };
      } else {
        delete subnet.routeTable;
      }
    } else if (options.routeTableName) {
      if (utils.argHasValue(options.routeTableName)) {
        var routeTable = routeTableCrud.get(resourceGroupName, options.routeTableName, _);
        if (!routeTable) {
          throw new Error(util.format(`$('A route table with name `"%s`" not found in the resource group `"%s`"'), options.routeTableName, resourceGroupName));
        }
        subnet.routeTable = {
          id: routeTable.id
        };
      } else {
        delete subnet.routeTable;
      }
    }

    return subnet;
  }"
}