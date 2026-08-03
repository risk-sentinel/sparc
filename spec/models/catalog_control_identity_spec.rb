# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260802140100_backfill_catalog_control_canonical_ids.rb")

# #881 — the identifier and hierarchy logic behind readable control URLs.
# The request specs cover the routes; these cover the rules underneath, which is
# where the subtle failures live.
RSpec.describe CatalogControl, type: :model do
  let(:catalog) { create(:control_catalog) }
  let(:family)  { create(:control_family, control_catalog: catalog, code: "AC") }

  def control(id) = family.catalog_controls.create!(control_id: id, title: "Control #{id}")

  describe "canonical identity" do
    it "stores the canonical form on write" do
      expect(control("ac-1a.1.(a)").canonical_id).to eq("ac-1a.1.a")
    end

    it "keeps it in step when control_id changes" do
      c = control("ac-2")
      c.update!(control_id: "ac-2.1.(b)")
      expect(c.reload.canonical_id).to eq("ac-2.1.b")
    end

    it "falls back to computing it when the column is empty" do
      c = control("ac-3.(a)")
      c.update_column(:canonical_id, nil)
      expect(c.reload.canonical_identifier).to eq("ac-3.a")
    end

    it "is unique per family — the index mirrors the control_id rule" do
      control("ac-4")
      dup = family.catalog_controls.build(control_id: "ac-4", title: "dupe")
      expect(dup).not_to be_valid
    end
  end

  describe ".find_by_canonical" do
    it "resolves within the given catalog" do
      c = control("ac-5.(a)")
      expect(described_class.find_by_canonical(catalog, "ac-5.a")).to eq(c)
    end

    it "does not leak across catalogs" do
      control("ac-6")
      other = create(:control_catalog)
      expect(described_class.find_by_canonical(other, "ac-6")).to be_nil
    end

    it "returns nil rather than raising on a blank identifier" do
      expect(described_class.find_by_canonical(catalog, "")).to be_nil
      expect(described_class.find_by_canonical(nil, "ac-1")).to be_nil
    end
  end

  # The bug that shipped briefly: a prefix match called ac-10 a sub-part of ac-1.
  describe "hierarchy" do
    it "does not treat a longer base number as a descendant" do
      expect(described_class.descendant?("ac-10", "ac-1")).to be(false)
      expect(described_class.descendant?("ac-100", "ac-1")).to be(false)
    end

    it "treats statement parts and enhancements as descendants" do
      expect(described_class.descendant?("ac-1a", "ac-1")).to be(true)
      expect(described_class.descendant?("ac-1.1", "ac-1")).to be(true)
      expect(described_class.descendant?("ac-1a.1", "ac-1a")).to be(true)
    end

    it "is not reflexive" do
      expect(described_class.descendant?("ac-1", "ac-1")).to be(false)
    end

    it "returns only direct children, one level down" do
      parent = control("ac-1")
      control("ac-1a")
      control("ac-1a.1")   # grandchild
      control("ac-10")     # NOT a child

      expect(parent.direct_children.map(&:control_id)).to contain_exactly("ac-1a")
    end
  end

  describe "ControlCatalog.find_for_url" do
    it "resolves by uuid, slug and numeric id" do
      expect(ControlCatalog.find_for_url(catalog.oscal_uuid)).to eq(catalog)
      expect(ControlCatalog.find_for_url(catalog.slug)).to eq(catalog)
      expect(ControlCatalog.find_for_url(catalog.id.to_s)).to eq(catalog)
    end

    it "returns nil for an unknown identifier instead of raising" do
      expect(ControlCatalog.find_for_url("nope")).to be_nil
      expect(ControlCatalog.find_for_url(nil)).to be_nil
    end

    it "prefers the uuid — it is the stable identity" do
      expect(catalog.url_id).to eq(catalog.oscal_uuid)
    end

    # oscal_uuid is taken verbatim from an uploaded OSCAL document and has no
    # format validation, so it is attacker-influenced input that reaches an
    # href. CodeQL flagged exactly this (rb/stored-xss).
    it "refuses a malformed oscal_uuid in a URL and falls back to the slug" do
      catalog.update_column(:oscal_uuid, "javascript:alert(1)")

      expect(catalog.reload.url_id).to eq(catalog.slug)
      expect(catalog.url_id).not_to include("javascript:")
    end

    it "keeps a hostile catalog NAME out of the URL — the slug is parameterized" do
      hostile = create(:control_catalog, name: %q{<script>alert(1)</script> & "quoted"})

      expect(hostile.slug).to match(/\A[a-z0-9\-_]+\z/)
      expect(hostile.url_id).to match(/\A[a-z0-9\-_]+\z/).or match(ControlCatalog::UUID_FORMAT)
    end
  end

  # The backfill runs post-boot via DeferredDataMigrationJob, so a deploy can
  # interrupt it. It has to resume, not redo or double-apply.
  describe BackfillCatalogControlCanonicalIds do
    subject(:migration) do
      described_class.new.tap { |m| m.define_singleton_method(:say) { |*| } }
    end

    it "populates rows that have no canonical_id" do
      c = control("ac-7.(a)")
      c.update_column(:canonical_id, nil)

      migration.backfill_canonical_ids

      expect(c.reload.canonical_id).to eq("ac-7.a")
    end

    it "is idempotent — a second run changes nothing" do
      c = control("ac-8.(b)")
      migration.backfill_canonical_ids
      first = c.reload.updated_at

      migration.backfill_canonical_ids

      expect(c.reload.canonical_id).to eq("ac-8.b")
      expect(c.reload.updated_at).to eq(first)
    end

    it "resumes from a partial run without disturbing rows already done" do
      done    = control("ac-9")
      pending = control("ac-9a")
      pending.update_column(:canonical_id, nil)

      migration.backfill_canonical_ids

      expect(pending.reload.canonical_id).to eq("ac-9a")
      expect(done.reload.canonical_id).to eq("ac-9")
    end

    it "skips a colliding row rather than aborting the whole run" do
      keep = control("ac-11")
      # Force a collision the unique index would reject.
      clash = family.catalog_controls.create!(control_id: "ac-11x", title: "clash")
      clash.update_column(:canonical_id, nil)
      allow(ControlId).to receive(:canonical).and_call_original
      allow(ControlId).to receive(:canonical).with("ac-11x").and_return("ac-11")

      expect { migration.backfill_canonical_ids }.not_to raise_error

      expect(clash.reload.canonical_id).to be_nil
      expect(keep.reload.canonical_id).to eq("ac-11")
    end
  end
end
