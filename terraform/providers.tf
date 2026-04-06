# Auth0 provider authenticates via environment variables.
# https://github.com/auth0/terraform-provider-auth0/blob/main/docs/index.md
#
# Required env vars (set by pipeline from variable group):
#   AUTH0_DOMAIN
#   AUTH0_CLIENT_ID
#   AUTH0_CLIENT_SECRET
provider "auth0" {}
