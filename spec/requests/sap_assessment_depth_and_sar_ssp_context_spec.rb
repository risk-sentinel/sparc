# frozen_string_literal: true

require "rails_helper"

# #1114 — the last two items from the owner's SAP/SAR screen review.
RSpec.describe "SAP assessment depth and SAR SSP context", type: :request do
  before { sign_in_as(create(:user, :admin)) }

  let(:catalog) { create(:control_catalog) }
  let(:family)  { create(:control_family, control_catalog: catalog, code: "AC") }
  let!(:catalog_control) do
    family.catalog_controls.create!(control_id: "ac-1", title: "Policy").tap do |cc|
      cc.catalog_control_parts.create!(
        part_id: "ac-1_asm-examine", part_name: "assessment-method", label: "AC-01-Examine",
        props_data: [ { "name" => "method", "value" => "EXAMINE" } ],
        row_order: 0, uuid: SecureRandom.uuid
      )
      cc.catalog_control_parts.create!(
        part_id: "ac-1_asm-examine_objects", part_name: "assessment-objects",
        parent_part_id: "ac-1_asm-examine",
        prose: "Access control policy and procedures; system security plan",
        row_order: 1, uuid: SecureRandom.uuid
      )
      # A method NIST defines with no objects — the case that must be CALLED OUT.
      cc.catalog_control_parts.create!(
        part_id: "ac-1_asm-interview", part_name: "assessment-method", label: "AC-01-Interview",
        props_data: [ { "name" => "method", "value" => "INTERVIEW" } ],
        row_order: 2, uuid: SecureRandom.uuid
      )
    end
  end

  # ── SAP item 1 ────────────────────────────────────────────────────────────
  # "The assessment plan should already have backmatter links for those that
  # have them and callout control parts that do not (e.g. under assessment depth
  # would be back matter reference(s) link(s))"
  describe "SAP assessment depth" do
    let(:sap) { create(:sap_document) }
    before { sap.sap_controls.create!(control_id: "ac-1", title: "Policy", row_order: 0) }

    it "shows what to examine under the method" do
      get sap_document_path(sap)

      expect(response.body).to include("Assessment Depth")
      expect(response.body).to include("Access control policy and procedures")
    end

    it "names the method itself" do
      get sap_document_path(sap)

      expect(response.body).to match(/examine/i)
    end

    # The callout. A method with no assessment objects is a GAP, and a blank row
    # hides it — the owner asked for it to be called out.
    it "calls out a method that names no assessment objects" do
      get sap_document_path(sap)

      expect(response.body).to include("No assessment objects defined")
    end
  end

  # ── SAR item 3 ────────────────────────────────────────────────────────────
  # "I would expect to see the information from the SSP populated for the
  # control's assessment context"
  describe "SAR context from the SSP" do
    let(:ssp) { create(:ssp_document) }
    let(:sar) { create(:sar_document, ssp_document: ssp) }

    before do
      ssp_control = ssp.ssp_controls.create!(control_id: "ac-1", title: "Policy")
      ssp_control.ssp_control_fields.create!(field_name: "status", field_value: "Implemented")
      ssp_control.ssp_control_fields.create!(field_name: "responsible_entities", field_value: "ISSO")
      # Per-statement claims — what #1100 made possible and what an assessor
      # actually assesses.
      ssp_control.ssp_control_statements.create!(
        statement_id: "ac-1_smt.a", label: "a.", row_order: 0, uuid: SecureRandom.uuid,
        implementation_prose: "Policy is published in Confluence and reviewed annually."
      )
      sar.sar_controls.create!(control_id: "ac-1", title: "Policy", row_order: 0)
    end

    it "shows the SSP's per-statement claims beside the assessment" do
      get sar_document_path(sar)

      expect(response.body).to include("As implemented")
      expect(response.body).to include("Policy is published in Confluence")
    end

    it "shows what the SSP declares about the control" do
      get sar_document_path(sar)

      expect(response.body).to include("Declared status")
      expect(response.body).to include("ISSO")
    end

    # Live, not copied. The enrich action snapshots a few SSP fields into
    # sar_control_fields, and that snapshot goes stale the moment the SSP is
    # edited — the dual-store trap of #1113. Editing the SSP must change what
    # this screen shows, with no re-enrich.
    it "reads the SSP live rather than a copied snapshot" do
      ssp.ssp_controls.first.ssp_control_statements.first
         .update!(implementation_prose: "Rewritten after the SSP was edited.")

      get sar_document_path(sar)

      expect(response.body).to include("Rewritten after the SSP was edited.")
      expect(response.body).not_to include("Policy is published in Confluence")
    end

    it "says nothing when the SAR has no linked SSP" do
      sar.update!(ssp_document: nil)

      get sar_document_path(sar)

      expect(response.body).not_to include("As implemented")
    end
  end
end
