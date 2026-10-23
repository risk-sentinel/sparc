# frozen_string_literal: true

# #1271 — what a failed copy tells the user. Every document action that
# duplicates a document (Copy on profiles and CDEFs, and a new profile made
# from a published one) reports a failure the same way: logged with its
# backtrace, audited as `<type>_copy_failed` against the source, and shown on
# the source document as "Could not duplicate '<name>': <reason>".
#
# Before, only the CDEF copy did (#519). A failed profile copy raised past the
# controller, and under Turbo the user saw the source page sit unchanged with
# no message at all.
#
# NIST 800-53: AU-12 (audit), SI-11 (error handling).
module DocumentCopyReporting
  extend ActiveSupport::Concern

  private

  # Runs the block, which duplicates `source` and returns the copy. On any
  # error, reports it and redirects to `source`; returns nil so the caller
  # stops. `audit_metadata` is merged into the failure's audit metadata.
  def reporting_copy_failure(source, audit_metadata: {})
    yield
  rescue StandardError => e
    type = source.class.model_name.singular
    Rails.logger.error("[#{controller_name}##{action_name}] #{type} source_id=#{source.id} " \
                       "copy failed: #{e.class}: #{e.message}")
    Rails.logger.error("[#{controller_name}##{action_name}] backtrace: #{Array(e.backtrace).first(20).join(' | ')}")
    audit_log("#{type}_copy_failed", subject: source,
              metadata: { source_id: source.id, source_name: source.name,
                          error_class: e.class.to_s, error_message: e.message.to_s[0, 300] }
                          .merge(audit_metadata).compact)
    flash[:error] = "Could not duplicate '#{source.name}': #{copy_failure_reason(e)}"
    redirect_to polymorphic_path(source)
    nil
  end

  # A failed validation names the field ("Slug has already been taken"), not
  # Rails' "Validation failed: " preamble.
  def copy_failure_reason(error)
    reason = error.is_a?(ActiveRecord::RecordInvalid) ? error.record.errors.full_messages.join(", ") : error.message
    reason.to_s[0, 200]
  end
end
