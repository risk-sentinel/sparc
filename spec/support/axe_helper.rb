# frozen_string_literal: true

# Layer 3 of the UI test net (#599) — axe-core accessibility matchers for
# RSpec system specs. Mirrors the Layer 2 Playwright axe audit, scoped to
# WCAG 2.1 A + AA (the Section 508 conformance bar).
#
# Usage in a system spec:
#   expect(page).to be_axe_clean.according_to(*SparcAxe::WCAG_2_1_AA)
#
# Baseline / ratchet: existing accessibility debt is recorded as skipped
# rule ids in SparcAxe::BASELINE_SKIPS (keyed by page). `.skipping(*rules)`
# excludes those known-failing rules so new violations still fail the build.
# Burn the baseline down by removing rule ids as they're fixed.
require "axe-rspec"

module SparcAxe
  # WCAG 2.1 Level A + AA rule tags — the Section 508 bar.
  WCAG_2_1_AA = %i[wcag2a wcag2aa wcag21a wcag21aa].freeze

  # Known, tracked violations per page (rule id). Documented debt — fixing a
  # page means deleting its rule ids here. Captured against the rendered app
  # at #599; see also tests/ui-smoke/a11y_baseline.json for the Layer 2 set.
  # Empty: the login-page debt (low-contrast secondary button + amber heading,
  # consent-banner scroll region missing keyboard focusability) was burned down
  # in #602 (v1.8.6). Add new page keys here only to track freshly-found debt.
  BASELINE_SKIPS = {}.freeze

  def self.baseline_for(key)
    BASELINE_SKIPS.fetch(key, [])
  end
end
