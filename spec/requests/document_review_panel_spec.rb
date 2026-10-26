# frozen_string_literal: true

require "rails_helper"

# With approval required (SPARC_REQUIRE_DOCUMENT_APPROVAL, on by default),
# Publish refuses a baseline or catalog that is not approved, and said so:
# "Cannot publish: document must be reviewed and approved first (current:
# Draft)". But no screen offered Submit for review for either; only CDEFs had a
# review panel. So a baseline or catalog could be published through the API
# alone. Both pages now carry the panel: its status, Submit for review for a
# writer, Approve and Reject for an approver.
RSpec.describe "Review panel on baseline and catalog pages", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:reader) { create(:user) }

  before { allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true) }

  def panel(path)
    get path
    follow_redirect! while response.redirect? # a catalog's id URL moves to its slug
    expect(response).to have_http_status(:ok)
    Nokogiri::HTML(response.body).at_css("[data-testid='document-review']")
  end

  def submit_form(panel, path) = panel&.at_css("form[action='#{path}']")

  {
    "baseline" => {
      doc: -> { create(:profile_document, control_catalog: create(:control_catalog)).tap { |p| create(:profile_control, profile_document: p, control_id: "ac-1", priority: "P1") } },
      show: ->(d) { profile_document_path(d) },
      submit: ->(d) { submit_for_review_profile_document_path(d) },
      approve: ->(d) { approve_profile_document_path(d) }
    },
    "catalog" => {
      # The factory's catalogs are published; a draft is what needs review.
      doc: -> { create(:control_catalog, lifecycle_status: "in_progress").tap { |c| create(:catalog_control, control_family: create(:control_family, control_catalog: c)) } },
      show: ->(d) { control_catalog_path(d) },
      submit: ->(d) { submit_for_review_control_catalog_path(d) },
      approve: ->(d) { approve_control_catalog_path(d) }
    }
  }.each do |kind, paths|
    context "on a draft #{kind}" do
      let(:doc) { instance_exec(&paths[:doc]) }

      it "offers its writer Submit for review, then its approver Approve, after which it publishes" do
        sign_in_as(admin)
        found = panel(instance_exec(doc, &paths[:show]))
        expect(found.at_css("[data-testid='document-review-status']").text).to include("Draft")
        expect(submit_form(found, instance_exec(doc, &paths[:submit]))).to be_present

        post instance_exec(doc, &paths[:submit])
        expect(doc.reload).to be_approval_pending
        found = panel(instance_exec(doc, &paths[:show]))
        expect(found.at_css("form[action='#{instance_exec(doc, &paths[:approve])}']")).to be_present
        expect(submit_form(found, instance_exec(doc, &paths[:submit]))).to be_nil

        post instance_exec(doc, &paths[:approve])
        expect(doc.reload).to be_approved
        expect(panel(instance_exec(doc, &paths[:show])).text).to include("Approved by #{admin.email}")
      end

      it "offers a reader neither action" do
        sign_in_as(reader)
        found = panel(instance_exec(doc, &paths[:show]))

        expect(found).to be_present
        expect(found.css("form")).to be_empty
      end
    end
  end

  it "shows nothing for a draft when approval is not required" do
    allow(SparcConfig).to receive(:require_document_approval?).and_return(false)
    sign_in_as(admin)
    profile = create(:profile_document, control_catalog: create(:control_catalog))

    get profile_document_path(profile)

    expect(response.body).not_to include("document-review")
  end
end
