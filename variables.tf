# ========== LOCALS ============================================================

# Define defaults, then merge per-environment variables as described in https://github.com/hashicorp/terraform/issues/15966
locals {
  default_file               = "./group_vars/all/main.yml"
  default_content            = fileexists(local.default_file) ? file(local.default_file) : "NoSettingsFileFound: true"
  default_vars               = yamldecode(local.default_content)
  env_file                   = "./group_vars/${terraform.workspace}/main.yml"
  env_content                = fileexists(local.env_file) ? file(local.env_file) : "NoSettingsFileFound: true"
  env_vars                   = yamldecode(local.env_content)
  vars                       = merge(local.default_vars, local.env_vars,
                                     { private_zone: "${terraform.workspace}.local" } )
}
