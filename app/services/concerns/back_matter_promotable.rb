# frozen_string_literal: true

# Shared back-matter promotion logic for document parser services
# (#498 / #583). Replaces the legacy `import_metadata["back_matter"]`
# stash with first-class BackMatterResource rows so the exporter
# reads from one place (the back_matter_resources table) instead of
# merging an opaque JSON stash on every export.
#
# Usage in a parser service:
#
#   include BackMatterPromotable
#
#   def parse_oscal_*(data)
#     ...
#     promote_back_matter_resources(data.dig("back-matter", "resources"))
#   end
#
# Behavior:
#   - One BackMatterResource row per OSCAL `back-matter.resources` entry.
#   - source: "imported" (the exporter's managed_resources query
#     picks these up via the !"authoritative" filter).
#   - Skips entries without a v4 UUID (the model enforces v4 and we
#     don't want a non-conformant upstream entry to fail the whole
#     parse).
#   - Emits one BackMatterResourceChange create row per BMR under a
#     shared batch_uuid (#581) so the audit log can render the
#     parser run as one event.
#
# UUID strategy (v1.8.2 — fixes the "global uniqueness collision"
# bug that crashed v1.8.1 deploys mid-migration):
#
# The back_matter_resources.uuid column has a GLOBAL unique index.
# Two docs that legitimately reference the same OSCAL back-matter
# UUID (common when both import NIST references) cannot both store
# that UUID directly. v1.8.0/v1.8.1 did this naively → second doc
# crashed.
#
# Fix: every promoted BMR gets a fresh BMR.uuid (SecureRandom). The
# original OSCAL source UUID is preserved in
# resource_data["source_uuid"] for provenance. This matches the
# pattern already used by SAR cross-doc back-matter copying in
# sar_documents_controller#copy_back_matter_into_sar.
#
# Per-doc dedup (idempotency on re-run) checks BOTH:
#   - back_matter_resources.uuid (legacy: pre-v1.8.2 imports stored
#     source UUID as the BMR uuid)
#   - resource_data['source_uuid'] (current: post-v1.8.2 imports)
# so a resume from a partially-failed v1.8.1 attempt picks up where
# it left off without re-creating already-promoted rows.
module BackMatterPromotable
  extend ActiveSupport::Concern

  V4_UUID_RE = /\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i

  private

  def promote_back_matter_resources(resources)
    return if resources.blank?

    batch_uuid = SecureRandom.uuid

    Array(resources).each do |res|
      source_uuid = res["uuid"].to_s
      next unless source_uuid.match?(V4_UUID_RE)
      next if back_matter_already_promoted?(@document, source_uuid)

      first_rlink = Array(res["rlinks"]).first || {}
      title = res["title"].presence || "Imported resource #{source_uuid.first(8)}"

      bmr = @document.back_matter_resources.create!(
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
      BackMatterAudit.record_create(bmr, batch_uuid: batch_uuid)
    end
  end

  # Has this document already had a BMR promoted for the given
  # source OSCAL uuid? Checks both the legacy uuid column (pre-
  # v1.8.2 imports stored source uuid as BMR.uuid) and the new
  # resource_data['source_uuid'] key. Either match means "skip;
  # already done."
  def back_matter_already_promoted?(doc, source_uuid)
    doc.back_matter_resources
       .where("back_matter_resources.uuid = :u OR back_matter_resources.resource_data ->> 'source_uuid' = :u",
              u: source_uuid)
       .exists?
  end
end
