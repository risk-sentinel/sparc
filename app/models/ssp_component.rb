class SspComponent < ApplicationRecord
  belongs_to :ssp_document
  belongs_to :cdef_document, optional: true
  has_many :ssp_by_components, dependent: :delete_all

  validates :uuid, presence: true
  validates :component_type, presence: true
  validates :title, presence: true
  validates :description, presence: true

  COMPONENT_TYPES = %w[
    this-system software hardware service policy
    process-procedure plan guidance standard validation
  ].freeze

  STATUS_STATES = %w[operational under-development disposition other].freeze

  scope :this_system, -> { where(component_type: "this-system") }

  # #398: when a component backed by a CDEF is added to an SSP, auto-populate
  # the matching SSP statements with the CDEF's implementation prose. Opt-in
  # via `SPARC_CDEF_AUTO_POPULATE` (default on). Errors are logged, not raised,
  # because we don't want a parser error to block component creation — the
  # inherited links can be re-computed via the rake task.
  after_create_commit :auto_populate_from_cdef, if: :should_auto_populate?

  private

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
