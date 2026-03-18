class SspUpdateService
  def initialize(ssp_document)
    @document = ssp_document
  end

  def update_control(control_id, field_updates)
    control = apply_field_updates(control_id, field_updates)

    # OSCAL spec: regenerate root UUID when content changes
    @document.regenerate_oscal_uuid!

    control
  end

  def bulk_update(updates)
    ActiveRecord::Base.transaction do
      updates.each do |control_id, field_updates|
        apply_field_updates(control_id, field_updates)
      end
    end

    # Regenerate once after all updates
    @document.regenerate_oscal_uuid!
  end

  private

  def apply_field_updates(control_id, field_updates)
    control = @document.ssp_controls.find_by!(control_id: control_id)

    field_updates.each do |field_name, new_value|
      # Validate against the EDITABLE_FIELDS constant directly so that
      # find_or_initialize_by (which returns an unsaved record with editable=nil)
      # does not block writes to legitimately editable fields.
      fname = field_name.to_s
      unless SspControlField::EDITABLE_FIELDS.include?(fname)
        raise StandardError, "Field '#{fname}' is not editable"
      end

      field = control.ssp_control_fields.find_or_initialize_by(field_name: fname)
      field.field_value = new_value
      field.save!
    end

    control
  end
end
