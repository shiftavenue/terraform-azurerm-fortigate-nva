locals {
  vnet_name        = var.fortigate_vnet_config.vnet_name == "" ? module.naming.virtual_network.name : var.fortigate_vnet_config.vnet_name
  templatefilename = var.custom_forti_configuration_file == "" ? "${path.module}/configuration/forticonf.conf" : var.custom_forti_configuration_file
}
