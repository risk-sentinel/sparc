# Tracks a document's *content-completeness* — whether it carries the
# required OSCAL content for its type (system characteristics, controls,
# a catalog basis, etc.).
#
# This is deliberately SEPARATE from two other axes already on documents:
#
#   * the processing `status` enum (pending → processing → completed/failed)
#     which only tracks file-import / parse-pipeline progress; and
#   * `lifecycle_status` (started → in_progress → published) which tracks
#     the authoring workflow position.
#
# A metadata-only API create (#618) has nothing to parse, so it resolves to
# `status: completed` — but that says only "the parse pipeline is done," NOT
# "the document is done." Such a shell can be `completed` yet have zero
# controls and no system characteristics (#627/#628). Content-completeness is
# the honest signal for "does this document actually have its required
# content," and the publication gate keys off it so an empty shell can never
# be published/trusted.
#
# Usage in a model:
#
#   include ContentCompleteness
#
#   requires_content("System characteristics") { system_id.present? }
#   requires_content("At least one control")   { ssp_controls.exists? }
#
# NIST 800-53: SI-10 (Information Input Validation), SI-11 (Error Handling) —
# no document is presented as done/publishable without its required content.
module ContentCompleteness
  extend ActiveSupport::Concern

  included do
    # Per-class list of [label, predicate] requirement definitions.
    # class_attribute gives each subclass its own copy; requires_content
    # reassigns (never mutates in place) so declarations don't leak across
    # models.
    class_attribute :content_requirement_defs, instance_writer: false, default: []
  end

  class_methods do
    # Declare a required-content check. `label` is the human-readable gap
    # shown when the requirement is unmet; the block is evaluated in the
    # instance context and must return truthy when the requirement is met.
    def requires_content(label, &predicate)
      raise ArgumentError, "requires_content needs a block" unless block_given?

      self.content_requirement_defs = content_requirement_defs + [ [ label, predicate ] ]
    end
  end

  # Human-readable labels for every unmet requirement (empty when complete).
  def content_completeness_gaps
    self.class.content_requirement_defs.reject do |(_label, predicate)|
      instance_exec(&predicate)
    end.map { |(label, _predicate)| label }
  end

  # True when the document carries all required content for its type.
  # Documents that declare no requirements are trivially complete.
  def content_complete?
    content_completeness_gaps.empty?
  end
end
