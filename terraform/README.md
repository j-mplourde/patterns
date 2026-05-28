# AWS Multi-Account Terraform + Terragrunt

A reference layout for managing many AWS accounts (one per environment, plus
dedicated foundation accounts for networking / management / ops / backup) with
**Terragrunt orchestrating Terraform**. The point is to push *blast radius* and
*state isolation* down to the account boundary, which is the strongest
isolation AWS provides.

---

## Why one account per environment?

The AWS-recommended multi-account strategy (see "Organizing Your AWS
Environment Using Multiple Accounts" in the AWS whitepapers) places each
workload-environment pair in its own account so that:

- **IAM is naturally siloed.** A role in `orbit-dev` cannot, by default, touch
  anything in `orbit-prod`. There's no "just put a tag on it and pray" - the
  isolation is at the trust-boundary level.
- **Quotas are independent.** A runaway dev workload can't starve prod of EIPs,
  ENIs, EC2 instances.
- **Billing is clean.** Every line item is already labeled.
- **Compromise is contained.** Stolen creds in one account don't grant
  anything in any other account.

Then, *foundation* responsibilities that need a single org-wide source of
truth get their own accounts too: management (Control Tower + SSO), networking
(shared public DNS), operations-tooling (ECR + CI OIDC + image builders),
backup (centralized vault for cross-account snapshot copies).

```
                       ┌──────────────────┐
                       │  management       │  Control Tower, Identity Center
                       └──────────────────┘
                                │
        ┌──────────────────┬───┴───┬──────────────────┐
        ▼                  ▼       ▼                  ▼
 ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐
 │ networking  │  │ operations  │  │   backup    │  │  workloads  │
 │  (Route 53) │  │  -tooling   │  │  (vaults)   │  │ (per env)   │
 │             │  │  (ECR/OIDC) │  │             │  │             │
 └─────────────┘  └─────────────┘  └─────────────┘  └─────────────┘
                                                   ┌──────────────┴──────────────┐
                                                   ▼              ▼              ▼
                                           orbit-dev      orbit-qa      orbit-prod
                                           (account A)    (account B)   (account C)
```

---

## What Terragrunt does for us

Terragrunt is invoked once per leaf folder under `environments/`. It does
three jobs for us:

1. **Account routing.** A single map in `environments/root.hcl` (`env_map`)
   maps each leaf folder path to its AWS account id, SSO profile, region, and
   S3 state bucket. The leaf's `terragrunt.hcl` resolves itself by calling
   `path_relative_to_include()` and looking up the match.
2. **Generated boilerplate.** `root.hcl` generates `provider.tf`, `backend.tf`,
   and `versions.tf` into each leaf at run time, so no environment hand-writes
   the same provider block twice.
3. **Cross-account dependencies.** A workload's `terragrunt.hcl` declares
   `dependency` blocks on the foundation accounts it reads from (e.g. a
   `hosted_zone_id` from `networking`, an `ecr_base_url` from
   `operations_tool`). Terragrunt orders applies and injects outputs as inputs.

---

## Folder structure

```
terraform/
├── environments/
│   ├── root.hcl                  ← env_map, backend config, provider generation
│   ├── management/ca-central-1/
│   ├── networking/ca-central-1/
│   ├── operations_tool/ca-central-1/
│   ├── backup/ca-central-1/
│   └── workloads/
│       └── orbit/dev/ca-central-1/      ← example workload env
│           ├── terragrunt.hcl
│           ├── main.tf                  ← consumes modules/
│           ├── variables.tf
│           └── outputs.tf
└── modules/
    ├── authentication/         Cognito user pool + client (web)
    ├── certificate/            ACM cert, DNS-validated in networking acct
    ├── database/               RDS Postgres
    │   └── backup/             AWS Backup plan with cross-account copy
    ├── dns/                    Route 53 record (uses aliased provider)
    ├── docker_repository/      ECR repo + lifecycle policy
    ├── email/                  SES domain identity + DKIM
    ├── encryption/             KMS CMK + alias
    ├── governance/             GuardDuty + Security Hub + Inspector2
    ├── identity_center/        SSO permission sets + group assignments
    ├── iot/                    IoT policy + topic rule -> SQS
    ├── mobile_user_pool/       Cognito user pool sized for mobile
    ├── monitoring/             CloudWatch dashboard
    ├── network/                VPC (minimal)
    ├── oidc_provider/          IAM OIDC for CI federation
    ├── queue_worker/           Lambda event source mapping for SQS
    ├── secrets_manager/        SSM Parameter Store entries
    ├── server/
    │   ├── app/                EC2 host + SSM instance profile (Ansible-tagged)
    │   ├── app_simplified/     smaller cousin of server/app
    │   ├── application_load_balancer/   ALB + HTTPS listener + target group
    │   └── image_builder/      EC2 Image Builder pipeline (in ops-tooling acct)
    ├── serverless/
    │   ├── main/               Lambda function + role + log group
    │   ├── dependency_node/    Lambda layer (Node)
    │   └── dependency_python/  Lambda layer (Python)
    └── storage/
        └── s3/                 Hardened S3 bucket (KMS, versioning, BPA)
```

The modules are a **reference catalog** of the building blocks used to compose
an environment. They are intentionally tight and illustrative, not exhaustive
production code.

---

## How `env_map` works

`environments/root.hcl` declares a single map keyed by an arbitrary slug:

```hcl
env_map = {
  orbit_dev_ca_central_1 = {
    account_id          = "222222000001"
    path                = "workloads/orbit/dev/ca-central-1"
    region              = "ca-central-1"
    profile             = "terraform-acme-orbit-dev"
    state_bucket        = "orbit-dev-tfstate"
    state_bucket_key    = "ca-central-1"
    state_bucket_region = "ca-central-1"
    project             = "orbit"
    environment         = "dev"
  }
  # ... and one entry per foundation/workload account
}
```

Every leaf `terragrunt.hcl` then resolves *itself* with:

```hcl
locals {
  full_env_key = path_relative_to_include()
  matching_env = [for k, v in include.root.locals.env_map : v if v.path == local.full_env_key]
  cfg          = local.matching_env[0]
}
```

…and the rest of the file uses `local.cfg.region`, `local.cfg.profile`, etc.
That means adding a new environment is two things:

1. Add an entry to `env_map`.
2. Create a folder at the path you declared, with a `terragrunt.hcl` that
   copies the include/dependency/inputs shape of an existing one.

No new provider code, no new backend config, no copy-pasted account ids.

---

## Same account, multiple regions

When prod spans two regions (e.g. `ca-central-1` *and* `us-east-1`) you create
**two `env_map` entries with the same `account_id` and the same
`state_bucket`**, but **different `state_bucket_key`** (typically the region
name). The S3 keys keep the two regions' state files apart while keeping the
account/billing boundary the same.

---

## Authentication: no static credentials

The pattern uses **AWS SSO profiles** end-to-end. `root.hcl` has a `run_cmd`
that opportunistically calls `aws sso login --sso-session <name>` if the test
profile's credentials have expired, so `terragrunt plan` "just works" after a
fresh boot without anyone having to remember the login command.

Aliased providers in the generated `provider.tf` let a workload read from the
foundation accounts (e.g. add a DNS record into the networking account's
hosted zone) without an explicit `assume_role` block.

---

## Operating the layout

From any leaf folder:

```sh
cd environments/workloads/orbit/dev/ca-central-1
terragrunt plan
terragrunt apply
```

From the repo root, across all accounts:

```sh
terragrunt run-all plan
terragrunt run-all apply
```

`run-all` respects the `dependency` graph - foundation accounts are applied
before workloads.

---

## Adding a new workload environment

1. Add an `env_map` entry (use the commented template at the bottom of
   `env_map` as your starting point).
2. Create the folder at `environments/workloads/<project>/<env>/<region>/`.
3. Copy the four files from `workloads/orbit/dev/ca-central-1/` and adjust
   inputs.
4. `terragrunt init && terragrunt plan` from inside the new folder.
