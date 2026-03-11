# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Security headers middleware", type: :request do
  before do
    allow(SparcConfig).to receive(:enable_local_login?).and_return(true)
    user = create(:user)
    post login_path, params: { email: user.email, password: "SecurePassword123!" }
  end

  it "sets X-Content-Type-Options to nosniff" do
    get root_path
    expect(response.headers["x-content-type-options"]).to eq("nosniff")
  end

  it "sets X-Frame-Options to SAMEORIGIN" do
    get root_path
    expect(response.headers["x-frame-options"]).to eq("SAMEORIGIN")
  end

  it "sets Referrer-Policy" do
    get root_path
    expect(response.headers["referrer-policy"]).to eq("strict-origin-when-cross-origin")
  end

  it "sets Permissions-Policy to restrict browser APIs" do
    get root_path
    expect(response.headers["permissions-policy"]).to eq("camera=(), microphone=(), geolocation=()")
  end

  it "sets X-Permitted-Cross-Domain-Policies to none" do
    get root_path
    expect(response.headers["x-permitted-cross-domain-policies"]).to eq("none")
  end
end
