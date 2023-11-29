# Terraform Module to deploy Fortinet Fortigate Marketplace VM

If you don't like how the official samples are cobbled together or you
would like to integrate your NVA into your corporate naming scheme (within reason),
give this module a try.

Azure/naming/azurerm is used to generate resource names. A default HA configuration
is provided as custom data to each HA partner VM. You can opt out of automatic configuration
and do everything manually of course. The automatic configuration follows Fortinet's best
practices as outlined in their sample code.

Pull Requests are very welcome!

## Example

A sample configuration could look like this:

```hcl
module "nva" {
  source  = "azurerm/fortigate/nva"
  version = "0.1.0"
  location = "westeurope"
}
```

or this, if some customization is required:

```hcl
module "nva" {
  source  = "azurerm/fortigate/nva"
  version = "0.1.0"
  location = "westeurope"
  fortigate_vnet_config = {
    vnet_address_space           = "10.0.0.0/16"
    public_subnet_address_space  = "10.0.0.0/24"
    private_subnet_address_space = "10.0.1.0/24"
    ha_sync_subnet_address_space = "10.0.2.0/24"
    ha_mgmt_subnet_address_space = "10.0.3.0/24"
    ha_mgmt_gateway_address      = "10.0.3.1"
    public_gateway_address       = "10.0.0.1"
  }
}
```