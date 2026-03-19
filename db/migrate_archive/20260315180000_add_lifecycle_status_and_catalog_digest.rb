class AddLifecycleStatusAndCatalogDigest < ActiveRecord::Migration[8.0]
  def up
    # Add lifecycle_status to all document tables
    %i[
      ssp_documents sar_documents sap_documents cdef_documents
      poam_documents profile_documents control_catalogs
    ].each do |table|
      add_column table, :lifecycle_status, :string, default: "in_progress"
      add_index table, :lifecycle_status
    end

    # Add catalog content digest for traceability
    add_column :control_catalogs, :catalog_content_digest, :string

    # Backfill existing records
    execute <<~SQL
      UPDATE ssp_documents     SET lifecycle_status = 'in_progress' WHERE status = 'completed';
      UPDATE sar_documents     SET lifecycle_status = 'in_progress' WHERE status = 'completed';
      UPDATE sap_documents     SET lifecycle_status = 'in_progress' WHERE status = 'completed';
      UPDATE cdef_documents    SET lifecycle_status = 'in_progress' WHERE status = 'completed';
      UPDATE poam_documents    SET lifecycle_status = 'in_progress' WHERE status = 'completed';
      UPDATE control_catalogs  SET lifecycle_status = 'published'   WHERE status = 'completed';
    SQL

    # Profiles with a published timestamp are already published
    execute <<~SQL
      UPDATE profile_documents SET lifecycle_status = 'in_progress' WHERE status = 'completed' AND (published IS NULL OR published = '');
      UPDATE profile_documents SET lifecycle_status = 'published'   WHERE status = 'completed' AND published IS NOT NULL AND published != '';
    SQL
  end

  def down
    %i[
      ssp_documents sar_documents sap_documents cdef_documents
      poam_documents profile_documents control_catalogs
    ].each do |table|
      remove_index table, :lifecycle_status, if_exists: true
      remove_column table, :lifecycle_status
    end

    remove_column :control_catalogs, :catalog_content_digest
  end
end
