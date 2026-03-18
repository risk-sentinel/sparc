# frozen_string_literal: true

require "rails_helper"

RSpec.describe SarFromProfileService do
  let(:resolved_catalog_json) do
    {
      "catalog" => {
        "uuid" => SecureRandom.uuid,
        "metadata" => {
          "title" => "Test Resolved Catalog",
          "version" => "1.0.0",
          "oscal-version" => "1.1.2",
          "last-modified" => Time.current.iso8601
        },
        "groups" => [
          {
            "id" => "ac",
            "class" => "family",
            "title" => "Access Control",
            "controls" => [
              {
                "id" => "ac-1",
                "class" => "SP800-53",
                "title" => "Policy and Procedures",
                "props" => [
                  { "name" => "label", "value" => "AC-1" },
                  { "name" => "priority", "value" => "P1" }
                ],
                "parts" => [
                  { "id" => "ac-1_smt", "name" => "statement", "prose" => "Develop and document access control policy." },
                  { "id" => "ac-1_gdn", "name" => "guidance", "prose" => "Access control policy can be included in the general security policy." }
                ]
              },
              {
                "id" => "ac-2",
                "class" => "SP800-53",
                "title" => "Account Management",
                "props" => [
                  { "name" => "label", "value" => "AC-2" },
                  { "name" => "priority", "value" => "P2" }
                ],
                "parts" => [
                  { "id" => "ac-2_smt", "name" => "statement", "prose" => "Define and document account types." },
                  { "id" => "ac-2_gdn", "name" => "guidance", "prose" => "Account management includes the identification of account types." }
                ]
              }
            ]
          },
          {
            "id" => "sc",
            "class" => "family",
            "title" => "System and Communications Protection",
            "controls" => [
              {
                "id" => "sc-1",
                "class" => "SP800-53",
                "title" => "Policy and Procedures",
                "props" => [
                  { "name" => "label", "value" => "SC-1" },
                  { "name" => "priority", "value" => "P3" }
                ],
                "parts" => [
                  { "id" => "sc-1_smt", "name" => "statement", "prose" => "Develop and document system protection policy." }
                ]
              },
              {
                "id" => "sc-7",
                "class" => "SP800-53",
                "title" => "Boundary Protection",
                "props" => [
                  { "name" => "label", "value" => "SC-7" },
                  { "name" => "priority", "value" => "P1" }
                ],
                "parts" => [
                  { "id" => "sc-7_smt", "name" => "statement", "prose" => "Monitor and control communications at external boundaries." },
                  { "id" => "sc-7_gdn", "name" => "guidance", "prose" => "Managed interfaces include gateways, routers, firewalls, and tunneling devices." }
                ]
              }
            ]
          }
        ]
      }
    }
  end

  let(:profile) do
    create(:profile_document,
      lifecycle_status: "published",
      resolved_catalog_json: resolved_catalog_json,
      published: Time.current.iso8601)
  end

  describe "#create" do
    it "creates a SarDocument with correct attributes" do
      sar = described_class.new(profile, name: "Test SAR").create

      expect(sar).to be_persisted
      expect(sar.name).to eq("Test SAR")
      expect(sar.creation_method).to eq("profile")
      expect(sar.file_type).to eq("json")
      expect(sar.status).to eq("completed")
      expect(sar.lifecycle_status).to eq("started")
      expect(sar.oscal_version).to eq("1.1.2")
    end

    it "uses default name when none provided" do
      sar = described_class.new(profile).create

      expect(sar.name).to eq("SAR from #{profile.name}")
    end

    it "sets profile_document_id to the source profile" do
      sar = described_class.new(profile).create

      expect(sar.profile_document_id).to eq(profile.id)
    end

    it "creates the correct number of SarControls" do
      sar = described_class.new(profile).create

      expect(sar.sar_controls.count).to eq(4)
    end

    it "creates controls with correct control_ids and titles" do
      sar = described_class.new(profile).create

      ac1 = sar.sar_controls.find_by(control_id: "ac-1")
      expect(ac1).to be_present
      expect(ac1.title).to eq("Policy and Procedures")

      ac2 = sar.sar_controls.find_by(control_id: "ac-2")
      expect(ac2).to be_present
      expect(ac2.title).to eq("Account Management")

      sc1 = sar.sar_controls.find_by(control_id: "sc-1")
      expect(sc1).to be_present

      sc7 = sar.sar_controls.find_by(control_id: "sc-7")
      expect(sc7).to be_present
      expect(sc7.title).to eq("Boundary Protection")
    end

    it "assigns sequential row_order to controls" do
      sar = described_class.new(profile).create

      orders = sar.sar_controls.order(:row_order).pluck(:row_order)
      expect(orders).to eq([ 0, 1, 2, 3 ])
    end

    it "extracts stated_requirement from statement prose" do
      sar = described_class.new(profile).create

      ac1 = sar.sar_controls.find_by(control_id: "ac-1")
      field = ac1.sar_control_fields.find_by(field_name: "stated_requirement")
      expect(field).to be_present
      expect(field.field_value).to eq("Develop and document access control policy.")
    end

    it "extracts description from guidance prose" do
      sar = described_class.new(profile).create

      ac1 = sar.sar_controls.find_by(control_id: "ac-1")
      field = ac1.sar_control_fields.find_by(field_name: "description")
      expect(field).to be_present
      expect(field.field_value).to include("general security policy")
    end

    it "does not create description field when no guidance part exists" do
      sar = described_class.new(profile).create

      sc1 = sar.sar_controls.find_by(control_id: "sc-1")
      field = sc1.sar_control_fields.find_by(field_name: "description")
      expect(field).to be_nil
    end

    it "creates editable placeholder fields with empty values" do
      sar = described_class.new(profile).create

      ac1 = sar.sar_controls.find_by(control_id: "ac-1")
      %w[result working_status notes_weakness recommended_fix working_comments date].each do |field_name|
        field = ac1.sar_control_fields.find_by(field_name: field_name)
        expect(field).to be_present, "Expected field '#{field_name}' to exist"
        expect(field.field_value).to eq("")
      end
    end

    it "marks editable placeholder fields as editable" do
      sar = described_class.new(profile).create

      ac1 = sar.sar_controls.find_by(control_id: "ac-1")
      %w[result working_status notes_weakness recommended_fix working_comments date].each do |field_name|
        field = ac1.sar_control_fields.find_by(field_name: field_name)
        expect(field.editable).to be(true), "Expected field '#{field_name}' to be editable"
      end
    end

    it "creates a default SarResult" do
      sar = described_class.new(profile).create

      expect(sar.sar_results.count).to eq(1)
      result = sar.sar_results.first
      expect(result.uuid).to be_present
      expect(result.title).to include("Assessment Results")
      expect(result.start_time).to be_present
    end

    it "creates a SarFinding for each control" do
      sar = described_class.new(profile).create

      result = sar.sar_results.first
      expect(result.sar_findings.count).to eq(4)
    end

    it "creates findings with target_data referencing the control" do
      sar = described_class.new(profile).create

      result = sar.sar_results.first
      finding = result.sar_findings.find_by(title: "Finding for ac-1")
      expect(finding).to be_present
      expect(finding.target_data["target-id"]).to eq("ac-1")
      expect(finding.target_data["status"]["state"]).to eq("not-satisfied")
    end

    it "stores import_metadata with source profile info" do
      sar = described_class.new(profile).create

      expect(sar.import_metadata["source_type"]).to eq("profile")
      expect(sar.import_metadata["source_profile_id"]).to eq(profile.id)
      expect(sar.import_metadata["source_profile_uuid"]).to eq(profile.uuid)
      expect(sar.import_metadata["source_profile_name"]).to eq(profile.name)
      expect(sar.import_metadata["format"]).to eq("resolved_catalog")
    end

    it "raises error for unpublished profile" do
      unpublished = create(:profile_document, lifecycle_status: "in_progress")

      expect {
        described_class.new(unpublished).create
      }.to raise_error(ArgumentError, /must be published/)
    end

    it "raises error for profile without resolved catalog" do
      no_catalog = create(:profile_document, lifecycle_status: "published", resolved_catalog_json: nil)

      expect {
        described_class.new(no_catalog).create
      }.to raise_error(ArgumentError, /must have a resolved catalog/)
    end
  end
end
