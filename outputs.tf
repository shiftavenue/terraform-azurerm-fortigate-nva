output "ClusterPublicIP" {
  value = azurerm_public_ip.ClusterPublicIP.ip_address
}

output "ActiveManagementPublicIP" {
  value = azurerm_public_ip.mgmtip[0].ip_address
}


output "PassiveManagementPublicIP" {
  value = azurerm_public_ip.mgmtip[1].ip_address
}

output "LicenseTerms" {
  value = jsondecode(data.external.term_acceptance.result)
}