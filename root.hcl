# =============================================================================
# Terragrunt root configuration
# =============================================================================
# Single source of truth for provider, backend, and common inputs.
# All catalog units inherit this via include "root".
#
# Backend: AWS S3 with native lockfile support
# Provider: Auth0 (credentials via AUTH0_DOMAIN, AUTH0_CLIENT_ID,
#           AUTH0_CLIENT_SECRET environment variables)
# =============================================================================

locals {
  # When running under a stack, env.hcl is in the environment directory.
  # We use find_in_parent_folders which traverses up from the generated unit.
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
          version = "~> 1.14"
        }
      }
    }

    provider "auth0" {}
  EOF
}

remote_state {
  backend = "s3"

  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }

  config = {
    bucket         = get_env("TF_STATE_BUCKET", "")
    key            = "${local.environment}/${replace(path_relative_to_include(), "\\", "/")}/terraform.tfstate"
    region         = get_env("AWS_DEFAULT_REGION", "us-east-1")
    encrypt        = true
    use_lockfile   = true
  }
}

inputs = {
  environment = local.environment
}
