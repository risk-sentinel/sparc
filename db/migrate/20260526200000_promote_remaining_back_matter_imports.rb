# #583 — promote previously-imported back-matter from the legacy
# `import_metadata["back_matter"]` stash to first-class
# BackMatterResource rows for SspDocument, SarDocument, SapDocument,
# ProfileDocument, and PoamDocument. CDEF was handled in the v1.8.0
# CDEF-specific migration; this completes the sweep so
# BackMatterBuilder#deduplicated_imports can be deleted.
#
# Idempotent: rows with a UUID already present in back_matter_resources
# for the same document are skipped. The stash key is removed after
# successful promotion so subsequent exports don't double-render.
class PromoteRemainingBackMatterImports < ActiveRecord::Migration[8.1]
  UUID_V4 = /\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i

  DOC_TYPES = [
    [ SspDocument, "ssp_back_matter_promoted" ],
    [ SarDocument, "sar_back_matter_promoted" ],
    [ SapDocument, "sap_back_matter_promoted" ],
    [ ProfileDocument, "profile_back_matter_promoted" ],
    [ PoamDocument, "poam_back_matter_promoted" ]
  ].freeze

  def up
    DOC_TYPES.each do |klass, _action|
      klass.find_each do |doc|
        resources = doc.import_metadata&.dig("back_matter")
        next if resources.blank?

        existing_uuids = doc.back_matter_resources.pluck(:uuid).to_set
        promoted = 0

        Array(resources).each do |res|
          uuid = res["uuid"].to_s
          next unless uuid.match?(UUID_V4)
          next if existing_uuids.include?(uuid)

          first_rlink = Array(res["rlinks"]).first || {}
          title = res["title"].presence || "Imported resource #{uuid.first(8)}"

          doc.back_matter_resources.create!(
            uuid:          uuid,
            title:         title,
            description:   res["description"],
            href:          first_rlink["href"],
            media_type:    first_rlink["media-type"],
            rel:           "reference",
            source:        "imported",
            resource_data: res.except("uuid", "title", "description", "rlinks")
          )
          existing_uuids << uuid
          promoted += 1
        end

        next if promoted.zero?

        updated_metadata = doc.import_metadata.dup
        updated_metadata.delete("back_matter")
        doc.update_columns(import_metadata: updated_metadata)

        # Note: per-doc-type audit actions are not yet registered in
        # AuditEvent::ACTIONS (parallel to cdef_back_matter_promoted).
        # Skipping the audit event emit here keeps the migration
        # forward-runnable without coupling to a follow-up commit
        # that registers the actions. Promotion fact is observable
        # in the back_matter_resources table.
      end
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration
  end
end
