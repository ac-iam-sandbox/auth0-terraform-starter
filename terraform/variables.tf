variable "environment" {
  description = "Target environment: dev | qa | val | prod"
  type        = string

  validation {
    condition     = contains(["dev", "qa", "val", "prod"], var.environment)
    error_message = "environment must be one of: dev, qa, val, prod"
  }
}

variable "secrets" {
  description = "All secret values for this environment, keyed by reference name. Populated by pipeline from Key Vault."
  type        = map(string)
  sensitive   = true
  default     = {}
}
