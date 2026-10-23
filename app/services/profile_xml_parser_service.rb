require "tempfile"

class ProfileXmlParserService
  include ProgressTrackable

  def initialize(profile_document, file_path)
    @document  = profile_document
    @file_path = file_path
  end

  # #1234 — an OSCAL profile in XML is converted to the JSON model and parsed
  # by ProfileJsonParserService, as the YAML parser already does. One parser for
  # the three formats means each import links its own catalog, whatever the
  # file's format (owner, 2026-10-21: JSON, YAML and XML must all be honoured).
  #
  # #1252 — the conversion is the whole OSCAL model, not a hand-built subset.
  # The subset dropped `matching`, `with-child-controls`, `exclude-controls`,
  # removes, added parts and a set-parameter's `select`, so an XML profile
  # selected and tailored differently from the same profile in JSON. The file
  # is schema-validated against the baked-in OSCAL XSD first, as an XML catalog
  # import is (#1228).
  def parse
    update_processing_stage!(:reading_file)
    content = File.read(@file_path)
    root = XmlSecurity.parse(content).tap(&:remove_namespaces!).root

    # A resolved profile catalog (NIST's published baselines) has a <catalog>
    # root carrying a resolution-tool prop or a source-profile link.
    return parse_resolved(content) if root&.name == "catalog" && resolved_profile_catalog_xml?(root)
    raise DocumentParseError, "Invalid OSCAL Profile XML: missing <profile> element" unless root&.name == "profile"

    validate!(:profile, content)
    delegate_to_json(convert(OscalProfileXmlToJson, content))
    @document.reload.update_column(:import_metadata, (@document.import_metadata || {}).merge("format" => "oscal_profile_xml"))
  end

  private

  def parse_resolved(content)
    validate!(:catalog, content)
    delegate_to_json(convert(OscalCatalogXmlToJson, content))
  end

  def validate!(model, content)
    result = OscalSchemaValidationService.validate_xml(model, content, version: OscalSchema::DEFAULT_VERSION)
    return if result.valid?

    raise DocumentParseError, "Not a valid OSCAL XML #{model} (OSCAL #{result.schema_version}): " \
                              "#{result.errors.first(3).join('; ')}"
  end

  def convert(converter, content)
    converter.convert(content)
  rescue OscalCatalogXmlToJson::ConversionError => e
    raise DocumentParseError, "Could not read the OSCAL XML file: #{e.message}"
  end

  def delegate_to_json(data)
    tmp = Tempfile.new([ "profile_xml_", ".json" ])
    tmp.write(JSON.generate(data))
    tmp.close

    ProfileJsonParserService.new(@document, tmp.path).parse
  ensure
    tmp&.unlink
  end

  def resolved_profile_catalog_xml?(catalog_el)
    metadata = catalog_el.at_xpath("metadata")
    return false unless metadata

    metadata.xpath("prop[@name='resolution-tool']").any? ||
      metadata.xpath("link[@rel='source-profile']").any?
  end
end
