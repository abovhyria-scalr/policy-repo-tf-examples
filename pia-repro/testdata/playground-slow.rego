# =====================================================================================
# PASTE THIS into the Rego Playground. The INPUT panel is ignored by this policy, so you
# can leave input-pia-05.json in place. Click Evaluate and read the grey timing line above
# the OUTPUT panel:
#
#   "Found 1 result in 36.348µs."      <-- that number is the whole point
#
# EXPECTED OUTPUT (small on purpose):
#   {
#     "deny": [],
#     "hits": 44545,
#     "work": 700
#   }
#
# `deny: []` means the policy passed -- correct, it is designed never to fire. `hits` is
# the proof that the expensive loop actually ran. If you see those two, it worked.
#
# WHAT THIS POLICY IS FOR
# It always passes. Its only job is to burn evaluation time, so that a test environment
# with ten workspaces can demonstrate a cost problem that only appears at a customer's
# scale of hundreds. Five copies of it live in the real fixture as slow_scan_1..5.
#
# THE MEASUREMENT — do this as a scaling test, not a single reading
# Change `work` below and re-Evaluate each time. The loop is quadratic, so every doubling
# of `work` should roughly quadruple the time:
#
#     work = 100     10,000 iterations   hits =    909    note the time
#     work = 200     40,000 iterations   hits =  3,636    ~4x the previous
#     work = 400    160,000 iterations   hits = 14,544    ~4x again
#     work = 700    490,000 iterations   hits = 44,545    the fixture default
#
# Start at 100 and walk up. The Playground is a shared service with an evaluation cap, so
# if a large value returns nothing at all, you have found the ceiling -- drop back down.
# That cap does not affect the real fixture; Scalr runs OPA in its own container.
#
# WHY THIS MATTERS FOR SCALRCORE-38740
# Scalr checks every enabled policy against every workspace run. The fixture has 14
# enabled policies and the setup script makes 10 workspaces:
#
#     14 policies x 10 runs = 140 evaluations
#
# Change one comment in one policy file and Scalr still performs all 140. The ticket asks
# for 10 instead (one changed policy x ten runs).
#
# Take your time at work = 700 and multiply by 50 -- five slow policies x ten workspaces.
# That is roughly the wall clock your test environment will burn for a one-line change.
# =====================================================================================

package terraform

import future.keywords

# Tunable. See the scaling table above.
work := 700

# Quadratic on purpose: every i is tested against every j.
#
# Note the shape -- count() wraps the comprehension directly, so only the final number is
# ever stored. An earlier version of this file built a named set of every matching [i, j]
# pair instead, which meant ~44,000 stored arrays: too big for the Playground to render,
# and a memory risk on the test environment when multiplied by 5 policies x 10 runs. This
# repo already has an oom_heavy/ folder from a previous incident of exactly that kind.
hits := count([1 |
	some i in numbers.range(1, work)
	some j in numbers.range(1, work)
	(i + j) % 11 == 0
])

# The threshold is unreachable, so this never denies -- but evaluating `hits` forces the
# whole loop above to run first. That is the cost being demonstrated.
deny contains msg if {
	hits > 100000000
	msg := sprintf("slow_scan: unreachable (%d hits)", [hits])
}
