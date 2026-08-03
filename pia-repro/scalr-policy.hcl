# Policy group manifest for the SCALRCORE-38740 repro.
#
# 20 policies in ONE group, 14 of them enabled. That is the point: today a one-line change
# to any single .rego file re-evaluates all 14 against every run in scope.
#
# Six are enabled = false. Two are deliberate caveat demos (see the bottom of this file);
# four were switched off because they produced noise without adding signal -- each carries
# a comment saying why. Disabled rather than deleted so they are one edit away from
# returning, and because toggling `enabled` is itself a manifest-only change, which is the
# AC #4 case: no .rego diff, but the policy set changed.
#
# Everything is advisory so nothing blocks a run while you experiment. Flip individual
# policies to soft-mandatory / hard-mandatory only if you want to test enforcement.
#
# Manifest key MUST equal the .rego filename (see OpaPolicyGroup._read_policy_rego_code
# in taco/app/policy/service/policy_group.py:235) -- a mismatch errors the whole group.

version = "v1"

# --- cheap, self-contained (10) ---------------------------------------------------

# OFF: duplicates deny_null_resource on this fixture -- both fire on the same two resources.
#    Flip enabled back to true to restore it.
policy "allowed_resource_types" {
  enabled           = false
  enforcement_level = "advisory"
}

# OFF: noisy. max_resource_count and resource_budget still provide always-red rows.
#    Flip enabled back to true to restore it.
policy "deny_null_resource" {
  enabled           = false
  enforcement_level = "advisory"
}

policy "max_resource_count" {
  enabled           = true
  enforcement_level = "advisory"
}

policy "workspace_name_suffix" {
  enabled           = true
  enforcement_level = "advisory"
}

# OFF: only meaningful against pia-terraform. Fires on any other config, which is noise.
#    Flip enabled back to true to restore it.
policy "require_random_pet" {
  enabled           = false
  enforcement_level = "advisory"
}

policy "deny_destroy_actions" {
  enabled           = true
  enforcement_level = "advisory"
}

policy "require_provider_allowlist" {
  enabled           = true
  enforcement_level = "advisory"
}

policy "deny_destroy_run" {
  enabled           = true
  enforcement_level = "advisory"
}

# OFF: fires on every run queued from the UI, since those have an empty message.
#    Flip enabled back to true to restore it.
policy "require_run_message" {
  enabled           = false
  enforcement_level = "advisory"
}

policy "deny_auto_apply" {
  enabled           = true
  enforcement_level = "advisory"
}

# --- depend on pia-common (3) -- the AC #3 set ------------------------------------
# These three import data.pia.helpers, which imports data.pia.naming.
# A change to pia-common/naming.rego must mark exactly these three as changed.

policy "tags_required" {
  enabled           = true
  enforcement_level = "advisory"
}

policy "naming_convention" {
  enabled           = true
  enforcement_level = "advisory"
}

policy "resource_budget" {
  enabled           = true
  enforcement_level = "advisory"
}

# --- deliberately slow (5) -------------------------------------------------------
# ~1-2s of OPA evaluation each. These make the O(runs x policies) cost visible on a
# TE with a handful of workspaces instead of State Farm's hundreds.

policy "slow_scan_1" {
  enabled           = true
  enforcement_level = "advisory"
}

policy "slow_scan_2" {
  enabled           = true
  enforcement_level = "advisory"
}

policy "slow_scan_3" {
  enabled           = true
  enforcement_level = "advisory"
}

policy "slow_scan_4" {
  enabled           = true
  enforcement_level = "advisory"
}

policy "slow_scan_5" {
  enabled           = true
  enforcement_level = "advisory"
}

# --- caveat demos, off by default (2) --------------------------------------------

policy "nondeterministic_http" {
  enabled           = false
  enforcement_level = "advisory"
}

policy "disabled_example" {
  enabled           = false
  enforcement_level = "advisory"
}
