# frozen_string_literal: true

# #1233 — what a caller needs to reach each /api/v1 route, for discovery.
#
# Discovery (`GET /api/v1/available`) used to list 45 hand-kept paths of the
# 202 the API serves. It now lists every route in ApiEndpointCatalog (the
# inventory the token picker and enforcement read), filtered by the token's
# limits and by this table. Each entry restates the check the controller
# itself makes; the controller stays the authority, and this table only
# decides what discovery advertises.
#
# A rule is one of:
#   :admin          instance administrators only
#   :authenticated  any authenticated caller (records may still be scoped)
#   [keys]          the caller holds ANY of these permissions, at any boundary
#                   ("role:<name>" means the caller holds that role)
#   { all: [keys] } the caller holds ALL of them
#
# Each controller sets `read` and `write` (for ApiEndpointCatalog's access
# level of the route) and may override single actions. A route whose
# controller has no entry FAILS spec/lib/api_route_permissions_spec.rb, so a
# new API controller cannot go unlisted.
#
#   AC-3 / AC-6 (discovery shows only what the caller may use), PM-5 (inventory)
module ApiRoutePermissions
  RULES = {
    # ── Discovery, sessions, reference ───────────────────────────────────
    "discovery"              => { read: :authenticated },
    "sessions"               => { write: :authenticated },
    "guides"                 => { read: :authenticated },
    "federation_identities"  => { read: :authenticated },
    "control_lookups"        => { read: :authenticated },
    "artifacts"              => { read: :authenticated },
    "translations"           => { read: :authenticated },

    # ── Catalogs, profiles, CDEFs, mappings: the shared library ─────────
    # Reads are listed under the role vocabulary's read key, as discovery
    # listed them before #1233. The API controllers themselves admit any
    # authenticated caller to these reads; whether they should check the key
    # is open (raised on #1233), so discovery keeps advertising them to the
    # holders the vocabulary names.
    "control_catalogs"        => { read: [ "catalogs.read" ], write: [ "catalogs.write" ],
                                   actions: { "approve" => [ "catalogs.approve", "role:policy_manager" ],
                                              "reject"  => [ "catalogs.approve", "role:policy_manager" ] } },
    "control_families"        => { read: [ "catalogs.read" ], write: [ "catalogs.write" ] },
    "catalog_controls"        => { read: [ "catalogs.read" ], write: [ "catalogs.write" ] },
    "ksi_catalog"             => { read: [ "catalogs.read" ], write: [ "catalogs.write" ] },
    "profile_documents"       => { read: [ "profiles.read" ], write: [ "profiles.write" ],
                                   actions: { "approve" => [ "profiles.approve", "role:policy_manager" ],
                                              "reject"  => [ "profiles.approve", "role:policy_manager" ] } },
    "baseline_parameters"     => { read: [ "profiles.read" ], write: [ "profiles.write" ],
                                   actions: { "import_preview" => [ "profiles.write" ] } },
    "cdef_documents"          => { read: [ "cdef.read" ], write: [ "cdef.write" ],
                                   actions: { "approve"      => [ "cdef.approve", "role:policy_manager" ],
                                              "reject"       => [ "cdef.approve", "role:policy_manager" ],
                                              "bulk_destroy" => :admin,
                                              "import_fields_preview" => [ "converters.write" ],
                                              "import_fields_confirm" => [ "converters.write" ],
                                              "bulk_apply_converter_preview" => [ "converters.write" ],
                                              "bulk_apply_converter_confirm" => [ "converters.write" ] } },
    "cdef_coverage"           => { read: [ "cdef.read" ], write: [ "cdef.write" ],
                                   # Deletes any run the caller can see (scoped), with no permission check.
                                   actions: { "destroy_run" => :authenticated } },
    "control_mappings"        => { read: [ "mappings.read" ], write: [ "mappings.write" ] },
    "control_mapping_entries" => { read: [ "mappings.read" ], write: [ "mappings.write" ] },
    "converters"              => { read: :authenticated, write: [ "converters.write" ] },
    "converter_entries"       => { read: :authenticated, write: [ "converters.write" ] },

    # ── Boundary-scoped documents ───────────────────────────────────────
    # A collection read follows the read key. The index itself admits any
    # caller but lists only records they may read, so without the key it is
    # an empty list, which discovery does not advertise as usable.
    "ssp_documents"          => { read: [ "ssp.read" ], write: [ "ssp.write" ] },
    "ssp_components"         => { read: [ "ssp.read" ], write: [ "ssp.write" ] },
    "ssp_control_statements" => { read: [ "ssp.read" ], write: [ "ssp.write" ] },
    "ssp_roles"              => { read: [ "ssp.read" ], write: [ "ssp.write" ] },
    "sap_documents"          => { read: [ "sap.read" ], write: [ "sap.write" ] },
    "sar_documents"          => { read: [ "sar.read" ], write: [ "sar.write" ] },
    "sar_objectives"         => { read: [ "sar.read" ], write: [ "sar.write" ] },
    "sar_risks"              => { read: [ "sar.read" ], write: [ "sar.write" ] },
    "poam_documents"         => { read: [ "poam.read" ], write: [ "poam.write" ] },
    "poam_risks"             => { read: [ "poam.read" ], write: [ "poam.write" ] },
    "poam_items"             => { read: [ "poam.read" ], write: [ "poam.write" ] },
    "poam_findings"          => { read: [ "poam.read" ], write: [ "poam.write" ] },
    "poam_observations"      => { read: [ "poam.read" ], write: [ "poam.write" ] },
    "poam_local_components"  => { read: [ "poam.read" ], write: [ "poam.write" ] },
    "poam_milestones"        => { read: [ "poam.read" ], write: [ "poam.write" ] },
    "poam_remediations"      => { read: [ "poam.read" ], write: [ "poam.write" ] },

    # ── Authorization boundaries ─────────────────────────────────────────
    "authorization_boundaries" => { read: [ "authorization_boundaries.read" ],
                                    write: [ "authorization_boundaries.write" ],
                                    actions: { "destroy" => :admin, "bulk_destroy" => :admin,
                                               # BoundaryOrganizationAssigner: an org admin may assign an unassigned boundary.
                                               "assign_organization" => :authenticated } },
    "authorization_boundary_memberships" => { read: [ "authorization_boundaries.read" ],
                                              write: [ "authorization_boundaries.manage_members" ] },
    "boundary_readiness"       => { read: [ "authorization_boundaries.read" ] },
    "hdf_systems"              => { read: { all: [ "authorization_boundaries.read", "ssp.read" ] } },
    # Membership of the leveraging boundary, checked by the controller.
    "leveraged_authorizations" => { read: :authenticated, write: :authenticated },

    # ── Evidence, scans, KSI validations, findings ──────────────────────
    "evidences"              => { read: [ "evidence.read" ], write: [ "evidence.write" ] },
    "evidence_control_links" => { read: [ "evidence.read" ], write: [ "evidence.write" ] },
    "attestations"           => { read: [ "evidence.read" ], write: [ "evidence.write" ] },
    "attester_eligibility"   => { read: [ "evidence.write" ] },
    "aggregations"           => { write: [ "evidence.write" ] },
    "scan_runs"              => { read: [ "evidence.read" ], write: [ "evidence.write" ] },
    "scanner_findings"       => { read: [ "evidence.read" ] },
    "finding_dispositions"   => { read: [ "evidence.read" ], write: [ "evidence.write" ],
                                  actions: { "approve" => [ "amendment.approve" ],
                                             "reject"  => [ "amendment.approve" ] } },
    "hdf_amendments"         => { read: [ "evidence.read" ] },
    "hdf_packages"           => { read: [ "evidence.read" ] },
    "ksi_validations"        => { read: [ "evidence.read" ], write: [ "evidence.write" ],
                                  actions: { "destroy" => :admin } },

    # ── Back matter, authoritative sources, federation ──────────────────
    "back_matter_resources" => { read: [ "back_matter.read" ], write: [ "back_matter.write" ],
                                 actions: {
                                   "promote"           => [ "back_matter.promote", "back_matter.write" ],
                                   "approve_promotion" => [ "back_matter.approve_promotion" ],
                                   "reject_promotion"  => [ "back_matter.approve_promotion" ],
                                   "promotion_queue"   => [ "back_matter.approve_promotion" ],
                                   "bulk"              => [ "back_matter.bulk_import", "back_matter.write" ],
                                   "archive"           => [ "back_matter.archive", "back_matter.write" ],
                                   "restore"           => [ "back_matter.archive", "back_matter.write" ]
                                 } },
    # Reads and create are scoped to the caller's organization, with no permission check.
    "authoritative_sources" => { read: :authenticated, write: [ "back_matter.write" ],
                                 actions: { "create" => :authenticated,
                                            "export" => [ "back_matter.federate" ],
                                            "import" => [ "back_matter.federate" ] } },
    "federation_peers"      => { read: [ "back_matter.federate" ], write: [ "back_matter.federate" ] },

    # ── Administration ──────────────────────────────────────────────────
    "users"                  => { read: :admin, write: :admin,
                                  # A caller may read and update their own record.
                                  actions: { "show" => :authenticated, "update" => :authenticated } },
    "api_tokens"             => { read: :admin, write: :admin },
    "service_accounts"       => { read: :admin, write: :admin },
    "organizations"          => { read: :admin, write: :admin },
    "roles"                  => { read: :admin, write: :admin },
    "idp_grants"             => { read: :admin },
    "entitlement_sync"       => { read: :admin },
    "api_endpoints"          => { read: :admin },
    "admin/credentials"      => { write: [ "admin.rotate_credentials" ] },
    "admin/reconciliation"   => { read: :admin },
    "admin/remediation_timelines" => { read: :admin, write: :admin }
  }.freeze

  extend self

  # The controller's name under api/v1, e.g. "ssp_documents".
  def controller_of(route) = route.key.split("#").first.delete_prefix("api/v1/")

  def action_of(route) = route.key.split("#").last

  # The rule for a route, or nil when its controller has no entry (or no rule
  # for that access level).
  def rule_for(route)
    entry = RULES[controller_of(route)]
    return nil unless entry

    entry.dig(:actions, action_of(route)) || entry[route.access.to_sym]
  end

  # Does `user` meet `rule`? Instance administrators meet every rule.
  def satisfied?(user, rule)
    return false if user.nil? || rule.nil?
    return true if user.instance_administrator?

    case rule
    when :admin         then false
    when :authenticated then true
    when Hash           then rule.fetch(:all).all? { |key| holds?(user, key) }
    when Array          then rule.any? { |key| holds?(user, key) }
    else false
    end
  end

  def holds?(user, key)
    role = key.to_s.delete_prefix("role:")
    return user.has_role?(role) if role != key.to_s

    user.has_any_permission?(key)
  end
end
