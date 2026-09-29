# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260928130000_import_fedramp_ksi_catalog_from_rules.rb")

# #1115 — the upgrade path: an existing deployment's catalog, seeded the old way
# with validations on it, is re-keyed without losing an assessment.
RSpec.describe ImportFedrampKsiCatalogFromRules do
  subject(:migration) { described_class.new }

  before { allow(migration).to receive(:say) }

  around do |example|
    DeferredDataMigration.executing!
    example.run
  ensure
    DeferredDataMigration.idle!
  end

  let(:boundary) { create(:authorization_boundary) }
  let(:catalog) { ControlCatalog.create!(name: "FedRAMP 20x Key Security Indicators", source: "FedRAMP 20x", version: "1.0.0") }

  def old_indicator(code, id) = catalog.control_families.find_or_create_by!(code: code) { |f| f.name = code }
                                       .catalog_controls.create!(control_id: id, label: id.upcase, sort_id: id, title: id)

  it "re-keys the old catalog and keeps every validation, on renamed and retired indicators alike" do
    renamed = KsiValidation.create!(authorization_boundary: boundary, catalog_control: old_indicator("IAM", "ksi-iam-02"), status: "passed")
    retired = KsiValidation.create!(authorization_boundary: boundary, catalog_control: old_indicator("AUTH", "ksi-auth-01"), status: "partial")

    migration.up

    expect(catalog.reload.version).to eq("2026.09.13.02")
    expect(renamed.reload.catalog_control.control_id).to eq("ksi-iam-elp")
    expect(retired.reload.catalog_control).to be_retired
    expect([ renamed.status, retired.status ]).to eq(%w[passed partial])
  end

  it "is a no-op on a second run" do
    migration.up

    expect(FedrampKsiImportService.new.call).to be_unchanged
  end

  it "fails the run when the import is refused, so the runner retries it instead of reporting success" do
    refused = FedrampKsiImportService::Result.new(status: :refused, version: "x", changes: {}, errors: [ "/: bad" ])
    allow(FedrampKsiImportService).to receive(:new).and_return(instance_double(FedrampKsiImportService, call: refused))

    expect { migration.up }.to raise_error(FedrampKsiImportService::Refused, /FedRAMP KSI import refused: \/: bad/)
  end
end
