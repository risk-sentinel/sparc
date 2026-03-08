# Loads and provides access to vendor-neutral data mapping definitions.
#
# Mapping files live in lib/data_mappings/*.json and describe how source
# columns (e.g. Excel headers) map to internal model attributes and fields,
# including editability, validation rules, and OSCAL export mappings.
#
# Usage:
#   schema = DataMappingSchema.load(:ssp_excel)
#   schema.column_map          # => { "paragraph/reqid" => { key: :control_id, control_attr: true }, ... }
#   schema.editable_fields     # => ["status", "private_implementation", ...]
#   schema.field_definition("status")  # => { "key" => "status", "editable" => true, ... }
#   schema.oscal_mappings      # => { "status" => { "target" => "prop", ... }, ... }
#
class DataMappingSchema
  class SchemaNotFound < StandardError; end
  class InvalidSchema < StandardError; end

  MAPPINGS_DIR = Rails.root.join("lib", "data_mappings").freeze

  attr_reader :format, :version, :description, :document_type, :control_type, :field_type, :fields

  def initialize(data)
    @format        = data.fetch("format")
    @version       = data.fetch("version")
    @description   = data["description"]
    @document_type = data.fetch("document_type")
    @control_type  = data.fetch("control_type")
    @field_type    = data.fetch("field_type")
    @fields        = data.fetch("fields")

    validate!
  end

  # Load a mapping schema by name (e.g. :ssp_excel, :sar_excel).
  def self.load(name)
    path = MAPPINGS_DIR.join("#{name}.json")
    raise SchemaNotFound, "No mapping file found at #{path}" unless path.exist?

    data = JSON.parse(path.read)
    new(data)
  end

  # Returns all available mapping schema names.
  def self.available
    Dir[MAPPINGS_DIR.join("*.json")].map { |f| File.basename(f, ".json").to_sym }
  end

  # Build a COLUMN_MAP hash compatible with existing parser services.
  # Returns: { "normalized_header" => { key: <symbol_or_string>, control_attr: <true|false|:subject> } }
  def column_map
    @column_map ||= fields.each_with_object({}) do |field, map|
      control_attr = case field["storage"]
                     when "control_attribute" then true
                     when "subject" then :subject
                     else false
                     end

      key = control_attr == true ? field["key"].to_sym : field["key"]

      map[field["source_header"]] = { key: key, control_attr: control_attr }
    end
  end

  # Returns array of editable field keys.
  def editable_fields
    @editable_fields ||= fields.select { |f| f["editable"] == true }.map { |f| f["key"] }
  end

  # Returns the full field definition hash for a given key.
  def field_definition(key)
    @field_index ||= fields.index_by { |f| f["key"] }
    @field_index[key]
  end

  # Returns hash of field_key => oscal_mapping for fields that have OSCAL mappings.
  def oscal_mappings
    @oscal_mappings ||= fields.each_with_object({}) do |field, map|
      map[field["key"]] = field["oscal_mapping"] if field["oscal_mapping"]
    end
  end

  # Returns validation rules for a given field key, or nil.
  def validation_for(key)
    field_definition(key)&.dig("validation")
  end

  # Returns allowed values for a field, or nil if unconstrained.
  def allowed_values_for(key)
    validation_for(key)&.dig("allowed_values")
  end

  private

  def validate!
    raise InvalidSchema, "format is required" if @format.blank?
    raise InvalidSchema, "version is required" if @version.blank?
    raise InvalidSchema, "fields must be an array" unless @fields.is_a?(Array)
    raise InvalidSchema, "fields cannot be empty" if @fields.empty?

    @fields.each do |field|
      raise InvalidSchema, "Each field must have a 'key'" if field["key"].blank?
      raise InvalidSchema, "Each field must have a 'source_header'" if field["source_header"].blank?
      raise InvalidSchema, "Each field must have a 'storage' (control_attribute, control_field, or subject)" unless
        %w[control_attribute control_field subject].include?(field["storage"])
    end
  end
end
