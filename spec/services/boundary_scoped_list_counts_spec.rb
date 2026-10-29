# frozen_string_literal: true

require "rails_helper"

# 1.18.0-rf #1292 — BoundaryScopedList.counts_by_boundary is the grouped form of
# each narrowing rule. The Boundary filter shows these numbers beside each
# boundary, so for EVERY type and EVERY boundary the count must equal what that
# boundary's list holds: `narrow(type, scope, id).count`. A grouped query that
# drifted from its rule (a CDEF counted twice, global evidence left out) would
# promise records the list does not show.
RSpec.describe "BoundaryScopedList counts by boundary (#1292)" do
  let!(:alpha) { create(:authorization_boundary, name: "Alpha ATO") }
  let!(:bravo) { create(:authorization_boundary, name: "Bravo ATO") }
  let!(:empty) { create(:authorization_boundary, name: "Empty ATO") }
  let(:boundaries) { [ alpha, bravo, empty ] }

  before do
    # Owned types: two in Alpha, one in Bravo, and one attached to none.
    %i[ssp_document sap_document sar_document poam_document].each do |factory|
      create_list(factory, 2, authorization_boundary: alpha)
      create(factory, authorization_boundary: bravo)
      create_legacy_orphan(factory)
    end
    # Evidence: global evidence (no boundary) belongs to every boundary's list.
    create_list(:evidence, 2, authorization_boundary: alpha)
    create(:evidence, authorization_boundary: bravo)
    create_list(:evidence, 2, authorization_boundary: nil)

    # CDEFs, each way one belongs to a boundary, and one belonging two ways
    # (counted once).
    own = create(:cdef_document)
    CdefScopeService.apply(own, scope: "boundary", authorization_boundary_id: alpha.id)
    linked = create(:cdef_document, globally_available: true)
    create(:boundary_cdef_document, boundary: create(:boundary, authorization_boundary: alpha), cdef_document: linked)
    create(:boundary_cdef_document, boundary: create(:boundary, authorization_boundary: bravo), cdef_document: linked)
    consumed = create(:cdef_document, globally_available: true)
    ssp = SspDocument.find_by!(authorization_boundary: bravo)
    create(:ssp_component, ssp_document: ssp, cdef_document: consumed)
    create(:boundary_cdef_document, boundary: create(:boundary, authorization_boundary: bravo), cdef_document: consumed)
    create(:cdef_document, globally_available: true) # belongs to none

    # Leveraged POA&Ms: Alpha leverages Bravo.
    create(:leveraged_authorization, leveraging_boundary: alpha, leveraged_boundary: bravo)

    create_list(:cdef_coverage_run, 2, authorization_boundary: alpha)
    create(:cdef_coverage_run, authorization_boundary: nil)
  end

  {
    ssp: SspDocument, sap: SapDocument, sar: SarDocument, poam: PoamDocument, evidence: Evidence,
    cdef: CdefDocument, leveraged_poam: PoamDocument, cdef_coverage: CdefCoverageRun
  }.each do |type, model|
    it "equals each boundary's list for #{type}" do
      counts = BoundaryScopedList.counts_by_boundary(type, model.all)

      boundaries.each do |b|
        expect(counts[b.id]).to eq(BoundaryScopedList.narrow(type, model.all, b.id).count), "#{type} in #{b.name}"
      end
    end
  end

  it "has the numbers the data above implies, so equal-but-wrong cannot pass" do
    count = ->(type, model) { BoundaryScopedList.counts_by_boundary(type, model.all).values_at(alpha.id, bravo.id, empty.id) }

    expect(count.(:ssp, SspDocument)).to eq([ 2, 1, 0 ])
    expect(count.(:evidence, Evidence)).to eq([ 4, 3, 2 ])
    expect(count.(:cdef, CdefDocument)).to eq([ 2, 2, 0 ])
    expect(count.(:leveraged_poam, PoamDocument)).to eq([ 1, 0, 0 ])
    expect(count.(:cdef_coverage, CdefCoverageRun)).to eq([ 2, 0, 0 ])
  end

  it "counts only within the scope it is given" do
    scope = SspDocument.where(authorization_boundary: alpha).limit(1)
    expect(BoundaryScopedList.counts_by_boundary(:ssp, scope).values_at(alpha.id, bravo.id)).to eq([ 1, 0 ])
  end

  it "is one query however many boundaries there are" do
    queries = []
    callback = ->(*, payload) { queries << payload[:sql] unless payload[:name].in?([ "SCHEMA", "TRANSACTION" ]) }
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      BoundaryScopedList.counts_by_boundary(:cdef, CdefDocument.all)
    end
    expect(queries.size).to eq(1)
  end

  it "matches nothing for a value that is not an id or `none`" do
    expect(BoundaryScopedList.narrow(:ssp, SspDocument.all, "abc")).to be_empty
    expect(BoundaryScopedList.narrow(:ssp, SspDocument.all, "all")).to be_empty
    # An integer column would read this as Alpha's id.
    expect(BoundaryScopedList.narrow(:ssp, SspDocument.all, "#{alpha.id}abc")).to be_empty
    # The evidence rule would otherwise still add the global evidence.
    expect(BoundaryScopedList.narrow(:evidence, Evidence.all, "abc")).to be_empty
    expect(BoundaryScopedList.narrow(:ssp, SspDocument.all, "none").count).to eq(1)
  end
end
