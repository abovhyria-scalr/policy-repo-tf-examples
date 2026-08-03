#!/usr/bin/env bash
#
# SCALRCORE-38740 -- measure what a PIA run actually did.
#
# Subcommands:
#   latest-planned   which workspaces PIA can see at all (the #1 repro trap)
#   checks           every source=vcs PolicyGroupCheck for the group, newest first
#   cells <pgchk>    result counts for one check, broken down by policy
#   resync           force a check without pushing a commit
#
# Usage:
#   export SCALR_HOSTNAME=mainiacp.bovhyria.testenv.scalr.dev
#   export SCALR_TOKEN=...
#   export SCALR_ENV=env-v0ord4r0sthdi9es5
#   export SCALR_POLICY_GROUP=pgrp-xxxxxxxxxxxx
#   ./scripts/pia-measure.sh checks
#
set -euo pipefail

: "${SCALR_HOSTNAME:?set SCALR_HOSTNAME}"
: "${SCALR_TOKEN:?set SCALR_TOKEN}"
API="https://${SCALR_HOSTNAME}/api/iacp/v3"

get() {
	curl -sS "${API}${1}" \
		-H "Authorization: Bearer ${SCALR_TOKEN}" \
		-H "Prefer: profile=preview"
}

case "${1:-checks}" in

latest-planned)
	: "${SCALR_ENV:?set SCALR_ENV}"
	echo "workspace                       latest_planned_run     visible_to_PIA"
	get "/workspaces?filter%5Benvironment%5D=${SCALR_ENV}&page%5Bsize%5D=100" \
	| jq -r '.data[] | [
			.attributes.name,
			(.relationships["latest-run"].data.id // "-"),
			(if .relationships["latest-run"].data then "yes" else "NO" end)
		] | @tsv' | column -t
	echo
	echo "NOTE: the API exposes latest-run, not latest_planned_run. For the value PIA"
	echo "actually queries, use the SQL in pia-repro/README.md step 4."
	;;

checks)
	: "${SCALR_POLICY_GROUP:?set SCALR_POLICY_GROUP}"
	get "/policy-group-checks?filter%5Bpolicy-group%5D=${SCALR_POLICY_GROUP}&include=vcs-revision&sort=-created-at&page%5Bsize%5D=20" \
	| jq -r '
		(.included // []) as $inc
		| .data[]
		| select(.attributes.source == "vcs")
		| [ .id,
		    .attributes.status,
		    (.attributes["created-at"] | tostring),
		    ( ($inc[] | select(.id == .relationships["vcs-revision"].data.id) | .attributes["commit-sha"][0:8]) // "-"),
		    (.attributes.result // {} | tostring)
		  ] | @tsv' 2>/dev/null \
	|| get "/policy-group-checks?filter%5Bpolicy-group%5D=${SCALR_POLICY_GROUP}&sort=-created-at&page%5Bsize%5D=20" \
	   | jq -r '.data[] | select(.attributes.source=="vcs")
	            | [.id, .attributes.status, .attributes["created-at"], (.attributes.result|tostring)] | @tsv'
	;;

cells)
	CHK="${2:?usage: pia-measure.sh cells pgchk-xxxxxxxx}"
	echo "total result rows:"
	get "/policy-group-checks/${CHK}/policy-check-results?page%5Bsize%5D=1" | jq -r '.meta.pagination["total-count"]'
	echo
	echo "per policy:"
	get "/policy-group-checks/${CHK}/policy-check-results?page%5Bsize%5D=500" \
	| jq -r '.data[] | [.attributes.name, .attributes.result] | @tsv' \
	| sort | uniq -c | sort -k2
	;;

resync)
	: "${SCALR_POLICY_GROUP:?set SCALR_POLICY_GROUP}"
	curl -sS -X POST "${API}/policy-groups/${SCALR_POLICY_GROUP}/actions/resync" \
		-H "Authorization: Bearer ${SCALR_TOKEN}" \
		-H "Content-Type: application/vnd.api+json" \
		-H "Prefer: profile=preview" -w '\nHTTP %{http_code}\n'
	echo "NOTE: resync goes through the API trigger path, which has NO commit diff at all."
	echo "It will always be a full evaluation, even after SCALRCORE-38740 ships."
	;;

*) sed -n '2,20p' "$0"; exit 1 ;;
esac
