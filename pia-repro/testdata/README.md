# testdata

Two hand-built policy inputs matching what Scalr actually sends: top-level `tfplan` and
`tfrun` keys, `tfrun` shaped by `types.Run` / `types.Workspace` in
`taco/app/policy/types.py:70-110` (snake_case — those models have no `alias_generator`,
unlike `Vcs`), `tfplan` shaped like `tofu show -json`.

The workspaces run **OpenTofu**, which shows up in two places:

* `provider_name` is `registry.opentofu.org/hashicorp/...`, not `registry.terraform.io/...`.
  Same config, different registry -- which is why `require_provider_allowlist.rego`
  allowlists both.
* `tfrun.workspace.iac_platform` is the string **`"tofu"`**, even though the workspace API
  attribute value is `"opentofu"` (`policy_input.py:75`). A policy matching on `"opentofu"`
  would never fire.

| File | Workspace | Expected |
|---|---|---|
| `input-pia-01-dev.json` | `pia-01-dev`, tagged `owner` + `cost-center` | passes the name and tag policies |
| `input-pia-05.json` | `pia-05`, untagged, short run message | fails `workspace_name_suffix`, `naming_convention`, `tags_required`, `require_run_message` |

Both trip `allowed_resource_types`, `deny_null_resource`, `max_resource_count` and
`resource_budget` — that's the `null_resource` pair in `pia-terraform/main.tf`.

Use `../../scripts/pia-validate.sh` to check every policy against both before pushing.
