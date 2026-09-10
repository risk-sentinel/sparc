# frozen_string_literal: true

# #1100 — REST API for an SSP's per-statement implementation prose.
#
#   GET   /api/v1/ssp_documents/:ssp_document_id/statements
#   GET   /api/v1/ssp_control_statements/:id
#   PATCH /api/v1/ssp_control_statements/:id
#
# WHY THIS EXISTS
#
# Answering a control per STATEMENT is how OSCAL models an SSP, and since #393 it
# is how SPARC stores one — but the only way to write `implementation_prose` was
# the HTML member route `PATCH /ssp_documents/:id/update_statement`. The UI was
# the sole path to the field that carries the actual system security plan, which
# is exactly backwards: the UI is meant to be a thin client over the API.
#
# NO create, NO destroy. Statements are DERIVED from the catalog's part tree by
# `CatalogPartExtractorService` — their `statement_id` and derived UUID are what
# an exported document references (#397), so inventing or deleting one through
# the API would put the SSP out of step with the catalog it claims to implement.
# Structure comes from the catalog; only the prose is authored.
#
# NIST 800-53 Controls:
#   IA-2 (token auth), AC-3/AC-6 (boundary-scoped RBAC),
#   AU-12 (audit record generation), CM-3 (documented change to the SSP)
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
class Api::V1::SspControlStatementsController < Api::V1::BaseController
  before_action :set_document,  only: %i[index]
  before_action :set_statement, only: %i[show update]
  before_action :authorize_read!,  only: %i[index show]
  before_action :authorize_write!, only: %i[update]

  # GET /api/v1/ssp_documents/:ssp_document_id/statements
  #
  # Optionally narrowed to one control with ?control_id=ac-2, which is what an
  # editor showing a single card needs and saves it filtering a whole document.
  def index
    scope = SspControlStatement
              .joins(:ssp_control)
              .where(ssp_controls: { ssp_document_id: @document.id })

    if params[:control_id].present?
      scope = scope.where(ssp_controls: { control_id: params[:control_id] })
    end

    scope  = scope.order("ssp_controls.control_id ASC, ssp_control_statements.row_order ASC")
    result = paginate(scope, items: 100)

    render json: { data: result[:data].map { |stmt| serialize(stmt) }, meta: result[:meta] }
  end

  # GET /api/v1/ssp_control_statements/:id
  def show
    render json: { data: serialize(@statement, detailed: true) }
  end

  # PATCH /api/v1/ssp_control_statements/:id
  def update
    @statement.update!(statement_params)

    audit_log("ssp_statement_updated", subject: @statement,
              metadata: { ssp_document_id: @document&.id,
                          control_id: @statement.ssp_control&.control_id,
                          statement_id: @statement.statement_id })
    render json: { data: serialize(@statement, detailed: true) }
  end

  private

  # slug OR id, matching the sibling document controllers — a caller who listed
  # documents gets the identifier the listing gave them, not a 404 (#1010).
  def set_document
    param = params[:ssp_document_id].to_s
    @document = SspDocument.find_by(slug: param) || SspDocument.find(param)
    @boundary = @document.authorization_boundary
  end

  def set_statement
    @statement = SspControlStatement.find(params[:id])
    @document  = @statement.ssp_control&.ssp_document
    @boundary  = @document&.authorization_boundary
  end

  # Prose only. `statement_id`, `parent_statement_id`, `row_order` and `uuid`
  # belong to the catalog's part tree, and letting a client move them would
  # break the join `CdefToSspInheritanceService` and the exporter rely on.
  def statement_params
    # `responsible_roles_data` is permitted as a SHAPE, not a blob: OSCAL models
    # responsible-roles as objects carrying a role-id, and the exporter writes
    # this column straight into the document, so a bare array of strings would
    # emit schema-invalid OSCAL.
    permit_strictly(:ssp_control_statement, :implementation_prose, :remarks,
      responsible_roles_data: [ :"role-id", { "party-uuids": [] } ]
    )
  end

  def serialize(stmt, detailed: false)
    data = {
      id: stmt.id,
      uuid: stmt.uuid,
      statement_id: stmt.statement_id,
      parent_statement_id: stmt.parent_statement_id,
      label: stmt.label,
      row_order: stmt.row_order,
      control_id: stmt.ssp_control&.control_id,
      # Whether this row still needs an answer is the question the whole
      # per-statement model exists to make askable — a client should not have to
      # infer it from an empty string.
      answered: stmt.implementation_prose.present?,
      source_kind: stmt.source_kind
    }

    if detailed
      data[:implementation_prose] = stmt.implementation_prose
      data[:remarks] = stmt.remarks
      data[:responsible_roles] = stmt.responsible_roles_data
      data[:created_at] = stmt.created_at.iso8601
      data[:updated_at] = stmt.updated_at.iso8601
    end

    data
  end

  def authorize_read!
    return if current_user.admin?
    return if current_user.has_permission?("ssp.read", authorization_boundary_id: @boundary&.id)

    raise NotAuthorizedError, "Not authorized to view SSP statements"
  end

  def authorize_write!
    return if current_user.admin?
    return if current_user.has_permission?("ssp.write", authorization_boundary_id: @boundary&.id)

    raise NotAuthorizedError, "Not authorized to modify SSP statements"
  end
end
