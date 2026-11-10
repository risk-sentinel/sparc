# frozen_string_literal: true

# #1357 — clear the baseline priorities SPARC invented.
#
# Until v1.17.9, building a baseline from a catalog gave every control a
# P1/P2/P3. When the catalog control carried none (neither NIST catalog SPARC
# ships does: priority codes are not part of SP 800-53 Rev 5 or 800-53B), it
# derived one from how many baselines include the control: three → P1, two →
# P2, one or none → P3. The result looked like a NIST value and was not one,
# and publishing refused a baseline until every control had one.
#
# A priority is now optional. This clears the derived ones from existing
# baselines, drafts and published alike (owner-decided), and keeps every
# priority a person or a file chose.
#
# ── What counts as invented ────────────────────────────────────────────────
#
# SPARC never recorded where a priority came from, so a value is cleared only
# when ALL of these hold:
#
#   1. The baseline was built in SPARC: not imported from an OSCAL profile or
#      resolved catalog, whose priorities are the author's.
#   2. Its catalog control carries no P1/P2/P3 of its own (one it did carry was
#      copied, not invented).
#   3. The value equals what the old derivation gives for that control.
#   4. No audit event shows a person setting it: no bulk or inline priority
#      edit naming the control, and the control was never created or saved
#      through its edit form. The edit form's audit does not say WHAT changed,
#      so any save there counts as a choice (owner-decided). A baseline made by
#      "Create from Profile" or Duplicate inherits the choices recorded on its
#      source.
#
# Anything SPARC cannot prove was invented is kept.
#
# ── Traceable and idempotent ───────────────────────────────────────────────
#
# Each baseline it changes gets one `profile_document_updated` audit event
# listing the controls cleared and their old values. A published baseline's
# stored resolved catalog is left as it is until the baseline is next
# published. A re-run finds nothing left to clear.
class ClearInventedProfilePriorities < ActiveRecord::Migration[8.1]
  include DeferredDataMigration
  data_migration_version "1.0.0"

  IMPORTED_FORMATS = %w[oscal_profile oscal_resolved_profile].freeze
  BULK_EDIT_ACTION = "profile_controls_bulk_edited"
  FORM_ACTIONS = %w[profile_control_created profile_control_updated].freeze

  # The derivation SPARC used before #1357, frozen here so this migration keeps
  # recognising what it produced after the live service changed.
  def self.invented_priority(catalog_control)
    case catalog_control.baseline_levels.size
    when 3.. then "P1"
    when 2    then "P2"
    else           "P3"
    end
  end

  def up
    defer_data_migration do
      cleared = 0
      chosen = chosen_controls
      copied_from = copy_sources

      ProfileDocument.find_each do |doc|
        next if IMPORTED_FORMATS.include?(doc.import_metadata.is_a?(Hash) ? doc.import_metadata["format"] : nil)

        old_values = invented_in(doc, chosen, copied_from)
        next if old_values.empty?

        ProfileDocument.transaction do
          doc.profile_controls.where(control_id: old_values.keys).update_all(priority: nil, updated_at: Time.current)
          AuditEvent.log(action: "profile_document_updated", subject: doc,
                         metadata: { name: doc.name, issue: 1357,
                                     reason: "Cleared priorities SPARC derived; NIST SP 800-53 Rev 5 assigns none",
                                     cleared_priorities: old_values })
        end
        cleared += old_values.size
        say "profile ##{doc.id}: cleared #{old_values.size} invented priorit#{old_values.size == 1 ? 'y' : 'ies'}"
      rescue StandardError => e
        say "profile ##{doc.id}: not changed — #{e.class}: #{e.message}"
      end

      say "cleared #{cleared} invented priorit#{cleared == 1 ? 'y' : 'ies'} in total"
      cleared
    end
  end

  def down
    # Deliberately empty: the cleared values were never NIST's, and each one is
    # recorded in its baseline's audit event should anyone want it back.
  end

  private

  # { control_id => old priority } for the controls in `doc` that SPARC invented.
  def invented_in(doc, chosen, copied_from)
    lineage = lineage_of(doc.id, copied_from)
    catalog_controls = {}

    doc.profile_controls.where.not(priority: [ nil, "" ]).each_with_object({}) do |pc, out|
      next if lineage.any? { |id| chosen.include?([ id, pc.control_id ]) }

      catalog = pc.source_catalog || doc.control_catalog
      next unless catalog

      cc = (catalog_controls[catalog.id] ||= index_controls(catalog))[pc.control_id]
      next unless cc
      next if ProfileControl::PRIORITIES.include?(cc.priority.to_s.strip.upcase)
      next unless pc.priority == self.class.invented_priority(cc)

      out[pc.control_id] = pc.priority
    end
  end

  # Every form a catalog's control ids take, so "ac-2.1" finds "ac-2(1)" too.
  def index_controls(catalog)
    catalog.catalog_controls.each_with_object({}) do |cc, index|
      ControlId.forms(cc.control_id).each { |form| index[form] ||= cc }
    end
  end

  # [profile id, control id] for every control a person set a priority on.
  def chosen_controls
    chosen = Set.new

    AuditEvent.where(action: BULK_EDIT_ACTION, subject_type: "ProfileDocument").find_each do |event|
      meta = event.metadata || {}
      next unless meta["priority_changed"].to_s == "true"

      Array(meta["control_ids"]).each { |cid| chosen << [ event.subject_id, cid ] }
    end

    form_ids = AuditEvent.where(action: FORM_ACTIONS, subject_type: "ProfileControl").distinct.pluck(:subject_id)
    ProfileControl.where(id: form_ids).pluck(:profile_document_id, :control_id).each { |pair| chosen << pair }

    chosen
  end

  # { copy id => source id }: "Create from Profile" records its source on the
  # copy; Duplicate records it in the copy's audit event.
  def copy_sources
    sources = AuditEvent.where(action: "profile_document_copied", subject_type: "ProfileDocument")
                        .pluck(:subject_id, :metadata)
                        .each_with_object({}) { |(copy_id, meta), map| map[copy_id] = (meta || {})["source_id"]&.to_i }
    ProfileDocument.where.not(source_profile_id: nil).pluck(:id, :source_profile_id).each { |id, src| sources[id] = src }
    sources
  end

  # The baseline and every baseline it was copied from, oldest last.
  def lineage_of(id, copied_from)
    seen = [ id ]
    while (source = copied_from[seen.last]) && !seen.include?(source)
      seen << source
    end
    seen
  end
end
