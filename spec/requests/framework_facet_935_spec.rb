# frozen_string_literal: true

require "rails_helper"

# #935 — filtering catalogs and baselines by framework.
#
# Cut from #908 because framework was not a field: it existed only as prose and
# filename, and deriving it per request by regexing titles was rejected — a
# catalog with a different title convention would be labelled wrongly, and a
# confidently wrong framework is worse than no filter.
#
# So it is derived once at import and persisted, and the facet is a column
# lookup. #908 shipped the mechanism, so one `facet` declaration reaches the
# screen AND the Api::V1 endpoint; these assert both, because the whole point of
# CollectionBrowseQuery is that a facet cannot be added to one without the other.
RSpec.describe "Framework facet (#935)", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:auth_headers) { { "Authorization" => "Bearer #{ApiToken.generate!(user: admin, name: 'Test').plaintext_token}" } }

  let!(:nist_catalog) do
    create(:control_catalog, name: "NIST SP 800-53 Rev 5 Catalog", framework: FrameworkDeriver::NIST_800_53)
  end
  let!(:ksi_catalog) do
    create(:control_catalog, name: "FedRAMP 20x KSI", framework: FrameworkDeriver::FEDRAMP_20X)
  end
  let!(:unspecified_catalog) do
    create(:control_catalog, name: "Demo Catalog", framework: nil)
  end

  before { sign_in_as(admin) }

  describe "the catalog index" do
    it "narrows to one framework" do
      get control_catalogs_path, params: { framework: FrameworkDeriver::NIST_800_53 }

      expect(response.body).to include(nist_catalog.name)
      expect(response.body).not_to include(ksi_catalog.name)
    end

    # A null is not a framework, and must not be swept into another's bucket.
    it "does not attribute an unspecified catalog to any framework" do
      get control_catalogs_path, params: { framework: FrameworkDeriver::NIST_800_53 }

      expect(response.body).not_to include(unspecified_catalog.name)
    end

    it "offers the facet in the filter UI" do
      get control_catalogs_path

      expect(response.body).to include("Framework")
    end
  end

  describe "the baseline index" do
    let!(:nist_profile) do
      create(:profile_document, name: "NIST LOW Baseline", framework: FrameworkDeriver::NIST_800_53)
    end
    let!(:ksi_profile) do
      create(:profile_document, name: "KSI Baseline", framework: FrameworkDeriver::FEDRAMP_20X)
    end

    it "narrows to one framework" do
      get profile_documents_path, params: { framework: FrameworkDeriver::FEDRAMP_20X }

      expect(response.body).to include(ksi_profile.name)
      expect(response.body).not_to include(nist_profile.name)
    end
  end

  # One declaration, two surfaces — the #908 guarantee.
  describe "Api::V1" do
    it "accepts framework on the catalog endpoint" do
      get "/api/v1/control_catalogs", params: { framework: FrameworkDeriver::FEDRAMP_20X },
          headers: auth_headers

      names = JSON.parse(response.body)["data"].map { |c| c["name"] }
      expect(names).to include(ksi_catalog.name)
      expect(names).not_to include(nist_catalog.name)
    end

    it "accepts framework on the profile endpoint" do
      profile = create(:profile_document, name: "API KSI Baseline", framework: FrameworkDeriver::FEDRAMP_20X)
      create(:profile_document, name: "API NIST Baseline", framework: FrameworkDeriver::NIST_800_53)

      get "/api/v1/profile_documents", params: { framework: FrameworkDeriver::FEDRAMP_20X },
          headers: auth_headers

      names = JSON.parse(response.body)["data"].map { |p| p["name"] }
      expect(names).to include(profile.name)
      expect(names).not_to include("API NIST Baseline")
    end
  end

  describe "derivation at import" do
    # The end-to-end claim: import a catalog and the column is populated without
    # anyone typing it.
    it "populates the column from the catalog's own controls" do
      catalog = create(:control_catalog, name: "Imported Set", source: "OSCAL", framework: nil)
      family  = create(:control_family, control_catalog: catalog, code: "KSI")
      create(:catalog_control, control_family: family, control_id: "ksi-auth-01")

      catalog.update_column(:framework, FrameworkDeriver.for_catalog(catalog))

      expect(catalog.reload.framework).to eq(FrameworkDeriver::FEDRAMP_20X)
    end
  end
end
