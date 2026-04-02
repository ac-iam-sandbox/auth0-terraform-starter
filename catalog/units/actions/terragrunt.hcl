include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/modules//actions"

  # CI builds actions/dist/ from TypeScript source.
  # Compiled JS is then copied to environments/{env}/actions/ for each env.
  # Each environment maintains its own copy for independent promotion.
  # No npm hooks here — the stack file reads from the env-local actions/ dir.
}

inputs = merge(
  try(values, {}),
  {}
)
