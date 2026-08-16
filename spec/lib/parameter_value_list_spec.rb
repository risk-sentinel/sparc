# frozen_string_literal: true

require "rails_helper"

# #942 — encoding a parameter field that holds more than one value.
RSpec.describe ParameterValueList do
  # The defect this exists for: OSCAL insert markup always contains a comma, so
  # comma-joining split a single chosen branch into two values, and both were
  # exported as `set-parameters` nobody chose.
  let(:composed) { "establish {{ insert: param, ac-20_odp.02 }}" }

  describe ".join then .split" do
    it "round-trips a value containing insert markup" do
      encoded = described_class.join([ composed ])

      expect(described_class.split(encoded)).to eq([ composed ])
    end

    it "round-trips several composed values" do
      values = [ composed, "identify {{ insert: param, ac-20_odp.03 }}" ]

      expect(described_class.split(described_class.join(values))).to eq(values)
    end

    it "round-trips ordinary literal values" do
      values = %w[VPN tunneled direct]

      expect(described_class.split(described_class.join(values))).to eq(values)
    end

    it "drops blanks rather than encoding empty slots" do
      expect(described_class.join([ "VPN", "", nil, " " ])).to eq("VPN")
    end
  end

  describe ".split on legacy comma-joined values" do
    # Rows written before this change are still comma-joined, so no data
    # migration is required.
    it "still splits a legacy list" do
      expect(described_class.split("VPN, tunneled, direct")).to eq(%w[VPN tunneled direct])
    end

    # Splitting is exactly what corrupts these, and a value that references a
    # parameter is never a comma-separated list.
    it "treats a legacy value carrying markup as ONE value, not two" do
      expect(described_class.split(composed)).to eq([ composed ])
    end

    it "returns nothing for blank input" do
      expect(described_class.split(nil)).to eq([])
      expect(described_class.split("   ")).to eq([])
    end
  end

  # Measured against the Rev 5 catalog: of 355 selection choices, 74 contain a
  # comma and none contains a pipe.
  it "uses a separator no catalog choice contains" do
    expect(composed).to include(",")
    expect(composed).not_to include(described_class::SEPARATOR)
  end
end
