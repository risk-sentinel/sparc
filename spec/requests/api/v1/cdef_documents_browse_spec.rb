# frozen_string_literal: true

require "rails_helper"

# #887 — API parity for the CDEF browser.
#
# The gap this closes: the card view derived services, partitions, capabilities
# and check coverage in the view layer, so an API consumer asking the same
# question got a thinner answer — and `?q=us-east` worked in the UI while
# returning nothing here. Everything the browser knows now comes from the same
# query object and the same component index.
RSpec.describe "Api::V1::CdefDocuments browse parity", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:api_token) { ApiToken.generate!(user: admin, name: "Test") }
  let(:auth_headers) { { "Authorization" => "Bearer #{api_token.plaintext_token}" } }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  def component(document, **attrs)
    attrs = { cdef_document: document, component_uuid: SecureRandom.uuid }.merge(attrs)
    attrs[:search_blob] ||= CdefComponent.build_search_blob(attrs)
    CdefComponent.create!(attrs)
  end

  def json = JSON.parse(response.body)
  def names = json["data"].map { |d| d["name"] }

  describe "search" do
    let!(:gov) { create(:cdef_document, name: "GovCloud IAM") }
    let!(:commercial) { create(:cdef_document, name: "Commercial Storage") }

    before do
      component(gov, service_id: "IAM", title: "AWS IAM",
                     region_ids: %w[us-gov-west-1], partitions: %w[aws-us-gov],
                     declared_capabilities: %w[MFA], native_control_ids: %w[IA-2.1],
                     has_checks: true, check_ids: %w[IAM_MFA_ENABLED])
      component(commercial, service_id: "S3", title: "Amazon S3",
                            region_ids: %w[us-east-1], partitions: %w[aws],
                            native_control_ids: %w[SC-28], has_checks: false)
    end

    # This is the parity bug in its most concrete form: the same query string
    # that worked in the browser returned nothing here.
    it "matches a region id, like the UI does" do
      get api_v1_cdef_documents_path, params: { q: "us-east" }, headers: auth_headers

      expect(names).to eq([ "Commercial Storage" ])
    end

    it "matches a control id" do
      get api_v1_cdef_documents_path, params: { q: "IA-2" }, headers: auth_headers

      expect(names).to eq([ "GovCloud IAM" ])
    end

    it "matches an automated check id" do
      get api_v1_cdef_documents_path, params: { q: "IAM_MFA" }, headers: auth_headers

      expect(names).to eq([ "GovCloud IAM" ])
    end

    it "still matches the document's own name" do
      get api_v1_cdef_documents_path, params: { q: "Commercial" }, headers: auth_headers

      expect(names).to eq([ "Commercial Storage" ])
    end
  end

  describe "facets" do
    let!(:gov) { create(:cdef_document, name: "GovCloud IAM") }
    let!(:commercial) { create(:cdef_document, name: "Commercial Storage") }

    before do
      component(gov, service_id: "IAM", title: "AWS IAM", partitions: %w[aws-us-gov],
                     declared_capabilities: %w[MFA], has_checks: true)
      component(commercial, service_id: "S3", title: "Amazon S3", partitions: %w[aws],
                            has_checks: false)
    end

    it "narrows by partition" do
      get api_v1_cdef_documents_path, params: { partition: "aws-us-gov" }, headers: auth_headers

      expect(names).to eq([ "GovCloud IAM" ])
    end

    it "narrows by capability" do
      get api_v1_cdef_documents_path, params: { capability: "MFA" }, headers: auth_headers

      expect(names).to eq([ "GovCloud IAM" ])
    end

    it "narrows by automated-check coverage in both directions" do
      get api_v1_cdef_documents_path, params: { checks: "true" }, headers: auth_headers
      expect(names).to eq([ "GovCloud IAM" ])

      get api_v1_cdef_documents_path, params: { checks: "false" }, headers: auth_headers
      expect(names).to eq([ "Commercial Storage" ])
    end

    it "intersects a facet with the search rather than replacing it" do
      get api_v1_cdef_documents_path, params: { q: "IAM", partition: "aws" }, headers: auth_headers

      expect(names).to be_empty
    end

    # A consumer that paginates needs to know what produced the result set
    # without re-parsing its own query string.
    it "echoes the applied facets in meta" do
      get api_v1_cdef_documents_path,
          params: { partition: "aws-us-gov", capability: "MFA" }, headers: auth_headers

      expect(json["meta"]["facets"]).to eq("partition" => "aws-us-gov", "capability" => "MFA")
    end

    it "reports no facets when none are applied" do
      get api_v1_cdef_documents_path, headers: auth_headers

      expect(json["meta"]["facets"]).to eq({})
    end
  end

  describe "the enriched shape" do
    let!(:document) { create(:cdef_document, name: "WorkSpaces") }

    before do
      component(document, component_type: "service", service_id: "WorkSpaces",
                          title: "Amazon WorkSpaces",
                          description: "Managed virtual desktops.",
                          region_ids: %w[us-east-1 us-gov-west-1],
                          partitions: %w[aws aws-us-gov],
                          declared_capabilities: %w[MFA], derived_capabilities: %w[Encryption\ at\ Rest],
                          native_control_ids: %w[AC-2], enriched_control_ids: %w[SC-28],
                          has_checks: true, check_ids: %w[WORKSPACES_ROOT_VOLUME_ENCRYPTION],
                          mapping_sources: %w[aws_direct], availability: "GA",
                          lifecycle_stage: "production")
    end

    subject(:components) do
      get api_v1_cdef_documents_path, headers: auth_headers
      json["data"].first["components"]
    end

    it "names the services rather than just counting them" do
      expect(components["service_titles"]).to eq([ "Amazon WorkSpaces" ])
      expect(components["service_count"]).to eq(1)
    end

    # The filename says "workspaces"; only the component says what it is.
    it "carries the component's own description" do
      expect(components["description"]).to eq("Managed virtual desktops.")
    end

    it "translates partition ids rather than leaving the caller to decode them" do
      expect(components["partitions"]).to contain_exactly(
        { "id" => "aws", "label" => "AWS Commercial" },
        { "id" => "aws-us-gov", "label" => "AWS GovCloud" }
      )
    end

    it "keeps declared and derived capabilities apart" do
      expect(components["capabilities"]).to eq(
        "declared" => [ "MFA" ], "derived" => [ "Encryption at Rest" ]
      )
    end

    # What the vendor asserted vs what SPARC mapped in is the whole question
    # behind "can I trust this coverage", so the counts stay separate.
    it "keeps native and enriched control counts apart" do
      expect(components["control_counts"]).to eq("native" => 1, "enriched" => 1)
    end

    it "reports automated-check coverage" do
      expect(components["check_count"]).to eq(1)
    end

    it "reports region coverage" do
      expect(components["region_count"]).to eq(2)
    end
  end

  describe "a definition with nothing indexed" do
    let!(:document) { create(:cdef_document, name: "Bare CDEF") }

    # 163 of the 230 upstream AWS definitions assert no control coverage at
    # all. That is a real state, not an error, and it must not force every
    # consumer to nil-check.
    it "returns an empty summary rather than omitting the key" do
      get api_v1_cdef_documents_path, headers: auth_headers
      components = json["data"].first["components"]

      expect(components["count"]).to eq(0)
      expect(components["service_titles"]).to eq([])
      expect(components["partitions"]).to eq([])
      expect(components["control_counts"]).to eq("native" => 0, "enriched" => 0)
    end
  end

  describe "GET /api/v1/cdef_documents/:id" do
    let!(:document) { create(:cdef_document, name: "Detailed CDEF") }

    before do
      component(document, component_type: "service", service_id: "IAM", title: "AWS IAM",
                          partitions: %w[aws-us-gov], has_checks: true,
                          check_ids: %w[IAM_MFA_ENABLED])
      component(document, component_type: "validation", title: "Config Rule check")
    end

    it "lists the components themselves, services first" do
      get api_v1_cdef_document_path(document), headers: auth_headers

      details = json["data"]["component_details"]
      expect(details.map { |c| c["title"] }).to eq([ "AWS IAM", "Config Rule check" ])
      expect(details.first["check_ids"]).to eq([ "IAM_MFA_ENABLED" ])
      expect(details.first["partitions"]).to eq([ { "id" => "aws-us-gov", "label" => "AWS GovCloud" } ])
    end

    # The list is a row-count multiplier on the index for no benefit — the
    # roll-up is what a list needs.
    it "does not list them on the index" do
      get api_v1_cdef_documents_path, headers: auth_headers

      expect(json["data"].first).not_to have_key("component_details")
      expect(json["data"].first["components"]["count"]).to eq(2)
    end
  end
end
