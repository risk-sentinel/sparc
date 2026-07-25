# frozen_string_literal: true

require "rails_helper"

# #805 — SPARC_REQUIRE_AUTH_METHODS is a CSV allowlist of accepted login methods;
# empty (default) means no restriction.
RSpec.describe SparcConfig, "required auth methods (#805)" do
  around do |ex|
    saved = ENV["SPARC_REQUIRE_AUTH_METHODS"]
    ENV.delete("SPARC_REQUIRE_AUTH_METHODS")
    ex.run
    saved.nil? ? ENV.delete("SPARC_REQUIRE_AUTH_METHODS") : ENV["SPARC_REQUIRE_AUTH_METHODS"] = saved
  end

  it "defaults to empty — no restriction" do
    expect(described_class.required_auth_methods).to eq([])
    expect(described_class.require_auth_methods?).to be(false)
  end

  it "parses a CSV allowlist (downcased, stripped, de-duped)" do
    ENV["SPARC_REQUIRE_AUTH_METHODS"] = " OIDC , piv ,oidc "
    expect(described_class.required_auth_methods).to eq(%w[oidc piv])
    expect(described_class.require_auth_methods?).to be(true)
  end

  it "treats a blank value as off" do
    ENV["SPARC_REQUIRE_AUTH_METHODS"] = "  ,  "
    expect(described_class.require_auth_methods?).to be(false)
  end
end
