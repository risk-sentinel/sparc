#!/usr/bin/env ruby
# frozen_string_literal: true

# ==============================================================================
# build_license_inventory.rb -- consolidate CycloneDX SBOMs into a license report
# ==============================================================================
# Issue #472
#
# Reads up to three CycloneDX JSON SBOMs (Ruby gems via cdxgen, Trivy fs,
# Trivy container), applies the policy in docs/compliance/license-policy.yml
# (with per-component exceptions from docs/compliance/license-dispositions.yml),
# and emits both machine-readable and human-readable inventory artifacts.
#
# Usage:
#   ruby scripts/ci/build_license_inventory.rb \
#     --sbom sbom-ruby:path/to/sbom-ruby.cdx.json \
#     --sbom trivy-fs:path/to/trivy-fs-sbom.cdx.json \
#     --sbom trivy-container:path/to/trivy-container-sbom.cdx.json \
#     --policy docs/compliance/license-policy.yml \
#     --dispositions docs/compliance/license-dispositions.yml \
#     --out-json license-inventory.json \
#     --out-md license-inventory.md
#
# Exit codes:
#   0 -- inventory built. Policy violations may exist but enforce=false.
#   1 -- inventory built. Policy enforce=true AND violations exist.
#   2 -- input error (missing files, malformed JSON/YAML).
# ==============================================================================

require "json"
require "yaml"
require "optparse"
require "date"
require "set"

class LicenseInventoryBuilder
  # #475 — Canonicalize common non-SPDX license strings emitted by upstream
  # package metadata (Trivy passes these through unmodified). Keeps the
  # policy file readable (one entry per logical license) and the action-item
  # list focused on real signals instead of formatting variants.
  #
  # Add entries here when a known-equivalent variant appears in the
  # inventory. Avoid case-insensitive regex matching: explicit aliases are
  # auditable, fuzzy matching hides legitimate variants.
  LICENSE_ALIASES = {
    "Apache 2.0"                  => "Apache-2.0",
    "Apache 2"                    => "Apache-2.0",
    "Apache License 2.0"          => "Apache-2.0",
    "Apache License, Version 2.0" => "Apache-2.0",
    "BSD 2-Clause"                => "BSD-2-Clause",
    "BSD 3-Clause"                => "BSD-3-Clause",
    "MIT License"                 => "MIT",
    "ISC License"                 => "ISC",
    "public-domain"               => "CC0-1.0",
    "PD"                          => "CC0-1.0",

    # SPDX deprecated old ambiguous IDs in favor of explicit -only / -or-later
    # forms (SPDX 3.10+). Upstream package metadata frequently uses the
    # deprecated bare IDs; canonicalize to -only since that's the safer
    # interpretation when the upstream didn't pick a side.
    "GPL-3.0"                     => "GPL-3.0-only",
    "GPL-2.0"                     => "GPL-2.0-only",
    "LGPL-3.0"                    => "LGPL-3.0-only",
    "LGPL-2.1"                    => "LGPL-2.1-only",
    "LGPL-2.0"                    => "LGPL-2.0-only",
    "AGPL-3.0"                    => "AGPL-3.0-only",

    # OpenLDAP uses the OLDAP-* SPDX namespace, not OpenLDAP-*.
    "OpenLDAP-2.8"                => "OLDAP-2.8",

    # SPDX doesn't have a dedicated MIT-X11 ID; functionally identical to MIT.
    "MIT-X11"                     => "MIT"
  }.freeze

  attr_reader :sboms, :policy, :dispositions, :git_sha

  def initialize(sboms:, policy:, dispositions:, git_sha: nil)
    @sboms = sboms
    @policy = policy
    @dispositions = dispositions || []
    @git_sha = git_sha
    @raw_components = {} # source => Array<original CycloneDX component hashes>
  end

  def build
    rows = []
    @sboms.each do |source, path|
      doc = JSON.parse(File.read(path))
      components = doc.fetch("components", [])
      @raw_components[source.to_s] = components
      components.each do |c|
        rows << build_row(c, source)
      end
    end

    # #475 — Collapse duplicate (purl)-keyed rows from multiple SBOMs into one.
    # A gem appears in both `sbom-ruby` (with license) and `trivy-container`
    # (without). Without dedup the action-item list double-counts the
    # without-license row as `unmapped` even though the license is known.
    rows = deduplicate_rows(rows)

    apply_policy!(rows)
    {
      generated_at: Time.now.utc.iso8601,
      git_sha: @git_sha,
      summary: summarize(rows),
      policy: { enforce: enforce?, file: "docs/compliance/license-policy.yml" },
      by_license: group_by_license(rows),
      action_items: action_items(rows),
      by_component: rows
    }
  end

  # Merge all source SBOMs into one CycloneDX document, deduplicating by
  # purl (or by (name, version, type) when purl is absent). Each merged
  # component records the source SBOMs it came from in
  # properties[name="sparc:source-sboms"].
  def merged_sbom
    seen = {} # dedupe key => merged component
    @raw_components.each do |source, components|
      components.each do |c|
        key = dedup_key(c)
        if seen.key?(key)
          # Record this additional source on the existing entry.
          props = seen[key]["properties"] ||= []
          source_prop = props.find { |p| p["name"] == "sparc:source-sboms" }
          if source_prop
            existing = source_prop["value"].to_s.split(",").map(&:strip)
            source_prop["value"] = (existing + [ source.to_s ]).uniq.join(",")
          else
            props << { "name" => "sparc:source-sboms", "value" => source.to_s }
          end
        else
          merged = c.dup
          merged["properties"] = (c["properties"] || []) + [
            { "name" => "sparc:source-sboms", "value" => source.to_s }
          ]
          seen[key] = merged
        end
      end
    end

    {
      "bomFormat" => "CycloneDX",
      "specVersion" => "1.6",
      "version" => 1,
      "metadata" => {
        "timestamp" => Time.now.utc.iso8601,
        "tools" => [ { "name" => "sparc/build_license_inventory.rb", "version" => "1.0" } ],
        "properties" => [
          { "name" => "sparc:git-sha", "value" => @git_sha.to_s },
          { "name" => "sparc:merged-from", "value" => @sboms.keys.map(&:to_s).join(",") }
        ]
      },
      "components" => seen.values
    }
  end

  # ── Reporters ─────────────────────────────────────────────────────────────

  def to_json_payload(report)
    JSON.pretty_generate(report)
  end

  def to_markdown(report)
    md = +""
    md << "# SPARC License Inventory\n\n"
    md << "Generated: `#{report[:generated_at]}`  \n"
    md << "Git SHA: `#{report[:git_sha] || 'unknown'}`  \n"
    md << "Policy: `#{report.dig(:policy, :file)}` (enforce=`#{report.dig(:policy, :enforce)}`)\n\n"

    md << "## Summary\n\n"
    s = report[:summary]
    md << "| Metric | Value |\n|---|---:|\n"
    md << "| Total components | #{s[:total_components]} |\n"
    md << "| Components with licenses | #{s[:with_licenses]} (#{s[:coverage_pct]}%) |\n"
    md << "| Components without licenses | #{s[:without_licenses]} |\n"
    md << "| Unique licenses | #{s[:unique_licenses]} |\n"
    md << "| Action items | #{report[:action_items].length} |\n\n"

    md << "## License Distribution\n\n"
    md << "| License | Count | Disposition |\n|---|---:|---|\n"
    report[:by_license].each do |license, info|
      md << "| `#{license || '(none)'}` | #{info[:count]} | #{info[:disposition]} |\n"
    end
    md << "\n"

    if report[:action_items].any?
      md << "## Action Items\n\n"
      md << "Components flagged by `docs/compliance/license-policy.yml` that need review. " \
            "Record dispositions in `docs/compliance/license-dispositions.yml`.\n\n"

      blocks = report[:action_items].group_by { |a| a[:severity] }
      %i[block warn unmapped].each do |sev|
        items = blocks[sev] || []
        next if items.empty?

        md << "### #{sev.to_s.upcase} (#{items.length})\n\n"
        md << "| Component | Version | License | Source | Reason |\n|---|---|---|---|---|\n"
        items.each do |a|
          md << "| `#{a[:name]}` | `#{a[:version] || '-'}` | `#{a[:license] || '(none)'}` | #{a[:source]} | #{a[:reason]} |\n"
        end
        md << "\n"
      end
    else
      md << "## Action Items\n\n_None — all components either fall under the allowlist or have recorded dispositions._\n\n"
    end

    md
  end

  # ── Internals ─────────────────────────────────────────────────────────────

  private

  # Dedup key: purl when available (canonical identifier); otherwise a
  # tuple of name + version + type. Two SBOMs reporting the same gem at
  # the same version collapse into one merged row.
  def dedup_key(component)
    purl = component["purl"]
    return purl if purl && !purl.to_s.empty?
    [ component["name"], component["version"], component["type"] ].join("|")
  end

  # Same dedup key for rows (already-built component hashes).
  def row_dedup_key(row)
    return row[:purl] if row[:purl] && !row[:purl].to_s.empty?
    [ row[:name], row[:version], row[:type] ].join("|")
  end

  # Collapse duplicate rows from multiple SBOMs. When the same purl appears
  # in two sources (e.g. sbom-ruby with a license, trivy-container without),
  # prefer the row that HAS a license. Combine source labels so provenance
  # is preserved.
  def deduplicate_rows(rows)
    grouped = rows.group_by { |r| row_dedup_key(r) }
    grouped.map do |_key, group|
      with_license = group.find { |r| r[:license] && !r[:license].to_s.empty? }
      winner = (with_license || group.first).dup
      winner[:source] = group.map { |r| r[:source] }.uniq.sort.join(",")
      winner
    end
  end

  def build_row(component, source)
    licenses = normalize_licenses(component["licenses"])
    {
      name: component["name"],
      version: component["version"],
      type: component["type"],
      purl: component["purl"],
      license: licenses.first, # primary
      all_licenses: licenses,
      source: source.to_s,
      disposition: nil,
      severity: nil,
      reason: nil
    }
  end

  # CycloneDX license shapes (all are valid):
  #   { "license": { "id": "MIT", ... } }
  #   { "license": { "name": "MIT-ish", ... } }
  #   { "expression": "MIT OR Apache-2.0" }
  def normalize_licenses(field)
    return [] unless field.is_a?(Array)

    field.flat_map do |entry|
      if entry.is_a?(Hash) && entry["expression"]
        entry["expression"].to_s.split(/\s+OR\s+/i).map(&:strip)
      elsif entry.is_a?(Hash) && entry["license"].is_a?(Hash)
        [ entry["license"]["id"] || entry["license"]["name"] ]
      else
        []
      end
    end.compact.reject(&:empty?).map { |id| canonicalize_license(id) }
  end

  # #475 — Map non-SPDX variants ("Apache 2.0", "public-domain") to their
  # canonical SPDX identifiers via LICENSE_ALIASES. Unknown strings pass
  # through unchanged so they show up in the inventory for triage.
  def canonicalize_license(id)
    LICENSE_ALIASES[id] || id
  end

  def apply_policy!(rows)
    allowlist = (@policy["allowlist"] || []).to_set
    warn_list = (@policy["warn_list"] || []).to_set
    blocklist = (@policy["blocklist"] || []).to_set
    unmapped  = (@policy["unmapped_action"] || "warn").to_s
    skip_patterns = (@policy["skip_patterns"] || []).map { |p| Regexp.new(p) }
    # #481 — skip_purls matches against the package-URL field instead of the
    # name. Useful when an ecosystem's component names are bare package names
    # (e.g. PyPI: `annotated-types`) but the purl reveals their ecosystem
    # (`pkg:pypi/annotated-types@0.7.0`).
    skip_purls = (@policy["skip_purls"] || []).map { |p| Regexp.new(p) }

    rows.each do |row|
      # Skip patterns short-circuit policy evaluation entirely.
      if skip_patterns.any? { |re| row[:name].to_s.match?(re) }
        row[:disposition] = "skipped"
        next
      end

      # #481 — purl-based skip (ecosystem-level filter).
      if row[:purl] && skip_purls.any? { |re| row[:purl].to_s.match?(re) }
        row[:disposition] = "skipped"
        next
      end

      # Per-component disposition wins.
      d = find_disposition(row)
      if d
        row[:disposition] = d["disposition"]
        row[:disposition_rationale] = d["rationale"]
        row[:reviewed_by] = d["reviewed_by"]
        row[:next_review_date] = d["next_review_date"]
        next if %w[accepted waiver remediated].include?(d["disposition"])

        # `replace` still counts as an action item until target is in place.
        row[:severity] = :warn
        row[:reason] = "Replace pending: target=#{d['target_component'] || 'TBD'}"
        next
      end

      # Fall through to policy class lookup.
      license = row[:license]
      if license.nil? || license.empty?
        next if unmapped == "ignore"
        row[:severity] = (unmapped == "block" ? :block : :unmapped)
        row[:reason] = "No license field in source SBOM"
        next
      end

      if blocklist.include?(license)
        row[:severity] = :block
        row[:reason] = "License is on the blocklist"
      elsif warn_list.include?(license)
        row[:severity] = :warn
        row[:reason] = "License requires review (warn_list)"
      elsif !allowlist.include?(license)
        # Unknown / not on allowlist either -- treat as warn so we discover gaps.
        row[:severity] = :warn
        row[:reason] = "License not on allowlist or warn_list -- needs review"
      end
    end
  end

  def find_disposition(row)
    @dispositions.find do |d|
      next false unless d.is_a?(Hash) && d["name"] == row[:name]
      d["version"].nil? || d["version"] == row[:version]
    end
  end

  def summarize(rows)
    total = rows.length
    with = rows.count { |r| r[:license] && !r[:license].empty? }
    licenses = rows.map { |r| r[:license] }.compact.uniq
    {
      total_components: total,
      with_licenses: with,
      without_licenses: total - with,
      coverage_pct: total.zero? ? 0.0 : ((with.to_f / total) * 100).round(2),
      unique_licenses: licenses.length
    }
  end

  def group_by_license(rows)
    grouped = rows.group_by { |r| r[:license] }
    grouped.transform_values do |group|
      severities = group.map { |r| r[:severity] }.compact.uniq
      disposition =
        if severities.include?(:block) then "BLOCK"
        elsif severities.include?(:warn) then "WARN"
        elsif severities.include?(:unmapped) then "UNMAPPED"
        else "OK"
        end

      {
        count: group.length,
        disposition: disposition,
        components: group.map { |r| { name: r[:name], version: r[:version], source: r[:source] } }
      }
    end.sort_by { |_lic, info| -info[:count] }.to_h
  end

  def action_items(rows)
    rows
      .select { |r| r[:severity] && r[:severity] != :skipped }
      .map do |r|
        {
          name: r[:name],
          version: r[:version],
          license: r[:license],
          source: r[:source],
          severity: r[:severity],
          reason: r[:reason],
          purl: r[:purl]
        }
      end
  end

  def enforce?
    @policy["enforce"] == true
  end
end

# ── Entry point ─────────────────────────────────────────────────────────────

def parse_args(argv)
  opts = { sboms: {} }
  parser = OptionParser.new do |o|
    o.banner = "Usage: build_license_inventory.rb [options]"
    o.on("--sbom NAME:PATH") do |v|
      name, path = v.split(":", 2)
      raise "--sbom expects NAME:PATH (got #{v.inspect})" if name.nil? || path.nil?
      opts[:sboms][name.to_sym] = path
    end
    o.on("--policy PATH")       { |v| opts[:policy] = v }
    o.on("--dispositions PATH") { |v| opts[:dispositions] = v }
    o.on("--out-json PATH")     { |v| opts[:out_json] = v }
    o.on("--out-md PATH")       { |v| opts[:out_md] = v }
    o.on("--out-merged-sbom PATH") { |v| opts[:out_merged_sbom] = v }
    o.on("--git-sha SHA")       { |v| opts[:git_sha] = v }
  end
  parser.parse!(argv)
  opts
end

def main(argv)
  args = parse_args(argv)
  policy_path = args[:policy] || "docs/compliance/license-policy.yml"
  dispositions_path = args[:dispositions] || "docs/compliance/license-dispositions.yml"

  unless File.exist?(policy_path)
    warn "Policy file not found: #{policy_path}"
    return 2
  end

  policy_raw = YAML.safe_load_file(policy_path)
  policy = policy_raw.is_a?(Hash) ? policy_raw.fetch("policy", policy_raw) : {}

  dispositions =
    if File.exist?(dispositions_path)
      d = YAML.safe_load_file(dispositions_path, permitted_classes: [ Date ])
      d.is_a?(Hash) ? Array(d["dispositions"]) : []
    else
      []
    end

  # Filter to SBOMs that actually exist (some CI artifacts may be optional).
  existing_sboms = args[:sboms].select { |_n, path| File.exist?(path) }
  missing = args[:sboms].keys - existing_sboms.keys
  warn "Skipping missing SBOMs: #{missing.join(', ')}" if missing.any?

  if existing_sboms.empty?
    warn "No SBOMs found. Pass at least one --sbom NAME:PATH."
    return 2
  end

  builder = LicenseInventoryBuilder.new(
    sboms: existing_sboms,
    policy: policy || {},
    dispositions: dispositions,
    git_sha: args[:git_sha] || ENV.fetch("GITHUB_SHA", nil)
  )
  report = builder.build

  if args[:out_json]
    File.write(args[:out_json], builder.to_json_payload(report))
    warn "Wrote #{args[:out_json]}"
  else
    puts builder.to_json_payload(report)
  end

  if args[:out_md]
    File.write(args[:out_md], builder.to_markdown(report))
    warn "Wrote #{args[:out_md]}"
  end

  if args[:out_merged_sbom]
    File.write(args[:out_merged_sbom], JSON.pretty_generate(builder.merged_sbom))
    warn "Wrote #{args[:out_merged_sbom]}"
  end

  # Exit code logic: only fail when enforce=true AND there is a :block-severity item.
  blocks = report[:action_items].count { |a| a[:severity] == :block }
  enforce = report.dig(:policy, :enforce) == true

  if enforce && blocks.positive?
    warn "License policy ENFORCE: #{blocks} block-severity item(s) found."
    return 1
  end

  0
end

if __FILE__ == $PROGRAM_NAME
  exit(main(ARGV) || 0)
end
