variable "region" {
  description = "Target region: na | apac | eu"
  type        = string

  validation {
    condition     = contains(["na", "apac", "eu"], var.region)
    error_message = "region must be one of: na, apac, eu"
  }
}

variable "environment" {
  description = "Target environment: dev | qa | val | prod"
  type        = string

  validation {
    condition     = contains(["dev", "qa", "val", "prod"], var.environment)
    error_message = "environment must be one of: dev, qa, val, prod"
  }
}

variable "secrets_json" {
  description = "JSON string of secret values. Populated by pipeline via TF_VAR_secrets_json."
  type        = string
  sensitive   = true
  default     = "{}"
}

locals {
  secrets = jsondecode(var.secrets_json)
}
