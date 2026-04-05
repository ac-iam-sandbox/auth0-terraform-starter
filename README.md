# Auth0 CIC Terraform Infrastructure

Manages Auth0 CIC (Customer Identity Cloud) tenant configuration across four environments (dev, qa, val, prod) in the NA region using Terraform with YAML-driven manifests, Azure DevOps pipelines, and AWS S3 state backend.

---

## Architecture overview

This repo uses a **single Terraform codebase applied to each environment via partial backend configuration**. One set of `.tf` files serves all four environments. Environment differentiation comes from YAML manifest filters and per-environment config files — not from separate directories, branches, or workspaces.

```
One codebase → parameterized by environment → applied via pipeline
                    ↓                              ↓
        manifests/environments/dev.yaml    terraform init -backend-config=backends/dev.s3.tfbackend
        manifests/environments/qa.yaml     terraform init -backend-config=backends/qa.s3.tfbackend
        manifests/environments/val.yaml    terraform init -backend-config=backends/val.s3.tfbackend
        manifests/environments/prod.yaml   terraform init -backend-config=backends/prod.s3.tfbackend
```

**Why this approach over the alternatives:**

| Approach | Pros | Cons | Our choice |
|---|---|---|---|
| **Single codebase + backend-config** | Zero code duplication, consistent providers across envs, one PR changes all envs | Requires discipline around env filters | **Yes — this is our approach** |
| Directory per environment | Full isolation, easy to reason about | Duplicated `.tf` files, drift between envs, maintenance burden | No |
| Terraform CLI workspaces | Built-in, no tooling needed | Shared backend credentials, invisible state, HashiCorp discourages for env separation | No |
| Terragrunt | DRY, cross-config orchestration, per-env version pinning | Extra tooling, learning curve, not justified at current scale | No (revisit when splitting state) |

## Branching strategy

**Trunk-based development on a single `master` branch.** All tested code lives on master. Feature branches are short-lived and merge through PRs. There are no long-lived environment branches (no `dev`, `qa`, `prod` branches).

**Why not GitFlow or environment branches?** Terraform state is the third dimension that Git branches cannot represent. Merging a `dev` branch into `prod` doesn't merge the state — it creates phantom infrastructure or destroys existing resources. Trunk-based development with environment filters in YAML manifests is safer because the routing logic is explicit, reviewable, and enforced by the pipeline.

**How environment isolation works without branches:**

Developer A is testing a new action in dev. Developer B needs to push an urgent fix to prod. Both work on the same master branch. Isolation comes from three YAML mechanisms:

1. **`environments` filter** — Developer A's new action has `environments: [dev]`. When Developer B promotes to prod, Terraform evaluates the manifest, sees the action isn't targeted at prod, and skips it. Developer A's work never reaches prod.

2. **`testing` block** — For existing resources that need code iteration, `main.js` is production-stable and `next.js` is the testing version. Dev and qa can run `next.js` while val and prod always run `main.js`. This is enforced by both the pipeline validation and Terraform preconditions.

3. **Manifest as routing table** — Each resource section is independent. Developer A's manifest changes don't affect Developer B's resources, even in the same PR. The pipeline evaluates every resource's filters per environment.

**The promotion model:**

```
New resource:
  Step 1: environments: [dev]              → test in dev
  Step 2: environments: [dev, qa]          → test in qa
  Step 3: environments: [dev, qa, val]     → validate in val
  Step 4: environments: [dev, qa, val, prod] → production

Code iteration on existing resource:
  Step 1: testing: { file: next.js, envs: [dev] }     → dev runs next.js
  Step 2: testing: { file: next.js, envs: [dev, qa] } → qa runs next.js
  Step 3: Overwrite main.js with next.js, remove testing block, delete next.js
  Step 4: Promote to val → promote to prod (they always run main.js)
```

**Critical safety rule:** `testing.envs` may NEVER contain `val` or `prod`. This is enforced by:
- `validate-manifests.py` — hard-fails if testing.envs contains val or prod
- Terraform lifecycle preconditions — blocks plan if val/prod would resolve a testing artifact

The promotion event for val/prod is always overwriting `main.*` with the tested code, not expanding `testing.envs`.

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

**Critical rule: `testing.envs` may only contain `dev` and `qa`. Never `val` or `prod`.** This is enforced by the manifest validation script and by Terraform lifecycle preconditions. Val and prod always run `main.js` / `main.json`.

```yaml
# This action exists everywhere. Dev and qa run new code, val and prod run current.
actions:
  enrich-signup-profile:
    name: "Enrich Signup Profile"
    trigger: "pre-user-registration"
    code: "main.js"                    # val, prod always run this
    testing:
      file: "next.js"                 # dev, qa run this
      envs: [dev, qa]
```

**Promotion workflow:**
```
Step 1: testing.envs: [dev]           -> merge -> dev runs next.js
Step 2: testing.envs: [dev, qa]       -> merge -> promote to qa
Step 3: overwrite main.js with next.js, delete next.js, remove testing block
Step 4: PR -> merge -> promote to val -> promote to prod
        (val/prod always run main.js — enforced by pipeline + Terraform)
```

The promotion event is **overwriting main.js**, not expanding testing.envs. This ensures val and prod never run untested artifacts.

### Using both together — new resource with code iteration

```yaml
actions:
  brand-new-action:
    name: "Brand New Action"
    trigger: "post-login"
    environments: [dev]               # Only exists in dev for now
    code: "main.js"
    testing:
      file: "next.js"                # Dev runs the experimental version
      envs: [dev]
```

When ready: expand `environments` to include qa, move `testing.envs` to match, promote. When QA approves: overwrite main.js with next.js, delete next.js, remove testing block, expand environments to include val and prod, promote.

### What happens when someone else promotes while I'm testing?

This is safe. Each resource's `environments` and `testing` blocks are independent YAML sections. When Developer B runs promote for qa to push their client change, Terraform evaluates every resource's filters:

- Developer A's new action has `environments: [dev]` -> Terraform skips it in qa. No effect.
- Developer B's client change applies normally in qa.

No blocking, no conflicts. The manifest is the routing table and each resource section is independent.

### When is a resource "ready for promotion"?

For dev and qa: a developer submits a PR that changes the manifest (expanding `environments` or `testing.envs`). The PR IS the promotion decision.

For val and prod: a developer submits a PR that overwrites `main.*` with the tested code and removes the `testing` block. Val and prod only ever read `main.*` — this is enforced by both the pipeline validation and Terraform preconditions.

```
Developer decides "this is ready for val/prod"
  -> PR: overwrite main.js with next.js, delete next.js, remove testing block
  -> Reviewer approves (reviews the final production artifact)
  -> Merge to master
  -> Trigger promote pipeline for val, then prod
  -> Environment approval gate
  -> Apply
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
│   ├── main.tf                                     # Root module — composes child modules
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
│   │   ├── flows/                                  # auth0_flow (form-local + shared)
│   │   └── forms/                                  # auth0_form (from dashboard exports)
│   │
│   ├── manifests/
│   │   ├── environments/                           # One file per env (nested by resource type)
│   │   │   ├── dev.yaml
│   │   │   ├── qa.yaml
│   │   │   ├── val.yaml
│   │   │   └── prod.yaml
│   │   ├── clients.yaml                            # Client definitions
│   │   ├── actions.yaml                            # Action definitions (with order field)
│   │   ├── action_modules.yaml                     # Module definitions (pinned deps)
│   │   ├── flows.yaml                              # Vault connections + flows + forms
│   │   └── forms/                                  # Dashboard-exported JSON snapshots
│   │       ├── email-verification/main.json
│   │       ├── progressive-profiling/main.json
│   │       ├── account-linking/main.json
│   │       └── post-account-linking/main.json
│   │
│   ├── actions/                                    # Action source code (main.js per action)
│   │   ├── enrich-signup-profile/main.js            # pre-user-registration
│   │   ├── enforce-email-verification/main.js       # post-login order 1
│   │   ├── complete-social-profile/main.js          # post-login order 2
│   │   ├── link-accounts/main.js                    # post-login order 3
│   │   ├── post-account-linking/main.js             # post-login order 4
│   │   ├── custom-claims/main.js                    # post-login order 5
│   │   ├── token-enrichment/main.js                 # post-login order 6
│   │   └── token-check/main.js                      # post-login order 7
│   │
│   ├── action_modules/                             # Shared module source code
│   │   ├── entry-path-verification/main.js
│   │   ├── account-linking/main.js
│   │   └── signup-validation/main.js
│   │
│   └── backends/                                   # Per-env S3 backend configs
│
└── pipelines/
    ├── deploy-dev.yml                              # Auto on merge to master
    ├── promote.yml                                 # Manual → qa | val | prod
    ├── pr-validation.yml                           # Auto on PR (plans dev + qa only)
    ├── scripts/
    │   └── validate-manifests.py                   # Manifest validation + safety enforcement
    └── templates/
        ├── security-scan.yml                       # Checkov, tflint, JS lint, manifest validation
        ├── terraform-validate.yml
        ├── terraform-init.yml
        ├── terraform-plan.yml                      # Plan + rate limit monitoring + summary table
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
Terraform plan        → binary plan artifact (sensitive) + plan summary + rate limit check
Terraform apply       → apply saved plan (approval gated) + apply output artifact
```

Binary plan artifacts contain secrets in raw form. They are published only for deploy/promote pipelines where the apply stage needs them. Treat as sensitive — limited retention, limited download access.

**PR Validation (dev + qa only):**
```
Security & quality    → Checkov, tflint, JS syntax, manifest validation
Terraform validation  → fmt check + validate (dev)
Plan dev              → plan summary only (no binary plan artifact)
Plan qa               → plan summary only (no binary plan artifact)
PR comment            → posts summary table + collapsible details to the PR
```

Val/prod are intentionally excluded from PR validation to limit credential exposure. Val/prod plans run only during the promote pipeline, which is manually triggered with approval gates.

---

## Current resources

### Clients (6) — all environments

| Key | Name | Type |
|---|---|---|
| `auth0-actions` | Auth0 Actions Service | M2M |
| `auth0-vault` | Auth0 Vault Service | M2M |
| `branded-ui-service` | Branded UI Service | M2M |
| `email-template-service` | Email Template Service | M2M |
| `marlo` | Marlo | SPA |
| `mulesoft` | MuleSoft Integration | M2M |

### Action modules (3) — all environments

| Key | Name | Config (env yaml) | Secrets (pipeline) |
|---|---|---|---|
| `entry-path-verification` | Entry Path Verification | — | — |
| `account-linking` | Account Linking | `MANAGEMENT_API_DOMAIN`, `MANAGEMENT_API_CLIENT_ID` | `MANAGEMENT_API_CLIENT_SECRET` |
| `signup-validation` | Signup Validation | — | — |

### Actions (8)

**Pre-user-registration trigger** (all environments):

| Order | Key | Name | Config | Modules |
|---|---|---|---|---|
| 1 | `enrich-signup-profile` | Enrich Signup Profile | `API_BASE_URL` | `entry-path-verification`, `signup-validation` |

**Post-login trigger** (dev only — promote after testing):

| Order | Key | Name | Config | Modules |
|---|---|---|---|---|
| 1 | `enforce-email-verification` | Enforce Email Verification | `FORM_ID` | — |
| 2 | `complete-social-profile` | Complete Social Profile | `API_BASE_URL`, `PROFILE_FORM_ID`, `LINKING_FORM_ID` | `account-linking`, `entry-path-verification`, `signup-validation` |
| 3 | `link-accounts` | Link Accounts | `LINKING_FORM_ID` | `account-linking` |
| 4 | `post-account-linking` | Post Account Linking | `LINKING_SUCCESS_FORM_ID` | — |
| 5 | `custom-claims` | Custom Claims | — | — |
| 6 | `token-enrichment` | Token Enrichment | — | — |
| 7 | `token-check` | Token Check | — | — |

### Vault connections (1) — all environments

| Key | Name | Config (env yaml) | Secrets (pipeline) |
|---|---|---|---|
| `auth0-m2m` | Auth0 M2M Connection | `domain`, `client_id` | `VAULT_AUTH0_CLIENT_SECRET` |

### Flows (5) — dev only

| Key | Name | Source form | Conn refs |
|---|---|---|---|
| `ev-send-email-otp` | Verify Email (OTP and Send Email) | email-verification #FLOW-1# | — |
| `ev-verify-otp-update` | Verify Email (Verify OTP and Update) | email-verification #FLOW-2# | #CONN-1# → auth0-m2m |
| `pp-update-user` | Progressive Profiling (Update User) | progressive-profiling #FLOW-1# | #CONN-1# → auth0-m2m |
| `pp-send-email-otp` | Progressive Profiling (OTP and Send Email) | progressive-profiling #FLOW-2# | — |
| `pp-verify-otp-update` | Progressive Profiling (Verify OTP and Update) | progressive-profiling #FLOW-3# | #CONN-1# → auth0-m2m |

### Forms (4) — dev only

| Key | Name | Flows | Translations |
|---|---|---|---|
| `email-verification` | Email Verification | 2 (#FLOW-1#, #FLOW-2#) | ja |
| `progressive-profiling` | Progressive Profiling | 3 (#FLOW-1#, #FLOW-2#, #FLOW-3#) | ja |
| `account-linking` | Account Linking | 0 | ja |
| `post-account-linking` | Post Account Linking | 0 | — |

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

## Bootstrap guide (first deployment only)

Targeted applies are a **one-time bootstrap exception**. Never use `-target` in normal operations — it bypasses full-graph planning and can mask dependency issues. After initial bootstrap, all deployments should use the full `terraform apply` via the pipeline.

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

## Dev deployment checklist

Everything you need to replace and configure before the first `terraform plan` against dev.

### 1. Replace PINME dependency versions in `manifests/action_modules.yaml`

Find your current versions in the Auth0 dashboard (Actions → Library → Installed Modules) and replace:

| Package | Placeholder | Example |
|---|---|---|
| `auth0` | `PINME` | `4.16.0` |
| `joi` | `PINME` | `17.13.3` |
| `libphonenumber-js` | `PINME` | `1.12.8` |

### 2. Replace form IDs in `manifests/environments/dev.yaml`

Find each form's ID in the Auth0 dashboard (Actions → Forms → click form → ID in URL, format `ap_xxxxx`):

| Placeholder | Where used | How to find |
|---|---|---|
| `REPLACE_WITH_dev_EMAIL_VERIFICATION_FORM_ID` | `enforce-email-verification` action | Dashboard → Forms → Email Verification → ID |
| `REPLACE_WITH_dev_PROFILE_FORM_ID` | `complete-social-profile` action | Dashboard → Forms → Progressive Profiling → ID |
| `REPLACE_WITH_dev_LINKING_FORM_ID` | `complete-social-profile` + `link-accounts` actions | Dashboard → Forms → Account Linking → ID |
| `REPLACE_WITH_dev_LINKING_SUCCESS_FORM_ID` | `post-account-linking` action | Dashboard → Forms → Post Account Linking → ID |

### 3. Azure DevOps variable group: `na-dev-axon-cic`

Verify these variables exist (some may already be configured):

**Standard variables (not masked):**

| Variable | Value | Purpose |
|---|---|---|
| `AUTH0_DOMAIN` | `na-dev-axon-cic.us.auth0.com` | Auth0 provider authentication |
| `AUTH0_CLIENT_ID` | Client ID of the Terraform M2M app | Auth0 provider authentication |
| `AWS_ACCESS_KEY_ID` | IAM access key for S3 state backend | Terraform state read/write |
| `AWS_DEFAULT_REGION` | `us-east-1` | S3 bucket region |
| `TF_STATE_BUCKET` | S3 bucket name for Terraform state | Backend config |

**Secret variables (masked):**

| Variable | Value | Purpose |
|---|---|---|
| `AUTH0_CLIENT_SECRET` | Client secret of the Terraform M2M app | Auth0 provider authentication |
| `AWS_SECRET_ACCESS_KEY` | IAM secret key for S3 state backend | Terraform state read/write |
| `VAULT_AUTH0_CLIENT_SECRET` | Client secret for the vault M2M app | Vault connection setup |
| `MANAGEMENT_API_CLIENT_SECRET` | Client secret for the actions M2M app | Account-linking module |

### 4. Azure DevOps environments (manual setup)

Create these four environments in Pipelines → Environments → New Environment (Resource type: None):

| Environment | Approvals | Exclusive lock |
|---|---|---|
| `na-dev-axon-cic` | 1 team member (self-approve OK) | Yes |
| `na-qa-axon-cic` | 1 team member, no self-approve | Yes |
| `na-val-axon-cic` | Team lead or release manager | Yes |
| `na-prod-axon-cic` | 2 senior engineers, min 2 approvals, no self-approve | Yes |

For each: click environment → three-dot menu → Approvals and checks → add Approvals + Exclusive lock.

### 5. PR comment permissions

Project Settings → Repositories → Security → Build Service identity → set "Contribute to pull requests" to **Allow**.

### 6. Import existing resources

Resources that already exist in the Auth0 dev tenant must be imported into Terraform state before the first apply. Get resource IDs from the Auth0 dashboard.

```bash
cd terraform
terraform init -backend-config="bucket=$TF_STATE_BUCKET" -backend-config=backends/dev.s3.tfbackend

# Import existing forms (get IDs from Dashboard → Forms → click form → ID in URL)
terraform import -var="environment=dev" 'module.forms.auth0_form.this["email-verification"]' "ap_XXXXX"
terraform import -var="environment=dev" 'module.forms.auth0_form.this["progressive-profiling"]' "ap_XXXXX"
terraform import -var="environment=dev" 'module.forms.auth0_form.this["account-linking"]' "ap_XXXXX"
terraform import -var="environment=dev" 'module.forms.auth0_form.this["post-account-linking"]' "ap_XXXXX"

# Import existing flows (get IDs from Dashboard → Forms → Flows tab → click flow → ID in URL)
terraform import -var="environment=dev" 'module.flows.auth0_flow.this["ev-send-email-otp"]' "flow_XXXXX"
terraform import -var="environment=dev" 'module.flows.auth0_flow.this["ev-verify-otp-update"]' "flow_XXXXX"
terraform import -var="environment=dev" 'module.flows.auth0_flow.this["pp-update-user"]' "flow_XXXXX"
terraform import -var="environment=dev" 'module.flows.auth0_flow.this["pp-send-email-otp"]' "flow_XXXXX"
terraform import -var="environment=dev" 'module.flows.auth0_flow.this["pp-verify-otp-update"]' "flow_XXXXX"

# Import existing vault connection (if already created)
terraform import -var="environment=dev" 'module.vault_connections.auth0_flow_vault_connection.this["auth0-m2m"]' "ac_XXXXX"
```

### 7. Validate with plan

After all imports and placeholder replacements:

```bash
terraform plan -var="environment=dev"
```

Expected: minimal drift from imported resources (mostly formatting differences in JSON). No unexpected creates or destroys. Review any changes carefully before applying.

## Action runtime policy

Auth0 Actions execute during the login transaction. Hard limits apply to all actions and modules.

**Execution limits:**
- Each action must complete within **20 seconds**
- Maximum **20 bound actions** per trigger
- Maximum **10 npm dependencies** per action
- Action source must stay under **100 KB**
- Action modules run inside the importing action's runtime (no separate process)
- Only public npm packages supported (no private registries, no native binaries)

**Management API constraints:**
- Management API calls during login are **rate limited** — minimize API calls in post-login actions
- `searchUsersByEmail` and `executeLinkPlan` (account-linking module) make Management API calls — use aggressive timeouts
- `setPrimaryUser` has transaction constraints when changing the primary identity

**Development standards:**
- All outbound HTTP calls must have explicit timeouts (5s recommended)
- All modules must be compatible with the `node22` runtime
- Pin all npm dependency versions — never use `latest`
- Never log tokens, secrets, user IDs, or upstream identity details
- Retry logic must respect the 20-second transaction budget

**The account-linking module is the highest-risk module** because it combines privileged credentials, post-login execution, and identity mutation. Changes to this module require careful code review for: least-privilege scope usage, timeout/error handling, idempotent linking logic, and logging discipline.

---

## M2M client ownership

M2M client grants are **not managed in this repo**. The platform team manages grants via their own Terraform configuration. This repo creates the client and outputs the `client_id`. The platform team uses that ID to configure grants with least-privilege scopes.

**Current M2M clients and their intended purposes:**

| Client | Purpose | Expected scopes |
|---|---|---|
| `auth0-actions` | Action-based user lookups and account linking | `read:users`, `update:users`, `create:user_identities` |
| `auth0-vault` | Vault connections for email, password, profile updates | `update:users`, `read:users` |
| `branded-ui-service` | Branding, universal login, UI customization | `read:branding`, `update:branding` |
| `email-template-service` | Email template management | `read:email_templates`, `update:email_templates` |
| `mulesoft` | MuleSoft proxy for user updates | `update:users`, `read:users` |

**Ownership responsibilities:**
- This repo: creates and configures client objects
- Platform team repo: manages client grants and scopes (least-privilege)
- Security team: reviews scope requests, rotation cadence, retirement decisions

---

## Resource retirement process

Resources with `prevent_destroy = true` (clients, actions, action modules, vault connections, flows, forms) cannot be deleted by Terraform without explicit override. This is intentional safety.

**To retire a resource:**

1. Confirm the resource is no longer in use (check Auth0 dashboard for active references)
2. Open a PR that removes `prevent_destroy` from the resource's lifecycle block (temporary)
3. In the same PR, remove the resource from the manifest YAML
4. PR requires senior engineer approval (this is a destructive operation)
5. After merge, run `terraform plan` to confirm the destroy
6. Apply with approval — the resource is deleted from Auth0
7. Follow-up PR: restore `prevent_destroy` in the module (it was temporarily removed)

**Alternative (manual removal):**
1. Remove the resource from Terraform state: `terraform state rm 'module.actions.auth0_action.this["action-key"]'`
2. Delete manually in Auth0 dashboard
3. Remove from manifest YAML
4. This avoids touching `prevent_destroy` but leaves no audit trail in Terraform

---

## State and plan security

Terraform state files and saved plan artifacts contain **sensitive values in plaintext**, including Auth0 client secrets, vault connection credentials, and Management API secrets. This is a known Terraform behavior that cannot be avoided with the current secrets approach.

**S3 state bucket requirements:**
- Server-side encryption enabled (SSE-S3 at minimum, SSE-KMS preferred)
- Bucket versioning enabled (allows state recovery)
- Strict IAM policies — limit read access to CI/CD service principal and break-glass roles
- No public access
- CloudTrail logging for audit trail

**Plan artifact handling:**
- Saved `.tfplan` files contain sensitive values — treat as secrets
- Limit access to plan artifacts in Azure DevOps (do not publish to broadly accessible artifact feeds)
- Plan summary text files (human-readable output) may also contain sensitive values in resource arguments
- Never enable debug logging (`TF_LOG`) in production pipelines — it dumps all values including secrets

**Current risk acceptance:**
- Secrets enter Terraform via `TF_VAR_secrets_json` environment variable and per-resource `TF_VAR_*` variables
- These values persist in state and plan files
- Mitigation: restrict S3 bucket access, restrict Azure DevOps artifact access, restrict who can view pipeline logs
- Future improvement: migrate to Azure Key Vault-backed variable groups and Terraform ephemeral resources

---

## Forms and flows

Forms and flows are managed as **exported dashboard JSON snapshots**. The Auth0 dashboard is the design tool; Terraform is the deployment tool.

**Architecture:**
- Each form's exported JSON is stored in `manifests/forms/{form-name}/main.json`
- The export contains the form definition, all referenced flows, vault connection placeholders, translations, and styling
- Terraform extracts flows from the export, replaces `#CONN-N#` placeholders with vault connection IDs, and creates `auth0_flow` resources
- Terraform extracts the form definition, replaces `#FLOW-N#` placeholders with flow IDs, and creates the `auth0_form` resource

**Flow types:**
- **Form-local flows**: extracted from the owning form's export. Lifecycle is tied to the form.
- **Shared flows** (future): independently maintained with their own source file and testing block. Used when multiple forms reference the same flow.

**Adding a new form:**
1. Design and validate the form in the Auth0 dashboard
2. Export the form JSON from the dashboard
3. Save as `manifests/forms/{form-name}/main.json`
4. Inspect the export for placeholder tokens (`#FLOW-N#`, `#CONN-N#`)
5. Add entries to `flows.yaml`: one `flows` entry per `#FLOW-N#` token, one `forms` entry with `flow_refs` mapping each `#FLOW-N#` to its flow key
6. PR -> merge -> deploy

**Updating a form:**
1. Modify in the Auth0 dashboard
2. Re-export the JSON
3. To test: save as `next.json`, add `testing` block with `envs: [dev]`
4. When tested: overwrite `main.json` with `next.json`, remove `next.json` and `testing` block
5. Promote to val/prod (they always read `main.json`)

**Translations** are inside the export JSON. A translation change requires re-exporting from the dashboard (or carefully editing the `translations` section in the JSON). Translations go through the same promotion workflow as structural changes — they do not reach production without approval.

---

## Known deferred gaps

These are acknowledged limitations that are intentionally accepted at this checkpoint, with plans to address them later.

| Gap | Risk | Current mitigation | Future fix |
|---|---|---|---|
| `secrets_pipeline` wiring is not machine-validated | A manifest can pass review but fail at plan/apply because a pipeline secret is missing from `TF_VAR_secrets_json` or the Azure DevOps variable group | Validation script emits explicit warnings; Terraform plan fails fast with a clear error if a secret is missing | Move secret declarations to a central machine-readable mapping that both manifests and pipeline templates reference |
| `TF_VAR_secrets_json` aggregates multiple secrets in one blob | A single accidental exposure reveals multiple secrets at once | Marked as `sensitive = true`; state/plan access restricted | Split into per-secret `TF_VAR_*` variables or migrate to Azure Key Vault-backed variable groups with ephemeral retrieval |
| No automated SCA scanning for Action npm dependencies | Vulnerable packages could enter login-time code paths | Dependency versions must be pinned (enforced); native module denylist blocks known-unsupported packages (heuristic, not complete) | Add `npm audit` or equivalent SCA step that generates a temporary `package.json` from manifest dependencies and flags vulnerabilities |
| Binary plan artifacts contain secrets | Anyone with pipeline run access can download `.tfplan` and extract raw secret values | Binary plans published only for deploy/promote (not PRs); plan-summary.txt uses `terraform show` which redacts sensitive values | Limit artifact retention, restrict download permissions, consider regenerating plans inside the apply stage |
| Long-lived AWS access keys in variable groups | Static credentials with no automatic rotation | Keys are masked in Azure DevOps variable groups | Migrate to OIDC/workload identity federation between Azure DevOps and AWS |

---

## Future goals

| Priority | Goal | Trigger | Benefit |
|---|---|---|---|
| High | Dedicated S3 buckets per environment | When budget allows | Stronger state isolation, per-env KMS keys, separate IAM policies |
| High | Azure Key Vault-backed variable groups | When Key Vault access is available | Automatic secret rotation, full audit trail, no static credentials in pipeline config |
| High | npm SCA scanning in pipeline | When security team has bandwidth | Catches vulnerable dependencies before they enter authentication flows |
| Medium | State splitting by lifecycle | When resource count exceeds ~50-100 | Faster plans, isolated blast radius, parallel deploys per resource type |
| Medium | Terragrunt adoption | After state splitting | Cross-config orchestration, DRY backend config, per-env module versioning |
| Medium | OIDC federation for AWS auth | When AWS IAM is configured | Eliminates long-lived AWS access keys, no credential rotation burden |
| Medium | Central secrets mapping file | When secrets count grows | Machine-enforceable secret wiring validation between manifests and pipeline |
| Low | Terraform ephemeral resources | When Terraform 1.10+ matures | Secrets never persist in state files |
| Low | Rename `secrets_config` to `env_config_keys` | Next major refactor | Eliminates naming confusion (these hold non-secret env config) |
| Low | Drift detection pipeline | When team has capacity | Scheduled `terraform plan -detailed-exitcode` catches manual dashboard changes |

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
| `auth0_flow` | https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/flow |
| `auth0_form` | https://registry.terraform.io/providers/auth0/auth0/latest/docs/resources/form |
| Provider authentication | https://github.com/auth0/terraform-provider-auth0/blob/main/docs/index.md |
| Terraform S3 backend | https://developer.hashicorp.com/terraform/language/backend/s3 |
| Terraform lock file | https://developer.hashicorp.com/terraform/language/files/dependency-lock |
| Azure DevOps environments | https://learn.microsoft.com/en-us/azure/devops/pipelines/process/environments |
| Auth0 Forms/Flows guide | https://registry.terraform.io/providers/auth0/auth0/latest/docs/guides/quickstart |
