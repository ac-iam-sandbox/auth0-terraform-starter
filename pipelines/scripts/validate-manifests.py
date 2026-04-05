#!/usr/bin/env python3
"""
Validates Auth0 Terraform manifest integrity.

Checks:
  1. Every resource has an explicit 'environments' key (hard fail)
  2. Every value in 'environments' is a valid environment name
  3. No empty 'environments' lists
  4. testing.envs must NEVER contain val or prod (hard fail)
  5. secrets_config keys resolve to entries in applicable environment files
  6. setup_config keys (vault connections) resolve to entries in env files
  7. Action module_key references exist in action_modules manifest
  8. Flow source_form references exist in forms manifest
  9. Flow vault_key references exist in vault_connections manifest
  10. Form flow_key references exist in flows manifest

Usage:
  python validate-manifests.py <manifests_dir>

Exit codes:
  0 = all validations passed
  1 = one or more errors found
"""

import sys
import os

import yaml


VALID_ENVS = {"dev", "qa", "val", "prod"}
PROTECTED_ENVS = {"val", "prod"}

# Dependency versions that must never reach the pipeline.
BANNED_VERSIONS = {"latest", "PINME", "*", ""}

# Auth0 Actions do not support native npm modules.
# These packages require native compilation and will fail at deploy/runtime.
NATIVE_MODULE_DENYLIST = {
    "bcrypt", "sharp", "canvas", "node-gyp", "leveldown", "sqlite3",
    "node-sass", "fsevents", "grpc", "cpu-features", "dtrace-provider",
    "microtime", "bufferutil", "utf-8-validate", "heapdump",
}

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
    try:
        with open(path, "r") as f:
            return yaml.safe_load(f) or {}
    except Exception as e:
        print(f"##[error]Failed to parse {path}: {e}")
        return None


def validate_environments_key(resource_key, resource_def, manifest_file, section):
    errors = []
    location = f"{manifest_file} -> {section}.{resource_key}"

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


def validate_testing_block(resource_key, resource_def, manifest_file, section):
    """Ban testing.envs from containing val or prod."""
    errors = []
    location = f"{manifest_file} -> {section}.{resource_key}"

    testing = resource_def.get("testing")
    if not testing:
        return errors

    if not isinstance(testing, dict):
        errors.append(f"{location}: 'testing' must be a mapping")
        return errors

    if "file" not in testing:
        errors.append(f"{location}: testing block missing 'file' key")

    test_envs = testing.get("envs", [])
    if not isinstance(test_envs, list):
        errors.append(f"{location}: testing.envs must be a list")
        return errors

    for env in test_envs:
        if env in PROTECTED_ENVS:
            errors.append(
                f"{location}: testing.envs contains '{env}' which is FORBIDDEN. "
                f"val and prod must always resolve main.* artifacts. "
                f"Promote by overwriting main.* with tested code and removing the testing block."
            )

    return errors


def validate_dependencies(resource_key, resource_def, manifest_file, section):
    """Check that dependencies are pinned and not native modules."""
    errors = []
    location = f"{manifest_file} -> {section}.{resource_key}"

    deps = resource_def.get("dependencies", {})
    if not isinstance(deps, dict):
        return errors

    for pkg_name, pkg_version in deps.items():
        version_str = str(pkg_version).strip()

        if version_str in BANNED_VERSIONS:
            errors.append(
                f"{location}: dependency '{pkg_name}' has banned version '{version_str}'. "
                f"Pin to an exact version (e.g., '4.16.0')."
            )

        if pkg_name.lower() in NATIVE_MODULE_DENYLIST:
            errors.append(
                f"{location}: dependency '{pkg_name}' is a native module and is not supported "
                f"by Auth0 Actions. Auth0 only supports public npm packages without native binaries."
            )

    return errors


def validate_config_crossref(resource_key, resource_def, env_config_section, env_files, manifest_file, section):
    errors = []
    location = f"{manifest_file} -> {section}.{resource_key}"

    if env_config_section is None:
        return errors

    target_envs = resource_def.get("environments", [])

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
                    f"environments/{env}.yaml -> {env_config_section}.{resource_key}.{config_key}"
                )

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
                    f"environments/{env}.yaml -> {env_config_section}.{resource_key}.{config_key}"
                )

    return errors


def validate_secrets_pipeline(resource_key, resource_def, manifest_file, section):
    """Warn about secrets_pipeline entries. This is an intentionally deferred hard-check.
    Full enforcement requires parsing pipeline YAML which is brittle.
    A missing secret will cause terraform plan to fail at runtime, but that is a
    slower feedback loop than catching it here. This gap should be closed by
    moving secret declarations to a central machine-readable mapping."""
    warnings = []
    location = f"{manifest_file} -> {section}.{resource_key}"

    for secret_name in resource_def.get("secrets_pipeline", []):
        warnings.append(
            f"{location}: DEFERRED CHECK -- secrets_pipeline key '{secret_name}' "
            f"must exist in TF_VAR_secrets_json in BOTH terraform-plan.yml AND terraform-apply.yml, "
            f"and as a masked variable in every applicable Azure DevOps variable group. "
            f"This is NOT machine-validated yet. Verify manually during PR review."
        )

    return warnings


def validate_action_module_refs(actions, action_modules):
    """Check that every module_key in actions references an existing action_module."""
    errors = []
    module_keys = set(action_modules.keys()) if action_modules else set()

    for action_key, action_def in (actions or {}).items():
        if not isinstance(action_def, dict):
            continue
        for mod_ref in action_def.get("modules", []):
            if isinstance(mod_ref, dict) and "module_key" in mod_ref:
                mk = mod_ref["module_key"]
                if mk not in module_keys:
                    errors.append(
                        f"actions.yaml -> actions.{action_key}: module_key '{mk}' "
                        f"does not exist in action_modules.yaml"
                    )
    return errors


def validate_flow_refs(flows, vault_connections, forms):
    """Cross-reference flow definitions against vault connections and forms."""
    errors = []
    vault_keys = set(vault_connections.keys()) if vault_connections else set()
    form_keys = set(forms.keys()) if forms else set()

    for flow_key, flow_def in (flows or {}).items():
        if not isinstance(flow_def, dict):
            continue
        location = f"flows.yaml -> flows.{flow_key}"

        # Check source_form exists
        source_form = flow_def.get("source_form")
        if source_form and source_form not in form_keys:
            errors.append(f"{location}: source_form '{source_form}' does not exist in forms manifest")

        # Check conn_refs vault_key exists
        for ref in flow_def.get("conn_refs", []):
            if isinstance(ref, dict) and "vault_key" in ref:
                vk = ref["vault_key"]
                if vk not in vault_keys:
                    errors.append(f"{location}: conn_refs vault_key '{vk}' does not exist in vault_connections")

    return errors


def validate_form_refs(forms, flows):
    """Cross-reference form definitions against flows."""
    errors = []
    flow_keys = set(flows.keys()) if flows else set()

    for form_key, form_def in (forms or {}).items():
        if not isinstance(form_def, dict):
            continue
        location = f"flows.yaml -> forms.{form_key}"

        # Check flow_refs flow_key exists
        for ref in form_def.get("flow_refs", []):
            if isinstance(ref, dict) and "flow_key" in ref:
                fk = ref["flow_key"]
                if fk not in flow_keys:
                    errors.append(f"{location}: flow_refs flow_key '{fk}' does not exist in flows manifest")

        # Check form export file exists
        code = form_def.get("code", "main.json")
        form_file = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                                  "terraform", "manifests", "forms", form_key, code)
        # Use relative check from manifests_dir (passed as arg)
    return errors


def validate_form_files(forms, manifests_dir):
    """Check that form export JSON files exist and are cleaned."""
    errors = []
    ALLOWED_KEYS = {"form", "flows"}

    for form_key, form_def in (forms or {}).items():
        if not isinstance(form_def, dict):
            continue
        code = form_def.get("code", "main.json")
        form_path = os.path.join(manifests_dir, "forms", form_key, code)
        if not os.path.exists(form_path):
            errors.append(
                f"flows.yaml -> forms.{form_key}: export file not found: "
                f"forms/{form_key}/{code}"
            )
        else:
            # Check for unclean export (contains metadata Terraform doesn't use)
            import json
            try:
                with open(form_path, "r") as fh:
                    export_data = json.load(fh)
                extra_keys = set(export_data.keys()) - ALLOWED_KEYS
                if extra_keys:
                    errors.append(
                        f"flows.yaml -> forms.{form_key}: export file forms/{form_key}/{code} "
                        f"contains metadata keys that should be removed: {', '.join(sorted(extra_keys))}. "
                        f"Run: python pipelines/scripts/clean-export.py forms/{form_key}/{code}"
                    )
            except json.JSONDecodeError as e:
                errors.append(
                    f"flows.yaml -> forms.{form_key}: invalid JSON in forms/{form_key}/{code}: {e}"
                )

        # Check testing file exists if testing block present
        testing = form_def.get("testing")
        if testing and isinstance(testing, dict) and "file" in testing:
            test_path = os.path.join(manifests_dir, "forms", form_key, testing["file"])
            if not os.path.exists(test_path):
                errors.append(
                    f"flows.yaml -> forms.{form_key}: testing file not found: "
                    f"forms/{form_key}/{testing['file']}"
                )
            elif os.path.exists(test_path):
                import json
                try:
                    with open(test_path, "r") as fh:
                        test_data = json.load(fh)
                    extra_keys = set(test_data.keys()) - ALLOWED_KEYS
                    if extra_keys:
                        errors.append(
                            f"flows.yaml -> forms.{form_key}: testing file forms/{form_key}/{testing['file']} "
                            f"contains metadata keys: {', '.join(sorted(extra_keys))}. "
                            f"Run: python pipelines/scripts/clean-export.py forms/{form_key}/{testing['file']}"
                        )
                except json.JSONDecodeError:
                    pass
    return errors


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

    # Load all manifests for cross-referencing
    actions_data = load_yaml(os.path.join(manifests_dir, "actions.yaml")) or {}
    action_modules_data = load_yaml(os.path.join(manifests_dir, "action_modules.yaml")) or {}
    flows_data = load_yaml(os.path.join(manifests_dir, "flows.yaml")) or {}

    actions = actions_data.get("actions", {})
    action_modules = action_modules_data.get("action_modules", {})
    vault_connections = flows_data.get("vault_connections", {})
    flows = flows_data.get("flows", {})
    forms = flows_data.get("forms", {})

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
                        f"{manifest_file} -> {section_key}.{resource_key}: "
                        f"resource definition must be a mapping, got {type(resource_def).__name__}"
                    )
                    continue

                # Check 1: environments key
                all_errors.extend(
                    validate_environments_key(resource_key, resource_def, manifest_file, section_key)
                )

                # Check 2: testing block safety
                all_errors.extend(
                    validate_testing_block(resource_key, resource_def, manifest_file, section_key)
                )

                # Check 3: config cross-references
                all_errors.extend(
                    validate_config_crossref(
                        resource_key, resource_def, env_config_section,
                        env_files, manifest_file, section_key
                    )
                )

                # Check 4: secrets_pipeline warnings
                all_warnings.extend(
                    validate_secrets_pipeline(resource_key, resource_def, manifest_file, section_key)
                )

                # Check 5: dependency version pinning and native module ban
                all_errors.extend(
                    validate_dependencies(resource_key, resource_def, manifest_file, section_key)
                )

    # Cross-reference checks
    all_errors.extend(validate_action_module_refs(actions, action_modules))
    all_errors.extend(validate_flow_refs(flows, vault_connections, forms))
    all_errors.extend(validate_form_refs(forms, flows))
    all_errors.extend(validate_form_files(forms, manifests_dir))

    # Count total resources
    total = sum(
        len(res) if isinstance(res, dict) else 0
        for manifest_file in MANIFEST_MAP
        for section_key in MANIFEST_MAP[manifest_file]
        for manifest_data in [load_yaml(os.path.join(manifests_dir, manifest_file))]
        if manifest_data
        for res in [manifest_data.get(section_key, {})]
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
          f"Checked {total} resources across {len(VALID_ENVS)} environments.")
    sys.exit(0)


if __name__ == "__main__":
    main()
