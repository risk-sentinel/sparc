# API Discovery endpoint — returns authorization-scoped endpoint inventory.
#
# Enables sparc-iac and other consumers to dynamically discover available
# endpoints and allowed HTTP methods before making API calls.
#
# NIST SP 800-53 Controls:
#   AC-3  Access Enforcement — response is scoped to caller's permissions
#   AC-6  Least Privilege — write methods hidden from read-only callers
#   PM-5  Information System Inventory — machine-readable API surface catalog
#
class Api::V1::DiscoveryController < Api::V1::BaseController
  # GET /api/v1/available
  def available
    endpoints = scoped_endpoints_for(current_user)

    render json: {
      api_version: "v1",
      system_id: "sparc-application",
      authenticated_as: current_user.display_label,
      auth_mode: SparcConfig.api_auth_mode,
      endpoints: endpoints
    }
  end

  private

  # AC-3 / AC-6: Filter endpoint registry to only methods the caller
  # is authorized to use. Omits entire endpoints when no methods remain.
  def scoped_endpoints_for(user)
    ENDPOINT_REGISTRY.filter_map do |ep|
      methods = allowed_methods(user, ep)
      next if methods.empty?

      {
        path: ep[:path],
        methods: methods,
        description: ep[:description]
      }
    end
  end

  def allowed_methods(user, ep)
    return ep[:methods] if user.admin?

    # Admin-only endpoints are invisible to non-admins entirely
    return [] if ep[:admin_only]

    ep[:methods].select do |method|
      case method
      when "GET"
        ep[:permission_read].nil? || user.has_any_permission?(ep[:permission_read])
      when "POST", "PUT", "PATCH", "DELETE"
        ep[:permission_write].present? && user.has_any_permission?(ep[:permission_write])
      else
        false
      end
    end
  end

  # Complete registry of all API v1 endpoints with their permission requirements.
  # Each entry defines which permission keys gate read (GET) and write (mutating) access.
  ENDPOINT_REGISTRY = [
    # --- Discovery ---
    { path: "/api/v1/available", methods: %w[GET],
      description: "API discovery — lists available endpoints scoped to caller permissions",
      permission_read: nil, permission_write: nil, admin_only: false },

    # --- SSP Documents ---
    { path: "/api/v1/ssp_documents", methods: %w[GET POST],
      description: "System Security Plans",
      permission_read: "ssp.read", permission_write: "ssp.write", admin_only: false },
    { path: "/api/v1/ssp_documents/:slug", methods: %w[GET PUT DELETE],
      description: "Single SSP document",
      permission_read: "ssp.read", permission_write: "ssp.write", admin_only: false },
    { path: "/api/v1/ssp_documents/convert", methods: %w[POST],
      description: "Parse Excel file into SSP",
      permission_read: nil, permission_write: "ssp.write", admin_only: false },
    { path: "/api/v1/ssp_documents/:slug/update_fields", methods: %w[PUT],
      description: "Bulk update SSP control fields",
      permission_read: nil, permission_write: "ssp.write", admin_only: false },
    { path: "/api/v1/ssp_documents/:slug/export", methods: %w[GET],
      description: "Export SSP as JSON",
      permission_read: "ssp.read", permission_write: nil, admin_only: false },

    # --- SAR Documents ---
    { path: "/api/v1/sar_documents", methods: %w[GET POST],
      description: "Security Assessment Results",
      permission_read: "sar.read", permission_write: "sar.write", admin_only: false },
    { path: "/api/v1/sar_documents/:slug", methods: %w[GET PUT DELETE],
      description: "Single SAR document",
      permission_read: "sar.read", permission_write: "sar.write", admin_only: false },
    { path: "/api/v1/sar_documents/convert", methods: %w[POST],
      description: "Parse Excel file into SAR",
      permission_read: nil, permission_write: "sar.write", admin_only: false },
    { path: "/api/v1/sar_documents/:slug/update_fields", methods: %w[PUT],
      description: "Bulk update SAR control fields",
      permission_read: nil, permission_write: "sar.write", admin_only: false },
    { path: "/api/v1/sar_documents/:slug/export", methods: %w[GET],
      description: "Export SAR as JSON",
      permission_read: "sar.read", permission_write: nil, admin_only: false },

    # --- SAP Documents ---
    { path: "/api/v1/sap_documents", methods: %w[GET POST],
      description: "Security Assessment Plans",
      permission_read: "sap.read", permission_write: "sap.write", admin_only: false },
    { path: "/api/v1/sap_documents/:slug", methods: %w[GET PUT DELETE],
      description: "Single SAP document",
      permission_read: "sap.read", permission_write: "sap.write", admin_only: false },

    # --- POA&M Documents ---
    { path: "/api/v1/poam_documents", methods: %w[GET POST],
      description: "Plans of Action and Milestones",
      permission_read: "poam.read", permission_write: "poam.write", admin_only: false },
    { path: "/api/v1/poam_documents/:slug", methods: %w[GET PUT DELETE],
      description: "Single POA&M document",
      permission_read: "poam.read", permission_write: "poam.write", admin_only: false },

    # --- Control Catalogs ---
    { path: "/api/v1/control_catalogs", methods: %w[GET POST],
      description: "NIST and custom control catalogs",
      permission_read: "catalogs.read", permission_write: "catalogs.write", admin_only: true },
    { path: "/api/v1/control_catalogs/:id", methods: %w[GET PUT DELETE],
      description: "Single control catalog",
      permission_read: "catalogs.read", permission_write: "catalogs.write", admin_only: true },

    # --- Profile Documents ---
    { path: "/api/v1/profile_documents", methods: %w[GET POST],
      description: "Baselines and resolved profiles",
      permission_read: "profiles.read", permission_write: "profiles.write", admin_only: false },
    { path: "/api/v1/profile_documents/:slug", methods: %w[GET PUT DELETE],
      description: "Single profile document",
      permission_read: "profiles.read", permission_write: "profiles.write", admin_only: false },

    # --- Baseline Parameters ---
    { path: "/api/v1/profile_documents/:slug/parameters", methods: %w[GET PUT],
      description: "Baseline parameter and enumeration management",
      permission_read: "profiles.read", permission_write: "profiles.write", admin_only: false },
    { path: "/api/v1/profile_documents/:slug/parameters/export", methods: %w[GET],
      description: "Export baseline parameters as JSON, YAML, or XML",
      permission_read: "profiles.read", permission_write: nil, admin_only: false },

    # --- CDEF Documents ---
    { path: "/api/v1/cdef_documents", methods: %w[GET POST],
      description: "Component Definitions",
      permission_read: "cdef.read", permission_write: "cdef.write", admin_only: false },
    { path: "/api/v1/cdef_documents/:slug", methods: %w[GET PUT DELETE],
      description: "Single component definition",
      permission_read: "cdef.read", permission_write: "cdef.write", admin_only: false },

    # --- Control Mappings ---
    { path: "/api/v1/control_mappings", methods: %w[GET POST],
      description: "Cross-framework control mappings",
      permission_read: "mappings.read", permission_write: "mappings.write", admin_only: true },
    { path: "/api/v1/control_mappings/:id", methods: %w[GET PUT DELETE],
      description: "Single control mapping",
      permission_read: "mappings.read", permission_write: "mappings.write", admin_only: true },

    # --- KSI Catalog ---
    { path: "/api/v1/ksi_catalog/themes", methods: %w[GET],
      description: "FedRAMP 20x KSI themes",
      permission_read: "catalogs.read", permission_write: nil, admin_only: false },
    { path: "/api/v1/ksi_catalog/indicators", methods: %w[GET],
      description: "FedRAMP 20x Key Security Indicators",
      permission_read: "catalogs.read", permission_write: nil, admin_only: false },
    { path: "/api/v1/ksi_catalog/indicators/:id", methods: %w[GET],
      description: "Single KSI indicator with mapped NIST controls",
      permission_read: "catalogs.read", permission_write: nil, admin_only: false },
    { path: "/api/v1/ksi_catalog/mappings", methods: %w[GET],
      description: "KSI-to-NIST 800-53 control mappings",
      permission_read: "catalogs.read", permission_write: nil, admin_only: false },

    # --- Authorization Boundaries ---
    { path: "/api/v1/authorization_boundaries", methods: %w[GET POST],
      description: "Authorization boundaries",
      permission_read: "authorization_boundaries.read", permission_write: "authorization_boundaries.write", admin_only: false },
    { path: "/api/v1/authorization_boundaries/:id", methods: %w[GET PUT DELETE],
      description: "Single authorization boundary",
      permission_read: "authorization_boundaries.read", permission_write: "authorization_boundaries.write", admin_only: false },

    # --- KSI Validations ---
    { path: "/api/v1/authorization_boundaries/:id/ksi_validations", methods: %w[GET POST],
      description: "KSI validation records for an authorization boundary",
      permission_read: "authorization_boundaries.read", permission_write: "authorization_boundaries.write", admin_only: false },
    { path: "/api/v1/authorization_boundaries/:id/ksi_validations/:vid", methods: %w[GET PUT DELETE],
      description: "Single KSI validation record",
      permission_read: "authorization_boundaries.read", permission_write: "authorization_boundaries.write", admin_only: false },
    { path: "/api/v1/authorization_boundaries/:id/ksi_validations/summary", methods: %w[GET],
      description: "KSI validation summary for an authorization boundary",
      permission_read: "authorization_boundaries.read", permission_write: nil, admin_only: false },
    { path: "/api/v1/authorization_boundaries/:id/ksi_validations/export", methods: %w[GET],
      description: "Export KSI compliance report (JSON, YAML, XML)",
      permission_read: "authorization_boundaries.read", permission_write: nil, admin_only: false },

    # --- Users ---
    { path: "/api/v1/users", methods: %w[GET POST],
      description: "User management",
      permission_read: nil, permission_write: nil, admin_only: true },
    { path: "/api/v1/users/:id", methods: %w[GET PUT DELETE],
      description: "Single user",
      permission_read: nil, permission_write: nil, admin_only: true }
  ].freeze
end
