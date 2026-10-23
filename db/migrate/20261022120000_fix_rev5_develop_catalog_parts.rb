# frozen_string_literal: true

# #1228 — give existing installs NIST's develop-branch fixes to SA-15(13),
# SA-24 and SI-02(07).
#
# A fresh install seeds the corrected catalog. An existing install already
# holds the v5.2.0 catalog NIST released with the errors, and the seed will not
# re-run: bumping its SeedRunner version would re-import over every install's
# catalog and overwrite what people have edited there. So this repairs the
# three controls, and only them, in place:
#
#   SA-15(13)  the statement was SA-15(12)'s requirement, and the Examine
#              method was labelled SA-15(12)-Examine (oscal-content#343)
#   SA-24      objectives b.[06]–b.[10] were missing (oscal-content#305)
#   SI-02(07)  objectives c.[01] and c.[02] had no labels (oscal-content#305)
#
# (SA-24's assessment-for links, #301, are not stored in any table, so there is
# nothing to repair for them.)
#
# ── Compare-and-swap, so a person's edit is never overwritten ──────────────
#
# The v5.2.0 values are embedded below. For each field and each part:
#
#   still NIST's v5.2.0 value  → replaced with NIST's fix (read through
#                                NistCatalogSource, derived exactly as an import
#                                would derive it)
#   already NIST's fix         → left alone (a re-run, or a fresh install)
#   anything else              → a person's edit: KEPT, and named in the log
#                                (owner decision, 2026-10-22)
#
# New objective parts are inserted only where absent, with the derived UUIDs an
# import gives them, so a later re-import agrees with them.
#
# ── Scope ──────────────────────────────────────────────────────────────────
#
# Only catalogs that ARE NIST's Rev 5 catalog — matched by NIST's document
# uuid, never by name — and only the three controls above. No `ssp_*`, `sap_*`
# or `sar_*` row is written: what an author wrote into an SSP is theirs. The
# SSPs whose statements still carry the old SA-15(13) text are COUNTED and
# NAMED instead, so an author can decide.
#
# Idempotent and resumable: one transaction per control, and every change is
# conditional on the row still holding NIST's old value.
class FixRev5DevelopCatalogParts < ActiveRecord::Migration[8.1]
  include DeferredDataMigration
  data_migration_version "1.0.0"

  SA_15_13 = "sa-15.13"
  SA_24 = "sa-24"
  SI_2_7 = "si-2.7"

  OLD_SA_15_13_STATEMENT = "Require the developer of the system or system component to minimize the use of " \
                           "personally identifiable information in development and test environments."

  # NIST v5.2.0 (2025-08-26), as an import stored it: guidance_data keys.
  OLD_GUIDANCE = {
    SA_15_13 => { "statement" => OLD_SA_15_13_STATEMENT },
    SA_24 => {
      "assessment_objective" => [
        "SA-24: Determine if:",
        *(1..5).map do |n|
          "SA-24a.0#{n}: organizational systems, system components, or system services achieve cyber " \
          "resiliency through {{ insert: param, sa-24_odp.0#{n} }};"
        end,
        "SA-24b.[01]: selected cyber resiliency goals are implemented as part of an organizational risk " \
        "management process of systems security engineering process;",
        "SA-24b.[02]: selected cyber resiliency objectives are implemented as part of an organizational risk " \
        "management process of systems security engineering process;",
        "SA-24b.[03]: selected cyber resiliency techniques are implemented as part of an organizational risk " \
        "management process of systems security engineering process;",
        "SA-24b.[04]: selected cyber resiliency implementation approaches are implemented as part of an " \
        "organizational risk management process of systems security engineering process;",
        "SA-24b.[05]: selected cyber resiliency design principles are implemented as part of an organizational " \
        "risk management process of systems security engineering process."
      ].join("\n")
    },
    SI_2_7 => {
      "assessment_objective" => [
        "SI-02(07): Determine if:",
        "SI-02(07)a.: Root cause analysis is conducted to identify underlying causes of issues or failures",
        "SI-02(07)b.: Actions to address the root cause of the issue of failure are developed",
        "The actions (defined in [SI-02(07)b.](#si-2.7_smt.b)) are implemented",
        "The implementation of actions is monitored for effectiveness."
      ].join("\n")
    }
  }.freeze

  # NIST v5.2.0, as an import stored them: catalog_control_parts rows.
  OLD_PARTS = {
    SA_15_13 => {
      "sa-15.13_smt" => { "label" => nil, "prose" => OLD_SA_15_13_STATEMENT, "props_data" => [] },
      "sa-15.13_asm-examine" => {
        "label" => "SA-15(12)-Examine", "prose" => nil,
        "props_data" => [
          { "name" => "method", "ns" => "http://csrc.nist.gov/ns/rmf", "value" => "EXAMINE" },
          { "name" => "label", "value" => "SA-15(12)-Examine", "class" => "sp800-53a" }
        ]
      }
    },
    SI_2_7 => {
      "si-2.7_obj.c-1" => { "label" => nil, "prose" => "The actions (defined in [SI-02(07)b.](#si-2.7_smt.b)) are implemented",
                            "props_data" => [] },
      "si-2.7_obj.c-2" => { "label" => nil, "prose" => "The implementation of actions is monitored for effectiveness.",
                            "props_data" => [] }
    }
  }.freeze

  # Parts NIST added; absent from every v5.2.0 import.
  NEW_PARTS = { SA_24 => %w[sa-24_obj.b-6 sa-24_obj.b-7 sa-24_obj.b-8 sa-24_obj.b-9 sa-24_obj.b-10] }.freeze

  CONTROL_IDS = [ SA_15_13, SA_24, SI_2_7 ].freeze
  PART_FIELDS = %w[label prose props_data].freeze

  def up
    defer_data_migration do
      catalogs = nist_rev5_catalogs
      say "NIST Rev 5 catalogs in scope: #{catalogs.size}"
      catalogs.each { |catalog| fix_catalog(catalog) }
      report_ssps_with_old_sa_15_13
    end
  end

  def down
    # Nothing to undo: putting NIST's errors back is not a state worth restoring.
  end

  private

  def nist_rev5_catalogs
    uuids = NistCatalogSource::CATALOG_UUIDS
    ControlCatalog.where(oscal_uuid: uuids)
                  .or(ControlCatalog.where("metadata_extra->>'catalog_uuid' IN (?)", uuids))
                  .order(:id).to_a
  end

  def fix_catalog(catalog)
    tally = Hash.new(0)
    CONTROL_IDS.each do |control_id|
      control = catalog.catalog_controls.find_by(control_id: control_id)
      if control.nil?
        say "catalog ##{catalog.id}: #{control_id} not found — skipped"
        next
      end

      ActiveRecord::Base.transaction { fix_control(catalog, control, tally) }
    end

    extra = catalog.metadata_extra.to_h
    catalog.update_column(:metadata_extra, extra.merge(
      "nist_develop_patch" => {
        "source_repository" => NistCatalogSource.provenance["source_repository"],
        "source_commit" => NistCatalogSource.source_commit,
        "controls" => CONTROL_IDS,
        "applied_at" => Time.current.utc.iso8601
      }
    ))
    say "catalog ##{catalog.id} (#{catalog.name.to_s.truncate(60)}): " \
        "#{tally[:fixed]} fixed, #{tally[:inserted]} inserted, #{tally[:current]} already current, " \
        "#{tally[:kept]} edited and kept"
  end

  def fix_control(catalog, control, tally)
    source = nist_control(control.control_id)
    fix_guidance(catalog, control, source, tally)
    fix_parts(catalog, control, source, tally)
    insert_new_parts(catalog, control, source, tally)
    reorder_parts(control, source)
  end

  # ── guidance_data ────────────────────────────────────────────────────────

  def fix_guidance(catalog, control, source, tally)
    fixed = CatalogImportService.oscal_guidance_data(source)
    updated = control.guidance_data.to_h.dup

    OLD_GUIDANCE.fetch(control.control_id, {}).each do |key, old|
      current = updated[key]
      if current == fixed[key]
        tally[:current] += 1
      elsif current == old
        updated[key] = fixed[key]
        tally[:fixed] += 1
      elsif current.nil?
        say "catalog ##{catalog.id}: #{control.control_id} has no guidance #{key} — left alone"
      else
        tally[:kept] += 1
        say "catalog ##{catalog.id}: #{control.control_id} guidance #{key} was edited — kept, NIST's fix not applied"
      end
    end

    control.update!(guidance_data: updated) if updated != control.guidance_data.to_h
  end

  # ── catalog_control_parts ────────────────────────────────────────────────

  def fix_parts(catalog, control, source, tally)
    fixed = source_parts(source)

    OLD_PARTS.fetch(control.control_id, {}).each do |part_id, old|
      row = control.catalog_control_parts.find_by(part_id: part_id)
      if row.nil?
        say "catalog ##{catalog.id}: #{control.control_id} part #{part_id} not stored — skipped"
        next
      end

      current = row.attributes.slice(*PART_FIELDS)
      target = fixed.fetch(part_id).slice(*PART_FIELDS)
      if current == target
        tally[:current] += 1
      elsif current == old
        row.update!(target)
        tally[:fixed] += 1
      else
        tally[:kept] += 1
        say "catalog ##{catalog.id}: #{control.control_id} part #{part_id} was edited — kept, NIST's fix not applied"
      end
    end
  end

  def insert_new_parts(catalog, control, source, tally)
    fixed = source_parts(source)

    NEW_PARTS.fetch(control.control_id, []).each do |part_id|
      part = fixed.fetch(part_id)
      row = control.catalog_control_parts.find_by(part_id: part_id)
      if row
        if row.attributes.slice(*PART_FIELDS) == part.slice(*PART_FIELDS)
          tally[:current] += 1
        else
          tally[:kept] += 1
          say "catalog ##{catalog.id}: #{control.control_id} part #{part_id} was edited — kept"
        end
        next
      end

      unless control.catalog_control_parts.exists?(part_id: part["parent_part_id"])
        say "catalog ##{catalog.id}: #{control.control_id} has no #{part['parent_part_id']} part — #{part_id} not added"
        next
      end

      # Written the way CatalogImportService#flush_control_parts! writes parts
      # (insert_all, no model validation): the derived identity an import gives
      # the part (#397) is a name-based uuid, which the model's v4-only format
      # check would refuse although an import stores exactly this value.
      CatalogControlPart.insert_all([
        part.slice(*PART_FIELDS, "part_id", "part_name", "parent_part_id", "row_order").merge(
          "catalog_control_id" => control.id,
          "uuid" => OscalUuidService.derived(control.uuid, "catalog-part:#{part['part_name']}", part_id)
        )
      ], unique_by: %i[catalog_control_id part_id])
      tally[:inserted] += 1
    end
  end

  # An inserted part shifts the parts after it. Their order is structure, not
  # content anyone edits, so it follows NIST's.
  def reorder_parts(control, source)
    source_parts(source).each do |part_id, part|
      control.catalog_control_parts.where(part_id: part_id).where.not(row_order: part["row_order"])
             .update_all(row_order: part["row_order"], updated_at: Time.current)
    end
  end

  # ── NIST's corrected catalog, through the one loader ─────────────────────

  def nist_control(control_id)
    @nist_controls ||= begin
      index = {}
      walk = lambda do |control|
        index[control["id"]] = control
        Array(control["controls"]).each(&walk)
      end
      NistCatalogSource.catalog.dig("catalog", "groups").each { |group| Array(group["controls"]).each(&walk) }
      index
    end
    @nist_controls.fetch(control_id)
  end

  # part_id => the row an import would store, row_order included.
  def source_parts(source)
    @source_parts ||= {}
    @source_parts[source["id"]] ||= begin
      acc = []
      CatalogPartExtractorService.walk_parts(Array(source["parts"]), acc,
                                             part_names: CatalogPartExtractorService::CATALOG_PART_NAMES,
                                             parent_part_id: nil)
      acc.each_with_index.to_h do |part, index|
        [ part[:part_id], part.transform_keys(&:to_s).merge("row_order" => index) ]
      end
    end
  end

  # ── Read-only report (owner decision, 2026-10-22) ────────────────────────

  # SSPs keep the requirement text they were generated with. Those whose
  # SA-15(13) statement is still SA-15(12)'s are named here; nothing is written.
  def report_ssps_with_old_sa_15_13
    rows = SspControl.joins(:ssp_document)
                     .joins("INNER JOIN ssp_control_fields f ON f.ssp_control_id = ssp_controls.id")
                     .where(ssp_documents: { deleted_at: nil })
                     .where("f.field_value LIKE ?", "%#{ActiveRecord::Base.sanitize_sql_like(OLD_SA_15_13_STATEMENT)}%")
                     .pluck("ssp_controls.control_id", "ssp_documents.id", "ssp_documents.name")
                     .select { |control_id, _, _| ControlId.canonical(control_id) == SA_15_13 }
    documents = rows.map { |_, id, name| [ id, name ] }.uniq

    say "SSPs whose SA-15(13) statement still carries SA-15(12)'s text: #{documents.size}"
    documents.each { |id, name| say "  SSP ##{id}: #{name}" }
    documents
  end
end
