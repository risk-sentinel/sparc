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

  # The control's Edit form answers each part that needs a response in one
  # Save (ssp_documents/_part_responses). Each changed part goes through
  # SspControlStatement#apply_author_edit, as a single row's Save and the API
  # do, so CDEF-filled text a person rewrites is marked theirs. A box left as
  # it was, including an empty one for an unanswered part, changes nothing.
  #
  # @param control [SspControl]
  # @param statements [Hash] statement id => { "implementation_prose" => text }
  # @return [Array<SspControlStatement>] the parts saved
  def update_statements(control, statements)
    return [] if statements.blank?

    by_id = control.ssp_control_statements.index_by { |s| s.id.to_s }
    saved = []
    ActiveRecord::Base.transaction do
      statements.to_h.each do |id, attrs|
        statement = by_id[id.to_s] or raise ActiveRecord::RecordNotFound, "Statement #{id} is not part of #{control.control_id}"
        prose = attrs.to_h.stringify_keys["implementation_prose"].to_s.strip.presence
        next if prose == statement.implementation_prose.to_s.strip.presence

        unless statement.apply_author_edit("implementation_prose" => prose)
          raise ActiveRecord::RecordInvalid, statement
        end
        saved << statement
      end
    end
    @document.regenerate_oscal_uuid! if saved.any?
    saved
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
