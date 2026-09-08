# frozen_string_literal: true

require "rails_helper"

# Owner review: AC-01's page reported "Sub-parts 3" while the control has nine.
# `direct_children` returned one level, so ac-1a.1, ac-1a.1.(a), ac-1a.1.(b),
# ac-1a.2, ac-1c.1 and ac-1c.2 were reachable only by guessing you could click
# into ac-1a — and the family screen, which shows the whole tree, disagreed with
# the control screen.
RSpec.describe "CatalogControl#descendants" do
  let(:catalog) { create(:control_catalog) }
  let(:family)  { create(:control_family, control_catalog: catalog) }

  def ctrl(id) = create(:catalog_control, control_family: family, control_id: id)

  let!(:ac1)   { ctrl("ac-1") }
  let!(:a)     { ctrl("ac-1a") }
  let!(:a1)    { ctrl("ac-1a.1") }
  let!(:a1a)   { ctrl("ac-1a.1.(a)") }
  let!(:c)     { ctrl("ac-1c") }
  # NOT descendants — they only share a prefix
  let!(:ac10)  { ctrl("ac-10") }
  let!(:ac11a) { ctrl("ac-11a") }

  it "returns EVERY descendant, not one level" do
    expect(ac1.descendants.map(&:control_id))
      .to match_array(%w[ac-1a ac-1a.1 ac-1a.1.(a) ac-1c])
  end

  it "still excludes a control that merely shares the prefix" do
    ids = ac1.descendants.map(&:control_id)
    expect(ids).not_to include("ac-10")
    expect(ids).not_to include("ac-11a")
  end

  it "orders by depth so the list nests correctly on screen" do
    depths = ac1.descendants.map(&:depth)
    expect(depths).to eq(depths.sort)
  end

  it "direct_children remains one level, for callers that want only that" do
    expect(ac1.direct_children.map(&:control_id)).to eq(%w[ac-1a ac-1c])
  end
end
