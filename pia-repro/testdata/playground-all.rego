# =====================================================================================
# PASTE THIS WHOLE FILE into the Rego Playground editor (play.openpolicyagent.org),
# then paste testdata/input-pia-05.json into the INPUT panel and click Evaluate.
#
# THIS IS A TEST HARNESS, NOT SHIPPED CODE.
#
# The real repro is 20 separate .rego files in ../  -- Scalr uploads and evaluates each
# one on its own (see policy_check.check in taco/app/policy/service/policy_check.py:115).
# The Playground has a single editor and a single package, so this file flattens 13 of
# those policies into one module so you can see every result in one click.
#
# Two things had to change to make the flattening work, and neither affects the logic:
#
#   1. Helper rules from ../../pia-common/*.rego are inlined here with `h_` and `n_`
#      prefixes. In the real fixture they live in a separate folder and the three
#      policies that use them reach them via `import data.pia.helpers`. The Playground
#      cannot load a second module, so the import is gone here. That import wiring is
#      what `scripts/pia-validate.sh` and the TE test, not the Playground.
#
#   2. Constants were renamed where two policies used the same name (`allowed` appeared
#      in both allowed_resource_types.rego and require_provider_allowlist.rego). In
#      separate files that is fine; in one file it collides.
#
# The five slow_scan policies are NOT here -- see playground-slow.rego.
# The two disabled policies are NOT here -- they are `enabled = false` in the manifest.
#
# HOW TO READ THE OUTPUT
# Every message starts with the name of the policy that produced it, so the `deny` array
# in the OUTPUT panel tells you exactly which of the 13 fired.
#
# Careful: messages != policies. One policy can produce several messages (one per bad
# resource). In real Scalr each policy is a separate file with its own pass/fail row, so
# the UI shows the policy count; here you see the message count.
#
#   input-pia-05.json     -> 10 messages from 8 policies
#     allowed_resource_types  x2   (null_resource.deploy, null_resource.migrate)
#     deny_null_resource      x2   (same two)
#     max_resource_count      x1   (6 > 4)
#     workspace_name_suffix   x1   ("pia-05" has no env suffix)
#     require_run_message     x1   ("wip" is under 8 chars)
#     tags_required           x1   (no owner / cost-center tag)
#     naming_convention       x1   (suffix rule; the slug rule passes)
#     resource_budget         x1   (2 null_resource, budget 1)
#
#   input-pia-01-dev.json -> 6 messages from 4 policies
#     allowed_resource_types x2, deny_null_resource x2, max_resource_count x1,
#     resource_budget x1
#     -- the four name/tag/message policies now pass, which is the difference between
#        the two fixtures and the reason both exist.
#
# If your counts match, the fixture logic is correct.
#
# EXPECTED LINT: 3 x style/messy-rule. Regal wants every `deny` definition adjacent; here
# each is separated by a constant belonging to its original file. Style only, and an
# artifact of the flattening -- in the real fixture each `deny` is alone in its own file.
# Anything else in the LINT panel is worth a look.
# =====================================================================================

package terraform

import rego.v1

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

# --- 1. allowed_resource_types.rego -------------------------------------------------

allowed_types := {"random_pet", "random_id", "random_string"}

deny contains msg if {
	some rc in input.tfplan.resource_changes
	not rc.type in allowed_types
	msg := sprintf("allowed_resource_types: %s has type %q which is not in the allowlist", [rc.address, rc.type])
}

# --- 2. deny_null_resource.rego -----------------------------------------------------

deny contains msg if {
	some rc in input.tfplan.resource_changes
	rc.type == "null_resource"
	msg := sprintf("deny_null_resource: %s uses null_resource", [rc.address])
}

# --- 3. max_resource_count.rego -----------------------------------------------------

max_resources := 4

deny contains msg if {
	n := count(input.tfplan.resource_changes)
	n > max_resources
	msg := sprintf("max_resource_count: %d resource changes exceeds the limit of %d", [n, max_resources])
}

# --- 4. workspace_name_suffix.rego --------------------------------------------------

deny contains msg if {
	name := input.tfrun.workspace.name
	not endswith(name, "-dev")
	not endswith(name, "-stg")
	not endswith(name, "-prod")
	msg := sprintf("workspace_name_suffix: workspace %q must end with -dev, -stg or -prod", [name])
}

# --- 5. require_random_pet.rego -----------------------------------------------------

deny contains msg if {
	pets := [rc | some rc in input.tfplan.resource_changes; rc.type == "random_pet"]
	count(pets) == 0
	msg := "require_random_pet: plan contains no random_pet resource"
}

# --- 6. deny_destroy_actions.rego ---------------------------------------------------

deny contains msg if {
	some rc in input.tfplan.resource_changes
	"delete" in rc.change.actions
	msg := sprintf("deny_destroy_actions: %s would be destroyed", [rc.address])
}

# --- 7. require_provider_allowlist.rego ---------------------------------------------

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

# --- 8. deny_destroy_run.rego -------------------------------------------------------

deny contains msg if {
	input.tfrun.is_destroy
	msg := "deny_destroy_run: destroy runs are not permitted"
}

# --- 9. require_run_message.rego ----------------------------------------------------

deny contains msg if {
	m := object.get(input, ["tfrun", "message"], "")
	count(m) < 8
	msg := sprintf("require_run_message: run message %q is too short", [m])
}

# --- 10. deny_auto_apply.rego -------------------------------------------------------

deny contains msg if {
	input.tfrun.workspace.auto_apply
	msg := sprintf("deny_auto_apply: workspace %q has auto-apply enabled", [input.tfrun.workspace.name])
}

# --- 11. tags_required.rego (uses the inlined helpers) ------------------------------

deny contains msg if {
	count(h_missing_tags) > 0
	msg := sprintf("tags_required: workspace %q is missing tags %v", [h_workspace_name, h_missing_tags])
}

# --- 12. naming_convention.rego (uses the inlined helpers) -------------------------

deny contains msg if {
	not n_has_valid_suffix(h_workspace_name)
	msg := sprintf("naming_convention: workspace %q must end with one of %v", [h_workspace_name, n_allowed_suffixes])
}

deny contains msg if {
	not n_is_slug(h_workspace_name)
	msg := sprintf("naming_convention: workspace %q is not a valid slug", [h_workspace_name])
}

# --- 13. resource_budget.rego (uses the inlined helpers) ---------------------------

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
