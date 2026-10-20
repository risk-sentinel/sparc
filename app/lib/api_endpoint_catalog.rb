# frozen_string_literal: true

# #1176 — the one definition of what an API token may be limited to.
#
# The token forms, the API that issues tokens, and the enforcement in
# ApiAuthentication all read this module, so a limit means the same thing on
# every path. It is built from the `/api/v1` route inventory, not typed out,
# so a new route lands in a group the moment it is drawn.
#
# A token's `allowed_endpoints` holds entries of three kinds:
#
#   "*"                     every endpoint. Stored as an EMPTY list, which is
#                           what "unrestricted" has always meant.
#   "ssp_documents:read"    one access level on one group. A group is the first
#                           path segment after /api/v1, so nested resources
#                           (an SSP's components) sit with their parent.
#   "/api/v1/ssp_documents*" a path pattern, as tokens were limited before this
#                           list existed. Kept working: it grants Read AND Write
#                           on the paths it matches, exactly as it did, so no
#                           token narrows on upgrade.
#
# Read or Write is a property of the ROUTE, not of the HTTP verb a caller
# might guess. GET and HEAD read. PUT, PATCH and DELETE write. POST writes
# unless the action is listed in READ_ONLY_POSTS: those compute an answer and
# change nothing (previews, translations, analysis). Owner, 2026-10-17:
# raw method checkboxes were rejected because many POSTs only compute.
#
# NIST SP 800-53 Rev 5: AC-3 (access enforcement), AC-6 (least privilege).
module ApiEndpointCatalog
  PREFIX = "/api/v1"
  ALL = "*"
  ACCESS_LEVELS = %w[read write].freeze
  READ_VERBS = %w[GET HEAD].freeze

  # POST actions that change nothing. Each was read before it was listed:
  # it returns a computed result and persists no record (audit events aside).
  # `ssp_documents#convert` and `sar_documents#convert` are NOT here: both
  # create a document. spec/lib/api_endpoint_catalog_spec.rb fails on an
  # entry that is no longer a POST route.
  READ_ONLY_POSTS = %w[
    api/v1/ssp_documents#import_fields_preview
    api/v1/sar_documents#import_fields_preview
    api/v1/sap_documents#import_fields_preview
    api/v1/cdef_documents#import_fields_preview
    api/v1/cdef_documents#bulk_apply_converter_preview
    api/v1/baseline_parameters#import_preview
    api/v1/cdef_coverage#analyze
    api/v1/entitlement_sync#preview
    api/v1/translations#sar_from_hdf
    api/v1/translations#poam_from_hdf
    api/v1/translations#poam_from_amendments
    api/v1/translations#amendments_from_oscal_poam
  ].freeze

  # Every group needs a label here. A route under a new first segment fails
  # spec/lib/api_endpoint_catalog_spec.rb until it is named, so a new resource
  # cannot appear on the token form as a bare path fragment.
  GROUP_LABELS = {
    "admin" => "Instance administration",
    "api_endpoints" => "API endpoint catalog",
    "artifacts" => "Artifacts",
    "attestations" => "Attester eligibility",
    "authoritative_sources" => "Authoritative sources",
    "authorization_boundaries" => "Authorization boundaries",
    "available" => "Discovery",
    "back_matter_resources" => "Back-matter resources",
    "cdef_coverage" => "CDEF coverage analysis",
    "cdef_documents" => "Component definitions (CDEF)",
    "control_catalogs" => "Control catalogs",
    "control_mappings" => "Control mappings",
    "controls" => "Control lookup",
    "converters" => "Converters",
    "entitlement_sync" => "Entitlement sync",
    "evidences" => "Evidence",
    "federation" => "Federation identity",
    "federation_peers" => "Federation peers",
    "guides" => "Guides",
    "hdf" => "HDF translations",
    "idp_grants" => "IdP grants",
    "ksi_catalog" => "KSI catalog",
    "organizations" => "Organizations",
    "oscal" => "OSCAL translations",
    "poam_documents" => "POA&Ms",
    "poam_risks" => "POA&M risks",
    "profile_documents" => "Profiles",
    "roles" => "Roles",
    "sap_documents" => "Assessment plans (SAP)",
    "sar_documents" => "Assessment results (SAR)",
    "sar_risks" => "SAR risks",
    "scanner_findings" => "Scanner findings",
    "service_accounts" => "Service accounts",
    "sessions" => "Browser sessions from a token",
    "ssp_control_statements" => "SSP control statements",
    "ssp_documents" => "System security plans (SSP)",
    "users" => "Users and API tokens"
  }.freeze

  Route = Struct.new(:verb, :spec, :key, :group, :access, keyword_init: true)
  Group = Struct.new(:key, :label, :access_levels, keyword_init: true)

  extend self

  # Every /api/v1 route with its group and access level.
  def routes
    Rails.application.routes.routes.filter_map do |route|
      spec = route.path.spec.to_s
      next unless spec == PREFIX || spec.start_with?("#{PREFIX}/", "#{PREFIX}(")

      key = "#{route.defaults[:controller]}##{route.defaults[:action]}"
      Route.new(verb: route.verb, spec: spec, key: key,
                group: group_of(spec), access: access_for(route.verb, key))
    end
  end

  # Groups for the token form, in label order. Each lists only the access
  # levels its routes actually have, so a read-only group offers no Write box.
  def groups
    routes.group_by(&:group).map do |key, list|
      Group.new(key: key, label: GROUP_LABELS.fetch(key, key),
                access_levels: ACCESS_LEVELS & list.map(&:access).uniq)
    end.sort_by(&:label)
  end

  def group_of(path)
    path.to_s.delete_prefix(PREFIX).delete_prefix("/").split(%r{[/(.]}).first.to_s
  end

  def access_for(verb, route_key)
    return "read" if READ_VERBS.include?(verb.to_s.upcase)
    return "read" if verb.to_s.upcase == "POST" && READ_ONLY_POSTS.include?(route_key)

    "write"
  end

  def entry(group, access) = "#{group}:#{access}"

  def legacy_pattern?(entry) = entry.to_s.start_with?("/")

  # Normalise a submitted list. "*" anywhere means every endpoint, which is
  # stored as an empty list. Blank entries are dropped, duplicates removed.
  def normalize(entries)
    list = Array(entries).map { |e| e.to_s.strip }.reject(&:blank?).uniq
    list.include?(ALL) ? [] : list
  end

  # Problems with a submitted list, one message per bad entry. The API refuses
  # a list with any; nothing is silently dropped.
  def errors_for(entries)
    normalize(entries).filter_map do |e|
      if legacy_pattern?(e)
        "#{e} matches no API route" unless pattern_matches_any_route?(e)
      else
        group, access = e.split(":", 2)
        known = groups.find { |g| g.key == group }
        if known.nil?
          "#{e}: #{group.inspect} is not an API resource group"
        elsif !known.access_levels.include?(access)
          "#{e}: #{known.label} offers #{known.access_levels.join(' and ')}, not #{access.inspect}"
        end
      end
    end
  end

  # Does this list let a request through? Empty means every endpoint.
  # `path` is the request path; `verb` and `route_key` ("controller#action")
  # identify the route the request reached, which fixes its access level.
  def permits?(entries, path:, verb:, route_key:)
    return true if entries.blank?

    needed = entry(group_of(path), access_for(verb, route_key))
    entries.any? do |e|
      legacy_pattern?(e) ? legacy_match?(e, path) : e == needed
    end
  end

  # The pre-#1176 rule, unchanged: "x*" is a prefix, anything else exact.
  def legacy_match?(pattern, path)
    pattern.end_with?("*") ? path.start_with?(pattern.chomp("*")) : path == pattern
  end

  # Human-readable lines for a token's limits, for the screens and the API.
  def describe(entries)
    return [ "All endpoints" ] if entries.blank?

    by_group = Hash.new { |h, k| h[k] = [] }
    patterns = []
    entries.each do |e|
      if legacy_pattern?(e)
        patterns << e
      else
        group, access = e.split(":", 2)
        by_group[group] << access
      end
    end
    by_group.map { |group, levels|
      "#{GROUP_LABELS.fetch(group, group)}: #{(ACCESS_LEVELS & levels).map(&:capitalize).join(' + ')}"
    }.sort + patterns.map { |p| "#{p} (path pattern: Read + Write)" }
  end

  # A legacy pattern is meaningful only if some route answers on it. Exact
  # patterns use the router's own matcher; "x*" prefixes compare segment by
  # segment, with ":param" route segments matching any value.
  def pattern_matches_any_route?(pattern)
    api_routes = Rails.application.routes.routes.select { |r| r.path.spec.to_s.start_with?(PREFIX) }
    if pattern.end_with?("*")
      prefix = pattern.chomp("*")
      api_routes.any? { |r| prefix_reaches?(r.path.spec.to_s.sub(/\(\.:format\)\z/, ""), prefix) }
    else
      api_routes.any? { |r| r.path.match(pattern) }
    end
  end

  def prefix_reaches?(spec, prefix)
    spec_parts = spec.split("/", -1)
    prefix_parts = prefix.split("/", -1)
    return false if prefix_parts.size > spec_parts.size

    prefix_parts.each_with_index.all? do |part, i|
      route_part = spec_parts[i]
      last = i == prefix_parts.size - 1
      if route_part.start_with?(":")
        true
      elsif last
        route_part.start_with?(part)
      else
        route_part == part
      end
    end
  end
end
