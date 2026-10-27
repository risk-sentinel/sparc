# frozen_string_literal: true

# #1089 — a CDEF linked to one baseline exported that baseline as every
# control's `control-implementation/@source`, read from its single
# `profile_document_id`. Now that a CDEF can serve several baselines, the
# document-level link no longer says which one a control was drawn from, so
# each control records it: the baseline the CDEF was linked to, for every
# control that names no source of its own.
#
# The export is unchanged by construction: the source each control now names is
# the one the document-level fallback gave it. Skipped where the document
# carries its own `control_implementation_source` (an authored source wins,
# #944) and where a control already names one (#1088). Idempotent: only blank
# sources are filled.
class BackfillCdefControlSources < ActiveRecord::Migration[8.1]
  include DeferredDataMigration
  data_migration_version "1.0.0"

  def up
    defer_data_migration do
      filled = 0
      CdefDocument.where.not(profile_document_id: nil)
                  .where(control_implementation_source: [ nil, "" ])
                  .includes(:profile_document).find_each do |cdef|
        href = OscalMetadata.import_href_for(cdef.profile_document)
        next if href.blank?

        filled += cdef.cdef_controls.where(implementation_source: [ nil, "" ]).update_all(implementation_source: href)
      end
      Rails.logger.info("[BackfillCdefControlSources] #{filled} controls now name their baseline")
    end
  end

  def down
    # Sources a control names are left as they are: they match what it exported.
  end
end
