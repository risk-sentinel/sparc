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
  "back_matter_resources"    => "back-matter-resources"
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
        norm   = parts.map { |p| p.gsub(/\{\{[^}]+\}\}/, ":id") }
        set << "#{method} /#{norm.join('/')}"
      end
    end
  }
  walk.call(collection["item"])
  set
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
  methods.any? { |m| postman_set.include?("#{m} #{route[:path]}") } ? "yes" : "**MISSING**"
end

routes      = load_routes.sort_by { |r| [r[:controller], r[:path], r[:method]] }
doc_text    = load_doc_text
postman_set = load_postman_endpoints

puts "| Method | Path | Controller#action | In `endpoints/*.md` | In Postman collection |"
puts "|--------|------|-------------------|---------------------|------------------------|"

stats = Hash.new(0)
routes.each do |r|
  d = doc_status(r, doc_text)
  p = postman_status(r, postman_set)
  stats["doc_#{d}"] += 1
  stats["pm_#{p}"]  += 1
  puts "| `#{r[:method]}` | `#{r[:path]}` | `#{r[:controller]}##{r[:action]}` | #{d} | #{p} |"
end

if ARGV.include?("--check")
  doc_gaps = stats["doc_**MISSING**"] + stats["doc_NO (no doc file)"]
  pm_gaps  = stats["pm_**MISSING**"]
  if doc_gaps.positive? || pm_gaps.positive?
    warn "Inventory drift: #{doc_gaps} undocumented endpoint(s), #{pm_gaps} missing Postman entry/entries"
    exit 1
  end
end
