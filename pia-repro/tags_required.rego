# Depends on data.pia.helpers -> data.pia.naming.
# Against pia-terraform: MIXED, driven by the workspace tags you set.
#
# SCALRCORE-38740 AC #3: editing pia-common/helpers.rego or pia-common/naming.rego
# must mark this policy as changed even though this file is untouched.
package terraform

import data.pia.helpers
import future.keywords

deny contains msg if {
	count(helpers.missing_tags) > 0
	msg := sprintf(
		"tags_required: workspace %q is missing tags %v",
		[helpers.workspace_name, helpers.missing_tags],
	)
}
