# Auth0 provider authenticates via environment variables.
# https://registry.terraform.io/providers/auth0/auth0/latest/docs
#
# Required env vars (set by pipeline from variable group):
#   AUTH0_DOMAIN
#   AUTH0_CLIENT_ID
#   AUTH0_CLIENT_SECRET
provider "auth0" {}
