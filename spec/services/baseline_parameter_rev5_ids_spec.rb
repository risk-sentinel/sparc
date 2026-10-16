# frozen_string_literal: true

require "rails_helper"

# #1218 — parameter ids as NIST's Rev 5 catalog spells them, and the two rules a
# bulk update relies on:
#
# * an `alt-identifier` (the Rev 4-style `ac-1_prm_2` NIST kept on
#   `ac-01_odp.03`) resolves to the parameter that declares it;
# * `null` is "not provided" and is skipped, while "" / [] still clear.
#
# The params below are AC-1's, copied verbatim from
# lib/data/catalogs/NIST_SP-800-53_rev5_catalog.json (v5.2.0).
RSpec.describe BaselineParameterService, "Rev 5 parameter ids" do
  let(:ac1_params) do
    [
      { "id" => "ac-1_prm_1", "label" => "organization-defined personnel or roles",
        "props" => [ { "name" => "aggregates", "ns" => "http://csrc.nist.gov/ns/rmf", "value" => "ac-01_odp.01" },
                     { "name" => "aggregates", "ns" => "http://csrc.nist.gov/ns/rmf", "value" => "ac-01_odp.02" } ] },
      { "id" => "ac-01_odp.01", "label" => "personnel or roles",
        "props" => [ { "name" => "label", "value" => "AC-01_ODP[01]", "class" => "sp800-53a" } ] },
      { "id" => "ac-01_odp.03",
        "props" => [ { "name" => "alt-identifier", "value" => "ac-1_prm_2" },
                     { "name" => "label", "value" => "AC-01_ODP[03]", "class" => "sp800-53a" } ],
        "select" => { "how-many" => "one-or-more",
                      "choice" => [ "organization-level", "mission/business process-level", "system-level" ] } },
      { "id" => "ac-01_odp.04", "label" => "official",
        "props" => [ { "name" => "alt-identifier", "value" => "ac-1_prm_3" },
                     { "name" => "label", "value" => "AC-01_ODP[04]", "class" => "sp800-53a" } ] }
    ]
  end
  let(:catalog) { create(:control_catalog) }
  let(:family) { create(:control_family, control_catalog: catalog, code: "AC") }
  let!(:ac1) do
    create(:catalog_control, control_family: family, control_id: "ac-1", title: "Policy and Procedures",
                             params_data: ac1_params)
  end
  let(:profile) { create(:profile_document, control_catalog: catalog) }
  let(:service) { described_class.new(profile) }

  def stored(param_id)
    described_class.new(profile).extract_schema
                   .then { |s| s[:parameters] + s[:selections] }
                   .find { |e| (e[:param_id] || e[:select_id]) == param_id }
                   .then { |e| e[:current_value] || e[:selected] }
  end

  describe "alt-identifier aliases" do
    it "shows the alias beside the id in the schema" do
      schema = service.extract_schema

      expect(schema[:selections].find { |s| s[:select_id] == "ac-01_odp.03" }[:alt_identifier]).to eq("ac-1_prm_2")
      expect(schema[:parameters].find { |p| p[:param_id] == "ac-01_odp.04" }[:alt_identifier]).to eq("ac-1_prm_3")
      expect(schema[:parameters].find { |p| p[:param_id] == "ac-01_odp.01" }[:alt_identifier]).to be_nil
    end

    it "stores a selection sent by its alias against the real id, and says so" do
      result = service.update_parameters(selections: [ { select_id: "ac-1_prm_2", selected: [ "system-level" ] } ])

      expect(result).to include(selections_updated: 1, validation_errors: [])
      expect(result[:resolved_aliases]).to eq([ { given: "ac-1_prm_2", select_id: "ac-01_odp.03" } ])
      expect(stored("ac-01_odp.03")).to eq([ "system-level" ])
    end

    it "stores a parameter sent by its alias against the real id" do
      result = service.update_parameters(parameters: [ { param_id: "ac-1_prm_3", value: "CISO" } ])

      expect(result).to include(parameters_updated: 1, validation_errors: [])
      expect(result[:resolved_aliases]).to eq([ { given: "ac-1_prm_3", param_id: "ac-01_odp.04" } ])
      expect(stored("ac-01_odp.04")).to eq("CISO")
    end

    it "prefers a real id over an alias spelled the same way" do
      # ac-1_prm_1 is a real (aggregate) parameter; were any other parameter to
      # carry it as an alt-identifier, the real one must still win.
      ac1.update!(params_data: ac1_params + [
        { "id" => "ac-01_odp.99", "props" => [ { "name" => "alt-identifier", "value" => "ac-1_prm_1" } ] }
      ])

      result = service.update_parameters(parameters: [ { param_id: "ac-1_prm_1", value: "ISSO" } ])

      expect(result[:resolved_aliases]).to be_empty
      expect(stored("ac-1_prm_1")).to eq("ISSO")
      expect(stored("ac-01_odp.99")).to be_nil
    end

    it "still refuses an id the profile has neither as an id nor as an alias" do
      result = service.update_parameters(parameters: [ { param_id: "ac-1_prm_9", value: "x" } ])

      expect(result[:validation_errors]).to eq([ { param_id: "ac-1_prm_9", error: "Unknown parameter ID" } ])
      expect(result[:parameters_updated]).to eq(0)
    end
  end

  describe "the parameter file import" do
    let(:file) do
      { parameters: [ { param_id: "ac-1_prm_3", value: "CISO" }, { param_id: "ac-01_odp.01", value: nil } ],
        selections: [ { select_id: "ac-1_prm_2", selected: [ "system-level" ] },
                      { select_id: "ac-01_odp.03", selected: nil } ] }.to_json
    end
    let(:payload) { OdpImportService.parse(content: file, format: "json") }

    it "previews an alias as the real id it writes, and a null as skipped" do
      rows = OdpImportService.new(profile).preview(payload)[:rows].map(&:to_h)

      expect(rows).to include(
        a_hash_including(param_id: "ac-01_odp.04", status: "change",
                         message: "ac-1_prm_3 is an alt-identifier for ac-01_odp.04"),
        a_hash_including(param_id: "ac-01_odp.01", status: "skipped"),
        a_hash_including(param_id: "ac-01_odp.03", status: "change",
                         message: "ac-1_prm_2 is an alt-identifier for ac-01_odp.03"),
        a_hash_including(param_id: "ac-01_odp.03", status: "skipped")
      )
      expect(rows.map { |r| r[:status] }).not_to include("unknown")
    end

    it "applies what the preview showed" do
      result = OdpImportService.new(profile).apply(payload)

      expect(result).to include(parameters_updated: 1, selections_updated: 1, validation_errors: [])
      expect(stored("ac-01_odp.04")).to eq("CISO")
      expect(stored("ac-01_odp.03")).to eq([ "system-level" ])
    end
  end

  describe "null means not provided" do
    before do
      service.update_parameters(parameters: [ { param_id: "ac-01_odp.04", value: "CISO" } ],
                                selections: [ { select_id: "ac-01_odp.03", selected: [ "system-level" ] } ])
    end

    it "skips a null value and a null selection, leaving what is stored" do
      result = described_class.new(profile).update_parameters(
        parameters: [ { param_id: "ac-01_odp.04", value: nil } ],
        selections: [ { select_id: "ac-01_odp.03", selected: nil } ]
      )

      expect(result).to include(parameters_updated: 0, selections_updated: 0, validation_errors: [])
      expect(result[:skipped].map { |s| s[:param_id] || s[:select_id] }).to eq(%w[ac-01_odp.04 ac-01_odp.03])
      expect(stored("ac-01_odp.04")).to eq("CISO")
      expect(stored("ac-01_odp.03")).to eq([ "system-level" ])
    end

    it "still clears on an explicit empty string or empty array" do
      described_class.new(profile).update_parameters(
        parameters: [ { param_id: "ac-01_odp.04", value: "" } ],
        selections: [ { select_id: "ac-01_odp.03", selected: [] } ]
      )

      expect(stored("ac-01_odp.04").to_s).to eq("")
      expect(stored("ac-01_odp.03")).to eq([])
    end
  end
end
