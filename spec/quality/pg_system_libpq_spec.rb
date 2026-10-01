# frozen_string_literal: true

require "rails_helper"

# #1204 — pg must be built against the system libpq, never the precompiled gem.
#
# The precompiled pg ships its own libpq (ports/<arch>/lib/libpq-ruby-pg.so.1)
# with OpenSSL built in, and that copy is what database TLS ran on: out of date
# (OpenSSL 3.6.0 — 5 critical / 26 high by CPE, all fixed upstream) and invisible
# to every scanner. The Gemfile forces the ruby platform. Bundler records that
# option in the Gemfile only (the lockfile keeps listing the precompiled
# variants), so this checks what is actually LOADED — which is what a
# `bundle update` or a dropped option would silently change back.
RSpec.describe "pg is built against the system libpq (#1204)" do
  let(:spec) { Gem.loaded_specs.fetch("pg") }

  it "loads pg compiled from source, not a precompiled platform gem" do
    expect(spec.platform.to_s).to eq("ruby"),
      "pg #{spec.version} loaded as #{spec.platform}: the precompiled gem bundles its own libpq and OpenSSL (#1204)"
  end

  it "carries no bundled libpq" do
    bundled = Dir[File.join(spec.full_gem_path, "ports", "**", "libpq*")]
    expect(bundled).to be_empty, "bundled libpq found: #{bundled.join(', ')}"
  end

  it "is forced to the ruby platform in the Gemfile" do
    pg = Bundler::Dsl.evaluate(Rails.root.join("Gemfile"), nil, {}).dependencies.find { |d| d.name == "pg" }
    expect(pg.force_ruby_platform).to be(true)
  end
end
