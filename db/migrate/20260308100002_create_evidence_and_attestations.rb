class CreateEvidenceAndAttestations < ActiveRecord::Migration[8.1]
  def change
    create_table :evidences do |t|
      t.string  :title, null: false
      t.text    :description
      t.string  :evidence_type, null: false, default: "artifact"
      t.string  :file_hash
      t.string  :file_content_type
      t.string  :original_filename
      t.integer :file_size
      t.string  :status, null: false, default: "draft"
      t.datetime :collected_at
      t.string  :collected_by
      t.string  :source
      t.bigint  :project_id
      t.timestamps
    end

    add_index :evidences, :evidence_type
    add_index :evidences, :status
    add_index :evidences, :collected_at
    add_index :evidences, :project_id
    add_foreign_key :evidences, :projects, on_delete: :nullify

    create_table :evidence_control_links do |t|
      t.bigint :evidence_id, null: false
      t.string :control_id, null: false
      t.string :control_type
      t.string :document_type
      t.bigint :document_id
      t.timestamps
    end

    add_index :evidence_control_links, :evidence_id
    add_index :evidence_control_links, [ :evidence_id, :control_id, :document_type, :document_id ],
              name: "idx_evidence_ctrl_link_unique", unique: true
    add_foreign_key :evidence_control_links, :evidences, on_delete: :cascade

    create_table :attestations do |t|
      t.bigint   :evidence_id, null: false
      t.string   :attester_name, null: false
      t.string   :attester_email
      t.string   :role
      t.text     :statement, null: false
      t.datetime :attested_at, null: false
      t.string   :signature_hash
      t.timestamps
    end

    add_index :attestations, :evidence_id
    add_index :attestations, :attested_at
    add_foreign_key :attestations, :evidences, on_delete: :cascade
  end
end
