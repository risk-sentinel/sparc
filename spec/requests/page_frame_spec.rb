# frozen_string_literal: true

require "rails_helper"

# 1.18.0-rf — the page frame (owner-approved 10-31):
# every list screen has the settings screens' frame. The header, the left
# column and the tabs sit on the page with no outer box; the list's totals
# are one line under the title; on a list with a left column the header sits
# beside it.
RSpec.describe "Page frame", type: :request do
  let(:admin) { create(:user, :admin) }

  def page = Nokogiri::HTML(response.body)

  def summary = page.css("[data-testid=page-header-summary] li").map { _1.text.squish }


  # Lists that show totals, and the ones with a left column.
  def document_lists = {
    "ssp_documents" => true, "sap_documents" => true, "sar_documents" => true, "poam_documents" => true,
    "profile_documents" => true, "cdef_documents" => true, "control_catalogs" => true, "evidences" => true,
    "control_mappings" => false, "converters" => false
  }

  def other_lists = %w[
    /review_queue /promotion_queue /federation_peers /authoritative_sources /leveraged_poam_documents
    /admin/users /admin/roles /admin/service_accounts /admin/organizations /admin/authorization_boundaries
    /admin/remediation_timelines /admin/audit_logs
  ]

  before do
    sign_in_as(admin)
    create(:ssp_document, authorization_boundary: create(:authorization_boundary))
  end

  context "in the 1.18.0-rf navigation" do
    before { allow(SparcConfig).to receive_messages(any_auth_enabled?: true) }

    it "marks the page as the new navigation" do
      get ssp_documents_path
      expect(page.at_css("body")["class"]).to eq("sparc-shell")
    end

    it "draws each document list's totals as one line under the title, with no banner" do
      document_lists.each_key do |list|
        get "/#{list}"
        expect(response).to have_http_status(:ok), list
        expect(page.css(".sparc-gradient-header")).to be_empty, list
        expect(summary).not_to be_empty, list
        expect(page.at_css(".sparc-list-card [data-testid=page-header] [data-testid=page-header-summary]")).to be_present, list
      end
    end

    it "shows the totals the banner showed, as one line" do
      get ssp_documents_path
      expect(summary.map { _1.sub(/\A[\d,]+( of [\d,]+)? /, "") })
        .to eq([ "SSP Documents", "Total Controls", "Responses answered", "Completed" ])
      expect(summary.first).to eq("#{SspDocument.count} SSP Documents")
    end

    it "puts the header beside the left column, not above it" do
      get ssp_documents_path
      expect(page.at_css(".sparc-filtered-collection")).to be_present

      # A list draws the column only when it has something to filter by.
      document_lists.select { |_, side| side }.each_key do |list|
        get "/#{list}"
        expect(page.css("[data-testid=page-header]").size).to eq(1), list
        next unless page.at_css(".sparc-filtered-collection")

        main = page.at_css(".sparc-filtered-collection > .sparc-filtered-collection__main")
        expect(main.at_css("> [data-testid=page-header]")).to be_present, list
      end
    end

    it "gives the other lists and the admin lists the same frame" do
      other_lists.each do |path|
        get path
        expect(response).to have_http_status(:ok), path
        expect(page.at_css(".sparc-list-card")).to be_present, path
        expect(page.css("[data-testid=page-header] h1").size).to eq(1), path
      end
    end

    it "keeps the AWS Labs refresh status with the CDEF header" do
      allow(SparcConfig).to receive(:aws_labs_cdef_enabled?).and_return(true)
      get cdef_documents_path
      expect(page.at_css("[data-testid=page-header] + [data-testid=aws-labs-refresh-status]")).to be_present
    end
  end
end
