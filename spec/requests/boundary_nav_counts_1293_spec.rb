# frozen_string_literal: true

require "rails_helper"

# 1.18.0-rf #1293 — the navigation counts.
#
# A count must equal what its list shows the same user for the same boundary,
# must cost a fixed number of queries however much data there is, and the API
# must report the same numbers.
RSpec.describe "Boundary navigation counts (#1293)", type: :request do
  let(:alpha) { create(:authorization_boundary, name: "Alpha ATO") }
  let(:bravo) { create(:authorization_boundary, name: "Bravo ATO") }
  let(:hidden) { create(:authorization_boundary, name: "Hidden ATO") }
  let(:member_role) do
    perms = %w[authorization_boundaries ssp sap sar poam evidence cdef].to_h { [ "#{_1}.read", true ] }
    create(:role, :authorization_boundary_scoped, permissions: perms)
  end
  let(:member) do
    create(:user).tap do |u|
      [ alpha, bravo ].each { create(:user_role, user: u, role: member_role, authorization_boundary: _1) }
    end
  end

  # [factory, list path, show path] for each count.
  lists = {
    ssp:      [ :ssp_document,  "/ssp_documents" ],
    sap:      [ :sap_document,  "/sap_documents" ],
    sar:      [ :sar_document,  "/sar_documents" ],
    poam:     [ :poam_document, "/poam_documents" ],
    evidence: [ :evidence,      "/evidences" ]
  }

  let!(:docs) do
    lists.to_h do |type, (factory, _)|
      made = [ alpha, alpha, bravo, hidden ].map { create(factory, authorization_boundary: _1) }
      made << create(factory, authorization_boundary: nil) if type == :evidence
      [ type, made ]
    end
  end
  let!(:cdefs) do
    own = create(:cdef_document).tap { CdefScopeService.apply(_1, scope: "boundary", authorization_boundary_id: alpha.id) }
    [ own, create(:cdef_document, globally_available: true) ]
  end

  def listed_count(type, path, params)
    get path, params: params
    expect(response).to have_http_status(:ok)
    (type == :cdef ? cdefs : docs.fetch(type)).count { response.body.include?(%(href="#{polymorphic_path(_1)}")) }
  end

  def sql_queries
    queries = []
    callback = lambda do |*, payload|
      queries << payload[:sql] unless payload[:name].in?([ "SCHEMA", "TRANSACTION" ]) || payload[:cached]
    end
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") { yield }
    queries
  end

  before do
    allow(SparcConfig).to receive_messages(any_auth_enabled?: true, nav_shell?: true)
    sign_in_as(member)
  end

  it "equals what each list shows the same user, in a boundary and across everything reachable" do
    { alpha => { authorization_boundary_id: alpha.id }, nil => {} }.each do |boundary, params|
      counts = BoundaryNavCounts.for(boundary, member)

      lists.merge(cdef: [ nil, "/cdef_documents" ]).each do |type, (_, path)|
        expect(counts[type]).to eq(listed_count(type, path, params)),
                                "#{type} in #{boundary&.name || 'all'}"
      end
    end

    # And the numbers themselves, so equal-but-wrong cannot pass: two of
    # Alpha's, plus the global evidence; three reachable, never Hidden's.
    alpha_counts = BoundaryNavCounts.for(alpha, member)
    expect(alpha_counts.values_at(:ssp, :sap, :sar, :poam, :evidence, :cdef)).to eq([ 2, 2, 2, 2, 3, 1 ])
    all_counts = BoundaryNavCounts.for(nil, member)
    expect(all_counts.values_at(:ssp, :sap, :sar, :poam, :evidence, :cdef)).to eq([ 3, 3, 3, 3, 4, 2 ])
  end

  it "costs the same number of queries however many boundaries and documents there are" do
    small = sql_queries { BoundaryNavCounts.for(alpha, member) }

    5.times do
      extra = create(:authorization_boundary)
      create(:user_role, user: member, role: member_role, authorization_boundary: extra)
      lists.each_value { |(factory, _)| create_list(factory, 2, authorization_boundary: extra) }
    end
    member.reload

    large = sql_queries { BoundaryNavCounts.for(alpha, member) }
    expect(large.size).to eq(small.size)
    # One COUNT per type. The rest is the permission scope each list applies
    # (BoundaryScopedDocument.scope: is the user an admin, which boundaries do
    # they hold), at most two per type and never per record.
    expect(small.grep(/\ASELECT COUNT\(/i).size).to eq(BoundaryNavCounts::LISTS.size)
    expect(small.size).to be <= 3 * BoundaryNavCounts::LISTS.size
  end

  it "covers the types the boundary sidebar links" do
    expect(BoundaryNavCounts::LISTS.keys).to eq(BoundaryScopedList.types)
  end

  it "is what the API reports for the boundary" do
    token = ApiToken.generate!(user: member, name: "caller", expires_at: 1.day.from_now)
    get "/api/v1/authorization_boundaries/#{alpha.id}", headers: { "Authorization" => "Bearer #{token.plaintext_token}" }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body.dig("data", "counts")).to eq(BoundaryNavCounts.for(alpha, member).stringify_keys)
  end

  context "with sign-in disabled" do
    before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(false) }

    it "counts every record, as the lists show them" do
      expect(BoundaryNavCounts.for(nil, nil).values_at(:ssp, :evidence)).to eq([ 4, 5 ])
      expect(BoundaryNavCounts.for(alpha, nil).values_at(:ssp, :evidence)).to eq([ 2, 3 ])
    end
  end
end
