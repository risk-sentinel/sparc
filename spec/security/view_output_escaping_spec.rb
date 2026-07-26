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

  describe "GET /poam_documents/:id/poam_items/new" do
    before { get new_poam_document_poam_item_path(poam) }

    include_examples "escapes the document name"
  end

  describe "GET /poam_documents/:id/poam_items/:id/edit" do
    before { get edit_poam_document_poam_item_path(poam, item) }

    include_examples "escapes the document name"
  end
end
