# #498 slice 3 — promote previously-imported CDEF back-matter from
# the legacy `import_metadata["back_matter"]` stash into first-class
# BackMatterResource rows (source: "imported").
#
# Idempotent: rows with a UUID already present in back_matter_resources
# for the same document are skipped. The stash key is removed after
# successful promotion so subsequent exports don't double-render.
class PromoteCdefBackMatterImports < ActiveRecord::Migration[8.1]
  UUID_V4 = /\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i

  def up
    CdefDocument.find_each do |cdef|
      resources = cdef.import_metadata&.dig("back_matter")
      next if resources.blank?

      existing_uuids = cdef.back_matter_resources.pluck(:uuid).to_set
      promoted = 0

      Array(resources).each do |res|
        uuid = res["uuid"].to_s
        next unless uuid.match?(UUID_V4)
        next if existing_uuids.include?(uuid)

        first_rlink = Array(res["rlinks"]).first || {}
        title = res["title"].presence || "Imported resource #{uuid.first(8)}"

        cdef.back_matter_resources.create!(
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

      updated_metadata = cdef.import_metadata.dup
      updated_metadata.delete("back_matter")
      cdef.update_columns(import_metadata: updated_metadata)

      AuditEvent.log(
        user: nil,
        action: "cdef_back_matter_promoted",
        subject: cdef,
        metadata: { promoted_count: promoted }
      )
    end
  end

  def down
    # One-way: the legacy stash is lossy compared to the promoted rows
    # (no source tracking, no organization scoping, no audit log).
    # Rolling back would discard the audit trail of the promotion.
    raise ActiveRecord::IrreversibleMigration
  end
end
