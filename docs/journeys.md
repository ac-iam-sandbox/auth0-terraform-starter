# Journeys: Forms, Flows, Vault Connections, i18n, and Promotion

This repo manages Auth0 Forms, Flows, and Flow Vault Connections using stable Terraform logical keys rather than tenant-created `af_...`, `ap_...`, or `ac_...` IDs.

## Design principles

- **Git stores stable logical references**, not tenant IDs.
- **Terraform resolves logical references to real Auth0 IDs at apply time.**
- **Environment promotion is selective.** You can promote one form and only its dependent flows and vaults.
- **Translations live outside the exported form JSON** in `i18n/forms/<logical_form>/<locale>.json`.
- **Sensitive values come from Azure DevOps pipeline variables**, not from committed JSON.

## Directory layout

```text
environments/<env>/
  forms.json
  flows.json
  vault-connections.json
  forms/
    <form>.form.json
    <form>.flow-*.json
  i18n/
    forms/
      <logical_form>/
        en.json
        ja.json
```

## Stable token format

Use stable placeholders inside exported JSON files.

### Forms reference flows

```json
{
  "flow_id": "__TF_FLOW__email_verification_send_email__"
}
```

Then map the token to the Terraform flow key in `forms.json`:

```json
{
  "email_verification": {
    "name": "Email Verification",
    "file": "forms/email-verification.form.json",
    "token_replacements": {
      "__TF_FLOW__email_verification_send_email__": "email_verification_send_email",
      "__TF_FLOW__email_verification_verify_otp__": "email_verification_verify_otp"
    }
  }
}
```

### Flows reference vault connections

```json
{
  "connection_id": "__TF_VAULT__auth0_mgmt__"
}
```

Then map the token to the Terraform vault key in `flows.json`:

```json
{
  "email_verification_verify_otp": {
    "name": "Verify Email (Verify OTP and Update User)",
    "file": "forms/verify-email.flow-verify-otp.json",
    "token_replacements": {
      "__TF_VAULT__auth0_mgmt__": "auth0_mgmt"
    }
  }
}
```

This keeps committed JSON stable across environments and avoids hard-coding tenant-specific IDs.

## Adding a new vault connection

Add an entry to `vault-connections.json`.

Literal values can be committed. Sensitive values should use the `env:` prefix so Terragrunt resolves them from pipeline variables.

```json
{
  "auth0_mgmt": {
    "name": "Auth0",
    "app_id": "AUTH0",
    "account_name": "apac-dev-axon-cic.jp.auth0.com",
    "setup": {
      "client_id": "env:AUTH0_MGMT_CLIENT_ID",
      "client_secret": "env:AUTH0_MGMT_CLIENT_SECRET",
      "domain": "env:AUTH0_DOMAIN",
      "type": "OAUTH_APP"
    }
  }
}
```

## Adding a new flow

1. Create `environments/<env>/forms/<name>.flow-<purpose>.json`.
2. Replace any `ac_...` connection IDs with stable `__TF_VAULT__<logical_key>__` tokens.
3. Add a `flows.json` entry.
4. If the flow file contains any other secret placeholders, add `env_replacements`.

Example:

```json
{
  "my_flow": {
    "name": "My Flow",
    "file": "forms/my-form.flow-send-email.json",
    "token_replacements": {
      "__TF_VAULT__auth0_mgmt__": "auth0_mgmt"
    },
    "env_replacements": {
      "__ENV__MY_API_KEY__": "MY_API_KEY"
    }
  }
}
```

## Adding a new form

1. Design in the Auth0 Dashboard.
2. Export the form JSON.
3. Save the form JSON under `environments/<env>/forms/<name>.form.json`.
4. Replace any `af_...` flow IDs with stable `__TF_FLOW__<logical_key>__` tokens.
5. Add an entry to `forms.json`.
6. Move translations out of the export and into `i18n/forms/<logical_form>/<locale>.json`.

## i18n structure

Keep one file per locale, per logical form:

```text
i18n/forms/progressive_profiling/en.json
i18n/forms/progressive_profiling/ja.json
i18n/forms/email_verification/ja.json
```

This makes diffs smaller, promotions easier, and future support for prompts and Universal Login more consistent.

## Promotion workflow

Promote only the journey assets you want.

```bash
npm run promote:journeys -- --from dev --to qa --form progressive_profiling
npm run promote:journeys -- --from dev --to val --form email_verification
npm run promote:journeys -- --from dev --to qa --flow email_verification_verify_otp
npm run promote:journeys -- --from dev --to qa --vault auth0_mgmt
```

What the script does:

- copies the selected form JSON file
- copies dependent flow JSON files
- copies dependent vault entries
- copies `i18n/forms/<form>` if present
- updates `forms.json`, `flows.json`, and `vault-connections.json` in the target environment

That lets you update two forms in dev and promote only one to QA or VAL.

## Secrets from Azure DevOps

### Actions and Action Modules

In `actions.json` or `action-modules.json`, secrets can use `env:` values:

```json
{
  "my_action": {
    "name": "My Action",
    "trigger_id": "post-login",
    "code_file": "my-action.js",
    "secrets": [
      {
        "name": "API_KEY",
        "value": "env:MY_ACTION_API_KEY"
      }
    ]
  }
}
```

Terragrunt resolves `env:MY_ACTION_API_KEY` using `get_env(...)` at runtime.

### Vault Connections

Vault connection `setup` entries can use the same `env:` pattern.

### Flows

For any non-vault sensitive values embedded in the flow JSON, use explicit `env_replacements` in `flows.json`, and place placeholders like `__ENV__MY_API_KEY__` in the flow JSON file.

## Azure DevOps variable groups

Recommended pattern:

- `auth0-dev-secrets`
- `auth0-qa-secrets`
- `auth0-val-secrets`
- `auth0-prod-secrets`

Each group exposes the environment variables Terragrunt expects, for example:

- `AUTH0_CLIENT_ID`
- `AUTH0_CLIENT_SECRET`
- `AUTH0_DOMAIN`
- `AUTH0_MGMT_CLIENT_ID`
- `AUTH0_MGMT_CLIENT_SECRET`
- any flow-specific secret variables used by `env_replacements`

These variables are injected into the pipeline job and consumed by Terragrunt through `get_env(...)`.

## Apply flow

```bash
cd environments/dev
terragrunt stack generate
terragrunt run --all plan
terragrunt run --all apply
```

## Import existing tenant resources

If a form, flow, or vault connection already exists in the tenant, import it into Terraform state before the first apply to avoid duplicate creation.
