# frozen_string_literal: true

# Login page controller. Renders the multi-method login view with
# conditional tabs based on SparcConfig auth toggles (local, OIDC, LDAP).
#
# Login is NOT enforced — this page is informational and prepares the
# UI surface for when authentication is implemented. No before_action
# gates any existing routes.
class SessionsController < ApplicationController
  layout "login"

  def new
    # Renders app/views/sessions/new.html.erb
  end
end
