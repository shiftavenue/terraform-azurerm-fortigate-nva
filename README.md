# Terraform Module to deploy Fortinet Fortigate Marketplace VM

If you don't like how the official samples are cobbled together or you
would like to integrate your NVA into your corporate naming scheme (within reason),
give this module a try.

Azure/naming/azurerm is used to generate resource names. A default HA configuration
is provided as custom data to each HA partner VM. You can opt out of automatic configuration
and do everything manually of course. The automatic configuration follows Fortinet's best
practices as outlined in their sample code.

Pull Requests are very welcome!

## Using your own configuration export

Good news! Using your exported configuration is no problem if your general structure
fits to whatever is deployed. Take good care to replace all placeholders with `$${}`
and `%%{}` respectively. Fortinet uses these on several occasions themselves, and
they would clash with this modules' replacements.

So what can you actually use as a placeholder with `${nameOfPlacehodler}`?

- type: License type, will be either PAYG or BYOL.
- license_file: Will be file path to your license file if BYOL is used.
- syncPort_ip: IP Address of the HASync port
- syncPort_mask: Subnet mask of the HASync port
- managementPort_ip: IP Address of the HAManagement port
- managementPort_mask: Subnet mask of the HAManagement port
- publicPort_ip: IP Address of the external or public port
- publicPort_mask: Subnet mask of the external or public port
- privatePort_ip: IP Address of the internal or private port
- privatePort_mask: Subnet mask of the internal or private port
- peerip: Will contain the IP address of the peer's HAMgmt or HASync interface, depending on your configuration
- peerPrio: Will contain 1 for the primary and 255 for the seconday node
- mgmt_gateway_ip: IP with last octet 1 in the management subnet
- default_gateway: IP with last octet 1 in the public subnet
- tenant: The Entra ID tenant ID for Azure SDN
- subscription: The subscription ID for Azure SDN
- clientid: Principal ID of the user-assigned managed identity or app registration
- clientsecret: Client secret of the user-assigned managed identity or app registration
- adminsport: FortiGate admin port number
- resourcegroup: Resource group name
- clusterip: Public IP address of the cluster (that is: the external load balancer)
- clusterName: Name of the cluster
- routename: Name of the internal route table's route
- hostname: Node name of each VM

## Example

A sample configuration could look like this, assuming the default network
and subnet configuration is acceptable:

```hcl
module "nva" {
  source  = "azurerm/fortigate/nva"
  version = "1.1.0"
  location = "westeurope"
}
```

or this, if some customization is required:

```hcl
module "nva" {
  source  = "azurerm/fortigate/nva"
  version = "1.1.0"
  location = "westeurope"
  fortigate_vnet_config = {
    vnet_address_space           = "10.0.0.0/16"
    public_subnet_address_space  = "10.0.0.0/24"
    private_subnet_address_space = "10.0.1.0/24"
    ha_mgmt_subnet_address_space = "10.0.3.0/24"
    ha_mgmt_gateway_address      = "10.0.3.1"
    public_gateway_address       = "10.0.0.1"
  }
}
```

The appliance even integrates into existing networks, in which case take
extra care of the address space and naming! For an existing network called
vnet-hub-corp with enough space left for all required subnets, the configuration
could look like this.

Provided that the network is already in the desired state, only the subnets
will be added.

```hcl
module "nva" {
  source  = "azurerm/fortigate/nva"
  version = "1.1.0"
  location = "westeurope"
  fortigate_vnet_config = {
    vnet_address_space           = "10.0.0.0/16"
    vnet_name                    = "vnet-hub-corp"
    public_subnet_address_space  = "10.0.5.0/24"
    private_subnet_address_space = "10.0.6.0/24"
    ha_mgmt_subnet_address_space = "10.0.8.0/24"
    ha_mgmt_gateway_address      = "10.0.8.1"
    public_gateway_address       = "10.0.5.1"
  }
}
```