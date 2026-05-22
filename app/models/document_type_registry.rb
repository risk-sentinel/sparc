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
      allowed_extensions: { ".xlsx" => "excel", ".xls" => "excel", ".json" => "json", ".xml" => "xml", ".yaml" => "yaml", ".yml" => "yaml" },
      parser_map:         { "excel" => SspExcelParserService, "json" => SspJsonParserService, "xml" => SspXmlParserService, "yaml" => SspYamlParserService },
      file_prefix:        "ssp",
      success_message:    "System Security Plan document uploaded. Processing in background..."
    ),
    sar: Entry.new(
      document_class:     SarDocument,
      control_class:      SarControl,
      field_class:        SarControlField,
      document_fk:        :sar_document_id,
      allowed_extensions: { ".xlsx" => "excel", ".xls" => "excel", ".json" => "json", ".xml" => "xml", ".yaml" => "yaml", ".yml" => "yaml" },
      parser_map:         { "excel" => SarExcelParserService, "json" => SarJsonParserService, "xml" => SarXmlParserService, "yaml" => SarYamlParserService },
      file_prefix:        "sar",
      success_message:    "Security Assessment Results uploaded. Processing in background..."
    ),
    cdef: Entry.new(
      document_class:     CdefDocument,
      control_class:      CdefControl,
      field_class:        CdefControlField,
      document_fk:        :cdef_document_id,
      allowed_extensions: { ".xml" => "xccdf", ".json" => "json", ".yaml" => "yaml", ".yml" => "yaml" },
      parser_map:         { "xccdf" => CdefXccdfParserService, "json" => CdefJsonParserService, "yaml" => CdefYamlParserService },
      file_prefix:        "cdef",
      success_message:    "Component Definition uploaded. Processing in background..."
    ),
    profile: Entry.new(
      document_class:     ProfileDocument,
      control_class:      ProfileControl,
      field_class:        ProfileControlField,
      document_fk:        :profile_document_id,
      allowed_extensions: { ".json" => "json", ".xml" => "xml", ".yaml" => "yaml", ".yml" => "yaml" },
      parser_map:         { "json" => ProfileJsonParserService, "xml" => ProfileXmlParserService, "yaml" => ProfileYamlParserService },
      file_prefix:        "profile",
      success_message:    "OSCAL Profile (Baseline) uploaded. Processing in background..."
    ),
    sap: Entry.new(
      document_class:     SapDocument,
      control_class:      SapControl,
      field_class:        SapControlField,
      document_fk:        :sap_document_id,
      allowed_extensions: { ".json" => "json", ".xml" => "xml", ".yaml" => "yaml", ".yml" => "yaml" },
      parser_map:         { "json" => SapJsonParserService, "xml" => SapXmlParserService, "yaml" => SapYamlParserService },
      file_prefix:        "sap",
      success_message:    "OSCAL Assessment Plan uploaded. Processing in background..."
    ),
    poam: Entry.new(
      document_class:     PoamDocument,
      control_class:      PoamItem,
      field_class:        nil,
      document_fk:        :poam_document_id,
      allowed_extensions: { ".json" => "json", ".xml" => "xml", ".yaml" => "yaml", ".yml" => "yaml" },
      parser_map:         { "json" => PoamJsonParserService, "xml" => PoamXmlParserService, "yaml" => PoamYamlParserService },
      file_prefix:        "poam",
      success_message:    "OSCAL POA&M uploaded. Processing in background..."
    )
  }.freeze

  class << self
    def for(key)
      entry = TYPES.fetch(key.to_sym) { raise ArgumentError, "Unknown document type: #{key}" }
      apply_xlsx_gate(entry)
    end

    private

    # #510: XLSX/XLS extensions are filtered out of allowed_extensions unless
    # SparcConfig.xlsx_uploads_enabled? returns true. Default-disabled
    # obscures the legacy XLSX path that survives only for API consumers
    # (UI access was already removed in #479). The Entry returned to callers
    # reflects current configuration so the upstream FileUploadable check
    # rejects XLSX with the same "Unsupported file type" message as if XLSX
    # had never been registered.
    def apply_xlsx_gate(entry)
      return entry if SparcConfig.xlsx_uploads_enabled?
      return entry unless entry.allowed_extensions.key?(".xlsx") || entry.allowed_extensions.key?(".xls")

      filtered = entry.allowed_extensions.except(".xlsx", ".xls")
      Entry.new(**entry.to_h.merge(allowed_extensions: filtered))
    end
  end
end
