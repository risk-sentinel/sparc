# frozen_string_literal: true

require "rails_helper"

# #1354 — one version of a document a boundary received. Never overwritten:
# what arrived and where it came from are fixed when it is stored; only the
# review fields change afterwards (SI-7, AU-10).
RSpec.describe ReceivedDocument do
  let(:boundary) { create(:authorization_boundary) }

  def version(**attrs) = create(:received_document, authorization_boundary: boundary, **attrs)

  describe "what arrived is fixed at receipt" do
    let(:doc) { version }

    {
      sha256: "f" * 64,
      byte_size: 999,
      format: "oscal",
      document_type: "ssp",
      stream_key: "upload:another-stream",
      source: "pull",
      received_at: Time.zone.parse("2020-01-01"),
      authorization_boundary_id: -> { create(:authorization_boundary).id },
      received_by_id: -> { create(:user).id }
    }.each do |attribute, value|
      it "refuses to change #{attribute}" do
        new_value = value.respond_to?(:call) ? instance_exec(&value) : value
        original = doc.public_send(attribute)

        expect { doc.update(attribute => new_value) }.to raise_error(ActiveRecord::ReadonlyAttributeError)
        expect { doc.update_columns(attribute => new_value) }.to raise_error(ActiveRecord::ActiveRecordError, /readonly/)
        expect(doc.reload.public_send(attribute)).to eq(original)
      end
    end

    it "lets the review fields change" do
      reviewer = create(:user)
      doc.update!(state: "rejected", review_action: "reject", review_note: "No.", reviewed_by: reviewer,
                  reviewed_at: Time.current)
      expect(doc.reload).to have_attributes(state: "rejected", review_note: "No.", reviewed_by: reviewer)
    end
  end

  describe "validations" do
    it "takes only the known states, sources, formats and review actions" do
      expect(build(:received_document, state: "approved")).not_to be_valid
      expect(build(:received_document, source: "email")).not_to be_valid
      expect(build(:received_document, format: "docx")).not_to be_valid
      expect(build(:received_document, review_action: "approve")).not_to be_valid
      expect(build(:received_document, review_action: nil)).to be_valid
      described_class::STATES.each { |s| expect(build(:received_document, state: s)).to be_valid, s }
      described_class::SOURCES.each { |s| expect(build(:received_document, source: s)).to be_valid, s }
    end

    it "needs a hex SHA-256 and a stream" do
      expect(build(:received_document, sha256: "abc")).not_to be_valid
      expect(build(:received_document, sha256: "g" * 64)).not_to be_valid
      expect(build(:received_document, stream_key: "")).not_to be_valid
    end

    it "stores one version per SHA-256 per stream" do
      first = version(stream_key: "upload:s", sha256: "a" * 64)
      expect { version(stream_key: "upload:s", sha256: first.sha256) }.to raise_error(ActiveRecord::RecordNotUnique)
      expect(version(stream_key: "upload:other", sha256: first.sha256)).to be_persisted
    end
  end

  describe "states" do
    it "is open while pending review or responded, and in effect only when accepted" do
      expect(described_class::OPEN_STATES).to eq(%w[pending_review responded])
      described_class::STATES.each do |state|
        doc = build(:received_document, state: state)
        expect(doc.open?).to eq(state.in?(%w[pending_review responded])), state
        expect(doc.in_effect?).to eq(state == "accepted"), state
      end
    end
  end

  describe "scopes" do
    let!(:docs) { described_class::STATES.index_with { |state| version(state: state) } }

    it ".in_effect is the accepted versions" do
      expect(described_class.in_effect).to eq([ docs["accepted"] ])
    end

    it ".awaiting_review is the open versions" do
      expect(described_class.awaiting_review).to contain_exactly(docs["pending_review"], docs["responded"])
    end

    it ".recent is newest first" do
      older = version(received_at: 2.days.ago)
      expect(described_class.recent.first).not_to eq(older)
      expect(described_class.recent.last).to eq(older)
    end
  end

  describe "#in_effect_version" do
    it "is the accepted version of the same stream, never itself or another stream's" do
      accepted = version(stream_key: "upload:s", state: "accepted")
      version(stream_key: "upload:other", state: "accepted")
      pending = version(stream_key: "upload:s")

      expect(pending.in_effect_version).to eq(accepted)
      expect(accepted.in_effect_version).to be_nil
    end
  end

  it "reads its validation errors, warnings and delta changes, empty when absent" do
    doc = build(:received_document, validation: { "errors" => [ { "message" => "x" } ], "warnings" => [ "w" ] },
                                    delta: { "changes" => [ { "kind" => "neutral" } ] })
    expect(doc.validation_errors).to eq([ { "message" => "x" } ])
    expect(doc.validation_warnings).to eq([ "w" ])
    expect(doc.delta_changes).to eq([ { "kind" => "neutral" } ])
    expect(build(:received_document).validation_errors).to eq([])
    expect(build(:received_document).delta_changes).to eq([])
  end

  it "#bytes is the attached file's content, nil without one" do
    doc = version
    expect(doc.bytes).to be_nil
    doc.file.attach(io: StringIO.new("exact\x00bytes".b), filename: "d.json")
    expect(doc.reload.bytes).to eq("exact\x00bytes".b)
  end
end
