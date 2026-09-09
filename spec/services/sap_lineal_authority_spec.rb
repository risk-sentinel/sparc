# frozen_string_literal: true

require "rails_helper"

# #1114 — a plan reads control language THROUGH the profile, not around it.
#
# NIST's layer model is a chain — Catalog -> Profile -> SSP -> Assessment Plan —
# and a profile "tailors by modifying statements, parameters and assessment
# actions". Reading `CatalogControl` directly therefore reads UNTAILORED text:
# the baseline's parameter values are not applied.
#
# Measured on the seeded catalog: ac-1's `guidance_data["assessment_objective"]`
# is 1,966 characters carrying `{{ insert: param, ac-01_odp.01 }}`. A plan built
# from it tells an assessor to determine something with the organisation-defined
# value still written as markup.
#
# Correcting the READ PATH is what fixes the parameters — the resolved catalog
# already substitutes them per part and recursively (#942). There is deliberately
# no second substitution step in the generator to drift from that one.
RSpec.describe "SAP reads through the profile (#1114)" do
  let(:catalog) { create(:control_catalog) }
  let(:family)  { create(:control_family, control_catalog: catalog, code: "AC") }

  let!(:catalog_control) do
    family.catalog_controls.create!(
      control_id: "ac-1", title: "Policy and Procedures",
      guidance_data: {
        "statement" => "Develop an access control policy.",
        # The raw markup, exactly as the shipped catalog carries it.
        "assessment_objective" => "the {{ insert: param, ac-01_odp.01 }} access control policy is reviewed"
      },
      params_data: [ { "id" => "ac-01_odp.01", "label" => "organization-defined frequency" } ]
    ).tap do |cc|
      cc.catalog_control_parts.create!(
        part_id: "ac-1_obj", part_name: "assessment-objective", label: "AC-01",
        row_order: 0, uuid: SecureRandom.uuid
      )
      cc.catalog_control_parts.create!(
        part_id: "ac-1_obj.a-1", part_name: "assessment-objective", parent_part_id: "ac-1_obj",
        label: "AC-01a.[01]",
        prose: "the {{ insert: param, ac-01_odp.01 }} access control policy is reviewed",
        row_order: 1, uuid: SecureRandom.uuid
      )
    end
  end

  # The profile TAILORS the parameter — this is the value an assessor must see.
  let(:profile) do
    create(:profile_document, control_catalog: catalog, lifecycle_status: "published")
  end
  # A profile tailors a parameter through `profile_control_fields` keyed
  # `parameter:<id>` — see OscalResolvedProfileCatalogService#set_parameter_values.
  let!(:profile_control) do
    profile.profile_controls.create!(control_id: "ac-1", title: "Policy and Procedures").tap do |pc|
      pc.profile_control_fields.create!(field_name: "parameter:ac-01_odp.01", field_value: "annual")
    end
  end

  before do
    profile.update!(resolved_catalog_json: JSON.parse(OscalResolvedProfileCatalogService.new(profile).export))
  end

  let(:boundary) { create(:authorization_boundary) }

  subject(:sap) do
    SapGeneratorService.new(name: "Generated Plan", profile_document: profile,
                            authorization_boundary: boundary).generate
  end

  it "emits no raw parameter markup" do
    control = sap.sap_controls.find_by(control_id: "ac-1")

    expect(control.objective.to_s).not_to include("{{ insert"),
      "the plan handed an assessor unresolved parameter markup"
  end

  it "carries the value the PROFILE tailored, not the catalog's placeholder" do
    control = sap.sap_controls.find_by(control_id: "ac-1")

    expect(control.objective.to_s).to include("annual")
  end

  # The FALLBACK path: a control the resolved catalog does not carry, so the
  # generator reads the raw catalog blob. There is nothing to tailor with, but it
  # must still not hand an assessor `{{ insert: param, ... }}` — the text is run
  # through the same resolver against the catalog's own parameter labels.
  #
  # This case exists because the first mutation run proved the fallback had no
  # test behind it: removing its resolver failed nothing.
  context "when the resolved catalog does not carry the control" do
    let(:ssp) { create(:ssp_document, profile_document: profile, authorization_boundary: boundary) }

    before do
      ssp.ssp_controls.create!(control_id: "ac-1", title: "Policy and Procedures")
      # A profile whose published catalog is EMPTY — the control is not in it, so
      # `objective_from_resolved` returns nil and the fallback runs.
      profile.update!(resolved_catalog_json: { "catalog" => { "controls" => [] } })
    end

    subject(:sap) do
      SapGeneratorService.new(name: "Fallback Plan", ssp_document: ssp,
                              authorization_boundary: boundary).generate
    end

    it "resolves the catalog's own parameter markup rather than emitting it" do
      control = sap.sap_controls.find_by(control_id: "ac-1")

      expect(control.objective).to be_present
      expect(control.objective).not_to include("{{ insert"),
        "the fallback handed an assessor unresolved parameter markup"
    end

    it "names the parameter it could not tailor, rather than dropping the sentence" do
      control = sap.sap_controls.find_by(control_id: "ac-1")

      expect(control.objective).to include("access control policy is reviewed")
    end
  end

  # Without a profile there is nothing to tailor with, but the plan must still
  # not emit markup — the fallback resolves against the catalog's own params.
  context "with no profile in reach" do
    subject(:sap) do
      SapGeneratorService.new(name: "Unprofiled Plan",
                              authorization_boundary: boundary,
                              profile_document: nil).generate
    end

    it "generates nothing rather than inventing a control list" do
      expect(sap.sap_controls.count).to eq(0)
    end
  end
end
