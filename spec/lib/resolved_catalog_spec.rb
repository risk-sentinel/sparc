# frozen_string_literal: true

require "rails_helper"

# #999 — the reader that made the nesting fix safe. Six services walked
# `groups[].controls[]` privately and stopped there; this is the one traversal
# they now share, so it has to read BOTH shapes a resolved catalog arrives in.
RSpec.describe ResolvedCatalog do
  # Shaped like NIST's published resolved profile catalog: enhancements nested
  # inside their parent control.
  let(:nested) do
    {
      "catalog" => {
        "uuid" => "c1",
        "metadata" => { "title" => "HIGH" },
        "groups" => [
          {
            "id" => "ac", "title" => "Access Control",
            "controls" => [
              { "id" => "ac-1", "title" => "Policy" },
              { "id" => "ac-2", "title" => "Account Management",
                "controls" => [
                  { "id" => "ac-2.1", "title" => "Automated System Account Management" },
                  { "id" => "ac-2.2", "title" => "Automated Temporary Accounts" }
                ] }
            ]
          },
          {
            "id" => "au", "title" => "Audit",
            "controls" => [ { "id" => "au-1", "title" => "Audit Policy" } ]
          }
        ]
      }
    }
  end

  # The shape SPARC emitted before #999, and what every stored
  # resolved_catalog_json written by an older release still holds.
  let(:flat) do
    {
      "catalog" => {
        "groups" => [
          { "id" => "ac", "title" => "Access Control",
            "controls" => [
              { "id" => "ac-1" }, { "id" => "ac-2" }, { "id" => "ac-2.1" }, { "id" => "ac-2.2" }
            ] },
          { "id" => "au", "title" => "Audit", "controls" => [ { "id" => "au-1" } ] }
        ]
      }
    }
  end

  describe "reading both shapes" do
    it "finds every control in a nested catalog, enhancements included" do
      expect(described_class.wrap(nested).control_ids)
        .to eq(%w[ac-1 ac-2 ac-2.1 ac-2.2 au-1])
    end

    it "finds every control in a flat catalog" do
      expect(described_class.wrap(flat).control_ids)
        .to eq(%w[ac-1 ac-2 ac-2.1 ac-2.2 au-1])
    end

    # The whole point: a caller cannot tell which shape it was handed, and does
    # not have to.
    it "reads the same control set from either shape" do
      expect(described_class.wrap(nested).control_ids)
        .to eq(described_class.wrap(flat).control_ids)
    end

    it "yields a nested enhancement with its parent's group, so the family survives" do
      families = described_class.wrap(nested).each_control.to_h { |c, g| [ c["id"], g["id"] ] }
      expect(families).to eq(
        "ac-1" => "ac", "ac-2" => "ac", "ac-2.1" => "ac", "ac-2.2" => "ac", "au-1" => "au"
      )
    end

    it "yields a parent before its enhancements, preserving document order" do
      ids = described_class.wrap(nested).control_ids
      expect(ids.index("ac-2")).to be < ids.index("ac-2.1")
    end
  end

  describe "documents that are not the expected wrapper" do
    it "accepts a bare catalog with no `catalog` key" do
      expect(described_class.wrap(nested["catalog"]).control_ids).to include("ac-2.1")
    end

    it "walks nested groups, which OSCAL permits even though NIST does not use them" do
      doc = { "catalog" => { "groups" => [
        { "id" => "ac", "groups" => [ { "id" => "ac-sub", "controls" => [ { "id" => "ac-9" } ] } ] }
      ] } }
      expect(described_class.wrap(doc).control_ids).to eq([ "ac-9" ])
    end

    it "treats a blank document as empty rather than raising" do
      [ nil, {}, "", [] ].each do |blank|
        expect(described_class.wrap(blank).control_ids).to eq([])
        expect(described_class.wrap(blank)).not_to be_any
      end
    end
  end

  describe "#find" do
    it "reaches a nested enhancement" do
      expect(described_class.wrap(nested).find("ac-2.2")["title"])
        .to eq("Automated Temporary Accounts")
    end

    it "returns nil for a control the catalog does not carry" do
      expect(described_class.wrap(nested).find("zz-9")).to be_nil
    end
  end
end
