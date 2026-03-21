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

      # SI-10: Server-side validation of file type and size
      unless avatar.content_type.in?(%w[image/png image/jpeg image/gif image/webp])
        redirect_to edit_profile_path, flash: { error: "Avatar must be a PNG, JPG, GIF, or WebP image." }
        return
      end

      if avatar.size > 2.megabytes
        redirect_to edit_profile_path, flash: { error: "Avatar must be less than 2 MB." }
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
