# frozen_string_literal: true

# #1176 — GET /api/v1/api_endpoints
#
# What a token's `allowed_endpoints` may name: every resource group, the
# access levels its routes have, and the entry strings to send. It reads
# ApiEndpointCatalog, the same definition the token forms show and the
# authentication check enforces, so automation that issues tokens never has
# to guess a path pattern.
#
# Instance-admin only, like issuing a token.
#
# NIST 800-53 Controls: AC-3 Access Enforcement, AC-6 Least Privilege.
class Api::V1::ApiEndpointsController < Api::V1::BaseController
  before_action :authorize_admin!

  def index
    render json: {
      data: ApiEndpointCatalog.groups.map do |group|
        {
          group: group.key,
          label: group.label,
          access_levels: group.access_levels,
          entries: group.access_levels.map { |level| ApiEndpointCatalog.entry(group.key, level) }
        }
      end,
      meta: {
        all_endpoints: ApiEndpointCatalog::ALL,
        note: "Send entries in allowed_endpoints. \"*\" (or an empty list) allows every endpoint. " \
              "Read covers GET and the POSTs that only compute (previews, translations, analysis); " \
              "Write covers every other POST, PUT, PATCH and DELETE. A path pattern such as " \
              "\"/api/v1/ssp_documents*\" is still accepted and grants Read and Write on the paths it matches."
      }
    }
  end

  private

  def admin_required_message = "Not authorized to read the API endpoint catalog"
end
