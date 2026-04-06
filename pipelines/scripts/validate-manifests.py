#!/usr/bin/env python3
"""
Validate platform ops YAML manifests.

Checks:
  1. All multi-instance resources (clients, client_grants, log_streams) have explicit
     'environments' lists with valid values.
  2. Client grant 'client_key' references exist in clients.yaml.
  3. Environment YAML files parse without errors.
  4. No unknown environment values.
"""

import sys
import os
import yaml

VALID_ENVS = {"dev", "qa", "val", "prod"}
MULTI_INSTANCE_FILES = {
    "clients.yaml": "clients",
    "client_grants.yaml": "client_grants",
    "log_streams.yaml": "log_streams",
}


def load_yaml(path):
    with open(path) as f:
        return yaml.safe_load(f)


def validate_environments_key(resources, resource_type, errors):
    """Every multi-instance resource must have an explicit environments list."""
    for key, defn in resources.items():
        if not isinstance(defn, dict):
            continue
        envs = defn.get("environments")
        if envs is None:
            errors.append(
                f"{resource_type}.{key}: missing required 'environments' key"
            )
            continue
        if not isinstance(envs, list) or len(envs) == 0:
            errors.append(
                f"{resource_type}.{key}: 'environments' must be a non-empty list"
            )
            continue
        invalid = set(envs) - VALID_ENVS
        if invalid:
            errors.append(
                f"{resource_type}.{key}: invalid environment(s): {invalid}"
            )


def validate_client_grant_refs(grants, clients, errors):
    """Every client_key in grants must reference an existing client."""
    if not grants:
        return
    client_keys = set(clients.keys()) if clients else set()
    for key, defn in grants.items():
        if not isinstance(defn, dict):
            continue
        client_key = defn.get("client_key")
        if client_key is None:
            errors.append(
                f"client_grants.{key}: missing required 'client_key'"
            )
        elif client_key not in client_keys:
            errors.append(
                f"client_grants.{key}: client_key '{client_key}' not found in clients.yaml"
            )

        # Validate required fields
        if defn.get("audience") is None:
            errors.append(f"client_grants.{key}: missing required 'audience'")
        if defn.get("scopes") is None:
            errors.append(f"client_grants.{key}: missing required 'scopes'")


def main():
    if len(sys.argv) < 2:
        print("Usage: validate-manifests.py <manifests_dir>")
        sys.exit(1)

    manifests_dir = sys.argv[1]
    errors = []
    warnings = []

    # 1. Validate multi-instance resource manifests
    for filename, root_key in MULTI_INSTANCE_FILES.items():
        filepath = os.path.join(manifests_dir, filename)
        if not os.path.exists(filepath):
            warnings.append(f"{filename}: file not found (no {root_key} defined)")
            continue
        try:
            data = load_yaml(filepath)
        except Exception as e:
            errors.append(f"{filename}: YAML parse error: {e}")
            continue

        if data is None or root_key not in data:
            warnings.append(f"{filename}: no '{root_key}' key found (empty manifest)")
            continue

        resources = data[root_key]
        if not isinstance(resources, dict):
            if resources is not None:
                errors.append(f"{filename}: '{root_key}' must be a map")
            continue

        validate_environments_key(resources, root_key, errors)

    # 2. Validate client grant references
    clients_path = os.path.join(manifests_dir, "clients.yaml")
    grants_path = os.path.join(manifests_dir, "client_grants.yaml")
    clients_data = {}
    grants_data = {}

    if os.path.exists(clients_path):
        try:
            raw = load_yaml(clients_path)
            clients_data = raw.get("clients", {}) or {}
        except Exception:
            pass

    if os.path.exists(grants_path):
        try:
            raw = load_yaml(grants_path)
            grants_data = raw.get("client_grants", {}) or {}
        except Exception:
            pass

    if grants_data:
        validate_client_grant_refs(grants_data, clients_data, errors)

    # 3. Validate singleton manifests parse correctly
    for filename in [
        "attack_protection.yaml",
        "email_provider.yaml",
        "guardian.yaml",
        "tenant.yaml",
    ]:
        filepath = os.path.join(manifests_dir, filename)
        if not os.path.exists(filepath):
            warnings.append(f"{filename}: file not found")
            continue
        try:
            load_yaml(filepath)
        except Exception as e:
            errors.append(f"{filename}: YAML parse error: {e}")

    # 4. Validate environment YAML files
    env_dir = os.path.join(manifests_dir, "environments")
    if os.path.isdir(env_dir):
        for env in VALID_ENVS:
            env_file = os.path.join(env_dir, f"{env}.yaml")
            if not os.path.exists(env_file):
                warnings.append(f"environments/{env}.yaml: not found")
                continue
            try:
                load_yaml(env_file)
            except Exception as e:
                errors.append(f"environments/{env}.yaml: YAML parse error: {e}")

    # Report
    print("")
    print("=" * 60)
    print(" Platform Ops Manifest Validation")
    print("=" * 60)

    if warnings:
        print(f"\n⚠  Warnings ({len(warnings)}):")
        for w in warnings:
            print(f"   {w}")

    if errors:
        print(f"\n✗  Errors ({len(errors)}):")
        for e in errors:
            print(f"   {e}")
        print("")
        print("=" * 60)
        sys.exit(1)
    else:
        print("\n✓  All manifests valid.")
        print("=" * 60)


if __name__ == "__main__":
    main()
