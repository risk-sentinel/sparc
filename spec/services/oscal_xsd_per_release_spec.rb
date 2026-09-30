# frozen_string_literal: true

require "rails_helper"
require "fileutils"
require "tmpdir"

# Owner, 2026-09-29: carry the XSDs of each release SPARC validates XML against
# — 1.1.2, 1.1.3, 1.2.2, 1.2.3 — rather than one DEFAULT_VERSION set, because
# releases are separate artifacts that can differ (the 1.1.x and 1.2.x
# element-order tables do: 338 types against 348). A document is validated
# against, and written in the element order of, the release it DECLARES. A
# release SPARC does not carry is validated against the nearest carried one in
# its line, and the result says so ("nearest carried, flagged").
RSpec.describe "OSCAL XSDs per release" do
  fixture = ->(path) { Rails.root.join("spec/fixtures/files", path).read }

  describe "OscalSchema.xsd_version_for" do
    {
      nil => OscalSchema::DEFAULT_VERSION, "" => OscalSchema::DEFAULT_VERSION,
      "1.1.2" => "1.1.2", "1.1.3" => "1.1.3", "1.2.2" => "1.2.2", "1.2.3" => "1.2.3",
      "1.1.1" => "1.1.2", "1.2.0" => "1.2.2", "1.2.1" => "1.2.2",
      "1.2.9" => "1.2.3", "1.0.0" => OscalSchema::DEFAULT_VERSION, "junk" => OscalSchema::DEFAULT_VERSION
    }.each do |declared, expected|
      it "#{declared.inspect} -> #{expected}" do
        expect(OscalSchema.xsd_version_for(declared)).to eq(expected)
      end
    end

    it "never answers a release whose XSDs are not carried" do
      %w[1.0.0 1.1.0 1.1.1 1.1.2 1.1.3 1.1.9 1.2.0 1.2.1 1.2.2 1.2.3 1.3.0].each do |v|
        expect(OscalSchema::XSD_VERSIONS).to include(OscalSchema.xsd_version_for(v))
      end
    end
  end

  describe "OscalSchemaValidationService.validate_xml" do
    def validate(model, xml, **opts) = OscalSchemaValidationService.validate_xml(model, xml, **opts)

    it "validates a NIST 1.1.2 CDEF against the 1.1.2 set, with no substitution" do
      result = validate(:component_definition, fixture.("components/example-component-definition.xml"))

      expect(result.schema_version).to eq("1.1.2")
      expect(result.declared_version).to eq("1.1.2")
      expect(result).not_to be_substituted
      expect(result).to be_valid, result.errors.first(3).inspect
    end

    it "validates a NIST 1.1.3 SSP against the 1.1.3 set" do
      result = validate(:ssp, fixture.("ssp/oscal_leveraging-example_ssp.xml"))

      expect([ result.schema_version, result.declared_version ]).to eq(%w[1.1.3 1.1.3])
      expect(result).to be_valid, result.errors.first(3).inspect
    end

    it "validates a 1.1.1 profile against 1.1.2 — the nearest carried — and flags it" do
      result = validate(:profile, fixture.("profiles/NIST_SP-800-53_rev4_MODERATE-baseline_profile.xml"))

      expect(result.declared_version).to eq("1.1.1")
      expect(result.schema_version).to eq("1.1.2")
      expect(result).to be_substituted
    end

    it "validates SPARC's own export against the default release" do
      xml = OscalExportFormatService.to_xml(
        OscalSspExportService.new(create(:ssp_document)).export_unvalidated, :ssp
      )
      result = validate(:ssp, xml)

      expect(result.schema_version).to eq(OscalSchema::DEFAULT_VERSION)
      expect(result.declared_version).to eq(OscalSchema::DEFAULT_VERSION)
    end

    it "honours an explicit version: over the document's own" do
      result = validate(:ssp, fixture.("ssp/oscal_leveraging-example_ssp.xml"), version: "1.2.2")

      expect(result.schema_version).to eq("1.2.2")
    end

    # The defect this replaces was a SILENT substitution. A carried release
    # whose files are missing must fail loudly, not borrow another set.
    it "fails, naming the missing file, when the declared release's set is absent — never borrowing another" do
      Dir.mktmpdir do |dir|
        FileUtils.cp_r(Rails.root.join("lib/oscal_xsd_schemas/v1.2.3"), dir)
        stub_const("OscalSchemaValidationService::XSD_SCHEMA_DIR", Pathname(dir))
        OscalSchemaValidationService.instance_variable_set(:@xsd_schema_cache, nil)

        result = validate(:ssp, fixture.("ssp/oscal_leveraging-example_ssp.xml"))

        expect(result).not_to be_valid
        expect(result.schema_version).to eq("1.1.3")
        expect(result.errors.join).to include("v1.1.3/oscal_ssp_schema.xsd")
      ensure
        OscalSchemaValidationService.instance_variable_set(:@xsd_schema_cache, nil)
      end
    end

    # Proves which FILES are read, not just which version is reported: plant a
    # set under v1.1.2 that rejects everything. A 1.1.2 document must now fail;
    # it could only pass if some other release's set had been read instead.
    it "reads the declared release's own files" do
      Dir.mktmpdir do |dir|
        FileUtils.cp_r(Rails.root.join("lib/oscal_xsd_schemas/v1.2.3"), dir)
        FileUtils.mkdir_p(File.join(dir, "v1.1.2"))
        File.write(File.join(dir, "v1.1.2", "oscal_component_schema.xsd"), <<~XSD)
          <?xml version="1.0" encoding="UTF-8"?>
          <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" version="1.1.2"
                     targetNamespace="urn:planted:rejects-everything" elementFormDefault="qualified">
            <xs:element name="planted" type="xs:string"/>
          </xs:schema>
        XSD
        stub_const("OscalSchemaValidationService::XSD_SCHEMA_DIR", Pathname(dir))
        OscalSchemaValidationService.instance_variable_set(:@xsd_schema_cache, nil)

        result = validate(:component_definition, fixture.("components/example-component-definition.xml"))

        expect(result).not_to be_valid
        expect(result.schema_version).to eq("1.1.2")
      ensure
        OscalSchemaValidationService.instance_variable_set(:@xsd_schema_cache, nil)
      end
    end

    it "names the substitution when a flagged document fails" do
      broken = fixture.("profiles/NIST_SP-800-53_rev4_MODERATE-baseline_profile.xml")
               .sub("</metadata>", "<not-an-oscal-element/></metadata>")

      expect { OscalSchemaValidationService.validate_xml!(:profile, broken) }
        .to raise_error(OscalValidationError, /declared 1\.1\.1, validated against 1\.1\.2/)
    end
  end

  describe "OscalJsonToXmlConverter" do
    it "writes in the element order of the release the document declares" do
      data = { "system-security-plan" => { "uuid" => SecureRandom.uuid, "metadata" => { "oscal-version" => "1.1.3" } } }

      expect(OscalJsonToXmlConverter.new(:ssp, data).oscal_version).to eq("1.1.3")
      expect(OscalJsonToXmlConverter.new(:ssp, data).element_order["_oscal_version"]).to eq("1.1.3")
    end

    it "uses the nearest carried release's order for an uncarried declaration, as validation does" do
      data = { "profile" => { "uuid" => SecureRandom.uuid, "metadata" => { "oscal-version" => "1.2.1" } } }

      expect(OscalJsonToXmlConverter.new(:profile, data).oscal_version).to eq("1.2.2")
    end

    it "uses the default release's order when nothing is declared" do
      data = { "catalog" => { "uuid" => SecureRandom.uuid, "metadata" => {} } }

      expect(OscalJsonToXmlConverter.new(:catalog, data).oscal_version).to eq(OscalSchema::DEFAULT_VERSION)
    end
  end
end
