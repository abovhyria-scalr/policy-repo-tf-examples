#!/usr/bin/env bash
#
# SCALRCORE-38740 -- provision the PIA repro on a test environment.
#
# Creates:
#   * two account tags (owner, cost-center) so tags_required has something to see
#   * N VCS-backed OpenTofu workspaces pointing at pia-terraform/
#   * one run per workspace, so Workspace.latest_planned_run gets set
#
# Workspaces are created with iac-platform = "opentofu" and NO terraform-version, so Scalr
# assigns the latest OpenTofu build itself (get_latest_opentofu()). If workspace creation
# fails with a software-version error, the TE has no OpenTofu versions seeded -- check
# Account scope -> Terraform & OpenTofu versions.
#
# It does NOT create the policy group -- do that in the UI once, it is a single form and
# the error messages are better there. See pia-repro/README.md step 3.
#
# Usage:
#   export SCALR_HOSTNAME=mainiacp.bovhyria.testenv.scalr.dev
#   export SCALR_TOKEN=...                     # account-scope API token
#   export SCALR_ACCOUNT=acc-svrcncgh453bi8g
#   export SCALR_ENV=env-v0ord4r0sthdi9es5
#   export SCALR_VCS_PROVIDER=vcs-xxxxxxxxxxxx
#   export SCALR_REPO=abovhyria-scalr/policy-repo-tf-examples
#   ./scripts/pia-te-setup.sh [workspace_count]   # default 10
#
set -euo pipefail

: "${SCALR_HOSTNAME:?set SCALR_HOSTNAME}"
: "${SCALR_TOKEN:?set SCALR_TOKEN}"
: "${SCALR_ACCOUNT:?set SCALR_ACCOUNT}"
: "${SCALR_ENV:?set SCALR_ENV}"
: "${SCALR_VCS_PROVIDER:?set SCALR_VCS_PROVIDER}"
: "${SCALR_REPO:?set SCALR_REPO}"

COUNT="${1:-10}"
BRANCH="${SCALR_BRANCH:-master}"
API="https://${SCALR_HOSTNAME}/api/iacp/v3"
PREFIX="${SCALR_WS_PREFIX:-pia}"

api() { # api METHOD PATH [BODY]
	local method="$1" path="$2" body="${3:-}" out code
	if [[ -n "$body" ]]; then
		out=$(curl -sS -w $'\n%{http_code}' -X "$method" "${API}${path}" \
			-H "Authorization: Bearer ${SCALR_TOKEN}" \
			-H "Content-Type: application/vnd.api+json" \
			-H "Prefer: profile=preview" \
			-d "$body")
	else
		out=$(curl -sS -w $'\n%{http_code}' -X "$method" "${API}${path}" \
			-H "Authorization: Bearer ${SCALR_TOKEN}" \
			-H "Prefer: profile=preview")
	fi
	code=$(tail -n1 <<<"$out")
	body=$(sed '$d' <<<"$out")
	if [[ "$code" -ge 400 ]]; then
		echo "  !! ${method} ${path} -> HTTP ${code}" >&2
		echo "$body" | head -c 2000 >&2; echo >&2
		return 1
	fi
	printf '%s' "$body"
}

echo "== account tags =="
declare -A TAG_ID
for tag in owner cost-center; do
	existing=$(api GET "/tags?filter%5Bname%5D=${tag}" | jq -r '.data[0].id // empty')
	if [[ -n "$existing" ]]; then
		TAG_ID[$tag]="$existing"
		echo "  ${tag} exists: ${existing}"
	else
		id=$(api POST /tags "$(jq -nc --arg n "$tag" --arg acc "$SCALR_ACCOUNT" '
			{data:{type:"tags",attributes:{name:$n},
			 relationships:{account:{data:{type:"accounts",id:$acc}}}}}')" | jq -r '.data.id')
		TAG_ID[$tag]="$id"
		echo "  ${tag} created: ${id}"
	fi
done

# Workspace naming drives workspace_name_suffix and naming_convention.
# Deliberately mixed so the PIA matrix is not uniformly green.
suffix_for() {
	case $(( $1 % 5 )) in
		0) echo "" ;;        # no suffix -> FAILS workspace_name_suffix + naming_convention
		1|2) echo "-dev" ;;
		3) echo "-stg" ;;
		4) echo "-prod" ;;
	esac
}

echo
echo "== workspaces (${COUNT}) =="
WS_IDS=()
for i in $(seq -f '%02g' 1 "$COUNT"); do
	name="${PREFIX}-${i}$(suffix_for "$((10#$i))")"
	existing=$(api GET "/workspaces?filter%5Bname%5D=${name}&filter%5Benvironment%5D=${SCALR_ENV}" \
		| jq -r '.data[0].id // empty')
	if [[ -n "$existing" ]]; then
		ws="$existing"; echo "  ${name} exists: ${ws}"
	else
		ws=$(api POST /workspaces "$(jq -nc \
			--arg name "$name" --arg repo "$SCALR_REPO" --arg branch "$BRANCH" \
			--arg env "$SCALR_ENV" --arg vcs "$SCALR_VCS_PROVIDER" '
			{data:{type:"workspaces",
			 attributes:{
			   name:$name,
			   "auto-apply":false,
			   "iac-platform":"opentofu",
			   "working-directory":"pia-terraform",
			   "vcs-repo":{
			     identifier:$repo,
			     branch:$branch,
			     "trigger-prefixes":["pia-terraform"],
			     "dry-runs-enabled":false
			   }},
			 relationships:{
			   environment:{data:{type:"environments",id:$env}},
			   "vcs-provider":{data:{type:"vcs-providers",id:$vcs}}}}}')" \
			| jq -r '.data.id')
		echo "  ${name} created: ${ws}"
	fi
	WS_IDS+=("$ws")

	# Tag only every other workspace, so tags_required produces mixed results.
	if (( 10#$i % 2 == 1 )); then
		api PATCH "/workspaces/${ws}/relationships/tags" "$(jq -nc \
			--arg a "${TAG_ID[owner]}" --arg b "${TAG_ID[cost-center]}" '
			{data:[{type:"tags",id:$a},{type:"tags",id:$b}]}')" >/dev/null
		echo "      tagged owner + cost-center"
	fi
done

echo
echo "== runs =="
# A plan-only (dry) run will NOT set latest_planned_run -- pipeline.py:743 requires
# `not run.plan_only`. So these are real runs left waiting for confirmation. Do not apply
# them; on_run_stop fires when the pipeline stops for user action, which is enough.
for ws in "${WS_IDS[@]}"; do
	run=$(api POST /runs "$(jq -nc --arg ws "$ws" '
		{data:{type:"runs",
		 attributes:{message:"SCALRCORE-38740 PIA repro baseline plan","is-dry":false},
		 relationships:{workspace:{data:{type:"workspaces",id:$ws}}}}}')" \
		| jq -r '.data.id')
	echo "  ${ws} -> ${run}"
done

cat <<EOF

Done. Now wait for the plans to finish, then confirm PIA can actually see them:

  ./scripts/pia-measure.sh latest-planned

Any workspace with a null latest_planned_run is invisible to
_get_runs_for_group_check and will silently shrink your repro.
EOF
