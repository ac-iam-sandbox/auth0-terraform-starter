# =============================================================================
# Environment: prod (production)
# =============================================================================

locals {
  environment          = "prod"
  tenant_friendly_name = "MyCompany PROD"
  aws_region           = get_env("AWS_DEFAULT_REGION", "us-east-1")
}
