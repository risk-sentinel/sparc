# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261122140000_add_fedramp_profile_and_statements.rb")

# #1390 — the upgrade path: a boundary already using FedRAMP keeps its
# FedRAMP features once they show only for boundaries that turn FedRAMP on.
RSpec.describe AddFedrampProfileAndStatements do
  subject(:migration) { described_class.new }

  before { allow(migration).to receive(:say) }

  it "turns FedRAMP on for boundaries that already use it, and leaves the rest off" do
    with_address = create(:authorization_boundary, fedramp_package_overview_uri: "https://provider.example/cpo.json")
    with_fields = create(:authorization_boundary, fedramp_package: { "service_name" => "Example Cloud" })
    with_evaluation = create(:authorization_boundary)
    create(:scanner_finding, authorization_boundary: with_evaluation, control_id: "CVE-1", status: "failed",
                             scan_run: create(:scan_run, authorization_boundary: with_evaluation))
    FedrampVulnerabilityEvaluation.create!(authorization_boundary: with_evaluation, control_id: "CVE-1", pain_rating: 2)
    plain = create(:authorization_boundary)
    AuthorizationBoundary.update_all(fedramp_enabled: false)

    migration.up
    migration.up # idempotent

    expect([ with_address, with_fields, with_evaluation ].map { |b| b.reload.fedramp_enabled }).to all(be(true))
    expect(plain.reload.fedramp_enabled).to be(false)
  end
end
