# frozen_string_literal: true

require "rails_helper"

# #1252 — OSCAL profile selection: include-all, with-ids, matching,
# with-child-controls and exclude-controls. Each rule is stated against an
# invented tree, and the expectation is derived from that tree.
RSpec.describe ProfileSelection do
  # zz-1 has two enhancements, zz-1.1 has one of its own; zz-10 must never
  # be mistaken for a child of zz-1.
  let(:tree) do
    [
      [ "zz-1", nil ], [ "zz-1.1", "zz-1" ], [ "zz-1.1.1", "zz-1.1" ], [ "zz-1.2", "zz-1" ],
      [ "zz-2", nil ], [ "zz-10", nil ], [ "yy-1", nil ]
    ]
  end
  let(:all_ids) { tree.map(&:first) }

  subject(:selection) { described_class.new(tree) }

  def ids(import) = selection.select(import)

  it "include-all selects every control at every depth, in catalog order" do
    expect(ids({ "include-all" => {} })).to eq(all_ids)
  end

  it "with-ids selects exactly the named controls, in the order listed" do
    expect(ids({ "include-controls" => [ { "with-ids" => %w[zz-2 zz-1] } ] })).to eq(%w[zz-2 zz-1])
  end

  it "without with-child-controls a named control brings no children" do
    expect(ids({ "include-controls" => [ { "with-ids" => %w[zz-1] } ] })).to eq(%w[zz-1])
  end

  it "with-child-controls brings every descendant, depth-first" do
    expect(ids({ "include-controls" => [ { "with-ids" => %w[zz-1], "with-child-controls" => "yes" } ] }))
      .to eq(%w[zz-1 zz-1.1 zz-1.1.1 zz-1.2])
  end

  it "matching selects by glob over the whole id, in catalog order" do
    pattern = "zz-1*"
    expected = all_ids.select { |id| File.fnmatch(pattern, id) }
    expect(ids({ "include-controls" => [ { "matching" => [ { "pattern" => pattern } ] } ] })).to eq(expected)
    expect(expected).to include("zz-10")
  end

  it "? in a pattern matches exactly one character" do
    expect(ids({ "include-controls" => [ { "matching" => [ { "pattern" => "zz-?" } ] } ] })).to eq(%w[zz-1 zz-2])
  end

  it "a pattern's dot is literal, not any character" do
    expect(ids({ "include-controls" => [ { "matching" => [ { "pattern" => "zz-1.?" } ] } ] })).to eq(%w[zz-1.1 zz-1.2])
  end

  it "exclude-controls removes after inclusion, by id and by pattern" do
    import = {
      "include-all" => {},
      "exclude-controls" => [ { "with-ids" => %w[zz-2] }, { "matching" => [ { "pattern" => "zz-1.*" } ] } ]
    }
    expected = all_ids - %w[zz-2] - all_ids.select { |id| File.fnmatch("zz-1.*", id) }
    expect(ids(import)).to eq(expected)
  end

  it "exclude-controls with-child-controls removes the descendants too" do
    import = { "include-all" => {}, "exclude-controls" => [ { "with-ids" => %w[zz-1.1], "with-child-controls" => "yes" } ] }
    expect(ids(import)).to eq(all_ids - %w[zz-1.1 zz-1.1.1])
  end

  it "a control selected twice keeps its first position" do
    import = { "include-controls" => [ { "with-ids" => %w[zz-2] }, { "matching" => [ { "pattern" => "zz-*" } ] } ] }
    expect(ids(import).first).to eq("zz-2")
    expect(ids(import).count("zz-2")).to eq(1)
  end

  it "keeps a named id the catalog lacks, and reports it" do
    import = { "include-controls" => [ { "with-ids" => %w[zz-1 qq-9] } ] }
    expect(ids(import)).to eq(%w[zz-1 qq-9])
    expect(selection.unknown_ids(import)).to eq(%w[qq-9])
  end

  it "selects nothing from an import with no selector" do
    expect(ids({ "href" => "#x" })).to eq([])
  end
end
