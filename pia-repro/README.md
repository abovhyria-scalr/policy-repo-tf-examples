# SCALRCORE-38740 repro — run PIA only for changed policies

Reproduces the current behaviour: **a one-line change to one policy re-evaluates every
enabled policy in the group against every run in scope.**

Ticket: [SCALRCORE-38740](https://scalr-labs.atlassian.net/browse/SCALRCORE-38740) ·
customer report: [CLOUD-4862](https://scalr-labs.atlassian.net/browse/CLOUD-4862)

New to Rego, or want to hand-check the fixture in the Rego Playground before pushing it?
Start with **[PLAYGROUND.md](PLAYGROUND.md)** — plain-English explanation of what each
part of this fixture is for, plus two copy-paste checks that take under ten minutes.

## Layout

| Path | Role |
|---|---|
| `pia-repro/` | policy group path — `scalr-policy.hcl` + 20 policies |
| `pia-common/` | common functions folder, deliberately **outside** `pia-repro/` |
| `pia-terraform/` | throwaway OpenTofu config for the repro workspaces |
| `pia-repro/testdata/` | two fixture inputs matching the real `tfplan` / `tfrun` shape |
| `scripts/pia-validate.sh` | run this first — `opa check` + `opa eval` locally |
| `scripts/pia-te-setup.sh` | creates tags, workspaces, runs |
| `scripts/pia-measure.sh` | API-side inspection |
| `scripts/pia-sql.sh` | the queries that actually prove it |

The 20 policies:

- **10 cheap, self-contained** — `allowed_resource_types`, `deny_null_resource`,
  `max_resource_count`, `workspace_name_suffix`, `require_random_pet`,
  `deny_destroy_actions`, `require_provider_allowlist`, `deny_destroy_run`,
  `require_run_message`, `deny_auto_apply`
- **3 that import `pia-common`** — `tags_required`, `naming_convention`,
  `resource_budget`. Chain is `naming.rego ← helpers.rego ← these three`. This is the
  AC #3 set: a change to `pia-common/naming.rego` must mark exactly these as changed.
- **5 deliberately slow** — `slow_scan_1..5`, ~1–2 s of OPA evaluation each. A TE has ten
  workspaces, not State Farm's hundreds, so these substitute compute for scale and make
  the `O(runs × policies)` shape visible in wall clock. Tune the `work := 700` constant.
- **2 disabled caveat demos** — `nondeterministic_http` (the `http.send` problem from
  §4.3 of the analysis: carrying a non-deterministic result forward is a behaviour
  change) and `disabled_example` (flipping `enabled` is a manifest-only change with no
  `.rego` diff — AC #4).

Expected results against `pia-terraform` (6 resources: 2 `random_pet`, 1 `random_id`,
1 `random_string`, 2 `null_resource`), all `advisory` so nothing blocks:

| Always fails | Mixed by workspace | Always passes |
|---|---|---|
| `allowed_resource_types`, `deny_null_resource`, `max_resource_count`, `resource_budget` | `workspace_name_suffix`, `naming_convention`, `tags_required`, `require_run_message` | `require_random_pet`, `deny_destroy_actions`, `require_provider_allowlist`, `deny_destroy_run`, `deny_auto_apply`, `slow_scan_1..5` |

Mixed results matter: once the change ships, that's how you tell a freshly evaluated cell
from a carried-forward one.

Leave the group on the default `execute_as = policy-check` (post-plan). On a `pre-plan`
group `input.tfplan` is the empty string (`policy_input.py:317`), so every
`resource_changes` rule goes undefined and the whole matrix turns green.

---

## Setup on the TE

TE: `https://mainiacp.bovhyria.testenv.scalr.dev` · account `acc-svrcncgh453bi8g` ·
`tf-admin@scalr.com` · namespace `bovhyria`.

### 0. Validate locally first

I could not run `opa` while writing this, so check it before it costs you a TE round trip.
A rego syntax error or a manifest key that doesn't match a filename errors the entire
policy group, not just one policy.

```bash
./scripts/pia-validate.sh          # or: OPA=/path/to/opa ./scripts/pia-validate.sh
```

It verifies manifest keys against files both ways, runs `opa check` over the policies and
`pia-common` together, evaluates every policy against both fixtures, and times the
`slow_scan_*` set. Expected: `pia-01-dev` fails 4 policies, `pia-05` fails 8.

### 1. Push the fixture

Push to **`master`** of your fork. An earlier version of this file said to use a branch;
`master` is better, and not just for convenience.

```bash
cd policy-repo-tf-examples
git add pia-repro pia-common pia-terraform scripts
git commit -m "SCALRCORE-38740 PIA repro fixture"
git push
```

Why master, not a branch — `ABCPushHandler.handle_push_event`
(`taco/app/policy/tasks/vcs_event_handlers.py:221`):

```python
if binding.path and not event.created:
    if not _has_changes_in_path(binding.path, common_functions_folder):
        continue        # skip: nothing under our path changed
```

`event.created` is true for the push that *creates* a branch, and it short-circuits the
path filter — so the first push to a new branch triggers a full PIA no matter which files
it touched. That directly confounds the negative-control test in step 6 ("touch the root
README, expect no group check"). On an existing branch the filter applies from the first
push onward.

Using master also means the open-PR path works naturally later, since
`check_for_policy_group` enumerates open PRs against the group's branch
(`service/policy_group_check.py:243-266`).

**One thing to check if you already had policy groups on this repo:** a push to master
fires the webhook for every binding on that branch. Groups bound to a specific `path`
(`aws`, `oom_heavy`, …) are filtered out by the code above. But a group bound to the
**repository root** — empty path, the monorepo case — has `binding.path` falsy, so the
filter is skipped and it re-syncs and re-runs PIA on every push. Harmless, but it explains
any unexpected policy group activity you see after pushing.

### 2. VCS provider — Account scope → VCS providers

Connect GitHub against `abovhyria-scalr/policy-repo-tf-examples`. **Confirm the webhook
delivers.** In GitHub → repo → Settings → Webhooks, the most recent delivery must be
green. If the TE isn't reachable from GitHub, no push will trigger anything and you'll be
stuck on `actions/resync`, which takes the API path with no diff at all — a different code
path from the one the ticket is about.

Note the `vcs-...` id.

### 3. Workspaces and runs — this is where the repro usually dies

> **Order matters: workspaces and runs BEFORE the policy group.**
>
> Not for correctness — either order ends up with the same data — but for whether your
> baseline number means anything.
>
> If the policy group already exists when the runs finish, each finishing run fires its own
> `contribute_for_run` task (`run/signal_handlers.py:310`) and evaluates itself against the
> latest check. The matrix fills in correctly, but the work is spread across ten separate
> Celery tasks, so there is no single wall-clock figure to measure.
>
> Create the runs first and the policy group's initial sync does all ten in **one**
> `check_for_policy_group` task. That one task's duration is your baseline: the cost of a
> full evaluation. It's the number you compare everything else against.

`_get_runs_for_group_check` (`policy_group_check.py:476`) only sees
`Workspace.latest_planned_run`, set only when `not run.plan_only and run.has_changes and
run.plan.is_succeeded` (`run/service/remote/pipeline.py:743`), and only if
`status_changed_at` is inside 30 days and the run isn't a destroy.

Your `tfenv1` has `w2` and `w01` applied 22 Jul and `w02` failed — 2 usable runs, and one
of those has no successful plan. **If no workspace has `latest_planned_run`, PIA finishes
in seconds with an empty matrix and you'll conclude there's no problem.**

```bash
export SCALR_HOSTNAME=mainiacp.bovhyria.testenv.scalr.dev
export SCALR_TOKEN=...
export SCALR_ACCOUNT=acc-svrcncgh453bi8g
export SCALR_ENV=env-v0ord4r0sthdi9es5
export SCALR_VCS_PROVIDER=vcs-...
export SCALR_REPO=abovhyria-scalr/policy-repo-tf-examples
export SCALR_BRANCH=master

./scripts/pia-te-setup.sh 10
```

That creates the `owner` / `cost-center` account tags, ten **OpenTofu** workspaces
(`pia-01-dev` … `pia-10`, mixed suffixes, every other one tagged) bound to
`pia-terraform/` with `trigger-prefixes = ["pia-terraform"]`, and queues one run each.

Workspaces are created with `iac-platform = "opentofu"` and no `terraform-version`, so
Scalr assigns the latest OpenTofu build itself. **Check first that your TE has OpenTofu
versions seeded** — Account scope → Terraform & OpenTofu versions. If the list is
Terraform-only, workspace creation fails on a software-version lookup.

The trigger prefix matters: without it every policy push also queues ten OpenTofu runs
and your timing numbers are garbage.

Do **not** apply them. `on_run_stop` fires when the pipeline stops for user action, which
is enough to set `latest_planned_run`; leaving them unapplied keeps every plan at 6
creates forever, so policy results stay stable across commits.

One OpenTofu detail that bites: `input.tfrun.workspace.iac_platform` is the string
`"tofu"`, not `"opentofu"` (`policy_input.py:75`). Nothing in this fixture depends on it,
but if you add a platform-matching policy later, that's the value to match.

Verify before going further:

```bash
./scripts/pia-sql.sh visible acc-svrcncgh453bi8g
```

Every row must show `in_pia_scope = YES`. 10 workspaces × 18 enabled policies = 180 cells.

Wait for all ten plans to finish before moving on. A run still planning has no
`latest_planned_run` yet, so creating the policy group now would give you a baseline over
six workspaces instead of ten.

### 4. Policy group — Account scope → Policy engine → Policy groups → Create

| Field | Value |
|---|---|
| Name | `pia-repro` |
| VCS provider | the one from step 2 |
| Repository | `abovhyria-scalr/policy-repo-tf-examples` |
| Branch | `master` |
| Path | `pia-repro` |
| Common functions folder | `pia-common` |
| OPA version | pick the newest offered; anything ≥ 0.42 works |
| Execute as | leave the default (`policy-check` / post-plan) |

The policy group has no platform setting — OPA evaluates plan JSON, and OpenTofu emits the
same schema Terraform does. Only the workspaces are OpenTofu.

**On the OPA version dropdown.** Every policy here uses `import future.keywords`, which is
valid from OPA 0.42 all the way through 1.x (a no-op in 1.x). That was deliberate: this TE
defaults some groups to **0.55.0**, and `import rego.v1` — the more modern spelling — only
works from 0.59. Picking the wrong version there does not produce a helpful message; you
get `rego_parse_error: var cannot be used for rule name`, because an OPA that doesn't know
the `contains` and `if` keywords reads `deny contains msg if` as three stray variables.

If you see that error on a `pia-repro` policy, the cause is an OPA older than 0.42, not a
bug in the policy.

`common-functions-folder` is resolved from the **repository root**, not from `path` —
`os.path.join(repo_dir, vcs_ref.common_functions_folder)` at
`taco/app/policy/service/policy_group.py:355`. So it's `pia-common`, not
`../pia-common`.

Wait for `status = active` and 20 policies listed. If it's `errored`, the message is on
the group; the usual cause is a manifest key not matching a `.rego` filename
(`_read_policy_rego_code`, `policy_group.py:235`). The file is `scalr-policy.hcl` —
hyphen, not the underscore the Jira description uses.

Then link it to `tfenv1`, or set **enforced in all environments**. Note the `pgrp-...` id.

Linking is what triggers the first full check (`apis/policy_groups_environments.py:100`).
Watch it live — this is your baseline measurement:

```bash
kubectl -n bovhyria logs -f statefulset/scalr-server-0 \
  | grep -Ei 'check_for_policy_group|policy_group_check_id|group_check'
```

Two things to look for in that log:

- One `check_for_policy_group` task covering all ten runs. That's the baseline.
- A failed common-functions upload that then succeeds on retry. `helpers.rego` imports
  `data.pia.naming`, and `_process_common_functions_files` (`policy_check.py:20-63`)
  resolves upload order by retrying failures rather than reading imports. That retry loop
  is exactly what a real dependency graph (§4.2 of the analysis) would replace.

### 5. Baseline, then the one-line change

```bash
export SCALR_POLICY_GROUP=pgrp-...

# baseline — the environment link in step 4 ran one full check over all ten runs
./scripts/pia-sql.sh checks pgrp-...

# the change the whole ticket is about: one comment line, one policy, 18 evaluated
echo '# SCALRCORE-38740 one-line change' >> pia-repro/deny_null_resource.rego
git commit -am "one-line comment change to a single policy" && git push

./scripts/pia-sql.sh checks pgrp-...
```

**`cells` and `policies_per_run` will be identical between the two rows** — 180 both
times, ~18 policies per run — and `wall_seconds` roughly the same, for a commit that
changed a comment in one file. That row pair is the evidence for the ticket.

Worker log while it runs:

```bash
kubectl -n bovhyria logs -f statefulset/scalr-server-0 \
  | grep -Ei 'check_for_policy_group|policy_group_check_id|group_check'
```

### 6. The other three cases

**Zero policies changed, full PIA anyway** — the cleanest single demo:

```bash
sed -i '' 's/demo counter: \([0-9]*\)/demo counter: 1/' pia-repro/notes.txt
git commit -am "touch a non-policy file inside the policy path" && git push
./scripts/pia-sql.sh checks pgrp-...
```

`notes.txt` isn't in the manifest, so nothing about the policy group changed.
`_has_changes_in_path` only compares path prefixes, so the webhook passes and all 180
cells are recomputed. This is AC #5's target.

**Negative control** — touch `/README.md` at the repo root, push. No new group check;
`_has_changes_in_path` correctly suppresses it. Confirms the existing filter works and
that AC #5 is about the finer-grained case above.

**Shared dependency (AC #3)** — add a suffix to `pia-common/naming.rego`:

```bash
sed -i '' 's/allowed_suffixes := \["-dev", "-stg", "-prod"\]/allowed_suffixes := ["-dev", "-stg", "-prod", "-qa"]/' pia-common/naming.rego
git commit -am "add -qa suffix to shared naming helper" && git push
```

No `.rego` under `pia-repro/` changed, yet `tags_required`, `naming_convention` and
`resource_budget` must all be re-evaluated — they reach `naming` transitively through
`helpers`. Today all 18 run, so it "works" by accident. After the change, the correct
answer is exactly 3, and a dependency graph that stops at direct imports would wrongly
give 0. Keep this case in the regression test.

**Manifest-only change (AC #4)** — flip `disabled_example` to `enabled = true`. No `.rego`
diff at all. This is why the content hash has to cover `enabled` and `enforcement_level`,
not just `rego_code`.

### 7. Where to look in the UI

Account scope → Policy engine → `pia-repro`:

- **Policy impact analysis** tab → `GET /policy-groups/{id}/pull-request-policy-check-results`
  (`apis/policy_groups.py:807`)
- **Policy reports** tab → `GET /policy-group-checks/{id}/policy-check-results`
  (`apis/policy_group_checks.py:65`) — this is the one with the CSV export and the
  `filter[policy]` / `filter[result]` / `filter[environment]` filters that the
  carried-forward work has to keep working

The commit status pushed back to GitHub is `scalr/<pgrp_id>`, deep-linking to
`…/v2/a/<acc>/run-policy-engine/<pgrp_id>/policy-impact-analysis?commitSha=<sha>`
(`service/commitstatus.py:53`). Its latency is what the customer actually feels.

### 8. Before you write code: check the split

```
speedup ≈ 1 / (input_fraction + eval_fraction × changed/total)
```

Cutting the policies axis removes none of the plan-input builds — those are per run and
cached in `run_inputs`. Compare `group_check_input_build_seconds` against
`group_check_duration_seconds` (`taco/app/policy/metrics.py`) on this group. The `slow_scan_*`
policies deliberately weight the eval side; drop them to see the realistic ratio, since
real policies are cheap and it's the plan JSON download and sanitize that costs.

If input build dominates on the State Farm account, the `opa eval` batching TODO at
`policy_check.py:41` is the better ticket.

### 9. Scaling past what a TE can show

For the `O(runs × policies)` proof at customer scale, use the component test rather than
the TE:

```bash
tacocli test component --no-verify-api-naming --no-verify-api-coverage --no-generate-api-coverage \
  tests/component/taco/app/policy/service/test_policy_group_check.py::TestCheckForPolicyGroup::test_base
```

Parametrise it up and count `policy_check_service.check` calls. That's a faster loop than
the TE and it's where the regression test for this change belongs.

## Teardown

```bash
# workspaces are unapplied, so nothing to destroy
./scripts/pia-measure.sh latest-planned    # list them
```

Then delete the policy group and the ten workspaces in the UI. The fixture folders can
stay on master — they are inert unless a policy group points at `pia-repro`.
