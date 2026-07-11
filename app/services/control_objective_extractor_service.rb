# Walks an OSCAL resolved catalog hash to extract assessment objectives
# (NIST 800-53A determination statements) for each control. NIST catalogs
# nest assessment-objective parts 2-3 levels deep
# (e.g. sr-1_obj -> sr-1_obj.a -> sr-1_obj.a-1) where only the leaf has
# the actual prose.
#
# Two entry points:
#
#   ControlObjectiveExtractorService.objectives_for_control(catalog_json, "ac-1")
#     => [{ objective_id:, label:, prose:, parent_objective_id:, row_order: }, ...]
#
#   ControlObjectiveExtractorService.new(sap_or_sar_document).backfill!
#     => bulk-inserts SapControlObjective / SarControlObjective records for
#        every control that has no objectives yet. Resolves the catalog via
#        document.profile_document_id -> document.ssp_document.profile_document_id.
#        If neither yields a catalog, flags the document with
#        import_metadata["objective_backfill_status"] = "needs_reassociation".
#
# The class methods are pure (no AR access) so they're safe to call from
# migrations and don't depend on model load order.
class ControlObjectiveExtractorService
  REASSOCIATION_FLAG = "objective_backfill_status".freeze
  REASSOCIATION_VALUE = "needs_reassociation".freeze

  def self.objectives_for_control(catalog_json, control_id)
    return [] if catalog_json.blank? || control_id.blank?

    target = control_id.to_s.downcase
    catalog = catalog_json.is_a?(Hash) ? (catalog_json["catalog"] || catalog_json) : {}
    control_node = find_control(catalog["groups"] || [], catalog["controls"] || [], target)
    return [] unless control_node

    objectives = []
    walk_parts(control_node["parts"] || [], objectives, parent_objective_id: nil)
    objectives.each_with_index { |o, i| o[:row_order] = i }
    objectives
  end

  def self.find_control(groups, controls, target)
    controls.each do |ctrl|
      return ctrl if ctrl["id"].to_s.downcase == target
      nested = find_control([], ctrl["controls"] || [], target)
      return nested if nested
    end
    groups.each do |group|
      hit = find_control(group["groups"] || [], group["controls"] || [], target)
      return hit if hit
    end
    nil
  end

  # Walks part subtrees collecting assessment-objective leaves. Always
  # recurses regardless of whether the current node has prose -- structural
  # wrapper parts (e.g. sr-1_obj with no prose, only nested parts) are
  # common in NIST catalogs.
  def self.walk_parts(parts, objectives, parent_objective_id:)
    parts.each do |part|
      next_parent = parent_objective_id

      if part["name"] == "assessment-objective"
        oid = part["id"].to_s
        if oid.present?
          label_prop = (part["props"] || []).find { |p| p["name"] == "label" }
          objectives << {
            objective_id:        oid,
            label:               label_prop && label_prop["value"].presence,
            prose:               part["prose"].to_s.strip.presence,
            parent_objective_id: parent_objective_id
          }
          next_parent = oid
        end
      end

      walk_parts(part["parts"] || [], objectives, parent_objective_id: next_parent)
    end
  end

  def initialize(document)
    @document = document
  end

  # Backfills objective records for all controls of the document. No-ops if
  # objectives already exist for a given control. Returns the number of
  # objective records inserted.
  def backfill!
    catalog = resolve_catalog
    if catalog.blank?
      flag_needs_reassociation
      return 0
    end

    rows = []
    now = Time.current
    controls_relation.includes(objective_assoc).find_each do |control|
      next if control.public_send(objective_assoc).any?

      self.class.objectives_for_control(catalog, control.control_id).each do |obj|
        rows << {
          fk_column => control.id,
          uuid:                SecureRandom.uuid,
          objective_id:        obj[:objective_id],
          label:               obj[:label],
          parent_objective_id: obj[:parent_objective_id],
          prose:               obj[:prose],
          status:              "pending",
          row_order:           obj[:row_order],
          created_at:          now,
          updated_at:          now
        }
      end
    end

    if rows.empty?
      flag_needs_reassociation
      return 0
    end

    objective_class.insert_all(rows)
    clear_reassociation_flag
    rows.size
  end

  private

  def resolve_catalog
    catalog = catalog_from_profile(@document.try(:profile_document_id))
    return catalog if catalog.present?

    ssp_id = @document.try(:ssp_document_id)
    return nil if ssp_id.blank?
    ssp = SspDocument.find_by(id: ssp_id)
    return nil if ssp.nil? || ssp.profile_document_id.blank?

    catalog_from_profile(ssp.profile_document_id)
  end

  def catalog_from_profile(profile_id)
    return nil if profile_id.blank?
    ProfileDocument.find_by(id: profile_id)&.resolved_catalog_json
  end

  def controls_relation
    case @document
    when SapDocument then @document.sap_controls
    when SarDocument then @document.sar_controls
    else nil # only SAP/SAR documents carry control objectives
    end
  end

  def objective_assoc
    sap? ? :sap_control_objectives : :sar_control_objectives
  end

  def fk_column
    sap? ? :sap_control_id : :sar_control_id
  end

  def objective_class
    sap? ? SapControlObjective : SarControlObjective
  end

  def sap?
    @document.is_a?(SapDocument)
  end

  def flag_needs_reassociation
    metadata = @document.import_metadata || {}
    return if metadata[REASSOCIATION_FLAG] == REASSOCIATION_VALUE
    @document.update_column(:import_metadata, metadata.merge(REASSOCIATION_FLAG => REASSOCIATION_VALUE))
  end

  def clear_reassociation_flag
    metadata = @document.import_metadata || {}
    return unless metadata.key?(REASSOCIATION_FLAG)
    @document.update_column(:import_metadata, metadata.except(REASSOCIATION_FLAG))
  end
end
