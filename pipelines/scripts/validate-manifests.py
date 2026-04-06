#!/usr/bin/env python3
"""
Validate platform ops YAML manifests.

Checks:
  1. Multi-instance resources have valid 'environments' lists.
  2. Optional 'regions' lists contain only valid values.
  3. Client grant 'client_key' references exist in clients.yaml.
  4. All region/env YAML files parse without errors.
  5. Singleton manifests parse correctly.
"""

import sys
import os
import yaml

VALID_ENVS = {"dev", "qa", "val", "prod"}
VALID_REGIONS = {"na", "apac", "eu"}
MULTI_INSTANCE_FILES = {
    "clients.yaml": "clients",
    "client_grants.yaml": "client_grants",
    "log_streams.yaml": "log_streams",
}


def load_yaml(path):
    with open(path) as f:
        return yaml.safe_load(f)


def validate_filters(resources, resource_type, errors):
    for key, defn in resources.items():
        if not isinstance(defn, dict):
            continue

        envs = defn.get("environments")
        if envs is None:
            errors.append(f"{resource_type}.{key}: missing required 'environments'")
        elif not isinstance(envs, list) or len(envs) == 0:
            errors.append(f"{resource_type}.{key}: 'environments' must be a non-empty list")
        else:
            invalid = set(envs) - VALID_ENVS
            if invalid:
                errors.append(f"{resource_type}.{key}: invalid environment(s): {invalid}")

        regions = defn.get("regions")
        if regions is not None:
            if not isinstance(regions, list) or len(regions) == 0:
                errors.append(f"{resource_type}.{key}: 'regions' must be a non-empty list when specified")
            else:
                invalid = set(regions) - VALID_REGIONS
                if invalid:
                    errors.append(f"{resource_type}.{key}: invalid region(s): {invalid}")


def validate_client_grant_refs(grants, clients, errors):
    if not grants:
        return
    client_keys = set(clients.keys()) if clients else set()
    for key, defn in grants.items():
        if not isinstance(defn, dict):
            continue
        client_key = defn.get("client_key")
        if client_key is None:
            errors.append(f"client_grants.{key}: missing required 'client_key'")
        elif client_key not in client_keys:
            errors.append(f"client_grants.{key}: client_key '{client_key}' not found in clients.yaml")
        if defn.get("scopes") is None and not defn.get("allow_all_scopes"):
            errors.append(f"client_grants.{key}: missing 'scopes' (or set allow_all_scopes: true)")


def main():
    if len(sys.argv) < 2:
        print("Usage: validate-manifests.py <manifests_dir>")
        sys.exit(1)

    manifests_dir = sys.argv[1]
    errors = []
    warnings = []

    # 1. Validate multi-instance manifests
    for filename, root_key in MULTI_INSTANCE_FILES.items():
        filepath = os.path.join(manifests_dir, filename)
        if not os.path.exists(filepath):
            warnings.append(f"{filename}: not found")
            continue
        try:
            data = load_yaml(filepath)
        except Exception as e:
            errors.append(f"{filename}: YAML parse error: {e}")
            continue
        if data is None or root_key not in data:
            continue
        resources = data[root_key]
        if not isinstance(resources, dict):
            if resources is not None:
                errors.append(f"{filename}: '{root_key}' must be a map")
            continue
        validate_filters(resources, root_key, errors)

    # 2. Validate client grant references
    clients_data = {}
    grants_data = {}
    try:
        raw = load_yaml(os.path.join(manifests_dir, "clients.yaml"))
        clients_data = raw.get("clients", {}) or {}
    except Exception:
        pass
    try:
        raw = load_yaml(os.path.join(manifests_dir, "client_grants.yaml"))
        grants_data = raw.get("client_grants", {}) or {}
    except Exception:
        pass
    if grants_data:
        validate_client_grant_refs(grants_data, clients_data, errors)

    # 3. Validate singleton manifests
    for filename in ["attack_protection.yaml", "email_provider.yaml", "guardian.yaml", "tenant.yaml"]:
        filepath = os.path.join(manifests_dir, filename)
        if not os.path.exists(filepath):
            warnings.append(f"{filename}: not found")
            continue
        try:
            load_yaml(filepath)
        except Exception as e:
            errors.append(f"{filename}: YAML parse error: {e}")

    # 4. Validate region/env YAML files
    regions_dir = os.path.join(manifests_dir, "regions")
    if os.path.isdir(regions_dir):
        for region in VALID_REGIONS:
            region_dir = os.path.join(regions_dir, region)
            if not os.path.isdir(region_dir):
                warnings.append(f"regions/{region}/: directory not found")
                continue
            for env in VALID_ENVS:
                env_file = os.path.join(region_dir, f"{env}.yaml")
                if not os.path.exists(env_file):
                    warnings.append(f"regions/{region}/{env}.yaml: not found")
                    continue
                try:
                    load_yaml(env_file)
                except Exception as e:
                    errors.append(f"regions/{region}/{env}.yaml: YAML parse error: {e}")
    else:
        warnings.append("regions/: directory not found")

    # Report
    print("")
    print("=" * 60)
    print(" Platform Ops Manifest Validation")
    print("=" * 60)

    if warnings:
        print(f"\n  Warnings ({len(warnings)}):")
        for w in warnings:
            print(f"   {w}")

    if errors:
        print(f"\n  Errors ({len(errors)}):")
        for e in errors:
            print(f"   {e}")
        print("\n" + "=" * 60)
        sys.exit(1)
    else:
        print("\n  All manifests valid.")
        print("=" * 60)


if __name__ == "__main__":
    main()
