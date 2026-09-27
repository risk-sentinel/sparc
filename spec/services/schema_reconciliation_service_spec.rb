# frozen_string_literal: true

require "rails_helper"

# #1151 — the generated, additive repair for a database behind schema.rb.
#
# Every repair here is followed by a STRICT drift check, not a presence check:
# the claim is that reconciliation builds exactly what `db:schema:load` would —
# type, default, nullability, index shape — and a column that merely exists
# with the right name would pass a presence check while being wrong.
#
# All DDL runs inside the example's transaction and is rolled back with it.
RSpec.describe SchemaReconciliationService do
  def connection = ActiveRecord::Base.connection

  def boundary_row(name = "b-#{SecureRandom.hex(3)}")
    connection.execute(<<~SQL)
      INSERT INTO authorization_boundaries (name, created_at, updated_at)
      VALUES (#{connection.quote(name)}, now(), now())
    SQL
  end

  def reconcile(**opts) = described_class.new(**opts).call

  def strict_drift = SchemaDriftService.new.drift(strict: true)

  after { [ AuthorizationBoundary, SspInformationType, CdefControl, ApiToken ].each(&:reset_column_information) }

  describe "a database that matches" do
    it "does nothing and records nothing" do
      expect { expect(reconcile).to be_clean }.not_to change(AuditEvent, :count)
    end
  end

  describe "additive repair" do
    it "adds a missing nullable column" do
      connection.remove_column(:authorization_boundaries, :description)

      result = reconcile

      expect(result).to be_reconciled
      expect(result.statements.join("\n")).to match(/ALTER TABLE "authorization_boundaries" ADD "description" text/)
      expect(strict_drift).to eq([])
    end

    it "adds a NOT NULL column that has a default to a POPULATED table, filling existing rows" do
      boundary_row("existing")
      connection.remove_column(:authorization_boundaries, :status)

      expect(reconcile).to be_reconciled
      expect(connection.select_value("SELECT status FROM authorization_boundaries WHERE name = 'existing'")).to eq("draft")
      expect(strict_drift).to eq([])
    end

    it "adds a column whose default is an SQL expression, evaluated per row, and its unique index" do
      2.times { boundary_row }
      connection.remove_column(:authorization_boundaries, :uuid)

      expect(reconcile).to be_reconciled
      uuids = connection.select_values("SELECT uuid FROM authorization_boundaries")
      expect(uuids.uniq.size).to eq(uuids.size)
      expect(strict_drift).to eq([])
    end

    it "creates a missing table with its columns, indexes and foreign keys" do
      connection.drop_table(:ssp_information_types, force: :cascade)

      result = reconcile

      expect(result).to be_reconciled
      expect(result.statements.join("\n")).to include('CREATE TABLE "ssp_information_types"')
      expect(strict_drift).to eq([])
    end

    it "adds a missing index and a missing foreign key" do
      connection.remove_index(:cdef_controls, name: "index_cdef_controls_on_document_and_source")
      connection.remove_foreign_key(:api_tokens, :users)

      expect(reconcile).to be_reconciled
      expect(strict_drift).to eq([])
    end

    it "enables a missing extension BEFORE recreating the index that needs it" do
      connection.execute("DROP EXTENSION pg_trgm CASCADE")

      result = reconcile

      expect(result).to be_reconciled
      extension_at = result.statements.index { |s| s.include?("pg_trgm") && s.start_with?("CREATE EXTENSION") }
      index_at = result.statements.index { |s| s.include?("idx_cdef_components_search_trgm") }
      expect(extension_at).to be < index_at
      expect(strict_drift).to eq([])
    end

    it "records what it did, statement by statement" do
      connection.remove_column(:authorization_boundaries, :description)

      expect { reconcile }.to change { AuditEvent.where(action: "schema_reconciled").count }.by(1)
      event = AuditEvent.where(action: "schema_reconciled").last
      expect(event.metadata["drift"]).to eq([ "missing column authorization_boundaries.description" ])
      expect(event.metadata["statements"].join).to include('ADD "description"')
      expect(event.metadata["schema_rb_version"]).to eq(SchemaDefinition.load(Rails.root.join("db/schema.rb")).version)
    end
  end

  describe "refusal — nothing is changed" do
    it "refuses a NOT NULL column with no default on a populated table, and applies NOTHING else either" do
      boundary_row
      connection.remove_column(:authorization_boundaries, :name)
      connection.remove_column(:authorization_boundaries, :description)

      result = reconcile

      expect(result).to be_refused
      expect(result.reasons.join).to match(/authorization_boundaries\.name is NOT NULL with no default/)
      expect(connection.column_exists?(:authorization_boundaries, :description)).to be(false)
    end

    it "adds that same column to an EMPTY table, where it is safe" do
      connection.execute("DELETE FROM authorization_boundaries")
      connection.remove_column(:authorization_boundaries, :name)

      expect(reconcile).to be_reconciled
      expect(strict_drift).to eq([])
    end

    it "refuses drift that is not additive" do
      connection.change_column(:ssp_information_types, :title, :text)

      result = reconcile

      expect(result).to be_refused
      expect(result.reasons.join).to match(/ssp_information_types\.title is text.*not additive/)
    end

    it "rolls back and refuses when a statement fails — a unique index over duplicate data" do
      boundary_row
      boundary_row
      connection.remove_index(:authorization_boundaries, name: "idx_auth_boundaries_on_uuid")
      connection.execute("UPDATE authorization_boundaries SET uuid = 'same'")
      connection.remove_column(:authorization_boundaries, :description)

      result = reconcile

      expect(result).to be_refused
      expect(result.reasons.join).to match(/idx_auth_boundaries_on_uuid|unique|duplicate/i)
      expect(connection.column_exists?(:authorization_boundaries, :description)).to be(false)
    end

    it "records the refusal and its reasons" do
      connection.change_column(:ssp_information_types, :title, :text)

      expect { reconcile }.to change { AuditEvent.where(action: "schema_reconciliation_refused").count }.by(1)
      expect(AuditEvent.where(action: "schema_reconciliation_refused").last.metadata["reasons"]).to be_present
    end
  end

  describe "dry run" do
    it "reports the exact statements, then rolls every one of them back" do
      connection.remove_column(:authorization_boundaries, :description)

      result = nil
      expect { result = reconcile(dry_run: true) }.not_to change(AuditEvent, :count)

      expect(result).to be_planned
      expect(result.statements.join).to include('ADD "description"')
      expect(connection.column_exists?(:authorization_boundaries, :description)).to be(false)
    end

    # The suite's own wrapping transaction is non-joinable, so Rails savepoints
    # inside it regardless and the example above cannot see this. A CALLER's
    # ordinary transaction is joinable: without `requires_new:` the rollback is
    # swallowed and the dry run quietly applies.
    it "still rolls back when called inside a caller's own transaction" do
      connection.remove_column(:authorization_boundaries, :description)

      ActiveRecord::Base.transaction { reconcile(dry_run: true) }

      expect(connection.column_exists?(:authorization_boundaries, :description)).to be(false)
    end
  end
end
