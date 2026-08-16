# #942 — move imported selection CHOICES out of the field that holds the
# operator's chosen VALUE.
#
# Deferred (see app/lib/deferred_data_migration.rb): the schema_migrations row is
# recorded at db:migrate time and the body runs post-boot.
#
# ── What went wrong ────────────────────────────────────────────────────────
#
# `ProfileJsonParserService` wrote a select parameter's available choices to
# `parameter:<id>`, which is not a list of options — it is the answer. That one
# field is read as the chosen value by `OscalProfileExportService` (emitted as
# OSCAL `set-parameters`), by `OscalResolvedProfileCatalogService` (used to
# resolve the baseline) and by `BaselineReviewService` (counted as an operator
# customization). So an imported profile looked as though every selection had
# already been answered, and the answer was the list of options — raw
# `{{ insert: param, … }}` markup included, which then travelled into exported
# OSCAL as though someone had chosen it.
#
# The importer now writes `parameter_choices:<id>`. This moves the rows already
# stored.
#
# ── Why the marker is safe to key on ───────────────────────────────────────
#
# Only values still carrying `{{ insert: param` are moved. That is template
# markup from the catalog: it is not something an operator types, and a
# parameter value containing it is not a value anyone chose. A joined choice
# list WITHOUT markup is indistinguishable from a legitimate multi-select answer
# — "VPN, tunneled, direct" is exactly what a correct one-or-more answer looks
# like — so those are left alone. Guessing there would silently discard real
# answers, which is worse than leaving a cosmetic duplicate.
#
# ── Idempotency and resume-from-partial ────────────────────────────────────
#
#   * The selection is the work: a row is matched only while it still has the
#     `parameter:` name and the markup. Once renamed it no longer matches, so a
#     re-run after a partial failure converges and a second run is a no-op.
#   * No cursor and no ordering assumption, so an interrupted run resumes from
#     wherever it stopped.
#
# ── What it deliberately does NOT do ───────────────────────────────────────
#
# It never deletes. The value is renamed, not dropped, so the choices remain
# available and an operator who wants to inspect what was imported still can. A
# migration that silently removed data on the strength of an inference would be
# the wrong trade even when the inference is sound.
class MoveChoiceMarkupOutOfParameterValues < ActiveRecord::Migration[8.1]
  include DeferredDataMigration
  data_migration_version "1.0.0"

  # The catalog's own template markup. See the note above on why this, and only
  # this, is safe to key on.
  MARKER = "{{ insert: param"

  def up
    defer_data_migration do
      move_choice_markup
    end
  end

  # Deliberately empty. Moving these back would restore choices to the field
  # read as the chosen value, which is the defect itself.
  def down
    # intentionally empty
  end

  def move_choice_markup
    moved = 0

    mis_stored.find_each(batch_size: 500) do |field|
      param_id = field.field_name.delete_prefix("parameter:")
      target   = "parameter_choices:#{param_id}"

      # A correctly-imported row may already exist alongside the bad one, in
      # which case the bad one is redundant rather than worth preserving under a
      # name that is taken.
      if ProfileControlField.where(profile_control_id: field.profile_control_id,
                                   field_name: target).exists?
        field.update_columns(field_name: "#{target}:superseded")
      else
        field.update_columns(field_name: target)
      end

      moved += 1
    end

    say "parameter choices: #{moved} field(s) carrying catalog template markup " \
        "moved out of the chosen-value field and into parameter_choices:"

    # Returned so the runner records it as `records_processed`.
    moved
  end

  private

  def mis_stored
    ProfileControlField
      .where("field_name LIKE ?", "parameter:%")
      .where.not("field_name LIKE ?", "parameter_label:%")
      .where("field_value LIKE ?", "%#{MARKER}%")
  end
end
