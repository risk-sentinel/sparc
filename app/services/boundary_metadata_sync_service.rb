# Propagates system-level metadata stored on an AuthorizationBoundary
# (system_owner, authorizing_official, impact_level, etc.) onto every
# linked document (SSP / SAP / SAR / Profile / POA&M).
#
# Boundary is the source of truth (#395 Phase 3). Documents that don't
# have a column for a given metadata field silently skip — `respond_to?`
# guards every setter call.
#
# Usage:
#   BoundaryMetadataSyncService.new(boundary).propagate!  # apply to all linked
#   BoundaryMetadataSyncService.new(boundary).drift_for(doc)
#   BoundaryMetadataSyncService.new(boundary).status_for(doc)
#
class BoundaryMetadataSyncService
  # boundary_metadata key → document attribute setter
  FIELD_TO_SETTER = {
    "system_title"          => :name=,
    "short_name"            => :short_name=,
    "impact_level"          => :baseline_level=,
    "authorization_date"    => :authorization_date=,
    "authorization_status"  => :authorization_status=,
    "authorizing_official"  => :authorizing_official_data=,
    "system_owner"          => :system_owner_data=,
    "isso"                  => :isso_data=,
    "issm"                  => :issm_data=,
    "assessor"              => :assessor_data=
  }.freeze

  def initialize(boundary)
    @boundary = boundary
  end

  # Push boundary metadata onto every linked document. Idempotent: only
  # touches columns that exist and only writes when the document value
  # differs from the boundary value.
  #
  # Returns: { document_global_id => updated_field_count }
  def propagate!
    @boundary.linked_documents.each_with_object({}) do |doc, acc|
      acc[doc.to_global_id.to_s] = sync_one(doc)
    end
  end

  # Per-document drift report. Returns:
  #   { field => { boundary: ..., document: ... } }
  # for every BOUNDARY_METADATA_KEY where (a) the document has a setter
  # for that field AND (b) the values differ.
  def drift_for(document)
    AuthorizationBoundary::BOUNDARY_METADATA_KEYS.each_with_object({}) do |key, acc|
      setter = FIELD_TO_SETTER[key]
      next unless setter && document.respond_to?(setter)
      getter = setter.to_s.delete_suffix("=")
      next unless document.respond_to?(getter)
      b_val = @boundary.public_send(key)
      d_val = document.public_send(getter)
      next if b_val == d_val
      next if b_val.blank? && d_val.blank?
      acc[key] = { boundary: b_val, document: d_val }
    end
  end

  # Sync status for a single document.
  #   :missing_fk  - document has no authorization_boundary_id (orphaned)
  #   :drift       - one or more fields differ from boundary
  #   :in_sync     - all writable fields match
  def status_for(document)
    return :missing_fk if document.respond_to?(:authorization_boundary_id) &&
                          document.authorization_boundary_id.nil?
    drift_for(document).any? ? :drift : :in_sync
  end

  private

  def sync_one(document)
    updated = 0
    AuthorizationBoundary::BOUNDARY_METADATA_KEYS.each do |key|
      setter = FIELD_TO_SETTER[key]
      next unless setter && document.respond_to?(setter)
      b_val = @boundary.public_send(key)
      next if b_val.blank?
      getter = setter.to_s.delete_suffix("=")
      next unless document.respond_to?(getter)
      next if document.public_send(getter) == b_val
      document.public_send(setter, b_val)
      updated += 1
    end
    document.save!(validate: false) if updated.positive? && document.persisted?
    updated
  end
end
