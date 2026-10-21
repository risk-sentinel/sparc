# frozen_string_literal: true

require "rails_helper"

RSpec.describe SarFromSspService do
  let(:ssp) { create(:ssp_document, status: "completed") }

  let!(:ssp_control_ac1) do
    ctrl = ssp.ssp_controls.create!(control_id: "ac-1", title: "Policy and Procedures", row_order: 0)
    ctrl.ssp_control_fields.create!(field_name: "stated_requirement", field_value: "Develop access control policy.")
    ctrl.ssp_control_fields.create!(field_name: "description", field_value: "Access control policy guidance.")
    ctrl.ssp_control_fields.create!(field_name: "status", field_value: "Implemented")
    ctrl
  end

  let!(:ssp_control_sc7) do
    ctrl = ssp.ssp_controls.create!(control_id: "sc-7", title: "Boundary Protection", row_order: 1)
    ctrl.ssp_control_fields.create!(field_name: "stated_requirement", field_value: "Monitor communications at boundaries.")
    ctrl.ssp_control_fields.create!(field_name: "description", field_value: "Boundary protection guidance.")
    ctrl.ssp_control_fields.create!(field_name: "status", field_value: "Deferred")
    ctrl.ssp_control_statements.create!(statement_id: "sc-7_smt.a", label: "a.", row_order: 0,
                                        uuid: SecureRandom.uuid,
                                        implementation_prose: "Waiting on the boundary firewall refresh in Q3.")
    ctrl
  end

  describe "#create" do
    it "creates a SarDocument with correct attributes" do
      sar = described_class.new(ssp, name: "Test SAR").create

      expect(sar).to be_persisted
      expect(sar.name).to eq("Test SAR")
      expect(sar.creation_method).to eq("ssp")
      expect(sar.file_type).to eq("json")
      expect(sar.status).to eq("completed")
      expect(sar.lifecycle_status).to eq("started")
    end

    it "uses default name when none provided" do
      sar = described_class.new(ssp).create

      expect(sar.name).to eq("SAR from #{ssp.name}")
    end

    it "sets ssp_document_id to the source SSP" do
      sar = described_class.new(ssp).create

      expect(sar.ssp_document_id).to eq(ssp.id)
    end

    it "inherits profile_document_id from SSP when present" do
      profile = create(:profile_document, lifecycle_status: "published")
      ssp.update!(profile_document_id: profile.id)

      sar = described_class.new(ssp).create

      expect(sar.profile_document_id).to eq(profile.id)
    end

    it "creates the correct number of SarControls" do
      sar = described_class.new(ssp).create

      expect(sar.sar_controls.count).to eq(2)
    end

    it "copies control_id and title from SSP controls" do
      sar = described_class.new(ssp).create

      ac1 = sar.sar_controls.find_by(control_id: "ac-1")
      expect(ac1).to be_present
      expect(ac1.title).to eq("Policy and Procedures")

      sc7 = sar.sar_controls.find_by(control_id: "sc-7")
      expect(sc7).to be_present
      expect(sc7.title).to eq("Boundary Protection")
    end

    it "assigns sequential row_order to controls" do
      sar = described_class.new(ssp).create

      orders = sar.sar_controls.order(:row_order).pluck(:row_order)
      expect(orders).to eq([ 0, 1 ])
    end

    it "derives control_family from control_id" do
      sar = described_class.new(ssp).create

      ac1 = sar.sar_controls.find_by(control_id: "ac-1")
      expect(ac1.control_family).to eq("AC")

      sc7 = sar.sar_controls.find_by(control_id: "sc-7")
      expect(sc7.control_family).to eq("SC")
    end

    it "copies stated_requirement from SSP as read-only field" do
      sar = described_class.new(ssp).create

      ac1 = sar.sar_controls.find_by(control_id: "ac-1")
      field = ac1.sar_control_fields.find_by(field_name: "stated_requirement")
      expect(field).to be_present
      expect(field.field_value).to eq("Develop access control policy.")
      expect(field.editable).to be(false)
    end

    it "copies description from SSP as read-only field" do
      sar = described_class.new(ssp).create

      ac1 = sar.sar_controls.find_by(control_id: "ac-1")
      field = ac1.sar_control_fields.find_by(field_name: "description")
      expect(field).to be_present
      expect(field.field_value).to eq("Access control policy guidance.")
      expect(field.editable).to be(false)
    end

    it "copies SSP status as ssp_status read-only field" do
      sar = described_class.new(ssp).create

      ac1 = sar.sar_controls.find_by(control_id: "ac-1")
      field = ac1.sar_control_fields.find_by(field_name: "ssp_status")
      expect(field).to be_present
      expect(field.field_value).to eq("Implemented")
      expect(field.editable).to be(false)
    end

    it "creates editable placeholder fields with empty values" do
      sar = described_class.new(ssp).create

      ac1 = sar.sar_controls.find_by(control_id: "ac-1")
      %w[result working_status notes_weakness recommended_fix working_comments date].each do |field_name|
        field = ac1.sar_control_fields.find_by(field_name: field_name)
        expect(field).to be_present, "Expected field '#{field_name}' to exist"
        expect(field.field_value).to eq("")
      end
    end

    it "marks editable placeholder fields as editable" do
      sar = described_class.new(ssp).create

      ac1 = sar.sar_controls.find_by(control_id: "ac-1")
      %w[result working_status notes_weakness recommended_fix working_comments date].each do |field_name|
        field = ac1.sar_control_fields.find_by(field_name: field_name)
        expect(field.editable).to be(true), "Expected field '#{field_name}' to be editable"
      end
    end

    it "creates a default SarResult" do
      sar = described_class.new(ssp).create

      expect(sar.sar_results.count).to eq(1)
      result = sar.sar_results.first
      expect(result.uuid).to be_present
      expect(result.title).to include("Assessment Results")
      expect(result.start_time).to be_present
    end

    # Owner, 2026-10-21: a finding only where something is KNOWN before the
    # assessment. The SSP reporting a control "Deferred" or "Will Not
    # Implement" is a known finding; "Implemented" is a claim, not an
    # assessment, and gets no finding until an assessor determines it. Every
    # control used to be recorded not-satisfied with a risk (287 of 287).
    describe "findings known before the assessment" do
      let(:result) { described_class.new(ssp).create.sar_results.first }

      it "records a control the SSP reports Deferred as a known, not-satisfied finding on its statement" do
        finding = result.sar_findings.find_by(title: "Finding for sc-7")

        expect(finding.target_data).to eq("type" => "statement-id", "target-id" => "sc-7_smt",
                                          "status" => { "state" => "not-satisfied" })
        expect(finding.description).to include("Reported in the SSP as Deferred before the assessment")
      end

      it "records Will Not Implement the same way" do
        ctrl = ssp.ssp_controls.create!(control_id: "cm-6", title: "Configuration Settings", row_order: 2)
        ctrl.ssp_control_fields.create!(field_name: "status", field_value: "Will Not Implement")

        expect(result.sar_findings.find_by(title: "Finding for cm-6")).to be_present
        expect(result.sar_risks.find_by(title: "Risk for cm-6")).to be_present
      end

      it "records nothing for a control the SSP reports Implemented, or has not answered" do
        ssp.ssp_controls.create!(control_id: "au-2", title: "Event Logging", row_order: 2)

        expect(result.sar_findings.pluck(:title)).to contain_exactly("Finding for sc-7")
        expect(result.sar_risks.pluck(:title)).to contain_exactly("Risk for sc-7")
      end

      it "gives the known finding a risk quoting the requirement and the SSP's own reason" do
        risk = result.sar_risks.find_by(title: "Risk for sc-7")

        expect(risk.status).to eq("open")
        expect(risk.statement).to include("reported in the SSP as Deferred")
        expect(risk.statement).to include("Monitor communications at boundaries.")
        expect(risk.statement).to include("Waiting on the boundary firewall refresh in Q3.")
        expect(SarFindingRisk.where(sar_risk: risk, sar_finding: result.sar_findings.find_by(title: "Finding for sc-7"))).to exist
      end

      # Asserted against the generator's own constant rather than a copied
      # list, so a new required field fails here instead of silently making
      # every generated risk skippable again.
      it "sets every field PoamGeneratorService requires to convert a risk" do
        result.sar_risks.each do |risk|
          PoamRisk::OSCAL_REQUIRED_FIELDS.each do |field|
            expect(risk.public_send(field)).to be_present,
              "expected risk #{risk.title.inspect} to set #{field}, which the POA&M generator requires"
          end
        end
      end

      # Left nil so the organisation's RemediationTimeline SLA resolves it.
      it "leaves the deadline unset so the SLA decides" do
        expect(result.sar_risks.pluck(:deadline)).to all(be_nil)
      end

      # #845 needs this: committed reference OSCAL must not churn.
      it "pins the deadline when a caller supplies one" do
        pinned = Time.utc(2030, 1, 1)

        sar = described_class.new(ssp, deadline: pinned).create

        expect(sar.sar_results.first.sar_risks.pluck(:deadline)).to all(eq(pinned))
      end

      it "produces a POA&M carrying the known finding and nothing else" do
        generated = PoamGeneratorService.new(name: "POA&M", sar_document: result.sar_document,
                                             authorization_boundary: create(:authorization_boundary)).generate

        expect(generated.poam_document.poam_items.pluck(:title)).to eq([ "Risk for sc-7" ])
        expect(generated.skipped).to be_empty
      end
    end

    # A caller that already holds an outcome (the #845 reference estate's
    # evidence) passes it; those controls are satisfied and produce no risk.
    context "when the caller already knows some controls are satisfied" do
      it "assesses those controls satisfied, matching ids canonically" do
        sar = described_class.new(ssp, satisfied_control_ids: %w[AC-01]).create

        states = sar.sar_results.first.sar_findings.to_h do |f|
          [ f.target_data["target-id"], f.target_data["status"]["state"] ]
        end

        expect(states).to eq("ac-1_smt" => "satisfied", "sc-7_smt" => "not-satisfied")
        expect(sar.sar_results.first.sar_risks.pluck(:title)).to contain_exactly("Risk for sc-7")
      end
    end

    it "gives the SAR every assessment objective its catalog defines" do
      expect(ControlObjectiveExtractorService).to receive(:backfill_generated!).and_call_original

      described_class.new(ssp).create
    end

    it "stores import_metadata with SSP source info" do
      sar = described_class.new(ssp).create

      expect(sar.import_metadata["source_type"]).to eq("ssp")
      expect(sar.import_metadata["source_ssp_id"]).to eq(ssp.id)
      expect(sar.import_metadata["source_ssp_uuid"]).to eq(ssp.uuid)
      expect(sar.import_metadata["source_ssp_name"]).to eq(ssp.name)
      expect(sar.import_metadata["format"]).to eq("ssp_controls")
    end

    it "raises error for non-completed SSP" do
      draft_ssp = create(:ssp_document, status: "processing")

      expect {
        described_class.new(draft_ssp).create
      }.to raise_error(ArgumentError, /must be completed/)
    end
  end
end
