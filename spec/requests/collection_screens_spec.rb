# frozen_string_literal: true

require "rails_helper"

# #888 — every collection screen, held to the same contract.
#
# One file rather than one per screen, because the point is that they behave
# identically: a reviewer should be able to see at a glance which screens are
# migrated and what each one considers its actions.
RSpec.describe "Collection screens", type: :request do
  let(:admin) { create(:user, :admin) }

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    sign_in_as(admin)
  end

  describe "System Security Plans" do
    it_behaves_like "a collection screen",
      path: -> { ssp_documents_path },
      screen: :ssp_documents,
      create: -> { create(:ssp_document, name: "Findable Widget", status: "completed") },
      search_term: "Findable",
      actions: %w[View Delete]
  end

  describe "Security Assessment Reports" do
    it_behaves_like "a collection screen",
      path: -> { sar_documents_path },
      screen: :sar_documents,
      create: -> { create(:sar_document, name: "Findable Widget", status: "completed") },
      search_term: "Findable",
      actions: %w[View Delete]
  end

  describe "Security Assessment Plans" do
    it_behaves_like "a collection screen",
      path: -> { sap_documents_path },
      screen: :sap_documents,
      create: -> { create(:sap_document, name: "Findable Widget", status: "completed") },
      search_term: "Findable",
      actions: %w[View Delete]
  end

  describe "POA&M documents" do
    it_behaves_like "a collection screen",
      path: -> { poam_documents_path },
      screen: :poam_documents,
      create: -> { create(:poam_document, name: "Findable Widget", status: "completed") },
      search_term: "Findable",
      actions: %w[View Delete]
  end

  describe "Component Definitions" do
    it_behaves_like "a collection screen",
      path: -> { cdef_documents_path },
      screen: :cdef_documents,
      create: -> { create(:cdef_document, name: "Findable Widget", status: "completed") },
      search_term: "Findable",
      actions: %w[View Delete],
      bulk_select: true
  end

  describe "Control catalogs" do
    it_behaves_like "a collection screen",
      path: -> { control_catalogs_path },
      screen: :control_catalogs,
      create: -> { create(:control_catalog, name: "Findable Widget") },
      search_term: "Findable",
      actions: %w[View]
  end

  describe "Profiles" do
    it_behaves_like "a collection screen",
      path: -> { profile_documents_path },
      screen: :profile_documents,
      create: -> { create(:profile_document, name: "Findable Widget") },
      search_term: "Findable",
      actions: %w[View]
  end

  describe "Authorization boundaries" do
    it_behaves_like "a collection screen",
      path: -> { authorization_boundaries_path },
      screen: :authorization_boundaries,
      create: -> { create(:authorization_boundary, name: "Findable Widget") },
      search_term: "Findable",
      actions: %w[View],
      bulk_select: true
  end

  describe "Control mappings" do
    it_behaves_like "a collection screen",
      path: -> { control_mappings_path },
      screen: :control_mappings,
      create: -> { create(:control_mapping, name: "Findable Widget") },
      search_term: "Findable",
      actions: %w[View]
  end

  describe "Converters" do
    it_behaves_like "a collection screen",
      path: -> { converters_path },
      screen: :converters,
      create: -> { create(:converter, name: "Findable Widget") },
      search_term: "Findable",
      actions: %w[View]
  end

  describe "Evidence" do
    it_behaves_like "a collection screen",
      path: -> { evidences_path },
      screen: :evidences,
      create: -> { create(:evidence, title: "Findable Widget") },
      search_term: "Findable",
      actions: %w[View]
  end

  describe "Federation peers" do
    it_behaves_like "a collection screen",
      path: -> { federation_peers_path },
      screen: :federation_peers,
      create: -> { create(:federation_peer, name: "Findable Widget") },
      search_term: "Findable"
  end

  describe "Leveraged POA&Ms" do
    it_behaves_like "a collection screen",
      path: -> { leveraged_poam_documents_path },
      screen: :leveraged_poam_documents,
      create: lambda {
        leveraged = create(:authorization_boundary)
        create(:leveraged_authorization, leveraging_boundary: create(:authorization_boundary),
                                         leveraged_boundary: leveraged)
        create(:poam_document, name: "Findable Widget", authorization_boundary: leveraged)
      },
      search_term: "Findable",
      actions: %w[View]
  end

  # The queues are Arrays, not relations — approval authority is decided per
  # record — so they exercise the Array pagination and in-memory search paths.
  describe "Promotion queue" do
    it_behaves_like "a collection screen",
      path: -> { promotion_queue_index_path },
      screen: :promotion_queue,
      create: -> { create(:back_matter_resource, title: "Findable Widget", promotion_status: "pending_review") },
      search_term: "Findable",
      actions: %w[Approve Reject]
  end

  describe "Review queue" do
    it_behaves_like "a collection screen",
      path: -> { review_queue_index_path },
      screen: :review_queue,
      create: lambda {
        submitter = create(:user)
        create(:control_catalog, name: "Findable Widget",
                                 approval_status: "pending_review",
                                 submitted_by_user: submitter)
      },
      search_term: "Findable",
      actions: %w[Approve Reject]
  end

  describe "Authoritative sources" do
    it_behaves_like "a collection screen",
      path: -> { authoritative_sources_path },
      screen: :authoritative_sources,
      create: -> { create(:back_matter_resource, title: "Findable Widget", source: "authoritative") },
      search_term: "Findable"
  end
end
