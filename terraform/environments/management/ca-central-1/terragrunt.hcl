# Management account: Control Tower landing zone, AWS Identity Center (SSO).
# This is the org "root of trust"; nothing else depends on it being deployed
# first except SSO itself, so it has no dependency blocks.
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

locals {
  full_env_key = path_relative_to_include()
  matching_env = [for k, v in include.root.locals.env_map : v if v.path == local.full_env_key]
  cfg          = length(local.matching_env) > 0 ? local.matching_env[0] : null
}

terraform {
  # No `source`: Terraform runs against the *.tf files IN THIS FOLDER.
}

inputs = {
  region      = local.cfg.region
  environment = local.cfg.environment
  project     = local.cfg.project

  # Account IDs of the other foundation accounts, passed in so management-level
  # guardrails (SCPs, delegated admin, etc.) can reference them by id.
  security_account_id = "111111000005"
  logging_account_id  = "111111000006"
}
