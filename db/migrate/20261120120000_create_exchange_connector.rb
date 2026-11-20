# frozen_string_literal: true

# #1354 — the connector core. SPARC takes FedRAMP, OSCAL, HDF and XCCDF
# documents from another system (a pull from a registered address) or from a
# person (an upload into a boundary), keeps every version it receives, and a
# reviewer of the receiving boundary accepts, answers or rejects each one.
#
#   exchange_connections      — another system SPARC pulls from: its trust
#                               center, the boundary its documents land in,
#                               its credential (encrypted) and its trust pins.
#   exchange_document_sources — each document set explicitly on a connection to
#                               pull (owner, 2026-11-20: crawl the root to find
#                               documents, pull only the explicit ones).
#   received_documents        — every version received, never overwritten.
#
# Idempotent (docs/dev/issue_rules.md, migration rules 1–6).
class CreateExchangeConnector < ActiveRecord::Migration[8.1]
  def up
    create_table :exchange_connections, if_not_exists: true do |t|
      t.string :name, null: false
      t.references :authorization_boundary, null: false, foreign_key: true, index: true
      t.string :fedramp_id
      t.string :certification_class
      t.string :certification_type
      t.string :root_url
      t.string :auth_scheme, null: false, default: "none"
      t.string :auth_header_name
      t.text :encrypted_credential
      t.jsonb :allowed_hosts, null: false, default: []
      t.jsonb :spki_sha256, null: false, default: []
      t.jsonb :allowed_cidrs, null: false, default: []
      t.boolean :enabled, null: false, default: true
      t.datetime :last_pulled_at
      t.string :last_pull_status
      t.text :last_error
      t.references :created_by, null: true, foreign_key: { to_table: :users }, index: true
      t.timestamps
    end
    add_index :exchange_connections, :name, unique: true unless index_exists?(:exchange_connections, :name, unique: true)

    create_table :exchange_document_sources, if_not_exists: true do |t|
      t.references :exchange_connection, null: false, foreign_key: true, index: true
      t.string :url, null: false
      t.string :format, null: false
      t.string :document_type
      t.integer :pull_interval_hours, null: false, default: 24
      t.boolean :enabled, null: false, default: true
      t.datetime :last_pulled_at
      t.string :last_status
      t.string :last_sha256
      t.text :last_error
      t.timestamps
    end
    unless index_exists?(:exchange_document_sources, %i[exchange_connection_id url], unique: true)
      add_index :exchange_document_sources, %i[exchange_connection_id url], unique: true
    end

    create_table :received_documents, if_not_exists: true do |t|
      t.references :authorization_boundary, null: false, foreign_key: true, index: true
      t.references :exchange_connection, null: true, foreign_key: true, index: true
      t.references :exchange_document_source, null: true, foreign_key: true, index: true
      t.string :source, null: false
      t.string :stream_key, null: false
      t.string :format, null: false
      t.string :document_type
      t.string :fedramp_id
      t.string :sha256, null: false
      t.bigint :byte_size, null: false, default: 0
      t.string :filename
      t.string :content_type
      t.string :state, null: false, default: "pending_review"
      t.boolean :valid_document, null: false, default: false
      t.jsonb :validation, null: false, default: {}
      t.jsonb :delta, null: false, default: {}
      t.integer :regression_count, null: false, default: 0
      t.integer :improvement_count, null: false, default: 0
      t.integer :neutral_count, null: false, default: 0
      t.boolean :auto_accepted, null: false, default: false
      t.datetime :received_at, null: false
      t.references :received_by, null: true, foreign_key: { to_table: :users }, index: true
      t.string :review_action
      t.text :review_note
      t.datetime :reviewed_at
      t.references :reviewed_by, null: true, foreign_key: { to_table: :users }, index: true
      t.references :scan_run, null: true, foreign_key: true, index: true
      t.timestamps
    end
    add_index :received_documents, %i[stream_key sha256], unique: true unless index_exists?(:received_documents, %i[stream_key sha256], unique: true)
    add_index :received_documents, %i[stream_key state] unless index_exists?(:received_documents, %i[stream_key state])
  end

  def down
    drop_table :received_documents, if_exists: true
    drop_table :exchange_document_sources, if_exists: true
    drop_table :exchange_connections, if_exists: true
  end
end
