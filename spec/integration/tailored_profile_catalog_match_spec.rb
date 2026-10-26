# frozen_string_literal: true

require "rails_helper"

# NIST's Rev 5 catalog and the tailored MODERATE profile, on an instance that
# also holds an agency overlay whose name says "SP 800-53 Rev 5".
#
# The profile's import names its catalog through a back-matter resource whose
# links are NIST file paths (`.../rev5/json/NIST_SP-800-53_rev5_catalog.json`),
# not a catalog uuid, so upload can only match it by name: "800-53" and the
# same revision. Both catalogs fit. The lowest id won, the import linked to the
# overlay, and the page warned that the baseline "names controls its catalog
# does not have", listing every control. Changing the catalog to NIST's then
# set the profile's catalog and nothing else, so the warning stayed.
#
# Now a match is a suggestion the owner CONFIRMS; with none, they SELECT one;
# either way the imports are re-checked against the catalog chosen, and a
# baseline whose catalog is unconfirmed cannot be published.
RSpec.describe "Tailored Rev 5 profile and its catalog", type: :request do
  let(:fixtures) { Rails.root.join("spec/fixtures/files") }
  let(:profile_path) { fixtures.join("profiles/NIST_SP-800-53_rev5_MODERATE-tailored_profile.json") }
  let(:overlay) { create(:control_catalog, name: "Agency overlay for NIST SP 800-53 Rev 5") }
  let(:nist) do
    CatalogImportService.call(File.open(fixtures.join("catalogs/NIST_SP-800-53_rev5_catalog.json")),
                              "NIST_SP-800-53_rev5_catalog.json")[:catalog].tap do |catalog|
      catalog.update_columns(lifecycle_status: "published")
    end
  end

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    sign_in_as(create(:user, :admin))
  end

  def upload
    create(:profile_document, status: "processing", file_type: "json",
           original_filename: File.basename(profile_path)).tap do |doc|
      ProfileJsonParserService.new(doc, profile_path.to_s).parse
      doc.reload.update_columns(status: "completed")
    end
  end

  def import_of(profile) = profile.reload.import_metadata["imports"].first

  def set_value(param_id)
    JSON.parse(File.read(profile_path)).dig("profile", "modify", "set-parameters")
        .find { |p| p["param-id"] == param_id }.fetch("values").first
  end

  def page_for(profile)
    get profile_document_path(profile)
    expect(response).to have_http_status(:ok)
    Nokogiri::HTML(response.body)
  end

  def choose(profile, catalog)
    patch set_baseline_profile_document_path(profile), params: { profile_document: { control_catalog_id: catalog.id } }
    profile.reload
  end

  def stored_values(profile)
    ProfileControlField.joins(:profile_control).where(profile_controls: { profile_document_id: profile.id })
                       .order(:id).pluck(:field_name, :field_value)
  end

  # The state upload produced in production: the import linked to the overlay.
  def linked_to_overlay(profile)
    metadata = profile.import_metadata.deep_dup
    metadata["imports"].first.merge!("catalog_id" => overlay.id, "unknown_ids" => metadata["imports"].first["control_ids"])
    profile.update_columns(control_catalog_id: overlay.id, import_metadata: metadata)
    profile.profile_controls.update_all(source_catalog_id: overlay.id)
    profile
  end

  context "when a loaded catalog matches" do
    before { overlay && nist }

    it "fits both catalogs by name, so the match has to choose between them" do
      expect(overlay.id).to be < nist.id
      expect([ overlay, nist ].map { |c| c.name.include?("800-53") && c.name.match?(/rev\.?\s*5/i) }).to all(be(true))
    end

    it "suggests the catalog holding the profile's controls, and asks for it to be confirmed" do
      profile = upload

      expect(profile.control_catalog).to eq(nist)
      expect(import_of(profile)).to include("catalog_id" => nist.id, "matched_by" => "nist_pattern")
      expect(profile).to be_catalog_confirmation_pending
      page = page_for(profile)
      expect(page.at_css("[data-catalog-state='pending']").text.squish).to include("matched to #{nist.name} by name")
      expect(page.at_css("[data-testid='confirm-catalog']")).to be_present
    end

    it "will not publish until the catalog is confirmed, and will once it is" do
      profile = upload
      expect(profile.content_completeness_gaps).to include("A confirmed control catalog")

      choose(profile, nist)

      expect(profile).not_to be_catalog_confirmation_pending
      expect(profile.content_completeness_gaps).not_to include("A confirmed control catalog")
      page = page_for(profile)
      expect(page.at_css("[data-testid='catalog-link']")).to be_nil
      expect(page.at_css("[data-testid='change-catalog-link']")).to be_present
    end

    it "re-checks the import when the catalog is changed, clearing the warning and leaving every value as it was" do
      profile = linked_to_overlay(upload)
      expect(page_for(profile).at_css("[data-testid='unknown-control-ids']")).to be_present
      values = stored_values(profile)

      choose(profile, nist)

      expect(import_of(profile)).to include("catalog_id" => nist.id, "matched_by" => "selected")
      expect(import_of(profile)).not_to have_key("unknown_ids")
      expect(profile.profile_controls.distinct.pluck(:source_catalog_id)).to eq([ nist.id ])
      expect(stored_values(profile)).to eq(values)
      expect(page_for(profile).at_css("[data-testid='unknown-control-ids']")).to be_nil
    end

    it "lets an API client confirm the same way" do
      profile = upload
      token = ApiToken.generate!(user: create(:user, :admin), name: "confirm")

      patch api_v1_profile_document_path(profile), params: { profile_document: { control_catalog_id: nist.id } }.to_json,
            headers: { "Authorization" => "Bearer #{token.plaintext_token}", "Content-Type" => "application/json" }

      expect(response).to have_http_status(:ok)
      expect(profile.reload).not_to be_catalog_confirmation_pending
    end

    it "shows AC-1's aggregate with the values the profile sets, and no field for it" do
      profile = upload
      page = page_for(profile)

      expect(page.css("[name^='param_values[ac-1_prm_1]']")).to be_empty
      expect(page.at_css("[data-aggregate-param='ac-1_prm_1']").text.squish)
        .to include("#{set_value("ac-01_odp.01")}, #{set_value("ac-01_odp.02")}")
      expect(page.at_css("[name='param_values[ac-01_odp.05]']")["value"]).to eq("365")
    end
  end

  context "when no loaded catalog matches" do
    it "links nothing, asks for a catalog to be selected, and says how to load one" do
      profile = upload

      expect(profile.control_catalog).to be_nil
      expect(profile).not_to be_catalog_confirmation_pending
      state = page_for(profile).at_css("[data-catalog-state='absent']")
      expect(state.text.squish).to include("Select the catalog")
      expect(state.at_css("a[href='#{import_control_catalogs_path}']")).to be_present
    end

    it "links and titles the controls once the catalog is loaded and selected" do
      profile = upload
      expect(profile.profile_controls.where(title: nil).count).to eq(profile.profile_controls.count)

      choose(profile, nist)

      expect(import_of(profile)).to include("catalog_id" => nist.id, "matched_by" => "selected")
      expect(profile.profile_controls.where(title: nil)).to be_empty
      expect(profile.profile_controls.distinct.pluck(:source_catalog_id)).to eq([ nist.id ])
    end
  end

  it "keeps an import the profile names by catalog uuid on that catalog when another is chosen" do
    nist
    profile = upload
    metadata = profile.import_metadata.deep_dup
    metadata["imports"].first["matched_by"] = "uuid"
    metadata["imports"] << { "href" => "#org", "title" => "Org Controls", "control_ids" => [], "matched_by" => "title" }
    profile.update_columns(import_metadata: metadata)

    choose(profile, overlay)

    expect(import_of(profile)).to include("catalog_id" => nist.id, "matched_by" => "uuid")
  end

  it "does not ask a baseline uploaded before the confirmation step to confirm" do
    profile = create(:profile_document, import_metadata: { "imports" => [ { "href" => "#x", "catalog_id" => 1 } ] })

    expect(profile).not_to be_catalog_confirmation_pending
  end
end
