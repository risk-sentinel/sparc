# frozen_string_literal: true

require "rails_helper"

# #1354 — what a boundary serves back out: its OSCAL documents, the CDEFs its
# components use, the boundary as an HDF system document, and ONLY the
# received versions it has accepted (with their SHA-256). Nothing from another
# boundary.
RSpec.describe ExchangeIndexService do
  let(:boundary) { create(:authorization_boundary) }
  let(:other) { create(:authorization_boundary) }

  def entries(origin = nil)
    docs = described_class.call(boundary)[:documents]
    origin ? docs.select { |d| d[:origin] == origin } : docs
  end

  def received(state, into: boundary, **attrs)
    create(:received_document, authorization_boundary: into, state: state, filename: "#{state}.json",
                               reviewed_at: Time.current, **attrs)
  end

  it "names the boundary and when the index was built" do
    index = described_class.call(boundary)
    expect(index[:authorization_boundary]).to eq(id: boundary.id, name: boundary.name)
    expect(Time.iso8601(index[:generated_at])).to be_within(5.seconds).of(Time.current)
  end

  it "lists the boundary's SSP, SAP, SAR and POA&M with their OSCAL export addresses, no SHA-256" do
    ssp = create(:ssp_document, authorization_boundary: boundary)
    sap = create(:sap_document, authorization_boundary: boundary)
    sar = create(:sar_document, authorization_boundary: boundary)
    poam = create(:poam_document, authorization_boundary: boundary)

    sparc = entries("sparc").reject { |d| d[:format] == "hdf" }

    expect(sparc.map { |d| [ d[:document_type], d[:id], d[:download_url] ] }).to contain_exactly(
      [ "ssp", ssp.id, "/api/v1/ssp_documents/#{ssp.id}/export?format=oscal" ],
      [ "assessment_plan", sap.id, "/api/v1/sap_documents/#{sap.id}/export?format=oscal" ],
      [ "assessment_results", sar.id, "/api/v1/sar_documents/#{sar.id}/export?format=oscal" ],
      [ "poam", poam.id, "/api/v1/poam_documents/#{poam.id}/export?format=oscal" ]
    )
    expect(sparc).to all(include(format: "oscal", sha256: nil))
  end

  it "lists each CDEF the boundary's components use, once" do
    cdef = create(:cdef_document)
    production = create(:boundary, authorization_boundary: boundary)
    staging = create(:boundary, authorization_boundary: boundary)
    create(:boundary_cdef_document, boundary: production, cdef_document: cdef)
    create(:boundary_cdef_document, boundary: staging, cdef_document: cdef)

    cdefs = entries("sparc").select { |d| d[:document_type] == "component_definition" }
    expect(cdefs).to match([ a_hash_including(id: cdef.id, format: "oscal",
                                           download_url: "/api/v1/cdef_documents/#{cdef.id}/export?format=oscal") ])
  end

  it "lists the boundary as an HDF system document" do
    expect(entries("sparc")).to include(
      a_hash_including(format: "hdf", document_type: "system", id: boundary.id, sha256: nil,
                       download_url: "/api/v1/authorization_boundaries/#{boundary.id}/hdf_system")
    )
  end

  it "lists only the accepted received versions, each with its SHA-256 and download address" do
    accepted = received("accepted", fedramp_id: "FR2400000001")
    %w[pending_review responded rejected superseded invalid].each { |state| received(state) }

    list = entries("received")

    expect(list.size).to eq(1)
    expect(list.first).to include(
      id: accepted.id, format: "fedramp", document_type: "vulnerability-detail-report", name: "accepted.json",
      fedramp_id: "FR2400000001", sha256: accepted.sha256, received_at: accepted.received_at.utc.iso8601,
      download_url: "/api/v1/authorization_boundaries/#{boundary.id}/received_documents/#{accepted.id}/file"
    )
  end

  it "lists nothing of another boundary's" do
    create(:ssp_document, authorization_boundary: other)
    create(:sar_document, authorization_boundary: other)
    cdef = create(:cdef_document)
    create(:boundary_cdef_document, boundary: create(:boundary, authorization_boundary: other), cdef_document: cdef)
    received("accepted", into: other)

    docs = entries

    expect(docs.map { |d| d[:origin] }).to eq([ "sparc" ])
    expect(docs.first).to include(format: "hdf", id: boundary.id)
  end
end
