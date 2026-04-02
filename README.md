# Auth0 Infrastructure as Code

Enterprise Auth0 tenant management using Terraform modules orchestrated by Terragrunt Stacks, with trunk-based CI/CD via Azure Pipelines.

## What This Repo Manages

| Resource | Managed Here | Managed Elsewhere |
|---|---|---|
| Applications (clients) | ✅ CRUD | — |
| Client credentials | ✅ CRUD | — |
| Actions (post-login, etc.) | ✅ Create/Read/Update | — |
| Trigger bindings | ✅ Read/Update | — |
| Forms | ✅ Create/Read/Update | — |
| Flows | ✅ Create/Read/Update | — |
| Flow vault connections | ✅ Create/Read/Update | — |
| APIs / Resource servers | — | ✅ Platform team repo |
| Connections (DB, social, SAML) | — | ✅ Platform team repo |
| Connection ↔ client associations | — | ✅ Platform team repo |
| Branding / tenant settings | — | ✅ Platform team repo |
| Attack protection | — | ✅ Platform team repo |
| Log streams | — | ✅ Platform team repo |

**Why connection-client associations live in the platform repo**: The connection owner (platform team) controls which applications can use their connections. This repo declares applications; the platform repo grants access via `auth0_connection_clients`.

**Safety**: All resources have `lifecycle { prevent_destroy = true }` to prevent accidental deletions. To intentionally remove a resource, you must first remove the lifecycle block, plan, review, and apply.

## Architecture

```
actions/                              ← TypeScript SOURCE (single copy, dev workspace)
  ├── src/*.ts                        ← Write action code here
  ├── src/__tests__/*.test.ts         ← Unit tests
  └── dist/                           ← CI build output (gitignored, transient)

environments/{dev,qa,val,prod}/
  ├── applications.json               ← Which apps exist in this env
  ├── actions.json                    ← Action metadata (name, trigger, secrets)
  ├── actions/*.js                    ← Compiled JS for THIS env (committed)
  ├── vault-connections.json          ← Vault connection config
  ├── flows.json                      ← Flow metadata + file paths
  ├── forms.json                      ← Form metadata + file paths
  ├── forms/*.form.json               ← Tokenized form exports
  ├── forms/*.flow-*.json             ← Tokenized flow exports
  ├── env.hcl                         ← Environment identity
  └── terragrunt.stack.hcl           ← Stack definition

modules/                              ← Terraform modules
  ├── applications/                   ← auth0_client + auth0_client_credentials
  ├── actions/                        ← auth0_action + auth0_trigger_actions
  ├── forms/                          ← auth0_form
  ├── flows/                          ← auth0_flow
  └── vault-connections/              ← auth0_flow_vault_connection

catalog/units/                        ← Terragrunt catalog (DRY unit definitions)
scripts/
  ├── promote-actions.sh              ← Copy compiled JS to target env
  └── tokenize-export.sh             ← Convert Dashboard export to tokenized JSON
```

---

## How Actions Work

### The lifecycle of action code

```
┌──────────────────────────────────────────────────────────────────────┐
│                                                                      │
│  actions/src/post-login-action.ts    ← You write code HERE           │
│            │                                                         │
│            │  npm run build                                          │
│            ▼                                                         │
│  actions/dist/post-login-action.js   ← Transient build (gitignored)  │
│            │                                                         │
│            │  ./scripts/promote-actions.sh dev                       │
│            ▼                                                         │
│  environments/dev/actions/post-login-action.js   ← COMMITTED to git  │
│                                                                      │
│  environments/qa/actions/post-login-action.js    ← DIFFERENT copy    │
│  environments/prod/actions/post-login-action.js  ← DIFFERENT copy    │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

**Key principle**: `actions/src/` is the development workspace. `environments/{env}/actions/` is what each Auth0 tenant actually runs. They are independent copies. Promoting is an explicit, deliberate action.

### Example: verify-email action exists in all environments

```
actions/src/verify-email.ts                    ← latest source (v3)
environments/dev/actions/verify-email.js       ← compiled from v3
environments/qa/actions/verify-email.js        ← compiled from v2
environments/val/actions/verify-email.js       ← compiled from v1
environments/prod/actions/verify-email.js      ← compiled from v1
```

All four environments have `verify-email.js`, but each is a snapshot from a different point in time. Dev got v3 last week. QA got v2 two weeks ago. Val and prod are still on v1 from the initial release.

### Workflow: Develop and test a change in dev

```bash
# 1. Edit the TypeScript source
vim actions/src/verify-email.ts

# 2. Run tests
cd actions && npm test

# 3. Build
npm run build

# 4. Promote ONLY to dev
./scripts/promote-actions.sh dev

# 5. Commit and PR
git add actions/src/verify-email.ts                # source change
git add environments/dev/actions/verify-email.js   # dev's compiled copy
git commit -m "action: update verify-email logic for dev testing"

# 6. PR → merge → pipeline deploys to dev
#    QA, VAL, PROD are untouched because their actions/*.js files didn't change
```

### Workflow: Promote tested action from dev to qa

```bash
# After dev testing passes:
./scripts/promote-actions.sh qa

git add environments/qa/actions/verify-email.js
git commit -m "action: promote verify-email v3 to qa"
# PR → merge → pipeline deploys, only qa's action changes
```

### Workflow: Hotfix directly to prod

```bash
# 1. Fix the source
vim actions/src/verify-email.ts

# 2. Build and promote to val + prod only
cd actions && npm run build
./scripts/promote-actions.sh val
./scripts/promote-actions.sh prod

# 3. Commit
git add actions/src/verify-email.ts
git add environments/val/actions/verify-email.js
git add environments/prod/actions/verify-email.js
git commit -m "action: hotfix verify-email for val/prod"

# Dev and QA keep their existing versions — unaffected
```

### What about "two versions on main"?

After a dev-only promotion, main has:

```
actions/src/verify-email.ts                    ← v3 (latest source)
environments/dev/actions/verify-email.js       ← v3 (promoted)
environments/qa/actions/verify-email.js        ← v2 (untouched)
environments/prod/actions/verify-email.js      ← v1 (untouched)
```

This is correct and intentional. When the pipeline runs, Terraform compares each environment's local `verify-email.js` against what Auth0 has. Since qa's file didn't change, Terraform shows no diff for qa. Only dev sees the update.

The compiled JS files are small (typically 1-5KB per action), so having copies per environment adds negligible repo size. The tradeoff is worth it for the independent promotion control.

---

## How Forms & Flows Work

### Creating a new form

1. **Design in Auth0 Dashboard** → iterate until the UX is right
2. **Export the form JSON** from the Dashboard UI
3. **Tokenize the export** to replace real IDs with placeholders:

```bash
./scripts/tokenize-export.sh ~/Downloads/progressive-profiling.json \
    environments/dev/forms/
```

This produces:
- `progressive-profiling.form.json` — tokenized form (flow IDs → `#FLOW-1#`, etc.)
- `progressive-profiling.flow-1.json` — extracted flow with vault tokens (`#CONN-1#`)
- `progressive-profiling.tokens.json` — map showing which token = which real ID

4. **Create `flows.json` entries** mapping logical names to flow files and vault connections:

```json
{
  "pp_update_user": {
    "name": "Progressive Profiling (Update User)",
    "file": "forms/progressive-profiling.flow-1.json",
    "token_replacements": { "#CONN-1#": "auth0_mgmt" }
  }
}
```

5. **Create `forms.json` entries** mapping logical names to form files and flow references:

```json
{
  "progressive_profiling": {
    "name": "Progressive Profiling",
    "file": "forms/progressive-profiling.form.json",
    "token_replacements": {
      "#FLOW-1#": "pp_update_user",
      "#FLOW-2#": "pp_otp_email",
      "#FLOW-3#": "pp_verify_otp"
    }
  }
}
```

6. **Commit and PR** → Terraform creates the vault connections, flows, and forms

### Promoting forms to qa/prod

```bash
# Copy all form + flow files
cp environments/dev/forms/progressive-profiling.* environments/qa/forms/

# Copy and adapt the metadata configs
cp environments/dev/flows.json environments/qa/flows.json
cp environments/dev/forms.json environments/qa/forms.json
# Edit vault-connections.json if account_name differs per env

# Commit and PR
```

### Updating an existing form

1. Edit the form in the Auth0 Dashboard (dev tenant)
2. Re-export → re-tokenize → overwrite files in `environments/dev/forms/`
3. Commit and PR → Terraform detects the diff and updates

---

## M2M Scopes Required

Per-environment M2M application needs these Management API scopes:

- `read:clients`, `create:clients`, `update:clients`
- `read:client_credentials`, `create:client_credentials`, `update:client_credentials`
- `read:actions`, `create:actions`, `update:actions`
- `read:triggers`, `update:triggers`
- `read:forms`, `create:forms`, `update:forms`
- `read:flows`, `create:flows`, `update:flows`
- `read:flows_vault`, `read:flows_vault_connections`, `create:flows_vault_connections`, `update:flows_vault_connections`

No `delete:*` scopes — intentional. Combined with `prevent_destroy` in Terraform, this ensures resources cannot be accidentally deleted via pipeline.

---

## Azure DevOps Setup

### Variable Groups

Each environment needs a variable group with:

| Variable | Type | Description |
|---|---|---|
| `AUTH0_DOMAIN` | Secret | Auth0 tenant domain |
| `AUTH0_CLIENT_ID` | Secret | M2M application client ID |
| `AUTH0_CLIENT_SECRET` | Secret | M2M application client secret |
| `ARM_TENANT_ID` | Plain | Azure AD tenant ID |
| `ARM_SUBSCRIPTION_ID` | Plain | Azure subscription ID |
| `ARM_RESOURCE_GROUP` | Plain | Resource group for state storage |
| `ARM_STORAGE_ACCOUNT` | Plain | Storage account name |
| `ARM_CONTAINER_NAME` | Plain | Blob container name |

### Environment Approval Gates

| Environment | Approvals | Branch Control |
|---|---|---|
| `na-dev-axon-cic` | None | `refs/heads/main` |
| `na-qa-axon-cic` | 1 approver | `refs/heads/main` |
| `na-val-axon-cic` | 1 approver | `refs/heads/main` |
| `na-prod-axon-cic` | 2+ approvers | `refs/heads/main` |
