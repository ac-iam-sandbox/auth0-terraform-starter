# =============================================================================
# Environment: val (validation / pre-production)
# =============================================================================

locals {
  environment          = "val"
  tenant_friendly_name = "MyCompany VAL"
  aws_region           = get_env("AWS_DEFAULT_REGION", "us-east-1")
}
