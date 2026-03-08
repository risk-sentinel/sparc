# frozen_string_literal: true

module AuthenticationHelpers
  # Sign in a user for request specs by setting the session.
  def sign_in(user)
    post login_path, params: { email: user.email, password: "SecurePassword123!" }
  end

  # Sign in via session directly (bypasses controller logic).
  def sign_in_as(user)
    allow_any_instance_of(ApplicationController).to receive(:current_user).and_return(user)
    allow_any_instance_of(ApplicationController).to receive(:signed_in?).and_return(true)
  end
end

RSpec.configure do |config|
  config.include AuthenticationHelpers, type: :request
end
