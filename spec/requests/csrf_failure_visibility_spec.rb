# frozen_string_literal: true

require "rails_helper"

# #978 — a CSRF rejection must reach the screen.
#
# The bug was not that the request was refused; refusing it is correct. The bug
# was that the refusal produced a 422 Turbo swallows, so the login form came
# back blank-faced and the operator read it as "these credentials are wrong".
#
# NOTE ON THE HARNESS: `config.action_controller.allow_forgery_protection` is
# FALSE in the test environment, so none of this is reachable by default — a
# spec written without the toggle below passes while asserting nothing. Each
# example turns protection on for its own duration and restores it after.
RSpec.describe "CSRF failure visibility", type: :request do
  around do |example|
    original = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = original
  end

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    allow(SparcConfig).to receive(:enable_local_login?).and_return(true)
  end

  describe "a form POST whose Origin does not match the app's own base URL" do
    it "redirects with a visible message instead of a silently swallowed 422" do
      post login_path,
           params: { email: "someone@example.gov", password: "whatever" },
           headers: { "HTTP_ORIGIN" => "http://www.example.com:9999" }

      expect(response).to have_http_status(:see_other)
      expect(flash[:error]).to be_present
    end

    it "names the scheme mismatch and says plainly that it is NOT a bad password" do
      post login_path,
           params: { email: "someone@example.gov", password: "whatever" },
           headers: { "HTTP_ORIGIN" => "http://www.example.com:9999" }

      expect(flash[:error]).to match(/NOT a wrong password/i)
      expect(flash[:error]).to include("www.example.com")
    end

    # The message is worthless if the layout cannot render the key it was set
    # under. A key missing from ApplicationHelper::FLASH_CLASSES renders
    # nowhere, silently (#902) — the same class of invisible failure this issue
    # is about, which is why this asserts on the BODY and not just on flash.
    it "renders the message in the page the user lands on" do
      post login_path,
           params: { email: "someone@example.gov", password: "whatever" },
           headers: { "HTTP_ORIGIN" => "http://www.example.com:9999" }
      follow_redirect!

      expect(response.body).to match(/NOT a wrong password/i)
    end

    it "keeps the flash key inside the registry the layouts actually read" do
      expect(ApplicationHelper::FLASH_CLASSES).to have_key("error")
    end
  end

  describe "a cross-site origin" do
    it "does not echo the attacker-controlled origin back into the page" do
      hostile = "https://evil.example.net"

      post login_path,
           params: { email: "someone@example.gov", password: "whatever" },
           headers: { "HTTP_ORIGIN" => hostile }

      expect(flash[:error]).to be_present
      expect(flash[:error]).not_to include("evil.example.net")
    end
  end

  describe "an ordinary same-origin request" do
    it "is not affected by the handler at all" do
      get login_path

      expect(response).to have_http_status(:ok)
      expect(flash[:error]).to be_nil
    end
  end
end
