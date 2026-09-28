# frozen_string_literal: true

require "digest"
require "json_schemer"

# #1115 / #1172 — build SPARC's FedRAMP 20x KSI catalog from what FedRAMP
# publishes, instead of from a hand-transcribed seed.
#
#   FedrampKsiImportService.new.call                  # import the vendored snapshot
#   FedrampKsiImportService.new(dry_run: true).call   # run it, report, roll back
#
# ── Source ─────────────────────────────────────────────────────────────────
#
# Only the VENDORED copy of FedRAMP/rules (lib/data/fedramp, provenance in the
# sidecar) is ever read — never the network at import time (#1103 precedent).
# It is validated against FedRAMP's own JSON Schema (2020-12) FIRST; a file that
# does not validate imports nothing. `bin/ksi_upstream_diff` is the separate tool
# that tells you upstream has moved on.
#
# ── Re-keying an existing catalog ──────────────────────────────────────────
#
# FedRAMP re-keyed every indicator (numbered -> mnemonic), renamed five themes
# and dropped AUTH. Validations link to indicators by ROW id and are
# `dependent: :destroy`, so the importer never deletes:
#
#   * the owner-approved map (lib/data/fedramp/ksi_legacy_map.yml) renames ten
#     indicators IN PLACE — same row, new id — so their validations move with
#     them;
#   * every other old indicator is RETIRED (`retired_at`, `superseded_by`) and
#     keeps its validations as history;
#   * themes are renamed in place (EDU->CED, CM->CMT, IR->INR, POL->PIY,
#     REC->RPL); a theme upstream no longer has (AUTH) is retired.
#
# ── Crosswalk ──────────────────────────────────────────────────────────────
#
# Each FedRAMP indicator carries its own NIST SP 800-53 crosswalk (`controls[]`).
# The "FedRAMP 20x KSI to NIST SP 800-53 Rev 5" mapping is rebuilt from it —
# replacing the seed's 62 hand-written rows. The Rev 5 catalog is found by
# framework + version, not by an exact name: the seed's exact-name lookup never
# matched a real deployment whose Rev 5 catalog is named after its OSCAL title,
# so that deployment had no KSI crosswalk at all. A target the Rev 5 catalog does
# not hold is skipped and counted, never fails the import.
#
# ── Idempotent ─────────────────────────────────────────────────────────────
#
# The catalog records the snapshot's sha256 as `catalog_content_digest`; the
# same snapshot imports as `unchanged`. Everything runs in one savepointed
# transaction: it lands whole or not at all.
#
# NIST SP 800-53 Rev 5: CM-3 (the change is audited), SA-9/SR-3 (external
# source validated before use), CA-2 (assessments stay attached to what they
# assessed).
class FedrampKsiImportService
  DATA_DIR      = Rails.root.join("lib/data/fedramp")
  SOURCE        = "FedRAMP 20x"
  CATALOG_NAME  = "FedRAMP 20x Key Security Indicators"
  MAPPING_NAME  = "FedRAMP 20x KSI to NIST SP 800-53 Rev 5"
  NIST_FRAMEWORK = "NIST SP 800-53"

  # FedRAMP renamed these themes; the family row is renamed in place.
  THEME_RENAMES = { "EDU" => "CED", "CM" => "CMT", "IR" => "INR", "POL" => "PIY", "REC" => "RPL" }.freeze

  Result = Struct.new(:status, :version, :changes, :errors, keyword_init: true) do
    def imported? = status == :imported
    def unchanged? = status == :unchanged
    def planned? = status == :planned
    def refused? = status == :refused

    def report
      return "KSI import REFUSED — nothing was changed:\n" + errors.map { |e| "  - #{e}" }.join("\n") if refused?
      return "KSI catalog already at FedRAMP #{version} — nothing to do" if unchanged?

      verb = planned? ? "would import" : "imported"
      lines = [ "KSI catalog #{verb} FedRAMP #{version}:" ]
      changes.each { |k, v| lines << "  #{k.to_s.tr('_', ' ')}: #{v.is_a?(Array) ? v.size : v}" }
      lines.join("\n")
    end
  end

  class Refused < StandardError; end

  def initialize(dry_run: false, data_dir: DATA_DIR, audit: true)
    @dry_run = dry_run
    @data_dir = Pathname(data_dir)
    @audit = audit
  end

  def call
    raw = data_path.binread
    data = JSON.parse(raw)
    errors = schema_errors(data)
    return finish(Result.new(status: :refused, version: data.dig("info", "version"), changes: {}, errors: errors)) if errors.any?

    digest = Digest::SHA256.hexdigest(raw)
    version = data.dig("info", "version")
    existing = ControlCatalog.find_by(source: SOURCE)
    if existing&.catalog_content_digest == digest && !dry_run
      return Result.new(status: :unchanged, version: version, changes: {}, errors: [])
    end

    changes = Hash.new(0)
    ActiveRecord::Base.transaction(requires_new: true) do
      catalog = upsert_catalog(existing, version, digest)
      apply_legacy_map(catalog, data, changes)
      upsert_themes_and_indicators(catalog, data, changes)
      retire_absent_themes(catalog, data, changes)
      rebuild_crosswalk(catalog, data, version, changes)
      raise ActiveRecord::Rollback if dry_run
    end
    finish(Result.new(status: dry_run ? :planned : :imported, version: version, changes: changes.to_h, errors: []))
  rescue Refused, ActiveRecord::ActiveRecordError, JSON::ParserError => e
    finish(Result.new(status: :refused, version: version, changes: {}, errors: [ e.message ]))
  end

  private

  attr_reader :dry_run, :data_dir

  def data_path = data_dir.join("fedramp-consolidated-rules.json")
  def schema_path = data_dir.join("fedramp-consolidated-rules.schema.json")
  def map_path = data_dir.join("ksi_legacy_map.yml")
  def provenance = @provenance ||= JSON.parse(data_dir.join("fedramp-consolidated-rules.provenance.json").read)
  def legacy_map = @legacy_map ||= YAML.safe_load_file(map_path).fetch("indicators")

  def schema_errors(data)
    JSONSchemer.schema(JSON.parse(schema_path.read)).validate(data).first(20).map do |e|
      "#{e['data_pointer'].presence || '/'}: #{e['error']}"
    end
  end

  def upsert_catalog(existing, version, digest)
    catalog = existing || ControlCatalog.new(name: CATALOG_NAME, source: SOURCE)
    catalog.assign_attributes(
      version: version,
      catalog_content_digest: digest,
      description: "FedRAMP 20x Key Security Indicators, imported from FedRAMP's consolidated rules " \
                   "(FedRAMP/rules, version #{version}).",
      metadata_extra: (catalog.metadata_extra || {}).merge(
        "fedramp_rules" => provenance.slice("source_repository", "source_commit", "upstream_version", "retrieved")
      )
    )
    catalog.save!
    catalog
  end

  def indicators_of(catalog) = CatalogControl.joins(:control_family).where(control_families: { control_catalog_id: catalog.id })

  def family(catalog, code) = catalog.control_families.find_by(code: code)

  # Renames first, so a renamed row is found by its NEW id when the indicators
  # are upserted and is updated rather than duplicated.
  def apply_legacy_map(catalog, data, changes)
    upstream = upstream_indicators(data)
    legacy_map.each do |old_id, row|
      control = indicators_of(catalog).find_by(control_id: old_id)
      next unless control

      if (new_label = row["rename_to"])
        new_id = new_label.downcase
        raise Refused, "#{old_id} -> #{new_label}: #{new_label} is not in FedRAMP #{data.dig('info', 'version')}" unless upstream.key?(new_label)
        raise Refused, "#{old_id} -> #{new_label}: #{new_id} already exists in the catalog" if indicators_of(catalog).exists?(control_id: new_id)

        control.update!(control_id: new_id, label: new_label, sort_id: new_id)
        changes[:renamed] += 1
      elsif row["retire"] && !control.retired?
        control.update!(retired_at: Time.current, superseded_by: Array(row["superseded_by"]))
        changes[:retired] += 1
      end
    end
  end

  def upsert_themes_and_indicators(catalog, data, changes)
    data.fetch("KSI").each_with_index do |(code, theme), index|
      fam = family(catalog, code) || rename_theme(catalog, code) || catalog.control_families.new(code: code)
      changes[:themes_created] += 1 if fam.new_record?
      fam.assign_attributes(name: theme.fetch("name"), sort_order: index + 1, retired_at: nil)
      fam.save!

      theme.fetch("indicators").each do |label, indicator|
        control_id = label.downcase
        control = indicators_of(catalog).find_by(control_id: control_id) || fam.catalog_controls.new(control_id: control_id)
        changes[:indicators_created] += 1 if control.new_record?
        control.assign_attributes(
          control_family: fam, label: label, sort_id: control_id,
          title: indicator.fetch("name"), description: statement_of(indicator),
          guidance_data: (control.guidance_data || {}).merge("fedramp" => indicator.slice("varies_by_class", "terms", "updated").compact),
          retired_at: nil, superseded_by: []
        )
        control.save!
      end
    end
  end

  # An indicator states one requirement, or one per impact class.
  def statement_of(indicator)
    return indicator["statement"] if indicator["statement"].present?

    # Keyed by FedRAMP impact class letter (b, c), each holding a `statement`.
    Array(indicator["varies_by_class"]).map { |cls, text| "Class #{cls.upcase}: #{text.is_a?(Hash) ? text['statement'] : text}" }.join("\n")
  end

  def rename_theme(catalog, code)
    old_code = THEME_RENAMES.key(code)
    fam = old_code && family(catalog, old_code)
    return unless fam

    fam.code = code
    fam
  end

  def retire_absent_themes(catalog, data, changes)
    catalog.control_families.not_retired.where.not(code: data.fetch("KSI").keys).find_each do |fam|
      raise Refused, "theme #{fam.code} still has current indicators" if fam.catalog_controls.not_retired.exists?

      fam.update!(retired_at: Time.current)
      changes[:themes_retired] += 1
    end
  end

  def rebuild_crosswalk(catalog, data, version, changes)
    nist = rev5_catalog
    unless nist
      changes[:crosswalk] = "skipped — no NIST SP 800-53 Rev 5 catalog is loaded"
      return
    end

    mapping = ControlMapping.find_or_initialize_by(name: MAPPING_NAME)
    mapping.assign_attributes(
      source_catalog: catalog, target_catalog: nist, status: "complete", method_type: "human",
      matching_rationale: "functional", mapping_version: version,
      description: "FedRAMP's own crosswalk from each Key Security Indicator to NIST SP 800-53 Rev 5, " \
                   "from the controls[] of FedRAMP/rules #{version}. FedRAMP authors it; SPARC does not."
    )
    mapping.save!
    mapping.control_mapping_entries.delete_all
    upstream_indicators(data).each do |label, indicator|
      indicator.fetch("controls").each do |target|
        unless ControlMappingEntry.resolves?(nist, target)
          changes[:crosswalk_targets_not_in_rev5] += 1
          next
        end
        mapping.control_mapping_entries.create!(source_control_id: label.downcase, target_control_id: target, relationship: "intersects")
        changes[:crosswalk_entries] += 1
      end
    end
  end

  # Highest 5.x in the NIST SP 800-53 framework; the seed's exact name as a
  # fallback for databases that carry it.
  def rev5_catalog
    ControlCatalog.where(framework: NIST_FRAMEWORK).where("version LIKE ?", "5.%")
                  .max_by { |c| Gem::Version.new(c.version.to_s[/\A[\d.]+/] || "0") } ||
      ControlCatalog.find_by(name: "NIST SP 800-53 Rev 5")
  end

  def upstream_indicators(data) = data.fetch("KSI").values.reduce({}) { |acc, t| acc.merge(t.fetch("indicators")) }

  def finish(result)
    audit!(result) if @audit && (result.imported? || result.refused?)
    result
  end

  def audit!(result)
    AuditEvent.log(
      action: result.imported? ? "ksi_catalog_imported" : "ksi_catalog_import_refused",
      metadata: { upstream_version: result.version, source_commit: provenance["source_commit"],
                  changes: result.changes, errors: result.errors }
    )
  rescue StandardError => e
    Rails.logger.error("ksi import: could not write the audit event (#{e.class}: #{e.message})")
  end
end
