# frozen_string_literal: true

require "rails_helper"

# 1.18.0-rf #1302 — the rest of the organization Overview (the home page under
# SPARC_NAV_SHELL): the people count, "Waiting on you" for approvers, every
# number linking to the list it counts, and the Overview's counts equal to the
# organization tabs' (both from BoundaryNavCounts).
RSpec.describe "Organization Overview (#1302)", type: :request do
  let(:org) { create(:organization, name: "Acme Org") }

  def page = Nokogiri::HTML(response.body)

  before { allow(SparcConfig).to receive_messages(any_auth_enabled?: true, nav_shell?: true) }

  describe "the header" do
    it "counts the one organization's people for a member, without a link to a screen they cannot open" do
      member = create(:user)
      create(:organization_membership, organization: org, user: member)
      create(:organization_membership, organization: org, user: create(:user))
      sign_in_as(member)
      get root_path

      people = page.at_css("[data-testid=org-meta-people]")
      expect(people.text.squish).to eq("2 people")
      expect(people.name).to eq("span")
    end

    it "counts everyone for an administrator, linked to the people screen" do
      admin = create(:user, :admin)
      sign_in_as(admin)
      get root_path

      people = page.at_css("[data-testid=org-meta-people]")
      expect(people.text.squish).to eq(pluralize_people(User.count))
      expect(people["href"]).to eq(admin_users_path)
    end

    it "links the boundary count to the boundaries" do
      sign_in_as(create(:user, :admin))
      get root_path

      expect(page.at_css("[data-testid=org-meta-boundaries]")["href"]).to eq(authorization_boundaries_path)
    end

    def pluralize_people(n) = n == 1 ? "1 person" : "#{n} people"
  end

  describe "Waiting on you" do
    let!(:pending) { create(:control_catalog, name: "Pending catalog", approval_status: "pending_review") }

    it "lists what the approver may approve — the list the header's indicator counts" do
      sign_in_as(create(:user, :admin))
      get root_path

      section = page.at_css("[data-testid=org-waiting]")
      expect(section.text).to include("Pending catalog")
      expect(section.at_css("a[href='#{polymorphic_path(pending)}']")).to be_present
      waiting = section.at_css("[data-testid=org-waiting-queue]")
      expect(waiting["href"]).to eq(review_queue_index_path)
      expect(waiting.text).to start_with(page.at_css("[data-testid=shell-review-queue]")["data-count"])
    end

    it "is not shown to someone who approves nothing" do
      sign_in_as(create(:user))
      get root_path

      expect(page.at_css("[data-testid=org-waiting]")).to be_nil
    end
  end

  describe "counts" do
    let(:admin) { create(:user, :admin) }
    let(:boundary) { create(:authorization_boundary) }

    before do
      create_list(:ssp_document, 2, authorization_boundary: boundary)
      create(:sap_document, authorization_boundary: boundary)
      create(:poam_document, authorization_boundary: boundary)
      create(:evidence, authorization_boundary: boundary)
      create(:profile_document)
      sign_in_as(admin)
      get root_path
    end

    it "gives every number a link to the list it counts" do
      page.css("[data-testid=org-box]").each do |box|
        title = box.at_css(".sparc-lane-box__title")
        expect(box.at_css(".sparc-lane-box__count")["href"]).to eq(title["href"]), box["data-box"]
      end
      expect(page.css("[data-testid=org-baseline-in-use]").map { _1["href"] }).to all(start_with("/profile_documents/"))
    end

    it "shows the same count as the organization tab for the same list" do
      tabs = page.css("[data-testid=org-tabs] [data-testid=shell-tab]").filter_map do |tab|
        counter = tab.at_css(".sparc-counter")
        [ tab["href"], counter.text.delete(",").to_i ] if counter
      end.to_h
      boxes = page.css("[data-testid=org-box]").to_h do |box|
        [ box.at_css(".sparc-lane-box__title")["href"], box.at_css(".sparc-lane-box__count").text.delete(",").to_i ]
      end

      shared = tabs.keys & boxes.keys
      expect(shared).to include(ssp_documents_path, sap_documents_path, poam_documents_path, evidences_path)
      shared.each { |path| expect(boxes[path]).to eq(tabs[path]), path }
    end
  end
end
