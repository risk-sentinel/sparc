# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260918120000_repair_columns_archived_by_the_squash.rb")

# #1147 — the repair has to work against a database that is BEHIND, which is
# exactly the case the squash was never tested against.
#
# The test database is built by `schema:load`, so it already has every column.
# These examples DROP them first, inside the per-example transaction, to
# reproduce what a v1.16.0 deployment actually had after upgrading. Postgres
# DDL is transactional, so the drops roll back with everything else.
RSpec.describe RepairColumnsArchivedByTheSquash do
  subject(:migration) { described_class.new }

  before { allow(migration).to receive(:say) }

  def connection = ActiveRecord::Base.connection

  def strip_the_archived_columns!
    connection.remove_column(:ssp_information_types, :authorization_boundary_id)
    %i[security_objective_confidentiality
       security_objective_integrity
       security_objective_availability].each do |c|
      connection.remove_column(:authorization_boundaries, c)
    end
    %i[component_uuid implementation_source implementation_description].each do |c|
      connection.remove_column(:cdef_controls, c)
    end
    [ AuthorizationBoundary, SspInformationType, CdefControl ].each(&:reset_column_information)
  end

  after { [ AuthorizationBoundary, SspInformationType, CdefControl ].each(&:reset_column_information) }

  describe "against a database upgraded from v1.16.0" do
    it "restores all seven columns" do
      strip_the_archived_columns!
      expect(connection.column_exists?(:ssp_information_types, :authorization_boundary_id)).to be(false)

      migration.up

      expect(connection.column_exists?(:authorization_boundaries, :security_objective_confidentiality)).to be(true)
      expect(connection.column_exists?(:authorization_boundaries, :security_objective_integrity)).to be(true)
      expect(connection.column_exists?(:authorization_boundaries, :security_objective_availability)).to be(true)
      expect(connection.column_exists?(:ssp_information_types, :authorization_boundary_id)).to be(true)
      expect(connection.column_exists?(:cdef_controls, :component_uuid)).to be(true)
      expect(connection.column_exists?(:cdef_controls, :implementation_source)).to be(true)
      expect(connection.column_exists?(:cdef_controls, :implementation_description)).to be(true)
    end

    it "restores the indexes the CDEF pages read through" do
      strip_the_archived_columns!

      migration.up

      names = connection.indexes(:cdef_controls).map(&:name)
      expect(names).to include("index_cdef_controls_on_document_and_component",
                               "index_cdef_controls_on_document_and_source")
    end

    # The defect that actually took production down: the boundary show page.
    it "makes the failing query answerable again" do
      boundary = create(:authorization_boundary)
      strip_the_archived_columns!
      # A savepoint, because the failing query ABORTS the transaction and every
      # statement after it — including this migration's DDL — would then fail
      # with PG::InFailedSqlTransaction. Same distinction #968 turned on.
      expect {
        ActiveRecord::Base.transaction(requires_new: true) { boundary.reload.security_objective(:confidentiality) }
      }.to raise_error(ActiveRecord::StatementInvalid)

      migration.up
      [ AuthorizationBoundary, SspInformationType, CdefControl ].each(&:reset_column_information)

      expect { boundary.reload.security_objective(:confidentiality) }.not_to raise_error
    end
  end

  describe "the data lift #940 S3 carried" do
    it "lifts a boundary's categorization from its newest SSP" do
      boundary = create(:authorization_boundary)
      create(:ssp_document, authorization_boundary: boundary,
                            security_objective_confidentiality: "fips-199-moderate",
                            security_objective_integrity: "fips-199-low",
                            security_objective_availability: "fips-199-low")
      strip_the_archived_columns!

      migration.up
      AuthorizationBoundary.reset_column_information

      expect(boundary.reload.security_objective_confidentiality).to eq("fips-199-moderate")
      expect(boundary.security_objective_integrity).to eq("fips-199-low")
    end

    it "points information types at the boundary their SSP belongs to" do
      boundary = create(:authorization_boundary)
      ssp = create(:ssp_document, authorization_boundary: boundary)
      it_row = create(:ssp_information_type, ssp_document: ssp)
      strip_the_archived_columns!

      migration.up
      SspInformationType.reset_column_information

      expect(it_row.reload.authorization_boundary_id).to eq(boundary.id)
    end

    # Only NULLs are written, so a value already set is never overwritten.
    it "does not overwrite a categorization the boundary already carries" do
      boundary = create(:authorization_boundary, security_objective_confidentiality: "fips-199-high",
                                                 security_objective_integrity: "fips-199-high",
                                                 security_objective_availability: "fips-199-high")
      create(:ssp_document, authorization_boundary: boundary,
                            security_objective_confidentiality: "fips-199-low",
                            security_objective_integrity: "fips-199-low",
                            security_objective_availability: "fips-199-low")

      migration.up

      expect(boundary.reload.security_objective_confidentiality).to eq("fips-199-high")
    end
  end

  describe "against a fresh database, where schema:load already did the work" do
    it "is a no-op and does not raise" do
      before_columns = connection.columns(:authorization_boundaries).map(&:name).sort

      expect { migration.up }.not_to raise_error

      expect(connection.columns(:authorization_boundaries).map(&:name).sort).to eq(before_columns)
    end

    it "is safe to run twice" do
      strip_the_archived_columns!

      migration.up
      migration.up

      expect(connection.column_exists?(:ssp_information_types, :authorization_boundary_id)).to be(true)
      expect(connection.indexes(:cdef_controls).map(&:name).tally.values).to all(eq(1))
    end
  end
end
