require "roo"

class SarExcelParserService
  include BatchInsertable
  include ProgressTrackable

  # Column mapping is loaded from lib/data_mappings/sar_excel.json via DataMappingSchema.
  # This provides a vendor-neutral, declarative mapping that includes editability,
  # validation rules, and OSCAL export field mappings alongside the import config.
  SCHEMA = DataMappingSchema.load(:sar_excel)
  COLUMN_MAP = SCHEMA.column_map.freeze

  def initialize(sar_document, file_path)
    @document    = sar_document
    @file_path   = file_path
    @spreadsheet = Roo::Spreadsheet.open(file_path.to_s)
  end

  def parse
    update_processing_stage!(:reading_file, "Opening spreadsheet...")

    sheet_metadata   = {}
    control_attrs    = []  # Array of attribute hashes for SarControl
    field_entries    = []  # Array of [control_index, field_name, field_value]
    global_row_order = 0

    total_sheets = @spreadsheet.sheets.size
    update_processing_stage!(:parsing, "Parsing #{total_sheets} sheets...")

    @spreadsheet.sheets.each do |sheet_name|
      section = sheet_name.to_s.strip
      sheet   = @spreadsheet.sheet(sheet_name)
      next if sheet.last_row.nil? || sheet.last_row < 2

      raw_headers = sheet.row(1).map { |h| h.to_s.strip.downcase }
      col_config  = build_col_config(raw_headers)

      # Capture original headers for Excel round-trip export
      sheet_metadata[section] = {
        "headers" => sheet.row(1).map { |h| h.to_s.strip }
      }

      (2..sheet.last_row).each do |row_num|
        row_data = sheet.row(row_num)
        next if row_data.all?(&:nil?)

        attrs  = { section: section, row_order: global_row_order }
        fields = {}

        col_config.each do |idx, config|
          raw   = row_data[idx]
          value = raw.nil? ? nil : raw.to_s.strip.presence

          case config[:control_attr]
          when true
            attrs[config[:key]] = value
          when :subject
            if value
              parts = value.split("|", 2)
              attrs[:subject_asset]       = parts[0]&.strip.presence
              attrs[:subject_environment] = parts[1]&.strip.presence
            end
          else
            fields[config[:key]] = value unless value.nil?
          end
        end

        # Compute denormalized columns inline
        attrs[:control_family] = attrs[:control_id].to_s.split("-").first.upcase.presence
        attrs[:cached_result]  = fields["result"]

        control_idx = control_attrs.size
        control_attrs << attrs
        fields.each do |fname, fval|
          field_entries << [ control_idx, fname.to_s, fval ]
        end

        # Progress heartbeat every 500 rows
        if global_row_order > 0 && (global_row_order % 500).zero?
          update_processing_progress!("Parsed #{global_row_order} rows across #{total_sheets} sheets...")
        end

        global_row_order += 1
      end
    end

    update_processing_stage!(:creating_records, "Creating #{control_attrs.size} controls in database...")
    batch_insert_records(
      control_class: SarControl,
      field_class:   SarControlField,
      document_fk:   :sar_document_id,
      control_attrs: control_attrs,
      field_entries: field_entries
    )

    # Save Excel metadata for round-trip export
    @document.update!(excel_metadata: {
      "sheet_order" => @spreadsheet.sheets.map { |s| s.to_s.strip },
      "sheets"      => sheet_metadata
    })
  end

  private

  def build_col_config(raw_headers)
    config = {}
    raw_headers.each_with_index do |header, idx|
      mapping = COLUMN_MAP[header]
      config[idx] = mapping if mapping
    end
    config
  end
end
