# frozen_string_literal: true

require "rails_helper"

# #1390 — FedrampPackageOverviewService writes FRC-CSO-PKG from the boundary.
RSpec.describe FedrampPackageOverviewService do
  let(:boundary) { create(:authorization_boundary, :fedramp_overview_ready) }

  it "writes an overview that passes FedRAMP's schema and the completeness check" do
    doc = described_class.call(boundary)
    expect(doc["$schema"]).to end_with("fedramp-certification-package-overview-schema-2026-06-24.json")
    result = DocumentValidationService.call(JSON.generate(doc), format: "fedramp")
    expect(result.document_type).to eq("certification-package-overview")
    expect(result.errors).to eq([])
  end

  it "names no overview address, so it needs none" do
    expect(boundary.fedramp_package_overview_uri).to be_nil
    expect(described_class.call(boundary)).not_to have_key("certificationPackageOverviewUri")
  end

  it "writes every optional field it records, still valid" do
    boundary.update!(fedramp_package: {
      uei_number: "ABCDEFGHJK12", business_categories: [ "Analytics", "Storage" ], next_ocr_date: "2027-01-15",
      trust_center_url: "https://trust.example", trust_center_description: "Our trust center",
      trust_center_authentication_required: "true", trust_center_access_instructions: "Request access by email."
    })
    doc = described_class.call(boundary)
    expect(doc["serviceProperties"]).to include("businessCategory" => %w[Analytics Storage],
                                                "nextOngoingCertificationReportDate" => "2027-01-15")
    expect(DocumentValidationService.call(JSON.generate(doc), format: "fedramp").errors).to eq([])
  end

  it "refuses, listing what is missing, when the boundary lacks a required field or contact" do
    boundary.update!(fedramp_package: { logo: "" }, fedramp_contacts: boundary.fedramp_contacts.first(1))
    expect { described_class.call(boundary) }
      .to raise_error(described_class::Incomplete, /Missing: Logo address, a Sales contact\./)
  end

  it "raises InvalidReport, never returning the document, when its own output fails validation" do
    invalid = DocumentValidationService::Result.new(
      format: "fedramp", document_type: "x", schema: {}, warnings: [], warnings_total: 0,
      errors: [ { check: "schema", pointer: "/serviceIdentification", message: "is bad" } ]
    )
    allow(DocumentValidationService).to receive(:call).and_return(invalid)
    expect { described_class.call(boundary) }.to raise_error(FedrampVulnerabilityReportService::InvalidReport) { |e|
      expect(e.document_type).to eq("certification-package-overview")
    }
  end
end
