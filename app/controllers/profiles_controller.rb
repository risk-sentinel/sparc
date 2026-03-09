# frozen_string_literal: true

# Handles user profile actions (avatar upload).
class ProfilesController < ApplicationController
  before_action :require_authentication

  def edit
    # Renders app/views/profiles/edit.html.erb
  end

  def update_avatar
    if params[:user] && params[:user][:avatar].present?
      current_user.avatar.attach(params[:user][:avatar])
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
