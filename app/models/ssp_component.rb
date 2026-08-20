class SspComponent < ApplicationRecord
  belongs_to :ssp_document
  belongs_to :cdef_document, optional: true
  has_many :ssp_by_components, dependent: :delete_all

  # ── Validation modeling (#998) ────────────────────────────────────────────
  #
  # OSCAL represents third-party product validation as a component PAIR: the
  # product, and a `validation` component carrying the certificate, joined by a
  # link with `rel="validation"` from the product to the validation. The
  # certificate is an assertion ABOUT a component, made by someone else, so it
  # gets its own subject rather than becoming a property of the product.
  #
  # `nullify` rather than `destroy`: deleting a product must not silently take
  # the certificate record with it. A validation left pointing at nothing is a
  # visible loose end; a deleted one is not.
  belongs_to :validated_component, class_name: "SspComponent",
                                   foreign_key: :validates_component_id,
                                   optional: true, inverse_of: :validations
  has_many :validations, class_name: "SspComponent",
                         foreign_key: :validates_component_id,
                         dependent: :nullify, inverse_of: :validated_component

  validates :uuid, presence: true
  validates :component_type, presence: true
  validates :title, presence: true
  validates :description, presence: true

  # An enum value with no supporting fields reads as support without being it,
  # so the fields are refused where they would mean nothing rather than stored
  # somewhere no exporter looks.
  validate :validation_fields_belong_to_a_validation_component
  validate :validation_target_is_a_sibling

  COMPONENT_TYPES = %w[
    this-system software hardware service policy
    process-procedure plan guidance standard validation
  ].freeze

  STATUS_STATES = %w[operational under-development disposition other].freeze

  scope :this_system, -> { where(component_type: "this-system") }
  scope :validations_only, -> { where(component_type: "validation") }

  def validation? = component_type == "validation"

  # True when this validation component actually says something — the point of
  # #998 is that `validation` as a bare type says nothing at all.
  def validation_claim?
    validation? && (validation_type.present? || validation_reference.present?)
  end

  # The OSCAL props a validation component carries. Named here rather than in
  # the exporter so import and export cannot disagree about the spelling.
  VALIDATION_TYPE_PROP      = "validation-type"
  VALIDATION_REFERENCE_PROP = "validation-reference"
  VALIDATION_DETAILS_REL    = "validation-details"
  VALIDATION_REL            = "validation"

  # #398: when a component backed by a CDEF is added to an SSP, auto-populate
  # the matching SSP statements with the CDEF's implementation prose. Opt-in
  # via `SPARC_CDEF_AUTO_POPULATE` (default on). Errors are logged, not raised,
  # because we don't want a parser error to block component creation — the
  # inherited links can be re-computed via the rake task.
  after_create_commit :auto_populate_from_cdef, if: :should_auto_populate?

  private

  def validation_fields_belong_to_a_validation_component
    return if validation?
    return if validation_type.blank? && validation_reference.blank? && validation_details_href.blank?

    errors.add(:component_type,
      "must be \"validation\" to record a validation type, reference or details link")
  end

  def validation_target_is_a_sibling
    return if validates_component_id.blank?

    if validates_component_id == id
      errors.add(:validates_component_id, "cannot be the component itself")
    elsif validated_component && validated_component.ssp_document_id != ssp_document_id
      errors.add(:validates_component_id, "must be a component of the same system security plan")
    end
  end

  def should_auto_populate?
    cdef_document_id.present? &&
      ENV.fetch("SPARC_CDEF_AUTO_POPULATE", "true") == "true"
  end

  def auto_populate_from_cdef
    CdefToSspInheritanceService.populate_from_component!(ssp_document, self)
  rescue StandardError => e
    Rails.logger.warn("[SspComponent] CDEF auto-populate failed for component #{id}: #{e.class} #{e.message}")
  end
end
