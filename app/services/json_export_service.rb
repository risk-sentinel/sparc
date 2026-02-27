class JsonExportService
  def self.export_ssp(ssp_document)
    new(ssp_document, :ssp).export
  end
  
  def self.export_tpr(tpr_document)
    new(tpr_document, :tpr).export
  end
  
  def initialize(document, type)
    @document = document
    @type = type
  end
  
  def export
    JSON.pretty_generate(@document.to_json_data)
  end
end