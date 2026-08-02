# frozen_string_literal: true

require "rails_helper"

# #857 — an invalid stored avatar used to make sign-in impossible.
#
# `record_sign_in!` saved the whole user on every successful authentication, so
# every validation had to pass for a login to succeed. The model spec pins the
# method; these pin the customer path — the actual login request — because that
# is where the failure showed up (a 422 on POST /login, with nothing in the
# response connecting it to an avatar rule).
#
# The third case is the one that keeps this fix honest: the upload gate must
# still reject a bad avatar. It would be easy to "fix" the lockout by loosening
# the rule, which would trade an outage for a hole.
RSpec.describe "Sign-in with an invalid stored avatar (#857)", type: :request do
  let(:password) { "Initial-Pwd-1234" } # gitleaks:allow
  let(:user) do
    create(:user, password: password, password_confirmation: password,
                  must_reset_password: false, password_changed_at: Time.current)
  end

  def attach_invalid_avatar(target)
    # Attaching succeeds because the validator skips while the blob is not yet
    # in the storage service; the record only becomes invalid afterwards. That
    # asymmetry is the whole bug.
    target.avatar.attach(
      io: StringIO.new("definitely not an image"),
      filename: "avatar.png",
      content_type: "image/png"
    )
    target.reload
  end

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    allow(SparcConfig).to receive(:enable_local_login?).and_return(true)
  end

  it "the stored avatar really does fail validation — the precondition" do
    attach_invalid_avatar(user)

    expect(user).not_to be_valid
    expect(user.errors[:avatar].join).to match(/must be a PNG, JPG, GIF, or WebP image/)
  end

  it "signs in successfully" do
    attach_invalid_avatar(user)

    post login_path, params: { email: user.email, password: password }

    expect(response).to have_http_status(:found)
    expect(response).not_to have_http_status(:unprocessable_entity)
    expect(session[:user_id]).to eq(user.id)
  end

  it "still records the sign-in bookkeeping" do
    attach_invalid_avatar(user)
    user.update_columns(sign_in_count: 0)

    post login_path, params: { email: user.email, password: password }

    expect(user.reload.sign_in_count).to eq(1)
    expect(user.last_sign_in_at).to be_present
  end

  it "does not weaken the upload gate — a bad avatar is still refused" do
    sign_in_as(user)

    bad = Rack::Test::UploadedFile.new(
      StringIO.new("definitely not an image"), "image/png", original_filename: "avatar.png"
    )
    patch update_avatar_profile_path, params: { user: { avatar: bad } }

    expect(flash[:error]).to match(/must be a PNG, JPG, GIF, or WebP image/)
  end
end
