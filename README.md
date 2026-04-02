# Auth0 Infrastructure as Code

Enterprise Auth0 tenant management using Terraform modules orchestrated by Terragrunt Stacks, with trunk-based CI/CD via Azure Pipelines.

## What This Repo Manages

| Resource | Managed Here | Managed Elsewhere |
|---|---|---|
| Applications (clients) | ✅ CRUD | — |
| Client credentials | ✅ CRUD | — |
| Actions (post-login, etc.) | ✅ Create/Read/Update | — |
| Action Modules (shared code) | ✅ Create/Read/Update | — |
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
actions/                              ← TypeScript SOURCE for Auth0 Actions
  ├── src/*.ts                        ← Write action code here
  ├── src/__tests__/*.test.ts         ← Unit tests
  └── dist/                           ← CI build output (gitignored)

action-modules/                       ← TypeScript SOURCE for Auth0 Action Modules
  ├── src/*.ts                        ← Write shared module code here
  ├── src/__tests__/*.test.ts         ← Unit tests
  └── dist/                           ← CI build output (gitignored)

environments/{dev,qa,val,prod}/
  ├── applications.json               ← Which apps exist in this env
  ├── actions.json                    ← Action metadata (name, trigger, secrets)
  ├── actions/*.js                    ← Compiled JS for THIS env (committed)
  ├── actions/manifest.json           ← Promotion tracking (SHA, git commit, who, when)
  ├── action-modules.json             ← Module metadata (name, publish, deps)
  ├── action-modules/*.js             ← Compiled JS for THIS env (committed)
  ├── action-modules/manifest.json    ← Promotion tracking
  ├── vault-connections.json          ← Vault connection config
  ├── flows.json                      ← Flow metadata + file paths + token_replacements
  ├── forms.json                      ← Form metadata + file paths + token_replacements
  ├── forms/*.form.json               ← Tokenized form exports
  ├── forms/*.flow-*.json             ← Tokenized flow exports
  ├── i18n/{form-name}/{locale}.json  ← Per-form translations (flat key-value)
  ├── env.hcl                         ← Environment identity
  └── terragrunt.stack.hcl           ← Symlink → ../../stack.hcl

stack.hcl                             ← Shared stack definition (all envs use this)

modules/                              ← Terraform modules
  ├── applications/                   ← auth0_client + auth0_client_credentials
  ├── actions/                        ← auth0_action + auth0_trigger_actions
  ├── action-modules/                 ← auth0_action_module
  ├── forms/                          ← auth0_form (with token replacement)
  ├── flows/                          ← auth0_flow (with token replacement)
  └── vault-connections/              ← auth0_flow_vault_connection

catalog/units/                        ← Terragrunt catalog (DRY unit definitions)
schemas/                              ← JSON Schema validation for env config files
scripts/
  ├── promote.mjs                     ← Promote compiled JS to target env (with manifest)
  ├── verify-manifests.mjs            ← Verify manifest SHA integrity
  ├── validate-schemas.mjs            ← Validate env JSON against schemas
  └── tokenize-export.sh             ← Convert Dashboard export to tokenized JSON
```

---

## Getting Started

### Prerequisites

```bash
# Install tools (or use .tool-versions with asdf)
terraform version   # >= 1.13.3
terragrunt version  # >= 0.78.4
node --version      # >= 20.x

# Install repo dependencies
npm install                       # root (husky, lint-staged)
cd actions && npm install         # action dependencies
cd ../action-modules && npm install  # module dependencies
```

### Developer Workflow

Pre-commit hooks (via Husky) automatically run:
- `terraform fmt` on `.tf` files
- ESLint on `.ts` files
- JSON schema validation on env config files

Pre-push hooks run the full test suite, `terraform validate`, and manifest integrity checks.

---

## How Actions Work

### The Promote CLI

Actions and modules use an explicit promotion model. Code is written once in TypeScript, compiled, then selectively promoted to each environment.

```bash
# Promote a single action to dev
npm run promote -- --env dev --action post-login-action

# Promote multiple actions to qa
npm run promote -- --env qa --action post-login-action --action enforce-mfa

# Promote everything to dev
npm run promote -- --env dev --all

# Promote a shared module
npm run promote -- --env dev --module shared-utils

# Dry run (see what would change without writing files)
npm run promote -- --env prod --all --dry-run
```

### What `promote` does

1. Builds the TypeScript source (if `dist/` is missing or stale)
2. Computes SHA256 of the compiled JS file
3. Copies the file to `environments/{env}/actions/{name}.js`
4. Updates `environments/{env}/actions/manifest.json`:

```json
{
  "post-login-action": {
    "source_file": "post-login-action.ts",
    "compiled_file": "post-login-action.js",
    "sha256": "a1b2c3d4e5f6...",
    "git_sha": "abc1234def5678...",
    "promoted_at": "2026-04-02T14:30:00Z",
    "promoted_by": "john.doe"
  }
}
```

5. You commit both the `.js` file and the manifest — git provides the version history.

### Selective Promotion

The key benefit: you can update actions 1 and 2 in TypeScript but only promote action 2 to QA:

```bash
# Both actions updated in source
vim actions/src/action-1.ts
vim actions/src/action-2.ts
cd actions && npm test && npm run build

# Only promote action-2 to qa
npm run promote -- --env qa --action action-2

# Commit — only qa/actions/action-2.js and qa manifest changed
git add environments/qa/actions/
git commit -m "promote: action-2 to qa from abc1234"
```

### Manifest Integrity

CI and pre-push hooks verify that every `.js` file's SHA256 matches its manifest entry. If someone manually edits a `.js` file without running `promote`, the build fails:

```bash
# Run manually
npm run verify:manifests

# Or verify a single env
node scripts/verify-manifests.mjs --env dev
```

### Full Action Lifecycle

```
┌──────────────────────────────────────────────────────────────────────┐
│                                                                      │
│  actions/src/post-login-action.ts    ← You write code HERE           │
│            │                                                         │
│            │  npm run build (or auto via promote)                    │
│            ▼                                                         │
│  actions/dist/post-login-action.js   ← Transient build (gitignored)  │
│            │                                                         │
│            │  npm run promote -- --env dev --action post-login-action│
│            ▼                                                         │
│  environments/dev/actions/post-login-action.js   ← COMMITTED to git  │
│  environments/dev/actions/manifest.json          ← SHA + git commit  │
│                                                                      │
│  environments/qa/actions/post-login-action.js    ← DIFFERENT copy    │
│  environments/prod/actions/post-login-action.js  ← DIFFERENT copy    │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

---

## How Action Modules Work

Action Modules are reusable code packages shared across multiple actions. They follow the exact same TypeScript → build → promote workflow as actions, but live in a separate directory.

```bash
# Write module code
vim action-modules/src/shared-utils.ts

# Test and build
cd action-modules && npm test && npm run build

# Promote to an environment
npm run promote -- --env dev --module shared-utils
```

The Terraform module sets `publish = true` by default, which creates an immutable published version on each apply. Actions can then reference the published module.

---

## How Forms & Flows Work

### Token Replacement

Forms reference flows via `#FLOW-1#` tokens. Flows reference vault connections via `#CONN-1#` tokens. These are mapped in the JSON config files:

**`flows.json`** maps token → vault connection logical name:
```json
{
  "pp_update_user": {
    "name": "Progressive Profiling (Update User)",
    "file": "forms/progressive-profiling.flow-update-user.json",
    "token_replacements": { "#CONN-1#": "auth0_mgmt" }
  }
}
```

**`forms.json`** maps token → flow logical name:
```json
{
  "progressive_profiling": {
    "name": "Progressive Profiling",
    "file": "forms/progressive-profiling.form.json",
    "token_replacements": {
      "#FLOW-1#": "pp_update_user",
      "#FLOW-2#": "pp_otp_email"
    }
  }
}
```

Token replacement is performed by the Terraform modules at plan/apply time.

### Creating a New Form

1. **Design in Auth0 Dashboard** → iterate until the UX is right
2. **Export the form JSON** from the Dashboard UI
3. **Tokenize the export**:

```bash
./scripts/tokenize-export.sh ~/Downloads/progressive-profiling.json \
    environments/dev/forms/
```

4. **Add entries** to `flows.json` and `forms.json`
5. **Commit and PR**

### i18n Translations

Translations are stored as flat key-value JSON files per locale:

```
environments/dev/i18n/progressive-profiling/en.json
environments/dev/i18n/progressive-profiling/ja.json
```

Each file is simple for translators to work with:
```json
{
  "last_name_placeholder": "姓*",
  "continue_button": "続行する",
  "terms_text": "<p>利用規約に同意します...</p>"
}
```

---

## Validation & Quality Gates

### JSON Schema Validation

All environment config files are validated against schemas in `schemas/`:

```bash
npm run verify:schemas            # all envs
node scripts/validate-schemas.mjs --env dev  # single env
```

### OPA Policies

Terraform plans are checked against OPA/Rego policies in `policies/auth0.rego`:
- Applications must use OIDC conformance
- JWT algorithm must be RS256
- Localhost URLs trigger warnings
- Resource deletions are denied
- Undeployed actions trigger warnings
- Unpublished action modules trigger warnings

Policies run via `conftest` in the pipeline after each plan.

### Checkov Security Scanning

All Terraform modules are scanned with Checkov for security best practices.

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
