# frozen_string_literal: true

require "rails_helper"

# #895 — second slice of the Catalog API. The web UI has been able to add and
# tailor catalog controls all along; the API could not reach them at all.
RSpec.describe "Api::V1::CatalogControls", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:token) { ApiToken.generate!(user: admin, name: "Test") }
  let(:auth)  { { "Authorization" => "Bearer #{token.plaintext_token}" } }

  let(:catalog) { create(:control_catalog, name: "NIST 800-53 Rev 5") }
  let(:family)  { create(:control_family, control_catalog: catalog, code: "AC", name: "Access Control") }

  let!(:control) do
    family.catalog_controls.create!(
      control_id: "ac-2", label: "AC-2", title: "Account Management",
      baseline_impact: "LOW, MODERATE, HIGH",
      guidance_data: { "statement" => "Manage accounts.", "supplemental_guidance" => "Original guidance." }
    )
  end

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  def catalog_path(cat = catalog) = "/api/v1/control_catalogs/#{cat.oscal_uuid}/controls"
  def family_path(fam = family) = "/api/v1/control_catalogs/#{catalog.oscal_uuid}/control_families/#{fam.code.downcase}/controls"

  describe "GET index" do
    it "lists the catalog's controls with their URL identifier" do
      get catalog_path, headers: auth

      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["data"].map { |c| c["identifier"] }).to include("ac-2")
      expect(body["meta"]).to include("page", "count")
    end

    it "does not leak controls from another catalog" do
      other_family = create(:control_family, control_catalog: create(:control_catalog), code: "ZZ")
      other_family.catalog_controls.create!(control_id: "zz-1", title: "Elsewhere")

      get catalog_path, headers: auth

      expect(JSON.parse(response.body)["data"].map { |c| c["control_id"] }).not_to include("zz-1")
    end

    it "scopes to one family when listed through the family" do
      other = create(:control_family, control_catalog: catalog, code: "AU")
      other.catalog_controls.create!(control_id: "au-1", title: "Audit Policy")

      get family_path, headers: auth

      ids = JSON.parse(response.body)["data"].map { |c| c["control_id"] }
      expect(ids).to include("ac-2")
      expect(ids).not_to include("au-1")
    end

    it "filters out statement sub-parts with top_level" do
      family.catalog_controls.create!(control_id: "ac-2a", title: "Sub-part")

      get "#{catalog_path}?top_level=true", headers: auth

      ids = JSON.parse(response.body)["data"].map { |c| c["control_id"] }
      expect(ids).to include("ac-2")
      expect(ids).not_to include("ac-2a")
    end

    it "filters by baseline level" do
      family.catalog_controls.create!(control_id: "ac-3", title: "Low only", baseline_impact: "LOW")

      get "#{catalog_path}?baseline=HIGH", headers: auth

      ids = JSON.parse(response.body)["data"].map { |c| c["control_id"] }
      expect(ids).to include("ac-2")
      expect(ids).not_to include("ac-3")
    end
  end

  describe "GET show" do
    it "addresses a control by its canonical identifier" do
      get "#{catalog_path}/ac-2", headers: auth

      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["data"]
      expect(data["title"]).to eq("Account Management")
      expect(data["guidance_data"]["statement"]).to eq("Manage accounts.")
      expect(data["control_catalog"]["uuid"]).to eq(catalog.oscal_uuid)
    end

    # #881: 48% of catalog rows are statement sub-parts, and their identifiers
    # contain dots. Without `format: false` on the route Rails strips `.1` as a
    # format extension and the control cannot be addressed at all.
    it "addresses a dotted sub-part identifier without losing the last segment" do
      family.catalog_controls.create!(control_id: "ac-2(4)(b)(1)", title: "Deep sub-part")

      get "#{catalog_path}/ac-2.4.b.1", headers: auth

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["data"]["title"]).to eq("Deep sub-part")
    end

    it "lists direct children only, not every prefix match" do
      family.catalog_controls.create!(control_id: "ac-2a", title: "Child")
      family.catalog_controls.create!(control_id: "ac-2a.1", title: "Grandchild")
      # `ac-20` starts with `ac-2` but is a separate control, not a sub-part.
      family.catalog_controls.create!(control_id: "ac-20", title: "Different control")

      get "#{catalog_path}/ac-2", headers: auth

      children = JSON.parse(response.body)["data"]["sub_parts"].map { |c| c["control_id"] }
      expect(children).to contain_exactly("ac-2a")
    end

    it "404s for a control that lives in a different catalog" do
      other_catalog = create(:control_catalog)
      other_family = create(:control_family, control_catalog: other_catalog, code: "ZZ")
      other_family.catalog_controls.create!(control_id: "zz-1", title: "Elsewhere")

      get "#{catalog_path}/zz-1", headers: auth

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST create" do
    it "creates a control in the family and audits it" do
      expect {
        post family_path, headers: auth, params: {
          catalog_control: {
            control_id: "ac-3", label: "AC-3", title: "Access Enforcement",
            baseline_levels: %w[LOW HIGH],
            guidance_data: { statement: "Enforce approved authorizations." }
          }
        }
      }.to change { family.catalog_controls.count }.by(1)

      expect(response).to have_http_status(:created)
      data = JSON.parse(response.body)["data"]
      expect(data["identifier"]).to eq("ac-3")
      expect(data["baseline_impact"]).to eq("LOW, HIGH")
      expect(data["baseline_levels"]).to eq(%w[LOW HIGH])
      expect(AuditEvent.where(action: "api_catalog_control_created")).to exist
    end

    # `false` is a value, not an absence. A blank-stripping create would drop
    # the KSI booleans that Api::V1::KsiCatalogController reads back. Posted as
    # JSON deliberately: form encoding would turn `false` into the string
    # "false" and the distinction under test would disappear.
    it "stores a false guidance value rather than dropping it as blank" do
      post family_path, headers: auth, as: :json, params: {
        catalog_control: {
          control_id: "ac-4", title: "KSI style",
          guidance_data: { automation_required: false, evidence_type: "config" }
        }
      }

      expect(response).to have_http_status(:created)
      created = family.catalog_controls.find_by(control_id: "ac-4")
      expect(created.guidance_data).to eq("automation_required" => false, "evidence_type" => "config")
    end

    it "refuses a duplicate control_id in the same family" do
      post family_path, headers: auth, params: { catalog_control: { control_id: "ac-2", title: "Dupe" } }

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "refuses a control with no control_id" do
      post family_path, headers: auth, params: { catalog_control: { title: "Nameless" } }

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "404s when the family is not in this catalog" do
      elsewhere = create(:control_family, control_catalog: create(:control_catalog), code: "QQ")

      post family_path(elsewhere), headers: auth,
           params: { catalog_control: { control_id: "qq-1", title: "X" } }

      expect(response).to have_http_status(:not_found)
    end
  end

  # The safeguard the owner called for. guidance_data is a free-form JSONB
  # column read by every OSCAL exporter, so the endpoint enumerates it rather
  # than accepting the loose hash the web form permits.
  describe "parameter enumeration" do
    it "drops an unenumerated guidance key instead of writing it to the column" do
      patch "#{catalog_path}/ac-2", headers: auth, params: {
        catalog_control: {
          guidance_data: { supplemental_guidance: "Updated.", injected_key: "should not land" }
        }
      }

      expect(response).to have_http_status(:ok)
      expect(control.reload.guidance_data).to include("supplemental_guidance" => "Updated.")
      expect(control.guidance_data).not_to have_key("injected_key")
    end

    it "drops an unenumerated attribute instead of writing it to the record" do
      patch "#{catalog_path}/ac-2", headers: auth, params: {
        catalog_control: { title: "Renamed", control_family_id: 999_999, id: 12_345 }
      }

      expect(response).to have_http_status(:ok)
      expect(control.reload.title).to eq("Renamed")
      expect(control.control_family_id).to eq(family.id)
      expect(control.id).not_to eq(12_345)
    end

    it "keeps the enumerated OSCAL parameter shape and drops the rest" do
      patch "#{catalog_path}/ac-2", headers: auth, params: {
        catalog_control: {
          params_data: [ {
            id: "ac-02_odp.01", label: "time period",
            select: { "how-many": "one-or-more", choice: %w[remove disable] },
            guidelines: [ { prose: "Organization-defined." } ],
            props: [ { name: "label", value: "AC-02_ODP[01]", class: "sp800-53a" } ],
            smuggled: "nope"
          } ]
        }
      }

      expect(response).to have_http_status(:ok)
      param = control.reload.params_list.first
      expect(param["id"]).to eq("ac-02_odp.01")
      expect(param.dig("select", "choice")).to eq(%w[remove disable])
      expect(param.dig("props", 0, "class")).to eq("sp800-53a")
      expect(param).not_to have_key("smuggled")
    end
  end

  describe "PATCH update" do
    # A JSONB column assigned wholesale drops every key the caller did not
    # resend. That loss would only surface in an OSCAL export much later.
    it "merges guidance_data rather than replacing the whole document" do
      patch "#{catalog_path}/ac-2", headers: auth, params: {
        catalog_control: { guidance_data: { supplemental_guidance: "Tailored for this system." } }
      }

      expect(response).to have_http_status(:ok)
      expect(control.reload.guidance_data).to eq(
        "statement" => "Manage accounts.",
        "supplemental_guidance" => "Tailored for this system."
      )
    end

    it "deletes a guidance key when it is sent empty" do
      patch "#{catalog_path}/ac-2", headers: auth, params: {
        catalog_control: { guidance_data: { supplemental_guidance: "" } }
      }

      expect(control.reload.guidance_data).to eq("statement" => "Manage accounts.")
    end

    it "relabels a single ODP without resending the whole params array" do
      control.update!(params_data: [
        { "id" => "ac-2_prm_1", "label" => "original", "guidelines" => [ { "prose" => "keep me" } ] },
        { "id" => "ac-2_prm_2", "label" => "untouched" }
      ])

      patch "#{catalog_path}/ac-2", headers: auth, params: {
        catalog_control: { params_labels: { "ac-2_prm_1" => "organization-defined frequency" } }
      }

      expect(response).to have_http_status(:ok)
      params = control.reload.params_list
      expect(params.find { |p| p["id"] == "ac-2_prm_1" }["label"]).to eq("organization-defined frequency")
      expect(params.find { |p| p["id"] == "ac-2_prm_1" }["guidelines"]).to eq([ { "prose" => "keep me" } ])
      expect(params.find { |p| p["id"] == "ac-2_prm_2" }["label"]).to eq("untouched")
    end

    it "records the changed fields in the audit event" do
      patch "#{catalog_path}/ac-2", headers: auth, params: { catalog_control: { title: "Renamed" } }

      event = AuditEvent.find_by(action: "api_catalog_control_updated")
      expect(event).to be_present
      expect(event.metadata["fields"]).to include("title")
    end

    # The delimiter split is a bare "," rather than /\s*,\s*/ — the regex form
    # backtracks polynomially on unbounded request data. Whitespace around the
    # levels must still be tolerated, which is what the per-token strip does.
    it "still accepts a comma-separated string with surrounding whitespace" do
      patch "#{catalog_path}/ac-2", headers: auth, params: {
        catalog_control: { baseline_impact: "  LOW ,   MODERATE  " }
      }

      expect(response).to have_http_status(:ok)
      expect(control.reload.baseline_levels).to eq(%w[LOW MODERATE])
    end

    it "rejects an unknown baseline level in a whitespace-padded string" do
      patch "#{catalog_path}/ac-2", headers: auth, params: {
        catalog_control: { baseline_impact: "LOW ,  CATASTROPHIC" }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(control.reload.baseline_impact).to eq("LOW, MODERATE, HIGH")
    end

    it "rejects an unknown baseline level instead of storing it" do
      patch "#{catalog_path}/ac-2", headers: auth, params: {
        catalog_control: { baseline_levels: %w[LOW CATASTROPHIC] }
      }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("CATASTROPHIC")
      expect(control.reload.baseline_impact).to eq("LOW, MODERATE, HIGH")
    end

    # The canonical identifier is derived from control_id, so renaming the
    # control moves its URL. Prove the new identifier resolves.
    it "moves the identifier when control_id changes" do
      patch "#{catalog_path}/ac-2", headers: auth, params: { catalog_control: { control_id: "ac-2.1" } }

      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["data"]["identifier"]).to eq("ac-2.1")

      get "#{catalog_path}/ac-2.1", headers: auth
      expect(response).to have_http_status(:ok)
    end
  end

  describe "DELETE destroy" do
    it "deletes a leaf control and audits it" do
      expect {
        delete "#{catalog_path}/ac-2", headers: auth
      }.to change { family.catalog_controls.count }.by(-1)

      expect(response).to have_http_status(:ok)
      expect(AuditEvent.where(action: "api_catalog_control_deleted")).to exist
    end

    # Sub-parts are separate rows with no foreign key to their parent, so a
    # cascade would leave them pointing at a control that no longer exists.
    it "refuses to delete a control that still has sub-parts" do
      family.catalog_controls.create!(control_id: "ac-2a", title: "Sub-part")

      expect {
        delete "#{catalog_path}/ac-2", headers: auth
      }.not_to change { family.catalog_controls.count }

      expect(response).to have_http_status(:unprocessable_entity)
      expect(JSON.parse(response.body)["sub_parts"]).to eq([ "ac-2a" ])
    end
  end

  describe "authentication and authorization" do
    it "refuses an unauthenticated request" do
      get catalog_path
      expect(response).to have_http_status(:unauthorized)
    end

    it "refuses a write without catalogs.write" do
      reader = create(:user)
      reader_token = ApiToken.generate!(user: reader, name: "Reader")

      patch "#{catalog_path}/ac-2",
            headers: { "Authorization" => "Bearer #{reader_token.plaintext_token}" },
            params: { catalog_control: { title: "Nope" } }

      expect(response).to have_http_status(:forbidden)
      expect(control.reload.title).to eq("Account Management")
    end

    it "allows a read without catalogs.write" do
      reader = create(:user)
      reader_token = ApiToken.generate!(user: reader, name: "Reader")

      get catalog_path, headers: { "Authorization" => "Bearer #{reader_token.plaintext_token}" }

      expect(response).to have_http_status(:ok)
    end
  end

  # #895 — the nested endpoints document the uuid as the stable identity, so
  # the catalog's own endpoint has to accept it too.
  describe "catalog identifier consistency" do
    it "resolves the catalog by uuid, slug and numeric id on its own endpoint" do
      [ catalog.oscal_uuid, catalog.slug, catalog.id ].each do |form|
        get "/api/v1/control_catalogs/#{form}", headers: auth
        expect(response).to have_http_status(:ok), "#{form.inspect} did not resolve"
      end
    end
  end
end
