# Compares a CDEF's controls against its source profile/baseline to
# identify coverage gaps. Returns covered, missing, and extra controls
# with a coverage percentage.
#
# Usage:
#   gap = CdefBaselineGapService.new(cdef_document).analyze
#   gap[:coverage_pct]  # => 85.7
#   gap[:missing]       # => ["ac-2", "ac-3"]
#
class CdefBaselineGapService
  def initialize(cdef_document)
    @cdef = cdef_document
    @profile = cdef_document.profile_document
  end

  def analyze
    return nil unless @profile&.resolved_catalog_json.present?

    baseline_ids = extract_baseline_control_ids
    cdef_ids = @cdef.cdef_controls.pluck(:control_id).to_set

    covered = (baseline_ids & cdef_ids).sort
    missing = (baseline_ids - cdef_ids).sort
    extra   = (cdef_ids - baseline_ids).sort

    {
      covered:      covered,
      missing:      missing,
      extra:        extra,
      total_baseline: baseline_ids.size,
      total_cdef:     cdef_ids.size,
      coverage_pct: baseline_ids.empty? ? 100.0 :
        (covered.size * 100.0 / baseline_ids.size).round(1)
    }
  end

  # Returns missing control details (id + title) for the gap UI.
  def missing_control_details
    gap = analyze
    return [] unless gap

    catalog_controls = build_catalog_control_map
    gap[:missing].map do |control_id|
      {
        id: control_id,
        title: catalog_controls[control_id] || control_id.upcase
      }
    end
  end

  private

  def extract_baseline_control_ids
    groups = @profile.resolved_catalog_json.dig("catalog", "groups") || []
    ids = Set.new
    groups.each do |group|
      (group["controls"] || []).each { |c| ids << c["id"] }
    end
    ids
  end

  def build_catalog_control_map
    groups = @profile.resolved_catalog_json.dig("catalog", "groups") || []
    map = {}
    groups.each do |group|
      (group["controls"] || []).each { |c| map[c["id"]] = c["title"] }
    end
    map
  end
end
