# frozen_string_literal: true

require "rails_helper"

# Views must never mark interpolated, user-supplied text as html_safe.
#
# The POA&M item new/edit screens built their "Back to <name>" link as
# `"&#8592; Back to #{@poam_document.name}".html_safe`. Marking the whole
# interpolated string html_safe disables escaping for the document name too, so a
# document named with markup rendered that markup into the page — stored XSS
# reachable by any user who can name a POA&M document (or by an imported OSCAL /
# Excel document carrying a crafted name).
#
# NIST 800-53: SI-10 (information input validation), SI-15 (information output
# filtering), AC-3 (a low-privilege author must not gain script execution in a
# reviewer's session).
RSpec.describe "View output escaping", type: :request do
  let(:user) { create(:user, :admin) }

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    sign_in_as(user)
  end

  # Markup + the characters that made this class of bug intermittent in specs.
  HOSTILE_NAME = %q(<script>alert('xss')</script> O'Hara & Sons <b>bold</b>)

  let(:poam) { create(:poam_document, name: HOSTILE_NAME) }
  let(:item) { create(:poam_item, poam_document: poam) }

  shared_examples "escapes the document name" do
    it "does not emit the raw markup" do
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include("<script>alert('xss')</script>")
      expect(response.body).not_to include("<b>bold</b>")
    end

    # An ERB comment containing "%>" terminates early and leaks its tail as page
    # text. Cheap guard: no un-rendered ERB fragment should reach the browser.
    it "leaks no un-rendered ERB" do
      expect(response.body).not_to include("%>")
    end

    it "renders the name as text, entities intact" do
      # Parsed back out, the link text must equal exactly what the user typed.
      link = Nokogiri::HTML(response.body)
                     .css("a")
                     .find { |a| a.text.include?("Back to") }
      expect(link).to be_present
      expect(link.text).to include(HOSTILE_NAME)
    end
  end

  # The processing banner renders `title` through an escaping tag but used to
  # interpolate `back_label` into an html_safe string — two opposite contracts in
  # one partial. poam_documents/show passed a pre-escaped title, which was then
  # escaped again, so users saw the literal text "Processing Your POA&amp;M".
  describe "GET /poam_documents/:id while processing" do
    # The banner only renders while the document is NOT completed, so pin the
    # status rather than letting the factory default decide (it defaults to
    # "completed", which silently skipped this check).
    let(:processing) { create(:poam_document, status: "pending") }

    before { get poam_document_path(processing) }

    it "renders the processing banner" do
      expect(response.body).to include("Processing Your")
    end

    it "shows the ampersand, not a literal entity" do
      text = Nokogiri::HTML(response.body).text
      expect(text).to include("Processing Your POA&M")
      expect(text).not_to include("POA&amp;M")
    end

    context "when the conversion failed (the branch that renders the back link)" do
      let(:processing) { create(:poam_document, status: "failed") }

      it "escapes the back label the same way" do
        text = Nokogiri::HTML(response.body).text
        expect(text).to include("Back to POA&Ms")
        expect(text).not_to include("POA&amp;Ms")
      end
    end
  end

  describe "GET /poam_documents/:id/poam_items/new" do
    before { get new_poam_document_poam_item_path(poam) }

    include_examples "escapes the document name"
  end

  describe "GET /poam_documents/:id/poam_items/:id/edit" do
    before { get edit_poam_document_poam_item_path(poam, item) }

    include_examples "escapes the document name"
  end

  # #897 — the OTHER half of the stored-value problem, and the one escaping does
  # not solve. Escaping protects the element BODY; these values land in an href
  # ATTRIBUTE, where the danger is the scheme rather than the characters. ERB
  # blocks quote-breaking; it does nothing about `javascript:`.
  #
  # `BackMatterResource#href` is writable on both the web and Api::V1 surfaces
  # and rendered into `<a href="...">` in four views. It carried no scheme
  # validation at all, while FederationPeer#base_url has enforced http|https
  # since it shipped — the two models disagreed, and the user-writable one was
  # the unguarded one.
  describe "BackMatterResource#href scheme allowlist" do
    def resource_with(href)
      BackMatterResource.new(
        title: "Probe", uuid: SecureRandom.uuid,
        source: "managed", rel: "reference", href: href
      )
    end

    # The vector: valid?==true before this validation existed.
    %w[
      javascript:alert(1)
      JavaScript:alert(1)
      data:text/html;base64,PHNjcmlwdD5hbGVydCgxKTwvc2NyaXB0Pg==
      vbscript:msgbox(1)
      file:///etc/passwd
    ].each do |dangerous|
      it "rejects #{dangerous[0, 28]}" do
        record = resource_with(dangerous)

        expect(record).not_to be_valid
        expect(record.errors[:href].join).to match(/scheme must be http or https/)
      end
    end

    # Rejecting these would break OSCAL import: this repo's own corpus is
    # ~25,485 fragment refs and 38 relative paths against 872 http(s) URLs, so a
    # "must be an absolute URL" rule would reject ~97% of real values.
    [
      "https://pages.nist.gov/OSCAL/",
      "http://example.gov/doc.pdf",
      "#a1b2c3d4-0000-4000-8000-000000000000",
      "../../../nist.gov/SP800-53/rev5/json/NIST_SP-800-53_rev5_catalog.json",
      "relative/path/doc.json"
    ].each do |legitimate|
      it "accepts #{legitimate[0, 34]}" do
        expect(resource_with(legitimate)).to be_valid
      end
    end

    it "accepts a blank href — it is optional" do
      expect(resource_with(nil)).to be_valid
      expect(resource_with("")).to be_valid
    end

    it "is not fooled by leading whitespace" do
      expect(resource_with("  javascript:alert(1)")).not_to be_valid
    end
  end

  # The render-side half of the house rule. Validation cannot retroactively
  # clean rows written before it existed, so the four views that put a stored
  # href into an anchor go through this.
  describe "ApplicationHelper#safe_external_url" do
    let(:helper) { Class.new { include ApplicationHelper }.new }

    it "returns nil for schemes that can execute" do
      %w[javascript:alert(1) JAVASCRIPT:alert(1) data:text/html,<script>alert(1)</script>
         vbscript:msgbox(1) file:///etc/passwd].each do |dangerous|
        expect(helper.safe_external_url(dangerous)).to be_nil, "expected #{dangerous} to be refused"
      end
    end

    it "passes through http, https and mailto" do
      %w[https://example.gov http://example.gov mailto:isso@example.gov].each do |safe|
        expect(helper.safe_external_url(safe)).to eq(safe)
      end
    end

    it "passes through fragments and relative paths — inert in an href" do
      expect(helper.safe_external_url("#uuid-here")).to eq("#uuid-here")
      expect(helper.safe_external_url("../catalog.json")).to eq("../catalog.json")
    end

    it "returns nil for blank input" do
      expect(helper.safe_external_url(nil)).to be_nil
      expect(helper.safe_external_url("   ")).to be_nil
    end

    it "is not fooled by leading whitespace or case" do
      expect(helper.safe_external_url("  JaVaScRiPt:alert(1)")).to be_nil
    end
  end

  # #897 — the house rule, enforced.
  #
  # There are ~40 `html_safe` calls in app/views, and almost all are inert:
  # `"&mdash;".html_safe`, `"&larr; Back".html_safe` — a frozen literal with
  # nothing interpolated. That is exactly the problem. A screen full of benign
  # html_safe is camouflage, and it is how the POA&M back-link
  # (`"&#8592; Back to #{@poam_document.name}".html_safe`) went unnoticed: it
  # looks like all the others, but interpolating a stored value into the string
  # disables escaping for that value too.
  #
  # RULE: html_safe may only be called on a literal containing no interpolation.
  # Anything else needs sanitize (see SessionsController#sanitize_banner) or, for
  # a URL position, safe_external_url above.
  describe "html_safe is only used on non-interpolated literals" do
    # Receiver immediately before `.html_safe`, when it is a double-quoted string
    # containing #{...}. Single-quoted Ruby strings do not interpolate.
    INTERPOLATED_HTML_SAFE = /"[^"\n]*\#\{[^}]*\}[^"\n]*"\s*\.html_safe/

    it "finds no interpolated html_safe in views or helpers" do
      offenders = Dir.glob(Rails.root.join("app/{views,helpers}/**/*.{erb,rb}")).flat_map do |path|
        relative = Pathname.new(path).relative_path_from(Rails.root).to_s
        File.readlines(path).each_with_index.filter_map do |line, i|
          "#{relative}:#{i + 1}  #{line.strip}" if line.match?(INTERPOLATED_HTML_SAFE)
        end
      end

      expect(offenders).to be_empty,
        "html_safe on an interpolated string disables escaping for the interpolated value. " \
        "If it is stored/user data this is stored XSS. Build the safe part with a helper, or " \
        "sanitize it.\n  #{offenders.join("\n  ")}"
    end

    # Proves the matcher above actually matches the shape it claims to, rather
    # than passing because the regex is wrong.
    it "would catch the #897/#902 POA&M back-link pattern" do
      expect('"&#8592; Back to #{@poam_document.name}".html_safe')
        .to match(INTERPOLATED_HTML_SAFE)
    end

    it "does not flag the inert literal form" do
      expect('"&mdash;".html_safe').not_to match(INTERPOLATED_HTML_SAFE)
      expect('"&larr; Back".html_safe').not_to match(INTERPOLATED_HTML_SAFE)
    end
  end
end
