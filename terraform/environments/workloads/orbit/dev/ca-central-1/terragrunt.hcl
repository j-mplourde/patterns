# Workload: orbit / dev / ca-central-1   (account 222222000001)
#
# Workload environments declare `dependency` blocks on the shared accounts they
# read from. Terragrunt uses these to (a) order `run-all` operations and (b)
# inject the upstream outputs as inputs. mock_outputs keep `plan` working before
# the dependencies have ever been applied.
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

dependency "networking" {
  config_path = "../../../../networking/ca-central-1"
  mock_outputs = {
    hosted_zones = {
      orbit = { zone_id = "Z0MOCKZONEID" }
    }
  }
}

dependency "operations_tool" {
  config_path = "../../../../operations_tool/ca-central-1"
  mock_outputs = {
    ecr_base_url = "111111000003.dkr.ecr.ca-central-1.amazonaws.com"
  }
}

dependency "backup" {
  config_path = "../../../../backup/ca-central-1"
  mock_outputs = {
    backup_vault_arn = "arn:aws:backup:ca-central-1:111111000004:backup-vault:mock"
  }
}

locals {
  full_env_key = path_relative_to_include()
  matching_env = [for k, v in include.root.locals.env_map : v if v.path == local.full_env_key]
  cfg          = length(local.matching_env) > 0 ? local.matching_env[0] : null
}

terraform {}

inputs = {
  region       = local.cfg.region
  environment  = local.cfg.environment
  project      = local.cfg.project
  domain_name  = "dev.orbitapp.example.com"
  admin_emails = ["devops@example.com"]

  # Pulled from the shared accounts via the dependency blocks above.
  hosted_zone_id   = dependency.networking.outputs.hosted_zones.orbit.zone_id
  ecr_base_url     = dependency.operations_tool.outputs.ecr_base_url
  backup_vault_arn = dependency.backup.outputs.backup_vault_arn
}
