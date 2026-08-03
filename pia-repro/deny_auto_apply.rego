# Workspaces must not auto-apply.
# Against pia-terraform: PASSES if you leave auto-apply off (the default).
package terraform

import rego.v1

deny contains msg if {
	input.tfrun.workspace.auto_apply
	msg := sprintf("deny_auto_apply: workspace %q has auto-apply enabled", [input.tfrun.workspace.name])
}
