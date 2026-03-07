class JsonExportService
  def self.export_ssp(ssp_document)
    new(ssp_document, :ssp).export
  end

  def self.export_sar(sar_document)
    new(sar_document, :sar).export
  end

  def self.export_cdef(cdef_document)
    new(cdef_document, :cdef).export
  end

  def self.export_profile(profile_document)
    new(profile_document, :profile).export
  end

  def initialize(document, type)
    @document = document
    @type = type
  end

  def export
    JSON.pretty_generate(@document.to_json_data)
  end
end
