# frozen_string_literal: true

# 1.18.0-rf #1288 / #1289 — a page showing the navigation shell's building
# blocks (layer colours, counters, tabs, segmented control, filter tokens,
# status chips, button group) and every icon, in whichever theme is active, so
# they can be reviewed before any screen uses them.
#
# It exists only while the shell is being built: off (404) unless
# SPARC_NAV_SHELL is on, and signed-in like the rest of the app. It reads no
# data.
#
# NIST SP 800-53: N/A — static presentation, no security-critical logic.
class ShellPreviewController < ApplicationController
  before_action :require_nav_shell

  def show
    @icon_names = IconHelper.names
  end

  private

  def require_nav_shell
    head :not_found unless SparcConfig.nav_shell?
  end
end
