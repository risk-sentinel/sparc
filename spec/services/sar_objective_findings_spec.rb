# frozen_string_literal: true

require "rails_helper"

# #1114 — an assessment result targets the 800-53A OBJECTIVE, in NIST's words.
#
# From the baked-in OSCAL v1.2.2 assessment-results schema:
#
#   finding                REQUIRED uuid, title, description, target
#   finding.target         REQUIRED type, target-id, status
#   finding.target.type    enum: statement-id | objective-id
#   finding.target.status  REQUIRED state
#   status.state           enum: satisfied | not-satisfied
#
# The exporter declared `"type" => "objective-id"` and passed a CONTROL id as the
# target. `objective-id` must reference an assessment objective (`ac-1_obj.a-1`);
# `ac-1` is not one. The schema cannot catch it — both are strings — so the
# document was valid and false.
#
# It also flattened the assessment: NIST divides ac-1 into 24 determination
# statements, and one Pass/Failed for the whole control asserts more than an
# assessor found.
RSpec.describe "SAR findings target 800-53A objectives (#1114)" do
  let(:document) { create(:sar_document) }
  let!(:control) { document.sar_controls.create!(control_id: "ac-1", title: "Policy", row_order: 0) }

  def objective(id, status, label: nil, prose: nil)
    control.sar_control_objectives.create!(
      objective_id: id, label: label, prose: prose, status: status,
      row_order: 0, uuid: SecureRandom.uuid
    )
  end

  def exported
    raw = OscalSarExportService.new(document.reload).export_unvalidated
    (raw.is_a?(String) ? JSON.parse(raw) : raw.deep_stringify_keys)
  end

  def findings
    Array(exported.dig("assessment-results", "results")).flat_map { |r| Array(r["findings"]) }
  end

  describe "with determinations recorded" do
    before do
      objective("ac-1_obj.a-1", "passing", label: "AC-01a.[01]", prose: "a policy is developed")
      objective("ac-1_obj.a-2", "failed",  label: "AC-01a.[02]", prose: "the policy is disseminated")
    end

    it "emits one finding per determined objective" do
      targets = findings.map { |f| f.dig("target", "target-id") }

      expect(targets).to include("ac-1_obj.a-1", "ac-1_obj.a-2")
    end

    it "names the target as an objective-id, and means it" do
      f = findings.find { |x| x.dig("target", "target-id") == "ac-1_obj.a-1" }

      expect(f.dig("target", "type")).to eq("objective-id")
      expect(f.dig("target", "target-id")).to start_with("ac-1_obj"),
        "an objective-id target must reference an objective, not a control"
    end

    # The only two values the format allows.
    it "uses NIST's determination vocabulary, not SPARC's workflow ladder" do
      states = findings.map { |f| f.dig("target", "status", "state") }.uniq

      expect(states).to all(be_in(%w[satisfied not-satisfied]))
      by_target = findings.to_h { |f| [ f.dig("target", "target-id"), f.dig("target", "status", "state") ] }
      expect(by_target["ac-1_obj.a-1"]).to eq("satisfied")
      expect(by_target["ac-1_obj.a-2"]).to eq("not-satisfied")
    end

    it "does not also emit the old control-level finding" do
      expect(findings.map { |f| f.dig("target", "target-id") }).not_to include("ac-01")
    end
  end

  # The most important example here. OSCAL has no "unknown" state, so an
  # objective nobody has assessed must produce NO finding — emitting one would
  # assert assurance that was never established.
  describe "with objectives still unassessed" do
    before do
      objective("ac-1_obj.a-1", "pending")
      objective("ac-1_obj.a-2", "in-progress")
      objective("ac-1_obj.a-3", "not_applicable")
    end

    it "emits no objective finding for them" do
      objective_targets = findings.select { |f| f.dig("target", "type") == "objective-id" }
      expect(objective_targets).to be_empty,
        "an unassessed objective must not be reported as determined"
    end

    # It still says something about the control, and labels that target
    # honestly — a control-level target is a statement-id, not an objective-id.
    it "falls back to a control-level finding, correctly typed" do
      expect(findings).not_to be_empty
      expect(findings.first.dig("target", "type")).to eq("statement-id")
    end
  end

  # The path the seeded estate actually takes: REAL findings whose imported
  # target_data claims objective-id against a control id. Measured on the demo
  # SAR — 150 findings, all 150 making that false claim.
  describe "a real finding whose imported target claims an objective it is not" do
    let!(:result) { create(:sar_result, sar_document: document) }
    let!(:finding) do
      result.sar_findings.create!(
        uuid: SecureRandom.uuid, title: "Finding for ac-1",
        description: "imported", target_data: { "type" => "objective-id", "target-id" => "ac-1" }
      )
    end

    it "downgrades the claim to statement-id rather than exporting it" do
      f = findings.find { |x| x["title"] == "Finding for ac-1" }

      expect(f.dig("target", "type")).to eq("statement-id"),
        "a control id must not be exported as an objective-id"
      expect(f.dig("target", "target-id")).to eq("ac-1")
    end

    it "keeps the claim when the target IS a real objective on this document" do
      objective("ac-1_obj.a-1", "passing")
      finding.update!(target_data: { "type" => "objective-id", "target-id" => "ac-1_obj.a-1" })

      f = findings.find { |x| x["title"] == "Finding for ac-1" }
      expect(f.dig("target", "type")).to eq("objective-id")
    end

    it "does not discard the finding — the assessment is real" do
      expect(findings.map { |x| x["title"] }).to include("Finding for ac-1")
    end
  end

  describe "with no objectives at all" do
    it "still exports a control-level finding" do
      expect(findings.size).to eq(1)
      expect(findings.first.dig("target", "type")).to eq("statement-id")
    end
  end
end
