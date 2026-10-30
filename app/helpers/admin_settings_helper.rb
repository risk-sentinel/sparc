# frozen_string_literal: true

# 1.18.0-rf #1303 — the administration screens as one settings menu, under
# SPARC_NAV_SHELL: the organization's Settings tab opens it (admin/settings),
# and every admin screen shows it in its left column, like an organization's
# settings on GitHub. The account menu's Administration list is unchanged.
#
# Every screen here is guarded by `authorize_admin!` (admin_access?), so the
# menu is shown on exactly that condition; nothing in it widens who may open
# a screen. Catalog lineage and Data migrations had no link before (owner,
# phase 4 plan: listed here, for administrators only).
#
# NIST SP 800-53 Rev 5: AC-3, AC-6 — shown only to whoever the screens admit.
module AdminSettingsHelper
  Item = Struct.new(:key, :label, :path, :icon, :description, :controller, keyword_init: true)
  Section = Struct.new(:title, :items, keyword_init: true)

  def admin_settings_sections
    [
      Section.new(title: "Access", items: [
        Item.new(key: :users, label: "Users", path: admin_users_path, icon: "user", controller: "admin/users",
                 description: "Accounts, their status, roles and API tokens"),
        Item.new(key: :roles, label: "Roles", path: admin_roles_path, icon: "shield", controller: "admin/roles",
                 description: "What each role may do"),
        Item.new(key: :service_accounts, label: "Service accounts", path: admin_service_accounts_path, icon: "key-round",
                 controller: "admin/service_accounts", description: "API-only accounts for pipelines and integrations"),
        Item.new(key: :idp_grants, label: "Unmatched IdP grants", path: admin_idp_grants_path, icon: "inbox",
                 controller: "admin/idp_grants", description: "Identity-provider grants that matched no role")
      ]),
      Section.new(title: "Organization", items: [
        Item.new(key: :organizations, label: "Organizations", path: admin_organizations_path, icon: "building-2",
                 controller: "admin/organizations", description: "Organizations and their contacts"),
        Item.new(key: :authorization_boundaries, label: "Authorization boundaries", path: admin_authorization_boundaries_path,
                 icon: "shield", controller: "admin/authorization_boundaries",
                 description: "Every boundary, its organization and members"),
        Item.new(key: :remediation_timelines, label: "Remediation timelines", path: admin_remediation_timelines_path,
                 icon: "clipboard-list", controller: "admin/remediation_timelines",
                 description: "Days to remediate, by baseline and criticality")
      ]),
      Section.new(title: "Records", items: [
        Item.new(key: :audit_logs, label: "Audit log", path: admin_audit_logs_path, icon: "file-text",
                 controller: "admin/audit_logs", description: "Who did what, and when"),
        Item.new(key: :reconciliation, label: "Catalog lineage", path: admin_reconciliation_index_path, icon: "list-checks",
                 controller: "admin/reconciliation", description: "How documents trace to their catalogs"),
        Item.new(key: :data_migrations, label: "Data migrations", path: admin_data_migrations_path, icon: "table",
                 controller: "admin/data_migrations", description: "Deferred data migrations and their status")
      ])
    ]
  end

  # The admin screens show the menu beside them (application layout).
  def admin_settings_page?
    controller_path.start_with?("admin/") && admin_access?
  end
end
