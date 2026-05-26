# frozen_string_literal: true

# Single helper for emitting BackMatterResourceChange rows when a
# BackMatterResource is created or duplicated through a CDEF write
# path (#581). Keeping the call site explicit (rather than a model
# callback) lets us:
#
#   - Pass the acting user through from the controller without a
#     thread-local Current.user pattern.
#   - Group multi-resource transactions (e.g. clone duplicates a
#     batch of BMRs at once) under one `batch_uuid` so the UI can
#     render them as a single audit unit.
#   - Skip the audit row in known-safe paths (system reconciliation,
#     test setup) without having to bypass a callback.
#
# Today this issue (#581) wires only the `create` change type from
# the three CDEF write paths that produce new BMRs:
#
#   1. CdefJsonParserService#promote_back_matter_resources
#   2. cdef_documents_controller#create_control_resource
#   3. cdef_documents_controller#copy → DocumentDuplicationService
#      back-matter duplication
#
# Update / archive / restore audit emission is its own follow-up.
class BackMatterAudit
  # Record a `create` change. Returns the persisted
  # BackMatterResourceChange, or nil if the resource isn't persisted
  # (defensive — callers should not call with an unsaved resource,
  # but we don't want a misuse to break the parent transaction).
  def self.record_create(resource, user: nil, batch_uuid: nil)
    return nil unless resource&.persisted?

    resource.changes_log.create!(
      change_type:       "create",
      changed_at:        Time.current,
      changed_by_user_id: user&.id,
      batch_uuid:        batch_uuid
    )
  end
end
