# frozen_string_literal: true

require "rails_helper"

# #1390 — the boundary's FedRAMP Certification Package Overview fields,
# contacts and overview address (FedrampPackageOverview).
RSpec.describe FedrampPackageOverview do
  let(:boundary) { create(:authorization_boundary) }

  around do |example|
    saved = ENV.fetch("SPARC_APP_URL", nil)
    example.run
  ensure
    saved.nil? ? ENV.delete("SPARC_APP_URL") : ENV["SPARC_APP_URL"] = saved
  end

  describe "fedramp_package=" do
    it "merges, so a partial update keeps the other fields" do
      boundary.update!(fedramp_package: { service_name: "Example Cloud", service_acronym: "EXC" })
      boundary.update!(fedramp_package: { service_acronym: "EC" })
      expect(boundary.reload.fedramp_package).to eq("service_name" => "Example Cloud", "service_acronym" => "EC")
    end

    it "removes a field sent blank, and ignores keys it does not know" do
      boundary.update!(fedramp_package: { service_name: "Example Cloud", unknown: "x" })
      boundary.update!(fedramp_package: { service_name: "  " })
      expect(boundary.reload.fedramp_package).to eq({})
    end

    it "keeps a list without the blank a form posts, and drops an empty one" do
      boundary.update!(fedramp_package: { service_types: [ "", "SaaS", "SaaS", "PaaS" ], business_categories: [ "" ] })
      expect(boundary.reload.fedramp_package).to eq("service_types" => %w[SaaS PaaS])
    end

    it "stores whether the trust center needs sign-in as a boolean" do
      boundary.update!(fedramp_package: { trust_center_url: "https://trust.example", trust_center_description: "TC",
                                          trust_center_authentication_required: "false" })
      expect(boundary.reload.fedramp_value("trust_center_authentication_required")).to be(false)
    end
  end

  describe "validation" do
    def errors_for(attrs)
      boundary.fedramp_package = attrs
      boundary.valid?
      boundary.errors.full_messages
    end

    it "accepts only the values the FedRAMP schema lists" do
      expect(errors_for(certification_type: "Rev4"))
        .to include("FedRAMP package overview: Certification type must be one of: 20x, Rev5")
      expect(errors_for(certification_type: "Rev5", service_types: [ "FaaS" ]))
        .to include(a_string_including("Service model has unknown values: FaaS"))
      expect(errors_for(service_types: [ "SaaS" ], deployment_model: "Government-Only Cloud")).to be_empty
    end

    it "allows at most ten business categories" do
      categories = AuthorizationBoundary.fedramp_choices("business_categories").first(11)
      expect(errors_for(business_categories: categories)).to include(a_string_including("may list at most 10"))
    end

    it "wants a logo address that names an image" do
      expect(errors_for(logo: "https://provider.example/logo.txt")).to include(a_string_including("Logo address must be"))
      expect(errors_for(logo: "https://provider.example/logo.svg?v=2")).to be_empty
    end

    it "wants http(s) addresses and ISO dates" do
      expect(errors_for(website: "provider.example")).to include(a_string_including("Website must be an http(s) address"))
      expect(errors_for(website: "https://provider.example", next_ocr_date: "12/01/2026"))
        .to include(a_string_including("must be a date in the form YYYY-MM-DD"))
    end

    it "wants the trust center's description, and its instructions when it needs sign-in" do
      messages = errors_for(trust_center_url: "https://trust.example", trust_center_authentication_required: "true")
      expect(messages).to include(a_string_including("Trust center description can't be blank"),
                                  a_string_including("access instructions are needed"))
      expect(errors_for(trust_center_url: "", trust_center_description: "orphan"))
        .to include(a_string_including("Trust center address is needed"))
    end

    it "checks each contact's type, email and phone" do
      boundary.fedramp_contacts = [ { contact_type: "Boss", email: "not-an-email", phone: "12" } ]
      boundary.valid?
      expect(boundary.errors.full_messages).to include(
        "FedRAMP contacts: contact 1: type must be one of Security, Sales, Primary",
        "FedRAMP contacts: contact 1: email is not an email address",
        "FedRAMP contacts: contact 1: phone must be a US number, e.g. 202-555-0123"
      )
    end

    it "accepts the US phone forms FedRAMP's schema allows" do
      [ "202-555-0123", "(800) 555-0199", "+1 202.555.0123 ext. 42" ].each do |phone|
        boundary.fedramp_contacts = [ { contact_type: "Sales", phone: phone } ]
        expect(boundary).to be_valid, phone
      end
    end

    it "limits the contacts list" do
      boundary.fedramp_contacts = Array.new(21) { { contact_type: "Primary", name: "x" } }
      boundary.valid?
      expect(boundary.errors.full_messages).to include("FedRAMP contacts: may list at most 20")
    end
  end

  describe "fedramp_contacts=" do
    it "takes the index-keyed hash a form posts, trims, and drops empty rows" do
      boundary.update!(fedramp_contacts: { "0" => { "contact_type" => "Sales", "name" => " Sales " },
                                           "1" => { "contact_type" => "", "name" => "" } })
      expect(boundary.reload.fedramp_contacts).to eq([ { "contact_type" => "Sales", "name" => "Sales" } ])
    end
  end

  describe "#fedramp_overview_missing" do
    it "names each required field and contact type not yet recorded" do
      boundary.update!(fedramp_contacts: [ { contact_type: "Primary", name: "x" } ])
      expect(boundary.fedramp_overview_missing).to include("FedRAMP ID", "Logo address", "Service model",
                                                           "a Security contact", "a Sales contact")
      expect(boundary).not_to be_fedramp_overview_ready
    end

    it "is empty once everything is recorded" do
      expect(create(:authorization_boundary, :fedramp_overview_ready)).to be_fedramp_overview_ready
    end
  end

  describe "#fedramp_overview_address" do
    it "is the address set on the boundary by default" do
      boundary.update!(fedramp_package_overview_uri: "https://trust.example/cpo.json")
      expect(boundary.fedramp_overview_address).to eq("https://trust.example/cpo.json")
    end

    it "is SPARC's own endpoint under SPARC_APP_URL, by the boundary UUID, when chosen" do
      ENV["SPARC_APP_URL"] = "https://sparc.example.gov:8443/sparc/"
      boundary.update!(fedramp_overview_from_sparc: true, fedramp_package_overview_uri: "https://trust.example/cpo.json")
      expect(boundary.fedramp_overview_address).to eq(
        "https://sparc.example.gov:8443/sparc/api/v1/authorization_boundaries/#{boundary.uuid}/fedramp/certification_package_overview"
      )
    end

    it "cannot be SPARC's own endpoint unless SPARC_APP_URL is https" do
      ENV["SPARC_APP_URL"] = "http://sparc.example.gov"
      boundary.fedramp_overview_from_sparc = true
      expect(boundary).not_to be_valid
      expect(boundary.errors.full_messages).to include("SPARC's own overview endpoint needs SPARC_APP_URL to be an https:// address")
    end

    it "is nil when SPARC's own endpoint was chosen and SPARC_APP_URL later stops being https" do
      ENV["SPARC_APP_URL"] = "https://sparc.example.gov"
      boundary.update!(fedramp_overview_from_sparc: true)
      ENV.delete("SPARC_APP_URL")
      expect(boundary.fedramp_overview_address).to be_nil
    end
  end

  describe "#fedramp_overview_document" do
    it "maps the fields onto the FedRAMP schema's names and omits what is not recorded" do
      ready = create(:authorization_boundary, :fedramp_overview_ready)
      ready.update!(fedramp_package: { trust_center_url: "https://trust.example", trust_center_description: "TC",
                                       trust_center_authentication_required: "true",
                                       trust_center_access_instructions: "Ask us." })
      doc = ready.fedramp_overview_document
      expect(doc["serviceIdentification"]).to include("fedRampPackageId" => "FR2400000001", "certificationType" => "20x")
      expect(doc["serviceIdentification"]).not_to have_key("ueiNumber")
      expect(doc["serviceProperties"]["trustCenter"]).to eq(
        "repositoryType" => [ "Trust Center" ], "url" => "https://trust.example", "repositoryDescription" => "TC",
        "authenticationRequired" => true, "accessRequestInstructions" => "Ask us."
      )
      expect(doc["contactInformation"].last).to eq("contactType" => "Sales", "contactName" => "Sales Team",
                                                   "contactPhone" => "202-555-0123")
    end
  end
end
