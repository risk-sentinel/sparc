require "caxlsx"

class TprExcelExportService
  def initialize(tpr_document)
    @document = tpr_document
    @metadata = tpr_document.excel_metadata || {}
  end

  def export
    package = Axlsx::Package.new
    workbook = package.workbook

    header_style = workbook.styles.add_style(
      b: true, bg_color: "2C3E50", fg_color: "FFFFFF", sz: 11
    )

    sheet_order = @metadata["sheet_order"] ||
                  @document.tpr_controls.distinct.order(:section).pluck(:section).compact

    sheets_meta = @metadata["sheets"] || {}

    sheet_order.each do |section_name|
      controls = @document.tpr_controls
                           .where(section: section_name)
                           .includes(:tpr_control_fields)
                           .order(:row_order)

      next if controls.empty?

      sheet_meta = sheets_meta[section_name] || {}
      headers = sheet_meta["headers"] || default_headers

      workbook.add_worksheet(name: truncate_sheet_name(section_name)) do |sheet|
        sheet.add_row headers, style: header_style

        controls.each do |control|
          field_map = control.tpr_control_fields.index_by(&:field_name)
          row = headers.map { |h| cell_value(h, control, field_map) }
          sheet.add_row row
        end
      end
    end

    package.to_stream.read
  end

  private

  def default_headers
    TprExcelParserService::COLUMN_MAP.map { |normalized, config|
      # Restore original casing from the normalized key
      normalized.split.map(&:capitalize).join(" ")
    }
  end

  def truncate_sheet_name(name)
    # Excel sheet names are limited to 31 characters
    name.to_s[0, 31]
  end

  def cell_value(header, control, field_map)
    normalized = header.to_s.strip.downcase
    config = TprExcelParserService::COLUMN_MAP[normalized]
    return nil unless config

    case config[:control_attr]
    when true
      control.public_send(config[:key]) rescue nil
    when :subject
      [control.subject_asset, control.subject_environment].compact.join(" | ").presence
    else
      field_map[config[:key].to_s]&.field_value
    end
  end
end
