class AddAuthoritativeWorkflowAndFederationToBackMatterResources < ActiveRecord::Migration[8.0]
  def change
    # ── Allow library / federated / authoritative resources to exist
    #     without a parent document (resourceable). Document-scoped
    #     resources still set both columns; library entries leave them null.
    change_column_null :back_matter_resources, :resourceable_type, true
    change_column_null :back_matter_resources, :resourceable_id,   true

    # ── Promotion workflow ────────────────────────────────────────────────
    unless column_exists?(:back_matter_resources, :promotion_status)
      add_column :back_matter_resources, :promotion_status, :string,
                 default: "none", null: false
    end

    unless column_exists?(:back_matter_resources, :promoted_from_organization_id)
      add_reference :back_matter_resources, :promoted_from_organization,
                    null: true, foreign_key: { to_table: :organizations }
    end

    unless column_exists?(:back_matter_resources, :promoted_from_authorization_boundary_id)
      add_reference :back_matter_resources, :promoted_from_authorization_boundary,
                    null: true, foreign_key: { to_table: :authorization_boundaries }
    end

    unless column_exists?(:back_matter_resources, :approved_by_user_id)
      add_reference :back_matter_resources, :approved_by_user,
                    null: true, foreign_key: { to_table: :users }
    end

    unless column_exists?(:back_matter_resources, :approved_at)
      add_column :back_matter_resources, :approved_at, :datetime
    end

    unless column_exists?(:back_matter_resources, :rejection_reason)
      add_column :back_matter_resources, :rejection_reason, :text
    end

    # ── Archive / supersede ───────────────────────────────────────────────
    unless column_exists?(:back_matter_resources, :archived_at)
      add_column :back_matter_resources, :archived_at, :datetime
    end

    unless column_exists?(:back_matter_resources, :superseded_by_id)
      add_reference :back_matter_resources, :superseded_by,
                    null: true,
                    foreign_key: { to_table: :back_matter_resources, on_delete: :nullify }
    end

    # ── Federation provenance ─────────────────────────────────────────────
    unless column_exists?(:back_matter_resources, :federated_from_instance)
      add_column :back_matter_resources, :federated_from_instance, :string
    end

    unless column_exists?(:back_matter_resources, :federated_bundle_uuid)
      add_column :back_matter_resources, :federated_bundle_uuid, :string
    end

    unless column_exists?(:back_matter_resources, :federated_at)
      add_column :back_matter_resources, :federated_at, :datetime
    end

    unless column_exists?(:back_matter_resources, :original_uuid)
      add_column :back_matter_resources, :original_uuid, :string
    end

    # ── Indexes for new query patterns ────────────────────────────────────
    unless index_exists?(:back_matter_resources, :promotion_status,
                         name: "idx_back_matter_resources_pending_review")
      add_index :back_matter_resources, :promotion_status,
                where: "promotion_status = 'pending_review'",
                name: "idx_back_matter_resources_pending_review"
    end

    unless index_exists?(:back_matter_resources, :archived_at,
                         name: "idx_back_matter_resources_active")
      add_index :back_matter_resources, :archived_at,
                where: "archived_at IS NULL",
                name: "idx_back_matter_resources_active"
    end

    unless index_exists?(:back_matter_resources,
                         [ :federated_from_instance, :original_uuid ],
                         name: "idx_back_matter_resources_federation_dedup")
      add_index :back_matter_resources,
                [ :federated_from_instance, :original_uuid ],
                name: "idx_back_matter_resources_federation_dedup"
    end

    # ── Changelog (audit trail per resource attribute change) ─────────────
    unless table_exists?(:back_matter_resource_changes)
      create_table :back_matter_resource_changes do |t|
        t.references :back_matter_resource, null: false, foreign_key: true
        t.references :changed_by_user, null: true,
                     foreign_key: { to_table: :users }
        t.string  :change_type, null: false # create|update|promote|approve|reject|archive|restore|federate
        t.string  :field
        t.text    :from_value
        t.text    :to_value
        t.string  :batch_uuid
        t.datetime :changed_at, null: false

        t.timestamps
      end

      add_index :back_matter_resource_changes, :batch_uuid
      add_index :back_matter_resource_changes,
                [ :back_matter_resource_id, :changed_at ],
                name: "idx_bmr_changes_resource_chronological"
    end

    # ── Federation peers (configured remote SPARC instances) ──────────────
    unless table_exists?(:federation_peers)
      create_table :federation_peers do |t|
        t.string   :name, null: false
        t.string   :base_url, null: false
        t.text     :encrypted_service_token # AR encrypts attribute via the model
        t.boolean  :enabled, default: true, null: false
        t.datetime :last_synced_at
        t.text     :last_sync_status

        t.timestamps
      end

      add_index :federation_peers, :name, unique: true
    end
  end
end
