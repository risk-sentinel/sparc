# frozen_string_literal: true

require "rails_helper"

RSpec.describe "AuthorizationBoundaries", type: :request do
  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    allow(SparcConfig).to receive(:enable_local_login?).and_return(true)
  end

  # #1244 — every action now checks the caller's permission on the boundary.
  # These examples signed in a user holding nothing, and passed only because
  # nothing was checked. They now grant what each action requires: read and
  # write on `ab`. Destroy is administrator-only, so its example signs in one.
  let(:user) do
    create(:user).tap do |u|
      grant_permission(u, "authorization_boundaries.read", authorization_boundary: ab)
      grant_permission(u, "authorization_boundaries.write", authorization_boundary: ab)
    end
  end
  let(:ab) { create(:authorization_boundary) }

  # #770 bug 4 — Artifact Summary tiles are uniform and clickable. The POA&M
  # tile previously omitted the shared font-size and had no link.
  describe "GET /authorization_boundaries/:id (Artifact Summary tiles)" do
    before { sign_in_as(user) }

    it "renders every artifact tile as a link, POA&M included" do
      get authorization_boundary_path(ab)
      expect(response).to have_http_status(:ok)

      # All four tiles carry the clickable wrapper class.
      link_count = response.body.scan("sparc-hero-tile-link").size
      expect(link_count).to be >= 4

      # The POA&M tile links to the POA&M index (was a bare, unlinked count).
      expect(response.body).to include("href=\"#{poam_documents_path}\"")
    end

    it "sizes the POA&M count consistently with the other tiles" do
      get authorization_boundary_path(ab)
      # Every hero-tile-count now carries the 1rem override; none inherits 2rem.
      counts = response.body.scan(/sparc-hero-tile-count[^>]*>/)
      expect(counts).to be_present
      expect(counts).to all(include("font-size: 1rem"))
    end
  end

  # #770 bug 3 — personnel assigned via admin (user_roles) must appear on the
  # boundary screen's roster, which previously read only legacy memberships.
  describe "GET /authorization_boundaries/:id (Personnel Roster)" do
    before { sign_in_as(user) }

    it "shows an admin-assigned member (user_role), not just legacy memberships" do
      member = create(:user, email: "admin-added@example.com", first_name: "Ada", last_name: "Assigned")
      role = create(:role, :authorization_boundary_scoped, display_name: "System Owner")
      create(:user_role, user: member, role: role, authorization_boundary: ab)

      get authorization_boundary_path(ab)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("admin-added@example.com")
      expect(response.body).to include("System Owner")
    end

    # #1251 — the roster's Edit/Remove appear only to someone the memberships
    # controller admits (authorization_boundaries.manage_members), so this
    # example grants that key; it relied on the controls showing to anyone.
    it "still shows legacy memberships with their edit/remove controls" do
      grant_permission(user, "authorization_boundaries.manage_members", authorization_boundary: ab)
      create(:authorization_boundary_membership, authorization_boundary: ab,
             user_name: "Legacy Member", user_email: "legacy@example.com")

      get authorization_boundary_path(ab)

      expect(response.body).to include("Legacy Member")
      expect(response.body).to include(edit_authorization_boundary_membership_path(
        ab, ab.authorization_boundary_memberships.first
      ))
    end
  end

  # #770 bug 5 — boundary-scoped artifacts (evidence) surfaced on the screen.
  # #1251 renamed the section "Evidence" and offers Add Evidence only with
  # evidence.write on the boundary, so this example grants it.
  describe "GET /authorization_boundaries/:id (Evidence section)" do
    before { sign_in_as(user) }

    it "lists evidence tied to the boundary with a pre-scoped Add link" do
      grant_permission(user, "evidence.write", authorization_boundary: ab)
      create(:evidence, authorization_boundary: ab, title: "Scan Result Q3")
      get authorization_boundary_path(ab)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Scan Result Q3")
      expect(response.body).to include(new_evidence_path(authorization_boundary_id: ab.id))
    end

    it "shows an empty state when the boundary has no evidence" do
      get authorization_boundary_path(ab)
      expect(response.body).to include("No evidence attached")
    end
  end

  describe "GET /evidences/new (boundary pre-scoping, #770 bug 5)" do
    before { sign_in_as(user) }

    # Assert on the parsed DOM, not the raw HTML. `options_for_select` escapes the
    # option text, so a boundary named "Schiller, O'Hara and Abbott ATO" renders as
    # "Schiller, O&#39;Hara and Abbott ATO". The previous regex compared the raw
    # name against the escaped body, so this spec failed whenever Faker happened to
    # generate a name containing ' & < > or " — an intermittent CI failure that had
    # nothing to do with the code under test. Nokogiri decodes the entities for us.
    def selected_boundary_option
      Nokogiri::HTML(response.body)
              .at_css("select#evidence_authorization_boundary_id option[selected]")
    end

    it "pre-selects the authorization boundary from the query param" do
      get new_evidence_path(authorization_boundary_id: ab.id)
      expect(response).to have_http_status(:ok)

      option = selected_boundary_option
      expect(option).to be_present
      expect(option["value"]).to eq(ab.id.to_s)
      expect(option.text).to eq(ab.name)
    end

    it "pre-selects a boundary whose name contains HTML-escapable characters" do
      tricky = create(:authorization_boundary, name: %q(Schiller, O'Hara & Abbott <ATO>))
      get new_evidence_path(authorization_boundary_id: tricky.id)
      expect(response).to have_http_status(:ok)

      option = selected_boundary_option
      expect(option["value"]).to eq(tricky.id.to_s)
      expect(option.text).to eq(tricky.name)
    end
  end

  describe "GET /authorization_boundaries/:id/ato_wizard" do
    before { sign_in_as(user) }

    it "returns 200 for a signed-in user" do
      get ato_wizard_authorization_boundary_path(ab)
      expect(response).to have_http_status(:ok)
    end

    it "renders the ATO wizard page" do
      get ato_wizard_authorization_boundary_path(ab)
      expect(response.body).to include(html_text(ab.name))
    end
  end

  describe "POST /authorization_boundaries/:id/create_ato_package" do
    before { sign_in_as(user) }

    context "with skip-all params" do
      let(:params) do
        {
          profile_mode: "skip",
          cdef_mode: "skip",
          ssp_mode: "skip",
          sap_mode: "skip",
          sar_mode: "skip",
          poam_mode: "skip"
        }
      end

      it "redirects to the authorization boundary show page" do
        post create_ato_package_authorization_boundary_path(ab), params: params
        expect(response).to redirect_to(authorization_boundary_path(ab))
      end

      it "sets a success flash message" do
        post create_ato_package_authorization_boundary_path(ab), params: params
        follow_redirect!
        expect(response.body).to include("ATO package built")
      end
    end

    context "when an error occurs" do
      it "redirects to the wizard with an error message" do
        allow_any_instance_of(AtoPackageService)
          .to receive(:create)
          .and_raise(StandardError, "something went wrong")

        post create_ato_package_authorization_boundary_path(ab), params: {
          ssp_mode: "skip", sap_mode: "skip", sar_mode: "skip",
          poam_mode: "skip", cdef_mode: "skip", profile_mode: "skip"
        }
        expect(response).to redirect_to(ato_wizard_authorization_boundary_path(ab))
      end
    end
  end

  describe "GET /authorization_boundaries/:id/download_ato_package" do
    before { sign_in_as(user) }

    context "when documents are linked" do
      let(:ssp) { create(:ssp_document, :enriched, authorization_boundary: ab) }

      before do
        ssp # ensure created

        allow_any_instance_of(AtoPackageExportService)
          .to receive(:generate_zip)
          .and_return("PK\x03\x04fake-zip-data")
      end

      it "returns a ZIP file" do
        get download_ato_package_authorization_boundary_path(ab)

        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include("application/zip")
        expect(response.headers["Content-Disposition"]).to include("attachment")
        expect(response.headers["Content-Disposition"]).to include("ato_package")
      end
    end

    context "when no documents are linked" do
      it "returns a ZIP file (with only manifest)" do
        allow_any_instance_of(AtoPackageExportService)
          .to receive(:generate_zip)
          .and_return("PK\x03\x04fake-zip-data")

        get download_ato_package_authorization_boundary_path(ab)

        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include("application/zip")
      end
    end
  end

  # #629 — single-delete now honors the referential guard (was: always "deleted").
  describe "DELETE /authorization_boundaries/:id (referential guard)" do
    before { sign_in_as(create(:user, :admin)) }

    it "blocks deletion when an SSP is attached and reports the reason" do
      boundary = create(:authorization_boundary)
      create(:ssp_document, authorization_boundary: boundary)

      delete authorization_boundary_path(boundary)

      expect(AuthorizationBoundary.exists?(boundary.id)).to be(true)
      expect(flash[:error]).to match(/SSP/)
    end
  end

  # #629 — admin-only bulk delete with partial-success reporting.
  describe "DELETE /authorization_boundaries/bulk_destroy" do
    let(:admin) { create(:user, :admin) }

    it "deletes selected unassociated boundaries and reports blocked ones (admin)" do
      sign_in_as(admin)
      deletable = create(:authorization_boundary)
      blocked   = create(:authorization_boundary)
      create(:ssp_document, authorization_boundary: blocked)

      delete bulk_destroy_authorization_boundaries_path, params: { ids: [ deletable.id, blocked.id ] }

      expect(AuthorizationBoundary.exists?(deletable.id)).to be(false)
      expect(AuthorizationBoundary.exists?(blocked.id)).to be(true)
      expect(flash[:warning]).to match(/blocked|Blocked/i)
    end

    it "is admin-only — a non-admin cannot bulk delete" do
      sign_in_as(user)
      boundary = create(:authorization_boundary)

      delete bulk_destroy_authorization_boundaries_path, params: { ids: [ boundary.id ] }

      expect(AuthorizationBoundary.exists?(boundary.id)).to be(true)
    end
  end

  # #1354 — the FedRAMP Certification Package Overview address, on the edit form.
  describe "FedRAMP package overview address" do
    before { sign_in_as(user) }

    it "is on the edit form with its field help" do
      get edit_authorization_boundary_path(ab)
      html = Nokogiri::HTML(response.body)
      expect(html.at_css("input[name='authorization_boundary[fedramp_package_overview_uri]']")).to be_present
      expect(html.css("button.sparc-field-help").map { |b| b["data-bs-title"] })
        .to include("Where your trust center publishes this system's FedRAMP Certification Package Overview. FedRAMP's reports name it.")
    end

    it "is saved from the form" do
      patch authorization_boundary_path(ab),
            params: { authorization_boundary: { fedramp_package_overview_uri: "https://example.gov/overview" } }
      expect(ab.reload.fedramp_package_overview_uri).to eq("https://example.gov/overview")
    end

    it "is refused when it is not https" do
      patch authorization_boundary_path(ab),
            params: { authorization_boundary: { fedramp_package_overview_uri: "ftp://example.gov/overview" } }
      expect(response).to have_http_status(:unprocessable_content)
      expect(ab.reload.fedramp_package_overview_uri).to be_nil
    end
  end

  # #1390 — the fields the Certification Package Overview is written from, and
  # its contacts, a list on the boundary separate from SPARC users.
  describe "FedRAMP package overview fields" do
    before { sign_in_as(user) }

    let(:form_fields) do
      { fedramp_overview_from_sparc: "false", fedramp_contacts_listed: "1",
        fedramp_package: { package_id: "FR2400000001", provider_name: "Example Provider", service_name: "Example Cloud",
                           service_acronym: "EXC", service_description: "A cloud service.", certification_type: "Rev5",
                           website: "https://provider.example", logo: "https://provider.example/logo.png",
                           service_types: [ "", "SaaS", "IaaS" ], deployment_model: "Hybrid Cloud",
                           business_categories: [ "" ], trust_center_authentication_required: "false" },
        fedramp_contacts: [ { contact_type: "Security", name: "Sec", email: "sec@provider.example", phone: "" },
                            { contact_type: "Sales", name: "Sales", email: "", phone: "202-555-0123" } ] }
    end

    it "renders every field, the address choice and the contact rows" do
      ab.update!(fedramp_contacts: [ { contact_type: "Sales", name: "Sales" } ])
      get edit_authorization_boundary_path(ab)
      html = Nokogiri::HTML(response.body)
      section = html.at_css("[data-testid='boundary-fedramp-package']")
      FedrampPackageOverview::FIELDS.each_key do |key|
        expect(section.at_css("[name^='authorization_boundary[fedramp_package][#{key}]']")).to be_present, key
      end
      expect(section.css("input[name='authorization_boundary[fedramp_overview_from_sparc]']").map { |r| r["value"] })
        .to eq(%w[false true])
      expect(section.css("[data-oscal-repeater-target='rows'] [data-testid='boundary-fedramp-contact']").size).to eq(1)
      expect(section.css("select[name='authorization_boundary[fedramp_package][certification_type]'] option").map(&:text))
        .to eq([ "", "20x", "Rev5" ])
    end

    it "saves the fields and contacts the form posts, readying the overview" do
      patch authorization_boundary_path(ab), params: { authorization_boundary: form_fields }
      expect(response).to redirect_to(authorization_boundary_path(ab))
      ab.reload
      expect(ab.fedramp_value("service_types")).to eq(%w[SaaS IaaS])
      expect(ab.fedramp_value("business_categories")).to be_nil
      expect(ab.fedramp_contacts.map { |c| c["contact_type"] }).to eq(%w[Security Sales])
      expect(ab).to be_fedramp_overview_ready
    end

    it "clears the contacts when every row is removed" do
      ab.update!(fedramp_contacts: [ { contact_type: "Sales", name: "Sales" } ])
      patch authorization_boundary_path(ab), params: { authorization_boundary: { name: ab.name, fedramp_contacts_listed: "1" } }
      expect(ab.reload.fedramp_contacts).to eq([])
    end

    it "leaves the contacts alone when the form does not list them" do
      ab.update!(fedramp_contacts: [ { contact_type: "Sales", name: "Sales" } ])
      patch authorization_boundary_path(ab), params: { authorization_boundary: { name: ab.name } }
      expect(ab.reload.fedramp_contacts.size).to eq(1)
    end

    it "re-renders with the reason when a value is not one FedRAMP allows" do
      form_fields[:fedramp_package][:logo] = "https://provider.example/logo.txt"
      patch authorization_boundary_path(ab), params: { authorization_boundary: form_fields }
      expect(response).to have_http_status(:unprocessable_content)
      expect(flash[:error]).to include("FedRAMP package overview: Logo address must be")
      expect(Nokogiri::HTML(response.body).at_css("[data-testid='boundary-fedramp-package']")["open"]).not_to be_nil
      expect(ab.reload.fedramp_package).to eq({})
    end
  end
end
