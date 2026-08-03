# Depends on data.pia.helpers -> data.pia.naming.
# Against pia-terraform: MIXED by workspace name.
package terraform

import data.pia.helpers
import future.keywords

deny contains msg if {
	not helpers.workspace_name_ok
	msg := sprintf(
		"naming_convention: workspace %q must end with one of %v",
		[helpers.workspace_name, data.pia.naming.allowed_suffixes],
	)
}

deny contains msg if {
	not helpers.workspace_slug_ok
	msg := sprintf("naming_convention: workspace %q is not a valid slug", [helpers.workspace_name])
}
