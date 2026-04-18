require "rails_helper"

RSpec.describe BoundaryLinkInheritance do
  describe "SapDocument with boundary that has an SSP" do
    let(:profile)  { create(:profile_document) }
    let(:ssp)      { create(:ssp_document, profile_document: profile) }
    let(:boundary) { create(:authorization_boundary).tap { |b| ssp.update!(authorization_boundary: b) } }

    it "auto-fills ssp_document_id from the boundary's SSP" do
      sap = SapDocument.new(name: "FY26 SAP", authorization_boundary: boundary)
      sap.valid?
      expect(sap.ssp_document_id).to eq(ssp.id)
    end

    it "auto-fills profile_document_id from the boundary's SSP's profile" do
      sap = SapDocument.new(name: "FY26 SAP", authorization_boundary: boundary)
      sap.valid?
      expect(sap.profile_document_id).to eq(profile.id)
    end

    it "does not overwrite an explicit user-supplied ssp_document_id" do
      other_ssp = create(:ssp_document)
      sap = SapDocument.new(name: "FY26 SAP",
                            authorization_boundary: boundary,
                            ssp_document_id: other_ssp.id)
      sap.valid?
      expect(sap.ssp_document_id).to eq(other_ssp.id)
    end

    it "is a no-op when authorization_boundary_id is blank" do
      sap = SapDocument.new(name: "FY26 SAP")
      sap.valid?
      expect(sap.ssp_document_id).to be_nil
      expect(sap.profile_document_id).to be_nil
    end

    it "tolerates a boundary without an SSP" do
      empty_boundary = create(:authorization_boundary)
      sap = SapDocument.new(name: "FY26 SAP", authorization_boundary: empty_boundary)
      expect { sap.valid? }.not_to raise_error
      expect(sap.ssp_document_id).to be_nil
    end
  end

  describe "SarDocument with boundary that has SSP and SAP" do
    let(:ssp)      { create(:ssp_document) }
    let(:sap)      { create(:sap_document, ssp_document: ssp) }
    let(:boundary) do
      b = create(:authorization_boundary)
      ssp.update!(authorization_boundary: b)
      sap.update!(authorization_boundary: b)
      b
    end

    it "auto-fills both ssp_document_id and sap_document_id" do
      sar = SarDocument.new(name: "FY26 SAR", authorization_boundary: boundary)
      sar.valid?
      expect(sar.ssp_document_id).to eq(ssp.id)
      expect(sar.sap_document_id).to eq(sap.id)
    end
  end
end
