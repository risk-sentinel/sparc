# frozen_string_literal: true

require "rails_helper"

RSpec.describe BaselineParameterService do
  let(:catalog) { create(:control_catalog) }
  let(:family) { create(:control_family, control_catalog: catalog, code: "AC") }
  let(:other_family) { create(:control_family, control_catalog: catalog, code: "AU") }

  let!(:control_with_params) do
    create(:catalog_control, :with_params,
      control_family: family,
      control_id: "ac-1",
      title: "Policy and Procedures")
  end

  let!(:control_with_select) do
    create(:catalog_control, :with_select_param,
      control_family: family,
      control_id: "ac-2",
      title: "Account Management")
  end

  let(:profile) { create(:profile_document, control_catalog: catalog) }
  let(:service) { described_class.new(profile) }

  describe "#extract_schema" do
    it "returns parameters from catalog controls" do
      schema = service.extract_schema

      expect(schema[:baseline]).to eq(profile.name)
      expect(schema[:parameters]).to be_an(Array)
      expect(schema[:parameters].length).to eq(2) # ac-1 has 2 params
      expect(schema[:parameters].first[:param_id]).to eq("ac-1_prm_1")
      expect(schema[:parameters].first[:control_id]).to eq("ac-1")
    end

    it "returns selections from catalog controls with select params" do
      schema = service.extract_schema

      expect(schema[:selections]).to be_an(Array)
      expect(schema[:selections].length).to eq(1)
      expect(schema[:selections].first[:select_id]).to eq("ac-2_prm_1")
      expect(schema[:selections].first[:choices]).to include("removes", "disables")
      expect(schema[:selections].first[:how_many]).to eq("one-or-more")
    end

    it "includes current values from profile_control_fields" do
      pc = create(:profile_control, profile_document: profile, control_id: "ac-1")
      pc.profile_control_fields.create!(
        field_name: "parameter:ac-1_prm_1",
        field_value: "System Administrators"
      )

      schema = service.extract_schema
      param = schema[:parameters].find { |p| p[:param_id] == "ac-1_prm_1" }
      expect(param[:current_value]).to eq("System Administrators")
      expect(param[:value]).to eq("System Administrators")
    end

    it "filters by control family" do
      create(:catalog_control, :with_params,
        control_family: other_family,
        control_id: "au-1",
        title: "Audit Policy")

      schema = service.extract_schema(family: family.code)
      control_ids = schema[:parameters].map { |p| p[:control_id] }
      expect(control_ids).to all(start_with(family.code.downcase))
    end
  end

  describe "#extract_schema with resolved_catalog_json" do
    let(:resolved_profile) do
      create(:profile_document, resolved_catalog_json: {
        "groups" => [
          {
            "id" => "ac",
            "title" => "Access Control",
            "controls" => [
              {
                "id" => "ac-7",
                "title" => "Unsuccessful Logon Attempts",
                "params" => [
                  { "id" => "ac-7_prm_1", "label" => "number" },
                  { "id" => "ac-7_prm_2", "label" => "time period",
                    "select" => { "how-many" => "one", "choice" => [ "locks", "delays" ] } }
                ]
              }
            ]
          }
        ]
      })
    end

    it "extracts parameters from resolved_catalog_json" do
      svc = described_class.new(resolved_profile)
      schema = svc.extract_schema

      expect(schema[:parameters].length).to eq(1)
      expect(schema[:parameters].first[:param_id]).to eq("ac-7_prm_1")
      expect(schema[:selections].length).to eq(1)
      expect(schema[:selections].first[:select_id]).to eq("ac-7_prm_2")
    end
  end

  describe "#update_parameters" do
    it "creates parameter fields for valid params" do
      # Need a profile_control for ac-1
      create(:profile_control, profile_document: profile, control_id: "ac-1")

      result = service.update_parameters(
        parameters: [
          { param_id: "ac-1_prm_1", value: "ISSO" },
          { param_id: "ac-1_prm_2", value: "annually" }
        ]
      )

      expect(result[:status]).to eq("updated")
      expect(result[:parameters_updated]).to eq(2)
      expect(result[:validation_errors]).to be_empty

      field = ProfileControlField.find_by(field_name: "parameter:ac-1_prm_1")
      expect(field.field_value).to eq("ISSO")
    end

    it "updates selection fields" do
      create(:profile_control, profile_document: profile, control_id: "ac-2")

      result = service.update_parameters(
        selections: [
          { select_id: "ac-2_prm_1", selected: [ "removes" ] }
        ]
      )

      expect(result[:status]).to eq("updated")
      expect(result[:selections_updated]).to eq(1)

      field = ProfileControlField.find_by(field_name: "parameter:ac-2_prm_1")
      expect(field.field_value).to eq("removes")
    end

    it "returns errors for unknown param_ids" do
      result = service.update_parameters(
        parameters: [
          { param_id: "nonexistent_prm_1", value: "test" }
        ]
      )

      expect(result[:status]).to eq("partial")
      expect(result[:validation_errors].length).to eq(1)
      expect(result[:validation_errors].first[:error]).to eq("Unknown parameter ID")
    end

    it "creates profile_control if missing" do
      expect {
        service.update_parameters(
          parameters: [ { param_id: "ac-1_prm_1", value: "test" } ]
        )
      }.to change(ProfileControl, :count).by(1)
    end
  end

  describe "#export" do
    it "exports as JSON" do
      output = service.export(format: :json)
      parsed = JSON.parse(output)

      expect(parsed["baseline"]).to eq(profile.name)
      expect(parsed["parameters"]).to be_an(Array)
      expect(parsed["selections"]).to be_an(Array)
    end

    it "exports as YAML" do
      output = service.export(format: :yaml)
      parsed = YAML.safe_load(output)

      expect(parsed["baseline"]).to eq(profile.name)
      expect(parsed["parameters"]).to be_an(Array)
    end

    it "exports as XML" do
      output = service.export(format: :xml)

      expect(output).to include("<?xml")
      expect(output).to include("baseline-parameters")
      expect(output).to include("parameters")
    end

    it "raises on unsupported format" do
      expect { service.export(format: :csv) }.to raise_error(ArgumentError, /Unsupported format/)
    end
  end
end
