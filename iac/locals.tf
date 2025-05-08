locals {
  appname              = "oidc-demo"
  short_appname        = local.appname # less than 14 characters to fit resource naming constraints
  default_suffix       = "${local.appname}-${var.env_code}"
  default_short_suffix = "${local.short_appname}${var.env_code}"

  # add resource names here, using CAF-aligned naming conventions
  resource_group_name = "rg-${local.default_suffix}"
  keyvault_name       = "kv${local.default_short_suffix}"

  location = data.azurerm_resource_group.parent.location

  default_tags = merge(
    var.default_tags,
    tomap({
      "Location"    = var.short_location_code
      "Environment" = var.env_code
    })
  )
}
