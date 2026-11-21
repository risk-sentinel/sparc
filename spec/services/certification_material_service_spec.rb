# frozen_string_literal: true

require "rails_helper"

# #1354 — the materials behind a Class A certification (FRC-CLA-EAM): kept by
# SHA-256 on the connection's boundary, reviewed like any received document,
# never schema-checked and never served back out.
RSpec.describe CertificationMaterialService do
  let(:uploader) { create(:user) }
  let(:connection) { create(:exchange_connection, certification_class: "A", fedramp_id: "FR2400000001") }
  let(:pdf) { "%PDF-1.7\n% SOC 2 Type II report\n" }

  def add(kind: "soc2_report", bytes: pdf, on: connection)
    described_class.call(connection: on, kind: kind, bytes: bytes, filename: "soc2.pdf",
                         content_type: "application/pdf", received_by: uploader)
  end

  it "stores the file, unchecked, pending review, in a stream per kind of material" do
    outcome = add

    expect(outcome).to be_stored
    expect(outcome.document).to have_attributes(
      format: ReceivedDocument::MATERIAL_FORMAT, document_type: "soc2_report", state: "pending_review",
      valid_document: true, source: "upload", exchange_connection: connection, fedramp_id: "FR2400000001",
      authorization_boundary: connection.authorization_boundary, received_by: uploader,
      sha256: Digest::SHA256.hexdigest(pdf), content_type: "application/pdf",
      stream_key: "class_a:connection:#{connection.id}:soc2_report"
    )
    expect(outcome.document.validation).to include("checked" => false)
    expect(outcome.document.bytes).to eq(pdf)
    expect(AuditEvent.find_by!(action: "certification_material_stored").metadata).to include("kind" => "soc2_report")
  end

  it "keeps a file once: the same bytes again are unchanged" do
    first = add.document

    again = add
    expect(again).to be_unchanged
    expect(again.document).to eq(first)
  end

  it "lets a reviewer accept it, and a newer one of the same kind supersede it, but never its uploader" do
    first = add.document
    reviewer = create(:user)

    expect { ReceivedDocumentReviewService.accept(first, user: uploader) }
      .to raise_error(ReceivedDocumentReviewService::SeparationOfDutiesError)
    ReceivedDocumentReviewService.accept(first, user: reviewer)

    second = add(bytes: "#{pdf}v2").document
    ReceivedDocumentReviewService.accept(second, user: reviewer)
    expect(first.reload.state).to eq("superseded")

    letter = add(kind: "bridge_letter", bytes: "%PDF letter").document
    ReceivedDocumentReviewService.accept(letter, user: reviewer)
    expect(second.reload.state).to eq("accepted")
  end

  it "is never listed in the boundary's exchange index, even when accepted" do
    doc = add.document
    doc.update!(state: "accepted")

    ids = ExchangeIndexService.call(connection.authorization_boundary)[:documents].select { |d| d[:origin] == "received" }
    expect(ids).to be_empty
  end

  it "refuses a connection that is not Class A, an unknown kind, an empty file, and one over the limit" do
    expect { add(on: create(:exchange_connection, certification_class: "B")) }
      .to raise_error(described_class::Error, /only for a Class A/)
    expect { add(kind: "iso27001") }.to raise_error(described_class::Error, /what kind/)
    expect { add(bytes: "") }.to raise_error(described_class::Error, /Empty/)

    allow(SparcConfig).to receive(:max_upload_bytes).and_return(4)
    expect { add }.to raise_error(described_class::Error, /upload limit/)
  end

  it "cannot be smuggled in through the document upload path" do
    expect do
      ReceivedDocumentService.call(boundary: connection.authorization_boundary, bytes: pdf, source: "upload",
                                   format: ReceivedDocument::MATERIAL_FORMAT)
    end.to raise_error(ReceivedDocumentService::Error, /added on the connection/)
  end
end
