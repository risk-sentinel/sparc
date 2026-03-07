# Centralized registry mapping document type keys to their associated classes,
# file extensions, parser services, and display messages.
#
# Usage:
#   entry = DocumentTypeRegistry.for(:sar)
#   entry.document_class  # => SarDocument
#   entry.parser_map      # => { "excel" => SarExcelParserService }
#
class DocumentTypeRegistry
  Entry = Data.define(
    :document_class,
    :control_class,
    :field_class,
    :document_fk,
    :allowed_extensions,
    :parser_map,
    :file_prefix,
    :success_message
  )

  TYPES = {
    ssp: Entry.new(
      document_class:     SspDocument,
      control_class:      SspControl,
      field_class:        SspControlField,
      document_fk:        :ssp_document_id,
      allowed_extensions: { ".xlsx" => "excel", ".xls" => "excel" },
      parser_map:         { "excel" => SspExcelParserService },
      file_prefix:        "ssp",
      success_message:    "Controls Implementation workbook uploaded. Processing in background..."
    ),
    sar: Entry.new(
      document_class:     SarDocument,
      control_class:      SarControl,
      field_class:        SarControlField,
      document_fk:        :sar_document_id,
      allowed_extensions: { ".xlsx" => "excel", ".xls" => "excel" },
      parser_map:         { "excel" => SarExcelParserService },
      file_prefix:        "sar",
      success_message:    "Security Assessment Results workbook uploaded. Processing in background..."
    ),
    cdef: Entry.new(
      document_class:     CdefDocument,
      control_class:      CdefControl,
      field_class:        CdefControlField,
      document_fk:        :cdef_document_id,
      allowed_extensions: { ".xml" => "xccdf", ".json" => "json" },
      parser_map:         { "xccdf" => CdefXccdfParserService, "json" => CdefJsonParserService },
      file_prefix:        "cdef",
      success_message:    "Component Definition uploaded. Processing in background..."
    ),
    profile: Entry.new(
      document_class:     ProfileDocument,
      control_class:      ProfileControl,
      field_class:        ProfileControlField,
      document_fk:        :profile_document_id,
      allowed_extensions: { ".json" => "json", ".xml" => "xml" },
      parser_map:         { "json" => ProfileJsonParserService, "xml" => ProfileXmlParserService },
      file_prefix:        "profile",
      success_message:    "OSCAL Profile (Baseline) uploaded. Processing in background..."
    )
  }.freeze

  class << self
    def for(key)
      TYPES.fetch(key.to_sym) { raise ArgumentError, "Unknown document type: #{key}" }
    end
  end
end
