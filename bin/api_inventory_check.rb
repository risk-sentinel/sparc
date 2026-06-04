#!/usr/bin/env ruby
# frozen_string_literal: true

# Regenerates docs/api/INVENTORY.md from three authoritative inputs:
#   - bin/rails routes  (filtered to /api/v1/)
#   - docs/api/endpoints/*.md  (per-endpoint markdown)
#   - docs/api/sparc-api.postman_collection.json  (Postman collection)
#
# Usage (from repo root):
#   bin/api_inventory_check.rb            # writes inventory body to stdout
#   bin/api_inventory_check.rb --check    # exits 1 if MISSING/NO rows exist
#
# This is the script behind the procedure documented in
# docs/api/SPARC-API-Review-and-Automated-Testing-Procedure.md
# Re-running it on any commit detects drift between code and docs.

require "json"
require "set"

REPO_ROOT = File.expand_path("..", __dir__)
DOCS_DIR  = File.join(REPO_ROOT, "docs/api/endpoints")
POSTMAN   = File.join(REPO_ROOT, "docs/api/sparc-api.postman_collection.json")
PYTESTS   = File.join(REPO_ROOT, "tests/api")

# Map of controller key (the `controller` part of `controller#action`)
# to the doc file basename under docs/api/endpoints/.
# Controllers absent from this map render as "NO (no doc file)".
CONTROLLER_TO_DOC = {
  "ssp_documents"            => "ssp-documents",
  "sar_documents"            => "sar-documents",
  "sap_documents"            => "sap-documents",
  "poam_documents"           => "poam-documents",
  "cdef_documents"           => "cdef-documents",
  "profile_documents"        => "profile-documents",
  "control_catalogs"         => "control-catalogs",
  "control_mappings"         => "control-mappings",
  "baseline_parameters"      => "baseline-parameters",
  "ksi_catalog"              => "ksi-catalog",
  "ksi_validations"          => "ksi-validations",
  "discovery"                => "discovery",
  "users"                    => "users",
  "authorization_boundaries" => "authorization-boundaries",
  "back_matter_resources"    => "back-matter-resources",
  "admin/credentials"        => "admin-credentials",
  "authoritative_sources"    => "authoritative-sources",
  "federation_peers"         => "federation-peers",
  "translations"             => "translations",
  "sessions"                 => "sessions",
  "attestations"             => "attestations"
}.freeze

def load_routes
  raw = `bin/rails routes 2>/dev/null`
  raise "bin/rails routes failed" if raw.empty?

  rows = []
  raw.each_line do |line|
    parts = line.strip.split(/\s+/)
    method = parts.find { |p| %w[GET POST PUT PATCH DELETE].include?(p) }
    path   = parts.find { |p| p.start_with?("/api/") }
    action = parts.find { |p| p.include?("#") && !p.start_with?("/") }
    next unless method && path && action

    path = path.sub(/\(\.\:format\)/, "")
    next unless path.start_with?("/api/")

    ctrl, act = action.sub("api/v1/", "").split("#")
    rows << { method: method, path: path, controller: ctrl, action: act }
  end

  # Collapse PATCH/PUT pairs that share the same path + action.
  by_key = rows.group_by { |r| [r[:path], r[:controller], r[:action]] }
  by_key.map do |(path, ctrl, act), entries|
    methods = entries.map { |e| e[:method] }.uniq.sort
    method  = (methods.sort == %w[PATCH PUT]) ? "PATCH/PUT" : methods.join("/")
    { method: method, path: path, controller: ctrl, action: act }
  end
end

def load_doc_text
  Dir.glob("#{DOCS_DIR}/*.md").to_h { |f| [File.basename(f, ".md"), File.read(f)] }
end

def load_postman_endpoints
  set = Set.new
  collection = JSON.parse(File.read(POSTMAN))
  walk = ->(items) {
    items.each do |it|
      if it["item"]
        walk.call(it["item"])
      elsif it["request"]
        method = it["request"]["method"]
        parts  = it.dig("request", "url", "path") || []
        # Postman uses {{var}} for path-vars; rails routes use :id and
        # :nested_resource_id. Normalize both sides to a generic ":id"
        # marker so nested-resource paths match regardless of which
        # specific id-name appears.
        norm = parts.map { |p| p.gsub(/\{\{[^}]+\}\}/, ":id") }
        set << "#{method} /#{norm.join('/')}"
      end
    end
  }
  walk.call(collection["item"])
  set
end

# Normalize a route path's id-style segments to ":id" so the postman
# matcher does not need to know each nested-resource's specific param
# name. (Rails generates :authorization_boundary_id for nested
# resources; postman uses {{boundary_id}} or similar — both collapse
# here to ":id".)
def normalize_id_segments(path)
  path.gsub(%r{/:[a-z_]+}, "/:id")
end

def doc_status(route, doc_text)
  doc_key = CONTROLLER_TO_DOC[route[:controller]]
  return "NO (no doc file)" if doc_key.nil?

  text      = doc_text[doc_key] || ""
  slug_path = route[:path].gsub(":id", ":slug")
  if text.include?(route[:path]) || text.include?(slug_path) ||
     text =~ /\b#{Regexp.escape(route[:action])}\b/i
    "yes"
  else
    "**MISSING**"
  end
end

def postman_status(route, postman_set)
  methods = route[:method].split("/")
  norm_path = normalize_id_segments(route[:path])
  methods.any? { |m| postman_set.include?("#{m} #{norm_path}") } ? "yes" : "**MISSING**"
end

# For each test_<controller>.py module under tests/api/, build a map of
# controller -> file content. Pytest coverage is granular per route: an
# endpoint is "covered" when its action name appears in the test module
# for its controller (action names are unique within a controller and
# the test classes/functions reference them, e.g. TestPromotion,
# test_admin_destroys_resource, /:id/promote). Falls back to "module
# exists" when an action name is generic enough to false-negative
# (index, show, create, update, destroy).
GENERIC_ACTIONS = %w[index show create update destroy].freeze

CONTROLLER_TO_TEST_MODULE = {
  "ssp_documents"            => "test_ssp_documents.py",
  "sar_documents"            => "test_sar_documents.py",
  "sap_documents"            => "test_sap_documents.py",
  "poam_documents"           => "test_poam_documents.py",
  "cdef_documents"           => "test_cdef_documents.py",
  "profile_documents"        => "test_profile_documents.py",
  "control_catalogs"         => "test_control_catalogs.py",
  "control_mappings"         => "test_control_mappings.py",
  "baseline_parameters"      => "test_baseline_parameters.py",
  "ksi_catalog"              => "test_ksi_catalog.py",
  "ksi_validations"          => "test_ksi_validations.py",
  "discovery"                => "test_discovery.py",
  "users"                    => "test_users.py",
  "authorization_boundaries" => "test_authorization_boundaries.py",
  "back_matter_resources"    => "test_back_matter_resources.py",
  "admin/credentials"        => "test_admin_credentials.py",
  "authoritative_sources"    => "test_authoritative_sources.py",
  "federation_peers"         => "test_federation_peers.py",
  "translations"             => "test_translations.py",
  "sessions"                 => "test_sessions.py",
  "attestations"             => "test_attestations.py"
}.freeze

def load_pytest_module_texts
  return {} unless Dir.exist?(PYTESTS)

  CONTROLLER_TO_TEST_MODULE.each_with_object({}) do |(ctrl, fname), h|
    path = File.join(PYTESTS, fname)
    h[ctrl] = File.exist?(path) ? File.read(path) : nil
  end
end

def pytest_status(route, pytest_module_texts)
  return "_n/a (suite not present)_" if pytest_module_texts.empty?

  text = pytest_module_texts[route[:controller]]
  return "**MISSING**" unless text  # no module for this controller

  # For non-generic actions, require the action name to appear in the
  # module text. For generic CRUD actions, the module's mere existence
  # is sufficient — the conftest fixtures + standard test classes
  # exercise them.
  if GENERIC_ACTIONS.include?(route[:action])
    "yes"
  elsif text.downcase.include?(route[:action].downcase)
    # Action name appears verbatim somewhere — test class, function
    # name, comment, or path string.
    "yes"
  elsif text.downcase.include?(route[:action].tr('_', '').downcase)
    # CamelCase form: show_indicator -> ShowIndicator (test class
    # convention).
    "yes"
  else
    "**MISSING**"
  end
end

routes              = load_routes.sort_by { |r| [r[:controller], r[:path], r[:method]] }
doc_text            = load_doc_text
postman_set         = load_postman_endpoints
pytest_module_texts = load_pytest_module_texts

puts "| Method | Path | Controller#action | In `endpoints/*.md` | In Postman collection | Covered by pytest |"
puts "|--------|------|-------------------|---------------------|------------------------|-------------------|"

stats = Hash.new(0)
routes.each do |r|
  d = doc_status(r, doc_text)
  p = postman_status(r, postman_set)
  t = pytest_status(r, pytest_module_texts)
  stats["doc_#{d}"] += 1
  stats["pm_#{p}"]  += 1
  stats["py_#{t}"]  += 1
  puts "| `#{r[:method]}` | `#{r[:path]}` | `#{r[:controller]}##{r[:action]}` | #{d} | #{p} | #{t} |"
end

if ARGV.include?("--check")
  doc_gaps = stats["doc_**MISSING**"] + stats["doc_NO (no doc file)"]
  pm_gaps  = stats["pm_**MISSING**"]
  py_gaps  = stats["py_**MISSING**"]
  total_gaps = doc_gaps + pm_gaps + py_gaps
  if total_gaps.positive?
    warn "Inventory drift: #{doc_gaps} undocumented endpoint(s), " \
         "#{pm_gaps} missing Postman entry/entries, " \
         "#{py_gaps} endpoint(s) with no pytest coverage"
    exit 1
  end
end
