# Root module — composes child modules in dependency order.
#
# Environment config is loaded from manifests/environments/{env}.yaml.
# Resource manifests reference keys from env_config for env-specific values.

locals {
  env_config     = yamldecode(file("${path.module}/manifests/environments/${var.environment}.yaml"))
  clients        = yamldecode(file("${path.module}/manifests/clients.yaml"))["clients"]
  actions        = yamldecode(file("${path.module}/manifests/actions.yaml"))["actions"]
  action_modules = yamldecode(file("${path.module}/manifests/action_modules.yaml"))["action_modules"]
  flows_manifest = yamldecode(file("${path.module}/manifests/flows.yaml"))
  vault_conns    = local.flows_manifest["vault_connections"]
  flows          = local.flows_manifest["flows"]
}

# 1. Vault connections
module "vault_connections" {
  source      = "./modules/vault_connections"
  definitions = local.vault_conns
  secrets     = local.secrets
  env_config  = local.env_config
}

# 2. Action modules
module "action_modules" {
  source      = "./modules/action_modules"
  definitions = local.action_modules
  secrets     = local.secrets
  env_config  = local.env_config
  environment = var.environment
}

# 3. Actions (depends on action_modules)
module "actions" {
  source                = "./modules/actions"
  definitions           = local.actions
  secrets               = local.secrets
  env_config            = local.env_config
  environment           = var.environment
  action_module_outputs = module.action_modules.module_map
}

# 4. Flows (depends on vault_connections)
module "flows" {
  source                   = "./modules/flows"
  definitions              = local.flows
  environment              = var.environment
  vault_connection_outputs = module.vault_connections.connection_map
}

# 5. Forms (depends on flows + vault_connections)
module "forms" {
  source                   = "./modules/forms"
  definitions              = local.flows_manifest
  environment              = var.environment
  flow_outputs             = module.flows.flow_map
  vault_connection_outputs = module.vault_connections.connection_map
}

# 6. Clients (independent)
module "clients" {
  source      = "./modules/clients"
  definitions = local.clients
  env_config  = local.env_config
  environment = var.environment
}
