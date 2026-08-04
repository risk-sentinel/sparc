# frozen_string_literal: true

# #888 — the contract every collection screen signs up to.
#
# Seventeen screens adopt the shared card/list component, and the failure this
# guards against is not hypothetical: the CDEF card view shipped with none of
# the row's actions on it, and because cards are the default, those actions
# disappeared from the screen users land on. Only one of five was caught, and
# only by accident, through an unrelated spec.
#
# So each screen asserts the same things: both views render, both show the same
# records, the view choice round-trips and is remembered, search narrows, and —
# the important one — every action reachable in one view is reachable in the
# other.
#
# Usage:
#
#   it_behaves_like "a collection screen",
#     path: -> { ssp_documents_path },
#     screen: :ssp_documents,
#     create: -> { create(:ssp_document, name: "Findable Widget") },
#     search_term: "Findable",
#     actions: %w[View Delete]            # markers present in BOTH views
#
# `actions` are substrings matched against the rendered body — a route, a
# Stimulus hook, or button text. Route fragments are the most durable.
RSpec.shared_examples "a collection screen" do |path:, screen:, create:, search_term: nil,
                                                actions: [], label: nil, bulk_select: false|
  let(:screen_path) { instance_exec(&path) }
  let!(:record) { instance_exec(&create) }

  def body_at(url)
    get url
    expect(response).to have_http_status(:ok)
    response.body
  end

  def with_view(url, mode)
    separator = url.include?("?") ? "&" : "?"
    body_at("#{url}#{separator}view=#{mode}")
  end

  describe "view modes" do
    it "renders cards by default" do
      expect(body_at(screen_path)).to include("sparc-item-card")
    end

    it "renders a table when asked for a list" do
      body = with_view(screen_path, "list")

      expect(body).to include("<table")
      expect(body).not_to include("sparc-item-card")
    end

    it "offers a way to switch between them" do
      body = body_at(screen_path)

      expect(body).to include('role="radiogroup"')
      expect(body).to include("view=list")
    end

    it "remembers an explicit choice for the next visit" do
      with_view(screen_path, "list")

      expect(cookies["sparc_view_#{screen}"]).to eq("list")
      expect(body_at(screen_path)).to include("<table")
    end

    # A preference set on one screen must not decide another's.
    it "scopes the memory to this screen" do
      with_view(screen_path, "list")

      expect(cookies.to_hash.keys.grep(/\Asparc_view_/)).to eq([ "sparc_view_#{screen}" ])
    end
  end

  describe "the records themselves" do
    it "shows the same records in both views" do
      identifier = record.try(:name).presence || record.try(:title).to_s
      skip "no name or title to assert on" if identifier.blank?

      expect(with_view(screen_path, "card")).to include(ERB::Util.html_escape(identifier))
      expect(with_view(screen_path, "list")).to include(ERB::Util.html_escape(identifier))
    end

    it "reports how many there are" do
      expect(body_at(screen_path)).to include('aria-live="polite"')
    end
  end

  if search_term
    describe "search" do
      it "keeps a record that matches" do
        expect(body_at("#{screen_path}?q=#{CGI.escape(search_term)}"))
          .to include(ERB::Util.html_escape(search_term))
      end

      # Asserted through the result count rather than the absence of the name:
      # chrome outside the collection legitimately names records (the boundary
      # picker in the layout lists every boundary), so a whole-page absence
      # check would be asserting something the screen never promised. The count
      # still has teeth — a search that was ignored reports a match, not none.
      it "drops one that does not" do
        expect(body_at("#{screen_path}?q=zzz-no-such-record-zzz"))
          .to match(/No .* match the current filters\./)
      end

      # Searching is not a request to change how results are drawn.
      it "keeps the chosen view" do
        with_view(screen_path, "list")

        expect(body_at("#{screen_path}?q=#{CGI.escape(search_term)}")).to include("<table")
      end
    end
  end

  if actions.any?
    describe "action parity" do
      actions.each do |marker|
        it "offers #{marker} in both views" do
          expect(with_view(screen_path, "card")).to include(marker), "card view is missing #{marker}"
          expect(with_view(screen_path, "list")).to include(marker), "list view is missing #{marker}"
        end
      end
    end
  end

  # Bulk delete is unusable in a view with nothing to tick. The table puts
  # select-all in its header, which the card grid does not have — so a screen
  # can pass every other check and still have lost bulk delete in the default
  # view. That is exactly what happened on both screens that offer it.
  if bulk_select
    describe "bulk selection" do
      it "can select an individual item in both views" do
        %w[card list].each do |mode|
          expect(with_view(screen_path, mode)).to include('data-bulk-select-target="row"'),
            "#{mode} view has nothing to select"
        end
      end

      it "can select all in both views" do
        %w[card list].each do |mode|
          expect(with_view(screen_path, mode)).to include('data-bulk-select-target="selectAll"'),
            "#{mode} view cannot select all"
        end
      end

      it "wires the selection to the bulk form in both views" do
        %w[card list].each do |mode|
          expect(with_view(screen_path, mode)).to match(/form="\w+BulkForm"/),
            "#{mode} view's checkbox is not wired to the bulk form"
        end
      end
    end
  end

  if label
    describe "labelling" do
      it "names the collection in its own words" do
        expect(body_at(screen_path)).to include(label)
      end
    end
  end
end
