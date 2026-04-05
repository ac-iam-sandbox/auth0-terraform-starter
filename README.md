# Auth0 CIC Terraform Infrastructure

Manages Auth0 CIC (Customer Identity Cloud) tenant configuration across four environments (dev, qa, val, prod) in the NA region using Terraform with YAML-driven manifests, Azure DevOps pipelines, and AWS S3 state backend.

## Architecture decisions

1. **YAML manifests are the single source of truth.** Resource definitions live in YAML. Adding a resource means editing YAML and opening a PR.
2. **No tfvars files.** Pipeline passes `environment` as a single `-var` flag.
3. **Config vs. secrets separation.** Non-secret values live in per-environment YAML. Actual secrets are masked pipeline variables.
4. **Nested env config mirrors manifest structure.** Environment files organized by resource type, keyed identically to resource manifests.
5. **Every apply requires approval.** Plan runs automatically. Approver reviews plan artifact before apply.
6. **Deployment and promotion are separate.** Merge to `master` plans+applies dev (after approval). Higher envs require the promote pipeline.
7. **`environments` key is required on every resource.** Controls WHERE a resource exists. `testing` block controls WHICH CODE it runs. The validation script enforces this — omitting the key fails the pipeline.
8. **`prevent_destroy` on critical resources.** Clients, vault connections, actions, and action modules.
9. **M2M client grants are NOT managed here.** Separate team uses outputted `client_id`.
10. **Commit `.terraform.lock.hcl`.** Ensures plan and apply use identical provider versions.
11. **Single pipeline run deploys everything.** Terraform dependency graph handles module -> action -> trigger ordering.
12. **Explicit `order` field controls trigger execution sequence.** Actions sharing a trigger are sorted by their `order` value. Terraform maps are unordered — without this field, actions would bind in alphabetical key order.

---

## Two resource controls — when to use which

Every resource type (clients, actions, action modules, vault connections, forms) supports both controls. They solve different problems and can be used independently or together.

### `environments` filter — controls WHERE a resource exists

**Required.** Every resource must have an explicit `environments` list. The manifest validation script enforces this on every PR and deploy. Resources that belong in all environments use `environments: [dev, qa, val, prod]`.

**Use a subset when:** The resource is new and shouldn't exist in higher environments yet, or it genuinely only belongs in certain environments (like a debug tool in dev only).

```yaml
# This action only exists in dev and qa
actions:
  new-feature-action:
    name: "New Feature Action"
    trigger: "post-login"
    environments: [dev, qa]              # ← only created in dev and qa
    code: "main.js"
    # ...
```

**Promotion workflow:**
```
Step 1: environments: [dev]              → merge → deploy to dev
Step 2: environments: [dev, qa]          → merge → promote to qa
Step 3: environments: [dev, qa, val]     → merge → promote to val
Step 4: environments: [dev, qa, val, prod] → promote to prod (final state)
```

### `testing` block — controls WHICH CODE a resource runs

The resource exists in all environments but some envs run different code. Use `main.js` (canonical) + `next.js` (testing).

**Use when:** The resource already exists everywhere and you're testing a new version of the code.

```yaml
# This action exists everywhere. Dev and qa run new code, val and prod run current.
actions:
  enrich-signup-profile:
    name: "Enrich Signup Profile"
    trigger: "pre-user-registration"
    code: "main.js"                    # ← val, prod run this
    testing:
      file: "next.js"                 # ← dev, qa run this
      envs: ["dev", "qa"]
```

**Promotion workflow:**
```
Step 1: testing.envs: ["dev"]         → merge → dev runs next.js
Step 2: testing.envs: ["dev", "qa"]   → merge → promote to qa
Step 3: testing.envs: ["dev", "qa", "val", "prod"]  → promote through
Step 4: overwrite main.js with next.js, delete next.js, remove testing block
```

### Using both together — new resource with code iteration

```yaml
actions:
  brand-new-action:
    name: "Brand New Action"
    trigger: "post-login"
    environments: ["dev"]             # Only exists in dev for now
    code: "main.js"
    testing:
      file: "next.js"                # Dev runs the experimental version
      envs: ["dev"]
```

When ready: expand `environments` to include qa, move `testing.envs` to match, promote.

### What happens when someone else promotes while I'm testing?

This is safe. Each resource's `environments` and `testing` blocks are independent YAML sections. When Developer B runs promote for qa to push their client change, Terraform evaluates every resource's filters:

- Developer A's new action has `environments: ["dev"]` → Terraform skips it in qa. No effect.
- Developer B's client has no `environments` filter → Terraform applies the change in qa.

No blocking, no conflicts. The manifest is the routing table and each resource section is independent.

### When is a resource "ready for promotion"?

The answer is always the same: **a developer submits a PR that changes the manifest.** There is no separate "mark as ready" step. The PR IS the promotion decision. The reviewer approves the manifest change. The promote pipeline applies it.

```
Developer decides "this is ready for qa"
  → PR: change environments or testing.envs to include qa
  → Reviewer approves
  → Merge to master
  → Trigger promote pipeline for qa
  → Environment approval gate
  → Apply
```

---

## Naming conventions

| Resource | Pattern | Example |
|---|---|---|
| Azure DevOps Variable Group | `{region}-{env}-axon-cic` | `na-dev-axon-cic` |
| Azure DevOps Environment | `{region}-{env}-axon-cic` | `na-dev-axon-cic` |
| Azure DevOps Pipeline | `CIC - {purpose}` | `CIC - Deploy Dev` |
| S3 state key | `auth0/{env}/terraform.tfstate` | `auth0/dev/terraform.tfstate` |
| Auth0 client name | Descriptive, no env/region | `Auth0 Actions Service` |
| Auth0 module/action name | Title Case descriptive | `Enrich Signup Profile` |
| Manifest keys | lowercase-kebab-case | `enrich-signup-profile` |

## Repository structure

```
auth0-infrastructure/
├── terraform/
│   ├── main.tf                                     # Root module
│   ├── variables.tf                                # environment + secrets_json
│   ├── outputs.tf
│   ├── providers.tf                                # Empty — AUTH0_* env vars
│   ├── versions.tf                                 # auth0/auth0 ~> 1.41 + S3 backend
│   │
│   ├── modules/
│   │   ├── clients/                                # auth0_client
│   │   ├── action_modules/                         # auth0_action_module
│   │   ├── actions/                                # auth0_action + auth0_trigger_actions
│   │   ├── vault_connections/                      # auth0_flow_vault_connection
│   │   ├── flows/                                  # auth0_flow
│   │   └── forms/                                  # auth0_form
│   │
│   ├── manifests/
│   │   ├── environments/                           # One file per env (nested by resource type)
│   │   │   ├── dev.yaml
│   │   │   ├── qa.yaml
│   │   │   ├── val.yaml
│   │   │   └── prod.yaml
│   │   ├── clients.yaml                            # Client definitions (env-agnostic)
│   │   ├── actions.yaml                            # Action definitions (env-agnostic)
│   │   ├── action_modules.yaml                     # Module definitions (env-agnostic)
│   │   ├── flows.yaml                              # Vault connections, flows, forms
│   │   └── forms/                                  # Exported dashboard JSON
│   │
│   ├── actions/
│   │   └── enrich-signup-profile/main.js
│   │
│   ├── action_modules/
│   │   ├── entry-path-verification/main.js
│   │   ├── account-linking/main.js
│   │   └── signup-validation/main.js
│   │
│   └── backends/                                   # Per-env S3 backend configs
│
└── pipelines/
    ├── deploy-dev.yml                              # Auto on merge to master
    ├── promote.yml                                 # Manual → qa | val | prod
    ├── pr-validation.yml                           # Auto on PR to master (plans all envs)
    ├── scripts/
    │   └── validate-manifests.py                   # YAML manifest cross-reference validation
    └── templates/
        ├── security-scan.yml                       # Checkov, tflint, JS lint, manifest validation
        ├── terraform-validate.yml
        ├── terraform-init.yml
        ├── terraform-plan.yml                      # Plan + rate limit monitoring
        ├── terraform-apply.yml
        └── pr-comment.yml                          # Posts plan summaries as PR comment
```

## How env-specific config works

One file per environment, nested by resource type:

```yaml
# manifests/environments/dev.yaml
tenant:
  auth0_domain: "na-dev-axon-cic.us.auth0.com"

clients:
  marlo:                                      # ← matches key in clients.yaml
    callbacks:   ["https://dev.marlo.example.com/callback"]
    logout_urls: ["https://dev.marlo.example.com"]

vault_connections:
  auth0-m2m:                                  # ← matches key in flows.yaml
    domain:    "na-dev-axon-cic.us.auth0.com"
    client_id: "qvFfk2E8XgVB0GFMVG8bIeBi5UAvIJoy"

action_modules:
  account-linking:                            # ← matches key in action_modules.yaml
    MANAGEMENT_API_DOMAIN:    "na-dev-axon-cic.us.auth0.com"
    MANAGEMENT_API_CLIENT_ID: "7d0qY6YcztsnqgjCPHQyGcS7QEVOV1xe"

actions:
  enrich-signup-profile:                      # ← matches key in actions.yaml
    API_BASE_URL: "https://dev2.nonprod-store.myalcon.com"
```

M2M clients with no env-specific values don't need entries in the env file.

## Module call order

```
1. vault_connections    → outputs connection IDs
2. action_modules       → creates + publishes, outputs { id, version_id }
3. actions              → creates actions, binds modules, binds to triggers
4. flows                → creates flows with vault refs
5. forms                → creates forms with flow + vault refs
6. clients              → independent
```

---

## Azure DevOps setup

### Variable groups

| Variable Group | Standard variables | Secrets to add (masked) |
|---|---|---|
| `na-dev-axon-cic` | `AUTH0_CLIENT_ID`, `AUTH0_CLIENT_SECRET`, `AUTH0_DOMAIN`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_DEFAULT_REGION`, `TF_STATE_BUCKET` | `VAULT_AUTH0_CLIENT_SECRET`, `MANAGEMENT_API_CLIENT_SECRET` |
| `na-qa-axon-cic` | Same | Same (qa values) |
| `na-val-axon-cic` | Same | Same |
| `na-prod-axon-cic` | Same | Same |

When adding secrets for new resources: add to variable groups AND to `TF_VAR_secrets_json` in both `terraform-plan.yml` and `terraform-apply.yml`.

### Environments

Create manually: Pipelines → Environments → New Environment → Resource type: None.

Then configure checks: click the environment → three-dot menu → "Approvals and checks".

| Environment | Approvals | Exclusive lock | Notes |
|---|---|---|---|
| `na-dev-axon-cic` | 1 team member (self-approve OK) | Yes | Fast iteration in dev |
| `na-qa-axon-cic` | 1 team member, no self-approve | Yes | PR author cannot approve their own deploy |
| `na-val-axon-cic` | Team lead or release manager | Yes | Gate before prod |
| `na-prod-axon-cic` | 2 senior engineers, min 2 approvals, no self-approve | Yes | Consider adding Business Hours check |

**Setting up approvals:**

1. Go to Pipelines → Environments → click environment name
2. Click the three-dot menu (⋯) → "Approvals and checks"
3. Click "+ Add check" → select "Approvals"
4. Add approvers, set minimum approvals, configure self-approval policy
5. Click "+ Add check" → select "Exclusive lock" (prevents concurrent applies)
6. Set timeout (recommended: 24h dev, 48h qa, 72h val/prod)

**The `deployment` job in `terraform-apply.yml` triggers these checks.** When the pipeline reaches the apply stage, it pauses and shows "Waiting for approval" in the pipeline UI. The approver reviews the plan summary artifact, then approves or rejects.

### PR comment permissions

The PR validation pipeline posts plan summaries as PR comments. This requires the Build Service identity to have "Contribute to pull requests" permission.

**Setup:** Project Settings → Repositories → Security → select your Build Service identity (usually `{Project Name} Build Service ({Org Name})`) → set "Contribute to pull requests" to **Allow**.

### Pipelines

| Pipeline name | YAML file | Trigger |
|---|---|---|
| `CIC - Deploy Dev` | `pipelines/deploy-dev.yml` | Auto (merge to master) |
| `CIC - Promote` | `pipelines/promote.yml` | Manual |
| `CIC - PR Validation` | `pipelines/pr-validation.yml` | Auto (PR to master) |

### Pipeline stages

**Deploy Dev / Promote (apply pipelines):**
```
Security & quality    → Checkov, tflint, JS syntax, manifest validation
Terraform validation  → fmt check + validate
Terraform plan        → plan artifact + plan summary + rate limit check
Terraform apply       → apply saved plan (approval gated) + apply output artifact
```

**PR Validation:**
```
Security & quality    → Checkov, tflint, JS syntax, manifest validation
Terraform validation  → fmt check + validate (dev)
Plan dev              → plan + rate limit check
Plan qa/val/prod      → parallel plans + rate limit checks (depend on dev passing)
PR comment            → posts summary table + collapsible details to the PR
```

---

## Current resources

### Clients (6)

| Key | Name | Type |
|---|---|---|
| `auth0-actions` | Auth0 Actions Service | M2M |
| `auth0-vault` | Auth0 Vault Service | M2M |
| `branded-ui-service` | Branded UI Service | M2M |
| `email-template-service` | Email Template Service | M2M |
| `marlo` | Marlo | SPA |
| `mulesoft` | MuleSoft Integration | M2M |

### Action modules (3)

| Key | Name | Config (env file) | Secrets (pipeline) |
|---|---|---|---|
| `entry-path-verification` | Entry Path Verification | — | — |
| `account-linking` | Account Linking | `MANAGEMENT_API_DOMAIN`, `MANAGEMENT_API_CLIENT_ID` | `MANAGEMENT_API_CLIENT_SECRET` |
| `signup-validation` | Signup Validation | — | — |

### Actions (1)

| Key | Name | Trigger | Config | Modules |
|---|---|---|---|---|
| `enrich-signup-profile` | Enrich Signup Profile | `pre-user-registration` | `API_BASE_URL` | `entry-path-verification`, `signup-validation` |

### Vault connections (1)

| Key | Name | Config (env file) | Secrets (pipeline) |
|---|---|---|---|
| `auth0-m2m` | Auth0 M2M Connection | `domain`, `client_id` | `VAULT_AUTH0_CLIENT_SECRET` |

---

## Config vs. secrets

| Value | Where | Why |
|---|---|---|
| All env-specific non-secret values | `manifests/environments/{env}.yaml` | Nested by resource type |
| Resource definitions | `manifests/*.yaml` | Env-agnostic, references env config keys |
| `VAULT_AUTH0_CLIENT_SECRET` | Variable group (masked) | Secret |
| `MANAGEMENT_API_CLIENT_SECRET` | Variable group (masked) | Secret |
| `AUTH0_*` provider credentials | Variable group (masked) | Secret |
| `AWS_*` credentials | Variable group (masked) | Secret |

---

## Bootstrap guide (first deployment)

To avoid partial apply issues, use targeted applies on first deploy:

```bash
terraform apply -var="environment=dev" -target=module.clients
terraform apply -var="environment=dev" -target=module.vault_connections
terraform apply -var="environment=dev" -target=module.action_modules
terraform apply -var="environment=dev" -target=module.actions
terraform apply -var="environment=dev"
```

**If partial apply happens** (resource created in Auth0, state not saved):
```bash
terraform import -var="environment=dev" \
  'module.actions.auth0_action.this["enrich-signup-profile"]' \
  "ACTION_ID_FROM_DASHBOARD"
```

---

## Adding new resources

### New client
1. Add to `manifests/clients.yaml` with `environments: [dev]` (start in dev only)
2. Add env config to `manifests/environments/dev.yaml` under `clients.{key}` (if SPA/web — M2M clients with no callbacks don't need env config)
3. PR → validate (manifest validation + plan for all envs confirms it only appears in dev) → merge → approve → apply

### New action
1. Create `actions/{name}/main.js`
2. Add to `manifests/actions.yaml` with `environments: [dev]` and an `order` value that places it correctly in its trigger's execution sequence
3. Add env config to `manifests/environments/dev.yaml` under `actions.{key}` (for any `secrets_config` entries)
4. PR → multi-env plan confirms it only appears in dev → merge → approve → apply

### New action module
1. Create `action_modules/{name}/main.js`
2. Add to `manifests/action_modules.yaml` with `environments: [dev]` and **pinned dependency versions** (never use `latest`)
3. If it has config: add values to `manifests/environments/dev.yaml` under `action_modules.{key}`
4. Reference in `actions.yaml` via `modules: [{ module_key: "{name}" }]`
5. PR → merge → single apply creates module + updates actions

### New secret
1. Add masked variable to each variable group in Azure DevOps
2. Add name to `secrets_pipeline` in the resource manifest
3. Add key to `TF_VAR_secrets_json` in BOTH `terraform-plan.yml` AND `terraform-apply.yml`

### Promote a resource to higher environments
1. Expand `environments` list to include target env (e.g. `[dev]` → `[dev, qa]`)
2. If resource needs env-specific config, add values to the target env file
3. PR → multi-env plan on PR shows the resource appearing in the new env → merge → trigger `CIC - Promote` for the target env

---

## Documentation sources

| Topic | URL |
|---|---|
| Auth0 Terraform Provider | https://registry.terraform.io/providers/auth0/auth0/latest/docs |
| `auth0_client` | https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/client |
| `auth0_action` | https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/action |
| `auth0_trigger_actions` | https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/trigger_actions |
| `auth0_action_module` | https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/action_module |
| `auth0_flow_vault_connection` | https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/flow_vault_connection |
| `auth0_form` | https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/form |
| Provider authentication | https://github.com/auth0/terraform-provider-auth0/blob/main/docs/index.md |
| Terraform S3 backend | https://developer.hashicorp.com/terraform/language/backend/s3 |
| Terraform lock file | https://developer.hashicorp.com/terraform/language/files/dependency-lock |
| Azure DevOps environments | https://learn.microsoft.com/en-us/azure/devops/pipelines/process/environments |
