class Evidence < ApplicationRecord
  include Sluggable
  include Searchable
  # Evidence has no `name`; `collected_by` is how an assessor finds their own.
  searchable_on :title, :description, :collected_by
  include AttachmentSizeLimit
  include ArtifactVersionable
  sluggable_source :title
  has_one_attached :file
  limit_attachment_size :file, max: -> { SparcConfig.max_upload_bytes }

  belongs_to :authorization_boundary, optional: true

  include BoundaryReferenceValidation
  has_many :evidence_control_links, dependent: :destroy
  has_many :attestations, dependent: :destroy
  has_many :ksi_validations

  validates :title, presence: true
  validates :evidence_type, presence: true
  validates :status, presence: true
  validates :description, presence: true  # #738: evidence must carry a description
  validates :source, presence: true       # #738: evidence must record its source

  # #903 / NIST AU-10 (non-repudiation), SI-10 (input validation) — evidence
  # cannot have been collected in the future. Both write paths stamp
  # `collected_at` server-side today (#738), so this can only fire if that ever
  # stops being true: a new permitted parameter, a console session, a data
  # migration, an admin tool. It is the backstop for that day, because an
  # impossible collection timestamp in a FedRAMP evidence package is a defect
  # an assessor is entitled to treat as a control failure.
  #
  # Guarded on `collected_at_changed?` so a row that already carries a bad value
  # can still be corrected — a validation that locks the record it is meant to
  # protect helps nobody.
  validate :collected_at_not_in_future

  # Stable, immutable OSCAL back-matter href (#680). Resolves via the
  # /artifacts/:uuid resolver to a freshly-signed download URL, so the
  # reference survives evidence rename (slug change), file re-upload (new
  # blob), and signed-URL rotation. Absolute (built from SPARC_APP_URL) so
  # external OSCAL consumers can dereference it. NIST AU-10 / SI-12 / CM-8.
  def oscal_resolver_url
    "#{SparcConfig.app_url.to_s.chomp('/')}/artifacts/#{uuid}"
  end

  enum :evidence_type, {
    artifact: "artifact",
    screenshot: "screenshot",
    log: "log",
    config_export: "config_export",
    scan_result: "scan_result",
    signed_statement: "signed_statement",
    policy_document: "policy_document",
    test_result: "test_result"
  }

  enum :status, {
    draft: "draft",
    collected: "collected",
    reviewed: "reviewed",
    attested: "attested",
    expired: "expired"
  }

  EVIDENCE_TYPE_LABELS = {
    "artifact" => "Artifact",
    "screenshot" => "Screenshot",
    "log" => "Log File",
    "config_export" => "Configuration Export",
    "scan_result" => "Scan Result",
    "signed_statement" => "Signed Statement",
    "policy_document" => "Policy Document",
    "test_result" => "Test Result"
  }.freeze

  STATUS_LABELS = {
    "draft" => "Draft",
    "collected" => "Collected",
    "reviewed" => "Reviewed",
    "attested" => "Attested",
    "expired" => "Expired"
  }.freeze

  def type_label
    EVIDENCE_TYPE_LABELS[evidence_type] || evidence_type.titleize
  end

  def status_label
    STATUS_LABELS[status] || status.titleize
  end

  def compute_file_hash!
    return unless file.attached?

    self.file_hash = Digest::SHA256.hexdigest(file.download)
    self.file_content_type = file.content_type
    self.original_filename = file.filename.to_s
    self.file_size = file.byte_size
    save!
  end

  def linked_control_ids
    evidence_control_links.pluck(:control_id).uniq
  end

  def attested?
    attestations.any?
  end

  private

  def collected_at_not_in_future
    return if collected_at.blank?
    return unless collected_at_changed?
    return if collected_at <= Time.current

    errors.add(:collected_at, "cannot be in the future")
  end
end
