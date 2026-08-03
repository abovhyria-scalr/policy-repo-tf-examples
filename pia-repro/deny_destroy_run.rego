# Block PIA-visible destroy runs.
# Against pia-terraform: PASSES. _get_runs_for_group_check already filters
# is_destroy runs out of PIA scope, so this can never fail there -- it exists to
# show a policy that is dead weight in PIA but meaningful in an in-run check.
package terraform

import rego.v1

deny contains msg if {
	input.tfrun.is_destroy
	msg := "deny_destroy_run: destroy runs are not permitted"
}
