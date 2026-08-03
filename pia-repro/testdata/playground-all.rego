# =====================================================================================
# PASTE THIS WHOLE FILE into the Rego Playground editor (play.openpolicyagent.org),
# then paste testdata/input-pia-05.json into the INPUT panel and click Evaluate.
#
# THIS IS A TEST HARNESS, NOT SHIPPED CODE.
#
# The real repro is 20 .rego files in ../, of which 14 are enabled in scalr-policy.hcl --
# Scalr uploads and evaluates each on its own (policy_check.check, policy_check.py:115).
# The Playground has a single editor and a single package, so this file flattens the 9
# enabled non-slow policies into one module so you see every result in one click.
#
# Two things had to change to make the flattening work, and neither affects the logic:
#
#   1. Helper rules from ../../pia-common/*.rego are inlined here with `h_` and `n_`
#      prefixes. In the real fixture they live in a separate folder and the three
#      policies that use them reach them via `import data.pia.helpers`. The Playground
#      cannot load a second module, so the import is gone here. That import wiring is
#      what `scripts/pia-validate.sh` and the TE test, not the Playground.
#
#   2. Constants were renamed where two policies shared a name. In separate files that is
#      fine; in one file it collides.
#
# The five slow_scan policies are NOT here -- see playground-slow.rego.
# The six disabled policies are NOT here -- they are `enabled = false` in the manifest.
#
# HOW TO READ THE OUTPUT
# Every message starts with the name of the policy that produced it, so the `deny` array
# in the OUTPUT panel tells you exactly which of the 9 fired.
#
# Careful: messages != policies. In real Scalr each policy is a separate file with its own
# pass/fail row, so the UI shows the policy count; here you see the message count. With
# these 9 the two happen to be equal -- each fires at most once.
#
#   input-pia-05.json     -> 5 messages
#     max_resource_count       (6 > 4)
#     workspace_name_suffix    ("pia-05" has no env suffix)
#     tags_required            (no owner / cost-center tag)
#     naming_convention        (suffix rule; the slug rule passes)
#     resource_budget          (2 null_resource, budget 1)
#
#   input-pia-01-dev.json -> 2 messages
#     max_resource_count, resource_budget
#     -- the three name/tag policies now pass, which is the difference between the two
#        fixtures and the reason both exist.
#
# If your counts match, the fixture logic is correct.
#
# EXPECTED LINT: 2 x style/messy-rule. Regal wants every `deny` definition adjacent; here
# they are separated by constants belonging to their original files. Style only, and an
# artifact of the flattening -- in the real fixture each `deny` is alone in its own file.
# Anything else in the LINT panel is worth a look.
# =====================================================================================

package terraform

import future.keywords

# --- inlined from pia-common/naming.rego (prefix n_) ---------------------------------

n_allowed_suffixes := ["-dev", "-stg", "-prod"]

n_slug_pattern := "^[a-z0-9][a-z0-9-]{1,62}$"

n_has_valid_suffix(name) if {
	some suffix in n_allowed_suffixes
	endswith(name, suffix)
}

n_is_slug(name) if regex.match(n_slug_pattern, name)

# --- inlined from pia-common/helpers.rego (prefix h_) --------------------------------

h_workspace_name := object.get(input, ["tfrun", "workspace", "name"], "")

h_workspace_tags := object.get(input, ["tfrun", "workspace", "tags"], [])

h_created_resources := [rc |
	some rc in object.get(input, ["tfplan", "resource_changes"], [])
	"create" in rc.change.actions
]

h_count_of_type(t) := count([rc | some rc in h_created_resources; rc.type == t])

h_required_tags := ["owner", "cost-center"]

h_missing_tags := [t |
	some t in h_required_tags
	not t in h_workspace_tags
]

# --- 1. max_resource_count.rego -----------------------------------------------------

max_resources := 4

deny contains msg if {
	n := count(input.tfplan.resource_changes)
	n > max_resources
	msg := sprintf("max_resource_count: %d resource changes exceeds the limit of %d", [n, max_resources])
}

# --- 2. workspace_name_suffix.rego --------------------------------------------------

deny contains msg if {
	name := input.tfrun.workspace.name
	not endswith(name, "-dev")
	not endswith(name, "-stg")
	not endswith(name, "-prod")
	msg := sprintf("workspace_name_suffix: workspace %q must end with -dev, -stg or -prod", [name])
}

# --- 3. deny_destroy_actions.rego ---------------------------------------------------

deny contains msg if {
	some rc in input.tfplan.resource_changes
	"delete" in rc.change.actions
	msg := sprintf("deny_destroy_actions: %s would be destroyed", [rc.address])
}

# --- 4. require_provider_allowlist.rego ---------------------------------------------

# Both registries: OpenTofu resolves `hashicorp/random` against registry.opentofu.org,
# Terraform against registry.terraform.io. The repro workspaces are OpenTofu.
allowed_providers := {
	"registry.opentofu.org/hashicorp/random",
	"registry.opentofu.org/hashicorp/null",
	"registry.terraform.io/hashicorp/random",
	"registry.terraform.io/hashicorp/null",
}

deny contains msg if {
	some rc in input.tfplan.resource_changes
	not rc.provider_name in allowed_providers
	msg := sprintf("require_provider_allowlist: %s uses provider %q", [rc.address, rc.provider_name])
}

# --- 5. deny_destroy_run.rego -------------------------------------------------------

deny contains msg if {
	input.tfrun.is_destroy
	msg := "deny_destroy_run: destroy runs are not permitted"
}

# --- 6. deny_auto_apply.rego -------------------------------------------------------

deny contains msg if {
	input.tfrun.workspace.auto_apply
	msg := sprintf("deny_auto_apply: workspace %q has auto-apply enabled", [input.tfrun.workspace.name])
}

# --- 7. tags_required.rego (uses the inlined helpers) ------------------------------

deny contains msg if {
	count(h_missing_tags) > 0
	msg := sprintf("tags_required: workspace %q is missing tags %v", [h_workspace_name, h_missing_tags])
}

# --- 8. naming_convention.rego (uses the inlined helpers) -------------------------

deny contains msg if {
	not n_has_valid_suffix(h_workspace_name)
	msg := sprintf("naming_convention: workspace %q must end with one of %v", [h_workspace_name, n_allowed_suffixes])
}

deny contains msg if {
	not n_is_slug(h_workspace_name)
	msg := sprintf("naming_convention: workspace %q is not a valid slug", [h_workspace_name])
}

# --- 9. resource_budget.rego (uses the inlined helpers) ---------------------------

resource_budget_limits := {
	"random_pet": 5,
	"random_id": 5,
	"random_string": 5,
	"null_resource": 1,
}

deny contains msg if {
	some t, limit in resource_budget_limits
	actual := h_count_of_type(t)
	actual > limit
	msg := sprintf("resource_budget: %d x %s exceeds the budget of %d", [actual, t, limit])
}
