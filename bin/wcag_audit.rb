#!/usr/bin/env ruby
# frozen_string_literal: true

# Runs pa11y (with the axe-core runner) against a curated list of SPARC
# pages and emits docs/dev/a11y_audit.md with aggregated WCAG 2.1 AA
# findings.
#
# Usage:
#   SPARC_SESSION_COOKIE='<value>' bin/wcag_audit.rb
#
# Env vars:
#   SPARC_SESSION_COOKIE  (required for authenticated pages — the value of
#                          the _ssp_tpr_manager_session cookie)
#   SPARC_BASE_URL        (default: https://sparc.risk-sentinel.org)
#   SPARC_AUDIT_PAGES     (optional comma-separated paths; overrides the
#                          built-in list)
#
# Dependencies: node + npx (pulls pa11y@latest from npm). Uses the system
# Chrome to avoid the Chromium download.

require "cgi"
require "json"
require "tempfile"
require "shellwords"

BASE_URL = ENV.fetch("SPARC_BASE_URL", "https://sparc.risk-sentinel.org").chomp("/")
COOKIE   = ENV["SPARC_SESSION_COOKIE"]
OUTPUT   = File.expand_path("../docs/dev/a11y_audit.md", __dir__)

DEFAULT_PAGES = [
  { path: "/login",              auth: false, label: "Login page (public)" },
  { path: "/",                   auth: true,  label: "Dashboard" },
  { path: "/ssp_documents",      auth: true,  label: "SSP documents index" },
  { path: "/sar_documents",      auth: true,  label: "SAR documents index" },
  { path: "/sap_documents",      auth: true,  label: "SAP documents index" },
  { path: "/poam_documents",     auth: true,  label: "POAM documents index" },
  { path: "/cdef_documents",     auth: true,  label: "CDEF documents index" },
  { path: "/profile_documents",  auth: true,  label: "Profile documents index" },
  { path: "/control_catalogs",   auth: true,  label: "Control catalogs index" },
  { path: "/control_mappings",   auth: true,  label: "Control mappings index" },
  { path: "/converters",         auth: true,  label: "Converters index" },
  { path: "/about",              auth: true,  label: "About / API docs" }
].freeze

PAGES =
  if ENV["SPARC_AUDIT_PAGES"]
    ENV["SPARC_AUDIT_PAGES"].split(",").map do |p|
      path = p.strip
      { path: path, auth: path != "/login", label: path }
    end
  else
    DEFAULT_PAGES
  end

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

abort "Chrome not found at #{CHROME}" unless File.executable?(CHROME)

if PAGES.any? { |p| p[:auth] } && (COOKIE.nil? || COOKIE.empty?)
  abort "SPARC_SESSION_COOKIE not set — required for authenticated pages."
end

def pa11y_config(auth_required:)
  cfg = {
    "runners"  => ["axe"],
    "standard" => "WCAG2AA",
    "timeout"  => 60_000,
    "wait"     => 1500,
    "chromeLaunchConfig" => {
      "executablePath" => CHROME,
      "args" => ["--no-sandbox", "--disable-setuid-sandbox"]
    }
  }
  if auth_required
    # Rails session cookies must be URL-encoded when sent in a Cookie header.
    # Browsers do this automatically; pa11y/Chrome via custom headers does not.
    encoded = CGI.escape(COOKIE)
    cfg["headers"] = { "Cookie" => "_ssp_tpr_manager_session=#{encoded}" }
  end
  cfg
end

def run_pa11y(url, cfg)
  out = nil
  Tempfile.create(["pa11y-cfg-", ".json"]) do |f|
    f.write(JSON.dump(cfg))
    f.flush
    cmd = "npx -y pa11y@latest --config #{Shellwords.escape(f.path)} --reporter json #{Shellwords.escape(url)} 2>/dev/null"
    out = `#{cmd}`
    code = $?.exitstatus
    return { error: "pa11y exited #{code} with no JSON" } if out.strip.empty?
    # pa11y --reporter json emits a bare array of issues at the top level.
    JSON.parse(out)
  end
rescue JSON::ParserError => e
  { error: "pa11y JSON parse error: #{e.message}", raw: out&.slice(0, 200) }
end

def severity_emoji(type)
  case type
  when "error"   then "🔴"
  when "warning" then "🟡"
  when "notice"  then "🔵"
  else "⚪"
  end
end

puts "→ Auditing #{PAGES.size} page(s) against #{BASE_URL}"
puts "  Runner: pa11y + axe-core (WCAG 2.1 AA)"

results = []
PAGES.each_with_index do |p, i|
  url = BASE_URL + p[:path]
  printf "  [%2d/%d] %-30s ", i + 1, PAGES.size, p[:path]
  $stdout.flush
  result = run_pa11y(url, pa11y_config(auth_required: p[:auth]))
  if result.is_a?(Hash) && result[:error]
    puts "ERROR: #{result[:error]}"
    results << { page: p, error: result[:error] }
    next
  end
  issues = Array(result)
  # Demote axe `needsFurtherReview: true` to a separate "review" bucket — axe
  # itself flagged these as uncertain (e.g., glyph antialiasing on heavy-check
  # icons confuses contrast computation). Treating them as hard errors gives
  # an inflated count that doesn't match the human-visible state.
  errors = issues.count { |i_| i_["type"] == "error" && !i_.dig("runnerExtras", "needsFurtherReview") }
  review = issues.count { |i_| i_["type"] == "error" &&  i_.dig("runnerExtras", "needsFurtherReview") }
  warns  = issues.count { |i_| i_["type"] == "warning" }
  notes  = issues.count { |i_| i_["type"] == "notice" }
  puts "#{errors}E / #{review}R / #{warns}W / #{notes}N"
  results << { page: p, issues: issues, errors: errors, review: review, warnings: warns, notices: notes }
end

# Sanity check: did any auth page redirect to /login (cookie invalid)?
auth_results = results.select { |r| r[:page][:auth] && r[:issues] }
if auth_results.any? && auth_results.all? { |r| r[:errors].to_i.zero? && r[:warnings].to_i.zero? && r[:notices].to_i.zero? }
  warn "  ⚠️  All authenticated pages returned zero findings — cookie may be invalid (pa11y followed redirect to /login). Verify SPARC_SESSION_COOKIE."
end

# ── Build markdown ───────────────────────────────────────────────────
out = String.new
out << "# SPARC live WCAG 2.1 AA audit\n\n"
out << "_Generated by `bin/wcag_audit.rb` against `#{BASE_URL}` on #{Time.now.utc.strftime("%Y-%m-%d %H:%M UTC")}._\n\n"
out << "Runner: pa11y + axe-core. Standard: WCAG2AA. Chrome: system install.\n\n"

# Summary table. "review" = axe items flagged needsFurtherReview (not hard fails)
out << "## Summary\n\n"
out << "| Page | URL | 🔴 errors | 🟣 review | 🟡 warn | 🔵 notice |\n"
out << "|---|---|---:|---:|---:|---:|\n"
total_e = total_r = total_w = total_n = 0
results.each do |r|
  next if r[:error]
  out << "| #{r[:page][:label]} | `#{r[:page][:path]}` | #{r[:errors]} | #{r[:review]} | #{r[:warnings]} | #{r[:notices]} |\n"
  total_e += r[:errors]; total_r += r[:review].to_i; total_w += r[:warnings]; total_n += r[:notices]
end
out << "| **Totals** | | **#{total_e}** | **#{total_r}** | **#{total_w}** | **#{total_n}** |\n\n"

# Errored pages
errored = results.select { |r| r[:error] }
if errored.any?
  out << "## Pages that failed to audit\n\n"
  errored.each { |r| out << "- `#{r[:page][:path]}` — #{r[:error]}\n" }
  out << "\n"
end

# Top recurring rules (axe rule IDs)
rule_counts = Hash.new(0)
results.each do |r|
  next if r[:error]
  (r[:issues] || []).each do |i|
    next unless i["type"] == "error"
    next if i.dig("runnerExtras", "needsFurtherReview")
    rid = i["code"].to_s.split(".").last || "unknown"
    rule_counts[rid] += 1
  end
end
if rule_counts.any?
  out << "## Top recurring errors (axe rule IDs)\n\n"
  out << "| Rule | Count |\n|---|---:|\n"
  rule_counts.sort_by { |_, c| -c }.first(15).each do |rid, c|
    out << "| `#{rid}` | #{c} |\n"
  end
  out << "\n"
end

# Per-page detail
out << "## Per-page findings\n\n"
results.each do |r|
  out << "### #{r[:page][:label]} — `#{r[:page][:path]}`\n\n"
  if r[:error]
    out << "_Error: #{r[:error]}_\n\n"
    next
  end
  if (r[:issues] || []).empty?
    out << "_No findings._\n\n"
    next
  end
  by_type = (r[:issues] || []).group_by { |i| i["type"] }
  %w[error warning notice].each do |t|
    next unless by_type[t]
    out << "#### #{severity_emoji(t)} #{t.capitalize}s (#{by_type[t].size})\n\n"
    by_type[t].first(20).each do |i|
      rule = i["code"].to_s.split(".").last
      sel  = (i["selector"] || "").to_s[0, 120]
      msg  = (i["message"] || "").to_s.gsub("\n", " ")[0, 240]
      out << "- **`#{rule}`** — #{msg}\n"
      out << "  - selector: `#{sel}`\n" unless sel.empty?
    end
    if by_type[t].size > 20
      out << "- _(+#{by_type[t].size - 20} more #{t}s — see raw JSON)_\n"
    end
    out << "\n"
  end
end

File.write(OUTPUT, out)
puts "→ Wrote #{OUTPUT} (#{out.bytesize} bytes)"
puts "→ Totals: #{total_e}E / #{total_r}R / #{total_w}W / #{total_n}N across #{results.count { |r| !r[:error] }} pages"
