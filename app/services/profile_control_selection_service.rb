# frozen_string_literal: true

# Select/deselect controls on a ProfileDocument (baseline) from its linked
# control catalog. Extracted from ProfileDocumentsController#update_controls so
# the web UI and the Api::V1 endpoint share one write path (api-first rule).
#
# Given the desired set of control ids, it diffs against the profile's current
# profile_controls, deletes the removed ones, and creates the added ones from the
# catalog's catalog_controls (carrying title / family / priority / row order and
# seeding parameter fields). Idempotent: re-applying the same set is a no-op.
#
# NIST 800-53: CM-3/CM-4 (baseline change control), AU-12 (audit — caller).
class ProfileControlSelectionService
  class SelectionError < StandardError; end

  Result = Struct.new(:added, :removed, keyword_init: true)

  def initialize(profile_document)
    @profile = profile_document
  end

  # @param control_ids [Array<String>] the desired complete set of control ids
  # @return [Result] counts of added / removed controls
  def update(control_ids)
    unless @profile.control_catalog
      raise SelectionError, "Cannot update controls: no source catalog linked to this profile."
    end

    desired  = Array(control_ids).map(&:to_s).reject(&:blank?).to_set
    existing = @profile.profile_controls.pluck(:control_id).to_set
    to_add    = desired - existing
    to_remove = existing - desired

    ActiveRecord::Base.transaction do
      if to_remove.any?
        @profile.profile_controls
                .where(control_id: to_remove.flat_map { ControlId.forms(_1) })
                .delete_all
      end
      add_controls(to_add.to_a) if to_add.any?
    end

    @profile.regenerate_oscal_uuid!
    Result.new(added: to_add.size, removed: to_remove.size)
  end

  private

  def add_controls(control_ids)
    catalog_controls = @profile.control_catalog.catalog_controls
                               .where(control_id: control_ids.flat_map { ControlId.forms(_1) })
                               .includes(:control_family)
    max_order = @profile.profile_controls.maximum(:row_order) || 0

    catalog_controls.each_with_index do |cc, idx|
      pc = @profile.profile_controls.create!(
        control_id: cc.control_id,
        title: cc.title,
        control_family: cc.control_family&.code || cc.family_code,
        priority: ProfilePriorityAssignmentService.assign(cc),
        row_order: max_order + idx + 1
      )

      cc.effective_params_list.each do |param|
        label = param["label"].to_s
        pc.profile_control_fields.create!(field_name: "parameter:#{param['id']}", field_value: label)
        pc.profile_control_fields.create!(field_name: "parameter_label:#{param['id']}", field_value: label)
      end
    end
  end
end
