# frozen_string_literal: true

# Shared bulk-delete logic for index pages + their API endpoints (#629).
#
# Attempts to destroy each record by id, honoring the model's referential
# integrity guards (SafeDestroyable#deletion_dependencies). It is
# **partial-success, not all-or-nothing**: unassociated records are deleted,
# blocked records are reported with their reason, and one blocked row never
# prevents the others from being deleted.
#
# Each attempt is audited per-row, mirroring the single-delete controllers:
#   "<model>_deleted"        on success
#   "<model>_delete_blocked" on a referential-integrity block
# (both action names must exist in AuditEvent::ACTIONS).
#
# Usage:
#   result = BulkDestroyService.new(
#     model_class: CdefDocument, ids: params[:ids],
#     user: current_user, ip_address: request.remote_ip
#   ).call
#   result.deleted  # => [{ id:, name: }, ...]
#   result.blocked  # => [{ id:, name:, reason: }, ...]
#   result.missing  # => [unknown ids]
#
# NIST 800-53: AC-3/AC-6 (admin-gated destructive action — caller authorizes),
# AU-12 (every attempt audited).
class BulkDestroyService
  Result = Struct.new(:deleted, :blocked, :missing, keyword_init: true) do
    def summary_sentence(label)
      parts = [ "#{deleted.size} #{label.pluralize(deleted.size)} deleted" ]
      parts << "#{blocked.size} blocked" if blocked.any?
      parts << "#{missing.size} not found" if missing.any?
      parts.join(", ") + "."
    end
  end

  MAX_IDS = 500

  def initialize(model_class:, ids:, user:, ip_address: nil)
    @model_class = model_class
    @ids         = Array(ids).map { |i| i.to_s.strip }.reject(&:blank?).uniq.first(MAX_IDS)
    @user        = user
    @ip_address  = ip_address
  end

  def call
    deleted = []
    blocked = []

    found = @model_class.where(id: @ids)
    found_by_id = found.index_by { |r| r.id.to_s }
    missing = @ids - found_by_id.keys

    found.each do |record|
      name = record.try(:name) || "##{record.id}"
      if record.destroy
        audit("#{audit_prefix}_deleted", record, name: name)
        deleted << { id: record.id, name: name }
      else
        reason = record.errors.full_messages.join(", ").presence || "Could not be deleted"
        audit("#{audit_prefix}_delete_blocked", record, name: name, reason: reason)
        blocked << { id: record.id, name: name, reason: reason }
      end
    end

    Result.new(deleted: deleted, blocked: blocked, missing: missing)
  end

  private

  def audit_prefix
    @model_class.name.underscore
  end

  def audit(action, subject, metadata)
    AuditEvent.log(action: action, user: @user, subject: subject,
                   metadata: metadata, ip_address: @ip_address)
  rescue => e
    Rails.logger.warn("Bulk-destroy audit log failed: #{e.message}")
    raise unless Rails.env.production?
  end
end
