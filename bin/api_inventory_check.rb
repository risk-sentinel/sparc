#!/usr/bin/env ruby
# frozen_string_literal: true

# Regenerates docs/api/INVENTORY.md from four authoritative inputs:
#   - bin/rails routes  (filtered to /api/v1/)
#   - docs/api/endpoints/*.md  (per-endpoint markdown)
#   - docs/api/sparc-api.postman_collection.json  (Postman collection)
#   - tests/api/test_*.py  (the pytest endpoint suite)
#
# Usage (from repo root):
#   bin/api_inventory_check.rb            # writes summary + inventory body to stdout
#   bin/api_inventory_check.rb --write    # splices both into docs/api/INVENTORY.md
#   bin/api_inventory_check.rb --check    # exits 1 if MISSING rows exist
#
# This is the script behind the procedure documented in
# docs/api/SPARC-API-Review-and-Automated-Testing-Procedure.md
# Re-running it on any commit detects drift between code and docs.
#
# #995 — the summary block used to be hand-written prose and drifted 66
# endpoints behind the table it introduced (it claimed 142 logical endpoints
# while the routes carried 208), so every percentage it published was computed
# against the wrong denominator and read as near-complete. The summary is now
# generated from the same pass that generates the table and spliced between
# markers, so the two cannot disagree.

require "json"
require "set"
require "date"

REPO_ROOT = File.expand_path("..", __dir__)
DOCS_DIR  = File.join(REPO_ROOT, "docs/api/endpoints")
POSTMAN   = File.join(REPO_ROOT, "docs/api/sparc-api.postman_collection.json")
PYTESTS   = File.join(REPO_ROOT, "tests/api")
INVENTORY = File.join(REPO_ROOT, "docs/api/INVENTORY.md")

SUMMARY_BEGIN = "<!-- BEGIN GENERATED SUMMARY -->"
SUMMARY_END   = "<!-- END GENERATED SUMMARY -->"
GAPS_BEGIN    = "<!-- BEGIN GENERATED GAPS -->"
GAPS_END      = "<!-- END GENERATED GAPS -->"
TABLE_BEGIN   = "<!-- BEGIN GENERATED INVENTORY -->"
TABLE_END     = "<!-- END GENERATED INVENTORY -->"

# Doc pages are resolved by SEARCHING EVERY PAGE FOR THE ROUTE PATH, not by a
# controller -> file map. The map was the drift mechanism: a controller absent
# from it rendered "NO (no doc file)" however well documented it was, and 27
# rows across five controllers (catalog_controls, ssp_components, poam_risks,
# control_families, cdef_coverage) reported as undocumented while carrying a
# convention-named page. It also could not express a page that documents
# several controllers — field-import.md documents the same two actions on four
# document types, and all eight rows reported MISSING because the script only
# ever looked in the controller's own file.
#
# Searching by path is also STRICTER than what it replaces: the old matcher
# accepted a bare mention of the action name anywhere in the mapped file, so
# the word "promote" in prose marked promote# documented.

# Test modules are resolved by convention first — controller `foo_bar` ->
# `test_foo_bar.py`, `admin/credentials` -> `test_admin_credentials.py` — so a
# new controller with a conventionally-named module is picked up with no edit
# here. Only genuine departures from the convention are listed.
TEST_MODULE_EXCEPTIONS = {
  # One API surface, one module: TestControlLinks lives in test_evidences.py.
  "evidence_control_links"             => "test_evidences.py",
  # Nested under boundaries in the routes, named for the resource in the suite.
  "authorization_boundary_memberships" => "test_boundary_memberships.py",
  # Nested collections covered inside their parent's module.
  "control_mapping_entries"            => "test_control_mappings.py",
  "attester_eligibility"               => "test_attestations.py",
  # #1010/#1011 — one module per SHAPE rather than per controller. The six
  # POA&M sub-objects are one contract, and converter entries are tested
  # alongside the converter they belong to.
  "converter_entries"                  => "test_converters.py",
  "poam_items"                         => "test_poam_subresources.py",
  "poam_observations"                  => "test_poam_subresources.py",
  "poam_findings"                      => "test_poam_subresources.py",
  "poam_local_components"              => "test_poam_subresources.py",
  "poam_remediations"                  => "test_poam_subresources.py",
  "poam_milestones"                    => "test_poam_subresources.py"
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
  by_key = rows.group_by { |r| [ r[:path], r[:controller], r[:action] ] }
  by_key.map do |(path, ctrl, act), entries|
    methods = entries.map { |e| e[:method] }.uniq.sort
    method  = (methods.sort == %w[PATCH PUT]) ? "PATCH/PUT" : methods.join("/")
    { method: method, path: path, controller: ctrl, action: act }
  end
end

def load_doc_text
  Dir.glob("#{DOCS_DIR}/*.md").to_h { |f| [ File.basename(f, ".md"), File.read(f) ] }
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

# Parse a doc page's `## Endpoints` overview table into the (method, path)
# pairs that page PUBLISHES. Crediting a route only when the page actually
# lists it is the point: the matcher this replaces accepted the action name
# appearing anywhere in the mapped file, so the word "promote" in a sentence
# marked `promote#` documented. Paths written relative to the page's
# `## Base URL` (`…/controls/:identifier`) are resolved against it.
# A page declares its base path as a `## Base URL` code block, as a
# `| **Base path** | ... |` table row, or not at all — in which case the first
# absolute path on the page stands in.
def doc_base_path(text)
  raw = [
    text[/^## Base URL\s*\n+```\n(.+?)\n```/m, 1],
    text[/\*\*Base (?:URL|path)\*\*\s*\|\s*`([^`]+)`/, 1],
    text[%r{(/api/v1/[A-Za-z0-9_:./-]+)}, 1]
  ].compact.first.to_s.strip

  raw.sub(%r{\Ahttps?://[^/]+}, "").sub(%r{/\z}, "")
end

def parse_doc_endpoints(text)
  base_path = doc_base_path(text)
  # `…/parameters/export` elides everything up to but NOT including the base's
  # final segment — the doc repeats the resource name for readability. Both
  # readings are offered, since a page is free to write `…/:id` meaning the
  # base plus an id, and a presence check within one page's own base URL is
  # not made meaningfully looser by accepting either.
  prefixes = [ base_path.sub(%r{/[^/]+\z}, ""), base_path ].uniq

  text.each_line.flat_map do |line|
    m = line.match(/^\|\s*`?([A-Z]+(?:`?\s*\/\s*`?[A-Z]+)?)`?\s*\|\s*`([^`]+)`/)
    next [] unless m

    methods = m[1].scan(/[A-Z]+/)
    next [] unless methods.all? { |v| %w[GET POST PUT PATCH DELETE].include?(v) }

    written = m[2].strip
    paths   = if written.start_with?("/api/")
      [ written ]
    elsif written.match?(/\A(?:…|\.\.\.)/)
      rem = written.sub(/\A(?:…|\.\.\.)/, "")
      prefixes.map { |pre| "#{pre}#{rem}" }
    else
      []
    end

    paths.flat_map { |path| methods.map { |v| "#{v} #{normalize_id_segments(path)}" } }
  end.to_set
end

# Three states, not two. A route listed in a page's Endpoints table is
# published; one that only appears somewhere in the prose is mentioned, which
# is not the same thing and should not be counted as though it were.
def doc_status(route, doc_endpoints, doc_text)
  methods = route[:method].split("/")
  norm    = normalize_id_segments(route[:path])

  page = doc_endpoints.find { |_name, set| methods.any? { |m| set.include?("#{m} #{norm}") } }
  return "[`#{page[0]}.md`](endpoints/#{page[0]}.md)" if page

  slug_path = route[:path].gsub(":id", ":slug")
  prose = doc_text.find { |_name, text| text.include?(route[:path]) || text.include?(slug_path) }
  return "prose only — [`#{prose[0]}.md`](endpoints/#{prose[0]}.md)" if prose

  "**MISSING**"
end

def postman_status(route, postman_set)
  methods = route[:method].split("/")
  norm_path = normalize_id_segments(route[:path])
  methods.any? { |m| postman_set.include?("#{m} #{norm_path}") } ? "yes" : "**MISSING**"
end

# The pytest column measures MODULE PRESENCE, not verification. For generic
# CRUD actions it means only that a module for the controller exists; for the
# rest it means the action name appears somewhere in that module's text —
# including in a comment or a path string. It is a coverage-shaped signal, and
# #995 exists because a coverage-shaped signal is not evidence an endpoint does
# what its documentation claims. Read this column as "there is somewhere for a
# real check to live", never as "the endpoint is verified".
GENERIC_ACTIONS = %w[index show create update destroy].freeze

def test_module_for(controller)
  TEST_MODULE_EXCEPTIONS[controller] || "test_#{controller.tr('/', '_')}.py"
end

def load_pytest_module_texts(routes)
  return {} unless Dir.exist?(PYTESTS)

  routes.map { |r| r[:controller] }.uniq.to_h do |ctrl|
    path = File.join(PYTESTS, test_module_for(ctrl))
    [ ctrl, File.exist?(path) ? File.read(path) : nil ]
  end
end

def pytest_status(route, pytest_module_texts)
  return "_n/a (suite not present)_" if pytest_module_texts.empty?

  text = pytest_module_texts[route[:controller]]
  return "**MISSING**" unless text  # no module for this controller

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

def pct(part, whole)
  whole.zero? ? "0%" : "#{((part.to_f / whole) * 100).round}%"
end

routes              = load_routes.sort_by { |r| [ r[:controller], r[:path], r[:method] ] }
doc_text            = load_doc_text
doc_endpoints       = doc_text.transform_values { |t| parse_doc_endpoints(t) }
postman_set         = load_postman_endpoints
pytest_module_texts = load_pytest_module_texts(routes)

rows = routes.map do |r|
  { route: r,
    doc: doc_status(r, doc_endpoints, doc_text),
    postman: postman_status(r, postman_set),
    pytest: pytest_status(r, pytest_module_texts) }
end

total       = rows.size
published   = rows.count { |r| r[:doc].start_with?("[`") }
prose_only = rows.count { |r| r[:doc].start_with?("prose only") }
in_postman  = rows.count { |r| r[:postman] == "yes" }
in_pytest   = rows.count { |r| r[:pytest] == "yes" }
controllers = routes.map { |r| r[:controller] }.uniq.size
verbs       = routes.flat_map { |r| r[:method].split("/") }.tally.sort_by { |_v, n| -n }

summary = +""
summary << "## Summary\n\n"
summary << "<!-- Generated by bin/api_inventory_check.rb — do not hand-edit. -->\n\n"
summary << "- **Generated:** #{Date.today.iso8601} from `bin/rails routes` on this commit\n"
summary << "- **Code:** **#{total} logical endpoints** across #{controllers} controller groups " \
           "(PATCH+PUT aliases collapsed) — #{verbs.map { |v, n| "#{n} #{v}" }.join(', ')}\n"
summary << "- **Documentation:** **#{published} / #{total}** endpoints are listed in an " \
           "`endpoints/*.md` page's own Endpoints table (**#{pct(published, total)}**); " \
           "#{prose_only} more are mentioned only in prose\n"
summary << "- **Postman collection:** **#{in_postman} / #{total}** endpoints covered " \
           "(**#{pct(in_postman, total)}**)\n"
summary << "- **Pytest suite:** **#{in_pytest} / #{total}** endpoints map to a " \
           "`tests/api/test_*.py` module (**#{pct(in_pytest, total)}**)\n\n"
summary << "> **The pytest column counts module presence, not verification.** For generic CRUD\n"
summary << "> actions it means only that a module for the controller exists; for the rest it means\n"
summary << "> the action name appears somewhere in that module's text. It is a coverage-shaped\n"
summary << "> signal, and [#995](https://github.com/risk-sentinel/sparc/issues/995) exists because a\n"
summary << "> coverage-shaped signal is not evidence that an endpoint does what its documentation\n"
summary << "> claims. Read it as \"there is somewhere for a real check to live\".\n"

# The gaps used to be a hand-maintained "Known gaps (4 rows)" list. It was
# four rows against a table that carried nineteen undocumented endpoints, for
# the same reason the summary was 66 endpoints stale: it was prose next to
# generated data. It is generated now.
def group_of(route)
  route[:controller]
end

undocumented = rows.select { |r| r[:doc] == "**MISSING**" }
prose_rows   = rows.select { |r| r[:doc].start_with?("prose only") }
no_module    = rows.select { |r| r[:pytest] == "**MISSING**" }
no_postman   = rows.select { |r| r[:postman] == "**MISSING**" }

gaps = +""
gaps << "### Documented nowhere — #{undocumented.size} endpoints\n\n"
gaps << "No `endpoints/*.md` page lists these paths, and none mentions them in prose.\n\n"
gaps << "| Method | Path | Controller#action |\n|---|---|---|\n"
undocumented.each do |r|
  gaps << "| `#{r[:route][:method]}` | `#{r[:route][:path]}` | `#{r[:route][:controller]}##{r[:route][:action]}` |\n"
end

gaps << "\n### Mentioned in prose but not published — #{prose_rows.size} endpoints\n\n"
gaps << "A page discusses these paths without listing them in its own Endpoints table, so a reader\n"
gaps << "working from the tables will not find them.\n\n"
gaps << "| Method | Path | Page |\n|---|---|---|\n"
prose_rows.each do |r|
  gaps << "| `#{r[:route][:method]}` | `#{r[:route][:path]}` | #{r[:doc].sub('prose only — ', '')} |\n"
end

gaps << "\n### No pytest module — #{no_module.size} endpoints across " \
        "#{no_module.map { |r| group_of(r[:route]) }.uniq.size} controllers\n\n"
gaps << "| Controller | Endpoints | Module looked for |\n|---|---|---|\n"
no_module.group_by { |r| group_of(r[:route]) }.sort_by { |c, rs| [ -rs.size, c ] }.each do |ctrl, rs|
  gaps << "| `#{ctrl}` | #{rs.size} | `tests/api/#{test_module_for(ctrl)}` |\n"
end

gaps << "\n### Not in the Postman collection — #{no_postman.size} endpoints\n\n"
gaps << "| Controller | Endpoints |\n|---|---|\n"
no_postman.group_by { |r| group_of(r[:route]) }.sort_by { |c, rs| [ -rs.size, c ] }.each do |ctrl, rs|
  gaps << "| `#{ctrl}` | #{rs.size} |\n"
end

table = +""
table << "| Method | Path | Controller#action | In `endpoints/*.md` | In Postman collection | Covered by pytest |\n"
table << "|--------|------|-------------------|---------------------|------------------------|-------------------|\n"
rows.each do |r|
  table << "| `#{r[:route][:method]}` | `#{r[:route][:path]}` | " \
           "`#{r[:route][:controller]}##{r[:route][:action]}` | " \
           "#{r[:doc]} | #{r[:postman]} | #{r[:pytest]} |\n"
end

# The surface, as data, so a second tool does not have to re-derive it. The
# Postman reconciler consumes this rather than duplicating the route loader —
# two scripts computing "the endpoints" independently is how they end up
# disagreeing about how many there are.
if ARGV.include?("--routes-json")
  puts JSON.pretty_generate(routes.map { |r|
    { method: r[:method], path: r[:path], controller: r[:controller], action: r[:action] }
  })
  exit 0
end

if ARGV.include?("--write")
  original = File.read(INVENTORY)
  updated  = original.dup
  { [ SUMMARY_BEGIN, SUMMARY_END ] => summary,
    [ GAPS_BEGIN, GAPS_END ]       => gaps,
    [ TABLE_BEGIN, TABLE_END ]     => table }.each do |(b, e), body|
    unless updated.include?(b) && updated.include?(e)
      abort "#{INVENTORY} is missing the #{b} / #{e} markers — add them before using --write"
    end
    updated.sub!(/#{Regexp.escape(b)}.*?#{Regexp.escape(e)}/m, "#{b}\n\n#{body}\n#{e}")
  end
  File.write(INVENTORY, updated)
  warn "Wrote #{total} rows to docs/api/INVENTORY.md"
else
  puts summary
  puts
  puts gaps
  puts
  puts table
end

if ARGV.include?("--check")
  doc_gaps = rows.count { |r| r[:doc] == "**MISSING**" }
  pm_gaps  = rows.count { |r| r[:postman] == "**MISSING**" }
  py_gaps  = rows.count { |r| r[:pytest] == "**MISSING**" }
  total_gaps = doc_gaps + pm_gaps + py_gaps
  if total_gaps.positive?
    warn "Inventory drift: #{doc_gaps} undocumented endpoint(s), " \
         "#{pm_gaps} missing Postman entry/entries, " \
         "#{py_gaps} endpoint(s) with no pytest coverage"
    exit 1
  end
end
