# frozen_string_literal: true

require "rails_helper"

# #802 — SPARC_REQUIRE_FIDO2 is ONE variable controlling both enablement and
# scope (infer-enable-from-value, like #785): setting it to local/all also
# enables FIDO2, so operators don't set two vars.
RSpec.describe SparcConfig, "mandatory FIDO2 (#802)" do
  around do |ex|
    keys = %w[SPARC_REQUIRE_FIDO2 SPARC_FIDO2_ENABLED]
    saved = keys.to_h { |k| [ k, ENV[k] ] }
    keys.each { |k| ENV.delete(k) }
    ex.run
    saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  it "defaults to off — opt-in only, FIDO2 disabled" do
    expect(described_class.require_fido2_mode).to eq("off")
    expect(described_class.require_fido2?).to be(false)
    expect(described_class.fido2_enabled?).to be(false)
  end

  it "SPARC_REQUIRE_FIDO2=all requires AND enables FIDO2 (one var)" do
    ENV["SPARC_REQUIRE_FIDO2"] = "all"
    expect(described_class.require_fido2_mode).to eq("all")
    expect(described_class.require_fido2?).to be(true)
    expect(described_class.fido2_enabled?).to be(true) # inferred
  end

  it "SPARC_REQUIRE_FIDO2=local scopes to local sessions AND enables FIDO2" do
    ENV["SPARC_REQUIRE_FIDO2"] = "local"
    expect(described_class.require_fido2_mode).to eq("local")
    expect(described_class.fido2_enabled?).to be(true)
  end

  it "aliases true->all and false->off" do
    ENV["SPARC_REQUIRE_FIDO2"] = "true"
    expect(described_class.require_fido2_mode).to eq("all")
    ENV["SPARC_REQUIRE_FIDO2"] = "false"
    expect(described_class.require_fido2_mode).to eq("off")
  end

  it "treats an unknown value as off (fail safe, not fail open)" do
    ENV["SPARC_REQUIRE_FIDO2"] = "banana"
    expect(described_class.require_fido2_mode).to eq("off")
  end

  it "SPARC_FIDO2_ENABLED=true enables opt-in WITHOUT requiring" do
    ENV["SPARC_FIDO2_ENABLED"] = "true"
    expect(described_class.fido2_enabled?).to be(true)
    expect(described_class.require_fido2?).to be(false)
  end
end
