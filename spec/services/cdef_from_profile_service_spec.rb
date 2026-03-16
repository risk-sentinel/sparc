# frozen_string_literal: true

require "rails_helper"

RSpec.describe CdefFromProfileService do
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
                "params" => [
                  { "id" => "ac-1_prm_1", "label" => "organization-defined personnel or roles" }
                ],
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
                  { "id" => "ac-2_smt", "name" => "statement", "prose" => "Define and document account types." }
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
    it "creates a CdefDocument with correct attributes" do
      cdef = described_class.new(profile, name: "Test CDEF").create

      expect(cdef).to be_persisted
      expect(cdef.name).to eq("Test CDEF")
      expect(cdef.cdef_type).to eq("custom")
      expect(cdef.status).to eq("completed")
      expect(cdef.lifecycle_status).to eq("started")
      expect(cdef.oscal_version).to eq("1.1.2")
    end

    it "uses default name when none provided" do
      cdef = described_class.new(profile).create

      expect(cdef.name).to eq("CDEF from #{profile.name}")
    end

    it "creates the correct number of CdefControls" do
      cdef = described_class.new(profile).create

      expect(cdef.cdef_controls.count).to eq(3)
    end

    it "maps priority P1 to severity high" do
      cdef = described_class.new(profile).create

      ac1 = cdef.cdef_controls.find_by(control_id: "ac-1")
      expect(ac1.severity).to eq("high")
    end

    it "maps priority P2 to severity medium" do
      cdef = described_class.new(profile).create

      ac2 = cdef.cdef_controls.find_by(control_id: "ac-2")
      expect(ac2.severity).to eq("medium")
    end

    it "maps priority P3 to severity low" do
      cdef = described_class.new(profile).create

      sc1 = cdef.cdef_controls.find_by(control_id: "sc-1")
      expect(sc1.severity).to eq("low")
    end

    it "sets control_family from group id" do
      cdef = described_class.new(profile).create

      ac1 = cdef.cdef_controls.find_by(control_id: "ac-1")
      expect(ac1.control_family).to eq("AC")

      sc1 = cdef.cdef_controls.find_by(control_id: "sc-1")
      expect(sc1.control_family).to eq("SC")
    end

    it "extracts description from statement prose" do
      cdef = described_class.new(profile).create

      ac1 = cdef.cdef_controls.find_by(control_id: "ac-1")
      desc = ac1.cdef_control_fields.find_by(field_name: "description")
      expect(desc.field_value).to eq("Develop and document access control policy.")
    end

    it "extracts guidance from guidance prose" do
      cdef = described_class.new(profile).create

      ac1 = cdef.cdef_controls.find_by(control_id: "ac-1")
      guidance = ac1.cdef_control_fields.find_by(field_name: "guidance")
      expect(guidance.field_value).to include("general security policy")
    end

    it "serializes parameters as JSON" do
      cdef = described_class.new(profile).create

      ac1 = cdef.cdef_controls.find_by(control_id: "ac-1")
      params_field = ac1.cdef_control_fields.find_by(field_name: "parameters")
      parsed = JSON.parse(params_field.field_value)
      expect(parsed.first["id"]).to eq("ac-1_prm_1")
    end

    it "creates editable placeholder fields" do
      cdef = described_class.new(profile).create

      ac1 = cdef.cdef_controls.find_by(control_id: "ac-1")
      impl = ac1.cdef_control_fields.find_by(field_name: "implementation_narrative")
      notes = ac1.cdef_control_fields.find_by(field_name: "notes")
      status = ac1.cdef_control_fields.find_by(field_name: "status_override")

      expect(impl).to be_present
      expect(notes).to be_present
      expect(status).to be_present
    end

    it "stores import_metadata with source profile info" do
      cdef = described_class.new(profile).create

      expect(cdef.import_metadata["source_type"]).to eq("profile")
      expect(cdef.import_metadata["source_profile_id"]).to eq(profile.id)
      expect(cdef.import_metadata["source_profile_uuid"]).to eq(profile.uuid)
      expect(cdef.import_metadata["source_profile_name"]).to eq(profile.name)
      expect(cdef.import_metadata["format"]).to eq("resolved_catalog")
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
