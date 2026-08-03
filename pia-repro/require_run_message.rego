# Runs must carry a non-trivial message.
# Against pia-terraform: MIXED, depends on how the run was queued.
package terraform

import future.keywords

deny contains msg if {
	m := object.get(input, ["tfrun", "message"], "")
	count(m) < 8
	msg := sprintf("require_run_message: run message %q is too short", [m])
}
