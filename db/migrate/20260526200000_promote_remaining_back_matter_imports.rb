# #583 — promote previously-imported back-matter from the legacy
# `import_metadata["back_matter"]` stash to first-class
# BackMatterResource rows for SspDocument, SarDocument, SapDocument,
# ProfileDocument, and PoamDocument. CDEF was handled in the v1.8.0
# CDEF-specific migration; this completes the sweep so
# BackMatterBuilder#deduplicated_imports can be deleted.
#
# v1.8.2 idempotency fix: the original v1.8.0 implementation stored
# the OSCAL source uuid as BMR.uuid directly. back_matter_resources.uuid
# has a GLOBAL unique index, so two docs that legitimately referenced
# the same source uuid (very common across SSP + SAR + SAP for shared
# NIST references) crashed the second doc and killed the deploy.
# Now: every BMR gets a fresh uuid; source is preserved in
# resource_data['source_uuid'] (matches the SAR cross-doc copy
# pattern). Per-doc dedup checks BOTH the legacy uuid column (for
# v1.8.0 imports that succeeded) and the new source_uuid metadata
# key (for v1.8.2 imports), so resume from a partially-failed v1.8.1
# attempt picks up cleanly.
class PromoteRemainingBackMatterImports < ActiveRecord::Migration[8.1]
  # v1.8.3 — deferred. Same rationale as PromoteCdefBackMatterImports.
  # Sequenced across 5 doc types; can run for many minutes on a
  # large fleet. Running in-band would block the container from
  # binding the port → ECS health check fails. Now runs post-boot
  # via DeferredDataMigrationJob with the container already up.
  include DeferredDataMigration

  UUID_V4 = /\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i

  DOC_TYPES = [
    [ SspDocument, "ssp_back_matter_promoted" ],
    [ SarDocument, "sar_back_matter_promoted" ],
    [ SapDocument, "sap_back_matter_promoted" ],
    [ ProfileDocument, "profile_back_matter_promoted" ],
    [ PoamDocument, "poam_back_matter_promoted" ]
  ].freeze

  def up
    defer_data_migration do
      promote_all_doc_types
    end
  end

  def promote_all_doc_types
    DOC_TYPES.each do |klass, _action|
      klass.find_each do |doc|
        resources = doc.import_metadata&.dig("back_matter")
        next if resources.blank?

        promoted = 0

        Array(resources).each do |res|
          source_uuid = res["uuid"].to_s
          next unless source_uuid.match?(UUID_V4)
          next if already_promoted_for?(doc, source_uuid)

          first_rlink = Array(res["rlinks"]).first || {}
          title = res["title"].presence || "Imported resource #{source_uuid.first(8)}"

          doc.back_matter_resources.create!(
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

  private

  # Has this document already had a BMR promoted for the given
  # source OSCAL uuid? Matches both pre-v1.8.2 imports (uuid ==
  # source uuid) and v1.8.2+ imports (resource_data['source_uuid']).
  def already_promoted_for?(doc, source_uuid)
    doc.back_matter_resources
       .where("back_matter_resources.uuid = :u OR back_matter_resources.resource_data ->> 'source_uuid' = :u",
              u: source_uuid)
       .exists?
  end
end
