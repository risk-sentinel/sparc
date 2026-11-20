# frozen_string_literal: true

require "rails_helper"

# #1354 / #1384 — one validator for the formats SPARC exchanges with other
# systems. Each format is checked against SPARC's pinned schema, and FedRAMP
# and OSCAL JSON also for completeness: a required field must be filled in.
RSpec.describe DocumentValidationService do
  def call(doc, **opts) = described_class.call(doc.is_a?(String) ? doc : JSON.generate(doc), **opts)
  def checks(result) = result.errors.map { |e| [ e[:check], e[:pointer] ] }

  let(:cpo_uri) { "https://fedramp.gov/schemas/fedramp-certification-package-overview-schema-2026-06-24.json" }
  let(:vdr) do
    {
      "certificationPackageOverviewUri" => "https://provider.example/package/cpo.json",
      "reportPeriod" => { "from" => "2026-10-01T00:00:00Z", "to" => "2026-10-31T23:59:59Z" },
      "vulnerabilities" => [
        { "providerTrackingId" => "VULN-1",
          "detection" => { "detectedAt" => "2026-10-02T10:00:00Z", "detectionSource" => "scanner" },
          "vulnerabilityDescription" => "Outdated library" }
      ]
    }
  end

  describe "FedRAMP package JSON" do
    it "recognizes a document by its required fields and accepts a complete one" do
      result = call(vdr)
      expect(result.format).to eq("fedramp")
      expect(result.document_type).to eq("vulnerability-detail-report")
      expect(result).to be_valid
      expect(result.schema).to include(name: "fedramp-vulnerability-detail-report-schema-2026-06-24.json",
                                        version: "0.1.1")
      expect(result.schema[:sha256]).to match(/\A\h{64}\z/)
    end

    it "reports a required field that is present but blank (FedRAMP's schemas would accept it)" do
      vdr["vulnerabilities"][0]["vulnerabilityDescription"] = "   "
      result = call(vdr)
      expect(result).not_to be_valid
      expect(checks(result)).to eq([ [ "completeness", "/vulnerabilities/0/vulnerabilityDescription" ] ])
    end

    it "reports a schema error with its JSON pointer" do
      vdr["reportPeriod"]["from"] = "October"
      result = call(vdr)
      expect(checks(result)).to include([ "schema", "/reportPeriod/from" ])
    end

    it "warns about optional fields left empty, without making the document invalid" do
      result = call(vdr)
      expect(result.warnings).to include(a_hash_including(pointer: "/vulnerabilities/0/finalDisposition"))
      expect(result.warnings_total).to be >= result.warnings.size
      expect(result).to be_valid
    end

    it "uses the schema the document names in $schema" do
      result = call({ "$schema" => cpo_uri, "serviceIdentification" => {} })
      expect(result.document_type).to eq("certification-package-overview")
      expect(checks(result)).to include([ "schema", "" ])
    end

    it "refuses a $schema SPARC does not carry" do
      expect { call({ "$schema" => "https://fedramp.gov/schemas/fedramp-nothing-schema-2026-06-24.json" }) }
        .to raise_error(described_class::Error, /not a FedRAMP schema SPARC carries/)
    end

    it "refuses a document_type that contradicts $schema" do
      expect { call({ "$schema" => cpo_uri }, document_type: "incident-report") }
        .to raise_error(described_class::Error, /does not match/)
    end

    it "takes the caller's document_type when the document does not say" do
      result = call({ "certificationPackageOverviewUri" => "https://x.example/cpo.json" },
                    format: "fedramp", document_type: "incident-report")
      expect(result.document_type).to eq("incident-report")
      expect(result).not_to be_valid
    end

    it "does not guess between schemas the document fits equally" do
      expect { call({ "certificationPackageOverviewUri" => "https://x.example/cpo.json" }, format: "fedramp") }
        .to raise_error(described_class::Error, /Could not tell which FedRAMP document/)
    end
  end

  describe "OSCAL" do
    let(:ssp) { Rails.root.join("samples/nist-traditional-demo/ssp-acme-cloud.json").read }

    it "validates JSON against the OSCAL schema and for completeness" do
      result = call(ssp)
      expect(result.format).to eq("oscal")
      expect(result.document_type).to eq("ssp")
      expect(result).to be_valid
    end

    it "reports a blank required OSCAL field" do
      doc = JSON.parse(ssp)
      doc["system-security-plan"]["metadata"]["title"] = " "
      result = call(doc)
      expect(checks(result)).to include([ "completeness", "/system-security-plan/metadata/title" ])
    end

    it "accepts OSCAL's include-all: {} as a complete answer" do
      sar = Rails.root.join("samples/nist-traditional-demo/sar-acme-cloud.json").read
      expect(sar).to include('"include-all": {}')
      expect(call(sar)).to be_valid
    end

    it "validates OSCAL XML against the XSD" do
      result = call(Rails.root.join("samples/ato-package-demo/cdef-example.xml").read)
      expect(result.format).to eq("oscal")
      expect(result.document_type).to eq("component_definition")
      expect(result).to be_valid
    end
  end

  describe "HDF" do
    let(:hdf) { Rails.root.join("spec/fixtures/files/hdf/sample-results.hdf.json").read }

    it "validates results with the pinned hdf CLI" do
      result = call(hdf)
      expect(result.format).to eq("hdf")
      expect(result.schema[:validator]).to start_with("hdf ")
      expect(result.errors).to eq([])
    end

    it "reports what hdf validate rejects" do
      result = call({ "profiles" => "not a list" }, format: "hdf")
      expect(result).not_to be_valid
      expect(result.errors.first[:check]).to eq("schema")
    end
  end

  describe "XCCDF" do
    it "validates XCCDF 1.2 results against the pinned schema" do
      result = call(Rails.root.join("spec/fixtures/files/hdf/scap-xccdf-results-source.xml").read)
      expect(result.format).to eq("xccdf")
      expect(result.schema).to include(name: "xccdf_1.2.xsd", version: "1.2")
      expect(result).to be_valid
    end

    it "refuses JSON named as XCCDF" do
      expect { call({}, format: "xccdf") }.to raise_error(described_class::Error, /XCCDF is XML/)
    end
  end

  describe "input it cannot check" do
    it "refuses an empty document" do
      expect { described_class.call("  ") }.to raise_error(described_class::Error, /Empty/)
    end

    it "refuses a document over the upload limit" do
      allow(SparcConfig).to receive(:max_upload_bytes).and_return(10)
      expect { call(vdr) }.to raise_error(described_class::Error, /upload limit/)
    end

    it "refuses text that is neither JSON nor XML" do
      expect { described_class.call("hello") }.to raise_error(described_class::Error, /Not valid JSON/)
    end

    it "refuses an unknown format" do
      expect { call(vdr, format: "csv") }.to raise_error(described_class::Error, /Unknown format/)
    end

    it "refuses XML with a DOCTYPE entity (XmlSecurity)" do
      xxe = %(<?xml version="1.0"?><!DOCTYPE x [<!ENTITY e SYSTEM "file:///etc/passwd">]><x>&e;</x>)
      expect { described_class.call(xxe) }.to raise_error(StandardError)
    end
  end
end
