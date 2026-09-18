# frozen_string_literal: true

require "rails_helper"

# #1147 — the check that would have caught the squash gap before a deploy.
RSpec.describe SchemaDriftService do
  def connection = ActiveRecord::Base.connection

  after { [ AuthorizationBoundary, SspInformationType, CdefControl ].each(&:reset_column_information) }

  describe "a database that matches schema.rb" do
    # The test database is built by schema:load, so it is the matching case by
    # construction — which is exactly why it must be asserted: if this reported
    # drift on a clean database, every later example would be meaningless.
    it "reports none" do
      expect(described_class.new.drift).to be_empty
      expect(described_class.new).to be_clean
    end

    it "says how many tables it checked, rather than a bare 'ok'" do
      expect(described_class.new.report).to match(/schema matches db\/schema\.rb — \d+ table\(s\) checked/)
    end

    it "checks a real number of tables — a parser that found nothing would also report clean" do
      expected = described_class.new.send(:expected)
      expect(expected.size).to be > 40
      expect(expected["authorization_boundaries"][:columns]).to include("security_objective_confidentiality")
    end
  end

  describe "a database behind schema.rb — the production case" do
    it "names each missing column" do
      connection.remove_column(:ssp_information_types, :authorization_boundary_id)
      SspInformationType.reset_column_information

      found = described_class.new.drift

      expect(found.map(&:to_s)).to include("missing column ssp_information_types.authorization_boundary_id")
      expect(described_class.new).not_to be_clean
    end

    it "finds drift on EVERY affected table, not just the first" do
      connection.remove_column(:ssp_information_types, :authorization_boundary_id)
      connection.remove_column(:authorization_boundaries, :security_objective_integrity)
      connection.remove_column(:cdef_controls, :component_uuid)

      tables = described_class.new.drift.map(&:table).uniq

      expect(tables).to include("ssp_information_types", "authorization_boundaries", "cdef_controls")
    end

    it "names a missing index" do
      connection.remove_index(:cdef_controls, name: "index_cdef_controls_on_document_and_source")

      expect(described_class.new.drift.map(&:to_s))
        .to include("missing index index_cdef_controls_on_document_and_source on cdef_controls")
    end

    it "names a missing table" do
      connection.drop_table(:ssp_information_types, force: :cascade)

      expect(described_class.new.drift.map(&:to_s)).to include("missing table ssp_information_types")
    end

    it "reports the upgrade explanation, not just a list" do
      connection.remove_column(:cdef_controls, :implementation_source)

      report = described_class.new.report

      expect(report).to include("SCHEMA DRIFT")
      expect(report).to include("cdef_controls:")
      expect(report).to match(/db:migrate. reports|archived/)
    end
  end

  describe "read-only by construction" do
    it "changes nothing about the database" do
      before_columns = connection.columns(:authorization_boundaries).map(&:name).sort

      described_class.new.report

      expect(connection.columns(:authorization_boundaries).map(&:name).sort).to eq(before_columns)
    end
  end
end
