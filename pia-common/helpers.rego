# Mid-level helper module. Imports data.pia.naming.
#
# SCALRCORE-38740 note: `_process_common_functions_files` in
# taco/app/policy/service/policy_check.py uploads these modules in os.listdir order and
# retries on failure to resolve ordering. "helpers" sorts before "naming", so on most
# filesystems helpers is attempted first, fails with "undefined function
# data.pia.naming.has_valid_suffix", is pushed to the end of the queue and succeeds on the
# second pass. That retry is observable in the worker logs and is the code a real
# dependency graph (§4.2 of the analysis) would replace.
package pia.helpers

import data.pia.naming
import rego.v1

workspace_name := object.get(input, ["tfrun", "workspace", "name"], "")

workspace_tags := object.get(input, ["tfrun", "workspace", "tags"], [])

created_resources := [rc |
	some rc in object.get(input, ["tfplan", "resource_changes"], [])
	"create" in rc.change.actions
]

count_of_type(t) := count([rc | some rc in created_resources; rc.type == t])

workspace_name_ok if naming.has_valid_suffix(workspace_name)

workspace_slug_ok if naming.is_slug(workspace_name)

required_tags := ["owner", "cost-center"]

missing_tags := [t |
	some t in required_tags
	not t in workspace_tags
]
