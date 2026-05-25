# frozen_string_literal: true

# Helpers for asserting AuditEvent emission from API mutations (#433 slice 5).
#
# Every mutating API endpoint in `Api::V1::*` is expected to call
# `audit_log(action, subject:, metadata:)`, which in turn writes an
# `AuditEvent` row via `AuditEvent.log`. Forgetting to call `audit_log`
# is a silent compliance bug — the action succeeds, but there's no
# trail. These helpers make it cheap to assert the event was written
# with the right action name and subject.
#
# Usage:
#
#     expect {
#       post api_v1_cdef_documents_path, params: {...}, headers: auth
#     }.to emit_audit_event(action: "cdef_document_created", subject_type: "CdefDocument")
#
# Or the imperative form for finer control:
#
#     before_count = AuditEvent.count
#     post api_v1_cdef_documents_path, params: {...}, headers: auth
#     expect(AuditEvent.count - before_count).to eq(1)
#     event = AuditEvent.order(created_at: :desc).first
#     expect(event.action).to eq("cdef_document_created")

module AuditEventHelpers
  # Block-form assertion: yields to the block, asserts exactly one
  # AuditEvent row was created with the given action (and optionally
  # subject_type / metadata). Returns the event for further assertions.
  def assert_audit_event(action:, subject_type: nil, metadata: nil)
    before_count = AuditEvent.count
    yield
    after_count = AuditEvent.count

    delta = after_count - before_count
    expect(delta).to eq(1),
      "Expected 1 AuditEvent to be created with action #{action.inspect}, " \
      "got #{delta}. Last event: #{AuditEvent.order(created_at: :desc).first&.attributes&.slice('action', 'subject_type', 'metadata')&.inspect || 'none'}"

    event = AuditEvent.order(created_at: :desc).first
    expect(event.action).to eq(action),
      "Expected audit event action #{action.inspect}, got #{event.action.inspect}"

    expect(event.subject_type).to eq(subject_type) if subject_type

    metadata&.each do |key, expected_value|
      actual = event.metadata[key.to_s] || event.metadata[key.to_sym]
      expect(actual).to eq(expected_value),
        "Expected audit event metadata[#{key.inspect}] to be #{expected_value.inspect}, got #{actual.inspect}"
    end

    event
  end
end

RSpec.configure do |config|
  config.include AuditEventHelpers, type: :request
end
