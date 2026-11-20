# frozen_string_literal: true

require "rails_helper"

# #1354 — a reviewer decides each received version: accept (in effect for its
# stream; the previous accepted version superseded; HDF into the boundary's
# findings), respond or reject (each with a note). Separation of duties
# (owner, 2026-11-20): the uploader cannot decide their own upload; only the
# break-glass administrator (`user.admin?`) is exempt (AC-5).
RSpec.describe ReceivedDocumentReviewService do
  let(:boundary) { create(:authorization_boundary) }
  let(:uploader) { create(:user) }
  let(:reviewer) { create(:user) }
  let(:break_glass) { create(:user, :admin) }

  def vdr(to: "2026-10-31T23:59:59Z")
    { "certificationPackageOverviewUri" => "https://provider.example/package/cpo.json",
      "reportPeriod" => { "from" => "2026-10-01T00:00:00Z", "to" => to }, "vulnerabilities" => [] }.to_json
  end

  def stored(bytes = vdr, by: uploader, into: boundary, **opts)
    ReceivedDocumentService.call(boundary: into, bytes: bytes, source: opts.delete(:source) || "upload",
                                 received_by: by, filename: "doc.json", **opts).document
  end

  def audits(action) = AuditEvent.where(action: action)

  describe "accept" do
    it "puts the version in effect and records who decided, when and why" do
      doc = stored
      described_class.accept(doc, user: reviewer, note: "Looks right.")

      expect(doc.reload).to have_attributes(state: "accepted", review_action: "accept", review_note: "Looks right.",
                                            reviewed_by: reviewer)
      expect(doc.reviewed_at).to be_within(5.seconds).of(Time.current)
      expect(doc).to be_in_effect
    end

    it "supersedes the version in effect in the same stream, and no other stream's" do
      first = stored
      other_stream = stored(vdr, into: create(:authorization_boundary))
      described_class.accept(first, user: reviewer)
      described_class.accept(other_stream, user: reviewer)

      second = stored(vdr(to: "2026-10-31T23:00:00Z"))
      described_class.accept(second, user: reviewer)

      expect(first.reload.state).to eq("superseded")
      expect(second.reload.state).to eq("accepted")
      expect(other_stream.reload.state).to eq("accepted")
      expect(ReceivedDocument.in_effect.where(stream_key: second.stream_key)).to eq([ second ])
    end

    it "accepts a version that was answered (responded is still open)" do
      doc = stored
      described_class.respond(doc, user: reviewer, note: "Which scanner?")
      described_class.accept(doc, user: reviewer)
      expect(doc.reload.state).to eq("accepted")
    end

    it "never accepts a version that failed validation" do
      doc = stored(vdr(to: " "))
      expect(doc.state).to eq("invalid")

      expect { described_class.accept(doc, user: reviewer) }
        .to raise_error(described_class::Error, "Only a version that passed validation can be accepted")
      expect { described_class.auto_accept(doc) }.to raise_error(described_class::Error)
      expect(doc.reload.state).to eq("invalid")
    end
  end

  describe "respond and reject" do
    it "responding keeps the version out of effect and the one in effect in effect" do
      accepted = stored
      described_class.accept(accepted, user: reviewer)
      doc = stored(vdr(to: "2026-10-31T23:00:00Z"))

      described_class.respond(doc, user: reviewer, note: "Please explain the period.")

      expect(doc.reload).to have_attributes(state: "responded", review_action: "respond",
                                            review_note: "Please explain the period.")
      expect(accepted.reload.state).to eq("accepted")
    end

    it "rejecting puts the version on record, never in effect" do
      doc = stored
      described_class.reject(doc, user: reviewer, note: "Wrong system.")
      expect(doc.reload).to have_attributes(state: "rejected", review_action: "reject", review_note: "Wrong system.")
    end

    it "needs a note to respond or reject" do
      doc = stored
      [ nil, "", "   " ].each do |note|
        expect { described_class.respond(doc, user: reviewer, note: note) }
          .to raise_error(described_class::Error, "Say why, so the provider and the record have it")
        expect { described_class.reject(doc, user: reviewer, note: note) }
          .to raise_error(described_class::Error, "Say why, so the provider and the record have it")
      end
      expect(doc.reload.state).to eq("pending_review")
    end
  end

  describe "a version that is no longer open" do
    %w[accepted rejected superseded].each do |state|
      it "cannot be decided again once #{state}" do
        doc = stored
        doc.update_columns(state: state)

        expect { described_class.accept(doc, user: reviewer) }.to raise_error(described_class::Error, /has been decided/)
        expect { described_class.reject(doc, user: reviewer, note: "x") }.to raise_error(described_class::Error, /has been decided/)
        expect { described_class.respond(doc, user: reviewer, note: "x") }.to raise_error(described_class::Error, /has been decided/)
        expect(doc.reload.state).to eq(state)
      end
    end

    it "refuses a decision made on a stale copy after another reviewer decided" do
      doc = stored
      stale = ReceivedDocument.find(doc.id)
      described_class.reject(doc, user: reviewer, note: "No.")

      # The stale copy still reads pending_review in memory; the row lock sees the truth.
      expect { described_class.accept(stale, user: create(:user)) }
        .to raise_error(described_class::Error)
      expect(doc.reload.state).to eq("rejected")
    end
  end

  describe "separation of duties" do
    it "refuses the uploader every decision on their own upload" do
      doc = stored(by: uploader)

      expect { described_class.accept(doc, user: uploader) }.to raise_error(described_class::SeparationOfDutiesError)
      expect { described_class.respond(doc, user: uploader, note: "x") }.to raise_error(described_class::SeparationOfDutiesError)
      expect { described_class.reject(doc, user: uploader, note: "x") }.to raise_error(described_class::SeparationOfDutiesError)
      expect(described_class.may_decide?(doc, uploader)).to be(false)
      expect(doc.reload.state).to eq("pending_review")
      expect(audits("received_document_accepted")).to be_empty
    end

    it "lets a different reviewer decide" do
      doc = stored(by: uploader)
      expect(described_class.may_decide?(doc, reviewer)).to be(true)
      described_class.accept(doc, user: reviewer)
      expect(doc.reload.state).to eq("accepted")
    end

    it "lets the break-glass administrator (admin?) decide their own upload" do
      doc = stored(by: break_glass)
      expect(described_class.may_decide?(doc, break_glass)).to be(true)
      described_class.accept(doc, user: break_glass)
      expect(doc.reload.state).to eq("accepted")
    end

    it "refuses an instance administrator by role (not admin?) their own upload" do
      role = create(:role, permissions: { "admin.administer" => true })
      role_admin = create(:user)
      create(:user_role, user: role_admin, role: role, authorization_boundary_id: nil)
      expect(role_admin).to be_instance_administrator
      expect(role_admin).not_to be_admin

      doc = stored(by: role_admin)

      expect(described_class.may_decide?(doc, role_admin)).to be(false)
      expect { described_class.accept(doc, user: role_admin) }.to raise_error(described_class::SeparationOfDutiesError)
      expect(doc.reload.state).to eq("pending_review")
    end

    it "lets any reviewer decide a pulled version, which has no uploader" do
      connection = create(:exchange_connection, authorization_boundary: boundary)
      source = create(:exchange_document_source, exchange_connection: connection)
      doc = ReceivedDocumentService.call(boundary: boundary, bytes: vdr, source: "pull", document_source: source,
                                         format: "fedramp").document
      expect(doc.received_by).to be_nil

      expect(described_class.may_decide?(doc, reviewer)).to be(true)
      described_class.reject(doc, user: reviewer, note: "Not ours.")
      expect(doc.reload.state).to eq("rejected")
    end

    it "lets no one decide without a user" do
      doc = stored
      expect(described_class.may_decide?(doc, nil)).to be(false)
      expect { described_class.accept(doc, user: nil) }.to raise_error(described_class::SeparationOfDutiesError)
    end
  end

  describe "an accepted HDF document" do
    let(:hdf) { Rails.root.join("spec/fixtures/files/hdf/sample-results.hdf.json").read }

    it "flows into the boundary's findings and links the scan run" do
      doc = stored(hdf)
      expect(doc).to have_attributes(format: "hdf", state: "pending_review")

      expect { described_class.accept(doc, user: reviewer) }.to change(ScanRun, :count).by(1)

      doc.reload
      expect(doc.state).to eq("accepted")
      expect(doc.scan_run).to be_present
      expect(doc.scan_run.authorization_boundary_id).to eq(boundary.id)
      expect(boundary.scanner_findings.count).to be > 0
      expect(boundary.scanner_findings.where(scan_run_id: doc.scan_run_id).count).to eq(boundary.scanner_findings.count)
    end

    it "is not accepted when the ingest fails: nothing changes, the previous version stays in effect" do
      doc = stored(hdf)
      previous = create(:received_document, authorization_boundary: boundary, stream_key: doc.stream_key,
                                            format: "hdf", state: "accepted")
      allow_any_instance_of(HdfIngestService).to receive(:ingest)
        .and_raise(HdfIngestService::IngestError, "No HDF controls found")

      expect { described_class.accept(doc, user: reviewer) }
        .to raise_error(described_class::Error, /could not be added to the boundary's findings: No HDF controls found/)

      expect(doc.reload).to have_attributes(state: "pending_review", review_action: nil, reviewed_by_id: nil,
                                            scan_run_id: nil)
      expect(previous.reload.state).to eq("accepted")
      expect(audits("received_document_accepted")).to be_empty
    end

    it "is not ingested when only responded to or rejected" do
      doc = stored(hdf)
      expect { described_class.reject(doc, user: reviewer, note: "No.") }.not_to change(ScanRun, :count)
    end
  end

  describe "audit" do
    it "records each decision with who, the state, the SHA-256 and the note" do
      accepted = stored
      described_class.accept(accepted, user: reviewer)
      responded = stored(vdr(to: "2026-10-31T23:00:00Z"))
      described_class.respond(responded, user: reviewer, note: "Why?")
      rejected = stored(vdr(to: "2026-10-31T22:00:00Z"))
      described_class.reject(rejected, user: reviewer, note: "No.")

      { "received_document_accepted" => [ accepted, "accepted", nil ],
        "received_document_responded" => [ responded, "responded", "Why?" ],
        "received_document_rejected" => [ rejected, "rejected", "No." ] }.each do |action, (doc, state, note)|
        event = audits(action).sole
        expect(event).to have_attributes(user_id: reviewer.id, subject_type: "ReceivedDocument", subject_id: doc.id)
        expect(event.metadata).to include("authorization_boundary_id" => boundary.id, "state" => state,
                                          "sha256" => doc.sha256)
        expect(event.metadata["note"]).to eq(note)
      end
    end

    it "records nothing for a refused decision" do
      doc = stored
      expect { described_class.accept(doc, user: uploader) }.to raise_error(described_class::Error)
      expect(AuditEvent.where("action LIKE 'received_document_%'").pluck(:action)).to eq([ "received_document_stored" ])
    end
  end
end
