# Auth0 Terraform + GitHub Actions: Enterprise Setup Guide

This guide provides end-to-end setup for Auth0 infrastructure as code with Terraform, Azure backend locking, unified CI/CD pipeline, and GitHub Actions with enterprise best practices.

---

## Prerequisites

* Terraform ≥ 1.13.3 (required for S3-native locking)
* Node.js 20+
* AWS CLI configured
* Auth0 Management API credentials for each environment (dev, prod)
* GitHub repository with Actions enabled

### Required GitHub Secrets (enterprise ready)

Store these as repository secrets or per-environment secrets:

- `AZURE_CLIENT_ID`
- `AZURE_CLIENT_SECRET`
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`

Per environment (for terraform backend and Auth0 variables):
- `ARM_RESOURCE_GROUP_DEV`, `ARM_STORAGE_ACCOUNT_DEV`, `ARM_CONTAINER_NAME_DEV`
- `AUTH0_DOMAIN_DEV`, `AUTH0_CLIENT_ID_DEV`, `AUTH0_CLIENT_SECRET_DEV`
- `ARM_RESOURCE_GROUP_PROD`, `ARM_STORAGE_ACCOUNT_PROD`, `ARM_CONTAINER_NAME_PROD`
- `AUTH0_DOMAIN_PROD`, `AUTH0_CLIENT_ID_PROD`, `AUTH0_CLIENT_SECRET_PROD`

Then configure protected GitHub environments: `dev`, `prod` and require reviewers as needed for prod.

---

## Architecture Overview

**Pipeline Strategy:**
- **GitHub Actions workflows**: CI in `.github/workflows/ci.yml`; deploy in `.github/workflows/terraform-deploy.yml`
- **GitHub Flow**: Feature branches → PR (CI only) → main (CI + parameterized plan/apply)
- **Artifact Reuse**: reuse built artifacts for action packaging in plan/apply flows

**Pipeline Flow:**
```
Pull Request:
  → CI Stages: Build → SecurityScan → Validate → PlanPreview → Summary
  → No deployment
  
Merge to main:
  → CI Stages: Build → SecurityScan → Validate → Summary
  → CD Stages: DeployDev → DeployProd
  → All CD stages reuse artifacts from Build stage
```

**Environments:**
- **DEV** (`na-dev-cic`): Auto-deploy, rapid iteration
- **PROD** (`na-prod-cic`): Strict approvals (2 reviewers), separated init/plan/apply steps

---

## Phase 1 — AWS S3 Backend Setup (One-Time)

### 1.1 Create S3 Buckets

Create **separate S3 buckets per environment**. Enable **versioning** and **encryption** for each.

```bash
# Create buckets for each environment
for env in dev prod; do
  aws s3api create-bucket \
    --bucket "terraform-state-cic-${env}" \
    --region us-east-1
  
  # Enable versioning (required for S3-native locking)
  aws s3api put-bucket-versioning \
    --bucket "terraform-state-cic-${env}" \
    --versioning-configuration Status=Enabled
  
  # Enable encryption
  aws s3api put-bucket-encryption \
    --bucket "terraform-state-cic-${env}" \
    --server-side-encryption-configuration '{
      "Rules": [{
        "ApplyServerSideEncryptionByDefault": {
          "SSEAlgorithm": "AES256"
        }
      }]
    }'
  
  # Block public access
  aws s3api put-public-access-block \
    --bucket "terraform-state-cic-${env}" \
    --public-access-block-configuration \
      "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
done
```

### 1.2 Backend Configuration

Update backend configuration in each environment directory:

**`environments/dev/backend.tf`:**
```hcl
terraform {
  backend "s3" {
    bucket       = "terraform-state-cic-dev"
    key          = "terraform.tfstate"
    region       = "us-east-1"
    encrypt      = true
    use_lockfile = true
  }
}
```

Repeat for **prod** with respective bucket names.

### 1.3 IAM Permissions

Ensure AWS credentials have these permissions for their respective environment buckets:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:PutObject",
        "s3:DeleteObject",
        "s3:ListBucket",
        "s3:GetBucketVersioning",
        "s3:GetBucketEncryption"
      ],
      "Resource": [
        "arn:aws:s3:::terraform-state-cic-*",
        "arn:aws:s3:::terraform-state-cic-*/*"
      ]
    }
  ]
}
```

**Best Practice:** Use separate AWS IAM users or roles per environment for production isolation.

---

## Phase 2 — Auth0 Setup

### 2.1 Auth0 M2M Applications (per environment)

For each environment:

* Auth0 Dashboard → Applications → Create Application → **Machine to Machine**
* Authorize **Auth0 Management API**
* Grant required scopes (at minimum):
  * clients, client_grants, connections: read/create/update/delete
  * branding: read/update
  * prompts: read/update
  * actions: read/create/update/delete
  * attack_protection: read/update
  * log_streams: read/create/update/delete
* Record Domain, Client ID, Client Secret

### 2.2 Tenant Naming Convention

Based on pattern `na-dev-cic`:

| Environment | Tenant Domain |
|-------------|--------------|
| DEV | `na-dev-cic.us.auth0.com` |
| PROD | `na-cic.us.auth0.com` |

### 2.3 Environment Variable Files

Create non-committed `*.tfvars.json` files per environment:

```bash
cp environments/dev/dev.platform.tfvars.example environments/dev/dev.platform.tfvars.json
```

Example `dev.platform.tfvars.json`:
```json
{
  "environment": "dev",
  "app_callbacks": [
    "https://dev-app.yourcompany.com/callback",
    "https://dev-app.yourcompany.com/silent-callback"
  ]
}
```

Ensure `*.tfvars` and `*.tfvars.json` are `.gitignore`d.

---

## Phase 3 — Azure DevOps Configuration

### 3.1 Variable Groups

Create in **Pipelines → Library**.

**terraform-common-cic** (Shared):
```
TF_VERSION = 1.13.3
NODE_VERSION = 20.x
```

**na-dev-cic**:
```
AUTH0_DOMAIN = na-dev-cic.us.auth0.com
AUTH0_CLIENT_ID = <dev_client_id>             # mark as secret
AUTH0_CLIENT_SECRET = <dev_client_secret>     # mark as secret
AWS_ACCESS_KEY_ID = <aws_access_key>          # mark as secret
AWS_SECRET_ACCESS_KEY = <aws_secret_key>      # mark as secret
AWS_DEFAULT_REGION = us-east-1
TF_STATE_BUCKET = terraform-state-cic-dev
app_callbacks = https://dev-app.yourcompany.com/callback,https://dev-app.yourcompany.com/silent-callback
ENVIRONMENT_NAME = na-dev-cic
```

Repeat for **na-prod-cic** with respective values.

**Note:** AWS credentials are stored in variable groups (not service connections). Consider migrating to Azure Key Vault for enhanced security.

### 3.2 Environments and Approvals

Create Azure DevOps **Environments**:

* `na-dev-cic` - No approval (auto-deploy)
* `na-prod-cic` - **Required: 2 approvers (tech lead + ops), business hours enforcement**

For `na-prod-cic`, configure:
- Approvals and checks → Add Approval
- Minimum 2 approvers
- Timeout: 7 days
- Optional: Business hours restriction

### 3.3 GitHub Branch Protection

In GitHub: **Settings → Branches → Add rule** for `main`:

```
☑ Require a pull request before merging
  ☑ Require approvals: 2
  ☑ Dismiss stale pull request approvals when new commits are pushed

☑ Require status checks to pass before merging
  ☑ Require branches to be up to date before merging
  Required status checks:
    - Build (from azure-pipelines.yml)
    - SecurityScan (from azure-pipelines.yml)
    - Validate (from azure-pipelines.yml)

☑ Require conversation resolution before merging

☑ Do not allow bypassing the above settings

☑ Restrict who can push to matching branches (DevOps team only)
```

### 3.4 Pipeline Setup

**Create the unified pipeline:**

1. Navigate to **Pipelines** in Azure DevOps
2. Click **New Pipeline**
3. Select **GitHub** as code location
4. Authorize and select your repository
5. Choose **Existing Azure Pipelines YAML file**
6. Select:
   - **Branch**: `master`
   - **Path**: `/azure-pipelines.yml`
7. Click **Continue**
8. Review the YAML
9. Click **Save** (or **Run** to test immediately)
10. Rename pipeline to: `cic-unified` or `Auth0 CI/CD Pipeline`

**Pipeline permissions:**
- Go to the pipeline → **⋮** → **Settings** → **Triggers**
- Verify triggers match YAML configuration
- Ensure pipeline has access to all variable groups and environments

---

## Phase 4 — Local Validation (DEV First)

### 4.1 Verify Terraform Version

```bash
terraform version
# Should be >= 1.13.3
```

### 4.2 Export Credentials (DEV)

```bash
export AUTH0_DOMAIN="na-dev-cic.us.auth0.com"
export AUTH0_CLIENT_ID="your_dev_client_id"
export AUTH0_CLIENT_SECRET="your_dev_client_secret"
export AWS_ACCESS_KEY_ID="your_dev_aws_key"
export AWS_SECRET_ACCESS_KEY="your_dev_aws_secret"
export AWS_DEFAULT_REGION="us-east-1"
```

### 4.3 Build and Test Actions

```bash
cd actions
npm ci
npm run build
npm test
```

### 4.4 Initialize and Plan

```bash
cd ../environments/dev
terraform init \
  -backend-config="bucket=terraform-state-cic-dev" \
  -backend-config="key=terraform.tfstate" \
  -backend-config="region=us-east-1" \
  -backend-config="use_lockfile=true" \
  -backend-config="encrypt=true"

terraform plan -var-file=dev.platform.tfvars.json
```

Validate planned resources (tenant, branding, connections, actions, trigger bindings, attack protection).

### 4.5 Apply to DEV

```bash
terraform apply -var-file=dev.platform.tfvars.json
```

Lock file appears during apply: `terraform.tfstate.tflock` in S3 bucket.

### 4.6 Verify in Auth0

* Branding: Universal Login reflects colors/logo
* Connections: Passwordless email exists and enabled
* Actions: Custom action present, deployed, bound to Login flow
* Attack Protection: Policies enabled
* Applications: Sample app exists if configured

---

## Phase 5 — Pipeline Execution

### 5.1 Development Workflow

**Standard feature development:**

```bash
# 1. Create feature branch
git checkout -b feature/add-mfa-enforcement

# 2. Make changes, test locally in DEV
cd environments/dev
terraform plan -var-file=dev.platform.tfvars.json
terraform apply -var-file=dev.platform.tfvars.json

# 3. Commit and push
git add .
git commit -m "feat: add MFA enforcement action"
git push origin feature/add-mfa-enforcement

# 4. Create Pull Request to master
# Pipeline runs CI stages only:
#   ✓ Build Actions
#   ✓ Run Tests  
#   ✓ Security Scan (Checkov)
#   ✓ Validate Terraform (all environments)
#   ✓ Generate plan preview
#   ✗ Deployment stages DO NOT run (master only)

# 5. Get 2 approvals, address review comments

# 6. Merge PR to master
# Pipeline runs ALL stages:
#   ✓ Build Actions (builds once)
#   ✓ Run Tests
#   ✓ Security Scan
#   ✓ Validate Terraform
#   ✓ CI Summary
#   ✓ Deploy DEV (automatic, uses Build artifacts)
#   ✓ Deploy QA (automatic or manual approval)
#   ⏸ Deploy VAL (manual approval - 1 reviewer)
#   ⏸ Deploy PROD (manual approval - 2 reviewers)
```

**Key difference:** The unified pipeline automatically progresses from CI to CD on master. No separate CD pipeline trigger needed.

### 5.2 First Pipeline Run

```bash
# Add the unified pipeline
git add azure-pipelines.yml
git commit -m "ci: add unified CI/CD pipeline"
git push origin master
```

**Pipeline execution:**
1. **CI stages run** (Build, SecurityScan, Validate, CISummary)
2. **CD stages start automatically** after CI passes
3. **DEV deploys** immediately (reuses artifacts from Build stage)
4. **QA deploys** after DEV
5. **VAL waits** for manual approval
6. **PROD waits** for manual approval (2 reviewers)

### 5.3 Production Deployment Process

When PROD stage reaches approval gate:

1. **Review artifacts:**
   - Download `prod-plan.txt` from pipeline artifacts
   - Review planned changes carefully
   - Verify DEV, QA, VAL deployed successfully

2. **Approve deployment:**
   - Navigate to pipeline run → PROD stage
   - Click **Review**
   - Both approvers must review and approve
   - Optionally add approval comments

3. **Monitor deployment:**
   - Watch PROD deployment progress through steps:
     - Step 1: Terraform Init
     - Step 2: Terraform Plan (published for review)
     - Step 3: Terraform Apply
     - Step 4: Capture Outputs
     - Step 5: Deployment Summary

4. **Post-deployment verification:**
   - Test Auth0 login flow in production
   - Verify actions execute correctly
   - Check Auth0 logs for errors
   - Confirm applications authenticate successfully

### 5.4 Pipeline Artifacts

Each pipeline run produces artifacts:

**CI Artifacts:**
- `actions-dist` - Built TypeScript actions (reused by all CD stages)
- `plan-preview-dev` - DEV plan preview (PR only)
- `security-scan-results` - Checkov security scan results

**CD Artifacts:**
- `dev-plan` and `dev-outputs` - DEV deployment plan and outputs
- `qa-artifacts` - QA deployment plan and outputs
- `val-artifacts` - VAL deployment plan and outputs
- `prod-plan` and `prod-outputs` - PROD deployment plan and outputs

Download artifacts: Pipeline run → **⋯** → **Artifacts**

---

## Operations

### Local Dev Loop

```bash
# Modify modules or actions
vim modules/tenant/main.tf
vim actions/src/verified-email.ts

# Test in DEV locally
cd environments/dev
terraform plan -var-file=dev.platform.tfvars.json
terraform apply -var-file=dev.platform.tfvars.json

# Create PR when ready
git checkout -b feature/my-changes
git commit -am "feat: my changes"
git push origin feature/my-changes
# Open PR, wait for CI, get reviews, merge
```

### Adding or Updating Actions

* Implement TypeScript action and tests in `actions/`
* Build and test: `npm test && npm run build`
* Update Terraform modules
* Apply to DEV locally for testing
* Create PR to trigger CI validation
* Merge to deploy through pipeline

### Rollbacks

**Preferred Method (Revert and Redeploy):**
```bash
# Find the problematic commit
git log --oneline

# Revert it
git revert <commit-hash>
git push origin master

# Pipeline automatically redeploys reverted state
# Approve through environments as usual
```

**Emergency Manual Rollback (PROD Only):**
```bash
# Checkout last known good commit
git checkout <last-good-commit>

# Apply to PROD manually
cd environments/prod
export AUTH0_DOMAIN="na-cic.us.auth0.com"
export AUTH0_CLIENT_ID="..."
export AUTH0_CLIENT_SECRET="..."
export AWS_ACCESS_KEY_ID="..."
export AWS_SECRET_ACCESS_KEY="..."

terraform init
terraform plan -var-file=prod.platform.tfvars.json
terraform apply -var-file=prod.platform.tfvars.json

# Document in incident report
# Create proper revert PR afterward
```

**Targeted Rollback:**
```bash
cd environments/prod

# Mark resource for recreation
terraform taint module.problematic_action.auth0_action.this

# Or destroy specific resource
terraform destroy -target=module.problematic_action.auth0_action.this

# Then reapply
terraform apply -var-file=prod.platform.tfvars.json
```

---

## Troubleshooting

### Backend configuration changed

```bash
cd environments/dev
terraform init -reconfigure
```

### Action JS file not found

```bash
cd actions
npm ci
npm run build

# Verify dist/ exists
ls -la dist/
```

### State locked / cannot acquire lock

Confirm no concurrent runs, then inspect S3 for `.tflock`:

```bash
aws s3 ls s3://terraform-state-cic-dev/terraform.tfstate.tflock

# If stale (confirmed no active runs):
aws s3 rm s3://terraform-state-cic-dev/terraform.tfstate.tflock
```

### AWS credentials error in pipeline

* Verify variable group has `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` marked as secret
* Test credentials locally:
  ```bash
  aws sts get-caller-identity
  ```
* Check IAM policy has required S3 permissions
* Verify `TF_STATE_BUCKET` variable matches actual bucket name
* Ensure pipeline has permission to use variable group

### Versioning not enabled

```bash
aws s3api put-bucket-versioning \
  --bucket terraform-state-cic-prod \
  --versioning-configuration Status=Enabled
```

### Terraform version mismatch

Upgrade to ≥ 1.13.3 and re-run `terraform init`.

### Pipeline not triggering

**CI stages not running on PR:**
- Verify GitHub-Azure DevOps connection
- Check trigger paths in YAML match changed files
- Ensure branch protection requires pipeline status checks
- Verify Azure Pipelines GitHub App is installed

**CD stages not running after merge:**
- Verify merge to master completed successfully
- Check pipeline trigger includes master branch
- Verify condition: `eq(variables['Build.SourceBranch'], 'refs/heads/master')`
- Check no path filters exclude your changes

**Pipeline shows "Skipped" for deployment stages:**
- This is normal for PR builds (deployment only on master)
- Merge the PR to master to trigger deployments

### Pipeline permission errors

**"The pipeline does not have access to resource":**
- Click **View** → **Permit** for each resource (variable group, environment)
- Or pre-authorize:
  - Library → Variable group → Security → Authorize pipeline
  - Environments → Environment → Security → Authorize pipeline

### Security scan failures

**Checkov finding issues:**
```bash
# Run locally to debug
pip install checkov
checkov -d environments/ --framework terraform

# Address findings or suppress with skip annotations in Terraform:
# resource "auth0_tenant" "main" {
#   #checkov:skip=CKV_SECRET_6:Acceptable risk - documented in security review
# }
```

### Action not enforcing verified email

* Confirm action exists, is deployed, and bound to Login flow in Auth0 Dashboard
* Inspect Terraform state:
  ```bash
  terraform state show module.verified_email_action.auth0_action.post_login
  terraform state show module.verified_email_action.auth0_trigger_actions.login
  ```
* Check Auth0 logs (Monitoring → Logs) for action execution errors
* Verify action code is correct in `actions/dist/`

---

## Security Checklist

* ✅ `*.tfvars` and `*.tfvars.json` with secrets excluded via `.gitignore`
* ✅ All secrets marked as secret in Azure DevOps variable groups
* ✅ S3 buckets: encryption enabled, versioning enabled, public access blocked
* ✅ Separate S3 buckets per environment
* ✅ Manual approval gates for VAL and PROD (2 approvers for PROD)
* ✅ Least-privilege IAM for S3 state (preferably separate AWS accounts per environment)
* ✅ No hardcoded secrets in code or committed to repository
* ✅ Auth0 M2M applications only (no user context)
* ✅ GitHub branch protection with required reviews (2) and status checks
* ✅ Unified pipeline with clear CI/CD separation via conditions
* ✅ Security scanning with Checkov on every build
* ✅ Artifact reuse prevents tampering between CI and CD

**Recommended enhancements:**
- Migrate secrets to Azure Key Vault
- Enable MFA for Auth0 tenant admins
- Configure Auth0 log streaming to SIEM
- Set up AWS CloudTrail for S3 access logging
- Implement secret rotation policy
- Regular security audits and access reviews

---

## Monitoring and Observability

**Pipeline Monitoring:**
- Azure DevOps → Pipelines → Analytics
- Track success rates, duration, failure patterns
- Set up email/Slack notifications for failures

**Auth0 Monitoring:**
- Auth0 Dashboard → Monitoring → Logs
- Review login failures, action errors, anomalies
- Configure anomaly detection (brute force, breached passwords)

**Terraform State:**
- Review state files for drift periodically
- Use `terraform plan` regularly to detect drift
- Consider scheduled drift detection pipeline

**Recommended Metrics:**
- Pipeline success rate by environment
- Average deployment duration
- Auth0 login success/failure rates
- Action execution times
- Terraform state size and complexity

---

## Performance Tips

* **Pipeline caching**: npm packages cached automatically (if `package-lock.json` exists)
* **Local testing**: Use `terraform init -backend=false` for faster iteration
* **Path filters**: Only relevant paths trigger pipelines (actions/**, modules/**, environments/**)
* **Parallel validation**: CI stage validates all environments in parallel
* **Artifact reuse**: CD stages download pre-built artifacts (no rebuild)

---

## References

* [Terraform Auth0 Provider](https://registry.terraform.io/providers/auth0/auth0/latest/docs)
* [Auth0 Management API](https://auth0.com/docs/api/management/v2)
* [Terraform S3 Backend (S3-native locking)](https://developer.hashicorp.com/terraform/language/backend/s3)
* [Azure DevOps Environments](https://learn.microsoft.com/en-us/azure/devops/pipelines/process/environments)
* [Checkov Documentation](https://www.checkov.io/1.Welcome/What%20is%20Checkov.html)
* [Azure Pipelines YAML Schema](https://learn.microsoft.com/en-us/azure/devops/pipelines/yaml-schema/)

---

## Support

* **Pipeline Issues**: Review Azure DevOps pipeline logs and run history
* **Terraform Issues**: Check Terraform state and apply logs
* **Auth0 Issues**: Review Auth0 Dashboard logs (Monitoring → Logs)
* **AWS Issues**: Check S3 bucket permissions and CloudTrail logs
