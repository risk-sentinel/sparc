require "roo"

class TprExcelParserService
  # Maps normalized header text → { key:, control_attr: }
  # control_attr: true    = stored on TprControl directly
  # control_attr: :subject = special Subject parsing (asset | environment)
  # control_attr: false   = stored as TprControlField
  COLUMN_MAP = {
    "#"                => { key: "row_number",       control_attr: false },
    "inherited"        => { key: "inherited",        control_attr: false },
    "date"             => { key: "date",             control_attr: false },
    "paragraph"        => { key: :control_id,        control_attr: true  },
    "provided as"      => { key: "coverage_level",      control_attr: false },
    "tester"           => { key: "tester",           control_attr: false },
    "result"           => { key: "result",           control_attr: false },
    "notes/weakness"   => { key: "notes_weakness",   control_attr: false },
    "recommended fix"  => { key: "recommended_fix",  control_attr: false },
    "subject"          => { key: :subject,           control_attr: :subject },
    "control status"   => { key: "control_status",   control_attr: false },
    "responsibility"   => { key: "responsibility",   control_attr: false },
    "test title"       => { key: :title,             control_attr: true  },
    "impact statement" => { key: "impact_statement", control_attr: false },
    "test text"        => { key: "test_text",        control_attr: false },
    "expected result"  => { key: "expected_result",  control_attr: false },
    "custom"           => { key: "custom",           control_attr: false },
    "custom name"      => { key: "custom_name",      control_attr: false },
    "custom author"    => { key: "custom_author",    control_attr: false },
    "control text"     => { key: "control_text",     control_attr: false },
    "implementation"   => { key: "implementation",   control_attr: false },
    "working comments" => { key: "working_comments", control_attr: false },
    "working status"   => { key: "working_status",   control_attr: false }
  }.freeze

  def initialize(tpr_document, file_path)
    @document    = tpr_document
    @file_path   = file_path
    @spreadsheet = Roo::Spreadsheet.open(file_path)
  end

  def parse
    global_row_order = 0

    @spreadsheet.sheets.each do |sheet_name|
      section = sheet_name.to_s.strip
      sheet   = @spreadsheet.sheet(sheet_name)
      next if sheet.last_row.nil? || sheet.last_row < 2

      raw_headers = sheet.row(1).map { |h| h.to_s.strip.downcase }
      col_config  = build_col_config(raw_headers)

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

        control = @document.tpr_controls.create!(
          control_id:          attrs[:control_id],
          title:               attrs[:title],
          section:             attrs[:section],
          subject_asset:       attrs[:subject_asset],
          subject_environment: attrs[:subject_environment],
          row_order:           attrs[:row_order]
        )

        global_row_order += 1

        fields.each do |field_name, value|
          control.tpr_control_fields.create!(
            field_name:  field_name.to_s,
            field_value: value
          )
        end
      end
    end
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
