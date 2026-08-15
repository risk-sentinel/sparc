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

    # Gap detection: statements the leveraged SSP flags as a customer
    # responsibility that the leveraging system has NOT yet implemented for
    # itself. See `addressed?` for what counts — it is deliberately not "a
    # link exists" (#956).
    #
    # Surfaces in the UI as a finding and (future) as a SAR validation rule.
    def responsibility_gaps(leveraged_auth)
      return [] unless leveraged_auth.scenario == 1

      leveraging_ssp = leveraged_auth.leveraging_boundary.ssp_document
      return [] unless leveraging_ssp

      responsibility_stmts = leveraged_auth.inheritable_statements
                                           .where(
                                             "set_parameters_data::jsonb @> ?::jsonb",
                                             [ { "tag" => SspControlStatement::RESPONSIBILITY_TAG } ].to_json
                                           )
      return [] if responsibility_stmts.empty?

      responsibility_stmts.reject { |source| addressed?(source, leveraging_ssp) }
    end

    private

    # #956 — only a `provided` statement carries an implementation the
    # leveraging system can inherit. A `responsibility` says "the customer
    # must do this themselves"; copying that in as the customer's own
    # implementation prose asserts the opposite of an implementation, and it
    # showed on screen — Boundary 2's SSP read "The reference platform does
    # not implement AC-20" as B's own narrative. A responsibility scaffolds a
    # place to author, not a pre-filled answer.
    def inheritable_prose(source_stmt)
      return nil if source_stmt.customer_responsibility?

      source_stmt.implementation_prose
    end

    # #956 — "addressed" used to mean "an active inheritance link exists",
    # which was wrong in BOTH directions and made the gap report useless:
    #
    #   - populate_from_leveraged! creates exactly that link for every
    #     responsibility, so doing NOTHING cleared the gap.
    #   - editing the statement flips the link to overridden, dropping it out
    #     of `.active`, so doing the RIGHT THING re-opened the gap. A customer
    #     who correctly implemented a responsibility was told they had not.
    #
    # A link records where a responsibility came FROM. It says nothing about
    # whether anyone has acted on it. Addressed means the leveraging system
    # has written its own implementation: the statement exists, carries prose,
    # and that prose is not merely the provider's text arriving by inheritance.
    def addressed?(source_stmt, leveraging_ssp)
      target = SspControlStatement
                 .joins(:ssp_control)
                 .where(ssp_controls: { ssp_document_id: leveraging_ssp.id,
                                        control_id: source_stmt.ssp_control.control_id })
                 .find_by(statement_id: source_stmt.statement_id)

      return false if target.nil? || target.implementation_prose.blank?

      link = target.inheritance_links.find_by(source_type: "SspControlStatement",
                                              source_id: source_stmt.id)

      # No link: the prose was authored independently. Overridden: the author
      # replaced what was inherited. Either way, someone did the work.
      link.nil? || link.overridden?
    end

    # The `new_record?` guard alone left inherited statements EMPTY once #955
    # made profile-generated SSPs arrive with statements already scaffolded:
    # the target was no longer a new record, so the source prose was never
    # copied and the leveraging system showed "inherited" with nothing in it.
    #
    # A statement that exists but carries no prose has nothing to protect, so
    # the source fills it. Author edits are still never clobbered — once
    # someone writes prose it is no longer blank, and the controller flips the
    # link to `overridden` on edit regardless.
    def upsert_target_statement(target_ctrl, source_stmt)
      stmt = target_ctrl.ssp_control_statements
                        .find_or_initialize_by(statement_id: source_stmt.statement_id)
      if stmt.new_record?
        stmt.uuid = OscalUuidService.derived(target_ctrl.uuid, "ssp-statement", source_stmt.statement_id)
        stmt.label = source_stmt.label
        stmt.parent_statement_id = source_stmt.parent_statement_id
        stmt.implementation_prose = inheritable_prose(source_stmt)
        stmt.row_order = source_stmt.row_order
        stmt.save!
      elsif stmt.implementation_prose.blank? && inheritable_prose(source_stmt).present?
        stmt.update!(implementation_prose: inheritable_prose(source_stmt))
      end
      stmt
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotUnique => e
      Rails.logger.warn("[LeveragedAuth] skipping statement #{source_stmt.statement_id}: #{e.class} #{e.message}")
      nil
    end
  end
end
