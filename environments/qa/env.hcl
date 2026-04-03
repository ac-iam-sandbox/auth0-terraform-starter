# =============================================================================
# Environment: qa (development test / QA)
# =============================================================================

locals {
  environment          = "qa"
  tenant_friendly_name = "MyCompany QA"
  aws_region           = get_env("AWS_DEFAULT_REGION", "us-east-1")
}
