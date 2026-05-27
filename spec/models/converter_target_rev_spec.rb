# frozen_string_literal: true

require "rails_helper"

# #499 slice 2 — Converter#target_rev reads/writes metadata_extra so
# ControlIdNormalizer can dispatch the right rev translation.
RSpec.describe Converter, "#target_rev (slice 2)" do
  let(:converter) do
    Converter.create!(name: "Test Conv #{SecureRandom.hex(4)}", converter_type: "custom",
                      status: "complete")
  end

  it "returns nil when metadata_extra has no target_rev" do
    expect(converter.target_rev).to be_nil
  end

  it "round-trips through the writer" do
    converter.target_rev = "5"
    converter.save!
    expect(converter.reload.target_rev).to eq("5")
    expect(converter.metadata_extra["target_rev"]).to eq("5")
  end

  it "stringifies non-string input" do
    converter.target_rev = 4
    expect(converter.target_rev).to eq("4")
  end

  it "preserves other metadata_extra keys when written" do
    converter.update!(metadata_extra: { "source" => "https://example.com/data.json" })
    converter.target_rev = "5"
    converter.save!
    expect(converter.reload.metadata_extra).to include("source" => "https://example.com/data.json", "target_rev" => "5")
  end

  it "handles nil assignment (clears the key)" do
    converter.update!(metadata_extra: { "target_rev" => "5" })
    converter.target_rev = nil
    converter.save!
    expect(converter.reload.target_rev).to be_nil
  end
end
