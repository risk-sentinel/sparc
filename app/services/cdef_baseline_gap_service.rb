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
  # #1089 — a CDEF serves several baselines; `profile:` names the one to
  # compare against, and must be one the CDEF is linked to. Without it, the
  # CDEF's own (mirrored) baseline.
  def initialize(cdef_document, profile: nil)
    @cdef = cdef_document
    @profile = profile || cdef_document.profile_document
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

  # 1.18.0-rf #1300 — coverage of many CDEFs against one baseline, for a list:
  # the same comparison as #analyze (the baseline's control ids through
  # ResolvedCatalog against each CDEF's control ids), in one query.
  # Returns { cdef_id => { covered:, total:, pct: } }; {} when the baseline
  # has not been resolved.
  def self.coverage_for(document_ids, profile)
    return {} unless profile&.resolved_catalog_json.present?

    baseline = baseline_control_ids(profile)
    ids = Array(document_ids).compact.uniq
    by_doc = CdefControl.where(cdef_document_id: ids).pluck(:cdef_document_id, :control_id)
                        .group_by(&:first).transform_values { |rows| rows.map(&:last).to_set }
    ids.index_with do |id|
      covered = (baseline & by_doc.fetch(id, Set.new)).size
      { covered: covered, total: baseline.size,
        pct: baseline.empty? ? 100.0 : (covered * 100.0 / baseline.size).round(1) }
    end
  end

  # A baseline's control ids, cached per version of the baseline: resolving
  # the catalog is the expensive part, and a list asks for it on every page.
  def self.baseline_control_ids(profile)
    Rails.cache.fetch([ "cdef-baseline-control-ids", profile.id, profile.updated_at.to_f ]) do
      ResolvedCatalog.wrap(profile.resolved_catalog_json).control_ids.to_a
    end.to_set
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

  # #999 — through ResolvedCatalog, so a nested enhancement counts as covered
  # rather than reading as a gap the CDEF was never asked to fill.
  def extract_baseline_control_ids
    self.class.baseline_control_ids(@profile)
  end

  def build_catalog_control_map
    map = {}
    ResolvedCatalog.wrap(@profile.resolved_catalog_json).each_control do |control, _group|
      map[control["id"]] = control["title"]
    end
    map
  end
end
