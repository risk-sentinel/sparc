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
    return false if guidance_data.blank?
    GUIDANCE_FIELDS.any? { |f| guidance_data[f].present? }
  end

  # Returns only populated guidance fields as { field_name => value }.
  def guidance_fields
    return {} if guidance_data.blank?
    guidance_data.select { |k, v| GUIDANCE_FIELDS.include?(k) && v.present? }
  end
end
