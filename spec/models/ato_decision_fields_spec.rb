# frozen_string_literal: true

require "rails_helper"

# #1154 — the AO-decision fields on risks and the decision dates on a boundary
# are validated at the point of entry, BEFORE type casting, so a value that
# cannot be represented is refused rather than silently replaced (ActiveModel
# casts "maybe" to true and "2026-13-40" to nil).
RSpec.describe "ATO decision fields (#1154)" do
  describe PoamRisk do
    let(:risk) { build(:poam_risk) }

    it "accepts every field unset — an undecided risk is valid" do
      expect(risk).to be_valid
      expect(risk.blocks_ato).to be_nil
    end

    it "accepts a decided risk in the contract's forms" do
      risk.assign_attributes(blocks_ato: "false", condition_expires: "2026-11-01", reopen_trigger: "blockers>=1")

      expect(risk).to be_valid
      expect(risk.blocks_ato).to be(false)
      expect(risk.condition_expires).to eq(Date.new(2026, 11, 1))
    end

    it "treats a blank trigger from a form as nil" do
      risk.reopen_trigger = "  "
      risk.valid?
      expect(risk.reopen_trigger).to be_nil
    end

    it "refuses blocks_ato values the cast would turn into true" do
      risk.blocks_ato = "maybe"
      expect(risk).not_to be_valid
      expect(risk.errors[:blocks_ato]).to be_present
    end

    it "refuses a condition_expires that is not a calendar date" do
      %w[2026-13-40 11/01/2026 soon].each do |bad|
        risk.condition_expires = bad
        expect(risk).not_to be_valid, "#{bad.inspect} was accepted"
        expect(risk.errors[:condition_expires]).to be_present
      end
    end

    it "refuses a trigger outside the contract's grammar" do
      %w[score=0.85 latency<5 score<abc].each do |bad|
        risk.reopen_trigger = bad
        expect(risk).not_to be_valid, "#{bad.inspect} was accepted"
      end
      %w[score<0.85 score<=1 blockers>0 blockers>=2].each do |good|
        risk.reopen_trigger = good
        expect(risk).to be_valid, "#{good.inspect} was refused: #{risk.errors.full_messages}"
      end
    end
  end

  describe SarRisk do
    let(:risk) { build(:sar_risk) }

    it "carries blocks_ato alone, validated the same way" do
      risk.blocks_ato = true
      expect(risk).to be_valid

      risk.blocks_ato = "perhaps"
      expect(risk).not_to be_valid
      expect(risk).not_to respond_to(:reopen_trigger)
    end
  end

  describe AuthorizationBoundary do
    let(:boundary) { create(:authorization_boundary) }

    it "stores next_decision_date and authorization_date as ISO dates" do
      boundary.update!(next_decision_date: Date.new(2026, 10, 11), authorization_date: "2025-10-11")

      expect(boundary.reload.next_decision_date).to eq("2026-10-11")
      expect(boundary.authorization_date).to eq("2025-10-11")
      expect(AuthorizationBoundary::BOUNDARY_METADATA_KEYS).to include("next_decision_date")
    end

    it "clears a date given as blank rather than storing an empty string" do
      boundary.update!(next_decision_date: "2026-10-11")
      boundary.update!(next_decision_date: "")

      expect(boundary.reload.boundary_metadata).not_to have_key("next_decision_date")
    end

    %w[next_decision_date authorization_date].each do |key|
      it "refuses a #{key} that is not YYYY-MM-DD" do
        boundary.public_send(:"#{key}=", "10/11/2026")

        expect(boundary).not_to be_valid
        expect(boundary.errors[key.to_sym].join).to include("YYYY-MM-DD")
      end
    end

    # A legacy value must not lock the record: only a CHANGED date is checked.
    it "does not block an unrelated edit on a boundary already holding a legacy date" do
      boundary.update_columns(boundary_metadata: { "authorization_date" => "Oct 2025" })

      expect(boundary.reload.update(name: "Renamed")).to be(true)
    end
  end
end
