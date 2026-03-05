# Centralized registry mapping document type keys to their associated classes,
# file extensions, parser services, and display messages.
#
# Usage:
#   entry = DocumentTypeRegistry.for(:tpr)
#   entry.document_class  # => TprDocument
#   entry.parser_map      # => { "excel" => TprExcelParserService }
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
    tpr: Entry.new(
      document_class:     TprDocument,
      control_class:      TprControl,
      field_class:        TprControlField,
      document_fk:        :tpr_document_id,
      allowed_extensions: { ".xlsx" => "excel", ".xls" => "excel" },
      parser_map:         { "excel" => TprExcelParserService },
      file_prefix:        "tpr",
      success_message:    "Test Plan Results workbook uploaded. Processing in background..."
    ),
    profile: Entry.new(
      document_class:     ProfileDocument,
      control_class:      ProfileControl,
      field_class:        ProfileControlField,
      document_fk:        :profile_document_id,
      allowed_extensions: { ".xml" => "xccdf", ".json" => "json" },
      parser_map:         { "xccdf" => ProfileXccdfParserService, "json" => ProfileJsonParserService },
      file_prefix:        "profile",
      success_message:    "Profile uploaded. Processing in background..."
    )
  }.freeze

  class << self
    def for(key)
      TYPES.fetch(key.to_sym) { raise ArgumentError, "Unknown document type: #{key}" }
    end
  end
end
