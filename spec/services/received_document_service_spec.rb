# frozen_string_literal: true

require "rails_helper"

# #1354 — receiving one document into a boundary: validate, store the exact
# bytes once, compare with the version in effect, and leave every new version
# for a person. Owner, 2026-11-20: only a byte-identical re-delivery needs no
# person (it is recorded as unchanged); any other change waits for a
# reviewer, an improvement included. An invalid document is stored with its
# errors and never takes effect.
RSpec.describe ReceivedDocumentService do
  let(:boundary) { create(:authorization_boundary) }
  let(:uploader) { create(:user) }
  let(:admin) { create(:user, :admin) }

  def vdr(to: "2026-10-31T23:59:59Z", vulnerabilities: [], **extra)
    { "certificationPackageOverviewUri" => "https://provider.example/package/cpo.json",
      "reportPeriod" => { "from" => "2026-10-01T00:00:00Z", "to" => to },
      "vulnerabilities" => vulnerabilities }.merge(extra).to_json
  end

  def vulnerability(id = "VULN-1", **extra)
    { "providerTrackingId" => id,
      "detection" => { "detectedAt" => "2026-10-02T10:00:00Z", "detectionSource" => "scanner" },
      "vulnerabilityDescription" => "Outdated library" }.merge(extra.transform_keys(&:to_s))
  end

  def deliver(bytes = vdr, into: boundary, **opts)
    described_class.call(boundary: into, bytes: bytes, source: opts.delete(:source) || "upload",
                         received_by: opts.key?(:received_by) ? opts.delete(:received_by) : uploader,
                         filename: "vdr.json", content_type: "application/json", **opts)
  end

  def accept(doc) = ReceivedDocumentReviewService.accept(doc, user: admin)

  describe "a valid upload" do
    it "is stored for review with what arrived, the first version of its stream" do
      outcome = deliver
      doc = outcome.document

      expect(outcome).to be_stored
      expect(doc).to have_attributes(state: "pending_review", valid_document: true, source: "upload",
                                     format: "fedramp", document_type: "vulnerability-detail-report",
                                     sha256: Digest::SHA256.hexdigest(vdr), byte_size: vdr.bytesize,
                                     received_by: uploader, auto_accepted: false, review_action: nil)
      expect(doc.delta).to include("first_version" => true, "identical" => false, "auto_acceptable" => false)
      expect(doc.validation).to include("valid" => true, "format" => "fedramp")
    end

    it "carries its delta against the version in effect: regressions counted for the reviewer" do
      accept(deliver.document)

      doc = deliver(vdr(vulnerabilities: [ vulnerability ])).document

      expect(doc.state).to eq("pending_review")
      expect(doc.delta["first_version"]).to be(false)
      expect(doc.regression_count).to be >= 1
      expect(doc.delta_changes).to include(a_hash_including("kind" => "regression"))
    end

    it "waits for a person even when every change is an improvement (owner rule)" do
      accept(deliver(vdr(vulnerabilities: [ vulnerability(currentRating: 4) ])).document)

      doc = deliver(vdr(vulnerabilities: [ vulnerability(currentRating: 1) ])).document

      expect(doc.improvement_count).to be >= 1
      expect(doc.regression_count).to eq(0)
      expect(doc).to have_attributes(state: "pending_review", auto_accepted: false, review_action: nil)
    end

    it "waits for a person when the bytes differ and nothing in the document changed" do
      first = deliver.document
      accept(first)
      reformatted = JSON.pretty_generate(JSON.parse(vdr))

      outcome = deliver(reformatted)

      expect(outcome).to be_stored
      expect(outcome.document.id).not_to eq(first.id)
      expect(outcome.document.delta).to include("identical" => false, "auto_acceptable" => false)
      expect(outcome.document.state).to eq("pending_review")
      expect(first.reload.state).to eq("accepted")
    end

    it "compares with the version in effect, not with a newer one still pending" do
      accepted = deliver.document
      accept(accepted)
      deliver(vdr(vulnerabilities: [ vulnerability ]))

      doc = deliver(vdr(to: "2026-10-31T23:00:00Z")).document

      expect(doc.delta_changes.map { |c| c["summary"] }.join).not_to match(/VULN-1/)
    end
  end

  describe "a byte-identical re-delivery" do
    %w[pending_review accepted responded rejected superseded invalid].each do |state|
      it "is recorded as unchanged and stores nothing when the stream's copy is #{state}" do
        first = deliver.document
        first.update_columns(state: state)

        outcome = nil
        expect { outcome = deliver }.not_to change(ReceivedDocument, :count)
        expect(outcome).to be_unchanged
        expect(outcome.document).to eq(first)
        expect(first.reload.state).to eq(state)
      end
    end

    it "leaves the accepted version in effect and writes no stored audit event" do
      first = deliver.document
      accept(first)

      expect { deliver }.not_to(change { AuditEvent.where(action: "received_document_stored").count })
      expect(first.reload.state).to eq("accepted")
    end

    it "is a new version in another boundary's stream" do
      deliver
      outcome = deliver(into: create(:authorization_boundary))
      expect(outcome).to be_stored
    end
  end

  describe "an invalid document" do
    it "is stored as invalid with its validation errors, and never accepted" do
      accept(deliver.document)

      doc = deliver(vdr(to: " ")).document

      expect(doc).to have_attributes(state: "invalid", valid_document: false, auto_accepted: false)
      expect(doc.validation_errors).to include(a_hash_including("check" => "completeness", "pointer" => "/reportPeriod/to"))
      expect(doc.delta).to eq({})
      expect(doc.regression_count + doc.improvement_count + doc.neutral_count).to eq(0)
      expect(doc.bytes).to eq(vdr(to: " ").b)
    end

    it "with a declared format SPARC cannot read (a pull) is stored invalid with a 'readable' error" do
      doc = deliver("this is not json", format: "fedramp", document_type: "vulnerability-detail-report",
                                        received_by: nil, source: "pull").document

      expect(doc).to have_attributes(state: "invalid", valid_document: false, format: "fedramp",
                                     document_type: "vulnerability-detail-report")
      expect(doc.validation_errors).to contain_exactly(a_hash_including("check" => "readable", "pointer" => ""))
      expect(doc.validation_errors.first["message"]).to match(/Not valid JSON/)
    end

    it "with no declared format and not any format SPARC reads is refused, and nothing is stored" do
      expect { deliver("this is not json") }
        .to raise_error(described_class::Error, /Not a FedRAMP, OSCAL, HDF or XCCDF document SPARC can read/)
      expect(ReceivedDocument.count).to eq(0)
    end
  end

  describe "refusals" do
    it "refuses an empty or whitespace-only document" do
      expect { deliver("") }.to raise_error(described_class::Error, "Empty document")
      expect { deliver("  \n ") }.to raise_error(described_class::Error, "Empty document")
      expect(ReceivedDocument.count).to eq(0)
    end

    it "refuses a document over the upload limit" do
      allow(SparcConfig).to receive(:max_upload_bytes).and_return(vdr.bytesize - 1)
      expect { deliver }.to raise_error(described_class::Error, /exceeds the #{vdr.bytesize - 1}-byte upload limit/)
      expect(ReceivedDocument.count).to eq(0)
    end

    it "takes a document exactly at the limit" do
      allow(SparcConfig).to receive(:max_upload_bytes).and_return(vdr.bytesize)
      expect(deliver).to be_stored
    end
  end

  describe "streams" do
    let(:connection) { create(:exchange_connection, authorization_boundary: boundary, fedramp_id: "FR2400000001") }
    let(:source) { create(:exchange_document_source, exchange_connection: connection) }

    it "keys a pull by its document address" do
      doc = described_class.call(boundary: boundary, bytes: vdr, source: "pull", document_source: source,
                                 format: "fedramp").document
      expect(doc.stream_key).to eq("pull:source:#{source.id}")
      expect(doc).to have_attributes(exchange_document_source: source, exchange_connection: connection, source: "pull")
    end

    it "keys an upload by boundary, format, document type and FedRAMP ID" do
      doc = deliver.document
      expect(doc.stream_key).to eq("upload:boundary:#{boundary.id}:fedramp:vulnerability-detail-report:-")

      with_connection = deliver(vdr(to: "2026-10-30T00:00:00Z"), connection: connection).document
      expect(with_connection.stream_key).to eq("upload:boundary:#{boundary.id}:fedramp:vulnerability-detail-report:FR2400000001")
    end

    it "keeps the same bytes pulled and uploaded in separate streams" do
      deliver
      pulled = described_class.call(boundary: boundary, bytes: vdr, source: "pull", document_source: source,
                                    format: "fedramp")
      expect(pulled).to be_stored
    end

    it "keeps each document type in its own stream" do
      vdr_doc = deliver.document
      cpo = { "$schema" => "https://fedramp.gov/schemas/fedramp-certification-package-overview-schema-2026-06-24.json",
              "serviceIdentification" => {} }.to_json
      cpo_doc = deliver(cpo).document
      expect(cpo_doc.stream_key).not_to eq(vdr_doc.stream_key)
    end
  end

  describe "FedRAMP ID" do
    it "comes from the connection" do
      connection = create(:exchange_connection, authorization_boundary: boundary, fedramp_id: "FR2400000009")
      expect(deliver(connection: connection).document.fedramp_id).to eq("FR2400000009")
    end

    it "comes from a FedRAMP document's own package ID when there is no connection" do
      cpo = { "$schema" => "https://fedramp.gov/schemas/fedramp-certification-package-overview-schema-2026-06-24.json",
              "serviceIdentification" => { "fedRampPackageId" => "FR2401234567" } }.to_json
      expect(deliver(cpo).document.fedramp_id).to eq("FR2401234567")
    end

    it "is nil when neither names one" do
      expect(deliver.document.fedramp_id).to be_nil
    end

    # Found by this spec: a pulled FedRAMP document that is JSON but not an
    # object (or whose serviceIdentification is not one) raised TypeError /
    # NoMethodError while reading the package ID, so the version was never
    # stored and the pull crashed instead of recording an invalid version.
    [ "[1, 2]", "\"a string\"", '{"serviceIdentification": "x"}',
      '{"serviceIdentification": {"fedRampPackageId": 7}}' ].each do |body|
      it "is nil, and the version still stored invalid, for #{body}" do
        doc = deliver(body, format: "fedramp", document_type: "certification-package-overview", source: "pull",
                            received_by: nil).document
        expect(doc).to have_attributes(state: "invalid", fedramp_id: nil)
      end
    end
  end

  it "audits the stored version with its SHA-256 and never its content" do
    doc = deliver.document

    event = AuditEvent.find_by!(action: "received_document_stored")
    expect(event).to have_attributes(user_id: uploader.id, subject_type: "ReceivedDocument", subject_id: doc.id)
    expect(event.metadata).to include("authorization_boundary_id" => boundary.id, "source" => "upload",
                                      "format" => "fedramp", "sha256" => doc.sha256, "state" => "pending_review")
    expect(event.metadata.to_json).not_to include("certificationPackageOverviewUri")
    expect(event.metadata.to_json).not_to include("reportPeriod")
  end

  it "attaches the exact bytes it received, with the filename and type" do
    bytes = vdr(note: "café ✓").gsub(",", ",\r\n")
    doc = deliver(bytes).document

    expect(doc.bytes).to eq(bytes.b)
    expect(Digest::SHA256.hexdigest(doc.bytes)).to eq(doc.sha256)
    expect(doc.file.filename.to_s).to eq("vdr.json")
    expect(doc.file.content_type).to eq("application/json")
  end
end
