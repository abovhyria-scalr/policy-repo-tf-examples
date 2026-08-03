# Cap the size of a single changeset.
# Against pia-terraform: FAILS (6 resources > 4).
package terraform

import rego.v1

max_resources := 4

deny contains msg if {
	n := count(input.tfplan.resource_changes)
	n > max_resources
	msg := sprintf("max_resource_count: %d resource changes exceeds the limit of %d", [n, max_resources])
}
