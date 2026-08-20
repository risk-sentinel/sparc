# #1007 — a parameter's value is unique within a profile, and while the profile
# is a draft the last update wins. The data does not currently satisfy that.
#
# `BaselineParameterService#upsert_parameter_field` stored a value against
# whichever control `find_control_id_for_param` happened to resolve first, and a
# statement sub-part that merely CITES its parent's parameter resolves just as
# readily as the control that declares it. So the same logical ODP accumulated a
# row under several controls, and the read — a flat `param_id => value` map
# built by walking the association — returned whichever row came last. A user
# could tailor a parameter, be told it was updated, and read back the old value
# forever.
#
# The service now writes to the declaring control and deletes the strays, so new
# writes cannot reintroduce this. That leaves the rows already stored, which
# still shadow the next read until they are collapsed. On the instance this was
# found on, one profile carried 996 duplicate rows across 498 param_ids.
#
# Which value survives is not a judgement call: the owner's rule is that the
# last update wins, so the most recently updated row is kept and the rest are
# deleted. `updated_at` ties break on `id`, so the outcome is deterministic even
# for rows written in the same transaction.
#
# Idempotent by construction — a second run finds one row per group and deletes
# nothing.
class CollapseDuplicateProfileParameterFields < ActiveRecord::Migration[8.1]
  def up
    duplicates = count_duplicates
    if duplicates.zero?
      say "No duplicate parameter rows to collapse"
      return
    end

    say "Collapsing #{duplicates} duplicate parameter row(s)"

    # One statement, so there is no window in which a partial collapse leaves
    # the read ambiguous. `rn > 1` keeps the most recently updated row in each
    # (profile, param_id) group and deletes the rest; a second run ranks one row
    # per group and deletes nothing.
    execute(<<~SQL)
      DELETE FROM profile_control_fields
      WHERE id IN (
        SELECT id FROM (
          SELECT pcf.id,
                 ROW_NUMBER() OVER (
                   PARTITION BY pc.profile_document_id, pcf.field_name
                   ORDER BY pcf.updated_at DESC, pcf.id DESC
                 ) AS rn
          FROM profile_control_fields pcf
          JOIN profile_controls pc ON pc.id = pcf.profile_control_id
          WHERE pcf.field_name LIKE 'parameter:%'
        ) ranked
        WHERE ranked.rn > 1
      )
    SQL

    say "#{count_duplicates} duplicate parameter row(s) remaining"
  end

  def down
    # Irreversible: the discarded rows held values that were already
    # unreachable, and there is nothing to restore them from.
    raise ActiveRecord::IrreversibleMigration
  end

  private

  def count_duplicates
    select_value(<<~SQL).to_i
      SELECT COALESCE(SUM(row_count - 1), 0)
      FROM (
        SELECT COUNT(*) AS row_count
        FROM profile_control_fields pcf
        JOIN profile_controls pc ON pc.id = pcf.profile_control_id
        WHERE pcf.field_name LIKE 'parameter:%'
        GROUP BY pc.profile_document_id, pcf.field_name
        HAVING COUNT(*) > 1
      ) groups
    SQL
  end
end
