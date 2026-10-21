# frozen_string_literal: true

# v1.17.2 — clear the catalog LABELS that were stored as parameter values.
#
# Building a baseline from a catalog seeded every organization-defined
# parameter's VALUE with the catalog's LABEL: `ac-01_odp.01` = "personnel or
# roles", which is NIST's description of what to decide, not a decision. The
# screens showed it as the baseline's value and the OSCAL export listed it
# under `set-parameters`, asserting tailoring nobody made.
#
# ProfileControlSelectionService no longer seeds it. This clears what is
# already stored: a `parameter:<id>` value EXACTLY equal to the same control's
# `parameter_label:<id>` becomes empty (not set). Anything else is an answer
# and is left alone. The label row itself is untouched.
#
# The one value this cannot tell apart is an author who typed the label's
# exact wording as their answer. That is accepted (owner, 2026-10-21): the
# value is restated by setting it again, while the fabricated tailoring is in
# every baseline built from a catalog.
#
# Idempotent: a second run finds nothing equal to its label. A run stopped
# part-way resumes where it left off for the same reason.
class ClearSeededParameterLabels < ActiveRecord::Migration[8.1]
  include DeferredDataMigration
  data_migration_version "1.0.0"

  def up
    defer_data_migration do
      cleared = clear_seeded_labels
      say "Cleared #{cleared} parameter value(s) that were the catalog's label, not an answer"
    end
  end

  def down
    # Not reversible by design: putting the labels back would re-assert
    # tailoring nobody made. Nothing to undo.
  end

  private

  def clear_seeded_labels
    connection.update(<<~SQL.squish)
      UPDATE profile_control_fields AS v
         SET field_value = '', updated_at = NOW()
        FROM profile_control_fields AS l
       WHERE l.profile_control_id = v.profile_control_id
         AND v.field_name LIKE 'parameter:%'
         AND l.field_name = 'parameter_label:' || substring(v.field_name FROM 11)
         AND v.field_value <> ''
         AND v.field_value = l.field_value
    SQL
  end
end
