# Depends on data.pia.helpers -> data.pia.naming.
# Against pia-terraform: FAILS (2 null_resource, budget 1).
package terraform

import data.pia.helpers
import future.keywords

budget := {
	"random_pet": 5,
	"random_id": 5,
	"random_string": 5,
	"null_resource": 1,
}

deny contains msg if {
	some t, limit in budget
	actual := helpers.count_of_type(t)
	actual > limit
	msg := sprintf("resource_budget: %d x %s exceeds the budget of %d", [actual, t, limit])
}
