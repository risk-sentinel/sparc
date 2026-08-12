# frozen_string_literal: true

require "rails_helper"

# #908 — the mechanics every filtered index screen shares.
#
# Exercised through the real subclasses rather than an anonymous test double,
# so a change that breaks a shipping screen fails here rather than passing
# against a fixture that resembles one.
RSpec.describe CollectionBrowseQuery do
  describe "narrowing" do
    let!(:rev5_high) do
      create(:control_catalog, name: "NIST 800-53 Rev 5 HIGH", version: "5.2.0",
                               oscal_version: "1.1.2", source: "OSCAL")
    end
    let!(:rev5_mod) do
      create(:control_catalog, name: "NIST 800-53 Rev 5 MODERATE", version: "5.2.0",
                               oscal_version: "1.1.3", source: "OSCAL")
    end
    let!(:rev4) do
      create(:control_catalog, name: "NIST 800-53 Rev 4", version: "4.0.0",
                               oscal_version: "1.1.2", source: "Import")
    end

    # Scoped to the records this example created rather than the whole table.
    # A local test database can carry seeded catalogs that CI's does not, and a
    # spec that assumes an empty table passes in one place and fails in the
    # other — with the failure blaming the query object rather than the fixture
    # state.
    let(:only_these) { ControlCatalog.where(id: [ rev5_high, rev5_mod, rev4 ].map(&:id)) }

    def records(params)
      CatalogBrowseQuery.new(ActionController::Parameters.new(params), scope: only_these).records
    end

    it "returns everything when nothing is filtered" do
      expect(records({})).to contain_exactly(rev5_high, rev5_mod, rev4)
    end

    it "defaults to the whole collection when no scope is supplied" do
      result = CatalogBrowseQuery.new(ActionController::Parameters.new({})).records

      expect(result).to include(rev5_high, rev5_mod, rev4)
    end

    it "narrows on a single facet" do
      expect(records(oscal_version: "1.1.2")).to contain_exactly(rev5_high, rev4)
    end

    it "INTERSECTS facets rather than unioning them" do
      # "1.1.2 AND Rev 5", not "1.1.2 OR Rev 5". Getting this backwards would
      # widen the result set as the user narrows, which reads as the filter
      # being ignored.
      expect(records(oscal_version: "1.1.2", version: "5.2.0")).to contain_exactly(rev5_high)
    end

    it "intersects a facet with the free-text search" do
      expect(records(q: "Rev 5", oscal_version: "1.1.3")).to contain_exactly(rev5_mod)
    end

    it "ignores a blank facet value rather than matching blank rows" do
      expect(records(oscal_version: "")).to contain_exactly(rev5_high, rev5_mod, rev4)
    end
  end

  describe "choices come from the data, not a hardcoded list" do
    # Same reason as above: scoped to what the example created, so seeded rows
    # in a local test database cannot change the answer.
    def fields_for(records, params = {})
      scope = ControlCatalog.where(id: Array(records).map(&:id))
      CatalogBrowseQuery.new(ActionController::Parameters.new(params), scope: scope).filter_fields
    end

    it "offers exactly the values present" do
      catalogs = [ create(:control_catalog, oscal_version: "1.1.2", version: "5.2.0"),
                   create(:control_catalog, oscal_version: "1.2.1", version: "5.2.0") ]

      field = fields_for(catalogs).find { |f| f[:key] == :oscal_version }

      expect(field[:choices].map(&:last)).to eq(%w[1.1.2 1.2.1])
    end

    it "excludes blank values, which are not a choice a user can mean" do
      catalogs = [ create(:control_catalog, source: "OSCAL"),
                   create(:control_catalog, source: nil),
                   create(:control_catalog, source: "Import") ]

      field = fields_for(catalogs).find { |f| f[:key] == :source }

      expect(field[:choices].map(&:last)).to eq(%w[Import OSCAL])
    end

    it "hides a facet with only one distinct value, because a one-choice dropdown is noise" do
      catalogs = create_list(:control_catalog, 3, oscal_version: "1.1.2")

      expect(fields_for(catalogs).map { |f| f[:key] }).not_to include(:oscal_version)
    end

    it "keeps a one-value facet visible when it is the one currently applied" do
      # Otherwise applying a filter that narrows to a single value makes the
      # control that set it vanish while its effect remains — the user is left
      # with a short list and no visible cause.
      catalogs = create_list(:control_catalog, 3, oscal_version: "1.1.2")

      keys = fields_for(catalogs, oscal_version: "1.1.2").map { |f| f[:key] }

      expect(keys).to include(:oscal_version)
    end
  end

  describe "date ranges" do
    let!(:old_doc) { create(:profile_document, created_at: Date.new(2026, 1, 10).noon) }
    let!(:new_doc) { create(:profile_document, created_at: Date.new(2026, 6, 20).noon) }

    let(:only_these) { ProfileDocument.where(id: [ old_doc, new_doc ].map(&:id)) }

    def records(params)
      ProfileBrowseQuery.new(ActionController::Parameters.new(params), scope: only_these).records
    end

    it "filters from a date" do
      expect(records(created_from: "2026-03-01")).to contain_exactly(new_doc)
    end

    it "filters to a date" do
      expect(records(created_to: "2026-03-01")).to contain_exactly(old_doc)
    end

    it "includes the whole of the 'to' day, not up to its midnight" do
      # A user choosing "to 20 June" means through the end of 20 June. Treating
      # it as the start of the day silently drops everything created that day.
      expect(records(created_to: "2026-06-20")).to include(new_doc)
    end

    it "ignores an unparseable date rather than returning nothing" do
      # A hand-edited query string must not 500, and zero rows would look like
      # a real empty result rather than a bad parameter.
      expect(records(created_from: "banana")).to contain_exactly(old_doc, new_doc)
    end

    it "exposes each end as its own removable param" do
      expect(ProfileBrowseQuery.facet_params).to include(:created_from, :created_to)
      expect(ProfileBrowseQuery.facet_labels[:created_from]).to eq("Created from")
    end
  end

  describe "the scope the caller supplies is never widened" do
    it "cannot reach records outside it" do
      # POA&Ms are boundary-scoped; the query object must narrow what it is
      # given and never re-derive who may see what.
      mine = create(:authorization_boundary)
      theirs = create(:authorization_boundary)
      visible = create(:poam_document, authorization_boundary: mine, oscal_version: "1.1.2")
      create(:poam_document, authorization_boundary: theirs, oscal_version: "1.1.2")

      result = PoamBrowseQuery.new(
        ActionController::Parameters.new(oscal_version: "1.1.2"),
        scope: PoamDocument.where(authorization_boundary_id: mine.id)
      ).records

      expect(result).to contain_exactly(visible)
    end
  end

  describe "facets reached through a join" do
    it "matches every accepted spelling of a control id" do
      evidence = create(:evidence)
      create(:evidence_control_link, evidence: evidence, control_id: "ac-1")
      create(:evidence)

      result = EvidenceBrowseQuery.new(ActionController::Parameters.new(control_id: "AC-01"),
                                       scope: Evidence.all).records

      expect(result).to contain_exactly(evidence)
    end
  end
end
