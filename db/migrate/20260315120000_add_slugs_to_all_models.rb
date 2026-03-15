# frozen_string_literal: true

class AddSlugsToAllModels < ActiveRecord::Migration[8.1]
  def change
    tables = %i[
      control_catalogs ssp_documents sar_documents cdef_documents
      sap_documents poam_documents profile_documents evidences
      authorization_boundaries control_mappings organizations
    ]

    tables.each do |table|
      add_column table, :slug, :string
      add_index table, :slug, unique: true
    end

    # Backfill slugs from name/title fields
    reversible do |dir|
      dir.up do
        # Models with `name` column
        %w[
          control_catalogs ssp_documents sar_documents cdef_documents
          sap_documents poam_documents profile_documents
          authorization_boundaries control_mappings organizations
        ].each do |table|
          execute <<~SQL.squish
            UPDATE #{table}
            SET slug = LOWER(REGEXP_REPLACE(
              REGEXP_REPLACE(name, '[^a-zA-Z0-9\\s-]', '', 'g'),
              '\\s+', '-', 'g'))
            WHERE slug IS NULL AND name IS NOT NULL
          SQL
        end

        # Evidence uses `title` instead of `name`
        execute <<~SQL.squish
          UPDATE evidences
          SET slug = LOWER(REGEXP_REPLACE(
            REGEXP_REPLACE(title, '[^a-zA-Z0-9\\s-]', '', 'g'),
            '\\s+', '-', 'g'))
          WHERE slug IS NULL AND title IS NOT NULL
        SQL
      end
    end
  end
end
