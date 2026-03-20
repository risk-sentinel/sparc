require "rails_helper"

RSpec.describe CatalogImportValidationService do
  let(:catalog) { create(:control_catalog, name: "NIST SP 800-53 Rev 5", oscal_version: "1.1.2") }
  let(:family) { create(:control_family, control_catalog: catalog, code: "AC", name: "Access Control") }
  let(:service) { described_class.new(catalog) }

  describe "#validate" do
    context "with a clean catalog (all data present)" do
      before do
        create(:catalog_control,
          control_family: family,
          control_id: "ac-1",
          priority: "P1",
          baseline_impact: "LOW, MODERATE, HIGH",
          guidance_data: { "statement" => "The organization...", "assessment_objective" => "Determine if..." })
      end

      it "returns no warnings" do
        result = service.validate
        expect(result["import_warnings"]).to be_empty
      end

      it "returns a summary with zero totals" do
        result = service.validate
        expect(result["import_warnings_summary"]["total_warnings"]).to eq(0)
      end
    end

    context "missing priorities" do
      before do
        create(:catalog_control, control_family: family, control_id: "ac-1", priority: nil,
          baseline_impact: "LOW", guidance_data: { "statement" => "text", "assessment_objective" => "obj" })
        create(:catalog_control, control_family: family, control_id: "ac-2", priority: "",
          baseline_impact: "LOW", guidance_data: { "statement" => "text", "assessment_objective" => "obj" })
        create(:catalog_control, control_family: family, control_id: "ac-3", priority: "P1",
          baseline_impact: "LOW", guidance_data: { "statement" => "text", "assessment_objective" => "obj" })
      end

      it "flags base controls with nil or blank priority" do
        result = service.validate
        warning = result["import_warnings"].find { |w| w["category"] == "missing_priority" }
        expect(warning).to be_present
        expect(warning["count"]).to eq(2)
        expect(warning["control_ids"]).to contain_exactly("ac-1", "ac-2")
        expect(warning["severity"]).to eq("warning")
      end
    end

    context "enhancements excluded from priority check" do
      before do
        create(:catalog_control, control_family: family, control_id: "ac-2", priority: "P1",
          baseline_impact: "LOW", guidance_data: { "statement" => "text", "assessment_objective" => "obj" })
        # Enhancement — should NOT be flagged for missing priority
        create(:catalog_control, control_family: family, control_id: "ac-2.1", priority: nil,
          baseline_impact: "LOW", guidance_data: { "statement" => "text", "assessment_objective" => "obj" })
      end

      it "does not flag enhancements for missing priority" do
        result = service.validate
        priority_warning = result["import_warnings"].find { |w| w["category"] == "missing_priority" }
        expect(priority_warning).to be_nil
      end
    end

    context "sub-parts excluded from all checks" do
      before do
        create(:catalog_control, control_family: family, control_id: "ac-1", priority: "P1",
          baseline_impact: "LOW", guidance_data: { "statement" => "text", "assessment_objective" => "obj" })
        # Sub-parts — should NOT be flagged
        create(:catalog_control, control_family: family, control_id: "ac-1a", priority: nil,
          baseline_impact: nil, guidance_data: {})
        create(:catalog_control, control_family: family, control_id: "ac-1a.1", priority: nil,
          baseline_impact: nil, guidance_data: {})
      end

      it "does not flag sub-parts in any check" do
        result = service.validate
        expect(result["import_warnings"]).to be_empty
      end
    end

    context "missing baselines" do
      before do
        create(:catalog_control, control_family: family, control_id: "ac-1", priority: "P1",
          baseline_impact: nil, guidance_data: { "statement" => "text", "assessment_objective" => "obj" })
        create(:catalog_control, control_family: family, control_id: "ac-2", priority: "P1",
          baseline_impact: "", guidance_data: { "statement" => "text", "assessment_objective" => "obj" })
      end

      it "flags controls with nil or blank baseline_impact" do
        result = service.validate
        warning = result["import_warnings"].find { |w| w["category"] == "missing_baseline" }
        expect(warning).to be_present
        expect(warning["count"]).to eq(2)
        expect(warning["severity"]).to eq("warning")
      end
    end

    context "missing statements" do
      before do
        create(:catalog_control, control_family: family, control_id: "ac-1", priority: "P1",
          baseline_impact: "LOW", guidance_data: nil)
        create(:catalog_control, control_family: family, control_id: "ac-2", priority: "P1",
          baseline_impact: "LOW", guidance_data: {})
        create(:catalog_control, control_family: family, control_id: "ac-3", priority: "P1",
          baseline_impact: "LOW", guidance_data: { "statement" => "" })
      end

      it "flags controls with missing or empty statement in guidance_data" do
        result = service.validate
        warning = result["import_warnings"].find { |w| w["category"] == "missing_statement" }
        expect(warning).to be_present
        expect(warning["count"]).to eq(3)
        expect(warning["severity"]).to eq("warning")
      end
    end

    context "missing assessment objectives (Rev 5 only)" do
      before do
        create(:catalog_control, control_family: family, control_id: "ac-1", priority: "P1",
          baseline_impact: "LOW", guidance_data: { "statement" => "text" })
      end

      it "flags base controls missing assessment_objective for Rev 5 catalogs" do
        result = service.validate
        warning = result["import_warnings"].find { |w| w["category"] == "missing_assessment_objective" }
        expect(warning).to be_present
        expect(warning["count"]).to eq(1)
        expect(warning["severity"]).to eq("info")
      end

      it "does not flag for Rev 4 catalogs" do
        catalog.update!(name: "NIST SP 800-53 Rev 4", oscal_version: "1.0.0")
        result = service.validate
        warning = result["import_warnings"].find { |w| w["category"] == "missing_assessment_objective" }
        expect(warning).to be_nil
      end
    end

    context "empty families" do
      let!(:empty_family) { create(:control_family, control_catalog: catalog, code: "AU", name: "Audit") }

      before do
        create(:catalog_control, control_family: family, control_id: "ac-1", priority: "P1",
          baseline_impact: "LOW", guidance_data: { "statement" => "text", "assessment_objective" => "obj" })
      end

      it "flags families with zero controls" do
        result = service.validate
        warning = result["import_warnings"].find { |w| w["category"] == "empty_family" }
        expect(warning).to be_present
        expect(warning["control_ids"]).to include("AU")
        expect(warning["severity"]).to eq("info")
      end
    end

    context "warning structure" do
      before do
        create(:catalog_control, control_family: family, control_id: "ac-1", priority: nil,
          baseline_impact: nil, guidance_data: nil)
      end

      it "includes all required keys in each warning" do
        result = service.validate
        result["import_warnings"].each do |warning|
          expect(warning).to have_key("category")
          expect(warning).to have_key("severity")
          expect(warning).to have_key("message")
          expect(warning).to have_key("control_ids")
          expect(warning).to have_key("count")
        end
      end
    end

    context "summary aggregation" do
      before do
        create(:catalog_control, control_family: family, control_id: "ac-1", priority: nil,
          baseline_impact: nil, guidance_data: nil)
      end

      it "aggregates summary by severity" do
        result = service.validate
        summary = result["import_warnings_summary"]
        expect(summary["total_warnings"]).to be > 0
        expect(summary["by_severity"]).to be_a(Hash)
        expect(summary["total_affected"]).to be > 0
      end
    end

    context "control ID truncation for large catalogs" do
      before do
        # Create 60 controls missing priority
        60.times do |i|
          create(:catalog_control, control_family: family, control_id: "ac-#{i + 1}", priority: nil,
            baseline_impact: "LOW", guidance_data: { "statement" => "text", "assessment_objective" => "obj" })
        end
      end

      it "truncates control_ids to 50 and notes the total in the message" do
        result = service.validate
        warning = result["import_warnings"].find { |w| w["category"] == "missing_priority" }
        expect(warning["control_ids"].size).to eq(50)
        expect(warning["count"]).to eq(60)
        expect(warning["message"]).to include("showing first 50 of 60")
      end
    end
  end
end
