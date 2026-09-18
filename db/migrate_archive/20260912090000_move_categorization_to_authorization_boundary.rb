# frozen_string_literal: true

# #940 S3 — FIPS-199 categorization belongs to the BOUNDARY, not the SSP.
#
# Owner, 2026-09-12: "The boundary's Classification is part of the boundary so
# that the SSP is accurate. Information types is both SP 800-60 and 800-53
# related to keep the boundaries Classification, Integrity, Availability (CIA)
# of data and what the boundary really is."
#
# This is the NIST chain: SP 800-60 information types carry provisional C/I/A
# impacts, the system owner adjusts them, FIPS-199 takes the HIGH WATER MARK as
# the system categorization, and that selects the 800-53 baseline.
#
# It was modelled on SspDocument, which put it one level too low:
#   * two SSPs for one boundary could disagree, and nothing detected it
#   * a boundary could not be categorized until an SSP existed — even though
#     categorization is what SELECTS the baseline the SSP is written against
#
# Additive and reversible. The SspDocument columns are LEFT IN PLACE and keep
# their values: the models read the boundary first and fall back to them, so a
# deployment mid-upgrade is never left with a blank categorization. Dropping
# them is a separate decision once nothing reads them.
class MoveCategorizationToAuthorizationBoundary < ActiveRecord::Migration[8.1]
  def up
    add_column :authorization_boundaries, :security_objective_confidentiality, :string
    add_column :authorization_boundaries, :security_objective_integrity, :string
    add_column :authorization_boundaries, :security_objective_availability, :string

    # Information types are the INPUT to the categorization, so they move with
    # it. Nullable: an information type authored against an SSP that has no
    # boundary yet is still valid data.
    add_reference :ssp_information_types, :authorization_boundary,
                  null: true, foreign_key: true, index: true

    up_only do
      # Lift each boundary's categorization from its SSP. `DISTINCT ON` picks one
      # SSP per boundary deterministically (newest first) — a boundary with two
      # SSPs that disagree is exactly the defect this migration ends, and the
      # newest is the best available answer.
      execute <<~SQL
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
      SQL

      # Point each information type at the boundary its SSP belongs to.
      execute <<~SQL
        UPDATE ssp_information_types it
        SET authorization_boundary_id = sd.authorization_boundary_id
        FROM ssp_documents sd
        WHERE it.ssp_document_id = sd.id
          AND sd.authorization_boundary_id IS NOT NULL
      SQL
    end
  end

  def down
    remove_reference :ssp_information_types, :authorization_boundary, foreign_key: true
    remove_column :authorization_boundaries, :security_objective_availability
    remove_column :authorization_boundaries, :security_objective_integrity
    remove_column :authorization_boundaries, :security_objective_confidentiality
  end
end
