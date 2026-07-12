# NIST SP 800-53: N/A — informational pages, no security-critical logic
class AboutController < ApplicationController
  skip_before_action :require_authentication, only: [ :index, :quickstart, :resources ], raise: false
  skip_before_action :check_password_reset, only: [ :index, :quickstart, :resources ], raise: false

  def index
    # Static informational page: renders its template, no data to load.
  end

  def api_docs
    # Static informational page: renders its template, no data to load.
  end

  def quickstart
    # Static informational page: renders its template, no data to load.
  end

  def resources
    # Static informational page: renders its template, no data to load.
  end
end
