# pia-terraform

Throwaway config for the workspaces used by the SCALRCORE-38740 repro. Creates nothing
real -- `random_*` and `null_resource` only. Runs on **OpenTofu**.

Do not apply these workspaces. Leaving them unapplied keeps every plan at 6 creates,
which keeps the policy results in `../pia-repro` stable across commits. That stability is
what lets you tell a freshly evaluated result from a carried-forward one.

Two things the setup script sets that matter:

* `iac-platform = "opentofu"`. Omit `terraform-version` alongside it -- Scalr then picks
  the latest OpenTofu build via `get_latest_opentofu()`. Pinning a Terraform version
  number next to an OpenTofu platform is how you get a confusing failure.
* `trigger-prefixes = ["pia-terraform"]`, so pushing a policy change does not also queue
  ten runs and pollute your timing measurements.

Worth knowing: the workspace API attribute value is `"opentofu"`, but the string that
reaches your policies as `input.tfrun.workspace.iac_platform` is `"tofu"` --
`policy_input.py:75` does `"tofu" if ws.iac_platform else "terraform"`. A policy matching
on `"opentofu"` will never fire.
