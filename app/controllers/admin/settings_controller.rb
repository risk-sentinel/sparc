# frozen_string_literal: true

# 1.18.0-rf #1303 — the administration settings page, the organization's
# Settings tab under SPARC_NAV_SHELL: every admin screen, grouped, with what
# each is for (AdminSettingsHelper). Read-only; each screen keeps its own
# guard. With the switch off there is no Settings tab and this page does not
# exist, as /shell_preview.
#
# NIST SP 800-53 Rev 5: AC-3, AC-6 — instance administrators only.
module Admin
  class SettingsController < ApplicationController
    before_action :authorize_admin!
    before_action { head :not_found unless SparcConfig.nav_shell? }

    def index; end
  end
end
