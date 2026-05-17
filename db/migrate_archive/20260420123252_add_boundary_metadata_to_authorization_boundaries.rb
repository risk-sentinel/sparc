class AddBoundaryMetadataToAuthorizationBoundaries < ActiveRecord::Migration[8.1]
  # #395 Phase 3: AuthorizationBoundary becomes the source of truth for
  # system-level metadata (system owner, authorizing official, impact level,
  # etc.) and gets a deterministic UUID so #396 (Leveraged Authorizations)
  # can derive stable OSCAL UUIDs from it.
  #
  # Idempotent: every column / index guard uses column_exists? / index_exists?.
  def up
    unless column_exists?(:authorization_boundaries, :boundary_metadata)
      add_column :authorization_boundaries, :boundary_metadata, :jsonb,
                 default: {}, null: false
    end

    unless column_exists?(:authorization_boundaries, :profile_document_id)
      add_reference :authorization_boundaries, :profile_document,
                    null: true, foreign_key: { on_delete: :nullify }, index: true
    end

    unless column_exists?(:authorization_boundaries, :uuid)
      add_column :authorization_boundaries, :uuid, :string,
                 null: false, default: -> { "gen_random_uuid()" }
    end

    unless index_exists?(:authorization_boundaries, :uuid, unique: true)
      add_index :authorization_boundaries, :uuid, unique: true,
                name: "idx_auth_boundaries_on_uuid"
    end

    # Backfill: any boundary with a linked SSP gets system_title populated
    # from the SSP name. Skips boundaries that already have non-empty
    # metadata so reruns are no-ops.
    execute(<<~SQL)
      UPDATE authorization_boundaries ab
      SET
        boundary_metadata = jsonb_build_object('system_title', s.name),
        profile_document_id = COALESCE(ab.profile_document_id, s.profile_document_id)
      FROM ssp_documents s
      WHERE s.authorization_boundary_id = ab.id
        AND (ab.boundary_metadata IS NULL OR ab.boundary_metadata = '{}'::jsonb)
    SQL
  end

  def down
    if column_exists?(:poam_documents, :ssp_document_id)
      remove_foreign_key :poam_documents, column: :ssp_document_id rescue nil
      remove_reference   :poam_documents, :ssp_document, index: true
    end
    if index_exists?(:authorization_boundaries, :uuid, name: "idx_auth_boundaries_on_uuid")
      remove_index :authorization_boundaries, name: "idx_auth_boundaries_on_uuid"
    end
    remove_column :authorization_boundaries, :uuid                if column_exists?(:authorization_boundaries, :uuid)
    if column_exists?(:authorization_boundaries, :profile_document_id)
      remove_foreign_key :authorization_boundaries, column: :profile_document_id rescue nil
      remove_reference   :authorization_boundaries, :profile_document, index: true
    end
    remove_column :authorization_boundaries, :boundary_metadata   if column_exists?(:authorization_boundaries, :boundary_metadata)
  end
end
