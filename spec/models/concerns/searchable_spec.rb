# frozen_string_literal: true

require "rails_helper"

# Issue #672 — shared free-text search scope used by every artifact index
# (web + Api::V1 ?q). Exercised here against SspDocument as a representative
# includer; the same scope backs all eight artifact models.
RSpec.describe Searchable, type: :model do
  describe ".search_text" do
    it "returns all records when the query is blank" do
      create(:ssp_document, name: "A")
      create(:ssp_document, name: "B")
      expect(SspDocument.search_text(nil).count).to eq(2)
      expect(SspDocument.search_text("   ").count).to eq(2)
    end

    it "matches name or description case-insensitively" do
      by_name = create(:ssp_document, name: "PRODUCTION portal")
      by_desc = create(:ssp_document, name: "ledger", description: "Production database")
      create(:ssp_document, name: "dev", description: "sandbox only")

      expect(SspDocument.search_text("production")).to contain_exactly(by_name, by_desc)
    end

    it "composes with other scopes (status)" do
      create(:ssp_document, name: "Match One", status: "completed")
      create(:ssp_document, name: "Match Two", status: "pending")

      expect(SspDocument.where(status: "completed").search_text("match").count).to eq(1)
    end

    it "treats the wildcard characters as literals (no injection)" do
      create(:ssp_document, name: "plain")
      # A bare % must not match everything — it is escaped into the LIKE pattern
      # as a literal via the bound parameter, so it only matches a literal %.
      expect(SspDocument.search_text("%").count).to eq(0)
    end
  end
end
