# frozen_string_literal: true

require "rails_helper"

# #618 — the server-side stuck-document reaper.
RSpec.describe StuckDocumentReaperJob, type: :job do
  let(:threshold) { SparcConfig.document_reap_minutes } # default 10

  def backdate!(doc, minutes_ago)
    doc.update_column(:updated_at, minutes_ago.minutes.ago)
  end

  def attach_file!(doc)
    doc.file.attach(io: StringIO.new("{}"), filename: "x.json", content_type: "application/json")
  end

  describe "#perform" do
    it "resolves a fileless pending document to completed (never needed parsing)" do
      doc = create(:cdef_document, status: "pending")
      backdate!(doc, threshold + 5)

      described_class.perform_now

      expect(doc.reload.status).to eq("completed")
    end

    it "marks a file-bearing stalled document failed when no live job exists" do
      doc = create(:cdef_document, status: "pending")
      attach_file!(doc)
      backdate!(doc, threshold + 5)
      allow_any_instance_of(described_class).to receive(:live_document_keys).and_return(Set.new)

      described_class.perform_now

      doc.reload
      expect(doc.status).to eq("failed")
      expect(doc.error_message).to be_present
    end

    it "notifies the uploader when it reaps their document (SMTP on)" do
      allow(SparcConfig).to receive(:enable_smtp?).and_return(true)
      uploader = create(:user, email: "uploader@sparc.local")
      doc = create(:cdef_document, status: "pending", uploaded_by: uploader)
      attach_file!(doc)
      backdate!(doc, threshold + 5)
      allow_any_instance_of(described_class).to receive(:live_document_keys).and_return(Set.new)

      expect {
        described_class.perform_now
      }.to have_enqueued_mail(DocumentParseMailer, :parse_failed)
    end

    it "does not enqueue a notification when SMTP is disabled" do
      allow(SparcConfig).to receive(:enable_smtp?).and_return(false)
      doc = create(:cdef_document, status: "pending", uploaded_by: create(:user))
      attach_file!(doc)
      backdate!(doc, threshold + 5)
      allow_any_instance_of(described_class).to receive(:live_document_keys).and_return(Set.new)

      expect {
        described_class.perform_now
      }.not_to have_enqueued_mail(DocumentParseMailer, :parse_failed)
    end

    it "leaves a file-bearing document alone while a live job is still working it" do
      doc = create(:cdef_document, status: "processing")
      attach_file!(doc)
      backdate!(doc, threshold + 5)
      allow_any_instance_of(described_class)
        .to receive(:live_document_keys).and_return(Set[[ "cdef", doc.id ]])

      described_class.perform_now

      expect(doc.reload.status).to eq("processing")
    end

    it "does not touch documents updated within the threshold" do
      doc = create(:cdef_document, status: "pending")
      attach_file!(doc)
      backdate!(doc, 1) # well within the threshold
      allow_any_instance_of(described_class).to receive(:live_document_keys).and_return(Set.new)

      described_class.perform_now

      expect(doc.reload.status).to eq("pending")
    end
  end
end
