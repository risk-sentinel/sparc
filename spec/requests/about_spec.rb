require "rails_helper"

RSpec.describe "About pages", type: :request do
  describe "GET /about" do
    it "returns 200 without authentication" do
      get about_path
      expect(response).to have_http_status(:ok)
    end

    it "contains key section headings" do
      get about_path
      body = response.body
      expect(body).to include("About SPARC")
      expect(body).to include("What is SPARC?")
      expect(body).to include("OSCAL Framework Layers")
      expect(body).to include("FedRAMP 20x and OSCAL")
      expect(body).to include("The Authoritative Layer")
      expect(body).to include("MITRE SAF")
      expect(body).to include("Control Mappings and Converters")
      expect(body).to include("Get Started")
    end
  end

  describe "GET /about/quickstart" do
    it "returns 200 without authentication" do
      get about_quickstart_path
      expect(response).to have_http_status(:ok)
    end

    it "contains step-by-step guide content" do
      get about_quickstart_path
      body = response.body
      expect(body).to include("Quick-Start Guide")
      expect(body).to include("Installation")
      expect(body).to include("Seed the Database")
      expect(body).to include("First Login")
      expect(body).to include("Export OSCAL")
      expect(body).to include("API Access")
    end
  end

  describe "GET /about/api" do
    it "redirects to login without authentication" do
      allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
      get about_api_path
      expect(response).to redirect_to(login_path)
    end

    context "when authenticated" do
      let(:user) { create(:user) }

      before { sign_in_as(user) }

      it "returns 200" do
        get about_api_path
        expect(response).to have_http_status(:ok)
      end

      it "contains API documentation content" do
        get about_api_path
        body = response.body
        expect(body).to include("API Documentation")
        expect(body).to include("Authentication")
        expect(body).to include("SSP Documents")
        expect(body).to include("KSI Catalog")
        expect(body).to include("Bearer")
      end
    end
  end
end
