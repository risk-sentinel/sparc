# frozen_string_literal: true

require "rails_helper"

# #902 follow-up — the JSON the evidence control picker calls.
#
# It exists because Api::V1 is Bearer-only and excludes cookies, so the browser
# cannot reach the API endpoint. Both run ControlLookupService: the thing that
# OFFERS identifiers and the thing that VALIDATES them must not be able to
# disagree, or the picker starts suggesting controls the server then rejects.
RSpec.describe "Control lookup (#902)", type: :request do
  let(:user) { create(:user, :admin) }

  # NOT a global `before` — sign_in_as stubs current_user on
  # ApplicationController rather than setting a cookie, so `reset!` cannot undo
  # it and the signed-out case below would never redirect.
  def signed_in!
    sign_in_as(user)
  end

  describe "GET /controls/lookup" do
    it "requires authentication" do
      ensure_control("ac-2")
      # Signed-out: the gate only engages when a login method is configured.
      allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
      reset!

      get control_lookup_path, params: { q: "ac-2" }

      expect(response).to have_http_status(:redirect)
    end

    it "finds a control by its canonical identifier" do
      signed_in!
      ensure_control("ac-2")

      get control_lookup_path, params: { q: "ac-2" }

      expect(response).to have_http_status(:ok)
      ids = JSON.parse(response.body)["data"].map { |c| c["control_id"] }
      expect(ids).to include("ac-2")
    end

    # The bug in one assertion: SPARC shows AC-02, the catalog stores ac-2.
    # Searching what is on screen has to find what is stored.
    it "finds a control by the PADDED form SPARC displays" do
      signed_in!
      ensure_control("ac-2")

      get control_lookup_path, params: { q: "AC-02" }

      ids = JSON.parse(response.body)["data"].map { |c| c["control_id"] }
      expect(ids).to include("ac-2")
    end

    it "finds a control by title" do
      signed_in!
      control = ensure_control("ac-2", title: "Account Management")

      get control_lookup_path, params: { q: control.title.split.first }

      titles = JSON.parse(response.body)["data"].map { |c| c["title"] }
      expect(titles).to include(control.title)
    end

    it "returns enhancements, flagged as such" do
      signed_in!
      ensure_control("ac-2.1", title: "Automated System Account Management")

      get control_lookup_path, params: { q: "ac-2.1" }

      row = JSON.parse(response.body)["data"].find { |c| c["control_id"] == "ac-2.1" }
      expect(row).to be_present
      expect(row["enhancement"]).to be true
      expect(row["display_id"]).to be_present
    end

    it "serialises all three legitimate forms so a client need not re-derive them" do
      signed_in!
      ensure_control("ac-2")

      get control_lookup_path, params: { q: "ac-2" }

      row = JSON.parse(response.body)["data"].find { |c| c["control_id"] == "ac-2" }
      expect(row["control_id"]).to eq("ac-2")
      expect(row["padded_id"]).to eq("AC-02")
      expect(row["display_id"]).to be_present
    end

    # Verified against the real seeded catalogs: ac-2 exists in both the NIST
    # Rev 4 and Rev 5 catalogs, and returning both gave two rows a user cannot
    # tell apart — while picking either stores the identical identifier.
    it "lists an identifier once even when several catalogs carry it" do
      signed_in!
      control = ensure_control("ac-2")
      other_catalog_family = create(:control_family, code: "AC")
      create(:catalog_control, control_family: other_catalog_family,
                               control_id: control.control_id, title: control.title)

      get control_lookup_path, params: { q: "ac-2" }

      ids = JSON.parse(response.body)["data"].map { |c| c["control_id"] }
      expect(ids.count("ac-2")).to eq(1), "the same identifier was offered #{ids.count('ac-2')} times"
      expect(ids.uniq.size).to eq(ids.size)
    end

    it "returns nothing for an identifier that names no control" do
      signed_in!
      ensure_control("ac-2")

      get control_lookup_path, params: { q: "zz-999" }

      expect(JSON.parse(response.body)["data"]).to be_empty
    end

    it "caps the result set" do
      signed_in!
      family = create(:control_family, code: "AC")
      30.times { |n| create(:catalog_control, control_family: family, control_id: "ac-#{n + 1}") }

      get control_lookup_path, params: { q: "ac-", limit: 5 }

      expect(JSON.parse(response.body)["data"].size).to eq(5)
      expect(JSON.parse(response.body)["meta"]["limit"]).to eq(5)
    end

    context "when the boundary carries a baseline" do
      it "narrows to that profile's controls and says so" do
        signed_in!
        in_baseline = ensure_control("ac-2")
        ensure_control("si-4")

        profile = create(:profile_document, name: "FedRAMP Moderate")
        create(:profile_control, profile_document: profile, control_id: in_baseline.control_id)
        boundary = create(:authorization_boundary, profile_document: profile)

        get control_lookup_path, params: { q: "-", authorization_boundary_id: boundary.id }

        body = JSON.parse(response.body)
        ids = body["data"].map { |c| c["control_id"] }
        expect(ids).to include("ac-2")
        expect(ids).not_to include("si-4")
        expect(body["meta"]["scoped_to_profile"]).to be true
        expect(body["meta"]["profile_title"]).to eq("FedRAMP Moderate")
      end

      # The common case today: no boundary has a baseline, so falling back to
      # every catalog is the load-bearing path, not an edge case.
      it "falls back to every catalog when the boundary has no baseline" do
        signed_in!
        ensure_control("ac-2")
        boundary = create(:authorization_boundary, profile_document: nil)

        get control_lookup_path, params: { q: "ac-2", authorization_boundary_id: boundary.id }

        body = JSON.parse(response.body)
        expect(body["data"].map { |c| c["control_id"] }).to include("ac-2")
        expect(body["meta"]["scoped_to_profile"]).to be false
      end
    end
  end
end
