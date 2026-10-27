# frozen_string_literal: true

require "rails_helper"

# #1101 — the ATO wizard starts from what the boundary already knows. It asked
# for a baseline and CDEFs the boundary had already settled, started every
# document step on Skip, and never kept the baseline it was given. Its
# create-new fields were also posted under names the controller never read, so a
# new SSP lost its status and sensitivity, and a new SAP or SAR its type and
# dates. The forms below are submitted as the page renders them.
RSpec.describe "ATO wizard defaults (#1101)", type: :request do
  let(:boundary) { create(:authorization_boundary) }
  let(:resolved_catalog_json) do
    { "catalog" => { "uuid" => SecureRandom.uuid,
                     "metadata" => { "title" => "Baseline", "version" => "1.0.0", "oscal-version" => "1.1.2",
                                     "last-modified" => Time.current.iso8601 },
                     "groups" => [ { "id" => "ac", "class" => "family", "title" => "Access Control",
                                     "controls" => [ { "id" => "ac-1", "class" => "SP800-53", "title" => "Policy",
                                                       "parts" => [ { "id" => "ac-1_smt", "name" => "statement",
                                                                      "prose" => "Develop a policy." } ] } ] } ] } }
  end
  let(:profile) do
    create(:profile_document, name: "Agency Moderate", lifecycle_status: "published",
                              resolved_catalog_json: resolved_catalog_json, published: Time.current.iso8601)
  end

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    sign_in_as(create(:user, :admin))
  end

  def wizard
    get ato_wizard_authorization_boundary_path(boundary)
    expect(response).to have_http_status(:ok)
    Nokogiri::HTML(response.body)
  end

  # Every named field as the browser would send it: inputs and selects with
  # their rendered values, checked radios and checkboxes only.
  def rendered_params(page, overrides = {})
    form = page.at_css("form[action='#{create_ato_package_authorization_boundary_path(boundary)}']")
    params = {}
    form.css("input[name], select[name], textarea[name]").each do |el|
      name = el["name"]
      next if name.end_with?("_radio") || name == "authenticity_token"
      next if el["type"] == "checkbox" && !el.key?("checked")

      value = el.name == "select" ? (el.at_css("option[selected]") || el.at_css("option"))&.[]("value") : el["value"]
      name.end_with?("[]") ? (params[name.delete_suffix("[]")] ||= []) << value : params[name] = value
    end
    params.merge(overrides)
  end

  describe "the baseline" do
    it "is settled context when the boundary has one, and that one is used" do
      boundary.update!(profile_document: profile)
      page = wizard

      expect(page.at_css("[data-testid='profile-settled']").text).to include("Agency Moderate", "set on this boundary")
      expect(page.css("select[name='profile_document_id']")).to be_empty
      expect(page.css("input[name='profile_radio']")).to be_empty

      other = create(:profile_document, lifecycle_status: "published", resolved_catalog_json: resolved_catalog_json)
      post create_ato_package_authorization_boundary_path(boundary),
           params: rendered_params(page, "profile_document_id" => other.id.to_s)
      expect(boundary.reload.profile_document).to eq(profile)
    end

    it "warns when the settled baseline is not published yet" do
      boundary.update!(profile_document: create(:profile_document, lifecycle_status: "started"))
      expect(wizard.at_css("[data-testid='profile-not-ready']")).to be_present
    end

    it "is asked for when the boundary has none, and the choice becomes its baseline" do
      profile
      page = wizard
      expect(page.at_css("select[name='profile_document_id'] option[value='#{profile.id}']")).to be_present

      post create_ato_package_authorization_boundary_path(boundary),
           params: rendered_params(page, "profile_mode" => "select_existing", "profile_document_id" => profile.id.to_s)

      expect(response).to redirect_to(authorization_boundary_path(boundary))
      expect(boundary.reload.profile_document).to eq(profile)
    end

    it "offers only published baselines with a resolved catalog" do
      draft = create(:profile_document, lifecycle_status: "started")
      expect(wizard.at_css("select[name='profile_document_id'] option[value='#{draft.id}']")).to be_nil
    end
  end

  describe "components" do
    it "shows the boundary's CDEFs as linked rather than offering them again" do
      linked = create(:cdef_document, name: "Managed Postgres", status: "completed")
      env = boundary.boundaries.create!(name: "Prod", environment: "production")
      env.boundary_cdef_documents.create!(cdef_document: linked)
      other = create(:cdef_document, name: "Load Balancer", status: "completed")

      page = wizard
      expect(page.at_css("[data-testid='cdefs-linked']").text).to include("Managed Postgres")
      offered = page.css("input[name='cdef_document_ids[]']").map { _1["value"] }
      expect(offered).to include(other.id.to_s)
      expect(offered).not_to include(linked.id.to_s)
    end
  end

  describe "document steps" do
    it "starts on the boundary's one current SSP, chosen and labelled" do
      ssp = create(:ssp_document, name: "HR Portal SSP", status: "completed", authorization_boundary: boundary)
      page = wizard

      expect(page.at_css("input#ssp_mode")["value"]).to eq("select_existing")
      expect(page.at_css("input[name='ssp_radio'][value='select_existing']").key?("checked")).to be(true)
      expect(page.at_css("select[name='ssp_document_id'] option[selected]")["value"]).to eq(ssp.id.to_s)
      expect(page.at_css("#ssp_select_existing_panel")["class"]).not_to include("sparc-d-none")
      expect(page.at_css("[data-testid='ssp-current']").text).to include("Using the boundary's current SSP", "HR Portal SSP")
      # Choose another, and Create new, stay available.
      expect(page.at_css("input[name='ssp_radio'][value='create_new']")).to be_present

      post create_ato_package_authorization_boundary_path(boundary), params: rendered_params(page)
      expect(response).to redirect_to(authorization_boundary_path(boundary))
    end

    it "lists several without choosing one, and says to choose when none is picked" do
      2.times { |i| create(:sap_document, name: "Plan #{i}", status: "completed", authorization_boundary: boundary) }
      page = wizard

      expect(page.at_css("[data-testid='sap-several']").text).to include("2 SAPs")
      expect(page.at_css("select[name='sap_document_id'] option[selected]")).to be_nil

      post create_ato_package_authorization_boundary_path(boundary), params: rendered_params(page)
      expect(flash[:error]).to include("choose a SAP to use, or skip that step")
    end

    it "starts on Skip when the boundary has none" do
      page = wizard
      %w[ssp sap sar poam].each do |step|
        expect(page.at_css("input##{step}_mode")["value"]).to eq("skip"), step
        expect(page.at_css("##{step}_select_existing_panel")["class"]).to include("sparc-d-none")
      end
    end

    it "never chooses a boundary-less document for the author" do
      # Boundary-less documents predate #952 and cannot be created any more.
      create(:ssp_document, status: "completed").update_columns(authorization_boundary_id: nil)
      expect(wizard.at_css("input#ssp_mode")["value"]).to eq("skip")
    end
  end

  describe "create new, as the form posts it" do
    it "keeps a new SSP's status, sensitivity and objectives" do
      boundary.update!(profile_document: profile)
      page = wizard
      names = page.css("#ssp_create_new_panel select").map { _1["name"] }
      expect(names).to contain_exactly("system_status", "security_sensitivity_level", "security_objective_confidentiality",
                                       "security_objective_integrity", "security_objective_availability")

      post create_ato_package_authorization_boundary_path(boundary), params: rendered_params(page,
        "ssp_mode" => "create_new", "ssp_name" => "New SSP", "system_status" => "under-development",
        "security_sensitivity_level" => "fips-199-moderate", "security_objective_confidentiality" => "fips-199-high",
        "security_objective_integrity" => "fips-199-moderate", "security_objective_availability" => "fips-199-low")

      expect(flash[:error]).to be_nil
      ssp = SspDocument.find_by!(name: "New SSP")
      expect(ssp).to have_attributes(system_status: "under-development", security_sensitivity_level: "fips-199-moderate",
                                     security_objective_confidentiality: "fips-199-high",
                                     security_objective_integrity: "fips-199-moderate",
                                     security_objective_availability: "fips-199-low",
                                     authorization_boundary_id: boundary.id, profile_document_id: profile.id)
    end

    it "keeps a new SAP's type and dates, and a new SAR's dates" do
      page = wizard
      expect(page.css("#sap_create_new_panel select, #sap_create_new_panel input").map { _1["name"] })
        .to include("assessment_type", "assessment_start", "assessment_end")
      expect(page.css("#sar_create_new_panel input").map { _1["name"] })
        .to include("sar_assessment_start", "sar_assessment_end")

      post create_ato_package_authorization_boundary_path(boundary), params: rendered_params(page,
        "sap_mode" => "create_new", "sap_name" => "New SAP", "assessment_type" => "annual",
        "assessment_start" => "2027-02-01", "assessment_end" => "2027-02-28",
        "sar_mode" => "create_new", "sar_name" => "New SAR",
        "sar_assessment_start" => "2027-03-01", "sar_assessment_end" => "2027-03-15")

      expect(flash[:error]).to be_nil
      sap = SapDocument.find_by!(name: "New SAP")
      expect(sap).to have_attributes(assessment_type: "annual")
      expect(sap.assessment_start.to_date).to eq(Date.new(2027, 2, 1))
      expect(sap.assessment_end.to_date).to eq(Date.new(2027, 2, 28))
      sar = SarDocument.find_by!(name: "New SAR")
      expect(sar.assessment_start.to_date).to eq(Date.new(2027, 3, 1))
      expect(sar.assessment_end.to_date).to eq(Date.new(2027, 3, 15))
    end
  end
end
