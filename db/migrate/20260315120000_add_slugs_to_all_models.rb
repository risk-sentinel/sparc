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

    # Backfill slugs from name/title fields.
    # Uses a window function to detect duplicate names and append
    # a numeric suffix (-2, -3, etc.) for uniqueness.
    reversible do |dir|
      dir.up do
        # Models with `name` column
        %w[
          control_catalogs ssp_documents sar_documents cdef_documents
          sap_documents poam_documents profile_documents
          authorization_boundaries control_mappings organizations
        ].each do |table|
          backfill_slugs(table, "name")
        end

        # Evidence uses `title` instead of `name`
        backfill_slugs("evidences", "title")
      end
    end
  end

  private

  def backfill_slugs(table, source_column)
    execute <<~SQL.squish
      UPDATE #{table}
      SET slug = sub.unique_slug
      FROM (
        SELECT id,
               CASE
                 WHEN ROW_NUMBER() OVER (
                   PARTITION BY LOWER(REGEXP_REPLACE(
                     REGEXP_REPLACE(#{source_column}, '[^a-zA-Z0-9\\s-]', '', 'g'),
                     '\\s+', '-', 'g'))
                   ORDER BY id
                 ) = 1
                 THEN LOWER(REGEXP_REPLACE(
                   REGEXP_REPLACE(#{source_column}, '[^a-zA-Z0-9\\s-]', '', 'g'),
                   '\\s+', '-', 'g'))
                 ELSE LOWER(REGEXP_REPLACE(
                   REGEXP_REPLACE(#{source_column}, '[^a-zA-Z0-9\\s-]', '', 'g'),
                   '\\s+', '-', 'g'))
                   || '-' || ROW_NUMBER() OVER (
                     PARTITION BY LOWER(REGEXP_REPLACE(
                       REGEXP_REPLACE(#{source_column}, '[^a-zA-Z0-9\\s-]', '', 'g'),
                       '\\s+', '-', 'g'))
                     ORDER BY id
                   )
               END AS unique_slug
        FROM #{table}
        WHERE #{source_column} IS NOT NULL
      ) sub
      WHERE #{table}.id = sub.id
        AND #{table}.slug IS NULL
    SQL
  end
end
