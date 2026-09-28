#!/usr/bin/env ruby
# frozen_string_literal: true

# #1115 / #1172 — has FedRAMP moved on from the KSI snapshot SPARC vendors?
#
#   bin/ksi_upstream_diff.rb                    # compare against FedRAMP/rules main
#   bin/ksi_upstream_diff.rb --ref <sha|branch> # ...or another ref
#   bin/ksi_upstream_diff.rb --upstream FILE    # ...or a file already on disk (no network)
#
# The importer reads only the vendored copy (lib/data/fedramp); it never
# fetches. This is the other half: it fetches upstream and reports what a
# re-vendor would change — the version, themes and indicators added or removed,
# and per indicator its name, statement and NIST `controls[]` — so drift is
# found by running a tool rather than by a customer.
#
# Exit status:
#   0  no drift — upstream's KSI section matches the vendored snapshot
#   1  drift — the report says what changed
#   2  could not compare (fetch failed, file unreadable, not FedRAMP's shape)
#
# FAILS CLOSED: a comparison that did not happen is exit 2, never a pass.
#
# An indicator upstream REMOVES is retired by the next import, keeping its
# validations. An indicator that was RENAMED shows here as one removal plus one
# addition; if the two are the same requirement, add a `rename_to` row to
# lib/data/fedramp/ksi_legacy_map.yml before re-vendoring, so that
# assessments move with the row instead of being left on a retired one.
#
# NIST SP 800-53 Rev 5: CM-3 (change to an external baseline is detected
# before it is applied), SA-9 / SR-3 (external source monitored), CA-7.
require "json"
require "net/http"
require "optparse"
require "uri"

REPO_ROOT = File.expand_path("..", __dir__)
VENDORED  = File.join(REPO_ROOT, "lib/data/fedramp/fedramp-consolidated-rules.json")
RAW_URL   = "https://raw.githubusercontent.com/FedRAMP/rules/%s/fedramp-consolidated-rules.json"

def fail_closed(message)
  warn "ksi_upstream_diff: #{message}"
  exit 2
end

def fetch(ref)
  uri = URI(format(RAW_URL, ref))
  response = Net::HTTP.start(uri.host, uri.port, use_ssl: true, open_timeout: 15, read_timeout: 60) do |http|
    http.request(Net::HTTP::Get.new(uri))
  end
  fail_closed("GET #{uri} answered #{response.code}") unless response.is_a?(Net::HTTPSuccess)
  response.body
rescue SocketError, SystemCallError, Net::OpenTimeout, Net::ReadTimeout, OpenSSL::SSL::SSLError => e
  fail_closed("could not fetch #{uri}: #{e.class}: #{e.message}")
end

def parse(text, label)
  data = JSON.parse(text)
  fail_closed("#{label} has no KSI section — not FedRAMP's consolidated rules") unless data.is_a?(Hash) && data["KSI"].is_a?(Hash)
  data
rescue JSON::ParserError => e
  fail_closed("#{label} is not JSON: #{e.message}")
end

# { "KSI-IAM-ELP" => { theme:, name:, statement:, controls: } }
def indicators(data)
  data["KSI"].each_with_object({}) do |(theme, body), acc|
    (body["indicators"] || {}).each do |id, ind|
      acc[id] = { theme: theme, name: ind["name"], statement: ind["statement"] || ind["varies_by_class"],
                  controls: Array(ind["controls"]).sort, updated: Array(ind["updated"]).last }
    end
  end
end

def compare(vendored, upstream)
  lines = []
  v_ver = vendored.dig("info", "version")
  u_ver = upstream.dig("info", "version")
  lines << "version: #{v_ver} -> #{u_ver}" if v_ver != u_ver

  v_themes = vendored["KSI"].transform_values { |t| t["name"] }
  u_themes = upstream["KSI"].transform_values { |t| t["name"] }
  (u_themes.keys - v_themes.keys).sort.each { |k| lines << "theme added:   #{k} #{u_themes[k]}" }
  (v_themes.keys - u_themes.keys).sort.each { |k| lines << "theme removed: #{k} #{v_themes[k]}" }
  (v_themes.keys & u_themes.keys).sort.each do |k|
    lines << "theme renamed: #{k} #{v_themes[k].inspect} -> #{u_themes[k].inspect}" if v_themes[k] != u_themes[k]
  end

  v_ind = indicators(vendored)
  u_ind = indicators(upstream)
  (u_ind.keys - v_ind.keys).sort.each { |k| lines << "indicator added:   #{k} #{u_ind[k][:name]}" }
  (v_ind.keys - u_ind.keys).sort.each { |k| lines << "indicator removed: #{k} #{v_ind[k][:name]}" }
  (v_ind.keys & u_ind.keys).sort.each do |k|
    a = v_ind[k]
    b = u_ind[k]
    changed = []
    changed << "theme #{a[:theme]} -> #{b[:theme]}" if a[:theme] != b[:theme]
    changed << "name #{a[:name].inspect} -> #{b[:name].inspect}" if a[:name] != b[:name]
    changed << "statement changed" if a[:statement] != b[:statement]
    added = b[:controls] - a[:controls]
    removed = a[:controls] - b[:controls]
    changed << "controls +#{added.join(',')}" if added.any?
    changed << "controls -#{removed.join(',')}" if removed.any?
    next if changed.empty?

    note = b[:updated] ? "  (upstream: #{b[:updated]['date']} #{b[:updated]['comment']})" : ""
    lines << "indicator changed: #{k} — #{changed.join('; ')}#{note}"
  end
  lines
end

if $PROGRAM_NAME == __FILE__
  options = { ref: "main", vendored: VENDORED }
  OptionParser.new do |o|
    o.banner = "Usage: bin/ksi_upstream_diff.rb [--ref REF | --upstream FILE] [--vendored FILE]"
    o.on("--ref REF", "FedRAMP/rules ref to compare against (default main)") { |v| options[:ref] = v }
    o.on("--upstream FILE", "compare against a local file instead of fetching") { |v| options[:upstream] = v }
    o.on("--vendored FILE", "the vendored snapshot (default lib/data/fedramp)") { |v| options[:vendored] = v }
  end.parse!

  vendored_text = begin
    File.read(options[:vendored])
  rescue SystemCallError => e
    fail_closed("cannot read the vendored snapshot: #{e.message}")
  end
  upstream_text = if options[:upstream]
    begin
      File.read(options[:upstream])
    rescue SystemCallError => e
      fail_closed("cannot read #{options[:upstream]}: #{e.message}")
    end
  else
    fetch(options[:ref])
  end
  source = options[:upstream] || "FedRAMP/rules@#{options[:ref]}"

  drift = compare(parse(vendored_text, "the vendored snapshot"), parse(upstream_text, source))
  if drift.empty?
    puts "No KSI drift: #{source} matches the vendored snapshot."
    exit 0
  end

  puts "KSI drift — #{source} differs from the vendored snapshot:"
  drift.each { |line| puts "  #{line}" }
  puts ""
  puts "To take it: re-vendor per lib/data/fedramp/fedramp-consolidated-rules.provenance.json (re_vendor),"
  puts "review lib/data/fedramp/ksi_legacy_map.yml for renames, then bin/rails 'ksi:import[true]' to preview."
  exit 1
end
