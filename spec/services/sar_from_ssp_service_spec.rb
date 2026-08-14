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
    ctrl.ssp_control_fields.create!(field_name: "status", field_value: "Planned")
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

    it "creates a SarFinding for each control" do
      sar = described_class.new(ssp).create

      result = sar.sar_results.first
      expect(result.sar_findings.count).to eq(2)
    end

    it "creates findings with target_data referencing the control" do
      sar = described_class.new(ssp).create

      result = sar.sar_results.first
      finding = result.sar_findings.find_by(title: "Finding for ac-1")
      expect(finding).to be_present
      expect(finding.target_data["target-id"]).to eq("ac-1")
      expect(finding.target_data["status"]["state"]).to eq("not-satisfied")
    end

    # #954 — findings alone left PoamGeneratorService with nothing to source,
    # so a SAR built from an SSP generated an EMPTY POA&M and reported success.
    describe "risks (#954)" do
      it "creates a SarRisk for each control" do
        sar = described_class.new(ssp).create

        expect(sar.sar_results.first.sar_risks.count).to eq(2)
      end

      it "links every risk to the finding it came from" do
        sar    = described_class.new(ssp).create
        result = sar.sar_results.first

        finding = result.sar_findings.find_by(title: "Finding for ac-1")
        risk    = result.sar_risks.find_by(title: "Risk for ac-1")

        expect(SarFindingRisk.where(sar_finding: finding, sar_risk: risk)).to exist
        expect(finding.sar_risks).to contain_exactly(risk)
      end

      # Asserted against the generator's own constant rather than a copied
      # list, so a new required field fails here instead of silently making
      # every generated risk skippable again.
      it "sets every field PoamGeneratorService requires to convert a risk" do
        sar = described_class.new(ssp).create

        sar.sar_results.first.sar_risks.each do |risk|
          PoamRisk::OSCAL_REQUIRED_FIELDS.each do |field|
            expect(risk.public_send(field)).to be_present,
              "expected risk #{risk.title.inspect} to set #{field}, which the POA&M generator requires"
          end
        end
      end

      it "carries the control's stated requirement into the risk statement" do
        sar  = described_class.new(ssp).create
        risk = sar.sar_results.first.sar_risks.find_by(title: "Risk for ac-1")

        expect(risk.statement).to include("Develop access control policy.")
        expect(risk.status).to eq("open")
      end

      it "says so when the SSP records no stated requirement" do
        ssp.ssp_controls.create!(control_id: "au-2", title: "Event Logging", row_order: 2)

        sar  = described_class.new(ssp).create
        risk = sar.sar_results.first.sar_risks.find_by(title: "Risk for au-2")

        expect(risk.statement).to include("no stated requirement")
        expect(risk.statement).to include("au-2")
      end

      # Left nil so the organisation's RemediationTimeline SLA resolves it —
      # a pinned date here would override configured policy for every user.
      it "leaves the deadline unset so the SLA decides" do
        sar = described_class.new(ssp).create

        expect(sar.sar_results.first.sar_risks.pluck(:deadline)).to all(be_nil)
      end

      # #845 needs this: an SLA-derived deadline is Time.current-relative, so
      # committed reference OSCAL would carry a fresh diff on every regen.
      it "pins the deadline when a caller supplies one" do
        pinned = Time.utc(2030, 1, 1)

        sar = described_class.new(ssp, deadline: pinned).create

        expect(sar.sar_results.first.sar_risks.pluck(:deadline)).to all(eq(pinned))
      end

      # #954's acceptance criteria required this outright: "a satisfied finding
      # does not produce a risk". Without it every control reaches the POA&M,
      # which is why the full reference estate produced 287 items per POA&M —
      # an entry for literally every control, which no real assessment yields.
      context "when the caller already knows some controls are satisfied" do
        it "assesses those controls satisfied" do
          sar = described_class.new(ssp, satisfied_control_ids: %w[ac-1]).create

          states = sar.sar_results.first.sar_findings.to_h do |f|
            [ f.target_data["target-id"], f.target_data["status"]["state"] ]
          end

          expect(states["ac-1"]).to eq("satisfied")
          expect(states["sc-7"]).to eq("not-satisfied")
        end

        it "creates no risk for a satisfied control" do
          sar = described_class.new(ssp, satisfied_control_ids: %w[ac-1]).create

          expect(sar.sar_results.first.sar_risks.pluck(:title)).to contain_exactly("Risk for sc-7")
        end

        it "keeps a satisfied control out of the POA&M entirely" do
          sar      = described_class.new(ssp, satisfied_control_ids: %w[ac-1]).create
          boundary = create(:authorization_boundary)

          generated = PoamGeneratorService.new(name: "POA&M", sar_document: sar,
                                               authorization_boundary: boundary).generate

          expect(generated.poam_document.poam_items.count).to eq(1)
          expect(generated.skipped).to be_empty
        end

        # The caller passes what a human writes; controls are stored
        # canonically. A literal match would silently satisfy nothing.
        it "matches control ids canonically, not literally" do
          sar = described_class.new(ssp, satisfied_control_ids: %w[AC-01]).create

          satisfied = sar.sar_results.first.sar_findings.select do |f|
            f.target_data["status"]["state"] == "satisfied"
          end

          expect(satisfied.map { |f| f.target_data["target-id"] }).to contain_exactly("ac-1")
        end

        it "still assesses everything not-satisfied when given none" do
          sar = described_class.new(ssp).create

          expect(sar.sar_results.first.sar_risks.count).to eq(2)
        end
      end

      it "produces a POA&M with real items instead of an empty one" do
        sar      = described_class.new(ssp).create
        boundary = create(:authorization_boundary)

        generated = PoamGeneratorService.new(name: "POA&M", sar_document: sar,
                                             authorization_boundary: boundary).generate

        expect(generated.poam_document.poam_items.count).to eq(2)
        expect(generated.skipped).to be_empty
      end
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
