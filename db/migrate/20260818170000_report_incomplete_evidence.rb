# #947 — report the evidence and attestations that the new completeness rules
# leave behind, so an operator upgrading across this release is told what exists
# rather than discovering it one rejected save at a time.
#
# Deferred (see app/lib/deferred_data_migration.rb): the schema_migrations row is
# recorded at db:migrate time and the body runs post-boot, so an instance with a
# large evidence corpus still comes up immediately.
#
# ── It deliberately changes NOTHING ────────────────────────────────────────
#
# Three rules arrived with #947: evidence must link at least one control, an
# artefact type must carry its file, and an attestation must name an account
# holding the role it claims on that boundary. It is tempting to repair the
# strays. There is nothing to write that would be TRUE:
#
#   * Which control a piece of evidence supports is a judgement about what it
#     shows. Picking one — "the first", "the one its description mentions" —
#     invents a claim nobody made, and evidence filed under the wrong control is
#     worse than evidence visibly filed under none.
#   * An `attester_name` string is not reliably a person. Resolving "J. Smith"
#     to an account by name match would put a real, checkable identity behind an
#     assertion that was never checked — the precise failure this issue closes.
#     Its `signature_hash` stays intact: history is reported, never rewritten.
#
# So this reports, and the ordinary edit path is how a human resolves each case
# knowingly. The owner's disposition for both was the same: readable, reported,
# and blocked on re-save — which the model validations already do.
#
# ── The one exemption, stated out loud ─────────────────────────────────────
#
# Evidence fetched by AuthoritativeSourceFetchService is exempt from the control
# rule at creation, because which controls cite a reference document is a
# property of the citing document and is not known at fetch time. Those rows
# still appear in this report, separated out. An exemption nobody can see the
# edges of is a loophole rather than a decision.
#
# ── Idempotency ────────────────────────────────────────────────────────────
#
# It only reads. Re-running re-reports whatever is still incomplete, which is
# the desired behaviour: the count falls as an operator works through them, and
# reaching zero is the signal the work is done. Safe to resume after a partial
# failure because there is no partial state to resume from.
#
# NIST 800-53: AU-10 (non-repudiation), CA-7 (continuous monitoring).
class ReportIncompleteEvidence < ActiveRecord::Migration[8.1]
  include DeferredDataMigration
  data_migration_version "1.0.0"

  SAMPLE_LIMIT = 20

  def up
    defer_data_migration do
      unlinked      = report_unlinked_evidence
      fileless      = report_fileless_artefact_evidence
      unverifiable  = report_unverifiable_attestations

      total = unlinked + fileless + unverifiable
      if total.zero?
        Rails.logger.info({ incomplete_evidence: { count: 0, note: "none found" } }.to_json)
        next
      end

      AuditEvent.log(
        action: "incomplete_evidence_reported",
        metadata: { unlinked_evidence: unlinked, fileless_artefact_evidence: fileless,
                    unverifiable_attestations: unverifiable, total: total }
      )
    end
  end

  def down
    # Nothing was written.
  end

  private

  # Evidence supporting no control: it appears under nothing and cannot be
  # assessed. Split so a reader can tell a genuine gap from the fetched-source
  # exemption rather than reading one inflated number.
  def report_unlinked_evidence
    unlinked = Evidence.where.missing(:evidence_control_links)
    return 0 if unlinked.none?

    fetched, authored = unlinked.to_a.partition { |evidence| authoritative_source?(evidence) }

    log_evidence(authored, :unlinked_evidence,
                 "supports no control, so it appears under nothing and cannot be assessed. " \
                 "Link a control from the evidence's edit screen; the next save requires one.")

    if fetched.any?
      Rails.logger.info(
        { unlinked_evidence_fetched: {
          count: fetched.length,
          sample: sample_of(fetched),
          note: "auto-fetched authoritative sources, exempt at fetch time because the citing " \
                "document decides which controls reference them. Listed so the exemption is visible."
        } }.to_json
      )
    end

    authored.length
  end

  # An artefact type with no artefact — the record claims to show something it
  # does not carry.
  def report_fileless_artefact_evidence
    fileless = Evidence.where.not(evidence_type: Evidence::ATTESTATION_TYPES)
                       .where.missing(:file_attachment)
    return 0 if fileless.none?

    records = fileless.to_a
    log_evidence(records, :fileless_artefact_evidence,
                 "an artefact type carrying no file. Upload the file, or change the type to " \
                 "Attestation if the substance is a statement rather than a document.")
    records.length
  end

  # Attestations whose claim was never checked against the roster — every row
  # written before #947, plus any whose attester has since lost the role.
  def report_unverifiable_attestations
    records = Attestation.includes(:evidence, :attester_user).reject(&:attester_verified?)
    return 0 if records.empty?

    Rails.logger.warn(
      { unverifiable_attestations: {
        count: records.length,
        sample: records.first(SAMPLE_LIMIT).map do |attestation|
          { id: attestation.id, evidence_id: attestation.evidence_id,
            attester_name: attestation.attester_name, role: attestation.role,
            has_account: attestation.attester_user_id.present? }
        end,
        note: "the attester was never checked against the boundary roster. These stay readable " \
              "and their signature_hash is untouched; re-saving one requires resolving the " \
              "attester to an account that holds the claimed role."
      } }.to_json
    )
    records.length
  end

  # `source` is the fetched URL and the collector is the service's own label, so
  # the pair identifies the fetch path without needing a column for it.
  def authoritative_source?(evidence)
    evidence.collected_by.to_s == AuthoritativeSourceFetchService::SYSTEM_COLLECTOR ||
      BackMatterResource.exists?(evidence_id: evidence.id)
  end

  def log_evidence(records, key, note)
    return if records.empty?

    Rails.logger.warn(
      { key => { count: records.length, sample: sample_of(records), note: note } }.to_json
    )
  end

  # Bounded: an operator needs to recognise them, not receive the whole table.
  def sample_of(records)
    records.first(SAMPLE_LIMIT).map { |e| { id: e.id, title: e.title, type: e.evidence_type } }
  end
end
