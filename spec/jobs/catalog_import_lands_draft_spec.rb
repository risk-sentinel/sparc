# frozen_string_literal: true

require "rails_helper"

# #1235 — an uploaded catalog lands as Draft and is published through
# `publish`; its quality warnings are advisory and carry no priority or
# baseline check (a catalog sets neither: the profile does).
RSpec.describe "Catalog import lands as Draft (#1235)", type: :request do
  let(:admin) { create(:user, :admin) }

  def import(fixture, catalog: create(:control_catalog, name: "Uploaded", status: "pending"))
    source = Rails.root.join("spec/fixtures/files/catalogs", fixture)
    tmp = Rails.root.join("tmp", "catalog_import_spec_#{SecureRandom.hex(4)}_#{fixture}")
    FileUtils.cp(source, tmp)
    CatalogImportJob.perform_now(catalog.id, tmp.to_s, fixture)
    # The service may resolve to another catalog by UUID; the job cleans up.
    ControlCatalog.find_by(id: catalog.id) || ControlCatalog.order(:updated_at).last
  end

  def categories(catalog)
    Array(catalog.reload.metadata_extra["import_warnings"]).map { |w| w["category"] }
  end

  describe "an upload" do
    it "is Draft and editable once imported" do
      catalog = import("basic-catalog.yaml")

      expect(catalog.status).to eq("completed")
      expect(catalog.lifecycle_status).to eq("in_progress")
      expect(catalog).to be_draft
    end

    it "returns a published catalog to Draft when re-imported into it" do
      existing = create(:control_catalog, name: "Uploaded", status: "pending", lifecycle_status: "published")

      catalog = import("basic-catalog.yaml", catalog: existing)

      expect(catalog.reload.lifecycle_status).to eq("in_progress")
    end
  end

  # A data migration re-imports through the service directly (e.g.
  # 20260905090000_backfill_catalog_control_parts). It must not demote a
  # published catalog on upgrade.
  it "leaves an existing catalog's lifecycle alone when the service is called directly" do
    existing = create(:control_catalog, name: "Seeded", lifecycle_status: "published")
    File.open(Rails.root.join("spec/fixtures/files/catalogs/basic-catalog.yaml")) do |io|
      CatalogImportService.call(io, "basic-catalog.yaml", existing_catalog: existing)
    end

    expect(existing.reload.lifecycle_status).to eq("published")
  end

  it "never publishes a catalog itself" do
    draft = create(:control_catalog, name: "Draft", lifecycle_status: "in_progress")
    File.open(Rails.root.join("spec/fixtures/files/catalogs/basic-catalog.yaml")) do |io|
      CatalogImportService.call(io, "basic-catalog.yaml", existing_catalog: draft)
    end

    expect(draft.reload.lifecycle_status).to eq("in_progress")
  end

  it "raises no priority or baseline warning for NIST's Rev 5 catalog" do
    catalog = import("NIST_SP-800-53_rev5_catalog.json")

    expect(catalog.catalog_controls.count).to be > 1000
    expect(categories(catalog)).not_to include("missing_priority", "missing_baseline")
  end

  describe "the publish dialog" do
    before do
      allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
      sign_in_as(admin)
    end

    let(:catalog) do
      create(:control_catalog, lifecycle_status: "in_progress", metadata_extra: {
        "import_warnings" => [
          { "category" => "missing_statement", "severity" => "warning", "message" => "2 controls missing statement text" }
        ]
      })
    end

    it "lists the stored warnings as advisory, without changing readiness" do
      get publish_check_control_catalog_path(catalog), as: :json
      with_warnings = response.parsed_body

      catalog.update_columns(metadata_extra: catalog.metadata_extra.except("import_warnings"))
      get publish_check_control_catalog_path(catalog), as: :json
      without = response.parsed_body

      expect(with_warnings["advisory_warnings"]).to eq(
        [ { "category" => "missing_statement", "message" => "2 controls missing statement text" } ]
      )
      expect(without["advisory_warnings"]).to eq([])
      expect(with_warnings["ready"]).to eq(without["ready"])
    end
  end
end

# #1235 — the processing page polls the URL the upload redirected to, the
# placeholder's random uuid. The import replaces that uuid with the file's own,
# and the next poll used to land on "Catalog not found — it may have been
# merged during re-import", losing the catalog the user had just uploaded.
RSpec.describe "The upload's address keeps working after import (#1235)", type: :request do
  let(:admin) { create(:user, :admin) }

  def upload(fixture, catalog)
    source = Rails.root.join("spec/fixtures/files/catalogs", fixture)
    tmp = Rails.root.join("tmp", "catalog_url_spec_#{SecureRandom.hex(4)}_#{fixture}")
    FileUtils.cp(source, tmp)
    CatalogImportJob.perform_now(catalog.id, tmp.to_s, fixture)
  end

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    sign_in_as(admin)
  end

  it "redirects the placeholder's address to the imported catalog" do
    shell = create(:control_catalog, name: "Uploaded", status: "pending")
    old_uuid = shell.oscal_uuid

    upload("basic-catalog.yaml", shell)
    catalog = ControlCatalog.find(shell.id)
    expect(catalog.oscal_uuid).not_to eq(old_uuid)

    get control_catalog_path(old_uuid)

    expect(response).to redirect_to(control_catalog_path(catalog.oscal_uuid))
    expect(response).to have_http_status(:moved_permanently)
  end

  it "resolves it to the catalog that already owned the file's uuid when the placeholder is merged away" do
    owner = create(:control_catalog, name: "Owner", status: "pending")
    upload("basic-catalog.yaml", owner)
    shell = create(:control_catalog, name: "Second upload", status: "pending")
    old_uuid = shell.oscal_uuid

    upload("basic-catalog.yaml", shell)

    expect(ControlCatalog.find_by(id: shell.id)).to be_nil
    expect(ControlCatalog.find_for_url(old_uuid)).to eq(owner.reload)
  end

  it "still sends an address no catalog ever held to the index" do
    get control_catalog_path(SecureRandom.uuid)

    expect(response).to redirect_to(control_catalogs_path)
  end
end
