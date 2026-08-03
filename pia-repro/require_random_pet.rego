# Sanity check that the plan is the one we expect.
# Against pia-terraform: PASSES.
package terraform

import rego.v1

deny contains msg if {
	pets := [rc | some rc in input.tfplan.resource_changes; rc.type == "random_pet"]
	count(pets) == 0
	msg := "require_random_pet: plan contains no random_pet resource"
}
