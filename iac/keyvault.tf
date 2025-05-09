module "keyvault" {
  source  = "Azure/avm-res-keyvault-vault/azurerm"
  version = "0.10.0"

  name                = local.keyvault_name
  location            = local.location
  resource_group_name = local.resource_group_name
  tenant_id           = data.azurerm_client_config.current.tenant_id

  sku_name                 = "standard"
  purge_protection_enabled = false

  role_assignments = {
    "kvadmin" = {
      principal_id               = azuread_group.keyvault_secret_users.object_id
      role_definition_id_or_name = "Key Vault Secrets User"
    }
  }

  tags = local.default_tags
}

resource "azuread_group" "keyvault_secret_users" {
  display_name     = "azg-${local.keyvault_name}-secret-user"
  description      = "Key Vault access group for ${local.keyvault_name}"
  members          = [data.azurerm_client_config.current.object_id, data.azuread_user.jane.object_id]
  security_enabled = true
}

data "azuread_user" "jane" {
  user_principal_name = "jane@kewalaka.nz"
}
