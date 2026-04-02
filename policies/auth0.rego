# =============================================================================
# OPA Policy: Auth0 Terraform Guardrails
# =============================================================================
# Usage: conftest test tfplan.json --policy ./policies/
# Scoped to resources this repo manages: applications, actions, action modules,
# forms, flows, vault connections
# =============================================================================

package terraform.auth0

import rego.v1

# Deny applications without OIDC conformance
deny contains msg if {
  some rc in input.resource_changes
  rc.type == "auth0_client"
  rc.change.after.oidc_conformant == false
  msg := sprintf("Application '%s' must have oidc_conformant = true", [rc.change.after.name])
}

# Deny applications with JWT algorithm other than RS256
deny contains msg if {
  some rc in input.resource_changes
  rc.type == "auth0_client"
  some jwt_config in rc.change.after.jwt_configuration
  jwt_config.alg != "RS256"
  msg := sprintf("Application '%s' must use RS256 signing algorithm", [rc.change.after.name])
}

# Warn on localhost URLs in non-dev environments
warn contains msg if {
  some rc in input.resource_changes
  rc.type == "auth0_client"
  some callback in rc.change.after.callbacks
  contains(callback, "localhost")
  msg := sprintf("Application '%s' has localhost callback URL: %s", [rc.change.after.name, callback])
}

# Deny any resource deletion (belt + suspenders with prevent_destroy)
deny contains msg if {
  some rc in input.resource_changes
  rc.change.actions[_] == "delete"
  msg := sprintf("Deletion of %s '%s' is not allowed in this repo", [rc.type, rc.address])
}

# Warn on actions not set to deploy
warn contains msg if {
  some rc in input.resource_changes
  rc.type == "auth0_action"
  rc.change.after.deploy == false
  msg := sprintf("Action '%s' is not set to deploy automatically", [rc.change.after.name])
}

# Warn on action modules not set to publish
warn contains msg if {
  some rc in input.resource_changes
  rc.type == "auth0_action_module"
  rc.change.after.publish == false
  msg := sprintf("Action Module '%s' is not set to publish", [rc.change.after.name])
}
