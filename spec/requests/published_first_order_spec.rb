# frozen_string_literal: true

require "rails_helper"

# 1.18.0-rf (owner, 2026-11-01) — the catalog and baseline lists show published
# documents first, then drafts: in progress, then started. Inside each group the
# list keeps its own order (catalogs by name on the screen, newest first
# elsewhere). The screens and Api::V1 read one definition, Lifecycle.published_first.
#
# The names and dates are chosen so that neither the old order (by name, or
# newest first) nor a reversed lifecycle order can pass.
RSpec.describe "Catalogs and baselines: published first", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:api_token) { ApiToken.generate!(user: admin, name: "Order") }
  let(:auth_headers) { { "Authorization" => "Bearer #{api_token.plaintext_token}" } }

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    sign_in_as(admin)
  end

  # The order the names appear in on the page, among the ones this example made.
  def page_order(names)
    names.sort_by { |name| response.body.index(ERB::Util.html_escape(name)) || raise("#{name} not on the page") }
  end

  def api_order(names)
    JSON.parse(response.body).fetch("data").map { _1["name"] } & names
  end

  describe "catalogs" do
    # name, lifecycle, age in days
    let!(:catalogs) do
      [ [ "Order Alpha Draft", "in_progress", 1 ], [ "Order Bravo Started", "started", 4 ],
        [ "Order Mike Published", "published", 3 ], [ "Order Zulu Published", "published", 2 ] ]
        .map { |name, status, age| create(:control_catalog, name: name, lifecycle_status: status, created_at: age.days.ago) }
    end
    let(:names) { catalogs.map(&:name) }

    it "lists published catalogs first on the screen, each group by name" do
      get control_catalogs_path(view: "table", per_page: 100)

      expect(page_order(names)).to eq([ "Order Mike Published", "Order Zulu Published",
                                        "Order Alpha Draft", "Order Bravo Started" ])
    end

    it "lists published catalogs first over the API, each group newest first" do
      get api_v1_control_catalogs_path, params: { items: 100 }, headers: auth_headers

      expect(api_order(names)).to eq([ "Order Zulu Published", "Order Mike Published",
                                       "Order Alpha Draft", "Order Bravo Started" ])
    end
  end

  describe "baselines" do
    let!(:baselines) do
      [ [ "Order Newest Draft", "in_progress", 1 ], [ "Order Older Started", "started", 2 ],
        [ "Order Oldest Published", "published", 5 ], [ "Order Newer Published", "published", 3 ] ]
        .map { |name, status, age| create(:profile_document, name: name, lifecycle_status: status, created_at: age.days.ago) }
    end
    let(:names) { baselines.map(&:name) }
    let(:expected) do
      [ "Order Newer Published", "Order Oldest Published", "Order Newest Draft", "Order Older Started" ]
    end

    it "lists published baselines first on the screen, each group newest first" do
      get profile_documents_path(view: "table", per_page: 100)

      expect(page_order(names)).to eq(expected)
    end

    it "lists published baselines first over the API, each group newest first" do
      get api_v1_profile_documents_path, params: { items: 100 }, headers: auth_headers

      expect(api_order(names)).to eq(expected)
    end
  end
end
