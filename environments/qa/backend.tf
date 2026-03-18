# ========================================
# Terraform Backend Configuration (QA)
# ========================================
# Azure Backend with Environment Variables
# The following will be provided via -backend-config flags from variable groups:
# - resource_group_name
# - storage_account_name
# - container_name

terraform {
  backend "azurerm" {
    key = "auth0/qa/terraform.tfstate"
  }
}