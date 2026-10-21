# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20261019120000_scope_email_uniqueness_to_human_accounts.rb")

# #1176 — the email index covers people only. DDL is transactional, so each
# example's index changes roll back with it.
RSpec.describe ScopeEmailUniquenessToHumanAccounts do
  subject(:migration) { described_class.new }

  before { allow(migration).to receive(:say) }

  def connection = ActiveRecord::Base.connection

  def index_named(name)
    connection.indexes(:users).find { |i| i.name == name }
  end

  # Put the database back the way a release before this one left it.
  def restore_old_index
    connection.remove_index(:users, name: described_class::HUMAN_INDEX, if_exists: true)
    unless connection.index_name_exists?(:users, described_class::OLD_INDEX)
      connection.add_index(:users, "lower((email)::text)", unique: true, name: described_class::OLD_INDEX)
    end
  end

  it "replaces the all-accounts index with one over people, and is a no-op the second time" do
    restore_old_index

    migration.up
    migration.up

    human = index_named(described_class::HUMAN_INDEX)
    expect(human).to be_present
    expect(human.unique).to be true
    expect(human.where).to include("service_account = false")
    expect(index_named(described_class::OLD_INDEX)).to be_nil
  end

  it "rolls back to the all-accounts index" do
    migration.down

    expect(index_named(described_class::OLD_INDEX)&.unique).to be true
    expect(index_named(described_class::HUMAN_INDEX)).to be_nil
  end
end
