# Operations-tooling account: ECR repositories, image builders, the CI OIDC
# provider, and shared KMS keys. Workloads pull image URIs / OIDC role ARNs from
# here. Keeping CI infrastructure in its own account means a leaked CI token
# can't reach production data planes directly.
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

  ci_workspace = include.root.locals.ci_workspace
  ci_audience  = include.root.locals.ci_audience
}
