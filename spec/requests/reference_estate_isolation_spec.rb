# frozen_string_literal: true

require "rails_helper"

# #845 — the reference estate is two ORGANIZATIONS, not two folders.
#
# Boundary 2 leverages Boundary 1, which means Org B legitimately inherits
# implementation prose from Org A's SSP through the inheritance links the
# estate wires up. That relationship is exactly what makes this worth pinning:
# a leveraging relationship grants a view of what the provider *declared it
# provides*, and nothing else. It must not become a back door to the
# provider's SSP, assessment plan, assessment results, or POA&Ms — the
# documents that would tell Org B where Org A is weak.
#
# The estate is the first fixture in the suite where that distinction can be
# tested against real documents rather than two empty records that happen to
# have different boundary ids.
RSpec.describe "Reference estate boundary isolation (#845)", type: :request do
  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    allow(SparcConfig).to receive(:enable_local_login?).and_return(true)
  end

  let(:estate)   { reference_estate(:lean) }
  let(:provider) { estate.leveraged }
  let(:consumer) { estate.leveraging }

  # Force the estate BEFORE any request. `estate` is a lazy `let`, so an
  # example that only names it inside its assertion builds it *after* the
  # response has already been rendered — the index then lists nothing and
  # `expect(body).not_to include(...)` passes without testing anything. That
  # is not hypothetical: it hid one example from a mutation that removed
  # boundary scoping from the index entirely.
  before { estate }

  let(:reader_role) do
    create(:role, :authorization_boundary_scoped, name: "estate_reader",
           permissions: { "ssp.read" => true, "sap.read" => true,
                          "sar.read" => true, "poam.read" => true })
  end

  def member_of(boundary)
    user = create(:user)
    create(:user_role, user: user, role: reader_role, authorization_boundary: boundary)
    user
  end

  # A user in Org B, holding every read permission the estate's documents use,
  # scoped to Boundary 2. Permission is not the question here — scope is.
  let(:consumer_reader) { member_of(consumer[:boundary]) }
  let(:provider_reader) { member_of(provider[:boundary]) }
  let(:outsider)        { create(:user) }

  # The API authenticates by bearer token, not by session, so a signed-in
  # session reaches it as an anonymous request and every assertion below would
  # have measured 401 rather than scoping.
  def api_headers_for(user)
    { "Authorization" => "Bearer #{ApiToken.generate!(user: user, name: 'Estate isolation').plaintext_token}" }
  end

  # Each document type, with the index and show paths for both sides.
  DOCUMENT_TYPES = {
    ssp:  ->(side) { side[:ssp] },
    sap:  ->(side) { side[:sap] },
    sar:  ->(side) { side[:sar] }
  }.freeze

  # The estate takes a few seconds to build and every request here only reads
  # it, so the requests one reader makes about one kind of document share an
  # example (and so one estate). `aggregate_failures` reports each claim that
  # fails by its own message instead of stopping at the first.
  describe "the leveraging boundary cannot read the leveraged boundary's documents" do
    DOCUMENT_TYPES.each do |kind, fetch|
      it "blocks the provider's #{kind.upcase} by URL and in the index, and still serves the consumer's own",
         :aggregate_failures do
        document = fetch.call(provider)
        expect(document).to be_present, "estate did not build a #{kind}"

        sign_in_as(consumer_reader)

        get send(:"#{kind}_document_path", document)
        expect(response).to have_http_status(:redirect), "a direct URL to the provider's #{kind} was not blocked"

        get send(:"#{kind}_document_path", fetch.call(consumer))
        expect(response).to have_http_status(:ok), "the consumer could not read their own #{kind}"

        get send(:"#{kind}_documents_path")
        expect(response.body).to include(html_text(fetch.call(consumer).name))
        expect(response.body).not_to include(html_text(fetch.call(provider).name))
      end
    end

    # Every POA&M name contains an ampersand, so a raw comparison of the index
    # would pass vacuously in BOTH directions — the provider check would never
    # fail and the consumer check always would. See HtmlEscapingHelpers.
    it "blocks each of the provider's POA&Ms by URL and omits them from the index", :aggregate_failures do
      poams = provider[:poams]
      expect(poams).to be_present

      sign_in_as(consumer_reader)
      poams.each do |poam|
        get poam_document_path(poam)
        expect(response).to have_http_status(:redirect), "#{poam.name} was readable"
      end

      get poam_documents_path
      provider[:poams].each { |poam| expect(response.body).not_to include(html_text(poam.name)) }
      consumer[:poams].each { |poam| expect(response.body).to include(html_text(poam.name)) }
    end
  end

  # The API is the DAST surface and a separate authorization path from the
  # controllers above — a scoping fix applied to one has more than once left
  # the other open.
  describe "the API scopes the estate the same way" do
    it "lists and serves a consumer-scoped reader their own SSP, and neither lists nor serves the provider's",
       :aggregate_failures do
      headers = api_headers_for(consumer_reader)

      get api_v1_ssp_documents_path, headers: headers
      names = JSON.parse(response.body).fetch("data", []).map { |d| d["name"] }
      expect(names).to include(consumer[:ssp].name)
      expect(names).not_to include(provider[:ssp].name)

      get api_v1_ssp_document_path(provider[:ssp]), headers: headers
      expect(response).to have_http_status(:not_found).or have_http_status(:forbidden)

      get api_v1_ssp_document_path(consumer[:ssp]), headers: headers
      expect(response).to have_http_status(:ok)
    end
  end

  describe "an outsider to both organizations" do
    it "sees neither boundary's SSP in the index and cannot open either directly", :aggregate_failures do
      sign_in_as(outsider)

      get ssp_documents_path
      expect(response.body).not_to include(provider[:ssp].name)
      expect(response.body).not_to include(consumer[:ssp].name)

      get ssp_document_path(provider[:ssp])
      expect(response).to have_http_status(:redirect)
      get ssp_document_path(consumer[:ssp])
      expect(response).to have_http_status(:redirect)
    end
  end

  # The mirror of every assertion above: the isolation is real, not an
  # artefact of the estate failing to build. If the provider's own member
  # cannot read these either, the specs above prove nothing.
  describe "the leveraged boundary's own member" do
    it "reads every document the consumer was refused" do
      sign_in_as(provider_reader)

      DOCUMENT_TYPES.each do |kind, fetch|
        get send(:"#{kind}_document_path", fetch.call(provider))
        expect(response).to have_http_status(:ok), "provider member could not read their own #{kind}"
      end

      provider[:poams].each do |poam|
        get poam_document_path(poam)
        expect(response).to have_http_status(:ok), "provider member could not read #{poam.name}"
      end
    end
  end

  # Inheritance is the one thing that DOES cross the boundary, and it crosses
  # as copied prose on the consumer's own statements — not as a reference the
  # consumer can follow back into the provider's document.
  describe "what the leveraging relationship does grant" do
    it "gives the consumer inherited prose without giving it the source document" do
      expect(estate.inheritance_links).to be_positive

      inherited = SspControlStatement.joins(:ssp_control)
                                     .where(ssp_controls: { ssp_document_id: consumer[:ssp].id })
                                     .select(&:inherited?)
      expect(inherited).to be_present

      sign_in_as(consumer_reader)
      get ssp_document_path(consumer[:ssp])
      expect(response).to have_http_status(:ok)

      get ssp_document_path(provider[:ssp])
      expect(response).to have_http_status(:redirect)
    end
  end
end
