# Auth0 Platform Ops Terraform Infrastructure

Manages Auth0 tenant platform operations configuration across four environments (dev, qa, val, prod) in the NA region using Terraform with YAML-driven manifests, Azure DevOps pipelines, and AWS S3 state backend.

This repo is the **platform ops counterpart** to the client-side `auth0-infrastructure` repo. It manages tenant-level configuration, M2M application grants, and operational concerns - not user-facing actions, forms, or flows.

---

## What this repo manages

| Module | Resource | Instance type | Description |
|---|---|---|---|
| **clients** | `auth0_client` | Multi (env-filtered) | M2M applications only - `non_interactive` with `client_credentials` |
| **client_grants** | `auth0_client_grant` | Multi (env-filtered) | Grants tying M2M clients to APIs with least-privilege scopes |
| **attack_protection** | `auth0_attack_protection` | Singleton | Brute force, breached passwords, suspicious IP throttling, bot detection, CAPTCHA |
| **email_provider** | `auth0_email_provider` | Singleton | Amazon SES email provider configuration |
| **guardian** | `auth0_guardian` | Singleton | MFA policy (`never`) and factor configuration (OTP + email enabled) |
| **log_streams** | `auth0_log_stream` | Multi (env-filtered) | Log streaming (empty - add when ready) |
| **tenant** | `auth0_tenant` | Singleton | Tenant-level settings, flags, session config, error pages |

**What this repo does NOT manage:** Actions, action modules, forms, flows, vault connections, connections, branding, resource servers, roles, or users.

---

## Current resources

### Clients (2) - all environments

| Key | Name | Type |
|---|---|---|
| `email-template-service` | Manage Email Template Service Application | M2M |
| `branded-ui-service` | Manage Branded UI Service App | M2M |

### Client grants (2) - all environments

| Key | Client | Audience | Scopes |
|---|---|---|---|
| `email-template-service-mgmt-api` | email-template-service | Management API | `read:email_templates`, `update:email_templates`, `create:email_templates`, `read:email_provider` |
| `branded-ui-service-mgmt-api` | branded-ui-service | Management API | `read:branding`, `update:branding`, `delete:branding`, `read:client_keys`, `read:custom_domains` |

### Singletons - all environments

| Resource | Key config |
|---|---|
| Guardian MFA | `policy: never`, OTP + email enabled |
| Email provider | Amazon SES |
| Attack protection | Brute force + suspicious IP + breached password detection enabled |
| Tenant | Session cookie persistent, pipeline2 enabled |

---

## Architecture overview

**Single Terraform codebase applied to each environment via partial backend configuration.** Same architecture as the client-side repo.

```
One codebase → parameterized by environment → applied via pipeline
                    ↓                              ↓
        manifests/environments/dev.yaml    terraform init -backend-config=backends/dev.s3.tfbackend
        manifests/environments/qa.yaml     terraform init -backend-config=backends/qa.s3.tfbackend
        manifests/environments/val.yaml    terraform init -backend-config=backends/val.s3.tfbackend
        manifests/environments/prod.yaml   terraform init -backend-config=backends/prod.s3.tfbackend
```

### Two resource patterns

**Singleton resources** (tenant, attack_protection, email_provider, guardian): One per tenant. No `environments` filter. Env-specific values come from `environments/{env}.yaml`.

**Multi-instance resources** (clients, client_grants, log_streams): Use `environments` list to control which envs they exist in.

---

## Repository structure

```
auth0-platform-ops/
├── terraform/
│   ├── main.tf                          # Root module - composes child modules
│   ├── variables.tf                     # environment + secrets_json
│   ├── outputs.tf
│   ├── providers.tf                     # Empty - AUTH0_* env vars
│   ├── versions.tf                      # auth0/auth0 ~> 1.41 + S3 backend
│   │
│   ├── modules/
│   │   ├── clients/                     # auth0_client (M2M only)
│   │   ├── client_grants/               # auth0_client_grant
│   │   ├── attack_protection/           # auth0_attack_protection
│   │   ├── email_provider/              # auth0_email_provider
│   │   ├── guardian/                    # auth0_guardian
│   │   ├── log_streams/                 # auth0_log_stream
│   │   └── tenant/                      # auth0_tenant
│   │
│   ├── manifests/
│   │   ├── environments/
│   │   │   ├── dev.yaml                 # na-dev-axon-cic
│   │   │   ├── qa.yaml
│   │   │   ├── val.yaml
│   │   │   └── prod.yaml
│   │   ├── clients.yaml                 # M2M client definitions
│   │   ├── client_grants.yaml           # Grant definitions
│   │   ├── attack_protection.yaml       # Attack protection config
│   │   ├── email_provider.yaml          # SES email provider
│   │   ├── guardian.yaml                # MFA config (policy: never)
│   │   ├── log_streams.yaml             # Empty - add when ready
│   │   └── tenant.yaml                  # Tenant settings
│   │
│   └── backends/                        # Per-env S3 backend configs
│
├── pipelines/
│   ├── deploy-dev.yml
│   ├── promote.yml
│   ├── pr-validation.yml
│   ├── import-dev.yml
│   ├── scripts/
│   │   └── validate-manifests.py
│   └── templates/
│       ├── security-scan.yml
│       ├── terraform-validate.yml
│       ├── terraform-init.yml
│       ├── terraform-plan.yml
│       ├── terraform-apply.yml
│       └── pr-comment.yml
│
├── .gitignore
└── README.md
```

---

## Config vs. secrets

| Value | Where | Injected how |
|---|---|---|
| Env-specific non-secret values | `manifests/environments/{env}.yaml` | Checked into Git |
| Resource definitions | `manifests/*.yaml` | Checked into Git |
| `SES_ACCESS_KEY_ID` | Variable group (masked) | `TF_VAR_secrets_json` |
| `SES_SECRET_ACCESS_KEY` | Variable group (masked) | `TF_VAR_secrets_json` |
| `AUTH0_DOMAIN` | Variable group | Env var |
| `AUTH0_CLIENT_ID` | Variable group | Env var |
| `AUTH0_CLIENT_SECRET` | Variable group (masked) | Env var |
| `AWS_ACCESS_KEY_ID` | Variable group | Env var |
| `AWS_SECRET_ACCESS_KEY` | Variable group (masked) | Env var |
| `AWS_DEFAULT_REGION` | Variable group | Env var |
| `TF_STATE_BUCKET` | Variable group | Backend config |

### Adding a new secret

1. Add masked variable to each Azure DevOps variable group (`na-{env}-axon-platform-ops`)
2. Add the key name to the resource manifest's `credentials_secrets` or `sink_secrets` map
3. Add to `TF_VAR_secrets_json` in **both** `terraform-plan.yml` **and** `terraform-apply.yml`

---

## Azure DevOps setup

### Variable groups

| Variable Group | Standard vars | Secrets (masked) |
|---|---|---|
| `na-dev-axon-platform-ops` | `AUTH0_CLIENT_ID`, `AUTH0_DOMAIN`, `AWS_ACCESS_KEY_ID`, `AWS_DEFAULT_REGION`, `TF_STATE_BUCKET` | `AUTH0_CLIENT_SECRET`, `AWS_SECRET_ACCESS_KEY`, `SES_ACCESS_KEY_ID`, `SES_SECRET_ACCESS_KEY` |
| `na-qa-axon-platform-ops` | Same | Same (qa values) |
| `na-val-axon-platform-ops` | Same | Same |
| `na-prod-axon-platform-ops` | Same | Same |

### Environments (stricter than client-side repo)

| Environment | Approvals | Exclusive lock |
|---|---|---|
| `na-dev-axon-platform-ops` | 1 team member (self-approve OK) | Yes |
| `na-qa-axon-platform-ops` | 1 team member, no self-approve | Yes |
| `na-val-axon-platform-ops` | 2 senior engineers, no self-approve | Yes |
| `na-prod-axon-platform-ops` | 2 senior engineers, min 2 approvals, no self-approve | Yes |

### Pipelines

| Pipeline name | YAML file | Trigger |
|---|---|---|
| `Platform Ops - Deploy Dev` | `pipelines/deploy-dev.yml` | Auto (merge to master) |
| `Platform Ops - Promote` | `pipelines/promote.yml` | Manual |
| `Platform Ops - PR Validation` | `pipelines/pr-validation.yml` | Auto (PR to master) |
| `Platform Ops - Import Dev` | `pipelines/import-dev.yml` | Manual (one-time) |

---

## Placeholders to replace before first plan

Search for `PLACEHOLDER_` across all files. Here's the complete list:

| Placeholder | File | Replace with |
|---|---|---|
| `PLACEHOLDER_MGMT_API_AUDIENCE` | `client_grants.yaml` | Default - overridden per env in env YAML |
| `PLACEHOLDER_SUPPORT_EMAIL` | `environments/{qa,val,prod}.yaml` | Support email for each env |
| `PLACEHOLDER_SUPPORT_URL` | `environments/{qa,val,prod}.yaml` | Support URL for each env |
| `PLACEHOLDER_DEV_FROM_ADDRESS` | `environments/dev.yaml` | SES from address for dev |
| `PLACEHOLDER_QA_DOMAIN` | `environments/qa.yaml` | Auth0 QA domain (e.g., `na-qa-axon-cic.us.auth0.com`) |
| `PLACEHOLDER_QA_FROM_ADDRESS` | `environments/qa.yaml` | SES from address for qa |
| `PLACEHOLDER_VAL_DOMAIN` | `environments/val.yaml` | Auth0 val domain |
| `PLACEHOLDER_VAL_FROM_ADDRESS` | `environments/val.yaml` | SES from address for val |
| `PLACEHOLDER_PROD_DOMAIN` | `environments/prod.yaml` | Auth0 prod domain |
| `PLACEHOLDER_PROD_FROM_ADDRESS` | `environments/prod.yaml` | SES from address for prod |
| `PLACEHOLDER_DEFAULT_FROM_ADDRESS` | `email_provider.yaml` | Fallback - overridden per env |

---

## Bootstrap guide

### First deployment (targeted applies)

```bash
terraform apply -var="environment=dev" -target=module.tenant
terraform apply -var="environment=dev" -target=module.attack_protection
terraform apply -var="environment=dev" -target=module.email_provider
terraform apply -var="environment=dev" -target=module.guardian
terraform apply -var="environment=dev" -target=module.clients
terraform apply -var="environment=dev" -target=module.client_grants
terraform apply -var="environment=dev"
```

Or use the `Platform Ops - Import Dev` pipeline to import existing resources.

---

## Adding new resources

### New M2M client + grant

1. Add client to `manifests/clients.yaml` with `environments: [dev]`
2. Add grant to `manifests/client_grants.yaml` with matching `client_key`
3. Add audience override per env in `manifests/environments/{env}.yaml`
4. PR → validate → merge → approve → apply
5. Promote: expand `environments` list

### New log stream

1. Add to `manifests/log_streams.yaml` with `environments: [dev]`
2. Add sink config in `manifests/environments/dev.yaml` under `log_streams.{key}.sink`
3. Add secrets to variable group + `TF_VAR_secrets_json` in plan/apply templates
4. PR → merge → apply

### Modify singleton

1. Edit the manifest YAML directly (e.g., `guardian.yaml`, `tenant.yaml`)
2. If change is env-specific, update `manifests/environments/{env}.yaml`
3. PR → merge → apply (applies to all envs - env YAML controls differences)

---

## Documentation sources

| Topic | URL |
|---|---|
| Auth0 Terraform Provider | https://registry.terraform.io/providers/auth0/auth0/latest/docs |
| `auth0_client` | https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/client |
| `auth0_client_grant` | https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/client_grant |
| `auth0_attack_protection` | https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/attack_protection |
| `auth0_email_provider` | https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/email_provider |
| `auth0_guardian` | https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/guardian |
| `auth0_log_stream` | https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/log_stream |
| `auth0_tenant` | https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/tenant |
| Terraform S3 backend | https://developer.hashicorp.com/terraform/language/backend/s3 |
