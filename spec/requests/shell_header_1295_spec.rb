# frozen_string_literal: true

require "rails_helper"

# 1.18.0-rf #1295 — the shell header behind SPARC_NAV_SHELL. Asserts what each
# viewer is OFFERED, in both directions: an entry appears for a viewer whose
# screen would admit them, and not for one it would refuse. The classic header
# with the switch off is pinned by nav_inventory_spec.rb.
RSpec.describe "Shell header (1.18.0-rf #1295)", type: :request do
  let(:alpha) { create(:authorization_boundary, name: "Alpha ATO") }
  let(:admin) { create(:user, :admin) }
  let(:member) do
    create(:user).tap { |u| grant_permission(u, "authorization_boundaries.read", authorization_boundary: alpha) }
  end

  def page = Nokogiri::HTML(response.body)

  def header = page.at_css("[data-testid=shell-header]")

  def items(testid) = header.css("[data-testid=#{testid}]").map { _1["data-item"] }

  def help_links = header.css("[data-testid=shell-help] a").map { _1.text.squish }

  before { allow(SparcConfig).to receive_messages(any_auth_enabled?: true, nav_shell?: true) }

  describe "an administrator" do
    before { sign_in_as(admin) }

    it "is offered every create, the whole library, help and the admin account links" do
      get "/"

      expect(items("shell-create-item")).to eq(%w[authorization_boundaries profile_documents ssp_documents cdef_documents
                                                  sap_documents sar_documents evidences poam_documents])
      expect(items("shell-library-item")).to eq(%w[control_catalogs profile_documents control_mappings cdef_documents
                                                   converters authoritative_sources promotion_queue
                                                   leveraged_poam_documents federation_peers])
      expect(help_links).to include("Help for this page", "Help Center", "About", "Resources", "OSCAL overview")
      expect(header.css("a").map { _1["href"] }).to include("/admin/users", "/admin/audit_logs")
    end

    it "loses the classic bar's layer dropdowns" do
      get "/"

      expect(page.at_css("#navbarNav")).to be_nil
      menus = header.css(".dropdown-toggle").map { _1["aria-label"] || _1.text.squish }
      expect(menus.first(3)).to eq(%w[Create Library Help])
      expect(menus.size).to eq(4)
      expect(menus.last).to end_with(admin.display_label)
    end

    it "counts the review queue as the queue lists it" do
      submitter = create(:user)
      create_list(:control_catalog, 2, approval_status: "pending_review", submitted_by_user: submitter)
      get "/"

      expect(header.at_css("[data-testid=shell-review-queue]")["data-count"]).to eq("2")
      get review_queue_index_path
      expect(ReviewQueue.approvable_for(admin).size).to eq(2)
    end
  end

  describe "a member with read access only" do
    before { sign_in_as(member) }

    it "is offered no create, no review queue and no screen that would refuse them" do
      get "/"

      expect(header.at_css("[data-testid=shell-create]")).to be_nil
      expect(header.at_css("[data-testid=shell-review-queue]")).to be_nil
      expect(items("shell-library-item")).to eq(%w[control_catalogs profile_documents control_mappings cdef_documents
                                                   converters promotion_queue leveraged_poam_documents])
      expect(header.css("a").map { _1["href"] }.grep(%r{\A/admin/})).to be_empty
    end
  end

  describe "a member who may write SSPs on one boundary" do
    before do
      grant_permission(member, "ssp.write", authorization_boundary: alpha)
      sign_in_as(member)
    end

    it "creates an SSP, in the boundary the page is inside" do
      get "/"
      expect(items("shell-create-item")).to eq(%w[ssp_documents])
      expect(header.at_css("[data-item=ssp_documents]")["href"]).to eq("/ssp_documents/new")

      get "/ssp_documents", params: { authorization_boundary_id: alpha.id }
      link = header.at_css("[data-item=ssp_documents]")["href"]
      expect(Rack::Utils.parse_query(URI(link).query)).to eq("authorization_boundary_id" => alpha.id.to_s)
      expect(header.at_css("[data-testid=shell-create] .sparc-dropdown-header").text.squish).to eq("Create in Alpha ATO")
    end
  end

  describe "an approver" do
    it "sees the queue indicator even when nothing is waiting" do
      approver = create(:user).tap { |u| grant_permission(u, "catalogs.approve") }
      sign_in_as(approver)
      get "/"

      expect(header.at_css("[data-testid=shell-review-queue]")["data-count"]).to eq("0")
    end
  end

  describe "a signed-out visitor" do
    it "is offered About, Resources and Login, and no library when it is private" do
      allow(SparcConfig).to receive(:public_catalogs?).and_return(false)
      get "/login"

      expect(header).to be_present
      expect(header.at_css("[data-testid=shell-library]")).to be_nil
      expect(header.at_css("[data-testid=shell-create]")).to be_nil
      expect(help_links).to eq(%w[About Resources])
      expect(header.css("a").map { _1["href"] }).to include("/login")
      expect(page.at_css("[data-testid=shell-bar]")).to be_nil
    end

    it "is offered the public library when catalogs are public" do
      allow(SparcConfig).to receive(:public_catalogs?).and_return(true)
      get "/login"

      expect(items("shell-library-item")).to eq(%w[control_catalogs profile_documents control_mappings cdef_documents converters])
    end
  end

  describe "with sign-in disabled" do
    it "offers creates and the library the open instance admits" do
      allow(SparcConfig).to receive(:any_auth_enabled?).and_return(false)
      get "/"

      expect(items("shell-create-item")).to include("ssp_documents", "poam_documents", "authorization_boundaries")
      expect(items("shell-library-item")).to include("promotion_queue", "leveraged_poam_documents", "federation_peers")
      expect(help_links).to include("Help for this page", "OSCAL overview")
    end
  end

  it "is absent with SPARC_NAV_SHELL off" do
    allow(SparcConfig).to receive(:nav_shell?).and_return(false)
    sign_in_as(admin)
    get "/"

    expect(header).to be_nil
    expect(page.at_css("nav.navbar #navbarNav")).to be_present
  end
end
