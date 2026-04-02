include "root" {
  path = "${get_repo_root()}/root.hcl"
}

terraform {
  source = "${get_repo_root()}/modules//actions"
}

inputs = merge(
  try(values, {}),
  {}
)
