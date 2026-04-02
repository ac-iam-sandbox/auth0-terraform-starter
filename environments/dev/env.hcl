# =============================================================================
# Environment: dev (sandbox)
# =============================================================================
# This file is the single source of truth for dev-specific settings.
# It is read by root.hcl (for state container name) and by the stack file
# (for env-specific inputs).
# =============================================================================

locals {
  environment = "dev"
}
