# Workspace names must carry an environment suffix.
# Against pia-terraform: MIXED -- pia-01-dev passes, pia-05 fails.
# This is the policy that makes the matrix interesting across workspaces.
package terraform

import rego.v1

deny contains msg if {
	name := input.tfrun.workspace.name
	not endswith(name, "-dev")
	not endswith(name, "-stg")
	not endswith(name, "-prod")
	msg := sprintf("workspace_name_suffix: workspace %q must end with -dev, -stg or -prod", [name])
}
