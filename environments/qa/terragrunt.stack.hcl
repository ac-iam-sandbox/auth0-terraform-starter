# =============================================================================
# Terragrunt Stack Definition (shared by all environments)
# =============================================================================
# This file is symlinked from each environments/{env}/ directory.
# It reads env.hcl from the environment directory to determine context.
#
# Manages: Applications, Actions, Action Modules, Forms, Flows, Vault Connections
# Does NOT manage: APIs, Connections, Branding, Tenant, Attack Protection
# (those are managed by the platform team's repo)
#
# To deploy:  cd environments/dev && terragrunt run --all -- apply
# To plan:    cd environments/dev && terragrunt run --all -- plan
# =============================================================================

locals {
  env_dir            = get_terragrunt_dir()
  env                = read_terragrunt_config("${local.env_dir}/env.hcl").locals.environment
  applications       = jsondecode(file("${local.env_dir}/applications.json"))
  actions_cfg        = jsondecode(file("${local.env_dir}/actions.json"))
  action_modules_cfg = try(jsondecode(file("${local.env_dir}/action-modules.json")), {})
  vault_conns_cfg    = jsondecode(file("${local.env_dir}/vault-connections.json"))
  flows_cfg          = jsondecode(file("${local.env_dir}/flows.json"))
  forms_cfg          = jsondecode(file("${local.env_dir}/forms.json"))

  # Parse each form file ONCE then reference fields
  forms_parsed = {
    for k, v in local.forms_cfg : k => jsondecode(file("${local.env_dir}/${v.file}"))
  }

  # -------------------------------------------------------------------------
  # Token replacement helper
  # -------------------------------------------------------------------------
  # Applies up to 5 chained replace() calls for a map of token→value pairs.
  # Uses "__noop_N__" as the search string when fewer than 5 tokens exist,
  # which will never match anything, making the replace() a no-op.
  # -------------------------------------------------------------------------

  # Resolve flow JSON with token replacements applied
  flows_resolved = {
    for k, v in local.flows_cfg : k => {
      name = v.name
      actions_json = replace(
        replace(
          replace(
            replace(
              replace(
                file("${local.env_dir}/${v.file}"),
                try(keys(try(v.token_replacements, {}))[0], "__noop_0__"),
                try(values(try(v.token_replacements, {}))[0], "")
              ),
              try(keys(try(v.token_replacements, {}))[1], "__noop_1__"),
              try(values(try(v.token_replacements, {}))[1], "")
            ),
            try(keys(try(v.token_replacements, {}))[2], "__noop_2__"),
            try(values(try(v.token_replacements, {}))[2], "")
          ),
          try(keys(try(v.token_replacements, {}))[3], "__noop_3__"),
          try(values(try(v.token_replacements, {}))[3], "")
        ),
        try(keys(try(v.token_replacements, {}))[4], "__noop_4__"),
        try(values(try(v.token_replacements, {}))[4], "")
      )
    }
  }

  # Resolve form JSON with token replacements applied
  # jsonencode() converts parsed object → string, then replace() swaps tokens
  forms_resolved = {
    for k, v in local.forms_cfg : k => {
      name = v.name

      start_json = replace(
        replace(
          replace(
            replace(
              replace(
                jsonencode(local.forms_parsed[k]["start"]),
                try(keys(try(v.token_replacements, {}))[0], "__noop_0__"),
                try(values(try(v.token_replacements, {}))[0], "")
              ),
              try(keys(try(v.token_replacements, {}))[1], "__noop_1__"),
              try(values(try(v.token_replacements, {}))[1], "")
            ),
            try(keys(try(v.token_replacements, {}))[2], "__noop_2__"),
            try(values(try(v.token_replacements, {}))[2], "")
          ),
          try(keys(try(v.token_replacements, {}))[3], "__noop_3__"),
          try(values(try(v.token_replacements, {}))[3], "")
        ),
        try(keys(try(v.token_replacements, {}))[4], "__noop_4__"),
        try(values(try(v.token_replacements, {}))[4], "")
      )

      nodes_json = replace(
        replace(
          replace(
            replace(
              replace(
                jsonencode(local.forms_parsed[k]["nodes"]),
                try(keys(try(v.token_replacements, {}))[0], "__noop_0__"),
                try(values(try(v.token_replacements, {}))[0], "")
              ),
              try(keys(try(v.token_replacements, {}))[1], "__noop_1__"),
              try(values(try(v.token_replacements, {}))[1], "")
            ),
            try(keys(try(v.token_replacements, {}))[2], "__noop_2__"),
            try(values(try(v.token_replacements, {}))[2], "")
          ),
          try(keys(try(v.token_replacements, {}))[3], "__noop_3__"),
          try(values(try(v.token_replacements, {}))[3], "")
        ),
        try(keys(try(v.token_replacements, {}))[4], "__noop_4__"),
        try(values(try(v.token_replacements, {}))[4], "")
      )

      ending_json       = jsonencode(local.forms_parsed[k]["ending"])
      style_json        = try(jsonencode(local.forms_parsed[k]["style"]), null)
      translations_json = try(jsonencode(local.forms_parsed[k]["translations"]), null)
      language_primary  = try(local.forms_parsed[k]["languages"]["primary"], "en")
      language_default  = try(local.forms_parsed[k]["languages"]["default"], "en")
    }
  }
}

# -----------------------------------------------------------------------------
# Applications
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
# Actions (compiled JS from per-env actions/ directory)
# -----------------------------------------------------------------------------
unit "actions" {
  source = "${get_repo_root()}/catalog/units/actions"
  path   = "actions"
  no_dot_terragrunt_stack = true

  values = {
    actions = {
      for k, v in local.actions_cfg : k => merge(v, {
        code = file("${local.env_dir}/actions/${v.code_file}")
      })
    }
  }
}

# -----------------------------------------------------------------------------
# Action Modules (compiled JS from per-env action-modules/ directory)
# -----------------------------------------------------------------------------
unit "action-modules" {
  source = "${get_repo_root()}/catalog/units/action-modules"
  path   = "action-modules"
  no_dot_terragrunt_stack = true

  values = {
    action_modules = {
      for k, v in local.action_modules_cfg : k => merge(v, {
        code = file("${local.env_dir}/action-modules/${v.code_file}")
      })
    }
  }
}

# -----------------------------------------------------------------------------
# Vault Connections
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
# Flows (tokens pre-replaced in locals above)
# -----------------------------------------------------------------------------
unit "flows" {
  source = "${get_repo_root()}/catalog/units/flows"
  path   = "flows"
  no_dot_terragrunt_stack = true

  values = {
    flows = local.flows_resolved
  }
}

# -----------------------------------------------------------------------------
# Forms (parsed once, tokens pre-replaced in locals above)
# -----------------------------------------------------------------------------
unit "forms" {
  source = "${get_repo_root()}/catalog/units/forms"
  path   = "forms"
  no_dot_terragrunt_stack = true

  values = {
    forms = local.forms_resolved
  }
}
