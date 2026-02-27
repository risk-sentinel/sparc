require 'roo'

class SspExcelParserService
  REQUIRED_COLUMNS = {
    control_id: ['Control ID', 'Control Identifier', 'ID'],
    title: ['Control Title', 'Title', 'Control Name'],
    responsible_role: ['Responsible Role', 'Role'],
    implementation_status: ['Implementation Status', 'Status'],
    control_type: ['Control Origination', 'Origination'],
    customer_responsibility: ['Customer Responsibility', 'Responsibility'],
    implementation_guidance: ['Implementation Guidance', 'Guidance']
  }.freeze
  
  def initialize(ssp_document, file_path)
    @document = ssp_document
    @file_path = file_path
    @spreadsheet = Roo::Spreadsheet.open(file_path)
  end
  
  def parse
    sheet = @spreadsheet.sheet(0)
    headers = normalize_headers(sheet.row(1))
    column_mapping = map_columns(headers)
    
    (2..sheet.last_row).each do |row_num|
      row_data = sheet.row(row_num)
      next if row_data.all?(&:nil?)
      
      create_control(row_data, column_mapping)
    end
  end
  
  private
  
  def normalize_headers(headers)
    headers.map { |h| h.to_s.strip.downcase }
  end
  
  def map_columns(headers)
    mapping = {}
    
    REQUIRED_COLUMNS.each do |field, possible_names|
      possible_names.each do |name|
        index = headers.index(name.downcase)
        if index
          mapping[field] = index
          break
        end
      end
    end
    
    mapping
  end
  
  def create_control(row_data, column_mapping)
    control_id = row_data[column_mapping[:control_id]]
    return unless control_id
    
    control = @document.ssp_controls.create!(
      control_id: control_id.to_s.strip,
      title: row_data[column_mapping[:title]]&.to_s&.strip
    )
    
    # Create fields for each mapped column
    column_mapping.each do |field_name, index|
      next if field_name == :control_id || field_name == :title
      
      value = row_data[index]
      next if value.nil?
      
      control.ssp_control_fields.create!(
        field_name: field_name.to_s,
        field_value: value.to_s
      )
    end
  end
end