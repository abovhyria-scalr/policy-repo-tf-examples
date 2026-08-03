# null_resource is a smell; deny it outright.
# Against pia-terraform: FAILS.
#
# SCALRCORE-38740: this is the file to edit for the "one-line change" demo.
# Append a comment line, commit, push -- see pia-repro/README.md step 5.
package terraform

import future.keywords

deny contains msg if {
	some rc in input.tfplan.resource_changes
	rc.type == "null_resource"
	msg := sprintf("deny_null_resource: %s uses null_resource", [rc.address])
}
