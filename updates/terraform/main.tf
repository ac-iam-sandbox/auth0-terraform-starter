# Root module
#
# Dependency chain:
#   clients → client_grants → email_provider (action needs client + grant)
#   tenant, attack_protection, guardian, log_streams (independent singletons)

locals {
  region_config  = yamldecode(file("${path.module}/manifests/regions/${var.region}/${var.environment}.yaml"))
  clients        = yamldecode(file("${path.module}/manifests/clients.yaml"))["clients"]
  client_grants  = yamldecode(file("${path.module}/manifests/client_grants.yaml"))["client_grants"]
  log_streams    = yamldecode(file("${path.module}/manifests/log_streams.yaml"))["log_streams"]
  attack_prot    = yamldecode(file("${path.module}/manifests/attack_protection.yaml"))["attack_protection"]
  email_provider = yamldecode(file("${path.module}/manifests/email_provider.yaml"))["email_provider"]
  guardian       = yamldecode(file("${path.module}/manifests/guardian.yaml"))["guardian"]
  tenant         = yamldecode(file("${path.module}/manifests/tenant.yaml"))["tenant"]
}

# ── Data source: resolve the tenant's Management API identifier automatically ──
data "auth0_tenant" "current" {}

# 1. Tenant settings (singleton)
module "tenant" {
  source     = "./modules/tenant"
  definition = local.tenant
  env_config = lookup(local.region_config, "tenant", {})
}

# 2. Attack protection (singleton)
module "attack_protection" {
  source     = "./modules/attack_protection"
  definition = local.attack_prot
}

# 3. Guardian MFA (singleton)
module "guardian" {
  source     = "./modules/guardian"
  definition = local.guardian
  env_config = lookup(local.region_config, "guardian", {})
}

# 4. M2M Clients (multi-instance, region+env filtered)
module "clients" {
  source      = "./modules/clients"
  definitions = local.clients
  region      = var.region
  environment = var.environment
}

# 5. Client grants (depends on clients)
module "client_grants" {
  source                    = "./modules/client_grants"
  definitions               = local.client_grants
  region                    = var.region
  environment               = var.environment
  client_ids                = module.clients.client_map
  management_api_identifier = data.auth0_tenant.current.management_api_identifier
}

# 6. Email provider (depends on clients + client_grants)
#    When name="custom", creates an auth0_action as a prerequisite.
#    AUTH0_DOMAIN is auto-injected from tenant — no env YAML duplication.
#    AUTH0_CLIENT_ID and AUTH0_CLIENT_SECRET resolved via client_refs.
module "email_provider" {
  source         = "./modules/email_provider"
  definition     = local.email_provider
  secrets        = local.secrets
  env_config     = lookup(local.region_config, "email_provider", {})
  tenant_domain  = data.auth0_tenant.current.domain
  client_ids     = module.clients.client_map
  client_secrets = module.clients.client_secret_map

  depends_on = [module.client_grants]
}

# 7. Log streams (multi-instance, region+env filtered)
module "log_streams" {
  source      = "./modules/log_streams"
  definitions = local.log_streams
  secrets     = local.secrets
  env_config  = lookup(local.region_config, "log_streams", {})
  region      = var.region
  environment = var.environment
}
