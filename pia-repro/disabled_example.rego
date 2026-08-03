# DISABLED by default. Proves that `enabled = false` in the manifest keeps a policy out
# of `OpaPolicyGroup.enabled_policies` and therefore out of every evaluation.
#
# SCALRCORE-38740: flipping this to `enabled = true` is a manifest-only change with no
# .rego diff. AC #4 says that must count as "this policy changed" -- which is why the
# content hash in §4.1 has to cover enabled + enforcement_level, not just rego_code.
package terraform

import future.keywords

deny contains msg if {
	count(input.tfplan.resource_changes) > 0
	msg := "disabled_example: this always fails when enabled"
}
