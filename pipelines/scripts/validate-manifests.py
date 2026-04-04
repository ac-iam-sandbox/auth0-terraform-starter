#!/usr/bin/env python3
"""
Validates Auth0 Terraform manifest integrity.

Checks:
  1. Every resource has an explicit 'environments' key (hard fail)
  2. Every value in 'environments' is a valid environment name
  3. No empty 'environments' lists
  4. secrets_config keys resolve to entries in applicable environment files
  5. setup_config keys (vault connections) resolve to entries in env files

Usage:
  python validate-manifests.py <manifests_dir>
  python validate-manifests.py terraform/manifests

Exit codes:
  0 = all validations passed
  1 = one or more errors found
"""

import sys
import os

import yaml


VALID_ENVS = {"dev", "qa", "val", "prod"}

# Maps manifest filename → dict of { yaml_section_key: env_config_section_name }
# env_config_section_name is the key used in environments/{env}.yaml
# None means no env config is expected for that section.
MANIFEST_MAP = {
    "clients.yaml": {"clients": "clients"},
    "actions.yaml": {"actions": "actions"},
    "action_modules.yaml": {"action_modules": "action_modules"},
    "flows.yaml": {
        "vault_connections": "vault_connections",
        "flows": None,
        "forms": None,
    },
}


def load_yaml(path):
    """Load a YAML file and return its contents, or empty dict on failure."""
    try:
        with open(path, "r") as f:
            return yaml.safe_load(f) or {}
    except Exception as e:
        print(f"##[error]Failed to parse {path}: {e}")
        return None


def validate_environments_key(resource_key, resource_def, manifest_file, section):
    """Check that the resource has a valid 'environments' key."""
    errors = []
    location = f"{manifest_file} → {section}.{resource_key}"

    if "environments" not in resource_def:
        errors.append(
            f"{location}: missing required 'environments' key. "
            f"Add environments: [dev, qa, val, prod] for all-env resources."
        )
        return errors

    envs = resource_def["environments"]

    if not isinstance(envs, list):
        errors.append(f"{location}: 'environments' must be a list, got {type(envs).__name__}")
        return errors

    if len(envs) == 0:
        errors.append(f"{location}: 'environments' list is empty (probably a mistake)")
        return errors

    for env in envs:
        if env not in VALID_ENVS:
            errors.append(f"{location}: invalid environment '{env}' (valid: {', '.join(sorted(VALID_ENVS))})")

    return errors


def validate_config_crossref(resource_key, resource_def, env_config_section, env_files, manifest_file, section):
    """Cross-reference secrets_config and setup_config against environment files."""
    errors = []
    location = f"{manifest_file} → {section}.{resource_key}"

    if env_config_section is None:
        return errors

    target_envs = resource_def.get("environments", [])

    # Check secrets_config keys exist in each applicable environment file
    for config_key in resource_def.get("secrets_config", []):
        for env in target_envs:
            if env not in env_files:
                continue
            env_data = env_files[env]
            env_section = env_data.get(env_config_section, {})
            resource_config = env_section.get(resource_key, {}) if env_section else {}

            if not resource_config or config_key not in resource_config:
                errors.append(
                    f"{location}: secrets_config key '{config_key}' is missing in "
                    f"environments/{env}.yaml → {env_config_section}.{resource_key}.{config_key}"
                )

    # Check setup_config keys (vault connections use this pattern)
    for config_key in resource_def.get("setup_config", []):
        for env in target_envs:
            if env not in env_files:
                continue
            env_data = env_files[env]
            env_section = env_data.get(env_config_section, {})
            resource_config = env_section.get(resource_key, {}) if env_section else {}

            if not resource_config or config_key not in resource_config:
                errors.append(
                    f"{location}: setup_config key '{config_key}' is missing in "
                    f"environments/{env}.yaml → {env_config_section}.{resource_key}.{config_key}"
                )

    return errors


def validate_secrets_pipeline(resource_key, resource_def, manifest_file, section):
    """Warn about secrets_pipeline entries (best-effort check)."""
    warnings = []
    location = f"{manifest_file} → {section}.{resource_key}"

    for secret_name in resource_def.get("secrets_pipeline", []):
        warnings.append(
            f"{location}: secrets_pipeline key '{secret_name}' — "
            f"verify this exists in TF_VAR_secrets_json in terraform-plan.yml and terraform-apply.yml"
        )

    return warnings


def main():
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <manifests_dir>")
        sys.exit(1)

    manifests_dir = sys.argv[1]
    env_dir = os.path.join(manifests_dir, "environments")

    if not os.path.isdir(manifests_dir):
        print(f"##[error]Manifests directory not found: {manifests_dir}")
        sys.exit(1)

    if not os.path.isdir(env_dir):
        print(f"##[error]Environments directory not found: {env_dir}")
        sys.exit(1)

    # Load environment files
    env_files = {}
    for env in VALID_ENVS:
        env_path = os.path.join(env_dir, f"{env}.yaml")
        if not os.path.exists(env_path):
            print(f"##[error]Environment file missing: {env_path}")
            sys.exit(1)
        data = load_yaml(env_path)
        if data is None:
            sys.exit(1)
        env_files[env] = data

    all_errors = []
    all_warnings = []

    # Validate each manifest
    for manifest_file, sections in MANIFEST_MAP.items():
        manifest_path = os.path.join(manifests_dir, manifest_file)
        if not os.path.exists(manifest_path):
            print(f"##[error]Manifest file missing: {manifest_path}")
            sys.exit(1)

        manifest_data = load_yaml(manifest_path)
        if manifest_data is None:
            sys.exit(1)

        for section_key, env_config_section in sections.items():
            resources = manifest_data.get(section_key, {})
            if not resources or not isinstance(resources, dict):
                continue

            for resource_key, resource_def in resources.items():
                if not isinstance(resource_def, dict):
                    all_errors.append(
                        f"{manifest_file} → {section_key}.{resource_key}: "
                        f"resource definition must be a mapping, got {type(resource_def).__name__}"
                    )
                    continue

                # Check 1: environments key
                all_errors.extend(
                    validate_environments_key(resource_key, resource_def, manifest_file, section_key)
                )

                # Check 2: config cross-references
                all_errors.extend(
                    validate_config_crossref(
                        resource_key, resource_def, env_config_section,
                        env_files, manifest_file, section_key
                    )
                )

                # Check 3: secrets_pipeline warnings
                all_warnings.extend(
                    validate_secrets_pipeline(resource_key, resource_def, manifest_file, section_key)
                )

    # Print results
    if all_warnings:
        print(f"\n{'=' * 60}")
        print(f"WARNINGS ({len(all_warnings)})")
        print(f"{'=' * 60}")
        for w in all_warnings:
            print(f"##[warning]{w}")

    if all_errors:
        print(f"\n{'=' * 60}")
        print(f"ERRORS ({len(all_errors)})")
        print(f"{'=' * 60}")
        for e in all_errors:
            print(f"##[error]{e}")
        print(f"\n##[error]Manifest validation failed with {len(all_errors)} error(s).")
        sys.exit(1)

    print(f"\nManifest validation passed. "
          f"Checked {sum(len(manifest_data.get(sk, {}) or {}) for _, sections in MANIFEST_MAP.items() for sk in sections for manifest_data in [load_yaml(os.path.join(manifests_dir, _))])} resources "
          f"across {len(VALID_ENVS)} environments.")
    sys.exit(0)


if __name__ == "__main__":
    main()
