terraform {
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "3.82.0"
    }
  }
}

module "naming" {
  source  = "Azure/naming/azurerm"
  suffix  = var.resource_suffix
  version = "0.4.0"
}
