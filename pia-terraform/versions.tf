# The repro workspaces run OpenTofu (`iac-platform = "opentofu"` in
# scripts/pia-te-setup.sh), not Terraform.
#
# The config itself is identical either way -- the `hashicorp/random` source shorthand is
# understood by both. What differs is where each platform resolves it:
#
#   OpenTofu   ->  registry.opentofu.org/hashicorp/random
#   Terraform  ->  registry.terraform.io/hashicorp/random
#
# That string lands in the plan JSON as `provider_name`, which is why
# ../pia-repro/require_provider_allowlist.rego allowlists both registries.
terraform {
  required_version = ">= 1.6"

  required_providers {
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
  }
}
