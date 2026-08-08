# frozen_string_literal: true

# The reconciliation gate (#911, layer 2 of 3).
#
# **Existing documents may exist as they are. Any UPDATE requires reconciliation
# first.** Reading, listing and exporting an untouched legacy document keep
# working; editing one is refused until it declares the baseline its controls
# descend from.
#
# ── Why the gate sits at the controller, not the model ──────────────────────
#
# A model validation would fire on every write, including the ones that repair
# the problem: parsers populating a freshly imported document, the boundary
# inheriting FKs onto its siblings (#395), background jobs, data migrations.
# Those are not the writes this is about. The gate exists to stop a *person*
# editing a document whose controls cannot be traced to a catalog — so it is
# enforced where a person's intent arrives, and internal writes are unaffected.
#
# ── The exit ────────────────────────────────────────────────────────────────
#
# A write that declares the baseline is always permitted, otherwise an
# unresolved document could never become resolved and the gate would be a
# trap rather than a prompt.
#
# ── What never blocks ───────────────────────────────────────────────────────
#
# Membership findings (layer 3) are surfaced, never blocking: a system
# legitimately implements more than its baseline, and refusing on that would
# make documents uneditable pending a profile import their author may not
# control. Converters are exempt from lineage entirely — they translate between
# frameworks rather than descending from a catalog.
#
# NIST 800-53: CA-2, CA-5, CM-3 (change control against an approved baseline).
module ReconciliationGate
  extend ActiveSupport::Concern

  private

  # `before_action` form, for the UI controllers whose edit actions are many
  # and varied (update_metadata, update_statement, update_field, ...). Reads
  # the document from the instance variable the controller's own `set_*`
  # before_action already populated.
  #
  # Content-level edits carry no lineage attributes, so they are refused —
  # which is the point: adding an implementation statement to a document whose
  # controls cannot be traced to a catalog is precisely the write worth
  # stopping.
  def enforce_reconciliation_gate!
    document = instance_variable_get(:"@#{controller_name.singularize}")
    return true if document.blank?

    enforce_reconciliation!(document, params[document.model_name.param_key] || {})
  end

  # @return [Boolean] true when the caller may proceed. Renders/redirects and
  #   returns false when the write is refused.
  def enforce_reconciliation!(document, attributes)
    return true unless reconciliation_blocked?(document, attributes)

    refuse_unreconciled_write(document)
    false
  end

  def reconciliation_blocked?(document, attributes)
    return false unless document.respond_to?(:reconciliation_blocks_update?)
    return false unless document.reconciliation_blocks_update?

    # Declaring the baseline is the permitted write.
    !document.lineage_resolving_write?(attributes)
  end

  # The refusal body is the SAME object the document reports when merely
  # advisory. An integrator writes one handler and reads `blocking` to tell
  # them apart, rather than discovering a second shape the first time a write
  # is refused.
  def refuse_unreconciled_write(document)
    if request.format.json? || request.path.start_with?("/api/")
      render json: { error: reconciliation_error_message(document),
                     reconciliation: document.reconciliation },
             status: :unprocessable_entity
    else
      redirect_back fallback_location: main_app.root_path,
                    alert: reconciliation_error_message(document)
    end
  end

  def reconciliation_error_message(document)
    issue = document.reconciliation[:issues].first
    "This #{document.class.name.underscore.humanize.sub(/ document\z/i, '')} cannot be " \
    "updated until it declares the baseline its controls come from. #{issue[:message]} " \
    "#{issue[:remedy]}"
  end
end
