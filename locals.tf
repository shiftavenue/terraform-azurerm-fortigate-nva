locals {
  activepassive = { # ingenious :)
    0 = "active"
    1 = "passive"
  }

  resource_group_name = var.resource_group_name == "" ? module.naming.resource_group.name : var.resource_group_name
  vnet_name           = var.fortigate_vnet_config.vnet_name == "" ? module.naming.virtual_network.name : var.fortigate_vnet_config.vnet_name
}
