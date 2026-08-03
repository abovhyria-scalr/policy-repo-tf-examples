# DISABLED by default (enabled = false in scalr-policy.hcl).
#
# SCALRCORE-38740 §4.3: a policy that calls http.send is not deterministic, so carrying
# its previous result forward is a behaviour change, not an optimisation. Either always
# re-evaluate any policy whose rego contains http.send, or document the caveat.
# Enable this one to demonstrate the problem; leave it off for timing runs.
package terraform

import rego.v1

deny contains msg if {
	resp := http.send({
		"method": "GET",
		"url": "https://www.random.org/integers/?num=1&min=1&max=10&col=1&base=10&format=plain",
		"raise_error": false,
		"timeout": "3s",
	})
	resp.status_code == 200
	to_number(trim_space(resp.raw_body)) > 5
	msg := "nondeterministic_http: coin flip came up deny"
}
