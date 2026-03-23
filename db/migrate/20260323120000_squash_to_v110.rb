# frozen_string_literal: true

# Pre-release migration squash — consolidates all schema changes through v1.1.0
# into a single migration. This replaces 73 individual migrations (64 original +
# 9 post-squash) with one clean entry point.
#
# For FRESH databases: evaluates db/schema.rb to create all 72 tables in one shot.
# For EXISTING databases: applies any missing columns/tables from the 8 post-squash
# migrations (handles partial migration states from interrupted deployments).
#
# Seeds (db/seeds.rb) are completely independent — they use SeedRunner with its own
# version tracking and are called separately from bin/docker-entrypoint.
#
# NIST SA-10: Developer Configuration Management
class SquashToV110 < ActiveRecord::Migration[8.1]
  def up
    if table_exists?(:ssp_documents)
      # Existing database — apply any missing columns/tables from post-squash migrations
      puts "[SquashToV110] Existing database detected — checking for missing schema additions..."
      apply_post_squash_additions
    else
      # Fresh database — load the entire schema in one shot from schema.rb
      puts "[SquashToV110] Fresh database detected — loading full schema..."
      schema = File.read(Rails.root.join("db/schema.rb"))

      # Strip the ActiveRecord::Schema wrapper, leaving just the create_table/add_index calls
      schema_body = schema.gsub(/\A.*ActiveRecord::Schema\[[\d.]+\]\.define\(version: \d+_\d+_\d+\) do/m, "")
      schema_body = schema_body.gsub(/\nend\s*\z/m, "")

      eval(schema_body) # rubocop:disable Security/Eval

      puts "[SquashToV110] Schema loaded — #{ActiveRecord::Base.connection.tables.count} tables created."
    end
  end

  def down
    raise ActiveRecord::IrreversibleMigration,
          "This migration consolidates all schema changes through SPARC v1.1.0. " \
          "To revert, restore from a database backup."
  end

  private

  # Idempotently apply all post-squash schema additions for databases that may
  # have partially applied the individual migrations before this squash.
  def apply_post_squash_additions
    changes = 0

    # From: 20260320140536_add_stig_id_to_cdef_controls
    unless column_exists?(:cdef_controls, :stig_id)
      add_column :cdef_controls, :stig_id, :string
      add_index :cdef_controls, [ :cdef_document_id, :stig_id ], name: "idx_cdef_controls_doc_stig", unique: true
      changes += 1
    end

    # From: 20260320163212_create_api_tokens
    unless table_exists?(:api_tokens)
      create_table :api_tokens do |t|
        t.references :user, null: false, foreign_key: true
        t.string :name, null: false
        t.string :token_digest, null: false
        t.datetime :expires_at
        t.datetime :last_used_at
        t.string :last_used_ip
        t.jsonb :scopes, default: {}
        t.timestamps
      end
      add_index :api_tokens, :token_digest, unique: true
      changes += 1
    end

    # From: 20260321013309_add_deleted_at_to_documents
    %i[ssp_documents sar_documents sap_documents poam_documents].each do |tbl|
      unless column_exists?(tbl, :deleted_at)
        add_column tbl, :deleted_at, :datetime
        add_index tbl, :deleted_at
        changes += 1
      end
    end

    # From: 20260321083520_add_deleted_at_to_profile_and_cdef_documents
    %i[profile_documents cdef_documents].each do |tbl|
      unless column_exists?(tbl, :deleted_at)
        add_column tbl, :deleted_at, :datetime
        add_index tbl, :deleted_at
        changes += 1
      end
    end

    # From: 20260321104459_create_ksi_validations
    unless table_exists?(:ksi_validations)
      create_table :ksi_validations do |t|
        t.references :authorization_boundary, null: false, foreign_key: true
        t.references :catalog_control, null: false, foreign_key: true
        t.references :evidence, foreign_key: true
        t.string :status, null: false, default: "not_assessed"
        t.string :validation_method
        t.string :evidence_format
        t.datetime :last_validated_at
        t.datetime :next_validation_due
        t.text :notes
        t.jsonb :validation_metadata, default: {}
        t.string :uuid, null: false, default: -> { "gen_random_uuid()" }
        t.timestamps
      end
      add_index :ksi_validations, [ :authorization_boundary_id, :catalog_control_id ],
                unique: true, name: "idx_ksi_validations_boundary_control"
      add_index :ksi_validations, :uuid, unique: true
      add_index :ksi_validations, :status
      add_index :ksi_validations, :next_validation_due
      changes += 1
    end

    # From: 20260321160538_add_service_account_to_users
    unless column_exists?(:users, :service_account)
      add_column :users, :service_account, :boolean, default: false, null: false
      add_index :users, :service_account
      changes += 1
    end

    # From: 20260321211012_add_service_account_fields
    unless column_exists?(:users, :owner_id)
      add_reference :users, :owner, foreign_key: { to_table: :users }, null: true
      changes += 1
    end
    unless column_exists?(:users, :disabled_at)
      add_column :users, :disabled_at, :datetime
      add_column :users, :disabled_reason, :string
      changes += 1
    end
    unless column_exists?(:api_tokens, :allowed_endpoints)
      add_column :api_tokens, :allowed_endpoints, :jsonb, default: []
      add_column :api_tokens, :allowed_cidrs, :jsonb, default: []
      add_reference :api_tokens, :created_by, foreign_key: { to_table: :users }, null: true
      changes += 1
    end

    # From: 20260323081951_create_seed_sections
    unless table_exists?(:seed_sections)
      create_table :seed_sections do |t|
        t.string :name, null: false
        t.string :version, default: "1.0.0"
        t.string :status, default: "pending"
        t.text :error_message
        t.integer :records_created, default: 0
        t.datetime :completed_at
        t.timestamps
      end
      add_index :seed_sections, :name, unique: true
      changes += 1
    end

    if changes > 0
      puts "[SquashToV110] Applied #{changes} missing schema addition(s)."
    else
      puts "[SquashToV110] Schema is up to date — no changes needed."
    end
  end
end
