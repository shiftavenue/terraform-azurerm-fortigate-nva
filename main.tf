resource "azurerm_marketplace_agreement" "fortinet" {
  publisher = var.vm_publisher
  offer     = var.vm_offer
  plan      = var.license_type == "payg" ? "fortinet_fg-vm_payg_2022" : "fortinet_fg-vm"
}

resource "azurerm_resource_group" "fortinetrg" {
  count    = var.existing_resource_ids.resource_group_id == "" ? 1 : 0
  name     = var.resource_group_name == "" ? module.naming.resource_group.name : var.resource_group_name
  location = var.location
  tags     = var.resource_group_tags
}

resource "azurerm_storage_account" "fortinetstorageaccount" {
  name                     = module.naming.storage_account.name_unique
  resource_group_name      = var.resource_group_name == "" ? module.naming.resource_group.name : var.resource_group_name
  location                 = var.location
  account_replication_type = "LRS"
  account_tier             = "Standard"
}

resource "azurerm_user_assigned_identity" "umi" {
  count               = var.assign_managed_identity ? 1 : 0
  name                = module.naming.user_assigned_identity.name
  location            = var.location
  resource_group_name = var.resource_group_name == "" ? module.naming.resource_group.name : var.resource_group_name
}

resource "azurerm_availability_set" "av" {
  count                        = var.deploy_availability_set ? 1 : 0
  name                         = module.naming.availability_set.name
  location                     = var.location
  resource_group_name          = var.resource_group_name == "" ? module.naming.resource_group.name : var.resource_group_name
  platform_fault_domain_count  = 2
  platform_update_domain_count = 2
  managed                      = true
}

resource "azurerm_virtual_machine" "fortinetvm" {
  count               = 2
  name                = join("-", [module.naming.linux_virtual_machine.name, count.index + 1])
  location            = var.location
  resource_group_name = var.resource_group_name == "" ? module.naming.resource_group.name : var.resource_group_name
  network_interface_ids = var.fortigate_vnet_config.ha_sync_subnet_address_space != "" ? [
    azurerm_network_interface.publicinterface[count.index].id,
    azurerm_network_interface.privateinterface[count.index].id,
    azurerm_network_interface.syncinterface[count.index].id,
    azurerm_network_interface.managementinterface[count.index].id
    ] : [
    azurerm_network_interface.publicinterface[count.index].id,
    azurerm_network_interface.privateinterface[count.index].id,
    azurerm_network_interface.managementinterface[count.index].id
  ]
  primary_network_interface_id = azurerm_network_interface.publicinterface[count.index].id
  vm_size                      = var.vm_size

  zones               = length(var.availability_zones) > 0 ? var.availability_zones : null
  availability_set_id = var.deploy_availability_set ? azurerm_availability_set.av[0].id : null

  depends_on = [azurerm_storage_account.fortinetstorageaccount, azurerm_marketplace_agreement.fortinet]

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
    name              = join("-", [join("-", [module.naming.linux_virtual_machine.name, count.index + 1]), "osdisk"])
    caching           = "ReadWrite"
    managed_disk_type = "Standard_LRS"
    create_option     = "FromImage"
  }

  delete_os_disk_on_termination = true

  # Log data disks
  storage_data_disk {
    name              = join("-", [join("-", [module.naming.linux_virtual_machine.name, count.index + 1]), "datadisk"])
    managed_disk_type = "Standard_LRS"
    create_option     = "Empty"
    lun               = 0
    disk_size_gb      = "30"
  }

  delete_data_disks_on_termination = true

  os_profile {
    computer_name  = join("-", [module.naming.linux_virtual_machine.name, count.index + 1])
    admin_username = var.adminusername
    admin_password = var.adminpassword
    custom_data = var.skip_config ? null : templatefile(local.templatefilename, {
      type                = var.license_type
      license_file        = var.license_file
      syncPort_ip         = var.fortigate_vnet_config.ha_sync_subnet_address_space != "" ? azurerm_network_interface.syncinterface[count.index].ip_configuration[0].private_ip_address : ""
      syncPort_mask       = var.fortigate_vnet_config.ha_sync_subnet_address_space != "" ? cidrnetmask(var.fortigate_vnet_config.ha_sync_subnet_address_space) : ""
      managementPort_ip   = azurerm_network_interface.managementinterface[count.index].ip_configuration[0].private_ip_address
      managementPort_mask = cidrnetmask(var.fortigate_vnet_config.ha_mgmt_subnet_address_space)
      publicPort_ip       = azurerm_network_interface.publicinterface[count.index].ip_configuration[0].private_ip_address
      publicPort_mask     = cidrnetmask(var.fortigate_vnet_config.public_subnet_address_space)
      privatePort_ip      = azurerm_network_interface.privateinterface[count.index].ip_configuration[0].private_ip_address
      privatePort_mask    = cidrnetmask(var.fortigate_vnet_config.private_subnet_address_space)
      peerip              = count.index == 0 ? (var.fortigate_vnet_config.ha_sync_subnet_address_space != "" ? azurerm_network_interface.syncinterface[1].ip_configuration[0].private_ip_address : azurerm_network_interface.managementinterface[1].ip_configuration[0].private_ip_address) : (var.fortigate_vnet_config.ha_sync_subnet_address_space != "" ? azurerm_network_interface.syncinterface[0].ip_configuration[0].private_ip_address : azurerm_network_interface.managementinterface[0].ip_configuration[0].private_ip_address)
      peerPrio            = count.index == 0 ? 255 : 1
      mgmt_gateway_ip     = cidrhost(var.fortigate_vnet_config.ha_mgmt_subnet_address_space, 1)
      default_gateway     = cidrhost(var.fortigate_vnet_config.public_subnet_address_space, 1)
      tenant              = var.tenant_id
      subscription        = var.subscription_id
      clientid            = var.client_id
      clientsecret        = var.client_secret
      adminsport          = var.fortigate_admin_port
      resourcegroup       = var.resource_group_name == "" ? module.naming.resource_group.name : var.resource_group_name
      clusterip           = azurerm_public_ip.ClusterPublicIP.name
      routename           = azurerm_route_table.internal.name
      hostname            = join("-", [module.naming.linux_virtual_machine.name, count.index + 1])
    })
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
  resource_group_name = var.resource_group_name == "" ? module.naming.resource_group.name : var.resource_group_name
}

resource "azurerm_subnet" "publicsubnet" {
  count                = var.existing_resource_ids.public_subnet_id == "" ? 1 : 0
  name                 = var.fortigate_vnet_config.public_subnet_name == "" ? join("-", [module.naming.subnet.name, "public"]) : var.fortigate_vnet_config.public_subnet_name
  resource_group_name  = var.resource_group_name == "" ? module.naming.resource_group.name : var.resource_group_name
  virtual_network_name = local.vnet_name
  address_prefixes     = [var.fortigate_vnet_config.public_subnet_address_space]
}

resource "azurerm_subnet" "privatesubnet" {
  count                = var.existing_resource_ids.private_subnet_id == "" ? 1 : 0
  name                 = var.fortigate_vnet_config.private_subnet_name == "" ? join("-", [module.naming.subnet.name, "private"]) : var.fortigate_vnet_config.private_subnet_name
  resource_group_name  = var.resource_group_name == "" ? module.naming.resource_group.name : var.resource_group_name
  virtual_network_name = local.vnet_name
  address_prefixes     = [var.fortigate_vnet_config.private_subnet_address_space]
}

resource "azurerm_subnet" "hamgmtsubnet" {
  count                = var.existing_resource_ids.ha_mgmt_subnet_id == "" ? 1 : 0
  name                 = var.fortigate_vnet_config.ha_mgmt_subnet_name == "" ? join("-", [module.naming.subnet.name, "hamgmt"]) : var.fortigate_vnet_config.ha_mgmt_subnet_name
  resource_group_name  = var.resource_group_name == "" ? module.naming.resource_group.name : var.resource_group_name
  virtual_network_name = local.vnet_name
  address_prefixes     = [var.fortigate_vnet_config.ha_mgmt_subnet_address_space]
}

resource "azurerm_subnet" "hasyncsubnet" {
  count                = var.existing_resource_ids.ha_sync_subnet_id == "" ? 1 : 0
  name                 = var.fortigate_vnet_config.ha_sync_subnet_name == "" ? join("-", [module.naming.subnet.name, "hasync"]) : var.fortigate_vnet_config.ha_sync_subnet_name
  resource_group_name  = var.resource_group_name == "" ? module.naming.resource_group.name : var.resource_group_name
  virtual_network_name = local.vnet_name
  address_prefixes     = [var.fortigate_vnet_config.ha_sync_subnet_address_space]
}

// Allocated Public IP
resource "azurerm_public_ip" "ClusterPublicIP" {
  name                = join("-", [module.naming.public_ip.name, "cluster"])
  location            = var.location
  resource_group_name = var.resource_group_name == "" ? module.naming.resource_group.name : var.resource_group_name
  sku                 = "Standard"
  allocation_method   = "Static"
}

resource "azurerm_public_ip" "mgmtip" {
  count               = 2
  name                = join("-", [module.naming.public_ip.name, "ha-mgmt", count.index + 1])
  location            = var.location
  resource_group_name = var.resource_group_name == "" ? module.naming.resource_group.name : var.resource_group_name
  sku                 = "Standard"
  allocation_method   = "Static"
}

//  Network Security Group
resource "azurerm_network_security_group" "publicnetworknsg" {
  name                = join("-", [module.naming.network_security_group.name, "public"])
  location            = var.location
  resource_group_name = var.resource_group_name == "" ? module.naming.resource_group.name : var.resource_group_name

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
  resource_group_name = var.resource_group_name == "" ? module.naming.resource_group.name : var.resource_group_name

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
  resource_group_name         = var.resource_group_name == "" ? module.naming.resource_group.name : var.resource_group_name
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
  resource_group_name         = var.resource_group_name == "" ? module.naming.resource_group.name : var.resource_group_name
  network_security_group_name = azurerm_network_security_group.privatenetworknsg.name
}

resource "azurerm_network_interface" "managementinterface" {
  count                         = 2
  name                          = join("-", [module.naming.network_interface.name, "ha-mgmt", count.index + 1])
  location                      = var.location
  resource_group_name           = var.resource_group_name == "" ? module.naming.resource_group.name : var.resource_group_name
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

resource "azurerm_network_interface" "syncinterface" {
  count                         = var.fortigate_vnet_config.ha_sync_subnet_address_space != "" ? 2 : 0
  name                          = join("-", [module.naming.network_interface.name, "ha-sync", count.index + 1])
  location                      = var.location
  resource_group_name           = var.resource_group_name == "" ? module.naming.resource_group.name : var.resource_group_name
  enable_accelerated_networking = var.use_accelerated_networking

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = var.existing_resource_ids.ha_sync_subnet_id == "" ? azurerm_subnet.hasyncsubnet[0].id : var.existing_resource_ids.ha_sync_subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = cidrhost(var.fortigate_vnet_config.ha_sync_subnet_address_space, (count.index + 4))
    primary                       = true
  }
}

resource "azurerm_network_interface" "publicinterface" {
  count                         = 2
  name                          = join("-", [module.naming.network_interface.name, "public", count.index + 1])
  location                      = var.location
  resource_group_name           = var.resource_group_name == "" ? module.naming.resource_group.name : var.resource_group_name
  enable_ip_forwarding          = true
  enable_accelerated_networking = var.use_accelerated_networking

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = var.existing_resource_ids.public_subnet_id == "" ? azurerm_subnet.publicsubnet[0].id : var.existing_resource_ids.public_subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = cidrhost(var.fortigate_vnet_config.public_subnet_address_space, (count.index + 4))
    public_ip_address_id          = var.deploy_load_balancer == false && count.index == 0 ? azurerm_public_ip.ClusterPublicIP.id : null
  }
}

resource "azurerm_network_interface" "privateinterface" {
  count                         = 2
  name                          = join("-", [module.naming.network_interface.name, "private", count.index + 1])
  location                      = var.location
  resource_group_name           = var.resource_group_name == "" ? module.naming.resource_group.name : var.resource_group_name
  enable_ip_forwarding          = true
  enable_accelerated_networking = var.use_accelerated_networking

  ip_configuration {
    name                          = "ipconfig1"
    subnet_id                     = var.existing_resource_ids.private_subnet_id == "" ? azurerm_subnet.privatesubnet[0].id : var.existing_resource_ids.private_subnet_id
    private_ip_address_allocation = "Static"
    private_ip_address            = cidrhost(var.fortigate_vnet_config.private_subnet_address_space, (count.index + 5))
  }

}

# Connect the security group to the network interfaces
resource "azurerm_network_interface_security_group_association" "managementPortnsg" {
  count                     = 2
  depends_on                = [azurerm_network_interface.managementinterface]
  network_interface_id      = azurerm_network_interface.managementinterface[count.index].id
  network_security_group_id = azurerm_network_security_group.publicnetworknsg.id
}

# Connect the security group to the network interfaces
resource "azurerm_network_interface_security_group_association" "syncPortnsg" {
  count                     = var.fortigate_vnet_config.ha_sync_subnet_address_space != "" ? 2 : 0
  depends_on                = [azurerm_network_interface.syncinterface]
  network_interface_id      = azurerm_network_interface.syncinterface[count.index].id
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
  resource_group_name = var.resource_group_name == "" ? module.naming.resource_group.name : var.resource_group_name
}

resource "azurerm_route" "default" {
  depends_on          = [azurerm_virtual_machine.fortinetvm]
  name                = "default"
  resource_group_name = var.resource_group_name == "" ? module.naming.resource_group.name : var.resource_group_name
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

resource "azurerm_lb" "internal" {
  count               = var.deploy_load_balancer ? 1 : 0
  name                = join("-", [module.naming.lb.name, "internal"])
  resource_group_name = var.resource_group_name == "" ? module.naming.resource_group.name : var.resource_group_name
  location            = var.location

  sku      = "Standard"
  sku_tier = "Regional"

  frontend_ip_configuration {
    private_ip_address            = cidrhost(var.fortigate_vnet_config.private_subnet_address_space, 4)
    private_ip_address_allocation = "Static"
    name                          = join("-", [join("-", [module.naming.lb.name, "internal"]), "frontend"])
    subnet_id                     = var.existing_resource_ids.private_subnet_id == "" ? azurerm_subnet.privatesubnet[0].id : var.existing_resource_ids.private_subnet_id
  }
}

resource "azurerm_lb" "external" {
  count               = var.deploy_load_balancer ? 1 : 0
  name                = join("-", [module.naming.lb.name, "external"])
  resource_group_name = var.resource_group_name == "" ? module.naming.resource_group.name : var.resource_group_name
  location            = var.location

  sku      = "Standard"
  sku_tier = "Regional"

  frontend_ip_configuration {
    public_ip_address_id = azurerm_public_ip.ClusterPublicIP.id
    name                 = join("-", [join("-", [module.naming.lb.name, "external"]), "frontend"])
  }
}

resource "azurerm_lb_backend_address_pool" "internal" {
  count           = var.deploy_load_balancer ? 1 : 0
  name            = join("-", [module.naming.lb.name, "internal", "pool"])
  loadbalancer_id = azurerm_lb.internal[0].id
}

resource "azurerm_lb_backend_address_pool" "external" {
  count           = var.deploy_load_balancer ? 1 : 0
  name            = join("-", [module.naming.lb.name, "external", "pool"])
  loadbalancer_id = azurerm_lb.external[0].id
}

resource "azurerm_network_interface_backend_address_pool_association" "internal" {
  depends_on              = [azurerm_virtual_machine.fortinetvm]
  count                   = var.deploy_load_balancer ? 2 : 0
  network_interface_id    = azurerm_network_interface.privateinterface[count.index].id
  ip_configuration_name   = "ipconfig1"
  backend_address_pool_id = azurerm_lb_backend_address_pool.internal[0].id
}

resource "azurerm_network_interface_backend_address_pool_association" "external" {
  depends_on              = [azurerm_virtual_machine.fortinetvm]
  count                   = var.deploy_load_balancer ? 2 : 0
  network_interface_id    = azurerm_network_interface.publicinterface[count.index].id
  ip_configuration_name   = "ipconfig1"
  backend_address_pool_id = azurerm_lb_backend_address_pool.external[0].id
}

resource "azurerm_lb_probe" "port_8008_internal" {
  count           = var.deploy_load_balancer ? 1 : 0
  loadbalancer_id = azurerm_lb.internal[0].id
  name            = "port_8008"
  port            = 8008
}

resource "azurerm_lb_probe" "port_8008_external" {
  count           = var.deploy_load_balancer ? 1 : 0
  loadbalancer_id = azurerm_lb.external[0].id
  name            = "port_8008"
  port            = 8008
}

resource "azurerm_lb_rule" "port_80_external" {
  count                          = var.deploy_load_balancer ? 1 : 0
  loadbalancer_id                = azurerm_lb.external[0].id
  name                           = "tcp-80"
  protocol                       = "Tcp"
  frontend_port                  = 80
  backend_port                   = 80
  frontend_ip_configuration_name = azurerm_lb.external[0].frontend_ip_configuration[0].name
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.external[0].id]
  probe_id                       = azurerm_lb_probe.port_8008_external[0].id
  enable_floating_ip             = true
  disable_outbound_snat          = true
  idle_timeout_in_minutes        = 5
  enable_tcp_reset               = false
}

resource "azurerm_lb_rule" "port_10551_external" {
  count                          = var.deploy_load_balancer ? 1 : 0
  loadbalancer_id                = azurerm_lb.external[0].id
  name                           = "udp-10551"
  protocol                       = "Udp"
  frontend_port                  = 10551
  backend_port                   = 10551
  frontend_ip_configuration_name = azurerm_lb.external[0].frontend_ip_configuration[0].name
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.external[0].id]
  probe_id                       = azurerm_lb_probe.port_8008_external[0].id
  enable_floating_ip             = true
  disable_outbound_snat          = true
}

resource "azurerm_lb_rule" "port_500_external" {
  count                          = var.deploy_load_balancer ? 1 : 0
  loadbalancer_id                = azurerm_lb.external[0].id
  name                           = "udp-500"
  protocol                       = "Udp"
  frontend_port                  = 500
  backend_port                   = 500
  frontend_ip_configuration_name = azurerm_lb.external[0].frontend_ip_configuration[0].name
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.external[0].id]
  probe_id                       = azurerm_lb_probe.port_8008_external[0].id
  enable_floating_ip             = true
  disable_outbound_snat          = true
}

resource "azurerm_lb_rule" "port_4500_external" {
  count                          = var.deploy_load_balancer ? 1 : 0
  loadbalancer_id                = azurerm_lb.external[0].id
  name                           = "udp-4500"
  protocol                       = "Udp"
  frontend_port                  = 4500
  backend_port                   = 4500
  frontend_ip_configuration_name = azurerm_lb.external[0].frontend_ip_configuration[0].name
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.external[0].id]
  probe_id                       = azurerm_lb_probe.port_8008_external[0].id
  enable_floating_ip             = true
  disable_outbound_snat          = true
}

resource "azurerm_lb_rule" "all_internal" {
  count                          = var.deploy_load_balancer ? 1 : 0
  loadbalancer_id                = azurerm_lb.internal[0].id
  name                           = "all"
  protocol                       = "All"
  frontend_port                  = 0 # High available ports
  backend_port                   = 0 # High available ports
  frontend_ip_configuration_name = azurerm_lb.internal[0].frontend_ip_configuration[0].name
  backend_address_pool_ids       = [azurerm_lb_backend_address_pool.internal[0].id]
  probe_id                       = azurerm_lb_probe.port_8008_internal[0].id
  enable_floating_ip             = true
  idle_timeout_in_minutes        = 5
  enable_tcp_reset               = false
}
