# frozen_string_literal: true

require "rails_helper"

# #1241 — the catalog editor edits a parameter's `values`, on the web form and
# the API alike (one model method, CatalogControl#merge_params_values). A select
# value that is not one of the choices is refused, 422, with nothing saved. The
# label is shown, never rewritten. Values are invented.
RSpec.describe "catalog parameter values (#1241)", type: :request do
  let(:admin)   { create(:user, :admin) }
  let(:catalog) { create(:control_catalog) }
  let(:family)  { create(:control_family, control_catalog: catalog, code: "EX") }
  let!(:control) do
    family.catalog_controls.create!(
      control_id: "ex-1", label: "EX-1", title: "Example Policy",
      params_data: [
        { "id" => "ex-01_odp.01", "label" => "frequency" },
        { "id" => "ex-01_odp.02", "select" => { "how-many" => "one", "choice" => %w[organization-level system-level] } },
        { "id" => "ex-01_odp.03", "label" => "events",
          "select" => { "how-many" => "one-or-more", "choice" => %w[audits incidents reviews] } }
      ]
    )
  end

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  def params_by_id = control.reload.params_list.index_by { |p| p["id"] }

  describe "the web form" do
    before { sign_in_as(admin) }

    it "shows a Value column bound to values, and the label read-only" do
      get control_catalog_edit_control_path(catalog.url_id, control)

      page = Nokogiri::HTML(response.body)
      expect(page.at_css("input[name='catalog_control[params_values][ex-01_odp.01]']")).to be_present
      expect(page.at_css("select[name='catalog_control[params_values][ex-01_odp.02]']")).to be_present
      expect(page.at_css("select[multiple][name='catalog_control[params_values][ex-01_odp.03][]']")).to be_present
      expect(page.css("input[name^='catalog_control[params_labels]']")).to be_empty
      expect(page.css("[data-testid='catalog-param-label']").map { |td| td.text.strip }).to include("frequency")
    end

    # The form's own action, not a hand-built path: the shallow /catalog_controls/:id
    # route reads the canonical id as a database id, and the save 404'd.
    it "saves through the address the edit form posts to" do
      get control_catalog_edit_control_path(catalog.url_id, control)
      form = Nokogiri::HTML(response.body).css("form").find { |f| f.at_css("input[name^='catalog_control[params_values]']") }
      expect(form["action"]).to eq(control_catalog_control_path(catalog.url_id, control))
      expect(form.at_css("input[name='_method']")&.[]("value")).to eq("patch")

      patch form["action"], params: { catalog_control: { params_values: { "ex-01_odp.01" => "quarterly-invented" } } }

      expect(response).to redirect_to(family)
      expect(params_by_id["ex-01_odp.01"]["values"]).to eq([ "quarterly-invented" ])
    end

    it "stores the values and leaves every label as it was" do
      patch control_catalog_control_path(catalog.url_id, control), params: { catalog_control: { params_values: {
        "ex-01_odp.01" => "quarterly-invented",
        "ex-01_odp.02" => "system-level",
        "ex-01_odp.03" => [ "", "audits", "reviews" ]
      } } }

      expect(response).to have_http_status(:redirect)
      expect(params_by_id["ex-01_odp.01"]).to include("label" => "frequency", "values" => [ "quarterly-invented" ])
      expect(params_by_id["ex-01_odp.02"]["values"]).to eq([ "system-level" ])
      expect(params_by_id["ex-01_odp.03"]).to include("label" => "events", "values" => %w[audits reviews])
    end

    it "clears a value submitted blank" do
      control.update!(params_data: control.params_list.map { |p| p["id"] == "ex-01_odp.01" ? p.merge("values" => [ "x" ]) : p })

      patch control_catalog_control_path(catalog.url_id, control), params: { catalog_control: { params_values: { "ex-01_odp.01" => "" } } }

      expect(params_by_id["ex-01_odp.01"]).not_to have_key("values")
    end

    it "refuses a select value that is not one of the choices, and saves nothing" do
      before = control.params_data

      patch control_catalog_control_path(catalog.url_id, control), params: { catalog_control: { title: "Changed", params_values: {
        "ex-01_odp.01" => "quarterly-invented", "ex-01_odp.02" => "invented-level"
      } } }

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("invented-level")
      expect(control.reload.params_data).to eq(before)
      expect(control.title).to eq("Example Policy")
    end
  end

  describe "the API" do
    let(:token) { ApiToken.generate!(user: admin, name: "Test") }
    let(:auth)  { { "Authorization" => "Bearer #{token.plaintext_token}" } }
    let(:path)  { "/api/v1/control_catalogs/#{catalog.oscal_uuid}/controls/ex-1" }

    it "sets values, an array for a multiple select, and returns them" do
      patch path, params: { catalog_control: { params_values: {
        "ex-01_odp.01" => "quarterly-invented", "ex-01_odp.03" => %w[incidents]
      } } }, headers: auth, as: :json

      expect(response).to have_http_status(:ok)
      returned = JSON.parse(response.body).dig("data", "params_data").index_by { |p| p["id"] }
      expect(returned.dig("ex-01_odp.01", "values")).to eq([ "quarterly-invented" ])
      expect(params_by_id["ex-01_odp.03"]).to include("label" => "events", "values" => [ "incidents" ])
    end

    it "refuses a select value that is not one of the choices: 422, nothing saved" do
      before = control.params_data

      patch path, params: { catalog_control: { params_values: { "ex-01_odp.02" => "invented-level" } } },
                  headers: auth, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["error"]).to include("invented-level", "not one of its choices")
      expect(control.reload.params_data).to eq(before)
    end

    it "refuses two values for a select that takes one" do
      patch path, params: { catalog_control: { params_values: { "ex-01_odp.02" => %w[organization-level system-level] } } },
                  headers: auth, as: :json

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "refuses a parameter the control does not have, rather than dropping it" do
      patch path, params: { catalog_control: { params_values: { "ex-01_odp.99" => "x" } } }, headers: auth, as: :json

      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body)["error"]).to include("ex-01_odp.99")
    end

    it "requires catalog write permission" do
      reader = create(:user)
      reader_token = ApiToken.generate!(user: reader, name: "Reader")

      patch path, params: { catalog_control: { params_values: { "ex-01_odp.01" => "x" } } },
                  headers: { "Authorization" => "Bearer #{reader_token.plaintext_token}" }, as: :json

      expect(response).to have_http_status(:forbidden)
      expect(params_by_id["ex-01_odp.01"]).not_to have_key("values")
    end
  end

  describe "the exported catalog" do
    # OSCAL allows a parameter `values` OR `select`. A select the catalog
    # answered is exported as its answer, so the document stays schema-valid.
    it "emits a select the catalog answered with its values and without the select" do
      control.update!(params_data: control.merge_params_values("ex-01_odp.02" => "system-level"))

      exported = JSON.parse(OscalCatalogExportService.new(catalog).export_unvalidated)
      params = exported.dig("catalog", "groups", 0, "controls", 0, "params").index_by { |p| p["id"] }

      expect(params["ex-01_odp.02"]).to eq("id" => "ex-01_odp.02", "values" => [ "system-level" ])
      expect(params["ex-01_odp.03"]).to have_key("select")
    end
  end
end
