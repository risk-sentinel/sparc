# #398: CDEF → SSP control statement auto-population.
#
# When an SSP author adds a component backed by a CDEF to their system,
# this service:
#   1. Finds every (cdef_control, cdef_statement) pair on the CDEF
#   2. For each matching ssp_control (by control_id), creates/updates an
#      ssp_control_statement with the CDEF's implementation prose
#   3. Persists an SspControlStatementInheritance link so the UI can
#      display the inherited badge and the refresh job can re-sync
#
# Idempotent: re-running on the same (ssp, component) does not create
# duplicates. Overridden inheritance links are left alone on refresh.
#
# NIST OSCAL Implementation Layers deck slide 13: component-driven SSP
# authoring. Implements the "inline copy + source UUID" pattern described
# in the issue risks section.
class CdefToSspInheritanceService
  class << self
    # Phase 1+2 for #398: populate SSP statements from a single SspComponent.
    # Returns the number of inheritance links created or updated.
    def populate_from_component!(ssp_document, ssp_component)
      return 0 unless ssp_component.cdef_document_id
      cdef = CdefDocument.find_by(id: ssp_component.cdef_document_id)
      return 0 unless cdef

      populate_from_cdef(ssp_document, cdef)
    end

    # Refresh all non-overridden inherited statements on the SSP from the
    # latest CDEF prose. Returns the number of statements updated.
    def refresh_from_cdef!(ssp_document, cdef_document)
      updated = 0
      cdef_stmt_ids = CdefControlStatement
                        .joins(:cdef_control)
                        .where(cdef_controls: { cdef_document_id: cdef_document.id })
                        .pluck(:id)

      # `preload` instead of `includes` avoids EagerLoadPolymorphicError
      # on the polymorphic `source` association.
      SspControlStatementInheritance
        .from_cdef.active
        .where(source_id: cdef_stmt_ids)
        .joins(:ssp_control_statement)
        .where(ssp_control_statements: { ssp_control_id: ssp_document.ssp_controls.select(:id) })
        .preload(:ssp_control_statement, :source)
        .find_each do |link|
          next if link.source.nil?
          if link.ssp_control_statement.update(implementation_prose: link.source.implementation_prose)
            updated += 1
          end
        end
      updated
    end

    # Refresh every SSP that has inheritance links sourced from this CDEF.
    # Used by the post-CDEF-save background job / rake task.
    def refresh_all_consumers!(cdef_document)
      consumer_ssp_ids = SspComponent
                           .where(cdef_document_id: cdef_document.id)
                           .pluck(:ssp_document_id)
                           .uniq
      consumer_ssp_ids.sum do |ssp_id|
        ssp = SspDocument.find_by(id: ssp_id)
        ssp ? refresh_from_cdef!(ssp, cdef_document) : 0
      end
    end

    private

    # Walk every CDEF control/statement and create (or find) the matching
    # SSP statement + inheritance link. Does NOT overwrite existing prose
    # on already-linked statements (callers use refresh_from_cdef! for that).
    def populate_from_cdef(ssp_document, cdef)
      links = 0
      cdef.cdef_controls.includes(:cdef_control_statements).find_each do |cdef_ctrl|
        ssp_ctrl = ssp_document.ssp_controls
                               .find_by(control_id: cdef_ctrl.control_id)
        next unless ssp_ctrl

        cdef_ctrl.cdef_control_statements.each do |cdef_stmt|
          ssp_stmt = upsert_ssp_statement(ssp_ctrl, cdef_stmt)
          next unless ssp_stmt

          link = SspControlStatementInheritance.find_or_initialize_by(
            ssp_control_statement_id: ssp_stmt.id,
            source_type: "CdefControlStatement",
            source_id: cdef_stmt.id
          )
          link.source_uuid = cdef_stmt.uuid
          link.overridden = false unless link.persisted?
          links += 1 if link.changed? && link.save
        end
      end
      links
    end

    def upsert_ssp_statement(ssp_ctrl, cdef_stmt)
      stmt = ssp_ctrl.ssp_control_statements
                     .find_or_initialize_by(statement_id: cdef_stmt.statement_id)

      if stmt.new_record?
        stmt.uuid = OscalUuidService.derived(ssp_ctrl.uuid, "ssp-statement", cdef_stmt.statement_id)
        stmt.label = cdef_stmt.label
        stmt.parent_statement_id = cdef_stmt.parent_statement_id
        stmt.implementation_prose = cdef_stmt.implementation_prose
        stmt.row_order = cdef_stmt.row_order
        stmt.save!
      end

      stmt
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      Rails.logger.warn("[CdefToSspInheritance] skipping statement #{cdef_stmt.statement_id}: #{e.class} #{e.message}")
      nil
    end
  end
end
