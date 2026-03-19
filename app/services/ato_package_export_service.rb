# Generates a ZIP file containing OSCAL JSON exports for all documents
# linked to an Authorization Boundary, plus a manifest with validation
# status.
#
# Usage:
#   service = AtoPackageExportService.new(authorization_boundary)
#   zip_data = service.generate_zip   # => binary string
#   summary  = service.validation_summary  # => { ssp: { valid: true, errors: [] }, ... }
#
class AtoPackageExportService
  require "zip"

  EXPORT_SERVICES = {
    ssp:  OscalSspExportService,
    sap:  OscalAssessmentPlanExportService,
    sar:  OscalSarExportService,
    poam: OscalPoamExportService,
    cdef: OscalComponentDefinitionExportService
  }.freeze

  def initialize(authorization_boundary)
    @ab = authorization_boundary
  end

  def generate_zip
    buffer = Zip::OutputStream.write_buffer do |zip|
      add_document(zip, "ssp.json", :ssp, @ab.ssp_document)
      add_document(zip, "sap.json", :sap, @ab.sap_document)
      add_document(zip, "sar.json", :sar, @ab.sar_document)

      @ab.poam_documents.each_with_index do |poam, i|
        add_document(zip, "poam-#{i + 1}.json", :poam, poam)
      end

      @ab.cdef_documents.distinct.each do |cdef|
        add_document(zip, "cdef-#{cdef.slug}.json", :cdef, cdef)
      end

      add_manifest(zip)
    end
    buffer.string
  end

  def validation_summary
    summary = {}

    { ssp: @ab.ssp_document, sap: @ab.sap_document, sar: @ab.sar_document }.each do |key, doc|
      summary[key] = validate_document(key, doc)
    end

    @ab.poam_documents.each_with_index do |poam, i|
      summary[:"poam_#{i + 1}"] = validate_document(:poam, poam)
    end

    @ab.cdef_documents.distinct.each do |cdef|
      summary[:"cdef_#{cdef.slug}"] = validate_document(:cdef, cdef)
    end

    summary
  end

  private

  def add_document(zip, filename, type, document)
    return unless document

    service = EXPORT_SERVICES[type].new(document)
    json = service.export_unvalidated
    zip.put_next_entry(filename)
    zip.write(json)
  rescue => e
    Rails.logger.warn("ATO export: failed to export #{type} #{document.id}: #{e.message}")
  end

  def validate_document(type, document)
    return { name: nil, valid: nil, errors: [ "Not linked" ] } unless document

    service = EXPORT_SERVICES[type].new(document)
    result = service.validation_result
    {
      name: document.name,
      valid: result.valid?,
      errors: result.valid? ? [] : result.errors.first(3)
    }
  rescue => e
    { name: document&.name, valid: false, errors: [ e.message ] }
  end

  def add_manifest(zip)
    manifest = {
      "authorization_boundary" => {
        "name" => @ab.name,
        "status" => @ab.status,
        "generated_at" => Time.current.iso8601
      },
      "documents" => build_document_list,
      "validation" => validation_summary.transform_values { |v| v[:valid] }
    }
    zip.put_next_entry("manifest.json")
    zip.write(JSON.pretty_generate(manifest))
  end

  def build_document_list
    list = []
    list << { type: "ssp", name: @ab.ssp_document&.name, file: "ssp.json" } if @ab.ssp_document
    list << { type: "sap", name: @ab.sap_document&.name, file: "sap.json" } if @ab.sap_document
    list << { type: "sar", name: @ab.sar_document&.name, file: "sar.json" } if @ab.sar_document
    @ab.poam_documents.each_with_index do |poam, i|
      list << { type: "poam", name: poam.name, file: "poam-#{i + 1}.json" }
    end
    @ab.cdef_documents.distinct.each do |cdef|
      list << { type: "cdef", name: cdef.name, file: "cdef-#{cdef.slug}.json" }
    end
    list
  end
end
