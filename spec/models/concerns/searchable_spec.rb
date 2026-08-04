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

  # #888 — name + description is right for a document but not for every
  # collection, so models can declare their own columns. The risk in that
  # change is silent: a screen whose search matches nothing looks like an empty
  # collection rather than a bug.
  describe ".searchable_on" do
    it "leaves the existing artifact models on name and description" do
      expect(SspDocument.searchable_columns).to eq(%i[name description])
    end

    it "searches the columns a model declares" do
      expect(Converter.searchable_columns).to eq(%i[name description source_framework target_framework])
      expect(Evidence.searchable_columns).to eq(%i[title description collected_by])
      expect(FederationPeer.searchable_columns).to eq(%i[name base_url])
      expect(BackMatterResource.searchable_columns).to eq(%i[title description href])
    end

    it "does not leak one model's choice into another" do
      expect(Evidence.searchable_columns).not_to eq(Converter.searchable_columns)
      expect(SspDocument.searchable_columns).to eq(%i[name description])
    end

    # Evidence has no `name` at all, so the default would have raised on every
    # search — the exact case that made the macro necessary.
    it "matches on a declared column the default would have missed" do
      match = create(:evidence, title: "Screenshot", collected_by: "auditor@example.gov")
      create(:evidence, title: "Other", collected_by: "someone@example.gov")

      expect(Evidence.search_text("auditor")).to contain_exactly(match)
    end

    it "matches on any one of several declared columns" do
      by_source = create(:converter, name: "A", source_framework: "CIS")
      by_target = create(:converter, name: "B", target_framework: "CIS Benchmark")
      create(:converter, name: "C", source_framework: "STIG", target_framework: "NIST")

      expect(Converter.search_text("cis")).to contain_exactly(by_source, by_target)
    end

    # A typo, or a column dropped by a later migration, would otherwise narrow
    # a screen's search to nothing without anyone noticing.
    it "raises rather than quietly searching nothing when a column is missing" do
      klass = Class.new(SspDocument) do
        def self.name = "BrokenSearchable"
        searchable_on :name, :no_such_column
      end

      expect { klass.search_text("x").to_a }
        .to raise_error(ArgumentError, /not searchable on no_such_column/)
    end
  end
end
