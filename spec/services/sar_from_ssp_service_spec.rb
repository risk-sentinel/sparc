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
