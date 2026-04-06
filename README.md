# Auth0 Platform Ops Terraform Infrastructure

Manages Auth0 tenant platform configuration across **3 regions × 4 environments = 12 tenants** using a single Terraform codebase with YAML-driven manifests.

## Architecture

```
One codebase → parameterized by region + environment → applied via pipeline

terraform plan -var="region=apac" -var="environment=dev"
                        ↓                      ↓
    manifests/regions/apac/dev.yaml    backends/apac-dev.s3.tfbackend
    variable group: apac-dev-axon-platform-ops
    state key: auth0-platform-ops/apac/dev/terraform.tfstate
```

**Shared manifests** define resources (same 5 M2M clients, same grants, same guardian config everywhere). **Region configs** provide tenant-specific values (domain, SES region, from address). Each region+env combo gets its own Terraform state, variable group, and approval gate.

## What this repo manages

| Module | Resource | Type | Description |
|---|---|---|---|
| clients | `auth0_client` | Multi | M2M apps — filtered by `environments` + optional `regions` |
| client_grants | `auth0_client_grant` | Multi | Grants — audience auto-resolves to Management API |
| attack_protection | `auth0_attack_protection` | Singleton | Brute force, breached passwords, IP throttling, bot detection, CAPTCHA |
| email_provider | `auth0_email_provider` | Singleton | Amazon SES |
| guardian | `auth0_guardian` | Singleton | MFA policy: `never` (OTP + email enabled) |
| log_streams | `auth0_log_stream` | Multi | Empty — add when ready |
| tenant | `auth0_tenant` | Singleton | Tenant settings, flags, sessions |

## Region filtering

Multi-instance resources support an optional `regions` filter alongside `environments`. Omitting `regions` means "all regions."

```yaml
# All regions, all envs (default)
clients:
  email-template-service:
    name: "Email Template Service"
    environments: [dev, qa, val, prod]
    # no regions key — deployed everywhere

# APAC only
  apac-specific-service:
    name: "APAC Compliance Service"
    environments: [dev, qa, val, prod]
    regions: [apac]
```

## Repository structure

```
terraform/
├── main.tf, variables.tf, outputs.tf, providers.tf, versions.tf
├── modules/
│   ├── clients/              # M2M only, region+env filtered
│   ├── client_grants/        # Auto-resolves Management API audience
│   ├── attack_protection/    # Singleton
│   ├── email_provider/       # Singleton (SES)
│   ├── guardian/             # Singleton
│   ├── log_streams/          # Multi, region+env filtered
│   └── tenant/               # Singleton
├── manifests/
│   ├── clients.yaml          # Shared — 5 M2M clients
│   ├── client_grants.yaml    # Shared — 5 grants with exact scopes
│   ├── attack_protection.yaml
│   ├── email_provider.yaml
│   ├── guardian.yaml
│   ├── log_streams.yaml
│   ├── tenant.yaml
│   └── regions/
│       ├── na/
│       │   ├── dev.yaml      # na-dev-axon-cic.us.auth0.com
│       │   ├── qa.yaml
│       │   ├── val.yaml
│       │   └── prod.yaml
│       ├── apac/
│       │   ├── dev.yaml      # apac-dev-axon-cic.jp.auth0.com
│       │   ├── qa.yaml
│       │   ├── val.yaml
│       │   └── prod.yaml
│       └── eu/
│           ├── dev.yaml
│           ├── qa.yaml
│           ├── val.yaml
│           └── prod.yaml
└── backends/
    ├── na-dev.s3.tfbackend    # key = auth0-platform-ops/na/dev/terraform.tfstate
    ├── na-qa.s3.tfbackend
    ├── ...                    # 12 total (3 regions × 4 envs)
    └── eu-prod.s3.tfbackend

pipelines/
├── deploy-dev.yml             # Auto on merge, takes region param
├── promote.yml                # Manual, takes region + environment
├── pr-validation.yml          # Auto on PR, takes region param
├── import-dev.yml             # One-time import, takes region + environment
├── scripts/validate-manifests.py
└── templates/                 # terraform-init, validate, plan, apply, etc.
```

## Azure DevOps setup

### Variable groups (12 total)

| Pattern | Example |
|---|---|
| `{region}-{env}-axon-platform-ops` | `na-dev-axon-platform-ops`, `apac-prod-axon-platform-ops` |

Each group needs: `AUTH0_DOMAIN`, `AUTH0_CLIENT_ID`, `AUTH0_CLIENT_SECRET` (masked), `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` (masked), `AWS_DEFAULT_REGION`, `TF_STATE_BUCKET`, `SES_ACCESS_KEY_ID` (masked), `SES_SECRET_ACCESS_KEY` (masked).

### Environments (12 total)

| Pattern | Approvals |
|---|---|
| `{region}-dev-axon-platform-ops` | 1 team member, self-approve OK |
| `{region}-qa-axon-platform-ops` | 1 team member, no self-approve |
| `{region}-val-axon-platform-ops` | 2 senior engineers, no self-approve |
| `{region}-prod-axon-platform-ops` | 2 senior engineers, min 2 approvals |

### Pipelines

| Pipeline | Trigger | Parameters |
|---|---|---|
| Platform Ops - Deploy Dev | Auto (merge to master) | `region` |
| Platform Ops - Promote | Manual | `region` + `target_environment` |
| Platform Ops - PR Validation | Auto (PR to master) | `region` |
| Platform Ops - Import | Manual (one-time) | `region` + `environment` + resource IDs |

## Config vs. secrets

| Value | Location |
|---|---|
| Resource definitions (shared) | `manifests/*.yaml` |
| Region+env config (domains, from addresses) | `manifests/regions/{region}/{env}.yaml` |
| `SES_ACCESS_KEY_ID`, `SES_SECRET_ACCESS_KEY` | Variable group (masked) → `TF_VAR_secrets_json` |
| `AUTH0_*`, `AWS_*` credentials | Variable group → env vars |

## Placeholders to replace

Run `grep -r "PLACEHOLDER_" terraform/manifests/` to find all placeholders. Replace with actual values per region+env before first plan.

## Adding resources

**New M2M client (all regions):** Add to `clients.yaml` with `environments: [dev]`. No `regions` key needed.

**Region-specific client:** Add `regions: [apac]` (or whichever regions).

**New secret:** Add to all 12 variable groups + `TF_VAR_secrets_json` in plan+apply templates.

**Promote:** Expand `environments` list, merge, run promote pipeline for each target region+env.
