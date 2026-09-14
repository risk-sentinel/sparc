# frozen_string_literal: true

# OSCAL roles (#1116).
#
# A `role-id` is an NCName token that must reference a role declared in
# `metadata.roles`. It is NOT a UUID, and it carries no namespace of its own.
#
# ── Two tiers, both legal ───────────────────────────────────────────────────
#
# NIST constrains `responsible-role/@role-id` with `allow-other="yes"` at every
# site in the SSP model, which means custom roles are ANTICIPATED, not tolerated.
# So there is no allow-list here and no validation that rejects an unknown id.
# The only hard rule — enforced by OscalConformanceService — is that whatever id
# is referenced must RESOLVE to a declared role.
#
#   Tier 1  NIST's suggested vocabulary, read from the generated conformance
#           dataset so it tracks the OSCAL version rather than a copied list.
#   Tier 2  Roles this deployment defines — AT&T's Policy Department, say.
#           Marked by a prop ON THE ROLE, because a role assembly carries props
#           (`assembly ref="property"` in metadata.xml) while its id cannot carry
#           a namespace.
#
# The point of offering tier 1 first is interoperability, not restriction:
# #1116 describes authors typing `isso`, which mints a private id for a role NIST
# already defines as `information-system-security-officer`. A reader resolving
# the NIST id knows what it means; one resolving `isso` has to guess.
class OscalRole
  ROLE_SOURCE_PROP = "role-source"
  ORGANIZATION_DEFINED = "organization-defined"

  # Acronyms that look wrong under naive capitalisation. `system-poc-technical`
  # should read "System POC (Technical)", not "System Poc Technical".
  ACRONYMS = { "poc" => "POC", "isso" => "ISSO", "issm" => "ISSM", "ao" => "AO" }.freeze

  # What an SSP declares when its author has declared nothing. Every id here is
  # in NIST's suggested vocabulary — verified by spec against the generated
  # dataset, so a typo or a NIST rename cannot pass silently.
  #
  # `prepared-by` is NIST's; `information-system-security-officer` is NIST's id
  # for the ISSO that #1116 records authors typing as `isso`.
  SSP_DEFAULT_IDS = %w[
    prepared-by
    system-owner
    authorizing-official
    information-system-security-officer
  ].freeze

  class << self
    # NIST's suggested role ids for an OSCAL version, as declarable roles.
    def suggested(version = OscalSchema::DEFAULT_VERSION)
      ids = OscalConformanceService.dataset_for(version)&.fetch("role_ids", nil) || []
      ids.map { |id| { "id" => id, "title" => humanize(id) } }
    end

    def suggested_ids(version = OscalSchema::DEFAULT_VERSION)
      suggested(version).map { |r| r["id"] }
    end

    # A role this deployment defined rather than NIST. The marker is a prop on
    # the role under the deployment namespace — never a namespaced id, which
    # OSCAL does not allow.
    def organization_defined(id, title)
      {
        "id" => id,
        "title" => title,
        "props" => [ { "name" => ROLE_SOURCE_PROP,
                       "ns" => OscalNamespace.instance,
                       "value" => ORGANIZATION_DEFINED } ]
      }
    end

    def organization_defined?(role)
      Array(role["props"]).any? do |p|
        p["name"] == ROLE_SOURCE_PROP && p["ns"] == OscalNamespace.instance
      end
    end

    def humanize(id)
      id.to_s.tr("_", "-").split("-").map { |w| ACRONYMS[w.downcase] || w.capitalize }.join(" ")
    end
  end
end
