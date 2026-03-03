require "roo"

class SspExcelParserService
  # Maps normalized header text → { key:, control_attr: }
  # control_attr: true  = stored directly on SspControl
  # control_attr: false = stored as SspControlField
  COLUMN_MAP = {
    "paragraph/reqid"        => { key: :control_id,             control_attr: true  },
    "title"                  => { key: :title,                   control_attr: true  },
    "stated requirement"     => { key: "stated_requirement",     control_attr: false },
    "private implementation" => { key: "private_implementation", control_attr: false },
    "public implementation"  => { key: "public_implementation",  control_attr: false },
    "notes"                  => { key: "notes",                  control_attr: false },
    "status"                 => { key: "status",                 control_attr: false },
    "expected completion"    => { key: "expected_completion",    control_attr: false },
    "class"                  => { key: "class",                  control_attr: false },
    "priority"               => { key: "priority",               control_attr: false },
    "responsible entities"   => { key: "responsible_entities",   control_attr: false },
    "control owner"          => { key: "control_owner",          control_attr: false },
    "type/use as"            => { key: "type_use_as",            control_attr: false },
    "inherited from"         => { key: "inherited_from",         control_attr: false },
    "provided as"            => { key: "provided_as",            control_attr: false },
    "control origination"    => { key: "control_origination",    control_attr: false },
    "history"                => { key: "history",                control_attr: false }
  }.freeze

  def initialize(ssp_document, file_path)
    @document  = ssp_document
    @file_path = file_path
    @spreadsheet = Roo::Spreadsheet.open(file_path)
  end

  def parse
    sheet = @spreadsheet.sheet(0)
    return if sheet.last_row.nil? || sheet.last_row < 2

    raw_headers = sheet.row(1).map { |h| h.to_s.strip.downcase }
    col_config = build_col_config(raw_headers)

    current_parent = nil
    row_order      = 0

    (2..sheet.last_row).each do |row_num|
      row_data = sheet.row(row_num)
      next if row_data.all?(&:nil?)

      attrs  = {}
      fields = {}

      col_config.each do |idx, config|
        raw   = row_data[idx]
        value = raw.nil? ? nil : raw.to_s.strip.presence

        if config[:control_attr]
          attrs[config[:key]] = value
        else
          fields[config[:key]] = value unless value.nil?
        end
      end

      control_id = attrs[:control_id]
      title      = attrs[:title]

      control = @document.ssp_controls.create!(
        control_id: control_id.presence,
        title:      title,
        row_order:  row_order,
        parent_id:  control_id.present? ? nil : current_parent&.id
      )

      current_parent = control if control_id.present?
      row_order += 1

      fields.each do |field_name, value|
        control.ssp_control_fields.create!(
          field_name:  field_name.to_s,
          field_value: value
        )
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
