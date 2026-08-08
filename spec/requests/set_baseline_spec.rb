# frozen_string_literal: true

require "rails_helper"

# #911 layer 2 — the write the reconciliation gate exists to provoke.
#
# The gate refuses to update a document that cannot name the catalog its
# controls descend from. That is only fair if the remedy is reachable from the
# UI. Before this it was not: `profile_document_id` was settable on an SSP only
# through the CREATION wizard, and the CDEF and profile controllers never
# referenced their lineage FK at all — so a legacy document of those types would
# have been refused an edit with no way to satisfy the refusal.
#
# This action is therefore deliberately NOT gated.
RSpec.describe "Declaring a document's baseline", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:catalog) { create(:control_catalog) }
  let(:profile) { create(:profile_document, control_catalog: catalog) }

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    sign_in_as(admin)
  end

  describe "an SSP with no imported profile" do
    # Claims a control, so the gate genuinely applies to it — a document with no
    # controls has nothing to trace and is left alone (catalog_lineage_spec).
    # Without a control here, the "reachable even though unreconciled" example
    # would pass vacuously against a document that was never gated.
    let(:ssp) do
      create(:ssp_document, profile_document: nil).tap do |doc|
        create(:ssp_control, ssp_document: doc, control_id: "ac-1")
      end
    end

    it "accepts the baseline and resolves the document" do
      patch set_baseline_ssp_document_path(ssp),
            params: { ssp_document: { profile_document_id: profile.id } }

      expect(ssp.reload.profile_document).to eq(profile)
      expect(ssp).to be_lineage_resolved
    end

    it "is reachable even though the document is unreconciled" do
      # If the gate covered this action, the remedy would be unreachable and
      # the document uneditable forever.
      expect(ssp.reconciliation_blocks_update?).to be(true)

      patch set_baseline_ssp_document_path(ssp),
            params: { ssp_document: { profile_document_id: profile.id } }

      expect(response).not_to have_http_status(:unprocessable_entity)
      expect(ssp.reload).to be_lineage_resolved
    end

    it "refuses an empty selection rather than silently doing nothing" do
      patch set_baseline_ssp_document_path(ssp),
            params: { ssp_document: { profile_document_id: "" } }

      expect(ssp.reload.profile_document).to be_nil
      follow_redirect!
      expect(response.body).to include("Choose a baseline")
    end

    it "records who declared it" do
      expect {
        patch set_baseline_ssp_document_path(ssp),
              params: { ssp_document: { profile_document_id: profile.id } }
      }.to change { AuditEvent.where(action: "ssp_document_baseline_declared").count }.by(1)
    end
  end

  # The three types that had NO path at all before this.
  describe "the types that previously had no remedy" do
    it "sets a CDEF's profile" do
      cdef = create(:cdef_document, profile_document: nil)

      patch set_baseline_cdef_document_path(cdef),
            params: { cdef_document: { profile_document_id: profile.id } }

      expect(cdef.reload.profile_document).to eq(profile)
    end

    it "sets a profile's catalog" do
      orphan = create(:profile_document, control_catalog: nil)

      patch set_baseline_profile_document_path(orphan),
            params: { profile_document: { control_catalog_id: catalog.id } }

      expect(orphan.reload.control_catalog).to eq(catalog)
    end
  end

  # Each type accepts exactly the FKs its own lineage declares, and nothing
  # else — the action reads `lineage_attribute_names` rather than a hand-kept
  # permit list that could drift from the declarations.
  describe "permitted attributes follow the lineage declaration" do
    it "sets a SAP's SSP" do
      sap = create(:sap_document, ssp_document: nil)
      ssp = create(:ssp_document, profile_document: profile)

      patch set_baseline_sap_document_path(sap),
            params: { sap_document: { ssp_document_id: ssp.id } }

      expect(sap.reload.ssp_document).to eq(ssp)
    end

    it "ignores an attribute that is not part of this type's lineage" do
      cdef = create(:cdef_document, profile_document: nil)

      patch set_baseline_cdef_document_path(cdef),
            params: { cdef_document: { profile_document_id: profile.id, name: "Renamed" } }

      expect(cdef.reload.profile_document).to eq(profile)
      expect(cdef.name).not_to eq("Renamed"), "set_baseline must not double as a general edit"
    end
  end
end
