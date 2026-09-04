class SarDocument < ApplicationRecord
  include OscalMetadata
  include Searchable
  include SafeDestroyable
  include Sluggable
  include Lifecycle
  include SoftDeletable
  include UploadTrackable
  include BoundaryLinkInheritance

  # #557 — belt-and-suspenders for the API-create path. See SspDocument
  # for the same fix.
  after_initialize { self.status ||= "pending" }

  belongs_to :authorization_boundary, optional: true
  # #952 — a system security plan, assessment plan, assessment result and POA&M
  # are per-system by definition: they carry the implementation detail and the
  # open weaknesses for ONE boundary. The association stays `optional: true` at
  # the belongs_to so legacy rows load, and the rule is a validation so a row
  # written before it can still be READ (and repaired via #929's attach flow)
  # while no new one can be created. Evidence is deliberately exempt — it is
  # leveraged and inherited across boundaries, so a boundary-less evidence
  # record is a legitimate state.
  validates :authorization_boundary, presence: true

  include BoundaryReferenceValidation

  has_many :sar_controls, dependent: :delete_all
  include AttachmentSizeLimit

  has_many :sar_results, dependent: :delete_all
  has_many :sar_local_components, dependent: :delete_all
  has_one_attached :file
  limit_attachment_size :file, max: -> { SparcConfig.max_upload_bytes }

  belongs_to :sap_document, optional: true
  belongs_to :profile_document, optional: true
  belongs_to :ssp_document, optional: true

  # #911 layer 2 — OSCAL requires `import-ap`, and it is the ONLY import on
  # assessment-results (verified against the 1.1.2 and 1.2.1 schemas:
  # `required: [uuid, metadata, import-ap, results]`, with no `import-ssp`
  # property at all). The SSP is reached transitively — SAR -> AP -> SSP — so
  # `ssp_document_id` here is a convenience FK from boundary inheritance (#395),
  # not a second lineage hop.
  #
  # A SAR carrying only the SSP link is therefore still unresolved: its controls
  # can be traced to a catalog, but it is not a valid SAR and will not export.
  # `traceable_via` makes that report as `incomplete_` rather than `missing_`,
  # because an operator sizing the remediation needs to know which one they have.
  include CatalogLineage
  lineage_via :sap_document,
              key:           :assessment_plan,
              href:          :import_ap_href,
              traceable_via: :ssp_document,
              controls:      :sar_controls,
              message:       { label:   "assessment plan",
                               remedy:  "Set the assessment plan this assessment reports results for.",
                               options: "/api/v1/sap_documents" }
  include ControlMembership
  membership_within controls: :sar_controls, baseline: :sap_document,
                    baseline_controls: :sap_controls,
                    label: "assessment plan"

  # Inherit cross-document FKs from the boundary's existing siblings on save
  # (#395 P1). User-supplied values take precedence; we only fill nil columns.
  inherits_from_boundary(
    sap_document_id:     ->(b) { b.sap_document&.id },
    ssp_document_id:     ->(b) { b.ssp_document&.id },
    profile_document_id: ->(b) { b.ssp_document&.profile_document_id }
  )

  enum :status, { pending: "pending", processing: "processing", completed: "completed", failed: "failed" }

  validates :name, presence: true
  validates :file_type, inclusion: { in: %w[excel json xml yaml] }, allow_nil: true
  validates :creation_method, inclusion: { in: %w[excel wizard oscal_import profile ssp] }, allow_nil: true

  CREATION_METHODS = %w[excel wizard oscal_import profile ssp].freeze

  def wizard_created?
    creation_method == "wizard"
  end

  def oscal_imported?
    creation_method == "oscal_import"
  end

  def profile_created?
    creation_method == "profile"
  end

  def ssp_created?
    creation_method == "ssp"
  end

  def enriched?
    description.present? ||
      sar_results.exists? ||
      sar_local_components.exists? ||
      import_ap_href.present?
  end

  def to_json_data
    {
      document_name: name,
      controls: sar_controls.order(:row_order).includes(:sar_control_fields).map(&:to_hash)
    }
  end
end
