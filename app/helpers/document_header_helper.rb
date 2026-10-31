# frozen_string_literal: true

# 1.18.0-rf #1304 — what a document page's header shows under SPARC_NAV_SHELL,
# one definition for every document page: the breadcrumb back to its
# boundary and list, and its lifecycle and approval chips.
#
# The list link is the list the document's tab opens: within its boundary
# (BoundaryScopedList, the rule the tabs and the API share) when it has one,
# else the whole list.
module DocumentHeaderHelper
  DOCUMENT_LISTS = {
    ssp: "SSPs", sap: "SAPs", sar: "SARs", poam: "POA&Ms", cdef: "CDEFs", evidence: "Evidence",
    leveraged_poam: "Leveraged POA&Ms", profile: "Baselines", catalog: "Catalogs"
  }.freeze

  LIFECYCLE_INTENT = { "started" => "caution", "in_progress" => "info", "published" => "positive" }.freeze
  APPROVAL_INTENT = { "pending_review" => "caution", "approved" => "positive", "rejected" => "danger" }.freeze

  # [[boundary, path], [list, path], [document name]]
  def document_crumbs(document, type, name: document.try(:name) || document.try(:title))
    boundary = document.try(:authorization_boundary)
    crumbs = []
    crumbs << [ boundary.name, authorization_boundary_path(boundary) ] if boundary
    crumbs << [ DOCUMENT_LISTS.fetch(type), document_list_path(type, boundary) ]
    crumbs << [ name ]
  end

  # Lifecycle, then approval once it has gone past draft.
  def document_chips(document)
    chips = []
    if document.respond_to?(:lifecycle_label) && document.lifecycle_status.present?
      chips << { label: document.lifecycle_label, intent: LIFECYCLE_INTENT.fetch(document.lifecycle_status, "neutral") }
    end
    if document.respond_to?(:approval_label) && APPROVAL_INTENT.key?(document.approval_status)
      chips << { label: document.approval_label, intent: APPROVAL_INTENT.fetch(document.approval_status) }
    end
    chips
  end

  # The export menu's paths (shared/_oscal_export_dropdown) for an OSCAL
  # document; every document type routes them the same way.
  def oscal_export_paths(document)
    key = document.model_name.singular_route_key
    { validate_path: public_send("validate_oscal_export_#{key}_path", document),
      download_json_path: public_send("download_oscal_validated_#{key}_path", document),
      download_yaml_path: public_send("download_yaml_#{key}_path", document),
      download_xml_path: public_send("download_xml_#{key}_path", document),
      fallback_json_path: public_send("download_oscal_unvalidated_#{key}_path", document) }
  end

  # shared/_publish_button's paths.
  def publish_paths(document)
    key = document.model_name.singular_route_key
    { publish_path: public_send("publish_#{key}_path", document), check_path: public_send("publish_check_#{key}_path", document) }
  end

  private

  def document_list_path(type, boundary)
    return BoundaryScopedList.path(type, boundary) if boundary && BoundaryScopedList::RULES.key?(type)

    { ssp: ssp_documents_path, sap: sap_documents_path, sar: sar_documents_path, poam: poam_documents_path,
      cdef: cdef_documents_path, evidence: evidences_path, leveraged_poam: leveraged_poam_documents_path,
      profile: profile_documents_path, catalog: control_catalogs_path }.fetch(type)
  end
end
