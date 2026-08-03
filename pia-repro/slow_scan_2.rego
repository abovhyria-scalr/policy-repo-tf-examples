# Deliberately expensive, always passes.
#
# SCALRCORE-38740: a TE has a handful of workspaces, not the hundreds State Farm has.
# These five policies substitute compute for scale so the O(runs x policies) shape is
# visible in wall clock. Each burns roughly 1-2s of OPA evaluation per input.
#
# Tuning: work=700 is ~490k iterations. The loop is quadratic, so halving work cuts the
# cost 4x. Lower it if the 6h task limit becomes a problem; raise it to exaggerate.
#
# Note the shape: count() wraps the comprehension directly so only the final number is
# retained. Do not refactor this into a named set of matching pairs -- that stores ~44k
# arrays per policy per input, and at 5 policies x N runs it is an OOM risk. See the
# oom_heavy/ folder in this repo for what that looks like in practice.
package terraform

import future.keywords

work := 700

offset := 2

hits := count([1 |
	some i in numbers.range(1, work)
	some j in numbers.range(1, work)
	(i + j + offset) % 11 == 0
])

deny contains msg if {
	hits > 100000000
	msg := sprintf("slow_scan_2: unreachable, this rule exists to consume evaluation time (%d hits)", [hits])
}
