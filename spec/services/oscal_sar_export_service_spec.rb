require "rails_helper"

RSpec.describe OscalSarExportService do
  let(:document) { create(:sar_document, :enriched) }
  let(:result) { create(:sar_result, sar_document: document) }
  let(:sar_control) { create(:sar_control, sar_document: document, control_id: "ac-1") }
  let(:objective) do
    create(:sar_control_objective, sar_control: sar_control,
                                   objective_id: "ac-1_obj.a-1",
                                   label: "AC-01a.[01]")
  end

  subject { described_class.new(document) }

  # #989 — the SAR's validated path had no coverage at all. The lazy lets are
  # forced: an assessment result with no findings or objectives is not the
  # document the rest of this file is about.
  it_behaves_like "an OSCAL export with validated and unvalidated paths",
                  model_type: :assessment_results,
                  service: lambda {
                    # Validated export additionally refuses a document citing a
                    # control that exists in no loaded catalog (#911), which is a
                    # different failure from the one under test.
                    ensure_control("ac-1")
                    result; sar_control; objective
                    described_class.new(document)
                  }

  it_behaves_like "produces stable UUIDs across exports"

  describe "#export_unvalidated -- finding target with linked objective" do
    it "emits target.type='objective-id' when finding has sar_control_objective" do
      finding = create(:sar_finding, sar_result: result,
                                     sar_control_objective: objective,
                                     target_data: { "type" => "control", "target-id" => "ac-1",
                                                    "status" => { "state" => "not-satisfied" } })

      data = JSON.parse(subject.export_unvalidated)
      results = data["assessment-results"]["results"]
      exported_finding = results.flat_map { |r| r["findings"] || [] }
                                .find { |f| f["uuid"] == finding.uuid }

      expect(exported_finding["target"]["type"]).to eq("objective-id")
      expect(exported_finding["target"]["target-id"]).to eq("ac-1_obj.a-1")
    end

    it "preserves status state from target_data" do
      create(:sar_finding, sar_result: result,
                           sar_control_objective: objective,
                           target_data: { "type" => "control", "target-id" => "ac-1",
                                          "status" => { "state" => "not-satisfied" } })
      data = JSON.parse(subject.export_unvalidated)
      finding = data["assessment-results"]["results"].flat_map { |r| r["findings"] || [] }.first
      expect(finding["target"]["status"]).to eq({ "state" => "not-satisfied" })
    end

    it "strips the internal needs_objective_link flag from exported target" do
      create(:sar_finding, sar_result: result,
                           target_data: { "type" => "objective-id", "target-id" => "ac-1_obj.a-1",
                                          "needs_objective_link" => true })
      data = JSON.parse(subject.export_unvalidated)
      finding = data["assessment-results"]["results"].flat_map { |r| r["findings"] || [] }.first
      expect(finding["target"]).not_to have_key("needs_objective_link")
    end

    it "leaves target alone when no objective is linked" do
      create(:sar_finding, sar_result: result,
                           sar_control_objective: nil,
                           target_data: { "type" => "control", "target-id" => "ac-2" })
      data = JSON.parse(subject.export_unvalidated)
      finding = data["assessment-results"]["results"].flat_map { |r| r["findings"] || [] }.first
      expect(finding["target"]["type"]).to eq("control")
      expect(finding["target"]["target-id"]).to eq("ac-2")
    end
  end
end
