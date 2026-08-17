# frozen_string_literal: true

require "rails_helper"

# #974 — what an unauthenticated caller may reach, in BOTH postures.
#
# `CdefDocumentsController` and `ControlFamiliesController` shipped a bare
# `skip_before_action :require_authentication` with no conditional gate, so the
# CDEF library and every control-family page were readable by anyone, with no
# setting that turned it off. Measured on a real instance with the flag OFF:
# `/cdef_documents` index and show and the canonical control-family page all
# returned 200 to an anonymous caller, while catalogs, profiles, mappings and
# converters correctly redirected to /login.
#
# **Both postures are asserted deliberately.** A suite that only runs with the
# flag off passes today for catalogs and never notices CDEFs; one that only runs
# with it on never notices that the gate does nothing. The rules that must hold
# REGARDLESS — no writes, no API, no boundary documents — are asserted in both.
#
# The browser-level twin is tests/ui-smoke/test_public_controls_974.py, which
# proves a real deployment behaves this way rather than a stubbed one.
RSpec.describe "Public Controls-layer access (#974)", type: :request do
  # Auth must be enabled or `require_authentication` is a no-op and every
  # example below passes against a completely ungated app.
  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  let!(:catalog) { create(:control_catalog) }
  let!(:family)  { create(:control_family, control_catalog: catalog, code: "AC") }
  let!(:profile) { create(:profile_document) }
  let!(:mapping) { create(:control_mapping) }
  let!(:cdef)    { create(:cdef_document) }
  let!(:converter) { create(:converter) }

  # Every Controls-layer READ path, as [label, path].
  def controls_read_paths
    [
      [ "catalog index",  control_catalogs_path ],
      [ "catalog show",   control_catalog_path(catalog) ],
      [ "family show",    control_catalog_family_path(catalog, family.code) ],
      [ "profile index",  profile_documents_path ],
      [ "profile show",   profile_document_path(profile) ],
      [ "mapping index",  control_mappings_path ],
      [ "mapping show",   control_mapping_path(mapping) ],
      [ "cdef index",     cdef_documents_path ],
      [ "cdef show",      cdef_document_path(cdef) ]
    ]
  end

  # Downloads follow the screens (#974): the OSCAL a reader can see is the OSCAL
  # they can fetch. Converters are the exception in the other direction — index
  # and show only, never `export`.
  def controls_download_paths
    [
      [ "catalog oscal",  download_oscal_control_catalog_path(catalog) ],
      [ "catalog yaml",   download_yaml_control_catalog_path(catalog) ],
      [ "profile json",   download_json_profile_document_path(profile) ],
      [ "profile oscal",  download_oscal_profile_document_path(profile) ],
      [ "mapping oscal",  download_oscal_control_mapping_path(mapping) ],
      [ "cdef json",      download_json_cdef_document_path(cdef) ]
    ]
  end

  context "with SPARC_PUBLIC_CATALOGS unset (the secure default)" do
    before { allow(SparcConfig).to receive(:public_catalogs?).and_return(false) }

    it "refuses every Controls-layer read to an anonymous caller" do
      controls_read_paths.each do |label, path|
        get path
        expect(response).to redirect_to(login_path), "#{label}: expected a redirect to /login, got #{response.status}"
      end
    end

    # Named separately because these two were the actual defect: they returned
    # 200 here while every sibling redirected.
    it "refuses the CDEF library specifically (#974's leak)" do
      get cdef_documents_path
      expect(response).to redirect_to(login_path)

      get cdef_document_path(cdef)
      expect(response).to redirect_to(login_path)
    end

    it "refuses the control-family page specifically (#974's leak)" do
      get control_catalog_family_path(catalog, family.code)
      expect(response).to redirect_to(login_path)
    end

    it "refuses every Controls-layer download" do
      controls_download_paths.each do |label, path|
        get path
        expect(response).to redirect_to(login_path), "#{label}: expected a redirect to /login"
      end
    end

    it "refuses the converter list and detail" do
      get converters_path
      expect(response).to redirect_to(login_path)

      get converter_path(converter)
      expect(response).to redirect_to(login_path)
    end
  end

  context "with SPARC_PUBLIC_CATALOGS=true" do
    before { allow(SparcConfig).to receive(:public_catalogs?).and_return(true) }

    # Catalogs answer a slug-addressed URL with #881's 301 to the canonical
    # UUID form, which is a legitimate public response — so the assertion is
    # "reaches the page without being sent to /login", not "200 first hop".
    # Asserting the first hop instead would have failed on a working redirect.
    it "serves every Controls-layer read to an anonymous caller" do
      controls_read_paths.each do |label, path|
        status = follow_to_final_status(path)

        expect(status).to eq(200), "#{label}: expected the page to render with the flag ON, got #{status}"
      end
    end

    it "serves every Controls-layer download" do
      controls_download_paths.each do |label, path|
        status = follow_to_final_status(path)

        expect(status).to eq(200), "#{label}: expected the download to be served, got #{status}"
      end
    end

    it "serves the converter list and detail" do
      expect(follow_to_final_status(converters_path)).to eq(200)
      expect(follow_to_final_status(converter_path(converter))).to eq(200)
    end

    # "View only, cannot fetch or update." `export` is a bulk pull of the
    # mapping data rather than a screen, so it stays behind authentication even
    # when the library is published.
    it "still refuses a converter EXPORT" do
      get export_converter_path(converter)
      expect(response).to redirect_to(login_path)
    end

    # Navigation stays where a user expects it. #974 changes VISIBILITY only —
    # an entry is offered when the visitor can reach it — and never relocates an
    # item to make it reachable. Component definitions and converters live in
    # the Implementation menu and stay there.
    it "offers the readable entries in their native menu" do
      get control_catalogs_path

      expect(response.body).to include(cdef_documents_path)
      expect(response.body).to include(converters_path)
      expect(response.body).to include("Implementation")
    end

    # The same menu must not advertise what this visitor cannot open.
    it "withholds boundary documents from that menu for an anonymous visitor" do
      get control_catalogs_path

      expect(response.body).not_to include(ssp_documents_path)
    end
  end

  # Follow up to three redirects and report the final status. Bounded so a
  # redirect loop fails the example rather than hanging it.
  #
  # A login bounce returns 302 deliberately, so the caller asserting `== 200`
  # catches it. An earlier version broke out of the loop on a login redirect and
  # then reported "status < 400", which passed on the very failure it existed to
  # detect — caught by mutating the gate to always require authentication, which
  # the spec did not notice until this was fixed.
  def follow_to_final_status(path)
    get path
    3.times do
      break unless response.redirect?
      return response.status if response.location.to_s.include?(login_path)

      follow_redirect!
    end
    response.status
  end

  # The invariants. These are asserted under BOTH postures, because a rule that
  # only holds in one of them is not a rule.
  [ false, true ].each do |public_catalogs|
    context "regardless of posture (SPARC_PUBLIC_CATALOGS=#{public_catalogs})" do
      before { allow(SparcConfig).to receive(:public_catalogs?).and_return(public_catalogs) }

      it "never exposes a boundary document" do
        boundary = create(:authorization_boundary)
        docs = {
          "ssp"  => ssp_document_path(create(:ssp_document, authorization_boundary: boundary)),
          "sap"  => sap_document_path(create(:sap_document, authorization_boundary: boundary)),
          "sar"  => sar_document_path(create(:sar_document, authorization_boundary: boundary)),
          "poam" => poam_document_path(create(:poam_document, authorization_boundary: boundary)),
          "evidence" => evidence_path(create(:evidence))
        }

        docs.each do |label, path|
          get path
          expect(response).to redirect_to(login_path),
            "#{label}: a boundary document must never be public (#929/#952)"
        end
      end

      it "never exposes a write action" do
        # A GET of an authoring screen is a write surface: reaching it means the
        # caller can begin a mutation.
        writes = {
          "new catalog"  => new_control_catalog_path,
          "edit catalog" => edit_control_catalog_path(catalog),
          "new mapping"  => new_control_mapping_path,
          "new converter" => new_converter_path,
          # A converter refresh reaches out to DISA/AWS and writes. It is a
          # write in effect even though the screen looks read-only.
          "converter export" => export_converter_path(converter)
        }

        writes.each do |label, path|
          get path
          expect(response).to redirect_to(login_path), "#{label}: writes are never public"
        end
      end

      it "never exposes the API without a token" do
        %w[
          /api/v1/control_catalogs
          /api/v1/profile_documents
          /api/v1/cdef_documents
          /api/v1/control_mappings
        ].each do |path|
          get path
          expect(response).to have_http_status(:unauthorized),
            "#{path}: the flag governs the web UI only; the API always requires a Bearer token"
        end
      end
    end
  end
end
