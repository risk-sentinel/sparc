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
    statement_id_map = build_statement_id_map(activities)
    catalog_json = matched_catalog

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

      build_objectives_for(sap_control, control_id, statement_id_map, catalog_json)
    end

    # If we auto-matched a source via include-all fallback, copy its back-matter
    copy_back_matter_from(@matched_source) if @matched_source
  end

  # Create SapControlObjective records for the given control. Two sources:
  #
  # 1. statement-ids found in the SAP's local-definitions activities --
  #    explicit objective-level scoping in the OSCAL document itself.
  # 2. The linked profile's resolved_catalog_json -- when the SAP doesn't
  #    name objectives explicitly, we still want all of the catalog's
  #    determination statements available so an assessor can edit them.
  #
  # When both sources exist, the catalog walk wins because it has prose
  # and labels; statement-ids without a catalog hit get sparse records
  # (objective_id only, no prose/label) flagged for later enrichment.
  def build_objectives_for(sap_control, control_id, statement_id_map, catalog_json)
    catalog_objectives = if catalog_json.present?
      ControlObjectiveExtractorService.objectives_for_control(catalog_json, control_id)
    else
      []
    end

    statement_ids = statement_id_map[control_id] || []
    by_id = catalog_objectives.index_by { |o| o[:objective_id] }

    rows = if catalog_objectives.any?
      catalog_objectives
    elsif statement_ids.any?
      # No catalog -- create skeletal records for the IDs we saw
      statement_ids.each_with_index.map do |sid, idx|
        { objective_id: sid, label: nil, prose: nil, parent_objective_id: nil, row_order: idx }
      end
    else
      []
    end

    return if rows.empty?

    now = Time.current
    sap_control.sap_control_objectives.insert_all(
      rows.map do |obj|
        {
          sap_control_id:      sap_control.id,
          uuid:                SecureRandom.uuid,
          objective_id:        obj[:objective_id],
          label:               obj[:label] || by_id.dig(obj[:objective_id], :label),
          parent_objective_id: obj[:parent_objective_id],
          prose:               obj[:prose] || by_id.dig(obj[:objective_id], :prose),
          status:              "pending",
          row_order:           obj[:row_order],
          created_at:          now,
          updated_at:          now
        }
      end
    )
  end

  # Catalog hash from the matched profile/SSP, if any. Used by build_objectives_for
  # to enrich objective records with prose/label.
  def matched_catalog
    return nil if @matched_source.blank?
    if @matched_source.respond_to?(:resolved_catalog_json)
      @matched_source.resolved_catalog_json
    elsif @matched_source.respond_to?(:profile_document_id) && @matched_source.profile_document_id.present?
      ProfileDocument.find_by(id: @matched_source.profile_document_id)&.resolved_catalog_json
    end
  end

  # Copy back-matter resources from an auto-matched source profile/SSP
  # to this SAP. Reads from BOTH back_matter_resources records (managed)
  # AND import_metadata["back_matter"] (imported from OSCAL JSON).
  # Skips UUIDs already present.
  def copy_back_matter_from(source)
    existing_uuids = @document.back_matter_resources.pluck(:uuid).to_set

    # 1. Copy managed BackMatterResource records
    if source.respond_to?(:back_matter_resources)
      source.back_matter_resources.each do |src_bm|
        next if existing_uuids.include?(src_bm.uuid)
        @document.back_matter_resources.create!(
          uuid:          src_bm.uuid,
          title:         src_bm.title,
          description:   src_bm.description,
          rel:           src_bm.rel,
          media_type:    src_bm.media_type,
          href:          src_bm.href,
          source:        "imported",
          resource_data: src_bm.resource_data
        )
        existing_uuids << src_bm.uuid
      end
    end

    # 2. Copy imported back-matter from import_metadata (OSCAL JSON hashes)
    imported = source.respond_to?(:import_metadata) ? (source.import_metadata&.dig("back_matter") || []) : []
    imported.each do |bm_hash|
      uuid = bm_hash["uuid"]
      next if uuid.blank? || existing_uuids.include?(uuid)
      rlink = (bm_hash["rlinks"] || []).first || {}
      @document.back_matter_resources.create!(
        uuid:          uuid,
        title:         bm_hash["title"] || "Imported Resource",
        description:   bm_hash["description"],
        rel:           "reference",
        media_type:    rlink["media-type"],
        href:          rlink["href"],
        source:        "imported",
        resource_data: bm_hash.except("uuid", "title", "description", "rlinks")
      )
      existing_uuids << uuid
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn("Skipping invalid imported back-matter resource #{uuid}: #{e.message}")
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

      # include-all: empty hash {} means "all controls" per OSCAL spec.
      # Use key? not .present? because Rails treats empty hash as blank.
      if sel.key?("include-all") && ids.empty?
        ids = resolve_all_controls(plan, sel)
      end
    end
    ids.uniq
  end

  # When the SAP uses include-all, resolve control IDs by trying:
  # 1. Linked profile (sap.profile_document_id)
  # 2. Linked SSP's profile or SSP controls (sap.ssp_document_id)
  # 3. Baseline hint from selection description, SAP metadata title, or
  #    terms-and-conditions prose (LOW/MODERATE/HIGH)
  # 4. Most recent published profile (any baseline)
  # 5. Most recent control catalog
  def resolve_all_controls(plan, selection = {})
    # Try linked profile first
    if @document.profile_document_id.present?
      profile = ProfileDocument.find_by(id: @document.profile_document_id)
      ids = profile_control_ids(profile)
      if ids.any?
        @matched_source = profile
        return ids
      end
    end

    # Try linked SSP's profile or controls
    if @document.ssp_document_id.present?
      ssp = SspDocument.find_by(id: @document.ssp_document_id)
      if ssp&.profile_document_id.present?
        profile = ProfileDocument.find_by(id: ssp.profile_document_id)
        ids = profile_control_ids(profile)
        if ids.any?
          @matched_source = profile
          return ids
        end
      end
      ctrl_ids = ssp&.ssp_controls&.where&.not(control_id: nil)&.pluck(:control_id)&.uniq
      if ctrl_ids&.any?
        @matched_source = ssp
        return ctrl_ids
      end
    end

    # Baseline hint from multiple sources (selection description, SAP title, terms-and-conditions)
    baseline_hint = detect_baseline_hint(plan, selection)
    if baseline_hint
      profile = ProfileDocument.where(lifecycle_status: "published")
                               .where("LOWER(baseline_level) = ?", baseline_hint)
                               .order(updated_at: :desc).first
      ids = profile_control_ids(profile)
      if ids.any?
        @matched_source = profile
        return ids
      end

      # Try draft profiles too
      profile = ProfileDocument.where("LOWER(baseline_level) = ?", baseline_hint)
                               .order(updated_at: :desc).first
      ids = profile_control_ids(profile)
      if ids.any?
        @matched_source = profile
        return ids
      end
    end

    # Most recent published profile (any baseline)
    profile = ProfileDocument.where(lifecycle_status: "published")
                             .order(updated_at: :desc).first
    ids = profile_control_ids(profile)
    if ids.any?
      @matched_source = profile
      return ids
    end

    # Any profile (draft or published)
    profile = ProfileDocument.order(updated_at: :desc).first
    ids = profile_control_ids(profile)
    if ids.any?
      @matched_source = profile
      return ids
    end

    # Last resort: most recent control catalog (NIST 800-53 etc.)
    catalog = ControlCatalog.order(updated_at: :desc).first
    if catalog && catalog.catalog_controls.any?
      @matched_source = catalog
      return catalog.catalog_controls.pluck(:control_id)
    end

    []
  end

  def profile_control_ids(profile)
    return [] unless profile
    profile.profile_controls.pluck(:control_id)
  end

  # Detect baseline hint from multiple OSCAL sources in priority order:
  # 1. control-selection description ("HIGH baseline")
  # 2. SAP metadata title ("HIGH Impact Assessment Plan")
  # 3. terms-and-conditions prose ("NIST SP 800-53 Rev 5 HIGH Impact Baseline")
  def detect_baseline_hint(plan, selection)
    sources = []
    sources << selection["description"].to_s
    sources << plan.dig("metadata", "title").to_s
    (plan.dig("terms-and-conditions", "parts") || []).each do |part|
      sources << part["prose"].to_s
    end

    text = sources.compact.join(" ").downcase
    return "high"     if text =~ /high\s+(baseline|impact)/
    return "moderate" if text =~ /moderate\s+(baseline|impact)/
    return "low"      if text =~ /low\s+(baseline|impact)/
    nil
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
      # statement_ids is a hash control_id => [objective_id, ...] so we
      # can later attribute objectives to the right control even when an
      # activity targets multiple controls.
      statement_ids = Hash.new { |h, k| h[k] = [] }
      (related["control-selections"] || []).each do |sel|
        (sel["include-controls"] || []).each do |ic|
          cid = ic["control-id"]
          control_ids << cid
          (ic["statement-ids"] || []).each { |sid| statement_ids[cid] << sid }
        end
      end

      steps = activity["steps"] || []
      test_case = steps.map { |s| s["remarks"] }.compact.first

      {
        method: method,
        description: activity["description"],
        control_ids: control_ids,
        statement_ids: statement_ids,
        test_case: test_case
      }
    end
  end

  # Aggregate statement-ids from all activities into a single per-control
  # map: { "ac-1" => ["ac-1_obj.a-1", "ac-1_obj.a-2", ...], ... }
  def build_statement_id_map(activities)
    accumulator = Hash.new { |h, k| h[k] = [] }
    activities.each do |activity|
      (activity[:statement_ids] || {}).each do |cid, sids|
        accumulator[cid].concat(sids)
      end
    end
    accumulator.transform_values(&:uniq)
  end

  # Build map of control_id => comma-separated methods (e.g. "examine,interview")
  # so multi-method controls are preserved on import.
  def build_method_map(activities)
    accumulator = Hash.new { |h, k| h[k] = [] }
    activities.each do |activity|
      m = activity[:method].to_s.downcase.strip
      next if m.blank?
      (activity[:control_ids] || []).each { |cid| accumulator[cid] << m }
    end
    accumulator.transform_values { |methods| methods.uniq.join(",") }
  end
end
