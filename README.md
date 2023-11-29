# Terraform Module to deploy Fortinet Fortigate Marketplace VM

If you don't like how the official samples are cobbled together or you
would like to integrate your NVA into your corporate naming scheme (within reason),
give this module a try.

Azure/naming/azurerm is used to generate resource names. A default HA configuration
is provided as custom data to each HA partner VM. You can opt out of automatic configuration
and do everything manually of course. The automatic configuration follows Fortinet's best
practices as outlined in their sample code.

Pull Requests are very welcome!
