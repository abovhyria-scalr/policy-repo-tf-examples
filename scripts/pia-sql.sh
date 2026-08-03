#!/usr/bin/env bash
#
# SCALRCORE-38740 -- the queries that actually prove the bug. Run against the TE's MySQL.
#
# Usage:  ./scripts/pia-sql.sh <query> [args]
#   visible  <acc_id>            what _get_runs_for_group_check can see
#   checks   <pgrp_id>           cells + wall clock per group check   <-- THE EVIDENCE
#   policies <pgchk_id>          which policies were evaluated in one check
#
# Assumes kubectl context on the TE. Override NS / POD if yours differ.
set -euo pipefail
NS="${NS:-bovhyria}"
POD="${POD:-mysql-0}"
DB="${DB:-scalr}"

run_sql() { kubectl -n "$NS" exec -i "$POD" -- mysql -uroot "$DB" -t -e "$1"; }

case "${1:?see header}" in

visible)
	ACC="${2:?acc-...}"
	run_sql "
	SELECT w.name AS workspace, w.latest_planned_run, r.status, r.status_changed_at,
	       r.is_destroy, r.plan_only,
	       CASE WHEN w.latest_planned_run IS NOT NULL
	                 AND r.status_changed_at > NOW() - INTERVAL 30 DAY
	                 AND r.is_destroy = 0
	            THEN 'YES' ELSE 'no' END AS in_pia_scope
	FROM tf_workspaces w
	LEFT JOIN tf_runs r ON r.id = w.latest_planned_run
	WHERE w.account_id = '${ACC}'
	ORDER BY w.name;"
	;;

checks)
	PG="${2:?pgrp-...}"
	# runs_evaluated x policies = cells. If cells is identical between a full-repo commit
	# and a one-line single-policy commit, that is SCALRCORE-38740 in one row.
	run_sql "
	SELECT gc.id, gc.status, LEFT(vr.commit_sha, 8) AS sha, gc.created_at,
	       COUNT(DISTINCT pc.id) AS runs_evaluated,
	       COUNT(pcr.id)         AS cells,
	       ROUND(COUNT(pcr.id) / NULLIF(COUNT(DISTINCT pc.id), 0), 1) AS policies_per_run,
	       TIMESTAMPDIFF(SECOND, gc.created_at, MAX(pc.created_at)) AS wall_seconds,
	       gc.total_failed
	FROM tf_policy_group_checks gc
	JOIN vcs_revisions vr ON vr.id = gc.revision_binding_id
	LEFT JOIN tf_policy_checks pc ON pc.policy_group_check_id = gc.id
	LEFT JOIN tf_policy_check_results pcr ON pcr.policy_check_id = pc.id
	WHERE gc.policy_group_id = '${PG}' AND gc.source = 'vcs'
	GROUP BY gc.id
	ORDER BY gc.created_at DESC
	LIMIT 20;"
	;;

policies)
	CHK="${2:?pgchk-...}"
	run_sql "
	SELECT pcr.name AS policy, pcr.result, COUNT(*) AS rows_
	FROM tf_policy_check_results pcr
	JOIN tf_policy_checks pc ON pc.id = pcr.policy_check_id
	WHERE pc.policy_group_check_id = '${CHK}'
	GROUP BY pcr.name, pcr.result
	ORDER BY pcr.name;"
	;;

*) sed -n '2,14p' "$0"; exit 1 ;;
esac
