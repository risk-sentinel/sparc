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

    # ── #994: the service is the last guard, not the only one ──────────────
    #
    # The API reaches here through BaselineParameterPayload, which refuses these
    # shapes at the edge. These examples pin the SERVICE's own behaviour,
    # because OdpImportService (#697) and any future caller reach it directly —
    # and because a guard nothing exercises is a guard that can be deleted
    # without a single test going red.
    it "refuses a non-array `selected` instead of coercing it into the record" do
      create(:profile_control, profile_document: profile, control_id: "ac-2")

      result = service.update_parameters(
        selections: [ { select_id: "ac-2_prm_1", selected: "removes" } ]
      )

      expect(result[:selections_updated]).to eq(0)
      expect(result[:status]).to eq("partial")
      expect(result[:validation_errors].first).to include(
        select_id: "ac-2_prm_1",
        error: a_string_matching(/must be an array/)
      )
      # The write is what mattered: a string used to be `to_s`'d straight in and
      # reported as `selections_updated: 1`.
      expect(ProfileControlField.find_by(field_name: "parameter:ac-2_prm_1")).to be_nil
    end

    it "reports a selection entry that names no id as missing one" do
      create(:profile_control, profile_document: profile, control_id: "ac-2")

      result = service.update_parameters(selections: [ { selected: [ "removes" ] } ])

      expect(result[:selections_updated]).to eq(0)
      expect(result[:validation_errors].first[:error]).to match(/missing select_id/)
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

  # ── #942 — choices composed from other parameters ────────────────────────
  #
  # AC-20 as the issue reports it: odp.01 is a select whose two choices are
  # templates referencing odp.02 and odp.03, so odp.01 chooses WHICH of those
  # applies. Presented as literal choices, the operator is asked the wrong
  # question and the relationship is lost.
  describe "selection choices that reference other parameters (#942)" do
    let!(:ac_20) do
      family.catalog_controls.create!(
        control_id: "ac-20",
        title: "Use of External Systems",
        params_data: [
          { "id" => "ac-20_odp.01",
            "select" => { "how-many" => "one-or-more",
                          "choice" => [ "establish {{ insert: param, ac-20_odp.02 }}",
                                        "identify {{ insert: param, ac-20_odp.03 }}" ] } },
          { "id" => "ac-20_odp.02", "label" => "terms and conditions" },
          { "id" => "ac-20_odp.03", "label" => "controls asserted" }
        ]
      )
    end

    def selection_for(id, schema = service.extract_schema)
      schema[:selections].find { |s| s[:select_id] == id }
    end

    it "keeps the verbatim OSCAL text so the document round-trips" do
      expect(selection_for("ac-20_odp.01")[:choices])
        .to eq([ "establish {{ insert: param, ac-20_odp.02 }}",
                 "identify {{ insert: param, ac-20_odp.03 }}" ])
    end

    it "resolves each choice to the term it stands for" do
      expect(selection_for("ac-20_odp.01")[:choice_details].map { |d| d[:display] })
        .to eq([ "establish terms and conditions", "identify controls asserted" ])
    end

    it "records which parameter each choice depends on" do
      details = selection_for("ac-20_odp.01")[:choice_details]

      expect(details.map { |d| d[:references] })
        .to eq([ [ "ac-20_odp.02" ], [ "ac-20_odp.03" ] ])
    end

    it "reports the union of everything the selection could require" do
      expect(selection_for("ac-20_odp.01")[:depends_on])
        .to contain_exactly("ac-20_odp.02", "ac-20_odp.03")
    end

    it "leaves a literal selection's choices unresolved and undependent" do
      selection = selection_for("ac-2_prm_1")

      expect(selection[:depends_on]).to be_empty
      expect(selection[:choice_details].map { |d| d[:display] }).to eq(selection[:choices])
    end

    # A reference can point at a parameter the family filter excluded. Resolving
    # to raw markup because of a DISPLAY filter would be worse than not
    # filtering, so the label index is built from the unfiltered set.
    it "resolves a reference even when the schema is filtered to one family" do
      selection = selection_for("ac-20_odp.01", service.extract_schema(family: "AC"))

      expect(selection[:choice_details].first[:display]).to eq("establish terms and conditions")
    end

    it "carries the resolved form and the references into the XML export" do
      output = service.export(format: :xml)

      expect(output).to include('display="establish terms and conditions"')
      expect(output).to include('references="ac-20_odp.02"')
      # The element text stays verbatim so the file round-trips.
      expect(output).to include("insert: param, ac-20_odp.02")
    end

    # Issue point 4: "a payload setting odp.01 without odp.02 should be
    # answerable rather than silently accepted."
    describe "the update path" do
      it "reports a selected branch whose referenced parameter has no value" do
        result = service.update_parameters(
          selections: [ { select_id: "ac-20_odp.01",
                          selected: [ "establish {{ insert: param, ac-20_odp.02 }}" ] } ]
        )

        expect(result[:status]).to eq("partial")
        expect(result[:validation_errors]).to include(
          hash_including(select_id: "ac-20_odp.01", param_id: "ac-20_odp.02")
        )
      end

      it "accepts the selection once the referenced parameter is answered" do
        result = service.update_parameters(
          parameters: [ { param_id: "ac-20_odp.02", value: "the agreed terms" } ],
          selections: [ { select_id: "ac-20_odp.01",
                          selected: [ "establish {{ insert: param, ac-20_odp.02 }}" ] } ]
        )

        expect(result[:validation_errors]).to be_empty
        expect(result[:status]).to eq("updated")
      end

      # Demanding a parameter that belongs to a branch nobody chose is the
      # over-collection the issue exists to stop.
      it "does not demand a parameter belonging to an unchosen branch" do
        result = service.update_parameters(
          parameters: [ { param_id: "ac-20_odp.02", value: "the agreed terms" } ],
          selections: [ { select_id: "ac-20_odp.01",
                          selected: [ "establish {{ insert: param, ac-20_odp.02 }}" ] } ]
        )

        expect(result[:validation_errors].map { |e| e[:param_id] }).not_to include("ac-20_odp.03")
      end

      it "still records the selection it flagged, rather than dropping the write" do
        service.update_parameters(
          selections: [ { select_id: "ac-20_odp.01",
                          selected: [ "establish {{ insert: param, ac-20_odp.02 }}" ] } ]
        )

        expect(selection_for("ac-20_odp.01")[:selected])
          .to eq([ "establish {{ insert: param, ac-20_odp.02 }}" ])
      end
    end
  end
end
