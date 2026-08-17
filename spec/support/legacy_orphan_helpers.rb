# frozen_string_literal: true

# #952 — build a document that belongs to NO authorization boundary.
#
# SSP/SAP/SAR/POA&M now validate the boundary's presence, so `create(:ssp_document,
# authorization_boundary: nil)` raises. Rows in that state still exist: every
# instance upgraded across this change carries the ones it produced before the
# rule, and #929's attach flow is how an operator repairs them.
#
# Specs that assert behaviour FOR those rows — the storage key they get, the
# fallback OSCAL party UUID, the boundary-sync status, lineage resolution — must
# still be able to construct one. This saves without validation, which is
# exactly how such a row exists in a real database: written before the rule, not
# written around it.
#
# This is NOT a way to skip the validation in a spec that simply forgot a
# boundary. The factories associate one; use them.
module LegacyOrphanHelpers
  # create_legacy_orphan(:ssp_document, name: "Unattached Plan")
  #
  # Built complete, then the boundary column is NULLed with `update_column`,
  # which writes straight to the row without validations or callbacks. That is
  # exactly the state of a pre-#952 record: everything else well-formed, the
  # boundary empty.
  #
  # Deliberately NOT `build(...).save(validate: false)`. Skipping validation
  # also skips `before_validation`, and `Sluggable#generate_slug` runs there —
  # the record would come back with a nil slug, so every `to_param` URL built
  # from it would 404 and the spec would fail for a reason that has nothing to
  # do with what it is testing.
  def create_legacy_orphan(factory, **attrs)
    record = create(factory, **attrs)
    record.update_column(:authorization_boundary_id, nil)
    record.reload
  end
end

RSpec.configure do |config|
  config.include LegacyOrphanHelpers
end
