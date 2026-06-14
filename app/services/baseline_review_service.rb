# frozen_string_literal: true

# #633 — Baseline review for a ProfileDocument. Surfaces, for the reviewer's
# sign-off, how the profile's control SELECTION and ODP/parameter VALUES compare
# to the expected baseline (the source catalog's controls flagged for the
# profile's baseline_level):
#
#   * missing  — controls expected at this baseline but NOT selected
#   * extra    — controls selected but NOT in the expected baseline
#   * odp      — how many set-parameter (ODP) values have been customized vs the
#                catalog default label
#
# Read-only and side-effect free; the approval itself (DocumentApprovalService)
# is the reviewer's sign-off. Mirrors the baseline_impact matching used by
# ControlCatalogsController#baseline_controls.
#
# NIST: aligns with RMF SP 800-37 Task S-6 — the AO approves the selected set of
# controls and their parameter values before lock-in.
class BaselineReviewService
  ABBREV = { "LOW" => "L", "MODERATE" => "M", "HIGH" => "H" }.freeze

  Result = Struct.new(:level, :expected_count, :selected_count, :missing, :extra,
                      :odp_customized_count, :odp_total_count, keyword_init: true) do
    # True when the selection exactly matches the expected baseline.
    def selection_matches_baseline? = missing.empty? && extra.empty?

    def to_h
      {
        baseline_level:        level,
        expected_count:        expected_count,
        selected_count:        selected_count,
        missing_controls:      missing,
        extra_controls:        extra,
        selection_matches_baseline: selection_matches_baseline?,
        odp_customized_count:  odp_customized_count,
        odp_total_count:       odp_total_count
      }
    end
  end

  def initialize(profile)
    @profile = profile
  end

  def review
    level    = @profile.baseline_level.to_s.strip.upcase
    expected = expected_control_ids(level)
    selected = @profile.profile_controls.pluck(:control_id).compact.map(&:to_s).to_set
    expected_set = expected.to_set

    customized, total = odp_stats

    Result.new(
      level:                level.presence,
      expected_count:       expected.size,
      selected_count:       selected.size,
      missing:              (expected_set - selected).to_a.sort,
      extra:                (selected - expected_set).to_a.sort,
      odp_customized_count: customized,
      odp_total_count:      total
    )
  end

  private

  # Controls in the source catalog flagged for this baseline level. Matches both
  # full ("MODERATE") and abbreviated ("M") baseline_impact encodings, same as
  # ControlCatalogsController#baseline_controls.
  def expected_control_ids(level)
    catalog = @profile.control_catalog
    return [] if catalog.nil? || level.blank?

    scope  = catalog.catalog_controls
    abbrev = ABBREV[level]
    rows = if abbrev
      scope.where("LOWER(baseline_impact) LIKE :full OR baseline_impact LIKE :abbrev",
                  full: "%#{level.downcase}%", abbrev: "%#{abbrev}%")
    else
      scope.where("LOWER(baseline_impact) LIKE ?", "%#{level.downcase}%")
    end
    rows.pluck(:control_id).compact.map(&:to_s)
  end

  # ODP/parameter customization: a "parameter:<id>" value counts as customized
  # when it is present and differs from its "parameter_label:<id>" catalog
  # default. Mirrors the publish_check parameter-customization signal.
  def odp_stats
    fields = ProfileControlField
             .joins(:profile_control)
             .where(profile_controls: { profile_document_id: @profile.id })
             .where("field_name LIKE 'parameter:%' OR field_name LIKE 'parameter_label:%'")
             .pluck(:field_name, :field_value)

    values = {}
    labels = {}
    fields.each do |name, val|
      if name.start_with?("parameter:")
        values[name.delete_prefix("parameter:")] = val
      elsif name.start_with?("parameter_label:")
        labels[name.delete_prefix("parameter_label:")] = val
      end
    end

    customized = values.count { |id, v| v.present? && v != labels[id] }
    [ customized, values.size ]
  end
end
