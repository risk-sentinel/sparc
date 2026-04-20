# #396: Leveraged Authorization inheritance computation.
#
# Only Scenario 1 (leveraged SSP is in SPARC and the leveraging org has
# access) populates inheritance links automatically — Scenarios 2/3 rely
# on CRM back-matter uploads since the leveraged SSP isn't queryable.
#
# NIST OSCAL Implementation Layers deck slide 18-19: the leveraging SSP
# links to leveraged statements by UUID; `provided` / `responsibility`
# tags on leveraged statements identify what may be inherited and what
# responsibility the leveraging system must address.
class LeveragedAuthorizationService
  class << self
    # Populate inheritance links from a Scenario-1 leveraged boundary.
    # Returns the number of links created (or found, for idempotency).
    def populate_from_leveraged!(leveraged_auth)
      return 0 unless leveraged_auth.scenario == 1

      leveraging_ssp = leveraged_auth.leveraging_boundary.ssp_document
      return 0 unless leveraging_ssp

      links = 0
      leveraged_auth.inheritable_statements.find_each do |source_stmt|
        control_id = source_stmt.ssp_control.control_id
        target_ctrl = leveraging_ssp.ssp_controls.find_by(control_id: control_id)
        next unless target_ctrl

        target_stmt = upsert_target_statement(target_ctrl, source_stmt)
        next unless target_stmt

        link = SspControlStatementInheritance.find_or_initialize_by(
          ssp_control_statement_id: target_stmt.id,
          source_type: "SspControlStatement",
          source_id: source_stmt.id
        )
        link.source_uuid = source_stmt.uuid
        link.overridden = false unless link.persisted?
        links += 1 if link.changed? && link.save
      end
      links
    end

    # Gap detection: statements on the leveraged SSP flagged as customer
    # responsibility that are NOT addressed (have no inheritance link
    # with overridden=false) on the leveraging SSP.
    #
    # Surfaces in the UI as a finding and (future) as a SAR validation rule.
    def responsibility_gaps(leveraged_auth)
      return [] unless leveraged_auth.scenario == 1

      leveraging_ssp = leveraged_auth.leveraging_boundary.ssp_document
      return [] unless leveraging_ssp

      responsibility_stmts = leveraged_auth.inheritable_statements
                                           .where(
                                             "set_parameters_data::jsonb @> ?::jsonb",
                                             [ { "tag" => "responsibility" } ].to_json
                                           )
      return [] if responsibility_stmts.empty?

      addressed_uuids = SspControlStatementInheritance
                          .from_leveraged.active
                          .where(source_id: responsibility_stmts.pluck(:id))
                          .joins(:ssp_control_statement)
                          .where(ssp_control_statements: { ssp_control_id: leveraging_ssp.ssp_controls.select(:id) })
                          .pluck(:source_uuid)
                          .to_set

      responsibility_stmts.reject { |s| addressed_uuids.include?(s.uuid) }
    end

    private

    def upsert_target_statement(target_ctrl, source_stmt)
      stmt = target_ctrl.ssp_control_statements
                        .find_or_initialize_by(statement_id: source_stmt.statement_id)
      if stmt.new_record?
        stmt.uuid = OscalUuidService.derived(target_ctrl.uuid, "ssp-statement", source_stmt.statement_id)
        stmt.label = source_stmt.label
        stmt.parent_statement_id = source_stmt.parent_statement_id
        stmt.implementation_prose = source_stmt.implementation_prose
        stmt.row_order = source_stmt.row_order
        stmt.save!
      end
      stmt
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      Rails.logger.warn("[LeveragedAuth] skipping statement #{source_stmt.statement_id}: #{e.class} #{e.message}")
      nil
    end
  end
end
