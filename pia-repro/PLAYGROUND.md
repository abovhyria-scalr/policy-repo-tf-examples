# Checking the fixture by hand in the Rego Playground

For [play.openpolicyagent.org](https://play.openpolicyagent.org). Written for someone who
hasn't used Rego before.

---

## Part 1 — plain English: what did I add, and why

### What the feature is

Scalr lets you write rules about Terraform and OpenTofu. "No `null_resource`." "Workspace names must
end in `-dev`." Those rules are files written in a language called **Rego**, and they live
in a Git repo — this repo. A **policy group** is Scalr pointing at one folder of them.

Two moments matter:

1. **During a run.** Someone runs OpenTofu or Terraform, Scalr checks the plan against your rules, and
   blocks it if a rule fails.
2. **When you edit a rule.** Scalr asks: *if this new rule had been active, which of my
   existing workspaces would have failed?* That's **Policy Impact Analysis** (PIA). It's a
   preview of the blast radius, so you don't merge a rule that breaks 200 teams.

### The bug in ticket SCALRCORE-38740

PIA is thorough in a wasteful way. Change **one** rule and Scalr re-checks **all** of them
against **every** workspace. A customer (State Farm) has 25 rules and hundreds of
workspaces; fixing one typo made them wait 4–5 hours.

The ticket is: only re-check the rules that actually changed.

### Why I needed to build a fixture at all

Before changing code you have to see the bug. That means a policy group big enough for
"all rules" to be visibly more than "one rule". Two problems with your test environment:

- **Your test env has 3 workspaces, not hundreds.** Even doing 100% of the wasted work,
  the whole thing finishes in seconds. Nothing to see.
- **The existing folders in this repo hold 1–2 rules each.** Change one of two rules and
  you've saved 50% — not a convincing demo.

So the fixture solves both:

| What I added | Why |
|---|---|
| `pia-repro/` with **20 rules in one group, 14 enabled** | so "one changed rule out of 14" is a real ratio |
| `slow_scan_1..5` — 5 rules that do pointless heavy math | so 10 workspaces feel like 500. Substituting compute for scale is the only way to see the cost on a small test env |
| `pia-common/` — shared helper code, kept **outside** the rules folder | the ticket says a rule must be re-checked if *shared code it depends on* changed, even when the rule file itself is untouched. Three rules depend on this folder, so you can test exactly that |
| `pia-terraform/` — 6 fake resources, no cloud, no cost | PIA needs workspaces with real OpenTofu plans to check against. `random_pet` and `null_resource` create nothing real |
| Rules deliberately split into always-fail / always-pass / depends-on-the-workspace | once the fix ships, results carried over from a previous check must be visually distinguishable from fresh ones. If every result were green you couldn't tell them apart |
| `notes.txt` | a file in the rules folder that isn't a rule. Touch it and Scalr runs the full analysis for a commit that changed **zero** rules — the shortest possible demo of the waste |
| `scripts/*.sh` | setup and measurement, so the numbers come from a query and not from a stopwatch |

Nothing here ships to customers. It's a test fixture, like a crash-test dummy.

---

## Part 2 — one thing to understand about Rego first

A Rego file starts with a **package** name, and Scalr requires the package `terraform`
plus a rule called **`deny`**:

```rego
package terraform

import future.keywords

deny contains msg if {
	some rc in input.tfplan.resource_changes
	rc.type == "null_resource"
	msg := sprintf("deny_null_resource: %s uses null_resource", [rc.address])
}
```

Read that as: *"add a message to `deny` for every resource in the plan whose type is
`null_resource`."*

- `deny` is a **set of strings**. Empty set = the rule passed. Non-empty = it failed, and
  the strings are the reasons shown in the UI.
- Lines inside `{ }` are joined by AND. All must hold for a message to be added.
- `input` is the JSON Scalr hands to OPA. It has exactly two keys you care about:
  **`input.tfplan`** (the OpenTofu/Terraform plan — what will be created or destroyed) and
  **`input.tfrun`** (context — workspace name, tags, who triggered it).
- One quirk that trips everyone: if a rule mentions a field that doesn't exist, the rule
  is **undefined**, which counts as a pass, not an error. A rule that silently passes
  because you typo'd a field name looks identical to a rule that genuinely passed.

That last point is exactly why validating in the Playground is worth your time.

---

## Part 3 — the actual checks

The Playground has one editor and one package. The fixture is 20 separate files, 14 of
them enabled, that Scalr loads one at a time. So I flattened the 9 enabled non-slow ones
into a single paste-able file. The flattening only renames things and inlines the shared
helpers — no logic changed. There's a comment block at the top of the file explaining
both edits.

### Check A — do all 9 rules behave correctly? (5 minutes)

1. Confirm the **`Rego (v1)`** dropdown in the toolbar says v1. It does in your screenshot.
2. Open `pia-repro/testdata/playground-all.rego`, copy the whole thing, replace everything
   in the editor.
3. Open `pia-repro/testdata/input-pia-05.json`, copy it, replace everything in the **INPUT**
   panel.
4. Click **Evaluate**.

**Expected: `deny` contains exactly 5 messages.** Every message starts with the name of
the rule that produced it:

```
max_resource_count: 6 resource changes exceeds the limit of 4
workspace_name_suffix: workspace "pia-05" must end with -dev, -stg or -prod
tags_required: workspace "pia-05" is missing tags ["owner", "cost-center"]
naming_convention: workspace "pia-05" must end with one of ["-dev", "-stg", "-prod"]
resource_budget: 2 x null_resource exceeds the budget of 1
```

**Ignore the OUTPUT keys that aren't `deny`.** You'll also see `allowed_types`,
`h_workspace_name`, `h_created_resources` and so on. The Playground prints every rule in
the package; Scalr only ever asks for `data.terraform.deny`
(`policy_check.py:98`). Seeing `h_missing_tags: ["owner", "cost-center"]` is handy for
debugging, but it isn't a result.

5. Now swap the INPUT for `input-pia-01-dev.json` and Evaluate again.

**Expected: exactly 2 messages** — `max_resource_count` and `resource_budget`.

The three that disappeared — `workspace_name_suffix`, `tags_required`,
`naming_convention` — are the point of having two fixtures. That workspace is named
`pia-01-dev` and is tagged, so those three pass.

**If both counts match, the fixture is correct** and you can push it. If a rule you
expected is missing, it's almost certainly the undefined-field trap from Part 2, not a
logic bug.

#### About the LINT panel

The **LINT** panel will show **2 `style/messy-rule` violations**, and that is expected.

These are style suggestions from Regal, not errors — the policy evaluates fine, and Scalr
does not run Regal. "Messy incremental rule" means the several `deny` definitions aren't
adjacent in the file: they are separated by constants belonging to their original rules
(`allowed_providers := {…}`, `resource_budget_limits := {…}`).

That's purely an artifact of flattening 9 files into one. In the real fixture each `deny`
sits alone in its own file, so the lint doesn't apply there. Silencing it here would mean
hoisting all the constants to the top and losing the one-section-per-original-file layout
that makes this harness readable — not worth it.

If you also see a 4th violation, `style/unconditional-assignment` on
`h_count_of_type`, you have an older copy of the file. That one was a genuine style
problem in `pia-common/helpers.rego` too, and both are now fixed — re-copy the file.

Any lint category *other* than those is worth looking at.

### Check B — see why the slow rules exist (3 minutes)

Paste `pia-repro/testdata/playground-slow.rego` over the editor. Leave INPUT alone; this
rule ignores it. Then walk `work` up rather than taking a single reading — the point is the
*shape* of the curve, not one number:

| `work` | iterations | expected |
|---|---|---|
| 100 | ~10,000 | note the time |
| 200 | ~40,000 | ~4× the previous |
| 400 | ~160,000 | ~4× again |
| 700 | ~490,000 | the fixture default |

Each doubling of `work` should roughly quadruple the time, because the loop is quadratic.
Read the grey line above OUTPUT — the one that said *"Found 1 result in 36.348µs"* for
hello-world.

Expected OUTPUT at any setting, and it should stay this small:

```json
{ "deny": [], "hits": 44545, "work": 700 }
```

`deny: []` means it passed, which is correct — this rule is designed never to fire. `hits`
is the proof the loop actually ran.

**If OUTPUT comes back empty**, you've hit the Playground's evaluation cap; drop `work`
down. (My first version of this file hit that cap at the default setting — it stored every
matching pair in a named set, ~44,000 of them, which was too large for the Playground to
render. It now wraps `count()` directly around the comprehension so only the final number
is kept. If your copy has a rule called `pairs`, re-copy the file.) The cap is a
Playground limit only; Scalr runs OPA in its own container.

Then take your time at `work = 700` and multiply by 50 — five slow rules × ten workspaces.
That's roughly the wall clock your test environment will burn for a commit that changed one
comment. That's the knob that makes 10 workspaces behave like a customer's 500.

### Check C — the dependency case, which the Playground *cannot* test

Three rules (`tags_required`, `naming_convention`, `resource_budget`) get their logic from
`pia-common/`. When Scalr runs them, they say `import data.pia.helpers` and Scalr loads
that second file alongside. The Playground can only hold one file, so
`playground-all.rego` has those helpers pasted inline with `h_` and `n_` prefixes.

**This means the Playground checks the helper logic but not the import wiring.** If I got
an import path wrong, Check A still passes and the policy group errors on your test env.

Two ways to cover it:

```bash
./scripts/pia-validate.sh     # opa check across both folders at once — catches bad imports
```

or just watch the policy group go `active` in step 3 of `README.md`. If it goes `errored`
instead, the message on the group will name the bad import.

---

## If something looks wrong

| Symptom | Likely cause |
|---|---|
| `rego_parse_error: var cannot be used for rule name` | the OPA reading the file is too old to know the `contains` / `if` keywords. In the Playground, set the dropdown to `Rego (v1)`. In Scalr, the policy group's OPA version is below 0.42 |
| A rule you expected to fail isn't in `deny` | typo in a field path — undefined counts as a pass (Part 2) |
| `undefined function data.pia...` | you pasted a fixture file from `pia-repro/` instead of `playground-all.rego`. Those reference the separate helper folder |
| Check B output is empty, or the Playground hangs | evaluation cap — lower `work`. Also check your copy has `hits`, not `pairs` |
| Way more messages than expected | check you replaced the INPUT panel, not appended to it |
| 2 `style/messy-rule` lint violations | expected — see the LINT section above |

Next step once both checks pass: `pia-repro/README.md`, step 1 onwards.
