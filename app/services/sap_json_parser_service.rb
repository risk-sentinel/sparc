# Parses an OSCAL Assessment Plan JSON file into a SapDocument with
# SapControls and SapControlFields.
#
# Handles the OSCAL assessment-plan model structure:
#   assessment-plan → reviewed-controls → control-selections → include-controls
#   assessment-plan → local-definitions → activities (methods and steps)
#
# Usage:
#   SapJsonParserService.new(sap_document, "/tmp/sap_abc.json").parse
#
class SapJsonParserService
  include ProgressTrackable

  def initialize(document, file_path)
    @document = document
    @file_path = file_path
  end

  def parse
    update_processing_stage!(:reading_file)
    raw = JSON.parse(File.read(@file_path))
    plan = raw["assessment-plan"] || raw

    update_processing_stage!(:creating_records)
    parse_metadata(plan)
    parse_controls(plan)

    @document.update!(status: "completed")
  rescue JSON::ParserError => e
    @document.update!(status: "failed", error_message: "Invalid JSON: #{e.message}")
    raise
  rescue StandardError => e
    @document.update!(status: "failed", error_message: e.message)
    raise
  end

  private

  def parse_metadata(plan)
    metadata = plan["metadata"] || {}
    attrs = {}

    attrs[:description] = metadata["title"] if @document.description.blank? && metadata["title"].present?
    attrs[:oscal_version] = metadata["oscal-version"] if metadata["oscal-version"].present?
    attrs[:sap_version] = metadata["version"] if metadata["version"].present?

    props = metadata["props"] || []
    type_prop = props.find { |p| p["name"] == "assessment-type" }
    attrs[:assessment_type] = type_prop["value"] if type_prop

    # Preserve full OSCAL metadata (roles, parties, revisions, etc.)
    attrs[:metadata_extra] = metadata.except("title", "version", "oscal-version", "last-modified")

    attrs[:import_metadata] = {
      "uuid"        => plan["uuid"],
      "back_matter" => plan.dig("back-matter", "resources")
    }.compact

    @document.update!(attrs.compact)
    @document.assign_oscal_uuid!(plan["uuid"])
  end

  def parse_controls(plan)
    control_ids = extract_control_ids(plan)
    activities = extract_activities(plan)
    method_map = build_method_map(activities)

    control_ids.each_with_index do |control_id, idx|
      denormalized_id = control_id.upcase.gsub(".", " (").then { |s| s.include?("(") ? "#{s})" : s }
                                   .gsub("-", "-")

      sap_control = @document.sap_controls.create!(
        control_id: denormalized_id,
        assessment_method: method_map[control_id],
        assessment_status: "planned",
        row_order: idx
      )

      activity = activities.find { |a| a[:control_ids]&.include?(control_id) }
      if activity
        sap_control.update!(
          objective: activity[:description],
          test_case: activity[:test_case]
        )
      end
    end
  end

  def extract_control_ids(plan)
    reviewed = plan["reviewed-controls"] || {}
    selections = reviewed["control-selections"] || []

    ids = []
    selections.each do |sel|
      # Explicit control list
      (sel["include-controls"] || []).each do |ic|
        ids << ic["control-id"] if ic["control-id"].present?
      end

      # include-all: resolve from linked profile or catalog
      if sel["include-all"].present? && ids.empty?
        ids = resolve_all_controls(plan, sel)
      end
    end
    ids.uniq
  end

  # When the SAP uses include-all, resolve control IDs by trying:
  # 1. Linked profile (sap.profile_document_id)
  # 2. Linked SSP's profile or SSP controls (sap.ssp_document_id)
  # 3. Baseline hint from the selection description (LOW/MODERATE/HIGH)
  # 4. Most recent published profile (any baseline)
  def resolve_all_controls(plan, selection = {})
    # Try linked profile first
    if @document.profile_document_id.present?
      profile = ProfileDocument.find_by(id: @document.profile_document_id)
      return profile.profile_controls.pluck(:control_id) if profile&.profile_controls&.any?
    end

    # Try linked SSP's profile or controls
    if @document.ssp_document_id.present?
      ssp = SspDocument.find_by(id: @document.ssp_document_id)
      if ssp&.profile_document_id.present?
        profile = ProfileDocument.find_by(id: ssp.profile_document_id)
        return profile.profile_controls.pluck(:control_id) if profile&.profile_controls&.any?
      end
      ctrl_ids = ssp&.ssp_controls&.where&.not(control_id: nil)&.pluck(:control_id)&.uniq
      return ctrl_ids if ctrl_ids&.any?
    end

    # Baseline hint from selection description (e.g., "NIST SP 800-53 Rev 5 HIGH baseline")
    description = selection["description"].to_s.downcase
    baseline_hint = case description
    when /high\s+baseline|high\s+impact/ then "high"
    when /moderate\s+baseline|moderate\s+impact/ then "moderate"
    when /low\s+baseline|low\s+impact/ then "low"
    end

    if baseline_hint
      profile = ProfileDocument.where(lifecycle_status: "published")
                               .where("LOWER(baseline_level) = ?", baseline_hint)
                               .order(updated_at: :desc).first
      return profile.profile_controls.pluck(:control_id) if profile&.profile_controls&.any?
    end

    # Last resort: most recent published profile
    profile = ProfileDocument.where(lifecycle_status: "published")
                             .order(updated_at: :desc).first
    return profile.profile_controls.pluck(:control_id) if profile&.profile_controls&.any?

    []
  end

  def extract_activities(plan)
    local_defs = plan["local-definitions"] || {}
    raw_activities = local_defs["activities"] || []

    raw_activities.map do |activity|
      props = activity["props"] || []
      method_prop = props.find { |p| p["name"] == "method" }
      method = method_prop&.dig("value")&.downcase

      related = activity["related-controls"] || {}
      control_ids = []
      (related["control-selections"] || []).each do |sel|
        (sel["include-controls"] || []).each do |ic|
          control_ids << ic["control-id"]
        end
      end

      steps = activity["steps"] || []
      test_case = steps.map { |s| s["remarks"] }.compact.first

      {
        method: method,
        description: activity["description"],
        control_ids: control_ids,
        test_case: test_case
      }
    end
  end

  def build_method_map(activities)
    map = {}
    activities.each do |activity|
      (activity[:control_ids] || []).each do |cid|
        map[cid] ||= activity[:method]
      end
    end
    map
  end
end
