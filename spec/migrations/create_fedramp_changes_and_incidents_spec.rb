# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261122150000_create_fedramp_changes_and_incidents.rb")

# #1390 — the significant change and incident tables, created idempotently.
RSpec.describe CreateFedrampChangesAndIncidents do
  subject(:migration) { described_class.new }

  before { allow(migration).to receive(:say) }

  after do
    migration.up
    [ FedrampSignificantChange, FedrampIncident ].each(&:reset_column_information)
  end

  it "creates both tables, and runs again without harm" do
    migration.down
    expect(ActiveRecord::Base.connection.table_exists?(:fedramp_incidents)).to be(false)

    migration.up
    migration.up
    connection = ActiveRecord::Base.connection
    expect(connection.table_exists?(:fedramp_significant_changes)).to be(true)
    expect(connection.index_exists?(:fedramp_incidents, %i[authorization_boundary_id tracking_id], unique: true)).to be(true)
  end
end
