# Auth0 CIC Terraform Infrastructure

Manages Auth0 CIC (Customer Identity Cloud) tenant configuration across four environments (dev, qa, val, prod) in the NA region using Terraform with YAML-driven manifests, Azure DevOps pipelines, and AWS S3 state backend.

## Architecture decisions

This repository follows these principles, arrived at through iterative design:

1. **YAML manifests are the single source of truth.** All resource definitions (clients, actions, flows, vault connections) live in YAML files. Adding a resource means editing a YAML file and opening a PR — no HCL changes required.
2. **No tfvars files.** The pipeline passes `environment` as a single `-var` flag. All other config lives in YAML manifests with per-environment overrides. This avoids two config systems.
3. **Secrets are reference names in YAML, values from the pipeline.** Non-secret values (domains, client IDs, URLs) are version-controlled in manifests. Secret values flow from Azure DevOps Variable Groups → `VAULT_AUTH0_CLIENT_SECRET` environment variable.
4. **Deployment and promotion are separate.** Merging to `master` auto-deploys to dev only. Higher environments require manually triggering the promote pipeline. This prevents accidental rollout.
5. **Two-file versioning for actions/modules/forms.** Each artifact has one canonical file (`main.js` / `main.json`). During development, a temporary `next.js` / `next.json` exists alongside it. The manifest `testing` block controls which environments use the new version. Maximum two files per artifact.
6. **`prevent_destroy` on critical resources.** Clients and vault connections have `lifecycle { prevent_destroy = true }` to prevent accidental deletion.
7. **M2M client grants are NOT managed here.** We create client shells and output their `client_id`. A separate team manages API permissions (client grants) using these IDs.
8. **Terragrunt is not used.** Single provider (Auth0), single root module, four environments. Terragrunt adds tooling overhead with no value for this scope.

## Naming conventions

| Resource | Pattern | Example |
|---|---|---|
| Azure DevOps Variable Group | `{region}-{env}-axon-cic` | `na-dev-axon-cic` |
| Azure DevOps Environment | `{region}-{env}-axon-cic` | `na-dev-axon-cic` |
| Azure DevOps Pipeline | `CIC - {purpose}` | `CIC - Deploy Dev` |
| S3 state key | `auth0/{env}/terraform.tfstate` | `auth0/dev/terraform.tfstate` |
| Auth0 client name | Descriptive purpose, no env/region | `Auth0 Actions Service` |
| Manifest keys | lowercase-kebab-case | `auth0-actions`, `auth0-m2m` |
| Action/module files | `main.js` (canonical), `next.js` (testing) | `actions/enrich-token/main.js` |
| Form files | `main.json` (canonical), `next.json` (testing) | `manifests/forms/verify-email/main.json` |

## Prerequisites

1. **Four Auth0 CIC tenants** (dev, qa, val, prod)
2. **Auth0 M2M application per tenant** for Terraform, authorized to call the Management API — [quickstart](https://github.com/auth0/terraform-provider-auth0/blob/main/docs/guides/quickstart.md)
3. **Terraform >= 1.10** for native S3 state locking — [docs](https://developer.hashicorp.com/terraform/language/backend/s3)
4. **AWS S3 bucket** with versioning and encryption enabled
5. **Azure DevOps project** with variable groups, environments, and pipelines (see setup sections below)

## Repository structure

```
auth0-infrastructure/
├── terraform/
│   ├── main.tf                                 # Root module — composes child modules
│   ├── variables.tf                            # environment (string) + secrets (map)
│   ├── outputs.tf                              # Client IDs, action IDs, flow IDs
│   ├── providers.tf                            # Empty — reads AUTH0_* env vars
│   ├── versions.tf                             # auth0/auth0 ~> 1.41 + S3 backend
│   │
│   ├── modules/                                # Reusable child modules (HCL logic)
│   │   ├── clients/                            # auth0_client (prevent_destroy)
│   │   ├── action_modules/                     # auth0_action_module
│   │   ├── actions/                            # auth0_action + auth0_trigger_actions
│   │   ├── vault_connections/                  # auth0_flow_vault_connection (prevent_destroy)
│   │   ├── flows/                              # auth0_flow
│   │   └── forms/                              # auth0_form
│   │
│   ├── manifests/                              # ALL configuration (YAML + exported JSON)
│   │   ├── environments.yaml                   # Per-env settings (domain, region)
│   │   ├── clients.yaml                        # Client definitions
│   │   ├── actions.yaml                        # Action definitions + testing routing
│   │   ├── action_modules.yaml                 # Shared module definitions
│   │   ├── flows.yaml                          # Vault connections, flows, forms
│   │   └── forms/                              # Exported Auth0 Dashboard JSON
│   │       ├── verify-email/main.json
│   │       └── mfa-challenge/main.json
│   │
│   ├── actions/                                # Action JS source (one file per action)
│   │   ├── enrich-token/main.js
│   │   ├── sync-user-metadata/main.js
│   │   ├── block-disposable-email/main.js
│   │   └── log-login-event/main.js
│   │
│   ├── action_modules/                         # Module JS source (one file per module)
│   │   ├── auth-utils/main.js
│   │   └── logging-helpers/main.js
│   │
│   └── backends/                               # Per-env S3 backend configs (key, region, encrypt, lock)
│       ├── dev.s3.tfbackend
│       ├── qa.s3.tfbackend
│       ├── val.s3.tfbackend
│       └── prod.s3.tfbackend
│
└── pipelines/                                  # Azure DevOps pipeline definitions
    ├── deploy-dev.yml                          # Auto on merge to master → dev only
    ├── promote.yml                             # Manual → qa | val | prod
    ├── pr-validation.yml                       # Auto on PR → validate + plan
    └── templates/
        ├── terraform-init.yml                  # Reusable init (uses TF_STATE_BUCKET)
        ├── terraform-plan.yml                  # Reusable plan
        └── terraform-apply.yml                 # Reusable apply (uses ADO environments)
```

## Module call order

Child modules are called in dependency order in `main.tf`:

```
1. vault_connections    → outputs vault connection IDs
2. action_modules       → outputs module IDs + version IDs
3. actions              → consumes action_module outputs
4. flows                → consumes vault_connection outputs
5. forms                → consumes flow + vault_connection outputs
6. clients              → independent (no dependencies)
```

---

## Azure DevOps setup

### Variable groups

Each group is scoped to one Auth0 tenant. These already exist in your project.

| Variable Group | Variables |
|---|---|
| `na-dev-axon-cic` | `AUTH0_CLIENT_ID`, `AUTH0_CLIENT_SECRET`, `AUTH0_DOMAIN`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION`, `TF_STATE_BUCKET`, `VAULT_AUTH0_CLIENT_SECRET` |
| `na-qa-axon-cic` | Same variables, qa-specific values |
| `na-val-axon-cic` | Same variables, val-specific values |
| `na-prod-axon-cic` | Same variables, prod-specific values |

**Variable details:**

- `AUTH0_CLIENT_ID`, `AUTH0_CLIENT_SECRET`, `AUTH0_DOMAIN` — Terraform M2M app credentials per tenant. Provider reads these from env vars automatically. [Provider docs](https://github.com/auth0/terraform-provider-auth0/blob/main/docs/index.md)
- `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION` — AWS credentials for S3 state backend
- `TF_STATE_BUCKET` — S3 bucket name, injected at `terraform init` via `-backend-config="bucket=$(TF_STATE_BUCKET)"`
- `VAULT_AUTH0_CLIENT_SECRET` — JSON string of secret values. Terraform reads it automatically (`TF_VAR_` prefix maps to `var.secrets_json`). Start with: `{"VAULT_AUTH0_CLIENT_SECRET":"your-secret"}`

The former `terraform-common-axon-cic` group is not needed. Terraform version is pinned in the pipeline template. Node version is irrelevant (Auth0 manages action runtimes).

### Environments

**Create manually** in Azure DevOps: Pipelines → Environments → New Environment.

| Environment name | Approvals | Locks |
|---|---|---|
| `na-dev-axon-cic` | None | Exclusive lock |
| `na-qa-axon-cic` | Team lead (1 approver) | Exclusive lock |
| `na-val-axon-cic` | Release manager (1 approver) | Exclusive lock |
| `na-prod-axon-cic` | 2 senior engineers, no self-approval | Exclusive lock |

Configure under each environment's "Approvals and checks" tab.

### Pipelines

**Create manually** in Azure DevOps: Pipelines → New Pipeline → GitHub → select repo → Existing Azure Pipelines YAML file.

| Pipeline name | YAML file | Trigger |
|---|---|---|
| `CIC - Deploy Dev` | `pipelines/deploy-dev.yml` | Auto (merge to master) |
| `CIC - Promote` | `pipelines/promote.yml` | Manual (env + region params) |
| `CIC - PR Validation` | `pipelines/pr-validation.yml` | Auto (PR to master) |

---

## How Terraform is invoked

```bash
# Init — bucket from variable group, rest from backend config file
terraform init \
  -backend-config="bucket=${TF_STATE_BUCKET}" \
  -backend-config=backends/${ENV}.s3.tfbackend \
  -reconfigure

# Plan — environment as single variable
terraform plan -var="environment=${ENV}" -out=${ENV}.tfplan

# Apply — saved plan artifact
terraform apply ${ENV}.tfplan
```

---

## Current resources

### Clients (6)

Defined in `manifests/clients.yaml`:

| Key | Name | Type | Purpose |
|---|---|---|---|
| `auth0-actions` | Auth0 Actions Service | M2M | User lookup by email, account linking |
| `auth0-vault` | Auth0 Vault Service | M2M | Vault connections — email config, user password/profile |
| `branded-ui-service` | Branded UI Service | M2M | Branding, universal login management |
| `email-template-service` | Email Template Service | M2M | Email template management |
| `marlo` | Marlo | SPA | Frontend app (env-specific callback URLs) |
| `mulesoft` | MuleSoft Integration | M2M | Management API proxy for external user updates |

All have `prevent_destroy = true`. M2M client grants managed by separate team using outputted `client_id`.

### Vault connections (1)

Defined in `manifests/flows.yaml`:

| Key | Name | Purpose |
|---|---|---|
| `auth0-m2m` | Auth0 M2M Connection | Auth0 Management API access for flows |

Setup config: `type` and env-specific `domain`/`client_id` in manifest (version controlled). Only `client_secret` from pipeline via `VAULT_AUTH0_CLIENT_SECRET`.

---

## Config vs. secrets

| Value | Where | Why |
|---|---|---|
| Auth0 tenant domain | `manifests/environments.yaml` | Not secret, rarely changes |
| Client callback URLs | `manifests/clients.yaml` | Not secret, env-specific |
| Vault connection domain | `manifests/flows.yaml` (per-env) | Not secret, env-specific |
| Vault connection client_id | `manifests/flows.yaml` (per-env) | Not secret, env-specific |
| Vault connection client_secret | `VAULT_AUTH0_CLIENT_SECRET` in variable group (masked) | **Secret** |
| Auth0 provider credentials | `AUTH0_*` in variable group | **Secret** |
| AWS credentials | `AWS_*` in variable group | **Secret** |
| S3 bucket name | `TF_STATE_BUCKET` in variable group | Already in your groups |

---

## Action versioning (for future use)

Each action has ONE canonical file: `main.js`. During development, `next.js` exists alongside it. The manifest `testing` block controls routing:

```yaml
actions:
  enrich-token:
    code: "main.js"
    testing:                      # Only present during active development
      file: "next.js"
      envs: ["dev", "qa"]        # These envs run next.js; others get main.js
```

**Promotion:** Append env to `testing.envs` list → merge → trigger promote pipeline.
**Rollback:** Remove env from list → merge → that env reverts to `main.js`.
**Cleanup:** After full promotion, overwrite `main.js` with `next.js` content, delete `next.js`, remove `testing` block.

Action modules follow the same pattern. Auth0 creates immutable published versions when `publish = true`. Actions consume the latest version. The promotion pipeline is the safety gate.

---

## Forms, flows, and vault connections (for future use)

```
Users see FORMS → Forms trigger FLOWS → Flows use VAULT CONNECTIONS for credentials
```

- **Vault connections** store credentials (API keys, M2M secrets). Non-secret config in manifest, secrets from pipeline.
- **Flows** define backend orchestration. Definitions extracted from exported form JSON.
- **Forms** are visual UI exported from Auth0 Dashboard as JSON with placeholder tokens (`#FLOW-1#`, `#CONN-1#`) that Terraform replaces with real resource IDs.

Forms use the same `main.json`/`next.json`/`testing` pattern.

---

## Getting started — first deployment

1. **Verify variable groups** in Azure DevOps have all required variables (see table above)
2. **Add `VAULT_AUTH0_CLIENT_SECRET`** to each variable group: `{"VAULT_AUTH0_CLIENT_SECRET":"actual-secret-value"}`
3. **Create environments** manually: `na-dev-axon-cic`, `na-qa-axon-cic`, `na-val-axon-cic`, `na-prod-axon-cic`
4. **Create three pipelines** pointing to the YAML files in `pipelines/`
5. **Update `manifests/clients.yaml`**: replace Marlo callback URLs with real domains
6. **Update `manifests/flows.yaml`**: replace `REPLACE_WITH_*_VAULT_CLIENT_ID` with real vault M2M client IDs
7. **Push to master** → `CIC - Deploy Dev` triggers automatically
8. **Verify in Auth0 dev tenant**: six clients + one vault connection should exist
9. **Trigger `CIC - Promote`** for qa, val, prod sequentially

---

## Adding new resources

### New client
1. Add entry to `manifests/clients.yaml`
2. PR → merge → deploy-dev → share `client_id` with grants team → promote

### New action
1. Create `actions/<n>/main.js`
2. Add entry to `manifests/actions.yaml`
3. PR → merge → deploy-dev

### New vault connection
1. Add entry to `manifests/flows.yaml` under `vault_connections`
2. Add secret values to `VAULT_AUTH0_CLIENT_SECRET` in each variable group
3. PR → merge → deploy-dev → promote

### New form/flow
1. Design form in Auth0 Dashboard
2. Export JSON → save to `manifests/forms/<n>/main.json`
3. Add entries to `manifests/flows.yaml`
4. PR → merge → deploy-dev → promote

---

## Documentation sources

| Topic | URL |
|---|---|
| Auth0 Terraform Provider | https://registry.terraform.io/providers/auth0/auth0/latest/docs |
| Provider quickstart | https://github.com/auth0/terraform-provider-auth0/blob/main/docs/guides/quickstart.md |
| Provider authentication | https://github.com/auth0/terraform-provider-auth0/blob/main/docs/index.md |
| `auth0_client` | https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/client |
| `auth0_action` | https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/action |
| `auth0_trigger_actions` | https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/trigger_actions |
| `auth0_action_module` | https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/action_module |
| `auth0_flow_vault_connection` | https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/flow_vault_connection |
| `auth0_flow` | https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/flow |
| `auth0_form` | https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/form |
| Terraform S3 backend | https://developer.hashicorp.com/terraform/language/backend/s3 |
| Terraform sensitive variables | https://developer.hashicorp.com/terraform/tutorials/configuration-language/sensitive-variables |
| Azure DevOps environments | https://learn.microsoft.com/en-us/azure/devops/pipelines/process/environments |
