# frozen_string_literal: true

# #904 — an operator's assertion that a CDEF covers a given service, or that a
# CDEF is expected never to appear in Terraform state.
#
# Replaces the reference script's hardcoded CUSTOM_ALIAS and ALWAYS_KEEP
# constants (sparc-iac `state_cdef_coverage.py`). Both describe one deployment's
# CDEF library rather than anything universal, so they are data.
#
# ── Why this is an assertion and not a guess ──────────────────────────────
#
# The coverage analysis will not infer that a CDEF named "ecs-fargate" covers
# `ecs`. Name matching is exactly the kind of inference #911 ruled out for
# catalog lineage and #887 ruled out for capabilities: it manufactures a claim
# about compliance coverage from prose. A row here is a human saying so, which
# is auditable in a way a regex over titles is not.
class CdefServiceAlias < ApplicationRecord
  belongs_to :cdef_document, optional: true

  validates :service_key, presence: true
  validates :service_key, uniqueness: { scope: :cdef_document_id,
                                        message: "is already asserted for this component definition" }

  # An ALWAYS_KEEP entry asserts absence is expected, so it needs no document.
  # A mapping entry asserts a specific CDEF covers a service, so it needs one.
  validate :mapping_entries_name_a_document

  scope :always_keep, -> { where(always_keep: true) }
  scope :mappings, -> { where(always_keep: false).where.not(cdef_document_id: nil) }

  # Service keys whose CDEF is expected to be absent from any Terraform state,
  # so a missing deployment is not reported as stale.
  def self.always_keep_service_keys = always_keep.distinct.pluck(:service_key)

  # cdef_document_id => [service keys the operator says it covers]
  def self.mapping_index
    mappings.pluck(:cdef_document_id, :service_key)
            .each_with_object(Hash.new { |h, k| h[k] = [] }) { |(id, key), acc| acc[id] << key }
  end

  private

  def mapping_entries_name_a_document
    return if always_keep? || cdef_document_id.present?

    errors.add(:cdef_document_id, "is required unless the entry is marked always_keep")
  end
end
