# frozen_string_literal: true

# #1147 — the columns the #1124 squash archived out of reach.
#
# ── What happened ──────────────────────────────────────────────────────────
#
# The squash (#1124, shipped in v1.16.1) replaced 42 schema migrations with one
# version-stamping migration. On a FRESH install that is correct: `db:prepare`
# loads `schema.rb`, which carries every column, and the stamp records the
# archived versions as applied.
#
# On an EXISTING database it is not, because `db:migrate` never consults
# `schema.rb` — it applies migrations. The stamp does no DDL:
#
#   == 20260912090000 SquashMigrationsToCurrentSchemaV2: migrated (0.0009s) ==
#
# So a deployment upgrading v1.16.0 -> v1.16.2 ends with **zero pending
# migrations and a schema missing seven columns**. The release note ("no pending
# migrations") was true and told nobody anything.
#
# Two of the 42 archived migrations post-dated v1.16.0, so no deployment had
# ever run them:
#
#   20260908180000_add_component_attribution_to_cdef_controls  (#1088)
#   20260912090000_move_categorization_to_authorization_boundary  (#940 S3)
#
# Measured in production: `GET /authorization_boundaries/:id` returns 500 on
# every boundary —
#
#   PG::UndefinedColumn: column ssp_information_types.authorization_boundary_id
#   does not exist
#     app/models/authorization_boundary.rb:100  #security_objective
#     app/services/boundary_readiness_service.rb:94  #classification
#
# The `cdef_controls` columns had not surfaced yet only because nobody had
# opened a CDEF page.
#
# ── Why this migration is shaped the way it is ─────────────────────────────
#
# IDEMPOTENT BY CONSTRUCTION, because it has to run against both populations: a
# fresh database that already has every column via `schema:load`, and an
# upgraded one that has none of them. Every statement is guarded, so this is a
# no-op on the former and a repair on the latter.
#
# THE BACKFILLS COME WITH IT. #940 S3 carried an `up_only` data lift, and adding
# the columns without it would leave every upgraded boundary uncategorized —
# the same bug, quieter: the page would render, and the FIPS-199 categorization
# that selects the control baseline would read as blank. Both updates only
# touch NULLs, so re-running changes nothing.
#
# NOT DEFERRED. The deferred-data-migration runner exists to keep long backfills
# off the boot path; this is DDL that the application cannot start without
# serving 500s, so it belongs in `db:migrate` where a failure blocks the deploy.
class RepairColumnsArchivedByTheSquash < ActiveRecord::Migration[8.1]
  def up
    repair_boundary_categorization
    repair_information_type_boundary
    repair_cdef_control_attribution
    backfill_categorization
  end

  def down
    # Deliberately empty, and it is not laziness. `up` is a repair, not a
    # feature: on a fresh database every column already existed before this ran,
    # so a `down` that dropped them would destroy structure this migration never
    # created and that `schema.rb` still declares. Reversing the repair means
    # restoring the archived migrations, not deleting columns.
    # (Inside the method because Sonar's empty-method rule does not read the
    # comment above it.)
  end

  private

  # #940 S3 — FIPS-199 categorization belongs to the boundary.
  def repair_boundary_categorization
    %i[security_objective_confidentiality
       security_objective_integrity
       security_objective_availability].each do |column|
      next if column_exists?(:authorization_boundaries, column)

      add_column :authorization_boundaries, column, :string
      say "authorization_boundaries.#{column} restored"
    end
  end

  def repair_information_type_boundary
    return if column_exists?(:ssp_information_types, :authorization_boundary_id)

    add_reference :ssp_information_types, :authorization_boundary,
                  null: true, foreign_key: true, index: true
    say "ssp_information_types.authorization_boundary_id restored"
  end

  # #1088 items 4 and 5 — which component asserted a control, and against which
  # source. Strings, not foreign keys: `CdefComponentIndexer#index!` is
  # delete_all + insert_all!, so every primary key changes on re-index and an FK
  # would dangle. The OSCAL uuid is stable by construction.
  def repair_cdef_control_attribution
    { component_uuid: :string,
      implementation_source: :string,
      implementation_description: :text }.each do |column, type|
      next if column_exists?(:cdef_controls, column)

      add_column :cdef_controls, column, type
      say "cdef_controls.#{column} restored"
    end

    add_index :cdef_controls, %i[cdef_document_id component_uuid],
              name: "index_cdef_controls_on_document_and_component", if_not_exists: true
    add_index :cdef_controls, %i[cdef_document_id implementation_source],
              name: "index_cdef_controls_on_document_and_source", if_not_exists: true
  end

  # The data half of #940 S3. Only NULLs are written, so a fresh database — where
  # the original migration already ran — is untouched, and a re-run is a no-op.
  def backfill_categorization
    lifted = execute(<<~SQL.squish).cmd_tuples
      UPDATE authorization_boundaries ab
      SET security_objective_confidentiality = s.security_objective_confidentiality,
          security_objective_integrity       = s.security_objective_integrity,
          security_objective_availability    = s.security_objective_availability
      FROM (
        SELECT DISTINCT ON (authorization_boundary_id)
               authorization_boundary_id,
               security_objective_confidentiality,
               security_objective_integrity,
               security_objective_availability
        FROM ssp_documents
        WHERE authorization_boundary_id IS NOT NULL
        ORDER BY authorization_boundary_id, updated_at DESC
      ) s
      WHERE ab.id = s.authorization_boundary_id
        AND ab.security_objective_confidentiality IS NULL
        AND ab.security_objective_integrity IS NULL
        AND ab.security_objective_availability IS NULL
    SQL

    pointed = execute(<<~SQL.squish).cmd_tuples
      UPDATE ssp_information_types it
      SET authorization_boundary_id = sd.authorization_boundary_id
      FROM ssp_documents sd
      WHERE it.ssp_document_id = sd.id
        AND sd.authorization_boundary_id IS NOT NULL
        AND it.authorization_boundary_id IS NULL
    SQL

    say "categorization: #{lifted} boundary(ies) lifted from their SSP, " \
        "#{pointed} information type(s) pointed at their boundary"
  end
end
