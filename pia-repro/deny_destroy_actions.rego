# No deletes in a plan.
# Against pia-terraform: PASSES (fresh state, everything is a create).
package terraform

import rego.v1

deny contains msg if {
	some rc in input.tfplan.resource_changes
	"delete" in rc.change.actions
	msg := sprintf("deny_destroy_actions: %s would be destroyed", [rc.address])
}
