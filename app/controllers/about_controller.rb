# NIST SP 800-53: N/A — informational pages, no security-critical logic
class AboutController < ApplicationController
  skip_before_action :require_authentication, only: [ :index, :quickstart, :resources ], raise: false
  skip_before_action :check_password_reset, only: [ :index, :quickstart, :resources ], raise: false

  def index
  end

  def api_docs
  end

  def quickstart
  end

  def resources
  end
end
