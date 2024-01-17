data "external" "term_acceptance" {
  program = [
    "bash",
    "az",
    "vm",
    "image",
    "terms",
    "accept",
    "--urn",
    "${var.var.vm_publisher}:${var.var.vm_offer}:${var.fgtsku[var.license_type]}:${var.var.fgtversion}"
  ]
}

data "azapi_resource" "launchpad" {
  parent_id              = "/subscriptions/${var.subscription_id}"
  type                   = "Microsoft.Resources/resourceGroups@2021-04-01"
  name                   = var.launchpad_resource_group_name != "" ? var.launchpad_resource_group_name : module.naming.resource_group.name
  response_export_values = ["*"]
}

resource "azapi_resource" "launchpad" {
  count                  = var.resource_group_creation_enabled == "" ? 1 : 0
  parent_id              = "/subscriptions/${var.subscription_id}"
  type                   = "Microsoft.Resources/resourceGroups@2021-04-01"
  name                   = var.launchpad_resource_group_name != "" ? var.launchpad_resource_group_name : module.naming.resource_group.name
  location               = var.location
  body                   = jsonencode({})
  response_export_values = ["*"]
  #tags      = var.tags
}

resource "azurerm_resource_group" "fortinetrg" {
  count    = var.existing_resource_ids.resource_group_id == "" ? 1 : 0
  name     = local.resource_group_name
  location = var.location
  tags     = var.resource_group_tags
}

resource "azurerm_storage_account" "fortinetstorageaccount" {
  name                     = module.naming.storage_account.name_unique
  resource_group_name      = local.resource_group_name
  location                 = var.location
  account_replication_type = "LRS"
  account_tier             = "Standard"
}

resource "azurerm_user_assigned_identity" "umi" {
  count               = var.assign_managed_identity ? 1 : 0
  name                = module.naming.user_assigned_identity.name
  location            = var.location
  resource_group_name = local.resource_group_name
}

resource "azurerm_virtual_machine" "fortinetvm" {
  count                        = 2
  name                         = join("-", [module.naming.linux_virtual_machine.name, local.activepassive[count.index]])
  location                     = var.location
  resource_group_name          = local.resource_group_name
  network_interface_ids        = [azurerm_network_interface.managementinterface[count.index].id, azurerm_network_interface.publicinterface[count.index].id, azurerm_network_interface.privateinterface[count.index].id]
  primary_network_interface_id = azurerm_network_interface.managementinterface[count.index].id
  vm_size                      = var.vm_size
  zones                        = var.availability_zones
  depends_on                   = [azurerm_storage_account.fortinetstorageaccount, azurerm_marketplace_agreement.fortinet]

  dynamic "identity" {
    for_each = var.assign_managed_identity ? toset([1]) : toset([])
    content {
      identity_ids = [azurerm_user_assigned_identity.umi[0].id]
      type         = "UserAssigned"
    }
  }

  storage_image_reference {
    publisher = var.vm_publisher
    offer     = var.vm_offer
    sku       = var.license_type == "byol" ? var.fgtsku["byol"] : var.fgtsku["payg"]
    version   = var.fgtversion
  }

  plan {
    name      = var.license_type == "byol" ? var.fgtsku["byol"] : var.fgtsku["payg"]
    publisher = var.vm_publisher
    product   = var.vm_offer
  }

  storage_os_disk {
    name              = join("-", [join("-", [module.naming.linux_virtual_machine.name, local.activepassive[count.index]]), "osdisk"])
    caching           = "ReadWrite"
    managed_disk_type = "Standard_LRS"
    create_option     = "FromImage"
  }

  # Log data disks
  storage_data_disk {
    name              = join("-", [join("-", [module.naming.linux_virtual_machine.name, local.activepassive[count.index]]), "datadisk"])
    managed_disk_type = "Standard_LRS"
    create_option     = "Empty"
    lun               = 0
    disk_size_gb      = "30"
  }

  os_profile {
    computer_name  = join("-", [module.naming.linux_virtual_machine.name, local.activepassive[count.index]])
    admin_username = var.adminusername
    admin_password = var.adminpassword
    custom_data    = var.skip_config ? null : data.template_file.forticonf[count.index].rendered
  }

  os_profile_linux_config {
    disable_password_authentication = false
  }

  boot_diagnostics {
    enabled     = true
    storage_uri = azurerm_storage_account.fortinetstorageaccount.primary_blob_endpoint
  }
}

resource "azurerm_virtual_network" "fortinetvnet" {
  count               = var.existing_resource_ids.vnet_id == "" ? 1 : 0
  name                = local.vnet_name
  address_space       = [var.fortigate_vnet_config.vnet_address_space]
  location            = var.location
  resource_group_name = local.resource_group_name
}

resource "azurerm_subnet" "publicsubnet" {
  count                = var.existing_resource_ids.public_subnet_id == "" ? 1 : 0
  name                 = var.fortigate_vnet_config.public_subnet_name == "" ? join("-", [module.naming.subnet.name, "public"]) : var.fortigate_vnet_config.public_subnet_name
  resource_group_name  = local.resource_group_name
  virtual_network_name = local.vnet_name
  address_prefixes     = [var.fortigate_vnet_config.public_subnet_address_space]
}

resource "azurerm_subnet" "privatesubnet" {
  count                = var.existing_resource_ids.private_subnet_id == "" ? 1 : 0
  name                 = var.fortigate_vnet_config.private_subnet_name == "" ? join("-", [module.naming.subnet.name, "private"]) : var.fortigate_vnet_config.private_subnet_name
  resource_group_name  = local.resource_group_name
  virtual_network_name = local.vnet_name
  address_prefixes     = [var.fortigate_vnet_config.private_subnet_address_space]
}

resource "azurerm_subnet" "hamgmtsubnet" {
  count                = var.existing_resource_ids.ha_mgmt_subnet_id == "" ? 1 : 0
  name                 = var.fortigate_vnet_config.ha_mgmt_subnet_name == "" ? join("-", [module.naming.subnet.name, "hamgmt"]) : var.fortigate_vnet_config.ha_mgmt_subnet_name
  resource_group_name  = local.resource_group_name
  virtual_network_name = local.vnet_name
  address_prefixes     = [var.fortigate_vnet_config.ha_mgmt_subnet_address_space]
}

// Allocated Public IP
resource "azurerm_public_ip" "ClusterPublicIP" {
  name                = join("-", [module.naming.public_ip.name, "cluster"])
  location            = var.location
  resource_group_name = local.resource_group_name
  sku                 = "Standard"
  allocation_method   = "Static"

}

resource "azurerm_public_ip" "mgmtip" {
  count               = 2
  name                = join("-", [module.naming.public_ip.name, "ha-mgmt", local.activepassive[count.index]])
  location            = var.location
  resource_group_name = local.resource_group_name
  sku                 = "Standard"
  allocation_method   = "Static"

}

//  Network Security Group
resource "azurerm_network_security_group" "publicnetworknsg" {
  name                = join("-", [module.naming.network_security_group.name, "public"])
  location            = var.location
  resource_group_name = local.resource_group_name

  security_rule {
    name                       = "TCP"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_network_security_group" "privatenetworknsg" {
  name                = join("-", [module.naming.network_security_group.name, "private"])
  location            = var.location
  resource_group_name = local.resource_group_name

  security_rule {
    name                       = "All"
    priority                   = 1001
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }

}

resource "azurerm_network_security_rule" "outgoing_public" {
  name                        = join("-", [module.naming.network_security_group_rule.name, "public"])
  priority                    = 100
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = local.resource_group_name
  network_security_group_name = azurerm_network_security_group.publicnetworknsg.name
}

resource "azurerm_network_security_rule" "outgoing_private" {
  name                        = join("-", [module.naming.network_security_group_rule.name, "private"])
  priority                    = 100
  direction                   = "Outbound"
  access                      = "Allow"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = local.resource_group_name
  network_security_group_name = azurerm_network_security_group.privatenetworknsg.name
}

resource "azurerm_network_interface" "managementinterface" {
  count                         = 2
  name                          = join("-", [module.naming.network_interface.name, "ha-mgmt", local.activepassive[count.index]])
  location                      = var.location
  resource_group_name           = local.resource_group_name
  enable_accelerated_networking = var.use_accelerated_networking

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = var.existing_resource_ids.ha_mgmt_subnet_id == "" ? azurerm_subnet.hamgmtsubnet[0].id : var.existing_resource_ids.ha_mgmt_subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = cidrhost(var.fortigate_vnet_config.ha_mgmt_subnet_address_space, (count.index + 4))
    primary                       = true
    public_ip_address_id          = azurerm_public_ip.mgmtip[count.index].id
  }
}

resource "azurerm_network_interface" "publicinterface" {
  count                         = 2
  name                          = join("-", [module.naming.network_interface.name, "public", local.activepassive[count.index]])
  location                      = var.location
  resource_group_name           = local.resource_group_name
  enable_ip_forwarding          = true
  enable_accelerated_networking = var.use_accelerated_networking

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = var.existing_resource_ids.public_subnet_id == "" ? azurerm_subnet.publicsubnet[0].id : var.existing_resource_ids.public_subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = cidrhost(var.fortigate_vnet_config.public_subnet_address_space, (count.index + 4))
    public_ip_address_id          = count.index == 0 ? azurerm_public_ip.ClusterPublicIP.id : null
  }

}

resource "azurerm_network_interface" "privateinterface" {
  count                         = 2
  name                          = join("-", [module.naming.network_interface.name, "private", local.activepassive[count.index]])
  location                      = var.location
  resource_group_name           = local.resource_group_name
  enable_ip_forwarding          = true
  enable_accelerated_networking = var.use_accelerated_networking

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = var.existing_resource_ids.private_subnet_id == "" ? azurerm_subnet.privatesubnet[0].id : var.existing_resource_ids.private_subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = cidrhost(var.fortigate_vnet_config.private_subnet_address_space, (count.index + 4))
  }

}

# Connect the security group to the network interfaces
resource "azurerm_network_interface_security_group_association" "managementPortnsg" {
  count                     = 2
  depends_on                = [azurerm_network_interface.managementinterface]
  network_interface_id      = azurerm_network_interface.managementinterface[count.index].id
  network_security_group_id = azurerm_network_security_group.publicnetworknsg.id
}


resource "azurerm_network_interface_security_group_association" "publicPortnsg" {
  count                     = 2
  depends_on                = [azurerm_network_interface.publicinterface]
  network_interface_id      = azurerm_network_interface.publicinterface[count.index].id
  network_security_group_id = azurerm_network_security_group.privatenetworknsg.id
}

resource "azurerm_network_interface_security_group_association" "privatePortnsg" {
  count                     = 2
  depends_on                = [azurerm_network_interface.privateinterface]
  network_interface_id      = azurerm_network_interface.privateinterface[count.index].id
  network_security_group_id = azurerm_network_security_group.privatenetworknsg.id
}

resource "azurerm_route_table" "internal" {
  name                = module.naming.route_table.name
  location            = var.location
  resource_group_name = local.resource_group_name
}

resource "azurerm_route" "default" {
  depends_on          = [azurerm_virtual_machine.fortinetvm]
  name                = "default"
  resource_group_name = local.resource_group_name
  route_table_name    = azurerm_route_table.internal.name
  address_prefix      = "0.0.0.0/0"
  next_hop_type       = "VirtualAppliance"
  # Unclear why Fortinet requires the next hop IP to be the active instance's IP
  next_hop_in_ip_address = azurerm_network_interface.privateinterface[0].ip_configuration[0].private_ip_address
}

resource "azurerm_subnet_route_table_association" "internalassociate" {
  depends_on     = [azurerm_route_table.internal]
  subnet_id      = var.existing_resource_ids.private_subnet_id == "" ? azurerm_subnet.privatesubnet[0].id : var.existing_resource_ids.private_subnet_id
  route_table_id = azurerm_route_table.internal.id
}


data "template_file" "forticonf" {
  count    = 2
  template = file("${path.module}/configuration/forticonf.conf")
  vars = {
    type                = var.license_type
    license_file        = var.license_file
    managementPort_ip   = azurerm_network_interface.managementinterface[count.index].ip_configuration[0].private_ip_address
    managementPort_mask = cidrnetmask(var.fortigate_vnet_config.ha_mgmt_subnet_address_space)
    publicPort_ip       = azurerm_network_interface.publicinterface[count.index].ip_configuration[0].private_ip_address
    publicPort_mask     = cidrnetmask(var.fortigate_vnet_config.public_subnet_address_space)
    privatePort_ip      = azurerm_network_interface.privateinterface[count.index].ip_configuration[0].private_ip_address
    privatePort_mask    = cidrnetmask(var.fortigate_vnet_config.private_subnet_address_space)
    peerip              = count.index == 0 ? azurerm_network_interface.managementinterface[1].ip_configuration[0].private_ip_address : azurerm_network_interface.managementinterface[0].ip_configuration[0].private_ip_address
    peerPrio            = count.index == 0 ? 255 : 1
    mgmt_gateway_ip     = cidrhost(var.fortigate_vnet_config.ha_mgmt_subnet_address_space, 1)
    default_gateway     = cidrhost(var.fortigate_vnet_config.public_subnet_address_space, 1)
    tenant              = var.tenant_id
    subscription        = var.subscription_id
    clientid            = var.client_id
    clientsecret        = var.client_secret
    adminsport          = var.fortigate_admin_port
    resourcegroup       = local.resource_group_name
    clusterip           = azurerm_public_ip.ClusterPublicIP.name
    routename           = azurerm_route_table.internal.name
    hostname            = join("-", [module.naming.linux_virtual_machine.name, local.activepassive[count.index]])
  }
}
