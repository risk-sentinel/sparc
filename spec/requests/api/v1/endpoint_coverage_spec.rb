# frozen_string_literal: true

require "rails_helper"

# Release gate: the /api/v1 surface is pinned to a committed snapshot
# (spec/fixtures/api_v1_endpoints.txt). This guards both directions:
#
#   - an endpoint disappearing (accidental route loss) FAILS the build, so we
#     can "validate that all expected endpoints exist";
#   - a NEW endpoint that isn't in the snapshot FAILS until it's registered,
#     forcing the author to (a) confirm it's intentional and (b) add a spec for
#     it — the "new CRUD requires an API endpoint + spec" guardrail.
#
# Regenerate the snapshot intentionally (after consciously adding/removing an
# endpoint) with:
#
#   bin/rails runner '
#     rows = Rails.application.routes.routes.filter_map do |r|
#       p = r.path.spec.to_s.sub(/\(\.:format\)\z/, "")
#       next unless p.start_with?("/api/v1/")
#       v = r.verb.to_s.gsub(/[^A-Z|]/, "").split("|").first
#       next if v.to_s.empty?
#       "#{v} #{p}"
#     end.uniq.sort
#     File.write("spec/fixtures/api_v1_endpoints.txt", "<header>\n" + rows.join("\n") + "\n")
#   '
RSpec.describe "API v1 endpoint coverage (release gate)", type: :request do
  SNAPSHOT_PATH = Rails.root.join("spec/fixtures/api_v1_endpoints.txt")

  def live_endpoints
    Rails.application.routes.routes.filter_map do |route|
      path = route.path.spec.to_s.sub(/\(\.:format\)\z/, "")
      next unless path.start_with?("/api/v1/")

      verb = route.verb.to_s.gsub(/[^A-Z|]/, "").split("|").first
      next if verb.to_s.empty?

      "#{verb} #{path}"
    end.uniq.sort
  end

  def snapshot_endpoints
    File.readlines(SNAPSHOT_PATH, chomp: true)
        .reject { |line| line.blank? || line.start_with?("#") }
        .sort
  end

  it "every expected /api/v1 endpoint still exists (no accidental route loss)" do
    missing = snapshot_endpoints - live_endpoints
    expect(missing).to be_empty,
      "Expected /api/v1 endpoints are GONE (a route was removed). If intentional, " \
      "regenerate the snapshot:\n  #{missing.join("\n  ")}"
  end

  it "no /api/v1 endpoint exists outside the registered snapshot" do
    added = live_endpoints - snapshot_endpoints
    expect(added).to be_empty,
      "New /api/v1 endpoint(s) not in the snapshot. Register them (and add a request " \
      "spec per the API-first guardrail), then regenerate the snapshot:\n  #{added.join("\n  ")}"
  end

  it "pins the full surface to a known size" do
    expect(live_endpoints.size).to eq(snapshot_endpoints.size)
  end
end
