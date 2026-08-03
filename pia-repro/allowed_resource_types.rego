# Deny resource types outside an allowlist.
# Against pia-terraform: FAILS (2x null_resource).
package terraform

import future.keywords

allowed := {"random_pet", "random_id", "random_string"}

deny contains msg if {
	some rc in input.tfplan.resource_changes
	not rc.type in allowed
	msg := sprintf("allowed_resource_types: %s has type %q which is not in the allowlist", [rc.address, rc.type])
}
