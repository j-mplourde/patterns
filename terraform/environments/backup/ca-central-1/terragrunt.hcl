# Backup account: centralized AWS Backup vault that receives cross-account copies
# of every workload's RDS / EBS snapshots. Isolating backups in a separate
# account means even an attacker with admin in a workload account cannot delete
# the backups - the classic ransomware/insider blast-radius mitigation.
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

# Backup policy is administered from the management account, so we wait for it.
dependency "management" {
  config_path = "../../management/ca-central-1"
  mock_outputs = {
    organization_id = "o-mockmanagement"
  }
}

locals {
  full_env_key = path_relative_to_include()
  matching_env = [for k, v in include.root.locals.env_map : v if v.path == local.full_env_key]
  cfg          = length(local.matching_env) > 0 ? local.matching_env[0] : null
}

terraform {}

inputs = {
  region          = local.cfg.region
  environment     = local.cfg.environment
  project         = local.cfg.project
  organization_id = dependency.management.outputs.organization_id
}
