"""Shared page inventory for the SPARC UI smoke suite (#599).

Single source of truth for the page surface, consumed by BOTH
test_authenticated_nav.py (navigation + render-health) and
test_accessibility.py (axe a11y). Keeping one list means a11y coverage and
navigation coverage can never silently drift apart.

Each entry: (label, path). `must_exist=True` pages are required to load (a 4xx/
5xx or /login bounce is a hard failure); show pages are discovered at runtime
and may legitimately be absent on a given deployment.
"""

from __future__ import annotations

# ── Public (unauthenticated) ───────────────────────────────────────────────
PUBLIC_PAGES = [
    ("login", "/login"),
]

# ── Authenticated index / list pages ───────────────────────────────────────
INDEX_PAGES = [
    ("dashboard", "/"),
    ("ssp_index", "/ssp_documents"),
    ("sar_index", "/sar_documents"),
    ("sap_index", "/sap_documents"),
    ("poam_index", "/poam_documents"),
    ("cdef_index", "/cdef_documents"),
    ("profile_index", "/profile_documents"),
    ("control_catalogs", "/control_catalogs"),
    ("control_mappings", "/control_mappings"),
    ("converters", "/converters"),
    ("authorization_boundaries", "/authorization_boundaries"),
    ("evidences", "/evidences"),
    ("authoritative_sources", "/authoritative_sources"),
    ("federation_peers", "/federation_peers"),
    ("promotion_queue", "/promotion_queue"),
    ("about", "/about"),
    ("about_api", "/about/api"),
    ("about_resources", "/about/resources"),
]

# ── Admin pages ────────────────────────────────────────────────────────────
ADMIN_PAGES = [
    ("admin_users", "/admin/users"),
    ("admin_service_accounts", "/admin/service_accounts"),
    ("admin_roles", "/admin/roles"),
    ("admin_audit_logs", "/admin/audit_logs"),
    ("admin_authorization_boundaries", "/admin/authorization_boundaries"),
    ("admin_organizations", "/admin/organizations"),
    ("admin_data_migrations", "/admin/data_migrations"),
]

# ── New / wizard forms (richest source of a11y debt + form-render bugs) ─────
FORM_PAGES = [
    ("ssp_new", "/ssp_documents/new"),
    ("ssp_wizard", "/ssp_documents/wizard"),
    ("sar_new", "/sar_documents/new"),
    ("sar_wizard", "/sar_documents/wizard"),
    ("sap_new", "/sap_documents/new"),
    ("poam_new", "/poam_documents/new"),
    ("cdef_new", "/cdef_documents/new"),
    ("profile_new", "/profile_documents/new"),
    ("control_catalog_new", "/control_catalogs/new"),
    ("control_mapping_new", "/control_mappings/new"),
    ("converter_new", "/converters/new"),
    ("authorization_boundary_new", "/authorization_boundaries/new"),
    ("evidence_new", "/evidences/new"),
    ("federation_peer_new", "/federation_peers/new"),
    ("profile_edit", "/profile/edit"),
    ("password_edit", "/password/edit"),
]

# All authenticated pages that MUST load (hard-fail on 4xx/5xx/login-bounce).
MUST_EXIST_PAGES = INDEX_PAGES + ADMIN_PAGES + FORM_PAGES

# ── Show pages — discovered at runtime from each index ──────────────────────
# (label, index_path, href_regex). Absent records skip (not fail), since the
# target deployment may not have a record of every type.
SHOW_PAGES = [
    ("ssp_show", "/ssp_documents", r"^/ssp_documents/\d+$"),
    ("sar_show", "/sar_documents", r"^/sar_documents/\d+$"),
    ("sap_show", "/sap_documents", r"^/sap_documents/\d+$"),
    ("poam_show", "/poam_documents", r"^/poam_documents/\d+$"),
    ("cdef_show", "/cdef_documents", r"^/cdef_documents/\d+$"),
    ("profile_show", "/profile_documents", r"^/profile_documents/\d+$"),
    ("control_catalog_show", "/control_catalogs", r"^/control_catalogs/\d+$"),
    ("authorization_boundary_show", "/authorization_boundaries",
     r"^/authorization_boundaries/\d+$"),
]
