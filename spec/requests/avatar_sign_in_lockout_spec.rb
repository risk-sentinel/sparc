# frozen_string_literal: true

require "rails_helper"

# #857 / #892 — an avatar that no longer satisfies the content-type rule used to
# make an account unusable, and the failure surfaced as a 422 on login with
# nothing pointing at an avatar.
#
# Two faults combined into that:
#
#   #857  `record_sign_in!` saved the whole user on every authentication, so
#         every validation had to pass for a login to succeed.
#   #892  the avatar validator ran on EVERY save of a user who had one,
#         re-reading the stored blob — and, at upload time, did not actually
#         run at all.
#
# The scenario below is the one the issue warns about and the one that survives
# both fixes: a stored avatar that was legitimate when uploaded and stops being
# legitimate when the rule is tightened. Simulated with stub_const rather than
# by writing a bad file, because after #892 a bad file cannot be attached.
RSpec.describe "Sign-in with a stored avatar that fails the current rule (#857, #892)",
               type: :request do
  let(:password) { "Initial-Pwd-1234" } # gitleaks:allow
  let(:user) do
    create(:user, password: password, password_confirmation: password,
                  must_reset_password: false, password_changed_at: Time.current)
  end
  let(:real_image) { Rails.root.join("app/assets/images/sparc_admin.jpg") }

  before do
    allow(SparcConfig).to receive(:any_auth_enabled?).and_return(true)
    allow(SparcConfig).to receive(:enable_local_login?).and_return(true)
  end

  def attach_then_tighten
    skip "fixture image missing" unless File.exist?(real_image)
    user.avatar.attach(io: File.open(real_image), filename: "sparc_admin.jpg",
                       content_type: "image/jpeg")
    user.reload
    # The rule changes under the user's feet — a dropped format, a new size cap,
    # a dimension requirement. Their stored avatar no longer qualifies.
    stub_const("User::ALLOWED_AVATAR_MIME_TYPES", %w[image/gif])
  end

  it "signs in successfully" do
    attach_then_tighten

    post login_path, params: { email: user.email, password: password }

    expect(response).to have_http_status(:found)
    expect(response).not_to have_http_status(:unprocessable_content)
    expect(session[:user_id]).to eq(user.id)
  end

  it "still records the sign-in bookkeeping" do
    attach_then_tighten
    user.update_columns(sign_in_count: 0)

    post login_path, params: { email: user.email, password: password }

    expect(user.reload.sign_in_count).to eq(1)
    expect(user.last_sign_in_at).to be_present
  end

  it "keeps the avatar — it is not silently purged to let the login through" do
    attach_then_tighten

    post login_path, params: { email: user.email, password: password }

    expect(user.reload.avatar).to be_attached
  end

  # The fix must not become a hole. Loosening the rule would also have "fixed"
  # the lockout, so the upload gate is re-asserted here.
  it "does not weaken the upload gate — a bad avatar is still refused" do
    sign_in_as(user)

    bad = Rack::Test::UploadedFile.new(
      StringIO.new("definitely not an image"), "image/png", original_filename: "avatar.png"
    )
    patch update_avatar_profile_path, params: { user: { avatar: bad } }

    expect(flash[:error]).to match(/must be a PNG, JPG, GIF, or WebP image/)
    expect(user.reload.avatar).not_to be_attached
  end
end
