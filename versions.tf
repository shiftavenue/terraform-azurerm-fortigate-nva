terraform {
  required_version = ">=1.6.5"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">=3.82.0"
    }
    template = {
      source  = "hashicorp/template"
      version = ">=2.2.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">=3.5.1"
    }
  }
}

module "naming" {
  source  = "Azure/naming/azurerm"
  suffix  = var.resource_suffix
  version = ">=0.4.0"
}
