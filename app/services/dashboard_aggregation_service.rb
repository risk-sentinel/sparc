class DashboardAggregationService
  SSP_STATUS_ORDER = [
    "Implemented", "Deferred", "Not Applicable", "Will Not Implement",
    "Partially Implemented", "Planned", "Alternative Implementation", "Not Implemented"
  ].freeze

  # Aggregate implementation status counts across ALL SSP documents,
  # grouped by NIST control family (e.g. "AC", "AU", "IA").
  #
  # Returns [heatmap_data, families, ordered_statuses] matching the
  # contract expected by the shared _heatmap.html.erb partial.
  def call
    data = {}

    SspControl
      .joins(:ssp_document)
      .where.not(control_id: [nil, ""])
      .includes(:ssp_control_fields)
      .find_each(batch_size: 1000) do |control|
        family = control.control_id.to_s.split("-").first.upcase
        next if family.blank?

        status_field = control.ssp_control_fields.find { |f| f.field_name == "status" }
        status = status_field&.field_value.presence || "(Unknown)"

        data[family] ||= {}
        data[family][status] ||= 0
        data[family][status] += 1
      end

    families = data.keys.sort
    all_statuses = data.values.flat_map(&:keys).uniq
    ordered = SSP_STATUS_ORDER.select { |s| all_statuses.include?(s) }
    ordered += (all_statuses - SSP_STATUS_ORDER).sort

    [data, families, ordered]
  end
end
