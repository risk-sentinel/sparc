# frozen_string_literal: true

require "rails_helper"

# 1.18.0-rf #1300 — the Component Definitions list under SPARC_NAV_SHELL:
# source tabs, the source line, what a CDEF applies to, the controls it
# covers and their families, family / applies-to filters, and — only when the
# list is filtered to a boundary with a resolved baseline — coverage of that
# baseline and sorting by it. The API index returns the same facts through
# the same definitions.
RSpec.describe "Component Definitions list (#1300)", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:org) { create(:organization, name: "Acme Org") }
  let(:baseline_ids) { %w[ac-1 ac-2 au-2 sc-7] }
  let(:baseline) do
    controls = baseline_ids.map { { "id" => _1, "title" => _1.upcase } }
    create(:profile_document, resolved_catalog_json: { "catalog" => { "groups" => [ { "id" => "all", "controls" => controls } ] } })
  end
  let(:boundary) { create(:authorization_boundary, name: "Alpha ATO", profile_document: baseline) }

  def cdef_with(controls, **attrs)
    create(:cdef_document, **attrs).tap do |doc|
      controls.each { |id| create(:cdef_control, cdef_document: doc, control_id: id) }
    end
  end

  def in_boundary = { "authorization_boundary_id" => boundary.id.to_s }

  let!(:aws) do
    # Also carries an organization: upstream AWS content is AWS first.
    cdef_with(%w[ac-1 ac-2 au-2], name: "AWS thing", cdef_version: "0.2.1", organization: org,
              import_metadata: { "source_type" => "aws_labs", "fetched_at" => 2.days.ago.iso8601 }.merge(in_boundary)).tap do |doc|
      CdefComponent.create!(cdef_document: doc, component_uuid: SecureRandom.uuid, component_type: "service",
                            title: "Thing", enriched_control_ids: %w[ac-1])
    end
  end
  # si-4 is outside the baseline: it is not coverage.
  let!(:org_cdef)   { cdef_with(%w[sc-7 si-4], name: "Org thing", organization: org, import_metadata: in_boundary) }
  let!(:sparc_cdef) { cdef_with(%w[ac-1], name: "Baseline thing", profile_document: create(:profile_document)) }
  let!(:local_cdef) { cdef_with(%w[SV-1r1_rule], name: "Local thing") }

  def page = Nokogiri::HTML(response.body)

  def row(name) = page.css("[data-testid=collection-row]").find { _1.text.include?(name) }

  def tab_count(slug) = page.at_css("[data-testid=status-tab][data-tab='#{slug}']")["data-count"].to_i

  def names = page.css("[data-testid=collection-row] .sparc-collection-row__title").map { _1.text.squish }

  before do
    allow(SparcConfig).to receive_messages(any_auth_enabled?: true, nav_shell?: true)
    sign_in_as(admin)
  end

  describe "source" do
    it "counts each source in a tab, and a tab lists exactly its own" do
      get cdef_documents_path(view: "list")

      expect(%w[all aws-labs organization sparc-baseline local].map { tab_count(_1) }).to eq([ 4, 1, 1, 1, 1 ])

      { "aws" => "AWS thing", "org" => "Org thing", "sparc" => "Baseline thing", "local" => "Local thing" }.each do |kind, name|
        get cdef_documents_path(view: "list", source: kind)
        expect(names).to eq([ name ]), kind
      end
    end

    it "lists nothing for a source that does not exist" do
      get cdef_documents_path(view: "list", source: "bogus")
      expect(names).to be_empty
    end

    it "says where each came from, which version, and when it last changed" do
      get cdef_documents_path(view: "list")

      expect(row("AWS thing").text.squish).to include("awslabs/oscal-content · v0.2.1 · synced 2 days ago")
      expect(row("Org thing").text.squish).to include("Acme Org")
      expect(row("Local thing").text.squish).to match(/Local · .*edited/)
    end
  end

  describe "what a CDEF covers" do
    it "shows the controls it covers, their families, what it applies to and SPARC's enrichment" do
      get cdef_documents_path(view: "list")
      aws_row = row("AWS thing")

      expect(aws_row.text.squish).to include("3 controls covered", "Applies to service")
      expect(aws_row.css(".sparc-chip--family").map(&:text)).to eq(%w[AC AU])
      expect(aws_row.text).to include("SPARC enrichment")
      # A STIG rule id is not a NIST family.
      expect(row("Local thing").css(".sparc-chip--family")).to be_empty
      expect(row("Org thing").text).not_to include("SPARC enrichment")
    end

    it "filters by family and by what it applies to, from the left column" do
      get cdef_documents_path(view: "list")
      side = page.at_css(".sparc-filtered-collection__side")
      expect(side.css("select[name=family] option").map { _1["value"] }).to include("AC", "AU", "SC")

      get cdef_documents_path(view: "list", family: "AC")
      expect(names).to contain_exactly("AWS thing", "Baseline thing")

      get cdef_documents_path(view: "list", component_type: "service")
      expect(names).to eq([ "AWS thing" ])
    end
  end

  describe "coverage of the boundary's baseline" do
    it "is not shown when the list is not filtered to a boundary" do
      get cdef_documents_path(view: "list")

      expect(page.css("[data-testid=coverage-meter]")).to be_empty
      expect(page.at_css("[data-testid=cdef-sort]")).to be_nil
    end

    it "measures each CDEF against the boundary's baseline, as the gap check does" do
      get cdef_documents_path(view: "list", authorization_boundary_id: boundary.id)

      meter = row("AWS thing").at_css("[data-testid=coverage-meter]")
      expect(meter["value"].to_f).to eq(CdefBaselineGapService.new(aws, profile: baseline).analyze[:coverage_pct])
      expect(meter["value"].to_f).to eq(75.0)
      expect(row("Org thing").at_css("[data-testid=coverage-meter]")["value"].to_f).to eq(25.0)
    end

    it "sorts by coverage on request" do
      get cdef_documents_path(view: "list", authorization_boundary_id: boundary.id, sort: "coverage")

      expect(names).to eq([ "AWS thing", "Org thing" ])
      expect(page.at_css("[data-testid=cdef-sort-coverage]")["aria-current"]).to eq("true")
    end

    it "is not shown for a boundary without a resolved baseline" do
      bare = create(:authorization_boundary, name: "Bare ATO")
      get cdef_documents_path(view: "list", authorization_boundary_id: bare.id)

      expect(page.css("[data-testid=coverage-meter]")).to be_empty
    end

    it "adds a coverage column to the Table view" do
      get cdef_documents_path(view: "table", authorization_boundary_id: boundary.id)

      expect(page.css("[data-testid=coverage-cell]").map { _1.text.squish }).to include("75% (3/4)", "25% (1/4)")
    end
  end

  describe "the API index (parity)" do
    let(:headers) { { "Authorization" => "Bearer #{ApiToken.generate!(user: admin, name: 'T').plaintext_token}" } }

    def data = response.parsed_body["data"].index_by { _1["name"] }

    it "returns the source, controls covered and families, and filters by source and family" do
      get api_v1_cdef_documents_path, headers: headers

      expect(data["AWS thing"]).to include("source_kind" => "aws", "controls_covered" => 3, "families" => %w[AC AU])
      expect(data["AWS thing"]["components"]["component_types"]).to eq([ "service" ])
      expect(data["Local thing"]["source_kind"]).to eq("local")
      expect(data["AWS thing"]).not_to have_key("baseline_coverage")

      get api_v1_cdef_documents_path, params: { source: "org" }, headers: headers
      expect(data.keys).to eq([ "Org thing" ])

      get api_v1_cdef_documents_path, params: { family: "AU" }, headers: headers
      expect(data.keys).to eq([ "AWS thing" ])
    end

    it "returns coverage and sorts by it for a boundary the caller can reach" do
      get api_v1_cdef_documents_path, params: { authorization_boundary_id: boundary.id, sort: "coverage" }, headers: headers

      expect(response.parsed_body["data"].map { _1["name"] }).to eq([ "AWS thing", "Org thing" ])
      expect(data["AWS thing"]["baseline_coverage"]).to eq(
        "covered" => 3, "total" => 4, "pct" => 75.0, "profile_document_id" => baseline.id
      )
    end

    it "returns no coverage for a boundary the caller cannot reach" do
      member = create(:user)
      member_headers = { "Authorization" => "Bearer #{ApiToken.generate!(user: member, name: 'M').plaintext_token}" }
      get api_v1_cdef_documents_path, params: { authorization_boundary_id: boundary.id }, headers: member_headers

      expect(response.parsed_body["data"].to_a.map { _1["baseline_coverage"] }.compact).to be_empty
    end
  end
end
