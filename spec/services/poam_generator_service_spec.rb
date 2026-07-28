# frozen_string_literal: true

require "rails_helper"

# #843 — the POA&M was the one document in the authorization chain with no
# generator, so the terminal artifact of an ATO could only be imported or
# hand-assembled record by record.
#
# The rule these specs exist to defend is that NOTHING is synthesised. #832
# made PoamRisk require title/description/statement/status/deadline and
# PoamFinding require title/description/target_data precisely so invalid OSCAL
# could not be created and then fail much later at export. A generator that
# filled those in with placeholders would reintroduce that bug wholesale — and
# a risk statement, a deadline and a finding target are compliance content an
# assessor reads, not blanks to be filled.
RSpec.describe PoamGeneratorService do
  let(:profile)  { create(:profile_document, baseline_level: "High") }
  let(:boundary) { create(:authorization_boundary, profile_document: profile) }
  let(:sar)      { create(:sar_document, authorization_boundary: boundary) }
  let(:result_record) { create(:sar_result, sar_document: sar) }

  def generate(**overrides)
    described_class.new(
      name: "Generated POA&M", sar_document: sar, authorization_boundary: boundary, **overrides
    ).generate
  end

  describe "converting a SAR's open risks" do
    let!(:sar_risk) do
      create(:sar_risk, sar_result: result_record, title: "Unencrypted backups",
                        impact: "High", status: "open")
    end

    it "creates a POA&M item, risk and their link for each open risk" do
      result = generate

      expect(result.created_risks).to eq(1)
      expect(result.created_items).to eq(1)
      expect(result.complete?).to be(true)

      risk = result.poam_document.poam_risks.first
      expect(risk.title).to eq("Unencrypted backups")
      expect(risk.poam_items.count).to eq(1)
    end

    it "carries the assessor's content across verbatim rather than restating it" do
      result = generate
      risk = result.poam_document.poam_risks.first

      expect(risk.description).to eq(sar_risk.description)
      expect(risk.statement).to eq(sar_risk.statement)
      expect(risk.status).to eq(sar_risk.status)
    end

    it "mints a NEW uuid rather than reusing the SAR's" do
      # A POA&M risk and the SAR risk it came from are distinct OSCAL objects.
      # Reusing the identifier would make two different assemblies claim one uuid.
      result = generate

      expect(result.poam_document.poam_risks.first.uuid).not_to eq(sar_risk.uuid)
    end

    it "attaches the POA&M to the boundary and its SSP" do
      ssp = create(:ssp_document, authorization_boundary: boundary)
      sar.update!(ssp_document: ssp)

      document = generate.poam_document
      expect(document.authorization_boundary).to eq(boundary)
      expect(document.ssp_document).to eq(ssp)
    end
  end

  describe "which risks are in scope" do
    it "excludes risks the assessment already closed" do
      create(:sar_risk, sar_result: result_record, status: "closed")

      result = generate
      expect(result.created_risks).to eq(0)
      expect(result.skipped_count).to eq(0) # excluded, not rejected
    end

    it "REPORTS a blank-status risk rather than silently excluding it" do
      # Status is required OSCAL content, so a blank one cannot be converted —
      # but it must not vanish either. Excluding it at the scoping stage would
      # be a silent omission; letting it reach the required-field check means
      # the author is told which risk is incomplete and why.
      create(:sar_risk, sar_result: result_record, title: "No status", status: nil)

      result = generate
      expect(result.created_risks).to eq(0)
      expect(result.skipped_count).to eq(1)
      expect(result.skipped.first[:title]).to eq("No status")
      expect(result.skipped.first[:reason]).to match(/missing status/)
    end

    it "includes in-flight statuses" do
      create(:sar_risk, sar_result: result_record, status: "investigating")

      expect(generate.created_risks).to eq(1)
    end
  end

  # The core rule.
  describe "never synthesising required content" do
    it "SKIPS a risk with no statement instead of inventing one" do
      create(:sar_risk, sar_result: result_record, title: "Has no statement", statement: nil)

      result = generate

      expect(result.created_risks).to eq(0)
      expect(result.skipped_count).to eq(1)
      expect(result.skipped.first[:reason]).to match(/missing statement/)
      expect(result.skipped.first[:title]).to eq("Has no statement")
      expect(result.complete?).to be(false)
    end

    it "names every missing field, not just the first" do
      create(:sar_risk, sar_result: result_record, statement: nil, description: nil)

      expect(generate.skipped.first[:reason]).to match(/description/).and match(/statement/)
    end

    it "leaves NO partial graph behind for a rejected risk" do
      # Checked before writing anything. Relying on validation to fail mid-build
      # would roll back the whole transaction and lose the convertible risks too.
      create(:sar_risk, sar_result: result_record, statement: nil)

      result = generate
      expect(result.poam_document.poam_items).to be_empty
      expect(PoamRisk.where(poam_document: result.poam_document)).to be_empty
    end

    it "still converts the good risks alongside a rejected one" do
      create(:sar_risk, sar_result: result_record, title: "Convertible", impact: "High")
      create(:sar_risk, sar_result: result_record, title: "Incomplete", statement: nil)

      result = generate
      expect(result.created_risks).to eq(1)
      expect(result.skipped_count).to eq(1)
      expect(result.poam_document.poam_risks.first.title).to eq("Convertible")
    end

    it "SKIPS a finding with no target instead of defaulting it" do
      risk = create(:sar_risk, sar_result: result_record, impact: "High")
      finding = create(:sar_finding, sar_result: result_record, title: "No target", target_data: {})
      create(:sar_finding_risk, sar_finding: finding, sar_risk: risk)

      result = generate

      expect(result.created_risks).to eq(1) # the risk itself is fine
      expect(result.created_findings).to eq(0)
      expect(result.skipped.map { |s| s[:type] }).to include("finding")
      expect(result.skipped.find { |s| s[:type] == "finding" }[:reason]).to match(/target_data/)
    end

    it "produces a POA&M whose records all pass the #832 validations" do
      create(:sar_risk, sar_result: result_record, impact: "High")

      result = generate
      result.poam_document.poam_risks.each do |risk|
        expect(risk.missing_required_fields).to be_empty
        expect(risk).to be_valid
      end
    end
  end

  describe "deadlines" do
    it "keeps the source risk's own deadline when it has one" do
      own = 10.days.from_now
      create(:sar_risk, sar_result: result_record, deadline: own, impact: "Critical")

      expect(generate.poam_document.poam_risks.first.deadline).to be_within(1.second).of(own)
    end

    it "derives one from the organisation's SLA when the source has none" do
      # High baseline + Critical severity = 7 days in the seeded defaults. This
      # is a configured policy lookup, not a number the generator invented.
      create(:sar_risk, sar_result: result_record, deadline: nil, impact: "Critical")

      deadline = generate.poam_document.poam_risks.first.deadline
      expect(deadline).to be_within(1.day).of(7.days.from_now)
    end

    it "uses the boundary's baseline, so a Low baseline gets a longer window" do
      profile.update!(baseline_level: "Low")
      create(:sar_risk, sar_result: result_record, deadline: nil, impact: "Critical")

      expect(generate.poam_document.poam_risks.first.deadline).to be_within(1.day).of(30.days.from_now)
    end

    it "honours an admin-provisioned SLA row over the built-in default" do
      RemediationTimeline.create!(baseline_level: "High", criticality: "Critical", days: 3)
      create(:sar_risk, sar_result: result_record, deadline: nil, impact: "Critical")

      expect(generate.poam_document.poam_risks.first.deadline).to be_within(1.day).of(3.days.from_now)
    end

    it "reads severity from props when the risk carries no impact" do
      create(:sar_risk, sar_result: result_record, deadline: nil, impact: nil,
                        props_data: [ { "name" => "severity", "value" => "CRITICAL" } ])

      expect(generate.poam_document.poam_risks.first.deadline).to be_within(1.day).of(7.days.from_now)
    end

    it "falls back to the Unknown window rather than dropping an unrated risk" do
      create(:sar_risk, sar_result: result_record, deadline: nil, impact: "not-a-severity")

      expect(generate.poam_document.poam_risks.first.deadline).to be_within(1.day).of(30.days.from_now)
    end

    it "gives the POA&M item a date matching its risk" do
      create(:sar_risk, sar_result: result_record, deadline: nil, impact: "Critical")

      document = generate.poam_document
      expect(document.poam_items.first.deadline).to eq(document.poam_risks.first.deadline.to_date)
    end
  end

  describe "findings and observations" do
    let!(:risk) { create(:sar_risk, sar_result: result_record, impact: "High") }

    it "carries findings across using the assessor's own linkage" do
      finding = create(:sar_finding, sar_result: result_record, title: "AC-2 not satisfied")
      create(:sar_finding_risk, sar_finding: finding, sar_risk: risk)

      result = generate
      expect(result.created_findings).to eq(1)

      carried = result.poam_document.poam_findings.first
      expect(carried.title).to eq("AC-2 not satisfied")
      expect(carried.target_data).to eq(finding.target_data)
      expect(carried.poam_risks).to eq(result.poam_document.poam_risks)
    end

    it "carries observations and links them to both the item and the risk" do
      observation = create(:sar_observation, sar_result: result_record, title: "Config scan")
      create(:sar_risk_observation, sar_risk: risk, sar_observation: observation)

      document = generate.poam_document
      expect(document.poam_observations.count).to eq(1)
      expect(document.poam_observations.first.poam_risks.count).to eq(1)
      expect(document.poam_observations.first.poam_items.count).to eq(1)
    end

    it "does not duplicate an observation shared by two risks" do
      second_risk = create(:sar_risk, sar_result: result_record, impact: "High")
      observation = create(:sar_observation, sar_result: result_record)
      create(:sar_risk_observation, sar_risk: risk, sar_observation: observation)
      create(:sar_risk_observation, sar_risk: second_risk, sar_observation: observation)

      document = generate.poam_document
      expect(document.poam_risks.count).to eq(2)
      expect(document.poam_observations.count).to eq(1) # one evidence record, not two
    end
  end

  describe "scaffold mode (no SAR)" do
    it "creates an empty POA&M attached to the boundary" do
      result = described_class.new(
        name: "Empty POA&M", authorization_boundary: boundary, description: "Started early"
      ).generate

      expect(result.poam_document).to be_persisted
      expect(result.poam_document.authorization_boundary).to eq(boundary)
      expect(result.poam_document.description).to eq("Started early")
      expect(result.created_items).to eq(0)
      expect(result.complete?).to be(true)
    end

    it "is 'started', since no authoring work has happened yet" do
      result = described_class.new(name: "Empty", authorization_boundary: boundary).generate

      expect(result.poam_document.lifecycle_status).to eq("started")
    end
  end

  describe "lifecycle status" do
    it "advances to in_progress once risks have been carried across" do
      create(:sar_risk, sar_result: result_record, impact: "High")

      expect(generate.poam_document.lifecycle_status).to eq("in_progress")
    end

    it "stays 'started' when every source risk was rejected" do
      create(:sar_risk, sar_result: result_record, statement: nil)

      result = generate
      expect(result.created_items).to eq(0)
      expect(result.poam_document.lifecycle_status).to eq("started")
    end
  end
end
