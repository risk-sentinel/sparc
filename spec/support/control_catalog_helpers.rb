# frozen_string_literal: true

# #902 follow-up — helpers for specs that need a control to actually exist.
#
# Find-or-create, deliberately. The test database is not guaranteed to be empty:
# specs that import a real NIST catalog commit outside the per-example
# transaction, so a local run can accumulate thousands of catalog controls that
# persist between runs. A helper that blindly `create`d would then trip
# CatalogControl's `uniqueness: { scope: :control_family_id }` and fail in a way
# that depends on what ran before it — which is exactly what happened.
#
# The spec's requirement is "this control exists", not "I created this control",
# so find-or-create expresses the intent and is robust either way.
module ControlCatalogHelpers
  # Ensures a control with this canonical identifier exists, and returns it.
  def ensure_control(canonical, title: nil)
    canonical = ControlId.canonical(canonical)
    existing = ControlLookupService.resolve(canonical)
    return existing if existing

    code = canonical.split("-").first.to_s.upcase.presence || "AC"
    family = ControlFamily.find_by(code: code) || FactoryBot.create(:control_family, code: code)
    FactoryBot.create(:catalog_control, control_family: family, control_id: canonical,
                                        **(title ? { title: title } : {}))
  end

  # An identifier guaranteed NOT to name any control, for negative cases. Uses a
  # family code no NIST catalog uses so it cannot collide with seeded data.
  def unknown_control_id(suffix = "999")
    "ZX-#{suffix}"
  end
end

RSpec.configure do |config|
  config.include ControlCatalogHelpers
end
