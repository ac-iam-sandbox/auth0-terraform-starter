# Auth0 Infrastructure as Code

Enterprise Auth0 tenant management using Terraform modules orchestrated by Terragrunt stacks, with Azure DevOps for CI/CD.

## What this repo manages

- Applications and client credentials
- Actions and Action Modules
- Forms, Flows, and Flow Vault Connections

## High-level layout

```text
actions/                                  # TypeScript source for Auth0 Actions
catalog/units/                            # Terragrunt units
modules/                                  # Terraform modules
environments/{dev,qa,val,prod}/
  applications.json
  actions.json
  actions/*.js
  action-modules.json
  action-modules/*.js
  env.hcl
  terragrunt.stack.hcl
  journeys/
    forms.json                            # form manifest
    flows.json                            # flow manifest
    vaults.json                           # vault manifest
    forms/*.form.json                     # raw/tokenized Auth0 form exports
    flows/*.flow.json                     # raw/tokenized Auth0 flow exports
    vaults/*.vault.json                   # one vault connection config per file
    i18n/forms/<form_key>/<locale>.json   # per-form translations
scripts/
  promote.mjs                             # promote actions/action modules
  promote-journeys.mjs                    # promote forms/flows/vaults selectively
  validate-schemas.mjs                    # validate manifest json files
```

## Why the journeys layout changed

The old repo shape mixed forms and flows in the same folder and had two i18n layouts. The updated structure separates them clearly:

- `journeys/forms/` only contains forms
- `journeys/flows/` only contains flows
- `journeys/vaults/` only contains vault connections
- `journeys/i18n/forms/<form_key>/` contains form translations

That makes reviews cleaner and makes selective promotion easier.

## Stable reference model

Do not commit tenant-specific Auth0 IDs like `af_...`, `ap_...`, or `ac_...` in your working manifests.

Instead:
- forms reference flows with stable placeholders like `__TF_FLOW__email_verification_send_email__`
- flows reference vaults with stable placeholders like `__TF_VAULT__auth0_mgmt__`
- Terraform resolves those placeholders to real Auth0 IDs at apply time

## Auth0 management vault connection

The repo now includes an explicit Auth0 vault connection file in each environment:

```text
environments/<env>/journeys/vaults/auth0-mgmt.vault.json
```

It uses Azure DevOps environment variables for the sensitive fields:

```json
{
  "name": "Auth0",
  "app_id": "AUTH0",
  "account_name": "env:AUTH0_DOMAIN",
  "setup": {
    "client_id": "env:AUTH0_MGMT_CLIENT_ID",
    "client_secret": "env:AUTH0_MGMT_CLIENT_SECRET",
    "domain": "env:AUTH0_DOMAIN",
    "type": "OAUTH_APP"
  }
}
```

## Actions build output shape

Compiled actions should export handlers in the Auth0-compatible CommonJS shape, for example:

```js
const onExecutePostLogin = async (event, api) => {
  if (!event.user?.email_verified) {
    api.access.deny('Please verify your email address to continue.');
    return;
  }
};

exports.onExecutePostLogin = onExecutePostLogin;
```

## Validation

```bash
npm run verify:schemas
npm run verify:manifests
npm run verify
```

## Promote actions

```bash
npm run promote -- --env dev --action post-login-action
npm run promote -- --env qa --module shared-utils
```

## Promote journeys selectively

Promote only one form and its dependent flows/vaults:

```bash
npm run promote:journeys -- --from dev --to qa --form progressive_profiling
```

Promote only one flow:

```bash
npm run promote:journeys -- --from dev --to val --flow email_verification_verify_otp
```

Promote only one vault:

```bash
npm run promote:journeys -- --from dev --to qa --vault auth0_mgmt
```

## Add a new form or flow

See `docs/journeys.md` for the exact workflow.
