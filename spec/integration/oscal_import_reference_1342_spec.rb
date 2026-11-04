# frozen_string_literal: true

require "rails_helper"

# #1342 — an exported SSP leads to its baseline, and an exported baseline to
# its catalog, by OSCAL's own rule: an href of `#<uuid>` resolves to the
# back-matter resource with that uuid. SPARC wrote `uuid:<uuid>`, which the
# schema passed (it is shaped like a URI) and nothing could follow.
RSpec.describe "OSCAL SSP → baseline → catalog links (#1342)" do
  let(:catalog) do
    create(:control_catalog, name: "NIST SP 800-53 Rev 5").tap do |cat|
      family = create(:control_family, control_catalog: cat)
      %w[ac-1 ac-2].each { create(:catalog_control, control_family: family, control_id: _1) }
    end
  end
  let(:profile) do
    create(:profile_document, name: "Rev 5 HIGH Baseline", oscal_version: "1.1.2", profile_version: "1.0.0",
                              control_catalog: catalog).tap do |p|
      %w[ac-1 ac-2].each_with_index { |id, i| create(:profile_control, profile_document: p, control_id: id, row_order: i) }
    end
  end
  let(:ssp) do
    create(:ssp_document, :enriched, name: "Linked SSP", oscal_version: "1.1.2", profile_document: profile).tap do |doc|
      create(:ssp_component, ssp_document: doc, component_type: "software", title: "App", description: "The app")
      create(:ssp_user, ssp_document: doc, title: "System Owner", role_ids_data: [ "system-owner" ])
      create(:ssp_information_type, ssp_document: doc, title: "Info", description: "Information")
      create(:ssp_control, ssp_document: doc, control_id: "ac-1", title: "Policy")
    end
  end

  # OSCAL's rule: `#<uuid>` names the back-matter resource with that uuid.
  def resolve(document, href)
    expect(href).to start_with("#"), "#{href.inspect} is not a #uuid reference"
    resources = document.dig("back-matter", "resources") || []
    matches = resources.select { _1["uuid"] == href.delete_prefix("#") }
    expect(matches.size).to eq(1), "#{href} names #{matches.size} back-matter resources"
    matches.first
  end

  def app_url = SparcConfig.app_url.to_s.chomp("/")

  describe "the SSP export" do
    let(:exported) { JSON.parse(OscalSspExportService.new(ssp).export)["system-security-plan"] }

    it "links import-profile to a back-matter resource naming the baseline and where its OSCAL is" do
      resource = resolve(exported, exported.dig("import-profile", "href"))

      expect(resource).to include("uuid" => profile.uuid, "title" => "Rev 5 HIGH Baseline")
      expect(resource["rlinks"].map { _1["href"] })
        .to eq([ "#{app_url}#{Rails.application.routes.url_helpers.download_oscal_profile_document_path(profile)}" ])
    end

    it "is schema-valid and names each back-matter uuid once, even when the SSP already holds the resource" do
      create(:back_matter_resource, resourceable: ssp, uuid: profile.uuid, title: "Brought in by an import")

      expect { OscalSspExportService.new(ssp).export }.not_to raise_error
      uuids = exported.dig("back-matter", "resources").map { _1["uuid"] }
      expect(uuids).to eq(uuids.uniq)
    end

    it "resolves back to the same baseline the way SSP import does" do
      href = exported.dig("import-profile", "href")

      expect(OscalMetadata.resolve_import_href(href, ProfileDocument)).to eq(profile)
    end

    it "keeps the imported file's href when the SSP has no baseline" do
      ssp.update_columns(profile_document_id: nil, import_profile_href: "baseline-profile.json")

      expect(exported.dig("import-profile", "href")).to eq("baseline-profile.json")
    end
  end

  describe "the baseline (profile) export" do
    let(:exported) { JSON.parse(OscalProfileExportService.new(profile).export)["profile"] }

    it "links each import to a back-matter resource naming its catalog and where its OSCAL is" do
      exported["imports"].each do |import|
        resource = resolve(exported, import["href"])

        expect(resource).to include("uuid" => catalog.oscal_uuid, "title" => "NIST SP 800-53 Rev 5")
        expect(resource["rlinks"].map { _1["href"] })
          .to eq([ "#{app_url}#{Rails.application.routes.url_helpers.download_oscal_control_catalog_path(catalog)}" ])
      end
    end

    it "resolves back to the same catalog the way profile import does" do
      resolutions = ProfileImportCatalogResolver.new(exported.dig("back-matter", "resources")).resolve(exported["imports"])

      expect(resolutions.map(&:catalog)).to all(eq(catalog))
      expect(resolutions.map(&:matched_by)).to all(eq("uuid"))
    end
  end

  it "still resolves the uuid: form older exports carry" do
    expect(OscalMetadata.resolve_import_href("uuid:#{profile.uuid}", ProfileDocument)).to eq(profile)
  end
end
