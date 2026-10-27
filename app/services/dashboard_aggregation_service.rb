# #1312 — implementation status across every SSP, counted per statement item
# that takes a response (each item records its own status now).
class DashboardAggregationService
  SSP_STATUS_ORDER = SspResponseProgress::ItemSummary::LABEL_ORDER

  # Aggregate item implementation status counts across ALL SSP documents,
  # grouped by NIST control family (e.g. "AC", "AU", "IA").
  #
  # Returns [heatmap_data, families, ordered_statuses] matching the
  # contract expected by the shared _heatmap.html.erb partial.
  def call
    data = {}
    cache = {}

    SspDocument.find_each do |document|
      SspResponseProgress.for(document, required_cache: cache).items.parts.each do |item|
        family = item.control_id.to_s.split("-").first.to_s.upcase
        next if family.blank?

        status = SspResponseProgress::ItemSummary.label(item.implementation_status)
        data[family] ||= {}
        data[family][status] = data[family].fetch(status, 0) + 1
      end
    end

    families = data.keys.sort
    all_statuses = data.values.flat_map(&:keys).uniq
    ordered = SSP_STATUS_ORDER.select { |s| all_statuses.include?(s) }
    ordered += (all_statuses - SSP_STATUS_ORDER).sort

    [ data, families, ordered ]
  end
end
