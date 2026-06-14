# frozen_string_literal: true

require "rails_helper"

RSpec.describe BulkDestroyService do
  let(:user) { create(:user) }

  describe "#call (partial success)" do
    it "deletes unassociated records, blocks associated ones, and reports missing ids" do
      deletable = create(:authorization_boundary)
      blocked   = create(:authorization_boundary)
      create(:ssp_document, authorization_boundary: blocked)

      result = described_class.new(
        model_class: AuthorizationBoundary,
        ids: [ deletable.id, blocked.id, 999_999 ],
        user: user
      ).call

      expect(result.deleted.map { |d| d[:id] }).to eq([ deletable.id ])
      expect(result.blocked.map { |b| b[:id] }).to eq([ blocked.id ])
      expect(result.blocked.first[:reason]).to match(/SSP/)
      expect(result.missing).to include("999999")

      expect(AuthorizationBoundary.exists?(deletable.id)).to be(false)
      expect(AuthorizationBoundary.exists?(blocked.id)).to be(true)
    end

    it "audits each successful deletion and each block" do
      deletable = create(:authorization_boundary)
      blocked   = create(:authorization_boundary)
      create(:ssp_document, authorization_boundary: blocked)

      expect {
        described_class.new(model_class: AuthorizationBoundary,
                            ids: [ deletable.id, blocked.id ], user: user).call
      }.to change(AuditEvent, :count).by(2)
    end

    it "dedupes and caps the id list" do
      ab = create(:authorization_boundary)
      result = described_class.new(model_class: AuthorizationBoundary,
                                   ids: [ ab.id, ab.id, "" ], user: user).call
      expect(result.deleted.size).to eq(1)
    end

    it "summary_sentence reflects deleted/blocked/missing counts" do
      ab = create(:authorization_boundary)
      result = described_class.new(model_class: AuthorizationBoundary, ids: [ ab.id ], user: user).call
      expect(result.summary_sentence("authorization boundary")).to eq("1 authorization boundary deleted.")
    end
  end
end
