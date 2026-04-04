# Auth0 CIC Terraform Infrastructure

Manages Auth0 CIC (Customer Identity Cloud) tenant configuration across four environments (dev, qa, val, prod) in the NA region using Terraform with YAML-driven manifests, Azure DevOps pipelines, and AWS S3 state backend.

## Architecture decisions

1. **YAML manifests are the single source of truth.** All resource definitions live in YAML. Adding a resource means editing YAML and opening a PR.
2. **No tfvars files.** Pipeline passes `environment` as a single `-var` flag. All config lives in YAML manifests.
3. **Config vs. secrets separation.** Non-secret values (domains, client IDs, URLs) are version-controlled in manifests. Actual secrets (client_secret, API keys) are individual masked variables in Azure DevOps variable groups, assembled into JSON by the pipeline template.
4. **Deployment and promotion are separate.** Merge to `master` auto-deploys to dev only. Higher environments require manually triggering the promote pipeline.
5. **Two-file versioning.** Each artifact has `main.js` (canonical) and optionally `next.js` (testing). The manifest `testing` block controls routing.
6. **`prevent_destroy` on critical resources.** Clients and vault connections cannot be accidentally deleted.
7. **M2M client grants are NOT managed here.** We create client shells and output `client_id` for the grants team.
8. **Commit `.terraform.lock.hcl`.** The lock file ensures plan and apply use identical provider versions. Do not gitignore it.
9. **Single pipeline run deploys everything.** Terraform's dependency graph creates modules first, publishes them, then creates actions with the correct module version IDs. No need to run the pipeline twice.

## Naming conventions

| Resource | Pattern | Example |
|---|---|---|
| Azure DevOps Variable Group | `{region}-{env}-axon-cic` | `na-dev-axon-cic` |
| Azure DevOps Environment | `{region}-{env}-axon-cic` | `na-dev-axon-cic` |
| Azure DevOps Pipeline | `CIC - {purpose}` | `CIC - Deploy Dev` |
| S3 state key | `auth0/{env}/terraform.tfstate` | `auth0/dev/terraform.tfstate` |
| Auth0 client name | Descriptive purpose, no env/region | `Auth0 Actions Service` |
| Auth0 action module name | Title Case descriptive | `Entry Path Verification` |
| Auth0 action name | Title Case descriptive | `Enrich Signup Profile` |
| Manifest keys | lowercase-kebab-case | `enrich-signup-profile` |

## Repository structure

```
auth0-infrastructure/
├── terraform/
│   ├── main.tf                                     # Root module — composes child modules
│   ├── variables.tf                                # environment + secrets_json
│   ├── outputs.tf
│   ├── providers.tf                                # Empty — reads AUTH0_* env vars
│   ├── versions.tf                                 # auth0/auth0 ~> 1.41 + S3 backend
│   │
│   ├── modules/
│   │   ├── clients/                                # auth0_client (prevent_destroy)
│   │   ├── action_modules/                         # auth0_action_module + versions
│   │   ├── actions/                                # auth0_action + auth0_trigger_actions
│   │   ├── vault_connections/                      # auth0_flow_vault_connection (prevent_destroy)
│   │   ├── flows/                                  # auth0_flow
│   │   └── forms/                                  # auth0_form
│   │
│   ├── manifests/
│   │   ├── environments/                            # Per-env config (one file per env)
│   │   │   ├── dev.yaml
│   │   │   ├── qa.yaml
│   │   │   ├── val.yaml
│   │   │   └── prod.yaml
│   │   ├── clients.yaml                            # 6 client definitions
│   │   ├── actions.yaml                            # Action definitions + module refs
│   │   ├── action_modules.yaml                     # 3 module definitions
│   │   ├── flows.yaml                              # Vault connections, flows, forms
│   │   └── forms/                                  # Exported dashboard JSON
│   │
│   ├── actions/
│   │   └── enrich-signup-profile/main.js           # Pre-user-registration action
│   │
│   ├── action_modules/
│   │   ├── entry-path-verification/main.js         # Entry path API verification
│   │   ├── account-linking/main.js                 # Account linking + Mgmt API
│   │   └── signup-validation/main.js               # Joi validation + phone + consent
│   │
│   └── backends/
│       ├── dev.s3.tfbackend
│       ├── qa.s3.tfbackend
│       ├── val.s3.tfbackend
│       └── prod.s3.tfbackend
│
└── pipelines/
    ├── deploy-dev.yml                              # Auto on merge to master
    ├── promote.yml                                 # Manual → qa | val | prod
    ├── pr-validation.yml                           # Auto on PR to master
    └── templates/
        ├── security-scan.yml                       # Checkov + tflint + JS syntax
        ├── terraform-validate.yml                  # fmt check + validate
        ├── terraform-init.yml
        ├── terraform-plan.yml
        └── terraform-apply.yml
```

## Module call order

Terraform resolves dependencies automatically. Single `terraform apply` handles everything:

```
1. vault_connections    → outputs vault connection IDs
2. action_modules       → creates modules, publishes versions, outputs { id, version_id }
3. actions              → consumes module outputs for modules {} block
4. flows                → consumes vault_connection outputs
5. forms                → consumes flow + vault_connection outputs
6. clients              → independent
```

Modules are created and published BEFORE actions because the action resource references `module_id` and `module_version_id`. Terraform's dependency graph ensures correct order in a single run.

---

## Azure DevOps setup

### Variable groups

| Variable Group | Standard variables | Secrets to add (masked) |
|---|---|---|
| `na-dev-axon-cic` | `AUTH0_CLIENT_ID`, `AUTH0_CLIENT_SECRET`, `AUTH0_DOMAIN`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION`, `TF_STATE_BUCKET` | `VAULT_AUTH0_CLIENT_SECRET`, `MANAGEMENT_API_CLIENT_SECRET` |
| `na-qa-axon-cic` | Same standard variables | Same secrets (qa values) |
| `na-val-axon-cic` | Same | Same |
| `na-prod-axon-cic` | Same | Same |

**Secrets to add** (mark as secret/opaque in each variable group):

| Variable name | Purpose | Where to get the value |
|---|---|---|
| `VAULT_AUTH0_CLIENT_SECRET` | Vault connection M2M app client secret | Auth0 Dashboard → Applications → vault M2M app → Settings → Client Secret |
| `MANAGEMENT_API_CLIENT_SECRET` | Account linking module M2M client secret | Auth0 Dashboard → Applications → account-linking M2M app → Client Secret |

The pipeline template assembles these into JSON for Terraform automatically. You just add them as individual masked variables.

### Config values to update in manifests (NOT secrets — version controlled)

| File | Value | What to update |
|---|---|---|
| `manifests/environments/{env}.yaml` | `auth0_domain` per env | Replace placeholders with real tenant domains |
| `manifests/clients.yaml` | Marlo `callbacks`, `logout_urls`, `web_origins` | Replace `example.com` with real domains |
| `manifests/flows.yaml` | Vault connection `client_id` per env | Replace `REPLACE_WITH_*` with real M2M client IDs |
| `manifests/action_modules.yaml` | Account linking `MANAGEMENT_API_DOMAIN` per env | Replace placeholders with real tenant domains |
| `manifests/action_modules.yaml` | Account linking `MANAGEMENT_API_CLIENT_ID` per env | Replace placeholders with real M2M client IDs |
| `manifests/actions.yaml` | `API_BASE_URL` per env | Replace placeholders with real API URLs |

### Environments

Create manually: Pipelines → Environments → New Environment.

| Environment | Approvals | Locks |
|---|---|---|
| `na-dev-axon-cic` | None | Exclusive lock |
| `na-qa-axon-cic` | Team lead | Exclusive lock |
| `na-val-axon-cic` | Release manager | Exclusive lock |
| `na-prod-axon-cic` | 2 senior engineers, no self-approval | Exclusive lock |

### Pipelines

Create manually: Pipelines → New Pipeline → GitHub → Existing YAML file.

| Pipeline name | YAML file | Trigger |
|---|---|---|
| `CIC - Deploy Dev` | `pipelines/deploy-dev.yml` | Auto (merge to master) |
| `CIC - Promote` | `pipelines/promote.yml` | Manual (env + region params) |
| `CIC - PR Validation` | `pipelines/pr-validation.yml` | Auto (PR to master) |

### Pipeline stages

Every pipeline runs these stages in order:

```
Security & quality          → Checkov scan, tflint, JS syntax check
Terraform validation        → terraform fmt -check + terraform validate
Terraform plan              → generates and publishes plan artifact + summary
Terraform apply             → applies saved plan (approval gated per env)
```

---

## Current resources

### Clients (6)

| Key | Name | Type | Purpose |
|---|---|---|---|
| `auth0-actions` | Auth0 Actions Service | M2M | User lookup, account linking |
| `auth0-vault` | Auth0 Vault Service | M2M | Vault connections, user updates |
| `branded-ui-service` | Branded UI Service | M2M | Branding, universal login |
| `email-template-service` | Email Template Service | M2M | Email templates |
| `marlo` | Marlo | SPA | Frontend app |
| `mulesoft` | MuleSoft Integration | M2M | Management API proxy |

### Action modules (3)

| Key | Name | Dependencies | Secrets |
|---|---|---|---|
| `entry-path-verification` | Entry Path Verification | None | None |
| `account-linking` | Account Linking | `auth0@latest` | `MANAGEMENT_API_DOMAIN` (config), `MANAGEMENT_API_CLIENT_ID` (config), `MANAGEMENT_API_CLIENT_SECRET` (pipeline) |
| `signup-validation` | Signup Validation | `joi@latest`, `libphonenumber-js@latest` | None |

### Actions (1)

| Key | Name | Trigger | Modules used | Secrets |
|---|---|---|---|---|
| `enrich-signup-profile` | Enrich Signup Profile | `pre-user-registration` (v2) | `entry-path-verification`, `signup-validation` | `API_BASE_URL` (config per env) |

### Vault connections (1)

| Key | Name | Config (in manifest) | Secrets (from pipeline) |
|---|---|---|---|
| `auth0-m2m` | Auth0 M2M Connection | `type`, `domain`, `client_id` per env | `VAULT_AUTH0_CLIENT_SECRET` |

### Trigger execution order

The order of actions in `manifests/actions.yaml` defines execution order per trigger. Currently:

```
pre-user-registration:
  1. Enrich Signup Profile
```

When you add more actions to a trigger, their order in the YAML file determines execution order.

---

## Config vs. secrets — where everything lives

| Value | Location | Why |
|---|---|---|
| All env-specific non-secret values | `manifests/environments/{env}.yaml` | One file per env — domains, URLs, client IDs |
| Resource definitions | `manifests/clients.yaml`, `actions.yaml`, etc. | Env-agnostic — reference keys from env config |
| Vault connection client_secret | `VAULT_AUTH0_CLIENT_SECRET` in variable group | **Secret** |
| Module secret (MGMT client_secret) | `MANAGEMENT_API_CLIENT_SECRET` in variable group | **Secret** |
| Auth0 provider credentials | `AUTH0_*` in variable group | **Secret** |
| AWS credentials | `AWS_*` in variable group | **Secret** |

---

## Action versioning

Each action/module has ONE canonical file: `main.js`. During development, `next.js` exists alongside it. The manifest `testing` block controls routing:

```yaml
actions:
  enrich-signup-profile:
    code: "main.js"
    testing:
      file: "next.js"
      envs: ["dev", "qa"]        # These envs run next.js; others get main.js
```

**Promotion:** Append env to `testing.envs` → merge → trigger promote.
**Rollback:** Remove env from list → that env reverts to `main.js`.
**Cleanup:** After full promotion, overwrite `main.js`, delete `next.js`, remove `testing` block.

### Module versioning strategy

Auth0 creates immutable published versions when `publish = true`. When you update a module's `main.js` and deploy, Auth0 publishes a new version. Actions always consume the latest published version via the `data.auth0_action_module_versions` data source.

The promotion pipeline is the safety gate — higher environments only see new module code when you trigger promote. Within a single environment, module and action updates happen atomically in one `terraform apply`.

---

## Adding new resources

### New action
1. Create `actions/<n>/main.js`
2. Add entry to `manifests/actions.yaml` with trigger, runtime, modules, secrets_config/secrets_pipeline
3. PR → merge → deploy-dev

### New action module
1. Create `action_modules/<n>/main.js`
2. Add entry to `manifests/action_modules.yaml`
3. Reference in `manifests/actions.yaml` via `modules: [{ module_key: "<n>" }]`
4. PR → merge → deploy-dev (single run creates module + updates actions)

### Adding a secret for a new module or action
1. Add the variable to each variable group (masked) in Azure DevOps
2. Add the variable name to `secrets_pipeline` in the manifest
3. Add the variable to the `TF_VAR_secrets_json` assembly in both `terraform-plan.yml` AND `terraform-apply.yml` templates

---

## Getting started

1. **Add secrets to variable groups**: `VAULT_AUTH0_CLIENT_SECRET` and `MANAGEMENT_API_CLIENT_SECRET` (masked) in each env group
2. **Create environments**: `na-dev-axon-cic`, `na-qa-axon-cic`, `na-val-axon-cic`, `na-prod-axon-cic`
3. **Create three pipelines** pointing to the YAML files
4. **Update config placeholders** in manifests (see table above)
5. **Push to master** → `CIC - Deploy Dev` triggers
6. **Verify in dev**: 6 clients, 1 vault connection, 3 modules, 1 action
7. **Trigger `CIC - Promote`** for qa, val, prod

---

## Documentation sources

| Topic | URL |
|---|---|
| Auth0 Terraform Provider | https://registry.terraform.io/providers/auth0/auth0/latest/docs |
| `auth0_client` | https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/client |
| `auth0_action` | https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/action |
| `auth0_trigger_actions` | https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/trigger_actions |
| `auth0_action_module` | https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/action_module |
| `auth0_action_module_versions` | https://registry.terraform.io/providers/auth0/auth0/latest/docs/data-sources/action_module_versions |
| `auth0_flow_vault_connection` | https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/flow_vault_connection |
| `auth0_flow` | https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/flow |
| `auth0_form` | https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/form |
| Provider authentication | https://github.com/auth0/terraform-provider-auth0/blob/main/docs/index.md |
| Terraform S3 backend | https://developer.hashicorp.com/terraform/language/backend/s3 |
| Terraform sensitive variables | https://developer.hashicorp.com/terraform/tutorials/configuration-language/sensitive-variables |
| Azure DevOps environments | https://learn.microsoft.com/en-us/azure/devops/pipelines/process/environments |
