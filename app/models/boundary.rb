class Boundary < ApplicationRecord
  belongs_to :authorization_boundary
  has_many :boundary_cdef_documents, dependent: :destroy
  has_many :cdef_documents, through: :boundary_cdef_documents

  validates :name, presence: true
  validates :environment, presence: true
  # Validate against the configurable environment set (#770). Legacy rows keep
  # working: production/development/staging/test slugs are in the default list.
  # Bypass the check for a value already persisted, so a boundary created under
  # a different SPARC_ENVIRONMENTS_LIST can't be made unsavable by a config
  # change (it only constrains new selections).
  validate :environment_in_configured_set, if: -> { environment.present? && will_save_change_to_environment? }

  # "Name (CODE)" for display; falls back to a titleized slug.
  def environment_label = SparcConfig.environment_label(environment)

  private

  def environment_in_configured_set
    return if SparcConfig.environment_values.include?(environment)

    errors.add(:environment, "is not one of the configured environments")
  end
end
