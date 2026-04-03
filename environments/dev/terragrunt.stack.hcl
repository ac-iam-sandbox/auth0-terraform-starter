# =============================================================================
# Terragrunt Stack Definition (shared by all environments)
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

  forms_parsed = {
    for k, v in local.forms_cfg : k => jsondecode(file("${local.env_dir}/${v.file}"))
  }

  form_translations_from_files = {
    for k, v in local.forms_cfg : k => (
      length(fileset("${local.env_dir}/i18n/forms/${k}", "*.json")) > 0 ?
      merge([
        for filename in fileset("${local.env_dir}/i18n/forms/${k}", "*.json") : {
          trimsuffix(filename, ".json") = jsondecode(file("${local.env_dir}/i18n/forms/${k}/${filename}"))
        }
      ]...) :
      try(local.forms_parsed[k]["translations"], null)
    )
  }
}

unit "applications" {
  source = "${get_repo_root()}/catalog/units/applications"
  path   = "applications"
  no_dot_terragrunt_stack = true

  values = {
    applications = local.applications
  }
}

unit "actions" {
  source = "${get_repo_root()}/catalog/units/actions"
  path   = "actions"
  no_dot_terragrunt_stack = true

  values = {
    actions = {
      for k, v in local.actions_cfg : k => merge(v, {
        code = file("${local.env_dir}/actions/${v.code_file}")
        secrets = [
          for secret in try(v.secrets, []) : {
            name  = secret.name
            value = startswith(secret.value, "env:") ? get_env(trimprefix(secret.value, "env:"), "") : secret.value
          }
        ]
      })
    }
  }
}

unit "action-modules" {
  source = "${get_repo_root()}/catalog/units/action-modules"
  path   = "action-modules"
  no_dot_terragrunt_stack = true

  values = {
    action_modules = {
      for k, v in local.action_modules_cfg : k => merge(v, {
        code = file("${local.env_dir}/action-modules/${v.code_file}")
        secrets = [
          for secret in try(v.secrets, []) : {
            name  = secret.name
            value = startswith(secret.value, "env:") ? get_env(trimprefix(secret.value, "env:"), "") : secret.value
          }
        ]
      })
    }
  }
}

unit "journeys" {
  source = "${get_repo_root()}/catalog/units/journeys"
  path   = "journeys"
  no_dot_terragrunt_stack = true

  values = {
    vault_connections = {
      for k, v in local.vault_conns_cfg : k => merge(v, {
        setup = {
          for setup_key, setup_value in try(v.setup, {}) :
          setup_key => (startswith(setup_value, "env:") ? get_env(trimprefix(setup_value, "env:"), "") : setup_value)
        }
      })
    }
    flows = {
      for k, v in local.flows_cfg : k => {
        name = v.name
        actions_json = replace(
          replace(
            replace(
              replace(
                replace(
                  file("${local.env_dir}/${v.file}"),
                  try(keys(try(v.env_replacements, {}))[0], "__noop_env_0__"),
                  get_env(try(values(try(v.env_replacements, {}))[0], "__NO_SUCH_ENV__"), "")
                ),
                try(keys(try(v.env_replacements, {}))[1], "__noop_env_1__"),
                get_env(try(values(try(v.env_replacements, {}))[1], "__NO_SUCH_ENV__"), "")
              ),
              try(keys(try(v.env_replacements, {}))[2], "__noop_env_2__"),
              get_env(try(values(try(v.env_replacements, {}))[2], "__NO_SUCH_ENV__"), "")
            ),
            try(keys(try(v.env_replacements, {}))[3], "__noop_env_3__"),
            get_env(try(values(try(v.env_replacements, {}))[3], "__NO_SUCH_ENV__"), "")
          ),
          try(keys(try(v.env_replacements, {}))[4], "__noop_env_4__"),
          get_env(try(values(try(v.env_replacements, {}))[4], "__NO_SUCH_ENV__"), "")
        )
        token_replacements = try(v.token_replacements, {})
      }
    }
    forms = {
      for k, v in local.forms_cfg : k => {
        name               = v.name
        start_json         = jsonencode(local.forms_parsed[k]["start"])
        nodes_json         = jsonencode(local.forms_parsed[k]["nodes"])
        ending_json        = jsonencode(local.forms_parsed[k]["ending"])
        style_json         = try(jsonencode(local.forms_parsed[k]["style"]), null)
        translations_json  = local.form_translations_from_files[k] != null ? jsonencode(local.form_translations_from_files[k]) : null
        language_primary   = try(local.forms_parsed[k]["languages"]["primary"], "en")
        language_default   = try(local.forms_parsed[k]["languages"]["default"], "en")
        token_replacements = try(v.token_replacements, {})
      }
    }
  }
}
