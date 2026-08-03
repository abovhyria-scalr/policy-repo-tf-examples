# Config for the SCALRCORE-38740 PIA repro workspaces. Runs on OpenTofu.
#
# No cloud credentials, no real infrastructure, no cost. It exists only to produce a
# plan.json with a predictable set of resource_changes so the policies in ../pia-repro
# give stable, mixed results.
#
# Why it must produce changes: _get_runs_for_group_check only picks up
# Workspace.latest_planned_run, and that is set only when
#   not run.plan_only and run.has_changes and run.plan.is_succeeded
# (taco/app/run/service/remote/pipeline.py:743), on on_run_stop. A workspace whose plan
# is a no-op is invisible to PIA. Never applied, so every plan is 6 creates forever.
#
# Resulting plan shape: 2 random_pet, 1 random_id, 1 random_string, 2 null_resource = 6.

resource "random_pet" "app" {
  length    = 2
  separator = "-"
}

resource "random_pet" "db" {
  length    = 2
  separator = "-"
}

resource "random_id" "suffix" {
  byte_length = 8
}

resource "random_string" "token" {
  length  = 16
  special = false
}

# Trips allowed_resource_types, deny_null_resource and resource_budget on purpose.
resource "null_resource" "deploy" {
  triggers = {
    pet = random_pet.app.id
  }
}

resource "null_resource" "migrate" {
  triggers = {
    id = random_id.suffix.hex
  }
}

output "app_name" {
  value = random_pet.app.id
}
