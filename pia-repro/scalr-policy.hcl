# Policy group manifest for the SCALRCORE-38740 repro.
#
# 20 policies in ONE group. That is the point: today a one-line change to any single
# .rego file re-evaluates all 18 enabled ones against every run in scope.
#
# Everything is advisory so nothing blocks a run while you experiment. Flip individual
# policies to soft-mandatory / hard-mandatory only if you want to test enforcement.
#
# Manifest key MUST equal the .rego filename (see OpaPolicyGroup._read_policy_rego_code
# in taco/app/policy/service/policy_group.py:235) -- a mismatch errors the whole group.

version = "v1"

# --- cheap, self-contained (10) ---------------------------------------------------

policy "allowed_resource_types" {
  enabled           = true
  enforcement_level = "advisory"
}

policy "deny_null_resource" {
  enabled           = true
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

policy "require_random_pet" {
  enabled           = true
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

policy "require_run_message" {
  enabled           = true
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
