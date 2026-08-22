# frozen_string_literal: true

# #1015 — REST API for a boundary's leveraged authorizations (#396).
#
#   GET    /api/v1/authorization_boundaries/:authorization_boundary_id/leveraged_authorizations
#   POST   /api/v1/authorization_boundaries/:authorization_boundary_id/leveraged_authorizations
#   GET    /api/v1/authorization_boundaries/:authorization_boundary_id/leveraged_authorizations/:id
#   POST   .../leveraged_authorizations/:id/populate
#   DELETE .../leveraged_authorizations/:id
#
# Found by the missing-endpoint axis of #995: a leveraged authorization records
# the ATO a system inherits from, OSCAL exports it as part of every SSP on the
# leveraging boundary, and it could be created, populated and deleted only from
# a browser.
#
# THE AUTHORITY MODEL IS MEMBERSHIP, NOT A PERMISSION KEY, and that is
# deliberate. The web controller guards on "assigned to this boundary" rather
# than `authorization_boundaries.write`, recorded in the #919 memo as the one
# place membership and permission still disagree. Narrowing it here to a
# permission key would be a product decision made silently inside an API
# addition, and would leave the two surfaces enforcing different rules — so
# this mirrors the web guard exactly. Change both together or neither.
#
# NIST 800-53 Controls:
#   CA-3 System Interconnections, CA-9 Internal System Connections,
#   AC-3 Access Enforcement, AU-12 Audit Record Generation
# See: docs/compliance/nist-sp800-53-rev5-mapping.md
class Api::V1::LeveragedAuthorizationsController < Api::V1::BaseController
  before_action :set_leveraging_boundary
  before_action :authorize_leveraging_boundary!
  before_action :set_leveraged_authorization, only: %i[show populate destroy]

  # GET .../leveraged_authorizations
  def index
    scope = @leveraging_boundary.leveraging_relationships.order(:id)
    result = paginate(scope, items: 50)

    render json: {
      data: result[:data].map { |record| serialize(record) },
      meta: result[:meta]
    }
  end

  # GET .../leveraged_authorizations/:id
  def show
    render json: { data: serialize(@leveraged_authorization, detailed: true) }
  end

  # POST .../leveraged_authorizations
  def create
    record = @leveraging_boundary.leveraging_relationships.new(leveraged_authorization_params)
    record.save!

    # Scenario 1 is the only one where SPARC holds the leveraged SSP, so it is
    # the only one that can populate inheritance links at creation.
    populated = if record.scenario == 1
      LeveragedAuthorizationService.populate_from_leveraged!(record)
    end

    audit_log("leveraged_authorization_created", subject: record,
              metadata: { boundary: @leveraging_boundary.slug, uuid: record.uuid,
                          crm_type: record.crm_type, populated: populated })

    render json: {
      data: serialize(record, detailed: true).merge(inheritance_links_populated: populated)
    }, status: :created
  end

  # POST .../leveraged_authorizations/:id/populate
  #
  # Idempotent re-import of inheritance links from the leveraged SSP, for when
  # the leveraged system's prose has moved on.
  def populate
    count = LeveragedAuthorizationService.populate_from_leveraged!(@leveraged_authorization)

    audit_log("leveraged_authorization_populated", subject: @leveraged_authorization,
              metadata: { boundary: @leveraging_boundary.slug, links: count })

    render json: {
      data: serialize(@leveraged_authorization, detailed: true)
              .merge(inheritance_links_populated: count)
    }
  end

  # DELETE .../leveraged_authorizations/:id
  def destroy
    audit_log("leveraged_authorization_deleted", subject: @leveraged_authorization,
              metadata: { boundary: @leveraging_boundary.slug,
                          uuid: @leveraged_authorization.uuid })
    @leveraged_authorization.destroy

    render json: {
      data: { id: @leveraged_authorization.id, uuid: @leveraged_authorization.uuid,
              deleted: true }
    }
  end

  private

  # AuthorizationBoundary uses Sluggable, so the web route param is a slug. Both
  # are accepted here: an API caller holding a numeric id from a list response
  # should not have to fetch the slug to use it.
  def set_leveraging_boundary
    param = params[:authorization_boundary_id].to_s
    @leveraging_boundary = AuthorizationBoundary.find_by(slug: param) ||
                           AuthorizationBoundary.find(param)
  end

  def set_leveraged_authorization
    @leveraged_authorization =
      @leveraging_boundary.leveraging_relationships.find(params[:id])
  end

  # Mirrors LeveragedAuthorizationsController#authorize_leveraging_boundary!.
  # See the note at the top of this file before changing it.
  def authorize_leveraging_boundary!
    return unless SparcConfig.any_auth_enabled?
    return if current_user&.admin?
    return if @leveraging_boundary.assigned_users.exists?(id: current_user&.id)

    raise NotAuthorizedError,
          "Membership of boundary '#{@leveraging_boundary.slug}' required"
  end

  def leveraged_authorization_params
    permit_strictly(:leveraged_authorization,
      :name, :crm_type, :leveraged_boundary_id, :date_authorized, :description
    )
  end

  def serialize(record, detailed: false)
    data = {
      id: record.id,
      uuid: record.uuid,
      name: record.name,
      crm_type: record.crm_type,
      scenario: record.scenario,
      leveraging_boundary_id: record.leveraging_boundary_id,
      leveraged_boundary_id: record.leveraged_boundary_id,
      date_authorized: record.date_authorized&.to_date&.iso8601
    }

    if detailed
      data[:description] = record.description
      data[:inheritance_link_count] = record.leveraged_authorization_components.count
      data[:back_matter_resource_count] = record.back_matter_resources.count
      data[:created_at] = record.created_at.utc.iso8601
      data[:updated_at] = record.updated_at.utc.iso8601
    end

    data
  end
end
