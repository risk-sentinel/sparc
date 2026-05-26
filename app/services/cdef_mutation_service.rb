# frozen_string_literal: true

# Single contract for all CDEF mutations (#498).
#
# Every write to a CdefDocument and its child records (cdef_controls,
# cdef_control_statements, cdef_control_fields, back_matter_resources)
# should go through this service. The service:
#
#   1. Wraps the caller's mutations in a database transaction so a
#      validation failure rolls back cleanly.
#   2. Validates that the post-mutation OSCAL representation conforms
#      to NIST OSCAL component-definition v1.1.2 BEFORE the transaction
#      commits. Rejects writes that would produce an invalid OSCAL hash.
#   3. (Slice 2) Regenerates derived UUIDs via OscalUuidService so
#      statement / component identifiers stay deterministic across
#      mutations.
#   4. (Slice 3) Promotes back-matter resources to first-class
#      BackMatterResource rows and emits BackMatterResourceChange audit
#      records.
#
# Usage:
#
#     cdef = CdefMutationService.apply(cdef_document) do |c|
#       c.update!(name: "Updated")
#       c.cdef_controls.create!(control_id: "ac-1", title: "...")
#     end
#
# If the block raises, the transaction rolls back. If the post-mutation
# OSCAL representation fails schema validation, the service raises
# `CdefMutationService::ValidationError` and the transaction rolls back.
#
# Slice 1 scope: the service contract + pre-save OSCAL validation.
# Wired into Api::V1::CdefDocumentsController#update as proof; other
# write paths (clone, parser write-through, web controller, manual
# edit) refactor to use this in slice 2.
class CdefMutationService
  class ValidationError < StandardError; end

  # Wrap a mutation block. Yields the document to the caller; on
  # successful block return, validates that the resulting OSCAL would
  # round-trip cleanly, then commits the transaction.
  #
  # Returns the (reloaded) document.
  def self.apply(cdef_document)
    raise ArgumentError, "block required" unless block_given?

    new(cdef_document).apply { |c| yield c }
  end

  def initialize(cdef_document)
    @cdef = cdef_document
  end

  def apply
    raise ArgumentError, "block required" unless block_given?

    ActiveRecord::Base.transaction do
      yield(@cdef)

      # Reload to ensure validation sees the post-mutation state (in
      # case the block did partial updates without a final save / used
      # raw SQL / mutated children).
      @cdef.reload

      validate_oscal_representation!
    end

    @cdef
  end

  private

  # Build the OSCAL hash via the existing exporter and confirm it
  # conforms to the NIST component-definition schema. Raises
  # `ValidationError` (which the transaction wrapper catches as a
  # rollback signal) when the resulting OSCAL would be invalid.
  #
  # CDEFs with no controls cannot satisfy the schema's
  # `components[].control-implementations[]` constraint, so we skip
  # validation for empty CDEFs — they exist legitimately as
  # placeholders / stubs during import + bulk-apply workflows.
  def validate_oscal_representation!
    return if @cdef.cdef_controls.none?

    service = OscalComponentDefinitionExportService.new(@cdef)
    result  = service.validation_result

    return if result.valid?

    raise ValidationError, "CDEF mutation produced invalid OSCAL " \
                           "(component-definition v#{result.schema_version}):\n" \
                           "#{result.errors.first(5).join("\n")}"
  end
end
