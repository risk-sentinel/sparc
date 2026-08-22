#!/usr/bin/env ruby
# frozen_string_literal: true

# Reconciles docs/api/sparc-api.postman_collection.json against the real
# /api/v1 surface.
#
# Usage (from repo root):
#   bin/api_postman_check.rb           # report what the collection is missing
#   bin/api_postman_check.rb --write   # add a request for every missing endpoint
#   bin/api_postman_check.rb --check   # exit 1 if anything is missing
#
# #995 — the collection covered 132 of 208 endpoints while its own description
# claimed "104 endpoints across 18 folders", and its Bulk Update Parameters body
# sent the object map the API refuses. A published collection that teaches a
# payload the server rejects is worse than no collection: it is the documented
# shape, so a caller trusts it over their own reading.
#
# The surface comes from `bin/api_inventory_check.rb --routes-json` rather than
# a second route loader here. Two tools deriving "the endpoints" independently
# is how they end up disagreeing about how many there are.
#
# Request bodies are built from each controller's own `permit_strictly` filter
# list — the same list the API now names in its `expected` array when it refuses
# a field. So a generated body cannot document a field the endpoint does not
# accept, which is the failure this script exists to stop repeating.

require "json"
require "set"

REPO_ROOT  = File.expand_path("..", __dir__)
COLLECTION = File.join(REPO_ROOT, "docs/api/sparc-api.postman_collection.json")
CONTROLLERS = File.join(REPO_ROOT, "app/controllers/api/v1")

# Folder names already in the collection, so a regenerated request lands beside
# its siblings instead of opening a near-duplicate folder.
# Literals used in several places. Named so a rename is one edit and a typo in
# one copy cannot silently disagree with the others.
TRANSLATIONS_FOLDER = "HDF ↔ OSCAL Translations"
HDF_SCAN_FIXTURE    = "scan.hdf.json"
CONTENT_TYPE_HEADER = "Content-Type"
JSON_CONTENT_TYPE   = "application/json"
# A Postman path variable, e.g. `{{slug}}`, normalised to `:id` for comparison
# against the route list.
POSTMAN_VARIABLE = /\{\{[^}]+\}\}/

CONTROLLER_TO_FOLDER = {
  "admin/credentials"                  => "Admin Credentials",
  "admin/reconciliation"               => "Admin Reconciliation",
  "admin/remediation_timelines"        => "Admin Remediation Timelines",
  "aggregations"                       => TRANSLATIONS_FOLDER,
  "artifacts"                          => "Artifacts",
  "attestations"                       => "Attestations",
  "attester_eligibility"               => "Attestations",
  "authoritative_sources"              => "Authoritative Sources",
  "authorization_boundaries"           => "Authorization Boundaries",
  "authorization_boundary_memberships" => "Boundary Memberships",
  "back_matter_resources"              => "Back-Matter Resources",
  "baseline_parameters"                => "Baseline Parameters",
  "catalog_controls"                   => "Catalog Controls",
  "cdef_coverage"                      => "CDEF Coverage",
  "cdef_documents"                     => "CDEF Documents",
  "control_catalogs"                   => "Control Catalogs",
  "control_families"                   => "Control Families",
  "control_lookups"                    => "Control Lookup",
  "control_mapping_entries"            => "Control Mappings",
  "control_mappings"                   => "Control Mappings",
  "discovery"                          => "Discovery",
  "evidence_control_links"             => "Evidence Control Links",
  "evidences"                          => "Evidence",
  "federation_peers"                   => "Federation Peers",
  "finding_dispositions"               => "Scanner Findings",
  "guides"                             => "Guides",
  "hdf_amendments"                     => TRANSLATIONS_FOLDER,
  "hdf_packages"                       => TRANSLATIONS_FOLDER,
  "ksi_catalog"                        => "KSI Catalog",
  "ksi_validations"                    => "KSI Validations",
  "oscal"                              => TRANSLATIONS_FOLDER,
  "poam_documents"                     => "POA&M Documents",
  "poam_risks"                         => "POA&M Risks",
  "profile_documents"                  => "Profile Documents",
  "sap_documents"                      => "SAP Documents",
  "sar_documents"                      => "SAR Documents",
  "scan_runs"                          => "Scan Runs",
  "scanner_findings"                   => "Scanner Findings",
  "sessions"                           => "Sessions",
  "ssp_components"                     => "SSP Components",
  "ssp_documents"                      => "SSP Documents",
  "translations"                       => TRANSLATIONS_FOLDER,
  "users"                              => "Users"
}.freeze

# Path segments the collection already parameterises, so a generated request
# uses the same variable a hand-written sibling does.
ID_VARIABLES = {
  "ssp_documents"            => "ssp_slug",
  "sar_documents"            => "sar_slug",
  "sap_documents"            => "sap_slug",
  "poam_documents"           => "poam_slug",
  "profile_documents"        => "profile_slug",
  "cdef_documents"           => "cdef_slug",
  "control_catalogs"         => "catalog_id",
  "authorization_boundaries" => "boundary_id"
}.freeze

# Endpoints that accept a payload BOTH ways — a multipart `file` upload and a
# raw request body — so the collection shows both rather than implying the one
# a generator happened to pick first. Verified in the controllers: the
# translation endpoints branch on `params[:file].respond_to?(:tempfile)` and
# fall back to `request.raw_post`; `scan_runs#create` does the same via
# `read_upload`.
#
# Endpoints that take a file ONLY (document `convert`, the ODP import pair) are
# deliberately absent: offering a raw-body variant there would document
# something that does not work.
DUAL_MODE_ENDPOINTS = {
  "POST /api/v1/oscal/sar_from_hdf" =>
    { file: HDF_SCAN_FIXTURE, note: "An HDF results file." },
  "POST /api/v1/oscal/poam_from_hdf" =>
    { file: HDF_SCAN_FIXTURE, note: "An HDF results file." },
  "POST /api/v1/oscal/poam_from_amendments" =>
    { file: "sample.hdf-amendments.json", note: "An HDF Amendments document." },
  "POST /api/v1/hdf/amendments_from_oscal_poam" =>
    { file: "poam.oscal.json", note: "An OSCAL POA&M document." },
  "POST /api/v1/authorization_boundaries/:id/scan_runs" =>
    { file: HDF_SCAN_FIXTURE, note: "A scanner output file." }
}.freeze

# Adds the missing half of a dual-mode endpoint, so the collection carries a
# JSON-body request and a multipart request side by side.
#
# The twin is inserted into the SAME folder object as its source. A first
# version placed it by searching folders for a matching request name, and
# "POST create" is not unique — a scan-run twin landed in Api Tokens.
def add_dual_mode_variants(collection)
  added = 0

  walk = lambda do |items|
    items.each do |entry|
      if entry["item"]
        walk.call(entry["item"])
        next
      end
      request = entry["request"]
      next unless request && request["method"] == "POST"

      segments = request.dig("url", "path") || []
      key = "POST " + normalize("/" + segments.map { |s| s.gsub(POSTMAN_VARIABLE, ":id") }.join("/"))
      spec = DUAL_MODE_ENDPOINTS[key]
      next unless spec
      next if entry["name"].to_s.match?(/\((?:raw body|multipart)/)

      mode = request.dig("body", "mode")
      next unless %w[raw formdata].include?(mode)

      entry["name"] = "#{entry['name']} (#{mode == 'raw' ? 'raw body' : 'multipart'})"

      twin = Marshal.load(Marshal.dump(entry))
      if mode == "raw"
        twin["name"] = twin["name"].sub("(raw body)", "(multipart file upload)")
        twin["request"]["header"] =
          (twin["request"]["header"] || []).reject { |h| h["key"] == CONTENT_TYPE_HEADER }
        twin["request"]["body"] = { "mode" => "formdata", "formdata" => [
          { "key" => "file", "type" => "file", "src" => [] }
        ] }
        twin["request"]["description"] =
          "#{spec[:note]} The same endpoint as the raw-body request above — send the " \
          "document as a multipart `file` field instead of as the request body."
      else
        twin["name"] = twin["name"].sub("(multipart)", "(raw body)")
        twin["request"]["header"] =
          (twin["request"]["header"] || []) + [ { "key" => CONTENT_TYPE_HEADER, "value" => JSON_CONTENT_TYPE } ]
        twin["request"]["body"] = { "mode" => "raw", "raw" => "{}",
                                    "options" => { "raw" => { "language" => "json" } } }
        twin["request"]["description"] =
          "#{spec[:note]} The same endpoint as the multipart request above — send the " \
          "document as the raw request body instead of as a `file` field."
      end

      items.insert(items.index(entry) + 1, twin)
      added += 1
    end
  end

  walk.call(collection["item"])
  added
end

def load_routes
  raw = `#{File.join(REPO_ROOT, 'bin/api_inventory_check.rb')} --routes-json`
  abort "could not read the route surface — is a DB-connected env available?" if raw.strip.empty?
  JSON.parse(raw, symbolize_names: true)
end

def load_collection = JSON.parse(File.read(COLLECTION))

def each_request(items, folder = nil, &block)
  items.each do |item|
    if item["item"]
      each_request(item["item"], item["name"], &block)
    elsif item["request"]
      block.call(folder, item)
    end
  end
end

def normalize(path) = path.gsub(%r{/:[a-z_]+}, "/:id").sub(%r{/\z}, "")

def route_keys(route)
  route[:method].split("/").map { |m| "#{m} #{normalize(route[:path])}" }
end

def covered_keys(collection)
  keys = Set.new
  each_request(collection["item"]) do |_folder, item|
    method = item.dig("request", "method")
    segments = item.dig("request", "url", "path") || []
    path = "/" + segments.map { |s| s.gsub(POSTMAN_VARIABLE, ":id") }.join("/")
    keys << "#{method} #{normalize(path)}"
  end
  keys
end

# The fields a controller actually accepts, read from its own permit list, so a
# generated body cannot name something the endpoint would refuse.
def permitted_fields(controller)
  file = File.join(CONTROLLERS, "#{controller.tr('/', '_')}_controller.rb")
  file = File.join(CONTROLLERS, "#{controller}_controller.rb") unless File.exist?(file)
  return [] unless File.exist?(file)

  source = File.read(file)
  # Both spellings occur: a single-line call, and one broken across lines. The
  # first pattern only matched the multi-line form, which is why memberships,
  # control families and the disposition endpoints generated no body at all.
  match = source[/permit_strictly\(\s*:[a-z_]+\s*,.*?\n\s*\)/m] ||
          source[/permit_strictly\(\s*:[a-z_]+\s*,[^\n]*\)/]
  return [] unless match

  root = match[/permit_strictly\(\s*:([a-z_]+)/, 1]
  body = match.sub(/permit_strictly\(\s*:[a-z_]+\s*,/, "")
  fields = body.scan(/:([a-z_]+)(?=\s*[,)\n])/).flatten
  fields -= %w[also_accepts]
  [ root, fields.uniq ]
end

# A handful of endpoints read their input straight off `params` rather than
# through a permit list, so nothing in the controller enumerates their fields
# for the parser above. They are listed here by route so a generated body still
# names what the action actually reads, taken from the controller source rather
# than invented. State transitions that genuinely take no body are absent on
# purpose — an empty body is the correct documentation for them.
UNPERMITTED_BODIES = {
  "PUT /api/v1/admin/remediation_timelines" =>
    { "baseline_level" => "", "criticality" => "", "days" => "" },
  "POST /api/v1/authorization_boundaries/:id/aggregate" =>
    { "async" => false },
  "POST /api/v1/scanner_findings/:id/disposition" =>
    { "kind" => "", "reason" => "", "expiration" => "",
      "linked_subject_type" => "", "linked_subject_id" => "" },
  "POST /api/v1/cdef_coverage/analyze" =>
    { "authorization_boundary_id" => "" },
  "POST /api/v1/cdef_coverage/runs" =>
    { "authorization_boundary_id" => "" }
}.freeze

def request_body(route)
  return nil unless %w[POST PUT PATCH].any? { |m| route[:method].include?(m) }

  explicit = UNPERMITTED_BODIES[route_keys(route).first]
  return explicit if explicit

  root, fields = permitted_fields(route[:controller])
  return nil if root.nil? || fields.empty?

  { root => fields.to_h { |f| [ f, "" ] } }
end

def build_request(route)
  segments = route[:path].sub(%r{\A/}, "").split("/").map do |segment|
    next segment unless segment.start_with?(":")

    name = segment.delete_prefix(":")
    variable = ID_VARIABLES[route[:controller]] if name == "id"
    variable ||= name.sub(/_id\z/, "_id")
    "{{#{variable}}}"
  end

  method = route[:method].split("/").first
  body   = request_body(route)

  request = {
    "method" => method,
    "header" => [ { "key" => "Authorization", "value" => "Bearer {{auth_token}}" } ],
    "url" => {
      "raw"  => "{{base_url}}/#{segments.join('/')}",
      "host" => [ "{{base_url}}" ],
      "path" => segments
    },
    "description" => "`#{route[:controller]}##{route[:action]}`. Generated by " \
                     "bin/api_postman_check.rb from the route table and the controller's " \
                     "own permitted-field list."
  }

  if body
    request["header"] << { "key" => CONTENT_TYPE_HEADER, "value" => JSON_CONTENT_TYPE }
    request["body"] = { "mode" => "raw", "raw" => JSON.pretty_generate(body),
                        "options" => { "raw" => { "language" => "json" } } }
  end

  { "name" => "#{method} #{route[:action].tr('_', ' ')}", "request" => request }
end

def folder_for(collection, name)
  found = collection["item"].find { |item| item["name"] == name && item["item"] }
  return found if found

  created = { "name" => name, "item" => [] }
  collection["item"] << created
  created
end

routes     = load_routes
collection = load_collection
covered    = covered_keys(collection)

missing = routes.reject { |route| route_keys(route).any? { |key| covered.include?(key) } }

# A write request with no body documents nothing. Some genuinely take none —
# `approve`, `archive`, `submit_for_review` are state transitions — so a body is
# only filled in where the controller declares a permitted-field list.
def backfill_bodies(collection, routes)
  by_key = {}
  routes.each { |route| route_keys(route).each { |key| by_key[key] = route } }

  filled = 0
  each_request(collection["item"]) do |_folder, item|
    request = item["request"]
    next unless %w[POST PUT PATCH].include?(request["method"])
    next if (request["body"] || {})["raw"].to_s != ""
    next if request.dig("body", "mode") == "formdata"

    segments = request.dig("url", "path") || []
    key = "#{request['method']} " + normalize("/" + segments.map { |s| s.gsub(POSTMAN_VARIABLE, ":id") }.join("/"))
    route = by_key[key]
    next unless route

    body = request_body(route)
    next unless body

    request["header"] ||= []
    unless request["header"].any? { |h| h["key"] == CONTENT_TYPE_HEADER }
      request["header"] << { "key" => CONTENT_TYPE_HEADER, "value" => JSON_CONTENT_TYPE }
    end
    request["body"] = { "mode" => "raw", "raw" => JSON.pretty_generate(body),
                        "options" => { "raw" => { "language" => "json" } } }
    filled += 1
  end
  filled
end

if ARGV.include?("--write")
  missing.each do |route|
    folder = folder_for(collection, CONTROLLER_TO_FOLDER[route[:controller]] || route[:controller].split("/").last.split("_").map(&:capitalize).join(" "))
    folder["item"] << build_request(route)
  end

  dual = add_dual_mode_variants(collection)
  warn "Added #{dual} multipart/raw-body twin(s)" if dual.positive?

  filled = backfill_bodies(collection, routes)
  warn "Filled #{filled} empty request body/bodies from controller permit lists" if filled.positive?

  collection["item"].sort_by! { |item| item["name"].to_s }
  collection["info"]["description"] =
    "Complete API collection for SPARC (Systematic Policy and Regulatory Compliance). " \
    "#{routes.size} endpoints across #{collection['item'].count { |i| i['item'] }} folders " \
    "covering OSCAL document lifecycle, FedRAMP 20x KSI management, federation, and platform " \
    "administration. Reconciled against the route table by bin/api_postman_check.rb."

  File.write(COLLECTION, JSON.pretty_generate(collection) + "\n")
  warn "Added #{missing.size} request(s); collection now covers #{routes.size} endpoints"
else
  puts "Surface: #{routes.size} endpoints"
  puts "Covered: #{routes.size - missing.size}"
  puts "Missing: #{missing.size}"
  missing.group_by { |r| r[:controller] }.sort_by { |_c, rs| -rs.size }.each do |controller, rs|
    puts "  #{controller} (#{rs.size})"
    rs.each { |r| puts "    #{r[:method]} #{r[:path]}" }
  end
end

exit 1 if ARGV.include?("--check") && missing.any?
