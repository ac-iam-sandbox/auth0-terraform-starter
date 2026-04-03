# =============================================================================
# Environment: dev (sandbox)
# =============================================================================

locals {
  environment          = "dev"
  tenant_friendly_name = "MyCompany DEV"
  aws_region           = get_env("AWS_DEFAULT_REGION", "us-east-1")
}
