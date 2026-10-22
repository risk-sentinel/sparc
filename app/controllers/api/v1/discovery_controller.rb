# API Discovery endpoint — returns authorization-scoped endpoint inventory.
#
# Enables sparc-iac and other consumers to dynamically discover available
# endpoints and allowed HTTP methods before making API calls.
#
# #1233 — built from ApiEndpointCatalog.routes, the route inventory the token
# picker and enforcement read, instead of a hand-kept registry that listed 45
# of the 202 paths. Each route is listed when BOTH hold:
#
#   * the token's own limits let it through (ApiEndpointCatalog.permits?, the
#     check enforcement makes), so a limited token is not shown endpoints it
#     will be refused; and
#   * the caller meets the route's rule in ApiRoutePermissions.
#
# The response shape is unchanged (`path`, `methods`, `description` per
# endpoint); `group` and `group_label` are added.
#
# NIST SP 800-53 Controls:
#   AC-3  Access Enforcement — response is scoped to caller's permissions
#   AC-6  Least Privilege — write methods hidden from read-only callers
#   PM-5  Information System Inventory — machine-readable API surface catalog
#
class Api::V1::DiscoveryController < Api::V1::BaseController
  # Descriptions the hand-kept registry carried, kept so a consumer reading
  # them sees no change. Any other path is described by its group's label.
  DESCRIPTIONS = {
    "/api/v1/available" => "API discovery — lists available endpoints scoped to caller permissions",
    "/api/v1/sessions/from_token" => "Exchange a Bearer API token for a Rails session cookie (UI test automation)",
    "/api/v1/ssp_documents" => "System Security Plans",
    "/api/v1/ssp_documents/:slug" => "Single SSP document",
    "/api/v1/ssp_documents/convert" => "Parse Excel file into SSP",
    "/api/v1/ssp_documents/:slug/update_fields" => "Bulk update SSP control fields",
    "/api/v1/ssp_documents/:slug/export" => "Export SSP as JSON",
    "/api/v1/sar_documents" => "Security Assessment Results",
    "/api/v1/sar_documents/:slug" => "Single SAR document",
    "/api/v1/sar_documents/convert" => "Parse Excel file into SAR",
    "/api/v1/sar_documents/:slug/update_fields" => "Bulk update SAR control fields",
    "/api/v1/sar_documents/:slug/export" => "Export SAR as JSON",
    "/api/v1/sap_documents" => "Security Assessment Plans",
    "/api/v1/sap_documents/:slug" => "Single SAP document",
    "/api/v1/poam_documents" => "Plans of Action and Milestones",
    "/api/v1/poam_documents/:slug" => "Single POA&M document",
    "/api/v1/poam_documents/:slug/export" => "Export a POA&M: fields JSON (default) or OSCAL (format=oscal|oscal-yaml|oscal-xml); ETag/304",
    "/api/v1/control_catalogs" => "NIST and custom control catalogs",
    "/api/v1/control_catalogs/:id" => "Single control catalog",
    "/api/v1/profile_documents" => "Baselines and resolved profiles",
    "/api/v1/profile_documents/:slug" => "Single profile document",
    "/api/v1/profile_documents/:slug/parameters" => "Baseline parameter and enumeration management",
    "/api/v1/profile_documents/:slug/parameters/export" => "Export baseline parameters as JSON, YAML, or XML",
    "/api/v1/cdef_documents" => "Component Definitions",
    "/api/v1/cdef_documents/:slug" => "Single component definition",
    "/api/v1/control_mappings" => "Cross-framework control mappings",
    "/api/v1/control_mappings/:id" => "Single control mapping",
    "/api/v1/control_mappings/:id/export" => "Export a control mapping as OSCAL mapping-collection (format=oscal|oscal-yaml); ETag/304",
    "/api/v1/ksi_catalog/themes" => "FedRAMP 20x KSI themes",
    "/api/v1/ksi_catalog/indicators" => "FedRAMP 20x Key Security Indicators",
    "/api/v1/ksi_catalog/indicators/:id" => "Single KSI indicator with mapped NIST controls",
    "/api/v1/ksi_catalog/mappings" => "KSI-to-NIST 800-53 control mappings",
    "/api/v1/ksi_catalog/import" => "Import the FedRAMP 20x KSI catalog from the vendored FedRAMP/rules snapshot",
    "/api/v1/authorization_boundaries" => "Authorization boundaries",
    "/api/v1/authorization_boundaries/:id" => "Single authorization boundary",
    "/api/v1/authorization_boundaries/:id/ksi_validations" => "KSI validation records for an authorization boundary",
    "/api/v1/authorization_boundaries/:id/ksi_validations/:vid" => "Single KSI validation record",
    "/api/v1/authorization_boundaries/:id/ksi_validations/summary" => "KSI validation summary for an authorization boundary",
    "/api/v1/authorization_boundaries/:id/ksi_validations/export" => "Export KSI compliance report (JSON, YAML, XML)",
    "/api/v1/authorization_boundaries/:id/hdf_system" => "The boundary as an HDF hdf-system document (v3.7.0); also requires ssp.read",
    "/api/v1/users" => "User management",
    "/api/v1/users/:id" => "Single user",
    "/api/v1/oscal/sar_from_hdf" => "Translate HDF results to OSCAL SAR (stateless)",
    "/api/v1/oscal/poam_from_hdf" => "Translate HDF results to OSCAL POAM (stateless)",
    "/api/v1/hdf/amendments_from_oscal_poam" => "Translate OSCAL POAM to HDF Amendments (stateless; for `hdf amend apply`)"
  }.freeze

  # Paths the registry spelled with other placeholder names than the route
  # (`:slug` for `:id`, ...). Shown as the registry spelled them, so a consumer
  # matching on them (sparc-iac) sees no change; every other path is shown as
  # the route declares it.
  LEGACY_PATHS = {
    "/api/v1/ssp_documents/:id" => "/api/v1/ssp_documents/:slug",
    "/api/v1/ssp_documents/:id/update_fields" => "/api/v1/ssp_documents/:slug/update_fields",
    "/api/v1/ssp_documents/:id/export" => "/api/v1/ssp_documents/:slug/export",
    "/api/v1/sar_documents/:id" => "/api/v1/sar_documents/:slug",
    "/api/v1/sar_documents/:id/update_fields" => "/api/v1/sar_documents/:slug/update_fields",
    "/api/v1/sar_documents/:id/export" => "/api/v1/sar_documents/:slug/export",
    "/api/v1/sap_documents/:id" => "/api/v1/sap_documents/:slug",
    "/api/v1/poam_documents/:id" => "/api/v1/poam_documents/:slug",
    "/api/v1/poam_documents/:id/export" => "/api/v1/poam_documents/:slug/export",
    "/api/v1/profile_documents/:id" => "/api/v1/profile_documents/:slug",
    "/api/v1/profile_documents/:profile_document_id/parameters" => "/api/v1/profile_documents/:slug/parameters",
    "/api/v1/profile_documents/:profile_document_id/parameters/export" => "/api/v1/profile_documents/:slug/parameters/export",
    "/api/v1/cdef_documents/:id" => "/api/v1/cdef_documents/:slug",
    "/api/v1/authorization_boundaries/:authorization_boundary_id/ksi_validations" => "/api/v1/authorization_boundaries/:id/ksi_validations",
    "/api/v1/authorization_boundaries/:authorization_boundary_id/ksi_validations/:id" => "/api/v1/authorization_boundaries/:id/ksi_validations/:vid",
    "/api/v1/authorization_boundaries/:authorization_boundary_id/ksi_validations/summary" => "/api/v1/authorization_boundaries/:id/ksi_validations/summary",
    "/api/v1/authorization_boundaries/:authorization_boundary_id/ksi_validations/export" => "/api/v1/authorization_boundaries/:id/ksi_validations/export",
    "/api/v1/authorization_boundaries/:authorization_boundary_id/hdf_system" => "/api/v1/authorization_boundaries/:id/hdf_system"
  }.freeze

  # GET /api/v1/available
  def available
    render json: {
      api_version: "v1",
      system_id: "sparc-application",
      authenticated_as: current_user.display_label,
      auth_mode: SparcConfig.api_auth_mode,
      endpoints: scoped_endpoints_for(current_user, current_api_token)
    }
  end

  private

  # AC-3 / AC-6: every route the token's limits and the caller's permissions
  # allow, one entry per path with the methods allowed on it.
  def scoped_endpoints_for(user, token)
    allowed = ApiEndpointCatalog.routes.select do |route|
      token_allows?(token, route, route.spec.to_s.delete_suffix("(.:format)")) && ApiRoutePermissions.satisfied?(user, ApiRoutePermissions.rule_for(route))
    end

    allowed.group_by { |route| display_path(route.spec) }.sort.map do |path, routes|
      group = routes.first.group
      label = ApiEndpointCatalog::GROUP_LABELS.fetch(group, group)
      {
        path: path,
        methods: routes.map(&:verb).uniq.sort_by { |v| METHOD_ORDER.index(v) || METHOD_ORDER.size },
        description: DESCRIPTIONS.fetch(path, label),
        group: group,
        group_label: label
      }
    end
  end

  METHOD_ORDER = %w[GET POST PUT PATCH DELETE].freeze

  def token_allows?(token, route, path)
    return true if token.nil?

    ApiEndpointCatalog.permits?(token.allowed_endpoints, path: path, verb: route.verb, route_key: route.key)
  end

  def display_path(spec)
    path = spec.to_s.delete_suffix("(.:format)")
    LEGACY_PATHS.fetch(path, path)
  end
end
