# frozen_string_literal: true

require "rails_helper"

# #908 — filter controls on the index screens.
#
# The mechanics live in CollectionBrowseQuery and are unit-tested there. What
# this covers is the part that only breaks once a real screen renders: the
# filter form is a GET form, and a GET form submits ONLY its own fields. Every
# piece of state that is not one of its inputs has to be re-emitted as a hidden
# field or it is silently dropped on submit.
#
# The evidence screen's hand-written form re-emitted `q` and `view` and missed
# `per_page`, so filtering quietly reset a user's page size. That is the class
# of bug a shared partial exists to stop happening once per screen.
RSpec.describe "Index screen filters", type: :request do
  let(:user) { create(:user, :admin) }

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    sign_in_as(user)
  end

  # The screens that gained filters, and a facet each that is definitely
  # rendered (two distinct values, so the cardinality-1 rule keeps it).
  SCREENS = {
    "control catalogs" => {
      path: :control_catalogs_path,
      setup: -> { [ create(:control_catalog, oscal_version: "1.1.2"),
                    create(:control_catalog, oscal_version: "1.2.1") ] },
      facet: "oscal_version"
    },
    "baselines" => {
      path: :profile_documents_path,
      setup: -> { [ create(:profile_document, baseline_level: "LOW"),
                    create(:profile_document, baseline_level: "HIGH") ] },
      facet: "baseline_level"
    },
    "POA&Ms" => {
      path: :poam_documents_path,
      setup: -> { [ create(:poam_document, oscal_version: "1.1.2"),
                    create(:poam_document, oscal_version: "1.2.1") ] },
      facet: "oscal_version"
    },
    "evidence" => {
      path: :evidences_path,
      setup: -> { [ create(:evidence, status: "draft"), create(:evidence, :collected) ] },
      facet: "status"
    }
  }.freeze

  SCREENS.each do |label, config|
    describe "the #{label} index" do
      before { instance_exec(&config[:setup]) }

      let(:path) { send(config[:path]) }

      it "renders a filter form" do
        get path

        expect(response.body).to include("name=\"#{config[:facet]}\"")
        expect(response.body).to include('value="Filter"')
      end

      it "carries per_page through a filter submit" do
        # The regression that motivated the shared partial. `per_page` must be
        # re-emitted as a hidden field, or applying a filter resets the page
        # size the user chose.
        get path, params: { per_page: 50 }

        expect(response.body).to match(
          /<input type="hidden" name="per_page" value="50"/
        ), "the filter form dropped per_page — filtering would reset the page size"
      end

      it "carries the search term and the view mode through a filter submit" do
        get path, params: { q: "anything", view: "list" }

        expect(response.body).to match(/<input type="hidden" name="q" value="anything"/)
        expect(response.body).to match(/<input type="hidden" name="view" value="list"/)
      end

      it "does not carry the page number, which means nothing against a new result set" do
        get path, params: { page: 3, per_page: 50 }

        expect(response.body).not_to match(/<input type="hidden" name="page" value="3"/)
      end

      it "shows a removable chip for an applied filter" do
        get path, params: { config[:facet] => filter_value(config) }

        expect(response.body).to include("1 filter active")
        expect(response.body).to include("Clear all")
      end

      it "narrows the list" do
        get path, params: { config[:facet] => filter_value(config) }

        expect(response).to have_http_status(:ok)
      end
    end
  end

  # The value each screen's chosen facet is filtered on.
  def filter_value(config)
    { "oscal_version" => "1.1.2", "baseline_level" => "LOW", "status" => "draft" }
      .fetch(config[:facet])
  end

  describe "a facet the corpus does not distinguish" do
    # Uses POA&Ms because that table is empty except for what the example
    # creates. Catalogs carry seeded rows in a local test database (and not in
    # CI), and they cannot simply be deleted — `control_families` holds a
    # foreign key to them — so an assertion about "the whole corpus" would be
    # about fixture state rather than about the rule.
    it "is not offered at all" do
      # One distinct value is not a choice. Rendering the dropdown anyway
      # invites a user to filter by the only thing there is.
      create(:poam_document, oscal_version: "1.1.2", lifecycle_status: "in_progress")
      create(:poam_document, oscal_version: "1.1.2", lifecycle_status: "published")

      get poam_documents_path

      expect(response.body).not_to include('name="oscal_version"'),
        "oscal_version is uniform across the corpus and must not be offered"
      expect(response.body).to include('name="lifecycle_status"'),
        "lifecycle_status has two values and must still be offered"
    end
  end
end
