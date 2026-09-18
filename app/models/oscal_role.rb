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
  # A declaration refused for a reason the author can act on. The message is
  # safe to show them.
  class DeclarationError < StandardError; end

  ROLE_SOURCE_PROP = "role-source"
  ORGANIZATION_DEFINED = "organization-defined"

  # Acronyms that look wrong under naive capitalisation. `system-poc-technical`
  # should read "System POC (Technical)", not "System Poc Technical".
  ACRONYMS = { "poc" => "POC", "isso" => "ISSO", "issm" => "ISSM", "ao" => "AO" }.freeze

  # ── Tier 2, sourced rather than typed (#1134) ───────────────────────────
  #
  # The deployment's own role vocabulary is the AUTHORIZATION-BOUNDARY
  # MEMBERSHIP roles — the seven built-ins plus whatever `SPARC_AUTH_BOUNDARY_ROLES`
  # adds (#875 made that configurable in fact, not just in name). That is where
  # personnel actually sit, which is the question an SSP's `responsible-role`
  # asks. `Role` is the permission-bearing vocabulary and answers a different
  # one — authority — so it is deliberately not the source here.

  # Membership roles that name a level of ACCESS, or bare participation, rather
  # than a function somebody is answerable for. Offering one as a
  # `responsible-role` would put a claim in the document that means nothing to
  # an assessor — "responsible for this control implementation: read-only
  # access" is not a statement anyone wants to defend.
  #
  # A DENY list, not an allow list, because the vocabulary is configurable: a
  # deployment that adds a role is naming a function, and we cannot know its
  # name in advance. Only the built-ins we ship can be judged here.
  ACCESS_ONLY_MEMBERSHIP_ROLES = %w[view_only project_member].freeze

  # Membership role → NIST's suggested id. VOCABULARY, not form, so it has to be
  # a table — no amount of case-folding gets from `isso` to
  # `information-system-security-officer`. Same discipline as
  # `AuthorizationBoundaryMembership.resolve_role` and `ControlId`.
  #
  # Only three of the seven built-ins have a NIST equivalent. The rest are
  # organization-defined, and inventing NIST ids for them would be the exact
  # failure this exists to prevent — an id NIST does not define, declared as
  # though it did. Every target here is checked against the generated dataset by
  # spec, so a typo or a NIST rename cannot pass silently.
  MEMBERSHIP_TO_NIST = {
    "authorizing_official" => "authorizing-official",
    "system_owner"         => "system-owner",
    "isso"                 => "information-system-security-officer"
  }.freeze

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

    # ── The boundary bridge (#1134) ──────────────────────────────────────
    #
    # `import_boundary_users` used to write the raw membership role into OSCAL
    # `role-ids` — underscored, which is not even NIST's form, and never
    # declared. Everything that turns a membership role into an OSCAL role now
    # goes through here, so the picker, the import and the migration cannot
    # disagree about what a role resolves to.

    def responsibility_bearing?(membership_role)
      ACCESS_ONLY_MEMBERSHIP_ROLES.exclude?(membership_role.to_s)
    end

    # `[[label, membership_role], ...]` for a picker. Reads `role_options`, so a
    # deployment that narrows the vocabulary narrows this too.
    def membership_role_options
      AuthorizationBoundaryMembership.role_options
                                     .select { |(_label, value)| responsibility_bearing?(value) }
    end

    # The declarable role a membership role resolves to: NIST's id where NIST
    # defines one, an organization-defined role otherwise. Either way the result
    # is something to DECLARE — the reference never dangles, and what is
    # non-NIST stays inside a namespaced prop.
    def from_membership_role(membership_role, version = OscalSchema::DEFAULT_VERSION)
      value = membership_role.to_s
      nist  = MEMBERSHIP_TO_NIST[value]

      # The dataset check is not ceremony: if NIST retires an id, the mapping
      # has to fall through to organization-defined rather than emit a reference
      # to a role the version's vocabulary no longer contains.
      return { "id" => nist, "title" => humanize(nist) } if nist && suggested_ids(version).include?(nist)

      organization_defined(membership_role_id(value),
                           AuthorizationBoundaryMembership.role_label_for(value))
    end

    # FORM only — `role-id` is an NCName and NIST's vocabulary is
    # lowercase-hyphen, while the membership column is underscored.
    def membership_role_id(membership_role)
      membership_role.to_s.tr("_", "-")
    end

    def humanize(id)
      id.to_s.tr("_", "-").split("-").map { |w| ACRONYMS[w.downcase] || w.capitalize }.join(" ")
    end
  end
end
