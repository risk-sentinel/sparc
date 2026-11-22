# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261122160000_create_fedramp_ongoing_reports.rb")

# #1390 — the Ongoing Certification Report table and the boundary's active
# agencies, created idempotently.
RSpec.describe CreateFedrampOngoingReports do
  subject(:migration) { described_class.new }

  before { allow(migration).to receive(:say) }

  after do
    migration.up
    [ FedrampOngoingReport, AuthorizationBoundary ].each(&:reset_column_information)
  end

  it "creates the table and the column, and runs again without harm" do
    migration.down
    expect(ActiveRecord::Base.connection.column_exists?(:authorization_boundaries, :fedramp_active_agencies)).to be(false)

    migration.up
    migration.up
    connection = ActiveRecord::Base.connection
    expect(connection.table_exists?(:fedramp_ongoing_reports)).to be(true)
    expect(connection.column_exists?(:authorization_boundaries, :fedramp_active_agencies, :jsonb)).to be(true)
  end
end
