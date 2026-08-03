#!/usr/bin/env bash
#
# SCALRCORE-38740 -- validate the repro fixture locally before pushing it.
#
# Catches the two failure modes that otherwise cost you a TE round trip:
#   * a rego syntax / undefined-reference error, which errors the whole policy group
#   * a manifest key that does not match a .rego filename, which does the same
#     (OpaPolicyGroup._read_policy_rego_code, taco/app/policy/service/policy_group.py:235)
#
# Needs the opa binary: https://www.openpolicyagent.org/docs/latest/#running-opa
# These policies use `import future.keywords`, which is valid from OPA 0.42 through 1.x,
# so any reasonably recent binary will do. Matching the policy group's opa-version exactly
# is still the safest check.
#
# Usage: ./scripts/pia-validate.sh
#
set -euo pipefail
cd "$(dirname "$0")/.."

OPA="${OPA:-opa}"
command -v "$OPA" >/dev/null || { echo "opa not found; set OPA=/path/to/opa" >&2; exit 1; }
"$OPA" version | head -2
echo

fail=0

echo "== manifest keys vs files =="
keys=$(grep -oE '^policy "[^"]+"' pia-repro/scalr-policy.hcl | sed 's/policy "//; s/"//')
for k in $keys; do
	[[ -f "pia-repro/${k}.rego" ]] || { echo "  MISSING pia-repro/${k}.rego"; fail=1; }
done
for f in pia-repro/*.rego; do
	n=$(basename "$f" .rego)
	grep -q "^policy \"${n}\"" pia-repro/scalr-policy.hcl \
		|| { echo "  ORPHAN ${f} is not in the manifest"; fail=1; }
done
echo "  $(wc -w <<<"$keys") manifest entries checked"
echo

echo "== opa check, one policy at a time + pia-common =="
# NOT `opa check pia-repro/*.rego` -- every policy is `package terraform`, so loading them
# together redeclares `allowed` (2x) and work/offset/hits (5x across slow_scan_1..5).
# Scalr uploads one module at a time (policy_check.py:117-120), so those collisions are
# legal in production and only an artifact of bundling. Check the same way Scalr runs.
for f in pia-repro/*.rego; do
	if "$OPA" check "$f" pia-common/ >/dev/null 2>&1; then
		printf '  ok    %s\n' "$(basename "$f")"
	else
		printf '  FAIL  %s\n' "$(basename "$f")"
		"$OPA" check "$f" pia-common/ 2>&1 | sed 's/^/        /'
		fail=1
	fi
done
echo

echo "== opa eval: deny per policy, per fixture =="
for input in pia-repro/testdata/input-*.json; do
	echo "--- $(basename "$input") ---"
	printf '%-30s %-8s %s\n' POLICY RESULT MESSAGES
	for f in pia-repro/*.rego; do
		n=$(basename "$f" .rego)
		# Each policy is evaluated in isolation against the shared common functions,
		# mirroring policy_check.check() in taco/app/policy/service/policy_check.py:115.
		out=$("$OPA" eval --fail-defined=false --format json \
			--data "$f" --data pia-common \
			--input "$input" 'data.terraform.deny' 2>&1) || { echo "  $n ERROR"; echo "$out" | head -5; fail=1; continue; }
		msgs=$(jq -r '[.result[0].expressions[0].value // []] | flatten | length' <<<"$out" 2>/dev/null || echo "?")
		if [[ "$msgs" == "0" ]]; then
			printf '%-30s %-8s\n' "$n" pass
		else
			body=$(jq -r '[.result[0].expressions[0].value // []] | flatten | .[0] // ""' <<<"$out")
			printf '%-30s %-8s %s\n' "$n" "FAIL($msgs)" "${body:0:70}"
		fi
	done
	echo
done

echo "== slow policy timing (what makes the repro measurable) =="
for n in 1 2 3 4 5; do
	s=$( { /usr/bin/time -f %e "$OPA" eval --format json --data "pia-repro/slow_scan_${n}.rego" \
		--input pia-repro/testdata/input-pia-01-dev.json 'data.terraform.deny' >/dev/null; } 2>&1 )
	printf '  slow_scan_%s  %ss\n' "$n" "$s"
done
echo
echo "18 enabled policies x N runs is the cost PIA pays today for a one-line change."

exit $fail
