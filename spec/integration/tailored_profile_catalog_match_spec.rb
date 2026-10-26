# frozen_string_literal: true

require "rails_helper"

# NIST's Rev 5 catalog and the tailored MODERATE profile, uploaded on an
# instance that also holds an agency overlay whose name says "SP 800-53 Rev 5".
#
# The profile's import names its catalog through a back-matter resource whose
# links are NIST file paths (`.../rev5/json/NIST_SP-800-53_rev5_catalog.json`),
# not a catalog uuid, so it is matched by the NIST pattern: "800-53" and the
# same revision. Both catalogs fit, and the lowest id won. The import linked to
# the overlay, which holds none of the profile's controls, and the baseline
# page reported every control as missing from its catalog, although the
# profile was uploaded against NIST's catalog and every control was there.
RSpec.describe "Tailored Rev 5 profile matched to its catalog", type: :request do
  let(:fixtures) { Rails.root.join("spec/fixtures/files") }
  let(:profile_path) { fixtures.join("profiles/NIST_SP-800-53_rev5_MODERATE-tailored_profile.json") }

  let!(:overlay) { create(:control_catalog, name: "Agency overlay for NIST SP 800-53 Rev 5") }
  let!(:nist) do
    CatalogImportService.call(File.open(fixtures.join("catalogs/NIST_SP-800-53_rev5_catalog.json")),
                              "NIST_SP-800-53_rev5_catalog.json")[:catalog].tap do |catalog|
      catalog.update_columns(lifecycle_status: "published")
    end
  end

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    sign_in_as(create(:user, :admin))
  end

  def upload(catalog)
    create(:profile_document, status: "processing", file_type: "json",
           original_filename: File.basename(profile_path), control_catalog: catalog).tap do |doc|
      ProfileJsonParserService.new(doc, profile_path.to_s).parse
      doc.reload.update_columns(status: "completed")
    end
  end

  def import_of(profile) = profile.import_metadata["imports"].first

  def set_value(param_id)
    JSON.parse(File.read(profile_path)).dig("profile", "modify", "set-parameters")
        .find { |p| p["param-id"] == param_id }.fetch("values").first
  end

  it "fits both catalogs by name, so the test is about choosing between them" do
    expect(overlay.id).to be < nist.id
    expect([ overlay, nist ].map { |c| c.name.include?("800-53") && c.name.match?(/rev\.?\s*5/i) }).to all(be(true))
  end

  it "links the import to the catalog the profile was uploaded against" do
    import = import_of(upload(nist))

    expect(import["catalog_id"]).to eq(nist.id)
    expect(import["unknown_ids"]).to be_nil
  end

  it "links to the fitting catalog that holds the profile's controls when none was chosen" do
    expect(import_of(upload(nil))["catalog_id"]).to eq(nist.id)
  end

  it "shows no missing-controls warning, and AC-1's aggregate reads from the values the profile sets" do
    profile = upload(nist)
    get profile_document_path(profile)
    page = Nokogiri::HTML(response.body)

    expect(response).to have_http_status(:ok)
    expect(page.at_css("[data-testid='unknown-control-ids']")).to be_nil
    expect(page.css("[name^='param_values[ac-1_prm_1]']")).to be_empty
    expect(page.at_css("[data-aggregate-param='ac-1_prm_1']").text.squish)
      .to include("#{set_value("ac-01_odp.01")}, #{set_value("ac-01_odp.02")}")
    expect(page.at_css("[name='param_values[ac-01_odp.05]']")["value"]).to eq("365")
  end
end
