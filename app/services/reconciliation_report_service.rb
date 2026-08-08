# frozen_string_literal: true

# Instance-wide catalog-lineage reconciliation report (#911, layer 2 of 3).
#
# The per-document banner tells one author about one document. An operator
# adopting this needs to size the whole job before it lands on them — how many
# documents are affected, of which types, and what each needs. Discovering that
# one refusal at a time is how an upgrade becomes a support ticket.
#
# ── Soft-deleted records are excluded, deliberately ─────────────────────────
#
# `SspDocument` and friends carry `default_scope { where(deleted_at: nil) }`, so
# the ordinary relation already excludes them and this must not use `unscoped`.
# This matters more than it looks: an earlier analysis of this very data counted
# 36 SSPs where the application sees 2, because soft-deleted `phase2-test-*`
# rows from the API suite were included. A report that counts deleted documents
# tells an operator to fix work that no longer exists.
class ReconciliationReportService
  # Every document type that declares catalog lineage. Listed explicitly rather
  # than discovered by scanning descendants, so a new document type shows up
  # here by a deliberate edit instead of appearing unannounced in an operator's
  # report.
  DOCUMENT_TYPES = [
    ProfileDocument, SspDocument, SapDocument, SarDocument, PoamDocument, CdefDocument
  ].freeze

  Row = Struct.new(:document, :type_label, :reconciliation, keyword_init: true) do
    def blocking? = reconciliation[:blocking].present?
    def codes     = reconciliation[:issues].map { _1[:code] }
  end

  # @return [Array<Row>] unresolved documents, blocking ones first — an operator
  #   works down the list, and the ones that stop people editing come first.
  def rows
    @rows ||= DOCUMENT_TYPES.flat_map { |klass| rows_for(klass) }
                            .sort_by { |row| [ row.blocking? ? 0 : 1, row.type_label, row.document.name.to_s ] }
  end

  def any?  = rows.any?
  def total = rows.size

  # Blocking vs advisory is the distinction that decides urgency: blocking
  # documents cannot be edited until reconciled; advisory ones are findings to
  # act on, not work that is stopping anybody.
  def blocking_count = rows.count(&:blocking?)
  def advisory_count = total - blocking_count

  # For the summary strip: how much of each type is affected, and out of how
  # many. A bare count of 12 means nothing without knowing whether that is 12
  # of 12 or 12 of 4000.
  def summary
    DOCUMENT_TYPES.map do |klass|
      affected = rows.count { |row| row.document.is_a?(klass) }
      { type: klass.model_name.human.pluralize, affected: affected, total: klass.count }
    end
  end

  private

  def rows_for(klass)
    label = klass.model_name.human
    # `includes` is not used: `reconciliation` touches the lineage association
    # of each row, so preloading only the declared associations keeps this to a
    # bounded number of queries rather than one per document.
    scope(klass).filter_map do |document|
      reconciliation = document.reconciliation
      next if reconciliation.blank?

      Row.new(document: document, type_label: label, reconciliation: reconciliation)
    end
  end

  def scope(klass)
    associations = klass.lineage_defs.flat_map { _1[:associations] }.uniq
    klass.preload(associations)
  end
end
