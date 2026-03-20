# Post-import quality check for catalog imports.
#
# Runs after CatalogImportService completes to detect missing or incomplete
# data that could cause issues downstream (profiles, SSPs, SARs).
#
# Returns structured warnings stored in metadata_extra["import_warnings"].
# Import always succeeds — warnings are advisory (soft failure).
#
class CatalogImportValidationService
  MAX_CONTROL_IDS = 50

  def initialize(catalog)
    @catalog = catalog
  end

  def validate
    warnings = []

    warnings.concat(check_missing_priorities)
    warnings.concat(check_missing_baselines)
    warnings.concat(check_missing_statements)
    warnings.concat(check_missing_assessment_objectives)
    warnings.concat(check_missing_parameters)
    warnings.concat(check_empty_families)

    summary = build_summary(warnings)

    { "import_warnings" => warnings, "import_warnings_summary" => summary }
  end

  private

  # Base controls only (e.g., "ac-1", "cm-6") — not enhancements ("ac-2.1") or sub-parts ("ac-1a").
  def base_controls
    @base_controls ||= @catalog.catalog_controls
      .joins(:control_family)
      .where("catalog_controls.control_id ~ ?", "^[a-z]+-[0-9]+$")
  end

  # Top-level = base + enhancements (e.g., "ac-1", "ac-2.1") — excludes sub-parts.
  def top_level_controls
    @top_level_controls ||= @catalog.catalog_controls
      .joins(:control_family)
      .top_level
  end

  def check_missing_priorities
    ids = base_controls.where(priority: [ nil, "" ]).pluck(:control_id)
    return [] if ids.empty?

    [ build_warning(
      category: "missing_priority",
      severity: "warning",
      message: "#{ids.size} base control#{'s' if ids.size != 1} missing priority designation (P1/P2/P3)",
      control_ids: ids
    ) ]
  end

  def check_missing_baselines
    ids = top_level_controls.where(baseline_impact: [ nil, "" ]).pluck(:control_id)
    return [] if ids.empty?

    [ build_warning(
      category: "missing_baseline",
      severity: "warning",
      message: "#{ids.size} control#{'s' if ids.size != 1} missing baseline impact level (LOW/MODERATE/HIGH)",
      control_ids: ids
    ) ]
  end

  def check_missing_statements
    # Controls where guidance_data is NULL, empty, or has no "statement" key
    ids = top_level_controls.where(
      "guidance_data IS NULL OR guidance_data = '{}' OR " \
      "NOT (guidance_data ? 'statement') OR " \
      "guidance_data->>'statement' IS NULL OR guidance_data->>'statement' = ''"
    ).pluck(:control_id)
    return [] if ids.empty?

    [ build_warning(
      category: "missing_statement",
      severity: "warning",
      message: "#{ids.size} control#{'s' if ids.size != 1} missing control statement text",
      control_ids: ids
    ) ]
  end

  def check_missing_assessment_objectives
    # Only check for Rev 5+ catalogs — Rev 4 uses different assessment format
    return [] unless rev5_or_later?

    ids = base_controls.where(
      "guidance_data IS NULL OR guidance_data = '{}' OR " \
      "NOT (guidance_data ? 'assessment_objective') OR " \
      "guidance_data->>'assessment_objective' IS NULL OR guidance_data->>'assessment_objective' = ''"
    ).pluck(:control_id)
    return [] if ids.empty?

    [ build_warning(
      category: "missing_assessment_objective",
      severity: "info",
      message: "#{ids.size} control#{'s' if ids.size != 1} missing assessment objective",
      control_ids: ids
    ) ]
  end

  def check_missing_parameters
    # Find controls whose statement text references {{ insert: param, ... }}
    # but have no params_data defined
    ids = top_level_controls.where(
      "(guidance_data->>'statement' LIKE '%{{ insert: param%' OR title LIKE '%{{ insert: param%') " \
      "AND (params_data IS NULL OR params_data = '[]' OR params_data = 'null' OR params_data::text = '')"
    ).pluck(:control_id)
    return [] if ids.empty?

    [ build_warning(
      category: "missing_parameters",
      severity: "info",
      message: "#{ids.size} control#{'s' if ids.size != 1} reference parameters but have none defined",
      control_ids: ids
    ) ]
  end

  def check_empty_families
    family_codes = @catalog.control_families
      .left_joins(:catalog_controls)
      .group("control_families.id")
      .having("COUNT(catalog_controls.id) = 0")
      .pluck(:code)
    return [] if family_codes.empty?

    [ build_warning(
      category: "empty_family",
      severity: "info",
      message: "#{family_codes.size} control famil#{'ies' if family_codes.size != 1}#{'y' if family_codes.size == 1} ha#{'ve' if family_codes.size != 1}#{'s' if family_codes.size == 1} no controls",
      control_ids: family_codes
    ) ]
  end

  def build_warning(category:, severity:, message:, control_ids:)
    truncated = control_ids.first(MAX_CONTROL_IDS)
    remaining = control_ids.size - truncated.size

    full_message = if remaining > 0
      "#{message} (showing first #{MAX_CONTROL_IDS} of #{control_ids.size})"
    else
      message
    end

    {
      "category" => category,
      "severity" => severity,
      "message" => full_message,
      "control_ids" => truncated,
      "count" => control_ids.size
    }
  end

  def build_summary(warnings)
    by_severity = warnings.group_by { |w| w["severity"] }.transform_values(&:size)
    {
      "total_warnings" => warnings.size,
      "total_affected" => warnings.sum { |w| w["count"] },
      "by_severity" => by_severity
    }
  end

  def rev5_or_later?
    version = @catalog.oscal_version.to_s
    name = @catalog.name.to_s.downcase

    # Check OSCAL version (1.1+ is Rev 5 era) or name contains "rev 5" / "rev5"
    version >= "1.1" || name.match?(/rev\.?\s*5/i)
  end
end
