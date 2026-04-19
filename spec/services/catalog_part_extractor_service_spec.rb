require "rails_helper"

RSpec.describe CatalogPartExtractorService do
  let(:catalog_json) do
    {
      "catalog" => {
        "groups" => [
          {
            "id" => "ac",
            "controls" => [
              {
                "id" => "ac-1",
                "title" => "Access Control Policy",
                "parts" => [
                  {
                    "id" => "ac-1_smt",
                    "name" => "statement",
                    "parts" => [
                      { "id" => "ac-1_smt.a", "name" => "statement",
                        "props" => [ { "name" => "label", "value" => "AC-01a." } ],
                        "prose" => "Develop and document an access control policy" },
                      { "id" => "ac-1_smt.b", "name" => "statement",
                        "props" => [ { "name" => "label", "value" => "AC-01b." } ],
                        "prose" => "Disseminate the policy to organization-defined personnel" }
                    ]
                  },
                  { "id" => "ac-1_obj", "name" => "assessment-objective",
                    "prose" => "Determine if the policy is adequate" }
                ]
              }
            ]
          }
        ]
      }
    }
  end

  describe ".parts_for_control" do
    it "extracts statement parts with labels and prose" do
      parts = described_class.parts_for_control(catalog_json, "ac-1")
      # The wrapper (ac-1_smt) plus its two children (a, b)
      expect(parts.map { |p| p[:part_id] }).to eq(%w[ac-1_smt ac-1_smt.a ac-1_smt.b])
      child = parts.find { |p| p[:part_id] == "ac-1_smt.a" }
      expect(child[:label]).to eq("AC-01a.")
      expect(child[:prose]).to start_with("Develop")
      expect(child[:parent_part_id]).to eq("ac-1_smt")
    end

    it "filters by part_names" do
      objs = described_class.parts_for_control(catalog_json, "ac-1", part_names: %w[assessment-objective])
      expect(objs.size).to eq(1)
      expect(objs.first[:part_id]).to eq("ac-1_obj")
    end

    it "returns [] when control_id missing" do
      expect(described_class.parts_for_control(catalog_json, "zz-99")).to eq([])
    end

    it "returns [] for blank input" do
      expect(described_class.parts_for_control(nil, "ac-1")).to eq([])
      expect(described_class.parts_for_control({}, nil)).to eq([])
    end
  end

  describe "#backfill_ssp_statements!" do
    let(:catalog) { create(:control_catalog) }
    let(:profile) do
      create(:profile_document, control_catalog: catalog, resolved_catalog_json: catalog_json)
    end
    let(:ssp) { create(:ssp_document, profile_document: profile) }
    let!(:control) { create(:ssp_control, ssp_document: ssp, control_id: "ac-1") }

    it "creates ssp_control_statements with deterministic UUIDs (#397 contract)" do
      count = described_class.new(ssp).backfill_ssp_statements!
      expect(count).to eq(3)

      statements = control.ssp_control_statements.order(:row_order)
      expect(statements.map(&:statement_id)).to eq(%w[ac-1_smt ac-1_smt.a ac-1_smt.b])

      # UUID stability invariant: backfilled UUID == derived(control.uuid, "ssp-statement", part_id)
      child = statements.find { |s| s.statement_id == "ac-1_smt.a" }
      expected = OscalUuidService.derived(control.uuid, "ssp-statement", "ac-1_smt.a")
      expect(child.uuid).to eq(expected)
    end

    it "is idempotent (skips controls that already have statements)" do
      described_class.new(ssp).backfill_ssp_statements!
      count = described_class.new(ssp).backfill_ssp_statements!
      expect(count).to eq(0)
    end

    it "flags the document for reassociation when no profile is linked" do
      orphan = create(:ssp_document, profile_document: nil)
      described_class.new(orphan).backfill_ssp_statements!
      expect(orphan.reload.import_metadata[CatalogPartExtractorService::REASSOCIATION_FLAG])
        .to eq(CatalogPartExtractorService::REASSOCIATION_VALUE)
    end
  end
end
