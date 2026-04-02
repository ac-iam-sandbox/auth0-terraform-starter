# =============================================================================
# Terragrunt root configuration
# =============================================================================
# Single source of truth for provider, backend, and common inputs.
# All catalog units inherit this via include "root".
#
# Backend: Azure Blob Storage with Azure AD auth (no storage keys)
# Provider: Auth0 (credentials via AUTH0_DOMAIN, AUTH0_CLIENT_ID,
#           AUTH0_CLIENT_SECRET environment variables)
# =============================================================================

locals {
  env_config  = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment = local.env_config.locals.environment
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    terraform {
      required_version = ">= 1.5.0"

      required_providers {
        auth0 = {
          source  = "auth0/auth0"
          version = "~> 1.14.0"
        }
      }
    }

    provider "auth0" {}
  EOF
}

remote_state {
  backend = "azurerm"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    resource_group_name  = get_env("ARM_RESOURCE_GROUP", "")
    storage_account_name = get_env("ARM_STORAGE_ACCOUNT", "saauth0tf01")
    container_name       = get_env("ARM_CONTAINER_NAME", "tfstate")
    key                  = "${local.environment}/${replace(path_relative_to_include(), "\\", "/")}/terraform.tfstate"

    tenant_id       = get_env("ARM_TENANT_ID", "")
    subscription_id = get_env("ARM_SUBSCRIPTION_ID", "")

    # Azure commercial cloud (not government)
    # Change to "usgovernment" if using Azure Government
    environment = "public"

    use_cli          = true
    use_azuread_auth = true
  }
}

inputs = {
  environment = local.environment

  tags = {
    Environment = local.environment
    ManagedBy   = "terragrunt"
    Repository  = "auth0-iac"
  }
}
