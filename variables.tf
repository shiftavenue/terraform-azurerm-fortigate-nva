variable "subscription_id" {
  type        = string
  description = "Azure subscription ID"
}

variable "resource_suffix" {
  type        = list(string)
  description = "Suffix used with Azure Naming module"
  default     = ["fg", "nva"]
}

variable "location" {
  type        = string
  description = "Azure Region"
}

variable "license_type" {
  type        = string
  description = "Type of license to apply, either PAYG or BYOL. If BYOL is used, license_file must be set"
  default     = "payg"

  validation {
    condition     = contains(["payg", "byol"], var.license_type)
    error_message = "Valid values for license_type are (payg, byol)"
  }
}

variable "vm_publisher" {
  type        = string
  description = "Value of the publisher parameter for the FortiGate VM image"
  default     = "fortinet"
}

variable "vm_offer" {
  type        = string
  description = "Value of the offer parameter for the FortiGate VM image"
  default     = "fortinet_fortigate-vm_v5"
}

variable "vm_size" {
  type        = string
  description = "Size of the VM, needs to fit your desired Fortigate operating model, e.g. number of NICs"
  default     = "Standard_F4s"
}

variable "fgtsku" {
  type = map(any)
  default = {
    byol = "fortinet_fg-vm"
    payg = "fortinet_fg-vm_payg_2023"
  }
}

variable "fgtversion" {
  type    = string
  default = "7.4.0"
}

variable "availability_zones" {
  type        = list(number)
  description = "Availability zones to use for the FortiGate VMs"
  default     = []
}

variable "adminusername" {
  type    = string
  default = "fortiadmin"
}

variable "adminpassword" {
  type      = string
  sensitive = true
  default   = "Fortinet123#"
}

variable "resource_group_tags" {
  type     = map(string)
  default  = null
  nullable = true
}

variable "resource_group_name" {
  type        = string
  default     = ""
  description = "Resource group name. Specify if resource group name should not be auto-generated"
}

variable "allow_resource_group_creation" {
  type        = bool
  description = "Allow the module to create a resource group. If set to false, specify the name of an existing resource group in resource_group_name"
  default     = true
}

variable "allow_vnet_creation" {
  type        = bool
  description = "Allow the module to create a virtual network. If set to false, specify the name of an existing virtual network and the required subnets public, private and hamgmt in fortigate_vnet_config"
  default     = true
}

variable "skip_config" {
  type        = bool
  description = "Skip the configuration of the FortiGate"
  default     = false
}

variable "license_file" {
  type        = string
  description = "Path to the license file to use for BYOL"
  default     = ""
}

variable "fortigate_admin_port" {
  type        = number
  description = "Port to use for the admin interface"
  default     = 8443
}

variable "fortigate_vnet_config" {
  type = object({
    vnet_address_space           = string
    vnet_name                    = optional(string, "")
    public_subnet_address_space  = string
    public_subnet_name           = optional(string, "")
    private_subnet_address_space = string
    private_subnet_name          = optional(string, "")
    ha_mgmt_subnet_address_space = string
    ha_mgmt_subnet_name          = optional(string, "")
    ha_mgmt_gateway_address      = string
    public_gateway_address       = string
  })
  default = {
    vnet_address_space           = "172.1.0.0/16"
    public_subnet_address_space  = "172.1.0.0/24"
    private_subnet_address_space = "172.1.1.0/24"
    ha_mgmt_subnet_address_space = "172.1.3.0/24"
    ha_mgmt_gateway_address      = "172.1.3.1"
    public_gateway_address       = "172.1.0.1"
  }
}

variable "tenant_id" {
  type        = string
  default     = ""
  description = "If using an App Registration with a client secret, specify the tenant ID alongside subscription, client_id and client_secret"
}

variable "client_id" {
  type        = string
  default     = ""
  description = "If using an App Registration with a client secret, specify the client_id alongside subscription, tenant ID and client_secret"
}

variable "client_secret" {
  type        = string
  default     = ""
  description = "If using an App Registration with a client secret, specify the client_secret alongside subscription, client_id and tenant ID"
}

variable "use_accelerated_networking" {
  type        = bool
  description = "Use accelerated networking. Ensure that your VM size supports this feature."
  default     = true
}

variable "assign_managed_identity" {
  type        = bool
  description = "Assign a user-assigned managed identity to the FortiGate VM"
  default     = true
}
