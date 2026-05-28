# Networking account: shared public DNS (Route 53 hosted zones). Workloads
# `dependency` on this account's outputs to get their hosted_zone_id.
include "root" {
  path   = find_in_parent_folders("root.hcl")
  expose = true
}

locals {
  full_env_key = path_relative_to_include()
  matching_env = [for k, v in include.root.locals.env_map : v if v.path == local.full_env_key]
  cfg          = length(local.matching_env) > 0 ? local.matching_env[0] : null
}

terraform {}

inputs = {
  region      = local.cfg.region
  environment = local.cfg.environment
  project     = local.cfg.project

  # Hosted zones this account owns; workloads look these up via dependency.
  hosted_zones = {
    orbit  = "orbitapp.example.com"
    portal = "portalapp.example.com"
  }
}
