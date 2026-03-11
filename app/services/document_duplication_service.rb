class DocumentDuplicationService
  SUPPORTED_TYPES = {
    "ProfileDocument" => { controls: :profile_controls, fields: :profile_control_fields, version_attr: :profile_version },
    "CdefDocument" => { controls: :cdef_controls, fields: :cdef_control_fields, version_attr: :cdef_version }
  }.freeze

  SKIP_ATTRIBUTES = %w[id created_at updated_at].freeze

  def initialize(source_document)
    @source = source_document
    @config = SUPPORTED_TYPES.fetch(source_document.class.name)
  end

  def duplicate(new_name: nil)
    new_name ||= "Copy of #{@source.name}"

    ActiveRecord::Base.transaction do
      copy = build_document_copy(new_name)
      copy.save!
      copy_controls(copy)
      copy
    end
  end

  private

  def build_document_copy(new_name)
    attrs = @source.attributes.except(*SKIP_ATTRIBUTES, "uuid", "status", "error_message", "original_filename", "file_type")
    attrs["name"] = new_name
    attrs[@config[:version_attr].to_s] = nil
    attrs["status"] = "completed"
    attrs["import_metadata"] = { "copied_from" => @source.id, "copied_at" => Time.current.iso8601 }

    @source.class.new(attrs)
  end

  def copy_controls(copy)
    controls_assoc = @config[:controls]
    fields_assoc = @config[:fields]

    @source.public_send(controls_assoc).includes(fields_assoc).find_each do |source_control|
      control_attrs = source_control.attributes.except(*SKIP_ATTRIBUTES, "#{controls_assoc.to_s.singularize.sub(/s$/, '')}_document_id")
      control_attrs.delete("profile_document_id")
      control_attrs.delete("cdef_document_id")

      new_control = copy.public_send(controls_assoc).build(control_attrs)
      new_control.save!

      source_control.public_send(fields_assoc).each do |source_field|
        field_attrs = source_field.attributes.except(*SKIP_ATTRIBUTES, "#{fields_assoc.to_s.singularize.sub(/s$/, '')}_control_id")
        field_attrs.delete("profile_control_id")
        field_attrs.delete("cdef_control_id")

        new_control.public_send(fields_assoc).create!(field_attrs)
      end
    end
  end
end
