class CatalogControl < ApplicationRecord
  belongs_to :control_family

  # Structured guidance fields stored in the guidance_data JSONB column.
  # These come from the providing catalog (e.g. r5.json / r4_final.json) and
  # are shown read-only as context for implementors completing the SSP.
  GUIDANCE_FIELDS = %w[
    supplemental_guidance
    implementation_guidance
    check
    fix
    related_controls
    org_ref
    nist_references
  ].freeze

  validates :control_id, presence: true, uniqueness: { scope: :control_family_id }

  default_scope { order(:control_id) }

  def family_code
    control_family.code
  end

  # Returns true when at least one guidance field has content.
  def guidance_present?
    data = parsed_guidance_data
    return false if data.blank?
    GUIDANCE_FIELDS.any? { |f| data[f].present? }
  end

  # Returns only populated guidance fields as { field_name => value }.
  def guidance_fields
    data = parsed_guidance_data
    return {} if data.blank?
    data.select { |k, v| GUIDANCE_FIELDS.include?(k) && v.present? }
  end

  private

  # update_all bypasses ActiveRecord type casting, so guidance_data can
  # arrive from the DB as a plain String (double-encoded JSON) rather than
  # a Hash.  Parse defensively to handle both cases.
  def parsed_guidance_data
    raw = guidance_data
    return {} if raw.blank?
    raw.is_a?(String) ? JSON.parse(raw) : raw
  rescue JSON::ParserError
    {}
  end
end
