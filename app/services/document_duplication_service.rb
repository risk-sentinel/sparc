class DocumentDuplicationService
  # Per-document-type config:
  #   controls:      has-many association on the document
  #   fields:        nested has-many on each control (always present)
  #   statements:    optional nested has-many on each control (CDEF only)
  #   version_attr:  document-version column to reset on the copy
  SUPPORTED_TYPES = {
    "ProfileDocument" => { controls: :profile_controls, fields: :profile_control_fields, version_attr: :profile_version },
    "CdefDocument"    => { controls: :cdef_controls,    fields: :cdef_control_fields,    statements: :cdef_control_statements, version_attr: :cdef_version }
  }.freeze

  # uuid is excluded so the duplicate gets its own gen_random_uuid() default
  # rather than colliding with the source's uuid (globally unique per #397).
  SKIP_ATTRIBUTES = %w[id created_at updated_at slug uuid].freeze

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
    attrs = @source.attributes.except(*SKIP_ATTRIBUTES, "uuid", "status", "error_message", "original_filename", "file_type", "lifecycle_status", "published")
    attrs["name"] = new_name
    attrs[@config[:version_attr].to_s] = nil
    attrs["status"] = "completed"
    attrs["lifecycle_status"] = "in_progress"
    attrs["published"] = nil if @source.class.column_names.include?("published")
    attrs["import_metadata"] = { "copied_from" => @source.id, "copied_at" => Time.current.iso8601 }

    @source.class.new(attrs)
  end

  def copy_controls(copy)
    controls_assoc   = @config[:controls]
    fields_assoc     = @config[:fields]
    statements_assoc = @config[:statements] # optional; CDEF only today

    includes_list = [ fields_assoc, statements_assoc ].compact
    @source.public_send(controls_assoc).includes(*includes_list).find_each do |source_control|
      control_attrs = source_control.attributes.except(*SKIP_ATTRIBUTES)
      control_attrs.delete("profile_document_id")
      control_attrs.delete("cdef_document_id")

      new_control = copy.public_send(controls_assoc).build(control_attrs)
      new_control.save!

      copy_field_children!(source_control, new_control, fields_assoc, parent_fk_for(fields_assoc))
      copy_field_children!(source_control, new_control, statements_assoc, parent_fk_for(statements_assoc)) if statements_assoc
    end
  end

  # Copy each nested child record (fields or statements). The parent FK is
  # excluded so create! sets it from the association.
  #
  # Some child models (e.g. CdefControlStatement) carry a `validates :uuid,
  # presence: true` Ruby-side check. The schema-level `gen_random_uuid()`
  # default only fires at INSERT, but validation runs before save and would
  # fail. Pre-fill a fresh SecureRandom UUID when the model has the column —
  # safe because we've already excluded `uuid` via SKIP_ATTRIBUTES (no
  # collision with the source's uuid).
  def copy_field_children!(source_control, new_control, assoc, parent_fk)
    source_control.public_send(assoc).each do |source_child|
      child_attrs = source_child.attributes.except(*SKIP_ATTRIBUTES)
      child_attrs.delete(parent_fk)
      child_class = source_child.class
      child_attrs["uuid"] = SecureRandom.uuid if child_class.column_names.include?("uuid")
      new_control.public_send(assoc).create!(child_attrs)
    end
  end

  # Derive the parent FK column from the association name:
  #   :cdef_control_fields     -> "cdef_control_id"
  #   :cdef_control_statements -> "cdef_control_id"
  #   :profile_control_fields  -> "profile_control_id"
  def parent_fk_for(assoc)
    "#{assoc.to_s.sub(/_(fields|statements)\z/, '')}_id"
  end
end
