# frozen_string_literal: true

require "rails_helper"

RSpec.describe "AuthorizationBoundaries", type: :request do
  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    allow(SparcConfig).to receive(:enable_local_login?).and_return(true)
  end

  let(:user) { create(:user) }
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

    it "still shows legacy memberships with their edit/remove controls" do
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
  describe "GET /authorization_boundaries/:id (Artifacts card)" do
    before { sign_in_as(user) }

    it "lists evidence tied to the boundary with a pre-scoped Add link" do
      create(:evidence, authorization_boundary: ab, title: "Scan Result Q3")
      get authorization_boundary_path(ab)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("Scan Result Q3")
      expect(response.body).to include(new_evidence_path(authorization_boundary_id: ab.id))
    end

    it "shows an empty state when the boundary has no artifacts" do
      get authorization_boundary_path(ab)
      expect(response.body).to include("No artifacts attached")
    end
  end

  describe "GET /evidences/new (boundary pre-scoping, #770 bug 5)" do
    before { sign_in_as(user) }

    it "pre-selects the authorization boundary from the query param" do
      get new_evidence_path(authorization_boundary_id: ab.id)
      expect(response).to have_http_status(:ok)
      # The boundary select renders the scoped boundary as the selected option.
      expect(response.body).to match(
        %r{<option selected(?:="selected")? value="#{ab.id}">#{Regexp.escape(ab.name)}</option>}
      )
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
      expect(response.body).to include(ERB::Util.html_escape(ab.name))
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
    before { sign_in_as(user) }

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
end
