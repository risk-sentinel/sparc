# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261021130000_revalidate_catalog_import_warnings.rb")

# #1235 — stored priority/baseline warnings are revalidated away; nothing else
# about the catalog changes.
RSpec.describe RevalidateCatalogImportWarnings do
  include ActiveSupport::Testing::TimeHelpers

  subject(:migration) { described_class.new }

  before { allow(migration).to receive(:say) }

  around do |example|
    DeferredDataMigration.executing!
    example.run
  ensure
    DeferredDataMigration.idle!
  end

  def warning(category, ids = [ "ac-1" ])
    { "category" => category, "severity" => "warning", "message" => category,
      "count" => ids.size, "control_ids" => ids }
  end

  # A published, acknowledged catalog with the two retired warnings and one
  # that still applies: ac-1 has no statement.
  def stale_catalog(name: "Stale")
    catalog = create(:control_catalog, name: name, lifecycle_status: "published")
    family = create(:control_family, control_catalog: catalog, code: "AC", name: "Access Control")
    create(:catalog_control, control_family: family, control_id: "ac-1", priority: nil,
      baseline_impact: nil, guidance_data: { "assessment_objective" => "obj" })
    catalog.update_columns(metadata_extra: {
      "import_warnings" => [ warning("missing_priority"), warning("missing_baseline"), warning("missing_statement") ],
      "import_warnings_summary" => { "total_warnings" => 3 },
      "import_warnings_acknowledged" => true
    })
    catalog
  end

  def categories(catalog)
    catalog.reload.metadata_extra["import_warnings"].map { |w| w["category"] }
  end

  it "drops the retired warnings and keeps the ones the content still raises" do
    catalog = stale_catalog

    migration.revalidate_catalog_import_warnings

    expect(categories(catalog)).to eq([ "missing_statement" ])
    expect(catalog.metadata_extra["import_warnings_summary"]["total_warnings"]).to eq(1)
  end

  it "keeps the lifecycle status and the acknowledgement" do
    catalog = stale_catalog

    migration.revalidate_catalog_import_warnings

    expect(catalog.reload.lifecycle_status).to eq("published")
    expect(catalog.metadata_extra["import_warnings_acknowledged"]).to be(true)
  end

  it "leaves a catalog without retired warnings untouched" do
    clean = create(:control_catalog, name: "Clean")
    clean.update_columns(metadata_extra: { "import_warnings" => [ warning("empty_family") ] })

    migration.revalidate_catalog_import_warnings

    expect(clean.reload.metadata_extra).to eq("import_warnings" => [ warning("empty_family") ])
  end

  it "resumes after a partial run, revalidating only the catalogs it had not reached" do
    done = stale_catalog(name: "Done")
    migration.revalidate_catalog_import_warnings
    stamped = done.reload.metadata_extra["last_validated_at"]
    pending = stale_catalog(name: "Pending")

    travel 1.minute do
      migration.revalidate_catalog_import_warnings
    end

    expect(done.reload.metadata_extra["last_validated_at"]).to eq(stamped)
    expect(categories(pending)).to eq([ "missing_statement" ])
  end

  it "is a no-op on a second run" do
    catalog = stale_catalog
    migration.revalidate_catalog_import_warnings
    before = catalog.reload.metadata_extra

    travel 1.minute do
      migration.revalidate_catalog_import_warnings
    end

    expect(catalog.reload.metadata_extra).to eq(before)
  end
end
