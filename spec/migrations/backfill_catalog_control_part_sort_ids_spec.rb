# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("db/migrate/20260815120000_backfill_catalog_control_part_sort_ids.rb")

# #941 — resolving the sort key for statement sub-parts already stored.
#
# The migration is deferred, so this drives `backfill_part_sort_ids` directly
# rather than through `up` (which would only enqueue it).
RSpec.describe BackfillCatalogControlPartSortIds do
  subject(:migration) { described_class.new }

  before { allow(migration).to receive(:say) }

  let(:catalog) { create(:control_catalog) }
  let(:family)  { create(:control_family, control_catalog: catalog) }

  # Reproduce the PRE-migration state faithfully. `upsert_catalog_control` only
  # assigns sort_id `if sort_id.present?`, so a sub-part row genuinely carried
  # NULL — writing the column directly is what real rows look like.
  def control_for(control_id, sort_id: nil, fam: family)
    control = CatalogControl.create!(control_family: fam, control_id: control_id, title: control_id)
    control.update_columns(sort_id: sort_id)
    control
  end

  # The exact case in the issue: "ac-2.7.(a)" sorted after "AC-25" because
  # COALESCE compared an unpadded identifier against a padded key.
  describe "the ordering the issue reports" do
    it "places a sub-part directly under its parent rather than after the family" do
      control_for("ac-2.7", sort_id: "ac-02.07")
      control_for("ac-25",  sort_id: "ac-25")
      subpart = control_for("ac-2.7.(a)")

      migration.backfill_part_sort_ids

      expect(subpart.reload.sort_id).to eq("ac-02.07.(a)")

      ordered = family.catalog_controls.reload.map(&:control_id)
      expect(ordered).to eq(%w[ac-2.7 ac-2.7.(a) ac-25])
    end

    # Proves the fix is the derived key and not an accident of the identifiers:
    # left NULL, the same three rows come back in the broken order.
    it "orders them wrongly while the sub-part key is still NULL" do
      control_for("ac-2.7", sort_id: "ac-02.07")
      control_for("ac-25",  sort_id: "ac-25")
      control_for("ac-2.7.(a)")

      ordered = family.catalog_controls.reload.map(&:control_id)
      expect(ordered).to eq(%w[ac-2.7 ac-25 ac-2.7.(a)])
    end
  end

  describe "the parent it chooses" do
    # Longest prefix, not first or shortest: "ac-2" is also a prefix of
    # "ac-2.7.(a)", and inheriting from it would order the sub-part under the
    # base control instead of under the enhancement it belongs to.
    it "inherits from the longest matching ancestor" do
      control_for("ac-2",   sort_id: "ac-02")
      control_for("ac-2.7", sort_id: "ac-02.07")
      subpart = control_for("ac-2.7.(a)")

      migration.backfill_part_sort_ids

      expect(subpart.reload.sort_id).to eq("ac-02.07.(a)")
    end

    it "chains through a parent resolved earlier in the same pass" do
      control_for("ac-3.3", sort_id: "ac-03.03")
      parent = control_for("ac-3.3.(b)")
      child  = control_for("ac-3.3.(b).(1)")

      migration.backfill_part_sort_ids

      expect(parent.reload.sort_id).to eq("ac-03.03.(b)")
      expect(child.reload.sort_id).to eq("ac-03.03.(b).(1)")
    end

    it "does not treat a control as its own parent" do
      orphan = control_for("ac-1")

      migration.backfill_part_sort_ids

      expect(orphan.reload.sort_id).to be_nil
    end

    # Families are separate catalogs' separate namespaces; a prefix match across
    # them would attach a Rev 4 sub-part to a Rev 5 parent.
    it "never inherits from a control in another family" do
      other = create(:control_family, control_catalog: create(:control_catalog))
      control_for("ac-2.7", sort_id: "ac-02.07", fam: other)
      subpart = control_for("ac-2.7.(a)")

      migration.backfill_part_sort_ids

      expect(subpart.reload.sort_id).to be_nil
    end
  end

  describe "what it refuses to do" do
    # A key that came from the catalog is authoritative; ours is a
    # reconstruction. Preferring ours would be wrong exactly where it matters.
    it "never overwrites a sort_id that is already set" do
      control_for("ac-2.7", sort_id: "ac-02.07")
      subpart = control_for("ac-2.7.(a)", sort_id: "operator-set")

      migration.backfill_part_sort_ids

      expect(subpart.reload.sort_id).to eq("operator-set")
    end

    # The test above is satisfied by the `sort_id: nil` filter on the SELECT
    # alone — it never reaches the predicate on the UPDATE. That second guard
    # exists for the case where a row is resolved between the read that selected
    # it and the write, which is not hypothetical: the first live run raced the
    # Solid Queue job holding the advisory lock. Without a test that forces the
    # interleaving, removing the write-time predicate leaves the suite green.
    it "does not clobber a key another runner set after the pass began" do
      control_for("ac-2.7", sort_id: "ac-02.07")
      racing = control_for("ac-2.7.(a)")

      allow(migration).to receive(:derive).and_wrap_original do |original, *args|
        racing.update_columns(sort_id: "set-by-other-runner")
        original.call(*args)
      end

      migration.backfill_part_sort_ids

      expect(racing.reload.sort_id).to eq("set-by-other-runner")
    end

    # NIST XML enhancement sub-parts keep their own parenthesised numbering,
    # which is not built from the parent-id. Fabricating a key would put the row
    # somewhere confidently wrong; NULL leaves the COALESCE fallback in charge.
    it "leaves a row NULL when no ancestor is a prefix of its identifier" do
      control_for("ac-2.7", sort_id: "ac-02.07")
      unplaceable = control_for("ac-2(7)(a)")

      migration.backfill_part_sort_ids

      expect(unplaceable.reload.sort_id).to be_nil
    end
  end

  describe "idempotency and resume-from-partial" do
    it "converges on a re-run without redoing work" do
      control_for("ac-2.7", sort_id: "ac-02.07")
      subpart = control_for("ac-2.7.(a)")

      expect(migration.backfill_part_sort_ids).to eq(1)
      expect(migration.backfill_part_sort_ids).to eq(0)
      expect(subpart.reload.sort_id).to eq("ac-02.07.(a)")
    end

    # This is not hypothetical: the first live run was interrupted partway by the
    # Solid Queue job holding the advisory lock, and the resumed run had to
    # finish only what remained.
    it "resumes correctly when an earlier run already resolved some rows" do
      control_for("ac-2.7", sort_id: "ac-02.07")
      already = control_for("ac-2.7.(a)", sort_id: "ac-02.07.(a)")
      pending = control_for("ac-2.7.(b)")

      expect(migration.backfill_part_sort_ids).to eq(1)

      expect(already.reload.sort_id).to eq("ac-02.07.(a)")
      expect(pending.reload.sort_id).to eq("ac-02.07.(b)")
    end

    it "reports the number it resolved so an operator sees the data work" do
      control_for("ac-2.7", sort_id: "ac-02.07")
      control_for("ac-2.7.(a)")
      control_for("ac-2.7.(b)")

      expect(migration.backfill_part_sort_ids).to eq(2)
    end
  end
end
