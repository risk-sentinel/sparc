# frozen_string_literal: true

require "rails_helper"

# #887 §5 / #888 — the collection screen itself: view mode round-tripping,
# facets narrowing the list, and the chrome that lets a user see and undo what
# is currently filtering it.
#
# CdefDocuments is the pilot; every other screen adopts the same component, so
# these are the behaviours the rest of #888 is measured against.
RSpec.describe "CdefDocuments collection view", type: :request do
  let(:user) { create(:user, :admin) }

  def component(document, **attrs)
    attrs = { cdef_document: document, component_uuid: SecureRandom.uuid }.merge(attrs)
    attrs[:search_blob] ||= CdefComponent.build_search_blob(attrs)
    CdefComponent.create!(attrs)
  end

  before { sign_in_as(user) }

  describe "view mode" do
    let!(:document) { create(:cdef_document, name: "Alpha CDEF") }

    it "renders cards by default" do
      get cdef_documents_path

      expect(response.body).to include("sparc-item-card")
      expect(response.body).to include("Alpha CDEF")
    end

    it "renders the table when the URL asks for a list" do
      get cdef_documents_path(view: "list")

      expect(response.body).to include("<table")
      expect(response.body).not_to include("sparc-item-card")
    end

    it "remembers an explicit choice for next time" do
      get cdef_documents_path(view: "list")
      expect(cookies["sparc_view_cdef_documents"]).to eq("list")

      get cdef_documents_path
      expect(response.body).to include("<table")
    end

    # Searching is not a request to change how the results are drawn.
    it "keeps a stored preference across a plain visit and a search" do
      get cdef_documents_path(view: "list")

      get cdef_documents_path(q: "Alpha")
      expect(response.body).to include("<table")
      expect(response.body).not_to include("sparc-item-card")
    end

    it "keeps the active search when switching views" do
      get cdef_documents_path(q: "Alpha", view: "list")

      expect(response.body).to include("Alpha CDEF")
      # The toggle's other option has to carry the query, or switching view
      # silently drops the search.
      expect(response.body).to include("view=card")
      expect(response.body).to include("q=Alpha")
    end

    it "exposes the toggle as a radio group rather than two loose links" do
      get cdef_documents_path

      expect(response.body).to include('role="radiogroup"')
      expect(response.body).to include('aria-checked="true"')
    end
  end

  describe "facets" do
    let!(:gov) { create(:cdef_document, name: "GovCloud Service") }
    let!(:commercial) { create(:cdef_document, name: "Commercial Service") }

    before do
      component(gov, service_id: "IAM", title: "AWS IAM",
                     region_ids: %w[us-gov-west-1], partitions: %w[aws-us-gov],
                     declared_capabilities: %w[MFA], has_checks: true)
      component(commercial, service_id: "S3", title: "Amazon S3",
                            region_ids: %w[us-east-1], partitions: %w[aws],
                            has_checks: false)
    end

    it "shows everything when no facet is applied" do
      get cdef_documents_path

      expect(response.body).to include("GovCloud Service", "Commercial Service")
    end

    it "narrows by partition" do
      get cdef_documents_path(partition: "aws-us-gov")

      expect(response.body).to include("GovCloud Service")
      expect(response.body).not_to include("Commercial Service")
    end

    it "narrows by capability" do
      get cdef_documents_path(capability: "MFA")

      expect(response.body).to include("GovCloud Service")
      expect(response.body).not_to include("Commercial Service")
    end

    it "narrows to definitions that carry automated checks" do
      get cdef_documents_path(checks: "true")

      expect(response.body).to include("GovCloud Service")
      expect(response.body).not_to include("Commercial Service")
    end

    it "narrows to definitions that carry none" do
      get cdef_documents_path(checks: "false")

      expect(response.body).to include("Commercial Service")
      expect(response.body).not_to include("GovCloud Service")
    end

    # The bug this guards: a facet that replaces the search instead of
    # composing with it, so `?q=iam&partition=aws` widens the result set.
    it "intersects with the free-text search rather than replacing it" do
      get cdef_documents_path(q: "IAM", partition: "aws-us-gov")
      expect(response.body).to include("GovCloud Service")
      expect(response.body).not_to include("Commercial Service")

      get cdef_documents_path(q: "IAM", partition: "aws")
      expect(response.body).not_to include("GovCloud Service")
      expect(response.body).not_to include("Commercial Service")
    end

    it "intersects two facets rather than unioning them" do
      get cdef_documents_path(partition: "aws", capability: "MFA")

      expect(response.body).not_to include("GovCloud Service")
      expect(response.body).not_to include("Commercial Service")
    end
  end

  describe "the active-filter chrome" do
    let!(:document) { create(:cdef_document, name: "Chrome CDEF") }

    before do
      component(document, service_id: "IAM", title: "AWS IAM",
                          partitions: %w[aws-us-gov], declared_capabilities: %w[MFA])
    end

    it "stays out of the way when nothing is filtering the list" do
      get cdef_documents_path

      expect(response.body).not_to include("filter active")
      expect(response.body).not_to include("Clear all")
    end

    it "counts what is currently narrowing the list" do
      get cdef_documents_path(partition: "aws-us-gov", capability: "MFA", q: "IAM")

      expect(response.body).to include("3 filters active")
    end

    it "names each facet with the screen's own wording" do
      get cdef_documents_path(partition: "aws-us-gov")

      expect(response.body).to include("Partition")
      expect(response.body).to include("aws-us-gov")
    end

    # A user who has scrolled past the search box otherwise has no way to see
    # why the list is short.
    it "shows the search term as a removable filter too" do
      get cdef_documents_path(q: "IAM")

      expect(response.body).to include("1 filter active")
      expect(response.body).to include("search: IAM")
    end

    it "offers a link that drops one facet and keeps the rest" do
      get cdef_documents_path(partition: "aws-us-gov", capability: "MFA", view: "list")
      links = removal_links(response.body)

      partition_removal = links.find { |href| !href.include?("partition=") }
      expect(partition_removal).to be_present
      expect(partition_removal).to include("capability=MFA")
      expect(partition_removal).to include("view=list")
    end

    it "returns to the first page when a facet is dropped" do
      get cdef_documents_path(partition: "aws-us-gov", page: "2")

      expect(removal_links(response.body)).to be_present
      expect(removal_links(response.body).select { |href| href.include?("page=") }).to be_empty
    end

    it "offers a clear-all that keeps how the list is drawn" do
      get cdef_documents_path(partition: "aws-us-gov", q: "IAM", view: "list")

      clear = clear_all_link(response.body)
      expect(clear).to be_present
      expect(clear).not_to include("partition=", "q=")
      expect(clear).to include("view=list")
    end

    it "says plainly when the filters match nothing" do
      get cdef_documents_path(q: "no-such-service-anywhere")

      expect(response.body).to include("No component definitions match the current filters.")
    end

    # A GET form submits only its own fields. Without hidden inputs carrying
    # them, the act of searching silently dropped every active facet and the
    # view mode — so a user who filtered, then searched within it, lost the
    # filter and could not tell why the results widened.
    describe "the search box" do
      it "carries the active facets so searching narrows within them" do
        get cdef_documents_path(partition: "aws-us-gov", capability: "MFA", view: "list")

        expect(search_form).to include('name="partition"', "aws-us-gov")
        expect(search_form).to include('name="capability"', "MFA")
        expect(search_form).to include('name="view"', "list")
      end

      it "does not carry the page number, which means nothing against new results" do
        get cdef_documents_path(partition: "aws-us-gov", page: "3")

        expect(search_form).not_to include('name="page"')
      end

      it "clears only the search, leaving the surrounding filters in place" do
        get cdef_documents_path(q: "iam", partition: "aws-us-gov")

        clear = response.body[/<a[^>]*class="btn btn-outline-secondary"[^>]*>\s*Clear\s*<\/a>/m].to_s
        expect(clear).to include("partition=aws-us-gov")
        expect(clear).not_to include("q=iam")
      end
    end
  end

  describe "pagination" do
    before { create_list(:cdef_document, 3) }

    it "announces the result count to assistive tech" do
      get cdef_documents_path

      expect(response.body).to include('aria-live="polite"')
      expect(response.body).to include("3 component definitions")
    end

    it "splits the collection when it exceeds a page" do
      get cdef_documents_path(per_page: "2")

      expect(response.body).to include("1–2 of 3 component definitions")
    end

    # The ceiling itself is proven in the concern spec, where the limit is
    # observable; here it only has to not blow up.
    it "survives an absurd per_page" do
      get cdef_documents_path(per_page: "999999")

      expect(response).to have_http_status(:ok)
    end

    it "keeps the search and view mode across pages" do
      get cdef_documents_path(per_page: "2", view: "list")

      expect(response.body).to include("per_page=2")
      expect(response.body).to include("view=list")
    end
  end

  # The chips are the only links in that block, so pulling hrefs out of it
  # keeps these assertions about behaviour rather than about markup.
  def removal_links(body)
    filter_block(body).scan(/href="([^"]*)"/).flatten.reject { |h| h.include?("Clear") }
  end

  def clear_all_link(body)
    filter_block(body)[/<a[^>]*href="([^"]*)"[^>]*>\s*Clear all/, 1]
  end

  # The search form specifically — the layout has others (logout, bulk delete),
  # and grabbing the first <form> on the page asserts nothing about search.
  def search_form
    response.body[/<form[^>]*data-index-search-target="form"[^>]*>.*?<\/form>/m].to_s
  end

  def filter_block(body)
    body[/filters? active.*?<\/div>/m].to_s
  end
end
