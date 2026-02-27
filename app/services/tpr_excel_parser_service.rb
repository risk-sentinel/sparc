require 'roo'

class TprExcelParserService
  REQUIRED_COLUMNS = {
    control_id: ['Control ID', 'Control Identifier', 'ID'],
    title: ['Control Title', 'Title', 'Control Name'],
    test_status: ['Test Status', 'Status'],
    test_date: ['Test Date', 'Date Tested'],
    tester_name: ['Tester Name', 'Tester', 'Tested By'],
    test_results: ['Test Results', 'Results', 'Findings'],
    remediation_plan: ['Remediation Plan', 'Remediation', 'Action Plan']
  }.freeze
  
  def initialize(tpr_document, file_path)
    @document = tpr_document
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
    
    control = @document.tpr_controls.create!(
      control_id: control_id.to_s.strip,
      title: row_data[column_mapping[:title]]&.to_s&.strip
    )
    
    column_mapping.each do |field_name, index|
      next if field_name == :control_id || field_name == :title
      
      value = row_data[index]
      next if value.nil?
      
      control.tpr_control_fields.create!(
        field_name: field_name.to_s,
        field_value: value.to_s
      )
    end
  end
end