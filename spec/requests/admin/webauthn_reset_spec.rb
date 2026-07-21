# frozen_string_literal: true

require "rails_helper"

# Admin lockout recovery for FIDO2 (#779): an admin revokes a user's security keys
# so they can re-enroll. This is the only recovery path (no self-service codes).
RSpec.describe "Admin security-key reset", type: :request do
  let(:target) { create(:user) }

  before do
    allow(SparcConfig).to receive(:fido2_enabled?).and_return(true)
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    target.webauthn_credentials.create!(external_id: "cred-#{SecureRandom.hex(6)}", public_key: "pk", sign_count: 0)
  end

  it "lets an admin revoke all of a user's keys and audits it" do
    sign_in_as(create(:user, :admin))
    expect { delete reset_security_keys_admin_user_path(target) }
      .to change { target.webauthn_credentials.count }.to(0)
      .and change { AuditEvent.where(action: "admin_webauthn_reset").count }.by(1)
    expect(response).to redirect_to(admin_user_path(target))
  end

  it "denies a non-admin" do
    sign_in_as(create(:user))
    delete reset_security_keys_admin_user_path(target)
    expect(target.webauthn_credentials.count).to eq(1)
  end
end
