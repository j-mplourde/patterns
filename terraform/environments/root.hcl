# =============================================================================
# root.hcl - Master Terragrunt configuration (single source of truth)
# =============================================================================
#
# This file is `include`d by every per-environment terragrunt.hcl. It does
# three jobs:
#
#   1. Holds `env_map`: the central account/region/state map. Each entry maps a
#      folder path under environments/ to ONE AWS account.
#   2. Configures the S3 remote state backend (one bucket per account).
#   3. Generates provider.tf / backend.tf / versions.tf into each leaf folder so
#      individual environments never duplicate provider boilerplate.
#
# The "which folder am I?" lookup is done with path_relative_to_include(), which
# returns the path of the CHILD terragrunt.hcl relative to this file. We match
# that against env_map[*].path to find the active account's config.
#
# NOTE: All account IDs, domains, and emails below are FICTIONAL placeholders.
# =============================================================================

locals {
  # ---------------------------------------------------------------------------
  # AWS SSO. No long-lived credentials anywhere. Every account is reached via an
  # SSO profile in ~/.aws/config. This run_cmd transparently triggers `aws sso
  # login` if the session has expired, so `terragrunt plan` never fails on creds.
  # ---------------------------------------------------------------------------
  aws_sso_session                = "acme"
  aws_sso_test_connected_profile = "terraform-acme-management"
  init = run_cmd("bash", "-c", "aws sts get-caller-identity --profile ${local.aws_sso_test_connected_profile} > /dev/null 2>&1 || aws sso login --sso-session ${local.aws_sso_session}")

  default_project = "acme"

  # ---------------------------------------------------------------------------
  # CI federation (example: OIDC from a CI provider into the ops-tooling account).
  # ---------------------------------------------------------------------------
  ci_workspace = "acme-engineering"
  ci_audience  = "sts.amazonaws.com"

  # ===========================================================================
  # env_map: the heart of the pattern.
  #
  # Two tiers of accounts:
  #
  #   SHARED / FOUNDATION accounts (one each, no environment dimension):
  #     - management      : Control Tower landing zone, Identity Center / SSO
  #     - networking       : shared Route 53 hosted zones, public DNS
  #     - operations_tool  : ECR, image builders, CI OIDC provider, shared KMS
  #     - backup           : centralized AWS Backup vault (cross-account copies)
  #
  #   WORKLOAD accounts (one per project PER environment -> blast radius):
  #     - orbit_dev_ca_central_1 : the "orbit" product, dev environment
  #     - ...repeat one entry per (product x environment x region) as you grow.
  #
  # Why one account per env? A mistake (or a compromise) in `orbit-dev` cannot
  # touch `orbit-prod` data, IAM, or networking. This is AWS's recommended
  # multi-account strategy for reducing blast radius. Only ONE workload entry is
  # shown below; a commented template follows it so you can copy as needed.
  # ===========================================================================
  env_map = {

    # ----- Foundation / shared-services accounts ----------------------------
    management = {
      account_id          = "111111000001"
      path                = "management/ca-central-1"
      region              = "ca-central-1"
      profile             = "terraform-acme-management"
      state_bucket        = "acme-management-tfstate"
      state_bucket_key    = "ca-central-1"
      state_bucket_region = "ca-central-1"
      project             = local.default_project
      environment         = "management"
    }
    networking = {
      account_id          = "111111000002"
      path                = "networking/ca-central-1"
      region              = "ca-central-1"
      profile             = "terraform-acme-networking"
      state_bucket        = "acme-networking-tfstate"
      state_bucket_key    = "ca-central-1"
      state_bucket_region = "ca-central-1"
      project             = local.default_project
      environment         = "networking"
    }
    operations_tool = {
      account_id          = "111111000003"
      path                = "operations_tool/ca-central-1"
      region              = "ca-central-1"
      profile             = "terraform-acme-operations-tooling"
      state_bucket        = "acme-operations-tooling-tfstate"
      state_bucket_key    = "ca-central-1"
      state_bucket_region = "ca-central-1"
      project             = local.default_project
      environment         = "operations-tooling"
    }
    backup = {
      account_id          = "111111000004"
      path                = "backup/ca-central-1"
      region              = "ca-central-1"
      profile             = "terraform-acme-backup"
      state_bucket        = "acme-backup-tfstate"
      state_bucket_key    = "ca-central-1"
      state_bucket_region = "ca-central-1"
      project             = local.default_project
      environment         = "backup"
    }

    # ----- Workload account: "orbit" product, one environment ---------------
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

    # ----- Template: copy this block to add an environment ------------------
    # Each new entry = a NEW AWS account (own account_id, profile, state bucket)
    # and a matching folder at `path`. That 1:1:1 mapping (account : folder :
    # state bucket) is what keeps blast radius contained. A few worked examples:
    #
    #   orbit_qa_ca_central_1 = {
    #     account_id = "222222000002"   # different account from dev
    #     path       = "workloads/orbit/qa/ca-central-1"
    #     profile    = "terraform-acme-orbit-qa"
    #     state_bucket     = "orbit-qa-tfstate"
    #     state_bucket_key = "ca-central-1"
    #     ... region/region/project/environment ...
    #   }
    #
    #   # Same prod account, two regions: SAME account_id + state_bucket, but a
    #   # different state_bucket_key keeps the two regions' state files apart.
    #   orbit_prod_ca_central_1 = { account_id = "222222000004", state_bucket_key = "ca-central-1", ... }
    #   orbit_prod_us_east_1    = { account_id = "222222000004", state_bucket_key = "us-east-1",   ... }
  }

  # ---------------------------------------------------------------------------
  # Resolve the active environment by matching this child's folder path against
  # env_map[*].path. `cfg` is then used to template the backend + providers.
  # ---------------------------------------------------------------------------
  full_env_key = path_relative_to_include()
  matching_env = [for k, v in local.env_map : v if v.path == local.full_env_key]
  cfg          = length(local.matching_env) > 0 ? local.matching_env[0] : null
}

# =============================================================================
# Remote state: one S3 bucket PER ACCOUNT. Because the bucket lives inside each
# workload's own account, state isolation matches account isolation - a blast
# radius win. `use_lockfile` uses S3-native locking (no shared DynamoDB table).
# =============================================================================
remote_state {
  backend = "s3"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite"
  }
  config = {
    bucket       = local.cfg.state_bucket
    key          = "${local.cfg.state_bucket_key}/terraform.tfstate"
    region       = local.cfg.state_bucket_region
    profile      = local.cfg.profile
    encrypt      = true
    use_lockfile = true
  }
}

# =============================================================================
# Generated provider config. Each environment gets a primary provider pinned to
# its own account's SSO profile, plus read-only aliased providers into the
# shared accounts (networking / ops-tooling / backup) so a workload can, e.g.,
# add a Route 53 record in the networking account or pull an ECR repo ARN.
# =============================================================================
generate "versions" {
  path      = "versions.tf"
  if_exists = "overwrite"
  contents  = <<EOF
terraform {
  required_version = ">= 1.10.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.70.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.6.0"
    }
  }
}
EOF
}

generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite"
  contents  = <<EOF
provider "aws" {
  region  = "${local.cfg.region}"
  profile = "${local.cfg.profile}"
  default_tags {
    tags = {
      Environment = "${local.cfg.environment}"
      Project     = "${local.cfg.project}"
      Region      = "${local.cfg.region}"
      ManagedBy   = "terraform"
    }
  }
}

# Aliased provider into the shared NETWORKING account (e.g. public DNS records).
provider "aws" {
  alias   = "networking_account"
  region  = "${local.env_map["networking"].region}"
  profile = "${local.env_map["networking"].profile}"
}

# Aliased provider into the shared OPERATIONS-TOOLING account (e.g. ECR, KMS).
provider "aws" {
  alias   = "operations_tooling_account"
  region  = "${local.env_map["operations_tool"].region}"
  profile = "${local.env_map["operations_tool"].profile}"
}

# Aliased provider into the shared BACKUP account (cross-account backup copies).
provider "aws" {
  alias   = "backup_account"
  region  = "${local.env_map["backup"].region}"
  profile = "${local.env_map["backup"].profile}"
}
EOF
}
