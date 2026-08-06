# Canonicalise a control identifier on write (#911, layer 1 of 3).
#
# Control identifiers have three legitimate forms (#852) — `ac-2.1` canonical,
# `AC-02.01` padded (SPARC's display convention), `AC-2 (1)` as NIST writes it.
# Catalogs store the canonical form. Anything that accepted a typed identifier
# and stored it verbatim therefore produced references that matched nothing on a
# literal comparison: not just typos, but the padded form SPARC itself puts on
# screen. Measured before this landed: `SarControl` and `EvidenceControlLink`
# resolved **0%** verbatim and **100%** after canonicalisation.
#
# ── What this does NOT do ────────────────────────────────────────────────────
#
# It does not check that the control exists, and it does not consult a catalog.
# `ControlId.canonical` is a pure string transform, so this is deterministic,
# idempotent and needs no database access. Two records referencing the same
# control converge on the same identifier independently, with nothing to
# coordinate and no cross-model writes — each record canonicalises its own
# column when that record is saved.
#
# Whether an identifier is *in scope* for its document is membership, which
# depends on lineage and is deliberately separate (layers 2 and 3).
#
# ── Migration posture ────────────────────────────────────────────────────────
#
# Existing rows are not rewritten wholesale; a row adopts the canonical form
# when it is next saved. Until then a column holds a mix, so comparisons must
# match `ControlId.forms(...)` rather than a single spelling.
#
# ── Why a callback alone is not enough ───────────────────────────────────────
#
# `before_validation` covers the interactive paths — a UI edit, an API PATCH —
# and misses the one that creates almost every row. All nine parser services
# insert through `BatchInsertable#batch_insert_records`, which calls
# `activerecord-import` with `validate: false`; that runs neither
# `before_validation` nor `before_save`. Measured on the same model with the
# same input:
#
#   IMPORT path stored: "AC-02 (1)"   SAVE path stored: "ac-2.1"
#
# So the callback would have canonicalised hand-edits while leaving imports
# untouched — and imports are where the malformed data came from in the first
# place (`SarControl` measured 0% verbatim, written by `sar_excel_parser_service`).
#
# `canonicalise_control_ids!` exists for those writers. It is the SAME transform
# reached a second way, not a second implementation: a bulk writer that wants a
# private normaliser is #852 recurring, so the attribute list is declared once
# here and every writer reads it.
#
# Usage:
#
#   class SspControl < ApplicationRecord
#     include ControlIdentifiable
#     canonicalises_control_id :control_id
#   end
#
# NIST 800-53: CA-2 / CA-5 / PM-6 (consistent control identification across the
# assessment and authorization artifacts).
module ControlIdentifiable
  extend ActiveSupport::Concern

  included do
    # Which columns this model canonicalises. Declared once, read by both the
    # callback and the bulk-insert path so the two cannot drift apart.
    class_attribute :canonicalised_control_id_attributes,
                    instance_writer: false,
                    default: [].freeze
  end

  class_methods do
    # Canonicalise one or more identifier columns before validation.
    # Blank values are left alone — presence is a separate concern, and several
    # models legitimately allow a row with no control id (shared-responsibility
    # entries in an SSP, an unmapped STIG rule in a CDEF).
    def canonicalises_control_id(*attributes)
      declared = attributes.flatten.map(&:to_sym)
      self.canonicalised_control_id_attributes =
        (canonicalised_control_id_attributes + declared).uniq.freeze

      declared.each do |attribute|
        before_validation { canonicalise_control_id_attribute(attribute) }
      end
    end

    # Apply the same transform to an unsaved record, for writers that bypass
    # callbacks (`activerecord-import`). Returns the record so it composes with
    # the `map` that builds an import batch.
    def canonicalise_control_ids!(record)
      canonicalised_control_id_attributes.each do |attribute|
        record.send(:canonicalise_control_id_attribute, attribute)
      end
      record
    end
  end

  private

  def canonicalise_control_id_attribute(attribute)
    value = public_send(attribute)
    return if value.blank?

    canonical = ControlId.canonical(value)
    # `canonical` returns "unknown" for input it cannot parse. Storing that
    # would replace the user's identifier with a word, losing the only record of
    # what they meant, so the original is kept instead.
    public_send(:"#{attribute}=", canonical) unless canonical == "unknown"
  end
end
