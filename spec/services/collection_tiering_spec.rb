# frozen_string_literal: true

require "rails_helper"

# #948 — tiering is PRESENTATION over an already-scoped relation.
#
# The load-bearing assertion in this file is the visible-set one: tiering must
# not add or remove a single record. Everything else is grouping detail.
RSpec.describe CollectionTiering do
  let(:org_a)    { create(:organization, name: "Alpha Agency") }
  let(:org_b)    { create(:organization, name: "Beta Bureau") }
  let(:bound_a1) { create(:authorization_boundary, name: "A1 Platform", organization: org_a) }
  let(:bound_a2) { create(:authorization_boundary, name: "A2 Mission", organization: org_a) }
  let(:bound_b1) { create(:authorization_boundary, name: "B1 Service", organization: org_b) }

  def tiering_over(scope, instance_label: "Instance-wide")
    described_class.new(scope: scope, records: scope.to_a, instance_label: instance_label)
  end

  describe "when to tier at all" do
    # Owner decision: automatic, not a view mode. A single-boundary user is not
    # made worse off because they never meet a tree with one branch.
    it "does not tier when every record shares one boundary" do
      create_list(:evidence, 2, authorization_boundary: bound_a1)

      expect(tiering_over(Evidence.all)).not_to be_tiered
    end

    it "does not tier when the collection is empty" do
      expect(tiering_over(Evidence.all)).not_to be_tiered
    end

    it "tiers across two boundaries" do
      create(:evidence, authorization_boundary: bound_a1)
      create(:evidence, authorization_boundary: bound_b1)

      expect(tiering_over(Evidence.all)).to be_tiered
    end

    # The split a user most needs to see: some of their evidence is visible to
    # everyone and some is not.
    it "tiers when one boundary is set and one record is instance-wide" do
      create(:evidence, authorization_boundary: bound_a1)
      create(:evidence, authorization_boundary: nil)

      expect(tiering_over(Evidence.all)).to be_tiered
    end
  end

  describe "the shape of the tiers" do
    before do
      create(:evidence, authorization_boundary: bound_a1)
      create(:evidence, authorization_boundary: bound_a2)
      create(:evidence, authorization_boundary: bound_b1)
      create(:evidence, authorization_boundary: nil)
    end

    it "puts the instance tier first, under the label the caller supplied" do
      tiers = tiering_over(Evidence.all, instance_label: "Provider / instance-wide").tiers

      expect(tiers.first.label).to eq("Provider / instance-wide")
      expect(tiers.first).to be_instance
    end

    it "orders organizations by name and nests their boundaries" do
      tiers = tiering_over(Evidence.all).tiers
      organizations = tiers.reject(&:instance?)

      expect(organizations.map(&:label)).to eq([ "Alpha Agency", "Beta Bureau" ])
      expect(organizations.first.boundaries.map(&:label)).to eq([ "A1 Platform", "A2 Mission" ])
    end

    it "counts each organization as the sum of its boundaries" do
      tiers = tiering_over(Evidence.all).tiers
      alpha = tiers.find { |t| t.label == "Alpha Agency" }

      expect(alpha.count).to eq(2)
    end
  end

  # `AuthorizationBoundary belongs_to :organization, optional: true`, so the
  # middle tier can be missing. The issue's three tiers do not cover it, and
  # folding these into the instance tier would say something false: the records
  # DO belong to a system.
  describe "a boundary with no organization" do
    it "gets its own group, not the instance tier" do
      orphan = create(:authorization_boundary, name: "Unfiled System", organization: nil)
      create(:evidence, authorization_boundary: orphan)
      create(:evidence, authorization_boundary: bound_a1)

      tiers = tiering_over(Evidence.all).tiers
      group = tiers.find { |t| t.key == "unaffiliated" }

      expect(group).to be_present
      expect(group).not_to be_instance
      expect(group.boundaries.map(&:label)).to eq([ "Unfiled System" ])
    end
  end

  # THE acceptance criterion. Tiering changes presentation only.
  describe "the visible set is identical before and after" do
    it "contains exactly the records the flat relation contains" do
      create(:evidence, authorization_boundary: bound_a1)
      create(:evidence, authorization_boundary: bound_a2)
      create(:evidence, authorization_boundary: bound_b1)
      create(:evidence, authorization_boundary: nil)
      create(:evidence, authorization_boundary: create(:authorization_boundary, organization: nil))

      scope = Evidence.all
      flat  = scope.to_a

      tiered = tiering_over(scope).tiers
                 .flat_map(&:boundaries).flat_map(&:records)

      expect(tiered.map(&:id).sort).to eq(flat.map(&:id).sort)
    end

    # The rule that makes generalising this safe: the query object must never
    # re-derive who may see what. If the caller narrows the scope, tiering shows
    # exactly that and nothing more.
    it "never reaches beyond the scope it was given" do
      visible = create(:evidence, authorization_boundary: bound_a1)
      create(:evidence, authorization_boundary: bound_b1) # outside the scope

      scope = Evidence.where(id: visible.id)
      tiered = described_class.new(scope: scope, records: scope.to_a,
                                   instance_label: "Instance-wide")
                              .tiers.flat_map(&:boundaries).flat_map(&:records)

      expect(tiered.map(&:id)).to eq([ visible.id ])
    end
  end

  # Counts describe the whole filtered collection; records describe the page.
  # A tier reading 24 while showing 8 is the intended behaviour.
  describe "counts versus the page" do
    it "counts the full scope even when only a page of records is passed" do
      create_list(:evidence, 3, authorization_boundary: bound_a1)
      scope = Evidence.all

      tiering = described_class.new(scope: scope, records: scope.limit(1).to_a,
                                    instance_label: "Instance-wide")
      boundary_tier = tiering.tiers.flat_map(&:boundaries).first

      expect(boundary_tier.count).to eq(3)
      expect(boundary_tier.records.length).to eq(1)
    end
  end
end
