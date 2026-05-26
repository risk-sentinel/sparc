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
module BackMatterPromotable
  extend ActiveSupport::Concern

  V4_UUID_RE = /\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i

  private

  def promote_back_matter_resources(resources)
    return if resources.blank?

    batch_uuid = SecureRandom.uuid

    Array(resources).each do |res|
      uuid = res["uuid"].to_s
      next unless uuid.match?(V4_UUID_RE)

      first_rlink = Array(res["rlinks"]).first || {}
      title = res["title"].presence || "Imported resource #{uuid.first(8)}"

      bmr = @document.back_matter_resources.create!(
        uuid:          uuid,
        title:         title,
        description:   res["description"],
        href:          first_rlink["href"],
        media_type:    first_rlink["media-type"],
        rel:           "reference",
        source:        "imported",
        resource_data: res.except("uuid", "title", "description", "rlinks")
      )
      BackMatterAudit.record_create(bmr, batch_uuid: batch_uuid)
    end
  end
end
