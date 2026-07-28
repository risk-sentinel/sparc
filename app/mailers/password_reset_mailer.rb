# frozen_string_literal: true

# #841 — delivers an admin-issued password reset link.
#
# One of two recovery routes. This one requires configured SMTP; where there is
# none (an air-gapped or mail-less deployment), the admin issues a temporary
# password out of band instead. Neither route lets an administrator learn a
# password the user keeps.
#
# The link carries the only copy of the token — the database holds a SHA-256
# digest — so it cannot be re-sent, only re-issued.
#
# NIST 800-53: IA-5 (Authenticator Management), AU-12 (the send is audited by
# the caller), SC-8 (delivery security is the SMTP configuration's concern).
class PasswordResetMailer < ApplicationMailer
  def reset_link(user, token, issued_by: nil)
    @user = user
    @issued_by = issued_by
    @reset_url = "#{SparcConfig.app_url.chomp('/')}#{Rails.application.routes.url_helpers.edit_password_reset_path(token: token)}"
    @expires_at = user.password_reset_expires_at

    mail(to: user.email, subject: "#{SparcConfig.app_name} — password reset")
  end
end
