# frozen_string_literal: true

require "rails_helper"

# #1390 — FedrampSecurityDecisionRecordService writes the SDR from the
# boundary's statements and SSP, and lists what FedRAMP still requires.
RSpec.describe FedrampSecurityDecisionRecordService do
  let(:boundary) do
    create(:authorization_boundary, fedramp_enabled: true, fedramp_package_overview_uri: "https://trust.example/cpo.json",
                                    fedramp_package: { certification_type: "Rev5", certification_path: "Agency",
                                                       certification_class: "B" })
  end
  let(:ssp) { SspDocument.create!(name: "SDR SSP", authorization_boundary: boundary) }
  let(:service) { described_class.new(boundary.reload) }

  def statement(control, status:, prose: nil, params: [])
    control.ssp_control_statements.create!(uuid: SecureRandom.uuid, statement_id: "#{control.control_id}_smt.#{SecureRandom.hex(2)}",
                                           implementation_status: status, implementation_prose: prose,
                                           set_parameters_data: params)
  end

  def record(kind, rule_id, **attributes)
    FedrampStatementService.new(boundary).record(kind: kind, rule_id: rule_id, user: nil, attributes: attributes)
  end

  def schema_errors(doc) = DocumentValidationService.call(JSON.generate(doc), format: "fedramp").errors

  it "writes a valid record with nothing answered yet, naming the overview" do
    doc = described_class.call(boundary)
    expect(doc["certificationPackageOverviewUri"]).to eq("https://trust.example/cpo.json")
    expect(doc["fedRampRequirements"]).to eq([])
    expect(doc["metadata"]).to include("version" => "0", "updateSource" => a_string_including("SPARC #{SparcConfig::VERSION}"))
    expect(schema_errors(doc)).to eq([])
  end

  it "carries the answered rules and KSIs, one statement per paragraph" do
    record("frr", "SDR-CSO-FRR", status: "Implemented", implementation: "SPARC writes it.\n\nNightly.", validation: "Checked.")
    record("ksi", "KSI-CED-RAT", status: "Partially Implemented", tests: [ "quarterly" ],
                                 evidence: [ { evidence_type: "Report", description: "LMS", location: "https://e.example/lms" } ])
    doc = service.call
    expect(doc["fedRampRequirements"].sole).to eq("frrID" => "SDR-CSO-FRR", "frrImplementationStatus" => "Implemented",
                                                  "frrImplementation" => [ "SPARC writes it.", "Nightly." ],
                                                  "frrValidation" => [ "Checked." ])
    ksi = doc["keySecurityIndicators"].sole
    expect(ksi).to include("ksiId" => "KSI-CED-RAT", "ksiTests" => [ "quarterly" ], "ksiImplementation" => [])
    expect(ksi["ksiEvidence"]).to eq([ { "evidenceType" => "Report", "evidenceDescription" => "LMS",
                                         "evidenceLocation" => "https://e.example/lms" } ])
    expect(doc["metadata"]["version"]).to eq("2")
    expect(schema_errors(doc)).to eq([])
  end

  it "leaves out an answer to a rule that no longer applies to the profile" do
    record("frr", "FRC-APS-ATO", status: "Implemented")
    boundary.update!(fedramp_package: { certification_path: "Program" })
    expect(described_class.new(boundary.reload).call["fedRampRequirements"]).to eq([])
  end

  it "writes the SSP's controls with their status, prose and parameters, filling FedRAMP's values for Rev5" do
    ac2 = ssp.ssp_controls.create!(control_id: "ac-2", title: "Account Management")
    statement(ac2, status: "implemented", prose: "SSO only.", params: [ { "param-id" => "ac-02_odp.10", "values" => [ "90 days" ] } ])
    ac61 = ssp.ssp_controls.create!(control_id: "ac-6.1", title: "Authorize Access")
    statement(ac61, status: "implemented")
    statement(ac61, status: "planned")
    na = ssp.ssp_controls.create!(control_id: "ac-8", title: "Banner")
    statement(na, status: "not-applicable")

    controls = service.call["securityControls"].index_by { |c| c["controlId"] }
    expect(controls["AC-2"]).to eq("controlId" => "AC-2", "controlImplementationStatus" => "Implemented",
                                   "controlImplementationDescription" => "SSO only.",
                                   "parameterValues" => [ { "parameterId" => "ac-02_odp.10", "parameterValue" => "90 days" } ])
    expect(controls["AC-6(1)"]["controlImplementationStatus"]).to eq("Partially Implemented")
    expect(controls["AC-6(1)"]["parameterValues"].map { |p| p["parameterId"] }).to include("ac-06.01_odp.02")
    expect(controls["AC-8"]).not_to have_key("controlImplementationStatus")
  end

  it "writes each component protocol and port range, with encryption and purpose when recorded" do
    ssp.ssp_components.create!(title: "Web", description: "Web tier", component_type: "software", uuid: SecureRandom.uuid,
                               props_data: [ { "name" => "encryption", "value" => "TLS 1.3" } ],
                               protocols_data: [ { "uuid" => SecureRandom.uuid, "name" => "https", "title" => "HTTPS",
                                                   "port-ranges" => [ { "start" => 443, "end" => 443, "transport" => "TCP" },
                                                                      { "start" => 8000, "end" => 8010, "transport" => "TCP" } ] } ])
    expect(service.call["portsAndProtocols"]).to eq([
      { "serviceName" => "Web: HTTPS", "portNumber" => "443", "transportProtocol" => "TCP", "encryption" => "TLS 1.3", "purpose" => "Web tier" },
      { "serviceName" => "Web: HTTPS", "portNumber" => "8000-8010", "transportProtocol" => "TCP", "encryption" => "TLS 1.3", "purpose" => "Web tier" }
    ])
  end

  it "raises MissingPackageOverview without an overview address" do
    boundary.update!(fedramp_package_overview_uri: nil)
    expect { service.call }.to raise_error(FedrampVulnerabilityReportService::MissingPackageOverview)
  end

  it "raises InvalidReport, never returning the record, when its own output fails validation" do
    invalid = DocumentValidationService::Result.new(format: "fedramp", document_type: "x", schema: {}, warnings: [],
                                                    warnings_total: 0, errors: [ { check: "schema", pointer: "/metadata", message: "bad" } ])
    allow(DocumentValidationService).to receive(:call).and_return(invalid)
    expect { service.call }.to raise_error(FedrampVulnerabilityReportService::InvalidReport)
  end

  describe "#gaps" do
    it "lists unanswered rules, the Rev5 baseline controls missing from the SSP, and ports and protocols" do
      ssp
      gaps = service.gaps
      expect(gaps).to include(a_string_matching(/\A\d+ FedRAMP rules not answered: /),
                              a_string_matching(/\A\d+ Rev5 Class B baseline controls not in the SSP: ac-1/),
                              "No ports and protocols recorded on the SSP's components")
      expect(gaps.join).not_to include("Key Security Indicator")
    end

    it "asks for an SSP and the KSIs for 20x" do
      boundary.update!(fedramp_package: { certification_type: "20x", certification_path: "Program" })
      gaps = described_class.new(boundary.reload).gaps
      expect(gaps).to include("Link an SSP to the boundary",
                              a_string_matching(/\A46 Key Security Indicators not answered \(required for 20x\)/))
      expect(gaps.join).not_to include("baseline")
    end

    it "asks for the profile first" do
      boundary.update!(fedramp_package: { certification_class: "" })
      expect(described_class.new(boundary.reload).gaps).to include("Set the FedRAMP certification type, path and class")
    end
  end
end
