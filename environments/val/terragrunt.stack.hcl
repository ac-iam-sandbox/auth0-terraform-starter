# =============================================================================
# Stack: val (validation / pre-production)
# =============================================================================
# Manages: Applications, Actions, Forms, Flows, Vault Connections
# Does NOT manage: APIs, Connections, Branding, Tenant, Attack Protection
# (those are managed by the platform team's repo)
#
# To deploy:  cd environments/val && terragrunt run --all -- apply
# To plan:    cd environments/val && terragrunt run --all -- plan
# =============================================================================

locals {
  env              = "val"
  applications     = jsondecode(file("${get_terragrunt_dir()}/applications.json"))
  actions_cfg      = jsondecode(file("${get_terragrunt_dir()}/actions.json"))
  vault_conns_cfg  = jsondecode(file("${get_terragrunt_dir()}/vault-connections.json"))
  flows_cfg        = jsondecode(file("${get_terragrunt_dir()}/flows.json"))
  forms_cfg        = jsondecode(file("${get_terragrunt_dir()}/forms.json"))
}

# -----------------------------------------------------------------------------
# Applications (data-driven from applications.json)
# -----------------------------------------------------------------------------
unit "applications" {
  source = "${get_repo_root()}/catalog/units/applications"
  path   = "applications"
  no_dot_terragrunt_stack = true

  values = {
    applications = local.applications
  }
}

# -----------------------------------------------------------------------------
# Actions (compiled JS read from per-env actions/ directory)
# -----------------------------------------------------------------------------
unit "actions" {
  source = "${get_repo_root()}/catalog/units/actions"
  path   = "actions"
  no_dot_terragrunt_stack = true

  values = {
    actions = {
      for k, v in local.actions_cfg : k => merge(v, {
        code = file("${get_terragrunt_dir()}/actions/${v.code_file}")
      })
    }
  }
}

# -----------------------------------------------------------------------------
# Vault Connections (secrets injected via pipeline variable groups)
# -----------------------------------------------------------------------------
unit "vault-connections" {
  source = "${get_repo_root()}/catalog/units/vault-connections"
  path   = "vault-connections"
  no_dot_terragrunt_stack = true

  values = {
    vault_connections = local.vault_conns_cfg
  }
}

# -----------------------------------------------------------------------------
# Flows (JSON read from per-env forms/ directory)
# -----------------------------------------------------------------------------
unit "flows" {
  source = "${get_repo_root()}/catalog/units/flows"
  path   = "flows"
  no_dot_terragrunt_stack = true

  values = {
    flows = {
      for k, v in local.flows_cfg : k => {
        name         = v.name
        actions_json = file("${get_terragrunt_dir()}/${v.file}")
      }
    }
  }
}

# -----------------------------------------------------------------------------
# Forms (exported JSON read from per-env forms/ directory)
# -----------------------------------------------------------------------------
unit "forms" {
  source = "${get_repo_root()}/catalog/units/forms"
  path   = "forms"
  no_dot_terragrunt_stack = true

  values = {
    forms = {
      for k, v in local.forms_cfg : k => {
        name              = v.name
        start_json        = jsonencode(jsondecode(file("${get_terragrunt_dir()}/${v.file}"))["start"])
        nodes_json        = jsonencode(jsondecode(file("${get_terragrunt_dir()}/${v.file}"))["nodes"])
        ending_json       = jsonencode(jsondecode(file("${get_terragrunt_dir()}/${v.file}"))["ending"])
        style_json        = try(jsonencode(jsondecode(file("${get_terragrunt_dir()}/${v.file}"))["style"]), null)
        translations_json = try(jsonencode(jsondecode(file("${get_terragrunt_dir()}/${v.file}"))["translations"]), null)
        language_primary  = try(jsondecode(file("${get_terragrunt_dir()}/${v.file}"))["languages"]["primary"], "en")
        language_default  = try(jsondecode(file("${get_terragrunt_dir()}/${v.file}"))["languages"]["default"], "en")
      }
    }
  }
}
