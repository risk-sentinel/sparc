class SspUpdateService
  def initialize(ssp_document)
    @document = ssp_document
  end
  
  def update_control(control_id, field_updates)
    control = @document.ssp_controls.find_by!(control_id: control_id)
    
    field_updates.each do |field_name, new_value|
      field = control.ssp_control_fields.find_or_initialize_by(field_name: field_name)
      
      # Only update if field is editable
      if field.editable
        field.field_value = new_value
        field.save!
      else
        raise StandardError, "Field '#{field_name}' is not editable"
      end
    end
    
    control
  end
  
  def bulk_update(updates)
    ActiveRecord::Base.transaction do
      updates.each do |control_id, field_updates|
        update_control(control_id, field_updates)
      end
    end
  end
end