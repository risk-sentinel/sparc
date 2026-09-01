class CdefDocument < ApplicationRecord
  include OscalMetadata
  include Searchable
  include SafeDestroyable
  include Sluggable
  include Lifecycle
  include SoftDeletable
  include UploadTrackable
  include ContentCompleteness
  include Approvable

  # CDEF intentionally does NOT include BoundaryLinkInheritance: it has
  # no authorization_boundary_id column. Scope is handled at the
  # controller layer via the global-vs-boundary picker (#395 P1) which
  # writes globally_available + organization_id or attaches via
  # boundary_cdef_documents.

  include AttachmentSizeLimit

  has_many :cdef_controls, dependent: :delete_all
  # #887 — derived browser index rows. delete_all (not destroy) to match
  # cdef_controls: there are no callbacks worth running and a CDEF can carry
  # hundreds of components. Without this the foreign key makes every CDEF
  # delete fail once the document has been indexed.
  has_many :cdef_components, dependent: :delete_all
  has_many :boundary_cdef_documents, dependent: :destroy
  has_many :boundaries, through: :boundary_cdef_documents
  belongs_to :profile_document, optional: true

  # #911 layer 2 — OSCAL requires `control-implementation/@source` on every
  # component definition: a component claims to implement controls FROM
  # something, and that something is a catalog or profile.
  include CatalogLineage
  lineage_via :profile_document,
              key:      :profile,
              controls: :cdef_controls,
              message:  { label:   "profile",
                          remedy:  "Choose the profile this component definition was authored against.",
                          options: "/api/v1/profile_documents" }
  include ControlMembership
  membership_within controls: :cdef_controls, baseline: :profile_document,
                    baseline_controls: :profile_controls,
                    label: "@source profile"

  belongs_to :organization, optional: true
  # Issue #466 — AWS-sourced CDEFs are read-only; users clone them to edit.
  # cloned_from points back to the original; clones are isolated from refreshes.
  belongs_to :cloned_from, class_name: "CdefDocument", optional: true
  has_many :clones, class_name: "CdefDocument", foreign_key: :cloned_from_id, dependent: :nullify
  has_one_attached :file
  limit_attachment_size :file, max: -> { SparcConfig.max_upload_bytes }

  enum :status, { pending: "pending", processing: "processing", completed: "completed", failed: "failed" }

  validates :name, presence: true

  # #944 — OSCAL `defined-component` types, taken verbatim from the enum in the
  # baked-in v1.1.2 component schema rather than retyped from memory.
  #
  # The schema expresses this as `anyOf: [string, enum]`, so a bespoke value is
  # technically valid OSCAL. The picker therefore offers these and validation
  # allows blank — but a value outside the list is refused, because every
  # instance of one we have seen has been a typo rather than a considered
  # extension, and a mistyped type is not visible in the exported artifact.
  COMPONENT_TYPES = %w[
    interconnection software hardware service policy physical
    process-procedure plan guidance standard validation
  ].freeze

  validates :component_type, inclusion: { in: COMPONENT_TYPES }, allow_blank: true

  # Scope: CDEFs visible to a given organization for SSP composition.
  # Returns globally_available CDEFs in that org. (Boundary-specific CDEFs
  # are reached via the boundary's `boundaries.cdef_documents` association.)
  scope :globally_available_in, ->(org) {
    where(globally_available: true, organization_id: org&.id)
  }

  # Issue #466 — rows ingested by AwsLabsCdefImportService are tagged in
  # import_metadata.source_type. Scope keeps queries readable.
  scope :aws_labs_sourced, -> {
    where("import_metadata->>'source_type' = ?", "aws_labs")
  }

  CDEF_TYPES = %w[disa_stig scap cis custom].freeze

  # #628 — content-completeness, independent of the parse `status`. A CDEF
  # asserts how a component implements controls, so it needs at least one
  # control before it can be published; a metadata-only API create has none.
  requires_content("At least one control") { cdef_controls.exists? }

  # True if this CDEF was imported from AWS Labs (read-only).
  def aws_labs_source?
    import_metadata.is_a?(Hash) && import_metadata["source_type"] == "aws_labs"
  end

  # #968 item 3 — the partial-success contract.
  #
  # `CdefJsonParserService#index_components` runs inside a SAVEPOINT and, when the
  # component indexer fails, records the failure in import_metadata and lets the
  # import finish. That is deliberate: a broken index must not lose a document that
  # parsed correctly. But until this predicate existed the only trace was a log
  # line, so a degraded import was indistinguishable from a clean one at every
  # surface a person actually looks at — API, index, show page.
  #
  # Degraded means: the document is present and its controls are intact, but its
  # component index is stale or missing, so component-derived views understate it.
  def component_index_degraded?
    import_metadata.is_a?(Hash) && import_metadata["component_index_failed_at"].present?
  end

  # Record a component-index failure. Lives on the model because TWO ingest paths
  # can hit it — CdefJsonParserService (upload / YAML / XCCDF) and
  # AwsLabsCdefImportService#reindex_components (the weekly refresh) — and #968
  # item 4 found the second one writing only a log line, which would have left
  # every AWS Labs document silently degraded with the badge dark.
  #
  # `update_column` on purpose: the caller is recovering from a failed statement
  # and must not run validations or callbacks that could raise again.
  def record_component_index_failure!(error)
    return false unless persisted?

    update_column(
      :import_metadata,
      (import_metadata || {}).merge(
        "component_index_failed_at" => Time.current.iso8601,
        "component_index_error"     => "#{error.class}: #{error.message}".truncate(500)
      )
    )
    true
  rescue StandardError
    # Never let the bookkeeping become the failure; the caller's log line stands.
    false
  end

  # When the index failed, as an ISO8601 string; nil when it never has.
  def component_index_failed_at
    return nil unless component_index_degraded?
    import_metadata["component_index_failed_at"]
  end

  # Issue #466 — AWS-sourced CDEFs are read-only. Controllers should check
  # this before applying field/statement/metadata edits and redirect users
  # to the clone action when false.
  def editable?
    !aws_labs_source?
  end

  # Issue #466 — convenience for the show-page banner + audit/UX. Returns
  # the source URL recorded in import_metadata, or nil for non-AWS rows.
  def source_url
    return nil unless aws_labs_source?
    import_metadata["source_url"]
  end

  # #911 — STIG rules in this CDEF that resolved to no NIST control. These are
  # not an error: a benchmark legitimately contains rules the CCI mapping does
  # not cover, and the remedy is a converter refresh rather than an edit. They
  # are reported so the gap is visible, because the alternative — parking the
  # rule id in `control_id` — made an unmapped rule indistinguishable from a
  # mapped control at every consumer, including the OSCAL export.
  def unmapped_stig_rule_count
    cdef_controls.unmapped_stig_rules.count
  end

  def unmapped_stig_rules?
    unmapped_stig_rule_count.positive?
  end

  # #911 — reported alongside lineage in the one reconciliation object rather
  # than as a field of its own, so an integrator handling reconciliation gets
  # this for free instead of learning a second shape.
  def additional_reconciliation_issues
    super + unmapped_stig_rule_issues
  end

  private def unmapped_stig_rule_issues
    return [] unless unmapped_stig_rules?

    count = unmapped_stig_rule_count
    [ {
      code: "unmapped_stig_rules",
      count: count,
      message: "#{count} STIG #{'rule'.pluralize(count)} resolved to no NIST control " \
               "through their CCI references, so they carry no control identifier.",
      remedy: "Refresh the stig_to_nist converter, or supply the missing CCI references in the benchmark.",
      # No Api::V1 converters endpoint exists yet, so this points at the screen
      # that owns the remedy rather than inventing a path.
      options: "/converters"
    } ]
  end

  def to_json_data
    {
      document_name: name,
      cdef_type: cdef_type,
      cdef_version: cdef_version,
      benchmark_id: benchmark_id,
      description: description,
      controls: cdef_controls.order(:row_order).includes(:cdef_control_fields).map(&:to_hash)
    }
  end

  private

  def deletion_dependencies
    deps = []
    ssp_count = SspDocumentCdefDocument.where(cdef_document_id: id).count
    deps << "#{ssp_count} SSP(s)" if ssp_count > 0
    boundary_count = BoundaryCdefDocument.where(cdef_document_id: id).count
    deps << "#{boundary_count} boundary environment(s)" if boundary_count > 0
    deps
  end
end
