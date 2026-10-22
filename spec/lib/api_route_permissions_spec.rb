# frozen_string_literal: true

require "rails_helper"

# #1233 — discovery advertises every route by this table, so a route without a
# rule would silently vanish from discovery, which is how 157 of 202 paths did.
RSpec.describe ApiRoutePermissions do
  let(:routes) { ApiEndpointCatalog.routes }

  it "has a rule for every /api/v1 route" do
    unmapped = routes.reject { |r| described_class.rule_for(r) }.map(&:key).uniq

    expect(unmapped).to be_empty,
      "No ApiRoutePermissions rule for: #{unmapped.join(', ')}. Add the controller (and the " \
      "check it makes) to app/lib/api_route_permissions.rb."
  end

  it "has no entry for a controller that serves no route" do
    live = routes.map { |r| described_class.controller_of(r) }.uniq

    expect(described_class::RULES.keys - live).to be_empty
  end

  it "names only permission keys that exist" do
    keys = described_class::RULES.values.flat_map { |entry|
      [ entry[:read], entry[:write], *entry.fetch(:actions, {}).values ]
    }.flat_map { |rule| rule.is_a?(Hash) ? rule[:all] : Array(rule) }
     .select { |k| k.is_a?(String) && !k.start_with?("role:") }.uniq

    expect(keys - Role::PERMISSION_KEYS.map(&:to_s)).to be_empty
  end

  describe ".satisfied?" do
    let(:user) { create(:user) }

    before { allow(user).to receive(:instance_administrator?).and_return(false) }

    it "admits an instance administrator to every rule" do
      admin = create(:user, :admin)
      expect(described_class.satisfied?(admin, :admin)).to be(true)
      expect(described_class.satisfied?(admin, [ "ssp.read" ])).to be(true)
    end

    it "refuses :admin to anyone else and admits :authenticated" do
      expect(described_class.satisfied?(user, :admin)).to be(false)
      expect(described_class.satisfied?(user, :authenticated)).to be(true)
    end

    it "needs ANY key of a list and ALL keys of an all-rule" do
      allow(user).to receive(:has_any_permission?) { |key| key == "ssp.read" }

      expect(described_class.satisfied?(user, [ "sar.read", "ssp.read" ])).to be(true)
      expect(described_class.satisfied?(user, [ "sar.read" ])).to be(false)
      expect(described_class.satisfied?(user, { all: [ "ssp.read", "authorization_boundaries.read" ] })).to be(false)
    end

    it "reads a role: entry as a role, not a permission" do
      allow(user).to receive(:has_role?).with("policy_manager").and_return(true)

      expect(described_class.satisfied?(user, [ "role:policy_manager" ])).to be(true)
    end

    it "refuses a route with no rule" do
      expect(described_class.satisfied?(user, nil)).to be(false)
    end
  end
end
