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

  # The control's Edit form answers every item that takes a response in one
  # Save (ssp_documents/_part_responses): its text, remarks, implementation
  # status, origination, responsible roles and expected completion (#1312).
  # Each changed item goes through SspControlStatement#apply_author_edit, as the
  # API does, so CDEF-filled text a person rewrites is marked theirs. An item
  # left as it was changes nothing.
  #
  # @param control [SspControl]
  # @param statements [Hash] statement id => attributes, any of ITEM_KEYS
  # @return [Array<SspControlStatement>] the items saved
  def update_statements(control, statements)
    return [] if statements.blank?

    by_id = control.ssp_control_statements.index_by { |s| s.id.to_s }
    saved = []
    ActiveRecord::Base.transaction do
      statements.to_h.each do |id, attrs|
        statement = by_id[id.to_s] or raise ActiveRecord::RecordNotFound, "Statement #{id} is not part of #{control.control_id}"
        changes = item_changes(statement, attrs.to_h.stringify_keys)
        next if changes.empty?

        unless statement.apply_author_edit(changes)
          raise ActiveRecord::RecordInvalid, statement
        end
        saved << statement
      end
    end
    @document.regenerate_oscal_uuid! if saved.any?
    saved
  end

  # What an item's form posts. `responsible_role_ids` are role ids the document
  # declares, stored in OSCAL's shape.
  ITEM_KEYS = %w[implementation_prose remarks implementation_status control_origination
                 responsible_role_ids expected_completion].freeze

  # Raised for a value the form cannot have offered: a role the document does
  # not declare, or a date that is not one.
  class InvalidItem < StandardError; end

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

  # The attributes that differ from what the item holds, normalised as the
  # model stores them.
  def item_changes(statement, attrs)
    wanted = {}
    %w[implementation_prose remarks].each do |key|
      wanted[key] = attrs[key].to_s.strip.presence if attrs.key?(key)
    end
    wanted["implementation_status"] = attrs["implementation_status"].presence if attrs.key?("implementation_status")
    wanted["control_origination"] = Array(attrs["control_origination"]).compact_blank if attrs.key?("control_origination")
    wanted["responsible_roles_data"] = role_refs(attrs["responsible_role_ids"]) if attrs.key?("responsible_role_ids")
    wanted["expected_completion"] = completion_date(attrs["expected_completion"]) if attrs.key?("expected_completion")

    wanted.reject { |key, value| same?(statement, key, value) }
  end

  def same?(statement, key, value)
    current = statement.public_send(key)
    case key
    when "control_origination" then Array(current).sort == value.sort
    when "responsible_roles_data" then Array(current) == value
    when "implementation_prose", "remarks" then current.to_s.strip.presence == value
    else current == value
    end
  end

  # #1116 — pick, never type: a role id must resolve to a role the document
  # declares, or the export names a role nobody defined.
  def role_refs(raw)
    ids = Array(raw).flat_map { _1.to_s.split(",") }.map(&:strip).compact_blank.uniq
    undeclared = ids - @document.declared_role_ids
    raise InvalidItem, "not declared on this document: #{undeclared.join(', ')}. Declare the role first." if undeclared.any?

    ids.map { { "role-id" => _1 } }
  end

  def completion_date(raw)
    return nil if raw.blank?

    Date.iso8601(raw.to_s.strip)
  rescue Date::Error
    raise InvalidItem, "expected completion #{raw.inspect} is not a date (YYYY-MM-DD)"
  end

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
