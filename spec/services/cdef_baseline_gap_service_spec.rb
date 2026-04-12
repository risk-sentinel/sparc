require "rails_helper"

RSpec.describe CdefBaselineGapService, type: :service do
  let(:catalog) { create(:control_catalog) }
  let(:profile) do
    create(:profile_document,
           control_catalog: catalog,
           lifecycle_status: "published",
           resolved_catalog_json: resolved_catalog)
  end

  let(:resolved_catalog) do
    {
      "catalog" => {
        "metadata" => { "title" => "Test Catalog" },
        "groups" => [
          {
            "id" => "ac",
            "controls" => [
              { "id" => "ac-1", "title" => "Access Control Policy" },
              { "id" => "ac-2", "title" => "Account Management" },
              { "id" => "ac-3", "title" => "Access Enforcement" }
            ]
          }
        ]
      }
    }
  end

  describe "#analyze" do
    context "when CDEF has all baseline controls" do
      let(:cdef) do
        doc = create(:cdef_document, profile_document: profile)
        create(:cdef_control, cdef_document: doc, control_id: "ac-1")
        create(:cdef_control, cdef_document: doc, control_id: "ac-2")
        create(:cdef_control, cdef_document: doc, control_id: "ac-3")
        doc
      end

      it "returns 100% coverage" do
        result = described_class.new(cdef).analyze
        expect(result[:coverage_pct]).to eq(100.0)
        expect(result[:missing]).to be_empty
        expect(result[:covered]).to eq(%w[ac-1 ac-2 ac-3])
      end
    end

    context "when CDEF is missing controls" do
      let(:cdef) do
        doc = create(:cdef_document, profile_document: profile)
        create(:cdef_control, cdef_document: doc, control_id: "ac-1")
        doc
      end

      it "identifies missing controls" do
        result = described_class.new(cdef).analyze
        expect(result[:coverage_pct]).to eq(33.3)
        expect(result[:missing]).to eq(%w[ac-2 ac-3])
        expect(result[:covered]).to eq(%w[ac-1])
      end
    end

    context "when CDEF has extra controls beyond baseline" do
      let(:cdef) do
        doc = create(:cdef_document, profile_document: profile)
        create(:cdef_control, cdef_document: doc, control_id: "ac-1")
        create(:cdef_control, cdef_document: doc, control_id: "ac-2")
        create(:cdef_control, cdef_document: doc, control_id: "ac-3")
        create(:cdef_control, cdef_document: doc, control_id: "cm-1")
        doc
      end

      it "identifies extra controls" do
        result = described_class.new(cdef).analyze
        expect(result[:coverage_pct]).to eq(100.0)
        expect(result[:extra]).to eq(%w[cm-1])
      end
    end

    context "when no profile is linked" do
      let(:cdef) { create(:cdef_document, profile_document: nil) }

      it "returns nil" do
        expect(described_class.new(cdef).analyze).to be_nil
      end
    end
  end

  describe "#missing_control_details" do
    let(:cdef) do
      doc = create(:cdef_document, profile_document: profile)
      create(:cdef_control, cdef_document: doc, control_id: "ac-1")
      doc
    end

    it "returns missing controls with titles" do
      details = described_class.new(cdef).missing_control_details
      expect(details.length).to eq(2)
      expect(details.first).to eq({ id: "ac-2", title: "Account Management" })
      expect(details.last).to eq({ id: "ac-3", title: "Access Enforcement" })
    end
  end
end
