# frozen_string_literal: true

# #1342 — how an exported OSCAL document names the document it is built on, so
# a reader can follow SSP → baseline (profile) → catalog.
#
# OSCAL links them with `import-profile.href` (SSP) and `imports[].href`
# (profile). An href of `#<uuid>` resolves to the back-matter resource with
# that uuid, which says where the document is. SPARC wrote `uuid:<uuid>`
# instead: shaped like a URI, so the schema passed it, but no OSCAL tool
# resolves it, and there was no resource to find.
#
# The resource takes the named document's own OSCAL uuid, as the profile
# export already did for its catalogs. That keeps the identity stable across
# exports, and SPARC's importers already resolve `#<uuid>` to the same
# document (OscalMetadata.resolve_import_href, ProfileImportCatalogResolver).
# Its rlink is SPARC's OSCAL export of that document.
#
# NIST SP 800-53 Rev 5: PL-2, CM-2 (the plan names the baseline it implements).
module OscalImportReference
  MEDIA_TYPE = "application/json"

  module_function

  def href(uuid) = "##{uuid}"

  # The back-matter resource naming a baseline, or nil when it has no uuid.
  def for_profile(profile, description: "The baseline (OSCAL profile) this document is built on")
    return nil if profile&.uuid.blank?

    resource(profile.uuid, profile.name, description,
             url_helpers.download_oscal_profile_document_path(profile))
  end

  # The back-matter resource naming a catalog, or nil when it has no uuid.
  def for_catalog(catalog, description: "Source catalog for this profile")
    return nil if catalog&.oscal_uuid.blank?

    resource(catalog.oscal_uuid, catalog.name, description,
             url_helpers.download_oscal_control_catalog_path(catalog))
  end

  # `ours` first, then every other resource whose uuid none of `ours` has. A
  # document imported from such an export brings the resource in as its own
  # back matter, and OSCAL requires each uuid once.
  def merge(ours, others)
    ours = ours.compact
    taken = ours.to_set { _1["uuid"] }
    ours + Array(others).reject { taken.include?(_1["uuid"]) }
  end

  def resource(uuid, title, description, path)
    { "uuid" => uuid, "title" => title.to_s, "description" => description,
      "rlinks" => [ { "href" => "#{SparcConfig.app_url.to_s.chomp('/')}#{path}", "media-type" => MEDIA_TYPE } ] }
  end

  def url_helpers = Rails.application.routes.url_helpers
end
