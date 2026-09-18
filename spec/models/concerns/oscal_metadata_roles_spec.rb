# frozen_string_literal: true

require "rails_helper"

# #1116 — a latent completeness bug found while planning the roles surface.
#
# `build_oscal_metadata` merged metadata_extra ALL-OR-NOTHING:
#
#     extra = (metadata_extra || {}).slice(*METADATA_EXTRA_KEYS)
#     if extra.any?
#       merged = base.merge(extra)          # <- defaults never applied
#     else
#       …apply default_roles / default_parties…
#     end
#
# METADATA_EXTRA_KEYS is `roles parties responsible-parties revisions props
# links document-ids locations remarks`. So a document that set ANY one of them
# — a party, a link, a remark — silently lost the role defaults and exported
# with NO roles at all. Every `role-id` in it then resolved to nothing.
#
# Schema validation cannot see this. The document is structurally perfect and
# refers to nothing, which is exactly the class of defect #1106 is about.
RSpec.describe OscalMetadata, "role and party defaults" do
  let(:boundary) { create(:authorization_boundary) }
  let(:ssp)      { create(:ssp_document, authorization_boundary: boundary) }

  def exported_metadata
    JSON.parse(OscalSspExportService.new(ssp.reload).export_unvalidated)
        .dig("system-security-plan", "metadata")
  end

  it "declares roles when no other metadata is set" do
    expect(exported_metadata["roles"]).to be_present
  end

  # The regression. Setting ONE unrelated key must not erase another.
  it "still declares roles when an unrelated metadata key is set" do
    ssp.update!(metadata_extra: { "remarks" => "Reviewed by the ISSO." })

    metadata = exported_metadata

    expect(metadata["remarks"]).to eq("Reviewed by the ISSO.")
    expect(metadata["roles"]).to be_present,
      "setting `remarks` must not silently drop the role declarations — every role-id would dangle"
  end

  it "still declares roles when parties are set, and keeps the authored parties" do
    ssp.update!(metadata_extra: {
                  "parties" => [ { "uuid" => "11111111-1111-4111-8111-111111111111",
                                   "type" => "organization", "name" => "ACME" } ]
                })

    metadata = exported_metadata

    expect(metadata.dig("parties", 0, "name")).to eq("ACME")
    expect(metadata["roles"]).to be_present
  end

  # Authored values must still WIN over defaults — this fix merges defaults
  # under the authored data, it does not override it.
  it "lets an authored roles list override the defaults entirely" do
    ssp.update!(metadata_extra: {
                  "roles" => [ { "id" => "policy-department", "title" => "Policy Department" } ]
                })

    expect(exported_metadata["roles"]).to eq(
      [ { "id" => "policy-department", "title" => "Policy Department" } ]
    )
  end

  # The whole point of declaring them: the export must be referentially sound.
  it "produces a document whose role-ids all resolve" do
    ssp.update!(metadata_extra: { "remarks" => "anything" })
    json = JSON.parse(OscalSspExportService.new(ssp.reload).export_unvalidated)

    result = OscalConformanceService.new(json, model: "system-security-plan").validate
    unresolved = result.violations.select { |v| v.rule == "role-id-unresolved" }

    expect(unresolved).to be_empty, -> { unresolved.map(&:message).join("\n") }
  end
end
