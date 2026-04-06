terraform {
  required_version = ">= 1.10.0"

  required_providers {
    # https://registry.terraform.io/providers/auth0/auth0/latest
    auth0 = {
      source  = "auth0/auth0"
      version = "~> 1.41"
    }
  }

  # https://developer.hashicorp.com/terraform/language/backend/s3
  # Partial config — completed via -backend-config flag at init.
  backend "s3" {}
}
