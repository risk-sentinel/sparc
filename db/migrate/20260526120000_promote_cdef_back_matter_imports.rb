# #498 slice 3 — promote previously-imported CDEF back-matter from
# the legacy `import_metadata["back_matter"]` stash into first-class
# BackMatterResource rows (source: "imported").
#
# v1.8.2 idempotency fix: back_matter_resources.uuid has a GLOBAL
# unique index. The original v1.8.0 implementation stored the OSCAL
# source uuid as BMR.uuid directly, which crashed when two CDEFs
# referenced the same source uuid. Now: every BMR gets a fresh uuid
# and the source is preserved in resource_data['source_uuid']
# (matches the SAR cross-doc copy pattern). Per-doc dedup checks
# BOTH the legacy uuid column (for v1.8.0 imports that succeeded)
# and the new source_uuid metadata key (for v1.8.2 imports), so a
# resume from a partially-failed v1.8.1 deploy picks up cleanly.
class PromoteCdefBackMatterImports < ActiveRecord::Migration[8.1]
  UUID_V4 = /\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i

  def up
    CdefDocument.find_each do |cdef|
      resources = cdef.import_metadata&.dig("back_matter")
      next if resources.blank?

      promoted = 0

      Array(resources).each do |res|
        source_uuid = res["uuid"].to_s
        next unless source_uuid.match?(UUID_V4)
        next if already_promoted_for?(cdef, source_uuid)

        first_rlink = Array(res["rlinks"]).first || {}
        title = res["title"].presence || "Imported resource #{source_uuid.first(8)}"

        cdef.back_matter_resources.create!(
          uuid:          SecureRandom.uuid,
          title:         title,
          description:   res["description"],
          href:          first_rlink["href"],
          media_type:    first_rlink["media-type"],
          rel:           "reference",
          source:        "imported",
          resource_data: res.except("uuid", "title", "description", "rlinks")
                            .merge("source_uuid" => source_uuid)
        )
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

  private

  # Has this CDEF already had a BMR promoted for the given source
  # OSCAL uuid? Matches both pre-v1.8.2 imports (uuid == source uuid)
  # and v1.8.2+ imports (resource_data['source_uuid'] == source uuid).
  def already_promoted_for?(cdef, source_uuid)
    cdef.back_matter_resources
        .where("back_matter_resources.uuid = :u OR back_matter_resources.resource_data ->> 'source_uuid' = :u",
               u: source_uuid)
        .exists?
  end
end
