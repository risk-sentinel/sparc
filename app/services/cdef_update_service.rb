# Updates CDEF control fields and severity.
#
# Mirrors the SspUpdateService pattern — validates field editability,
# uses find_or_initialize_by for backward compatibility with existing
# CDEFs that don't have new field rows, and regenerates the document
# UUID per OSCAL spec on content changes.
#
# Usage:
#   service = CdefUpdateService.new(cdef_document)
#   service.update_control("ac-1", { "implementation_status" => "implemented" })
#   service.update_severity("ac-1", "high")
#
class CdefUpdateService
  def initialize(cdef_document)
    @document = cdef_document
  end

  # Update one or more editable fields on a single control.
  def update_control(control_id, field_updates)
    control = find_control!(control_id)
    apply_field_updates(control, field_updates)
    @document.regenerate_oscal_uuid!
    control
  end

  # Update severity on a control (column + field row for display consistency).
  def update_severity(control_id, new_severity)
    unless CdefControlField::SEVERITY_VALUES.include?(new_severity)
      raise ArgumentError, "Invalid severity '#{new_severity}'. Valid: #{CdefControlField::SEVERITY_VALUES.join(', ')}"
    end

    control = find_control!(control_id)
    control.update!(severity: new_severity)

    # Also update the display field row if it exists
    severity_field = control.cdef_control_fields.find_by(field_name: "severity")
    severity_field&.update!(field_value: new_severity)

    @document.regenerate_oscal_uuid!
    control
  end

  # Update a single field (convenience for inline editing).
  def update_field(control_id, field_name, field_value)
    if field_name == "severity"
      update_severity(control_id, field_value)
    else
      update_control(control_id, { field_name => field_value })
    end
  end

  # Bulk update multiple controls in a single transaction.
  def bulk_update(updates)
    ActiveRecord::Base.transaction do
      updates.each do |control_id, field_updates|
        field_updates = field_updates.to_h if field_updates.respond_to?(:to_h)
        severity = field_updates.delete("severity") || field_updates.delete(:severity)
        update_severity(control_id, severity) if severity.present?
        apply_field_updates(find_control!(control_id), field_updates) if field_updates.any?
      end
    end
    @document.regenerate_oscal_uuid!
  end

  private

  def find_control!(control_id)
    @document.cdef_controls.find_by!(control_id: control_id)
  rescue ActiveRecord::RecordNotFound
    raise ActiveRecord::RecordNotFound, "Control '#{control_id}' not found in CDEF '#{@document.name}'"
  end

  def apply_field_updates(control, field_updates)
    field_updates.each do |field_name, new_value|
      fname = field_name.to_s
      unless CdefControlField::EDITABLE_FIELDS.include?(fname)
        raise ArgumentError, "Field '#{fname}' is not editable. Editable fields: #{CdefControlField::EDITABLE_FIELDS.join(', ')}"
      end

      field = control.cdef_control_fields.find_or_initialize_by(field_name: fname)
      field.field_value = new_value
      field.save!
    end
  end
end
