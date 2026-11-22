# frozen_string_literal: true

require "rails_helper"

# #1390 — FedRAMP's business days: weekends and US federal holidays excluded,
# each holiday on the day it is observed.
RSpec.describe FederalBusinessDays do
  it "observes the eleven federal holidays of 2026" do
    expect(described_class.holidays(2026).sort.map(&:iso8601)).to eq(
      %w[2026-01-01 2026-01-19 2026-02-16 2026-05-25 2026-06-19 2026-07-03 2026-09-07 2026-10-12
         2026-11-11 2026-11-26 2026-12-25]
    )
  end

  it "observes a Saturday holiday on the Friday before and a Sunday one on the Monday after" do
    expect(described_class.holiday?(Date.new(2026, 7, 3))).to be(true)   # 4 July 2026 is a Saturday
    expect(described_class.holiday?(Date.new(2027, 12, 31))).to be(true) # 1 January 2028 is a Saturday
    expect(described_class.holidays(2028)).not_to include(Date.new(2028, 1, 1))
    expect(described_class.holiday?(Date.new(2022, 12, 26))).to be(true) # 25 December 2022 was a Sunday
  end

  it "counts business days forward and back, skipping weekends and holidays" do
    expect(described_class.add(Date.new(2026, 11, 20), 5)).to eq(Date.new(2026, 11, 30)) # Thanksgiving skipped
    expect(described_class.add(Date.new(2026, 12, 28), -1)).to eq(Date.new(2026, 12, 24)) # Christmas skipped
    expect(described_class.add(Date.new(2026, 11, 21), 0)).to eq(Date.new(2026, 11, 21))
    expect(described_class.business_day?(Date.new(2026, 11, 21))).to be(false) # a Saturday
  end
end

RSpec.describe FedrampTimeframe do
  it "shifts by business days, hours and calendar time" do
    expect(described_class.shift(Date.new(2026, 12, 1), "bizdays", 10, before: true)).to eq(Date.new(2026, 11, 16))
    expect(described_class.shift(Time.utc(2026, 11, 25, 15), "bizdays", 1)).to eq(Time.utc(2026, 11, 27, 15))
    expect(described_class.shift(Time.utc(2026, 11, 25, 15), "hours", 0.25)).to eq(Time.utc(2026, 11, 25, 15, 15))
    expect(described_class.shift(Date.new(2026, 1, 31), "months", 3)).to eq(Date.new(2026, 4, 30))
    expect { described_class.shift(Date.current, "fortnights", 1) }.to raise_error(ArgumentError)
  end

  it "says how long a timeframe is" do
    expect(described_class.describe("bizdays", 1)).to eq("1 business day")
    expect(described_class.describe("hours", 6)).to eq("6 hours")
    expect(described_class.describe("hours", 0.25)).to eq("15 minutes")
  end
end
