# frozen_string_literal: true

# Handles user profile actions (avatar upload with crop/scale).
#
# NIST SP 800-53 Controls:
#   SI-10 Information Input Validation — validates file type and size
#         before attaching avatar (server-side, complements client-side
#         validation in avatar_crop_controller.js)
#
class ProfilesController < ApplicationController
  before_action :require_authentication

  def edit
    # Renders app/views/profiles/edit.html.erb
  end

  def update_avatar
    if params[:user] && params[:user][:avatar].present?
      avatar = params[:user][:avatar]

      # SI-10: Server-side validation. Magic-byte content-type sniff (#509)
      # — client-supplied Content-Type header is NOT trusted. Size cap
      # checked at the model layer via AttachmentSizeLimit (#510), which
      # honors SPARC_MAX_AVATAR_MB.
      actual = File.open(avatar.tempfile.path, "rb") { |io| Marcel::MimeType.for(io) }
      unless User::ALLOWED_AVATAR_MIME_TYPES.include?(actual)
        redirect_to edit_profile_path,
          flash: { error: "Avatar must be a PNG, JPG, GIF, or WebP image (detected #{actual.inspect})." }
        return
      end

      current_user.avatar.attach(avatar)
      redirect_to edit_profile_path, flash: { success: "Avatar updated." }
    else
      redirect_to edit_profile_path, flash: { error: "Please select an image to upload." }
    end
  end

  def remove_avatar
    current_user.avatar.purge if current_user.avatar.attached?
    redirect_to edit_profile_path, flash: { success: "Avatar removed." }
  end
end
