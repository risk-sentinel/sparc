# frozen_string_literal: true

require "rails_helper"

# #808 — the PIV/CAC login button is shown only when a verified client cert was
# forwarded on the login request, when SPARC_PIV_LOGIN_REQUIRES_CERT=true;
# default keeps today's always-show (when PIV is enabled).
RSpec.describe "PIV login button visibility (#808)", type: :request do
  BUTTON = "Sign in with your CAC / smart card"
  VERIFY_HEADER = "X-SSL-Client-Verify"

  before { allow(SparcConfig).to receive(:enable_piv?).and_return(true) }

  context "default (SPARC_PIV_LOGIN_REQUIRES_CERT off)" do
    before { allow(SparcConfig).to receive(:piv_login_requires_cert?).and_return(false) }

    it "shows the button when PIV is enabled, with no cert header" do
      get "/login"
      expect(response.body).to include(BUTTON)
    end

    it "shows the button regardless of a cert header" do
      get "/login", headers: { VERIFY_HEADER => "SUCCESS" }
      expect(response.body).to include(BUTTON)
    end
  end

  context "SPARC_PIV_LOGIN_REQUIRES_CERT=true" do
    before { allow(SparcConfig).to receive(:piv_login_requires_cert?).and_return(true) }

    it "shows the button when a verified cert is present at page load" do
      get "/login", headers: { VERIFY_HEADER => "SUCCESS" }
      expect(response.body).to include(BUTTON)
    end

    it "matches the verify value case-insensitively" do
      get "/login", headers: { VERIFY_HEADER => "success" }
      expect(response.body).to include(BUTTON)
    end

    it "hides the button when no verified cert is present" do
      get "/login"
      expect(response.body).not_to include(BUTTON)
    end

    it "hides the button when the verify header is not SUCCESS" do
      get "/login", headers: { VERIFY_HEADER => "NONE" }
      expect(response.body).not_to include(BUTTON)
    end
  end

  it "never shows the button when PIV is disabled" do
    allow(SparcConfig).to receive(:enable_piv?).and_return(false)
    get "/login", headers: { VERIFY_HEADER => "SUCCESS" }
    expect(response.body).not_to include(BUTTON)
  end
end
