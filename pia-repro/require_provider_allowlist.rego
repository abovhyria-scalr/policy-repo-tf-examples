# Only approved providers.
# Against pia-terraform: PASSES.
#
# Both registries are listed on purpose. OpenTofu resolves the `hashicorp/random` source
# shorthand against registry.opentofu.org, Terraform against registry.terraform.io, so the
# `provider_name` in the plan JSON differs by platform even though the config is identical:
#
#   OpenTofu   ->  registry.opentofu.org/hashicorp/random
#   Terraform  ->  registry.terraform.io/hashicorp/random
#
# A real allowlist policy has to cover both or it denies every run in a mixed fleet. The
# repro workspaces are OpenTofu (`iac-platform = "opentofu"`), so only the opentofu.org
# entries are exercised here; the others keep the fixture working if you flip a workspace
# back to Terraform.
package terraform

import future.keywords

allowed := {
	"registry.opentofu.org/hashicorp/random",
	"registry.opentofu.org/hashicorp/null",
	"registry.terraform.io/hashicorp/random",
	"registry.terraform.io/hashicorp/null",
}

deny contains msg if {
	some rc in input.tfplan.resource_changes
	not rc.provider_name in allowed
	msg := sprintf("require_provider_allowlist: %s uses provider %q", [rc.address, rc.provider_name])
}
