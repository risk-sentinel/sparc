# frozen_string_literal: true

# #1354 / #1384 — push and Class A on a connection.
#
# Push: a provider tells SPARC that a registered document changed, by a
# request it signs with an Ed25519 key whose public half is pinned on the
# connection (two at most, so the provider can rotate). SPARC then pulls the
# document fresh from its registered address; the push itself never decides
# what is stored.
#
#   exchange_connections.push_public_keys   pinned Ed25519 public keys, base64 of the raw 32 bytes
#   exchange_connections.last_pushed_at / last_push_status
#   exchange_push_receipts                  one row per accepted push request: what was
#                                           pushed (SHA-256), with which key, when it was
#                                           signed, and whether the fresh pull confirmed it.
#                                           signature_sha256 is unique: a signature is
#                                           accepted once (replay protection)
#   received_documents.push_confirmed       nil unless the version came from a push; false
#                                           for pushed bytes the fresh pull did not confirm
#
# Class A (FedRAMP FRC-CLA-ASF): the alternative security framework the
# provider's certification rests on, when it was certified, and when it
# expires, 12 months later.
#
# Idempotent (docs/dev/issue_rules.md, migration rules 1–6).
class AddExchangePushAndClassA < ActiveRecord::Migration[8.1]
  CONNECTION_COLUMNS = {
    push_public_keys: [ :jsonb, { null: false, default: [] } ],
    last_pushed_at: [ :datetime, {} ],
    last_push_status: [ :string, {} ],
    class_a_framework: [ :string, {} ],
    class_a_certified_on: [ :date, {} ],
    class_a_expires_on: [ :date, {} ]
  }.freeze

  def up
    CONNECTION_COLUMNS.each do |name, (type, options)|
      add_column :exchange_connections, name, type, **options unless column_exists?(:exchange_connections, name)
    end

    unless column_exists?(:received_documents, :push_confirmed)
      add_column :received_documents, :push_confirmed, :boolean, null: true
    end

    create_table :exchange_push_receipts, if_not_exists: true do |t|
      t.references :exchange_connection, null: false, foreign_key: true, index: true
      t.references :exchange_document_source, null: true, foreign_key: { on_delete: :nullify }, index: true
      t.references :received_document, null: true, foreign_key: { on_delete: :nullify }, index: true
      t.string :sha256, null: false
      t.bigint :byte_size, null: false, default: 0
      t.string :content_type
      t.string :signature_sha256, null: false
      t.string :key_fingerprint, null: false
      t.datetime :signed_at, null: false
      t.string :remote_ip
      t.string :status, null: false, default: "pending"
      t.text :reason
      t.datetime :completed_at
      t.timestamps
    end
    unless index_exists?(:exchange_push_receipts, :signature_sha256, unique: true)
      add_index :exchange_push_receipts, :signature_sha256, unique: true
    end
  end

  def down
    drop_table :exchange_push_receipts, if_exists: true
    remove_column :received_documents, :push_confirmed if column_exists?(:received_documents, :push_confirmed)
    CONNECTION_COLUMNS.each_key do |name|
      remove_column :exchange_connections, name if column_exists?(:exchange_connections, name)
    end
  end
end
