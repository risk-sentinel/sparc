# frozen_string_literal: true

require "rails_helper"

# #888 — the rules every collection screen shares. Each one is a decision that
# is invisible in the rendered page but wrong in a way a user would feel:
# a shared link that silently rewrites their saved preference, a "remove this
# filter" link that drops the others with it, a `?per_page=` that asks the
# server to draw the whole corpus.
RSpec.describe CollectionViewable do
  # Minimal harness: the concern only needs params, cookies and request, and
  # driving it directly keeps these cases about the rule rather than about
  # whichever screen happens to be hosting it.
  let(:cookie_jar) { FakeCookieJar.new }

  # Behaves like ActionDispatch's jar for what the concern uses: assignment
  # takes either a bare value or an options hash, reading returns the value.
  class FakeCookieJar
    def initialize = @store = {}
    def [](name) = @store[name.to_s]&.fetch(:value)
    def []=(name, options)
      @store[name.to_s] = options.is_a?(Hash) ? options : { value: options }
    end
    def options_for(name) = @store[name.to_s]
    def written = @store.keys
  end

  def harness(params: {}, cookies: cookie_jar, ssl: false)
    query = params.transform_keys(&:to_s).transform_values(&:to_s)

    Class.new do
      include CollectionViewable
      public :resolve_view_mode, :normalize_view_mode, :view_cookie_name,
             :active_facets, :clear_facets_params, :resolve_per_page

      attr_reader :params, :cookies, :request

      def initialize(params, cookies, request)
        @params = params
        @cookies = cookies
        @request = request
      end
    end.new(
      ActionController::Parameters.new(params.transform_keys(&:to_s)),
      cookies,
      instance_double("ActionDispatch::Request", query_parameters: query, ssl?: ssl)
    )
  end

  describe "#resolve_view_mode" do
    it "defaults to cards when nothing is asked for and nothing is stored" do
      expect(harness.resolve_view_mode(:cdef_documents)).to eq(:card)
    end

    it "honours an explicit ?view= over everything else" do
      cookie_jar["sparc_view_cdef_documents"] = { value: "card" }
      subject = harness(params: { view: "list" })

      expect(subject.resolve_view_mode(:cdef_documents)).to eq(:list)
    end

    it "falls back to the stored preference when the URL says nothing" do
      cookie_jar["sparc_view_cdef_documents"] = { value: "list" }

      expect(harness.resolve_view_mode(:cdef_documents)).to eq(:list)
    end

    # A preference is per screen: keeping list for SSPs and cards for CDEFs is
    # the point of scoping the cookie name.
    it "does not let one screen's preference leak into another" do
      cookie_jar["sparc_view_ssp_documents"] = { value: "list" }

      expect(harness.resolve_view_mode(:cdef_documents)).to eq(:card)
      expect(harness.resolve_view_mode(:ssp_documents)).to eq(:list)
    end

    it "ignores a mode it does not recognise and falls through" do
      cookie_jar["sparc_view_cdef_documents"] = { value: "list" }

      expect(harness(params: { view: "gallery" }).resolve_view_mode(:cdef_documents)).to eq(:list)
    end

    it "ignores a stored value it does not recognise" do
      cookie_jar["sparc_view_cdef_documents"] = { value: "gallery" }

      expect(harness.resolve_view_mode(:cdef_documents)).to eq(:card)
    end

    it "accepts a mode regardless of case" do
      expect(harness(params: { view: "LIST" }).resolve_view_mode(:cdef_documents)).to eq(:list)
    end

    it "takes a caller-supplied default" do
      expect(harness.resolve_view_mode(:promotion_queue, default: :list)).to eq(:list)
    end

    describe "persistence" do
      it "stores the choice when the user makes one explicitly" do
        harness(params: { view: "list" }).resolve_view_mode(:cdef_documents)

        expect(cookie_jar["sparc_view_cdef_documents"]).to eq("list")
      end

      # The reason the write is conditional: someone shares
      # `/cdef_documents?view=list`, the recipient opens it, and from then on
      # every collection they visit is a list — a preference they never set.
      it "does not write anything when no explicit choice was made" do
        cookie_jar["sparc_view_cdef_documents"] = { value: "list" }
        harness.resolve_view_mode(:cdef_documents)

        expect(cookie_jar.written).to eq([ "sparc_view_cdef_documents" ])
        expect(cookie_jar["sparc_view_cdef_documents"]).to eq("list")
      end

      it "writes nothing at all when the URL carries an unrecognised mode" do
        harness(params: { view: "gallery" }).resolve_view_mode(:cdef_documents)

        expect(cookie_jar.written).to be_empty
      end

      it "is not readable from script and does not ride cross-site" do
        harness(params: { view: "list" }).resolve_view_mode(:cdef_documents)
        options = cookie_jar.options_for("sparc_view_cdef_documents")

        expect(options[:httponly]).to be(true)
        expect(options[:same_site]).to eq(:lax)
        expect(options[:expires]).to be > 6.months.from_now
      end

      it "marks the cookie secure only when the request is over TLS" do
        harness(params: { view: "list" }, ssl: true).resolve_view_mode(:a)
        harness(params: { view: "list" }, ssl: false).resolve_view_mode(:b)

        expect(cookie_jar.options_for("sparc_view_a")[:secure]).to be(true)
        expect(cookie_jar.options_for("sparc_view_b")[:secure]).to be(false)
      end
    end
  end

  describe "#view_cookie_name" do
    it "namespaces every screen under one prefix" do
      expect(harness.view_cookie_name(:cdef_documents)).to eq("sparc_view_cdef_documents")
    end

    it "normalises a screen name into something cookie-safe" do
      expect(harness.view_cookie_name("Leveraged POA&M Documents"))
        .to eq("sparc_view_leveraged_poa_m_documents")
    end
  end

  describe "#active_facets" do
    let(:allowed) { %i[partition capability checks] }
    let(:labels) { { partition: "Partition", checks: "Automated checks" } }

    it "reports nothing when no facet is set" do
      expect(harness.active_facets(allowed)).to be_empty
    end

    it "reports only the facets actually in play" do
      subject = harness(params: { partition: "aws-us-gov", q: "iam" })

      expect(subject.active_facets(allowed).map { |f| f[:key] }).to eq([ :partition ])
    end

    it "ignores a facet present but blank" do
      expect(harness(params: { partition: "" }).active_facets(allowed)).to be_empty
    end

    it "ignores params that are not declared facets" do
      subject = harness(params: { sort: "name", partition: "aws" })

      expect(subject.active_facets(allowed).map { |f| f[:key] }).to eq([ :partition ])
    end

    it "keeps the declared order rather than the order they appear in the URL" do
      subject = harness(params: { checks: "true", partition: "aws" })

      expect(subject.active_facets(allowed).map { |f| f[:key] }).to eq([ :partition, :checks ])
    end

    it "uses the screen's label when it supplies one" do
      subject = harness(params: { checks: "true" })

      expect(subject.active_facets(allowed, labels: labels).first[:label]).to eq("Automated checks")
    end

    it "falls back to a readable label when the screen supplies none" do
      subject = harness(params: { capability: "MFA" })

      expect(subject.active_facets(allowed, labels: labels).first[:label]).to eq("Capability")
    end

    describe "the remove link" do
      let(:subject) do
        harness(params: { partition: "aws-us-gov", capability: "MFA", q: "iam",
                          view: "card", page: "3" })
      end
      let(:remove) { subject.active_facets(allowed).first[:remove_params] }

      it "drops the facet it removes" do
        expect(remove).not_to have_key("partition")
      end

      # Removing one chip must not quietly reset the rest of the user's view.
      it "keeps the other facets, the search and the view mode" do
        expect(remove).to include("capability" => "MFA", "q" => "iam", "view" => "card")
      end

      it "returns to the first page, because the old page number means nothing now" do
        expect(remove).not_to have_key("page")
      end
    end
  end

  describe "#clear_facets_params" do
    let(:allowed) { %i[partition capability checks] }

    let(:cleared) do
      harness(params: { partition: "aws", capability: "MFA", checks: "true", q: "iam",
                        page: "4", view: "list", per_page: "50" })
        .clear_facets_params(allowed)
    end

    it "drops every facet" do
      expect(cleared.keys).not_to include("partition", "capability", "checks")
    end

    it "drops the search term too — it narrows the collection like any facet" do
      expect(cleared).not_to have_key("q")
    end

    it "returns to the first page" do
      expect(cleared).not_to have_key("page")
    end

    # View mode and page size are how the collection is drawn, not which rows
    # are in it. Clearing filters should not also throw away the user's layout.
    it "keeps the view mode and page size" do
      expect(cleared).to eq("view" => "list", "per_page" => "50")
    end
  end

  describe "#resolve_per_page" do
    it "uses the screen default when nothing is asked for" do
      expect(harness.resolve_per_page(24)).to eq(24)
    end

    it "honours a reasonable request" do
      expect(harness(params: { per_page: "50" }).resolve_per_page(24)).to eq(50)
    end

    # Cards default everywhere, so an uncapped per_page is a request to render
    # the entire corpus as cards.
    it "caps a request that would draw the whole corpus" do
      expect(harness(params: { per_page: "999999" }).resolve_per_page(24))
        .to eq(described_class::MAX_PER_PAGE)
    end

    it "allows exactly the ceiling" do
      expect(harness(params: { per_page: "200" }).resolve_per_page(24)).to eq(200)
    end

    it "falls back to the default for zero, negative and non-numeric values" do
      %w[0 -5 abc].each do |raw|
        expect(harness(params: { per_page: raw }).resolve_per_page(24)).to eq(24)
      end
    end
  end
end
