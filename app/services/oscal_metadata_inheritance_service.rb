# Propagates OSCAL metadata along the artifact chain.
#
# Inheritance chain:
#   ControlCatalog -> ProfileDocument -> SspDocument -> SapDocument -> SarDocument
#                                        SspDocument -> PoamDocument
#
# Uses OSCAL resolution rules: child overrides parent for scalar fields,
# array fields (roles, parties) are merged with child entries taking precedence.
class OscalMetadataInheritanceService
  def initialize(document)
    @document = document
  end

  # Resolve and apply inherited metadata from the parent document.
  # Returns the document (not saved — caller decides when to persist).
  def resolve
    parent = find_parent
    return @document unless parent

    @document.inherit_metadata_from(parent)

    # Inherit oscal_version if not set
    if @document.respond_to?(:oscal_version=) && @document.oscal_version.blank? && parent.respond_to?(:oscal_version)
      @document.oscal_version = parent.oscal_version
    end

    @document
  end

  # Resolve and persist.
  def resolve!
    resolve
    @document.save! if @document.changed?
    @document
  end

  private

  def find_parent
    case @document
    when SspDocument
      @document.profile_document
    when SapDocument
      @document.ssp_document || @document.profile_document
    when SarDocument
      @document.sap_document
    when PoamDocument
      # POAM links to SSP via system_id; check import_metadata for ssp reference
      find_poam_parent
    else
      nil
    end
  end

  def find_poam_parent
    ssp_href = (@document.import_metadata || {}).dig("import-ssp", "href")
    return nil unless ssp_href

    # Try to match by UUID stored in the href
    uuid = ssp_href.gsub(/^#/, "")
    SspDocument.find_by("import_metadata->>'uuid' = ?", uuid)
  end
end
