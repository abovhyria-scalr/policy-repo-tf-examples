# Leaf helper module. Nothing else in pia-common imports this.
#
# SCALRCORE-38740 note: this file is the bottom of a 2-level dependency chain
#   naming.rego  <-  helpers.rego  <-  {tags_required, naming_convention, resource_budget}
# A change here must mark those three policies as changed (AC #3) and nothing else.
package pia.naming

import rego.v1

allowed_suffixes := ["-dev", "-stg", "-prod"]

slug_pattern := "^[a-z0-9][a-z0-9-]{1,62}$"

has_valid_suffix(name) if {
	some suffix in allowed_suffixes
	endswith(name, suffix)
}

is_slug(name) if regex.match(slug_pattern, name)
