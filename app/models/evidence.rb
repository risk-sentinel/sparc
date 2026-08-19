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

  # #934 / NIST AU-10 — who collected this, as a reference rather than a name.
  # Optional for the same reason `UploadTrackable`'s is: a system-initiated
  # fetch has no interactive user, and the backfill leaves an ambiguous name
  # unattributed rather than guessing. `collected_by` remains the historical
  # snapshot and is never derived from this association.
  belongs_to :collected_by_user, class_name: "User", optional: true

  include BoundaryReferenceValidation
  has_many :evidence_control_links, dependent: :destroy
  has_many :attestations, dependent: :destroy

  # #947 — an attestation IS evidence, so it is created WITH the record rather
  # than bolted on at a second screen afterwards.
  #
  # Before this, `Attestation` could only be reached at
  # /evidences/:id/attestations/new — after the evidence row already existed —
  # which meant attestation-type evidence had to pass through a state where it
  # asserted nothing. Nesting closes that window: one screen, one save.
  #
  # `reject_if` keeps the nested block inert for artefact types, so a form that
  # renders the fields but leaves them blank does not try to build an empty
  # attestation and fail validation on fields the user never saw.
  accepts_nested_attributes_for :attestations,
    reject_if: ->(attrs) { attrs["statement"].blank? && attrs["attester_user_id"].blank? }
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

  # #947 — the file rule, moved OFF the form and onto the model.
  #
  # It lived in the view as `required: !@evidence.file.attached?` on a dropzone
  # whose real `<input type="file">` is `d-none`. A browser cannot focus a
  # hidden required field to report a message, so the form simply refused to
  # submit with nothing shown — an attestation was unrecordable and the screen
  # never said why. A constraint that cannot report itself is not a constraint,
  # it is a trap; here it is stated where it can produce an error message.
  #
  # `on: :create` deliberately. Rows written before this rule exist without
  # files, and demanding a re-upload to fix a typo in a title would be its own
  # trap (the same reasoning #902 applied to editing).
  validate :file_required_for_artefact_types, on: :create

  # #947 — attestation-type evidence must carry its assertion.
  #
  # The mirror of the file rule: an artefact type without a file is incomplete,
  # and so is an assertion type without an assertion. Create-only for the same
  # reason — rows that predate the rule are reported by the advisory migration,
  # not made uneditable.
  validate :attestation_required_for_attestation_types, on: :create

  # #947 — evidence must support at least one control.
  #
  # Evidence that supports nothing cannot be assessed, appears under no control,
  # and quietly inflates the evidence count. Owner decision: collected evidence
  # requires 1:n controls.
  #
  # Fires on create AND update, which is the stronger of the two dispositions
  # considered and the one chosen: rows that predate the rule are reported by
  # the advisory migration and stay readable, but the next time anyone edits one
  # they must attach a control before saving. That does block an unrelated title
  # fix behind the cleanup — a cost accepted deliberately, so the backlog gets
  # worked rather than accumulating.
  validate :at_least_one_control_link

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
    # #947 — relabelled from "Signed Statement". An attestation IS evidence: a
    # System Owner performing a periodic access review satisfies the control by
    # ASSERTING it, and there may be no file at all. The stored enum value is
    # unchanged, so no migration and no data churn — only what a user reads.
    "signed_statement" => "Attestation",
    "policy_document" => "Policy Document",
    "test_result" => "Test Result"
  }.freeze

  # #947 — the types whose substance is an assertion rather than a file.
  #
  # These require a statement and a verified attester, and do NOT require a
  # file (one may still be attached). Every other type names an artefact, so
  # the file requirement stands for them.
  ATTESTATION_TYPES = %w[signed_statement].freeze

  STATUS_LABELS = {
    "draft" => "Draft",
    "collected" => "Collected",
    "reviewed" => "Reviewed",
    "attested" => "Attested",
    "expired" => "Expired"
  }.freeze

  def type_label
    EVIDENCE_TYPE_LABELS[evidence_type] || evidence_type&.titleize
  end

  def status_label
    STATUS_LABELS[status] || status.titleize
  end

  # #738 / #934 — NIST AU-10 (non-repudiation), AU-12.
  #
  # The one place collection provenance is written. It lived as two copied lines
  # in `EvidencesController#create` and `Api::V1::EvidencesController#create`,
  # and as an omission in `AuthoritativeSourceFetchService` — a third creation
  # path that recorded no collector at all while its caller already knew who the
  # actor was (#934). A single method is what stops a fourth path from
  # repeating that.
  #
  # Assignment only, never a save: each caller owns its own validation and error
  # rendering. UTC because a local-zone timestamp drifts across DST and an
  # impossible collection time in an evidence package reads as a control failure.
  #
  # `label` is for a collector that is not a user — a scheduled fetch, a console
  # session. Naming it plainly is honest; leaving the field blank is not, which
  # is exactly the state #934 found in production data.
  def stamp_collection!(actor:, label: nil)
    self.collected_at      = Time.current.utc
    self.collected_by      = label.presence || actor&.display_label.presence || actor&.email.presence
    self.collected_by_user = actor
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

  # #947 — is this evidence an assertion rather than an artefact?
  def attestation_type?
    ATTESTATION_TYPES.include?(evidence_type)
  end

  # #947 — set ONLY by AuthoritativeSourceFetchService, for the one creation
  # path that genuinely cannot name a control.
  #
  # An authoritative source pulled into a document's back-matter is a REFERENCE
  # artefact: which controls cite it is a property of the document, discovered
  # after the fetch, not something the fetch knows. Requiring a link there would
  # mean inventing one, and an invented control link in a compliance tool is
  # worse than an honest gap.
  #
  # Deliberately VIRTUAL, not a column. It exempts the fetching save and nothing
  # else, so the moment a person edits the record it falls under the ordinary
  # rule like any other evidence. The advisory migration reports these rows
  # alongside the other unlinked ones — an exemption nobody can see is a
  # loophole, not a decision.
  attr_accessor :system_fetched

  private

  def at_least_one_control_link
    return if system_fetched
    return if evidence_control_links.reject(&:marked_for_destruction?).any?

    errors.add(:base, "Link at least one control — evidence that supports no " \
                      "control cannot be assessed and appears under nothing.")
  end

  def attestation_required_for_attestation_types
    return unless attestation_type?
    return if attestations.reject(&:marked_for_destruction?).any?

    errors.add(:base, "An attestation needs a statement and an attester — " \
                      "that assertion is the evidence when there is no file.")
  end

  def file_required_for_artefact_types
    # The presence validation already reports a missing type; adding a second
    # error about which file a nameless type needs only obscures it.
    return if evidence_type.blank?
    return if attestation_type?
    return if file.attached?

    errors.add(:file, "is required for #{type_label} evidence. " \
                      "To record an assertion with no file, choose the Attestation type.")
  end

  def collected_at_not_in_future
    return if collected_at.blank?
    return unless collected_at_changed?
    return if collected_at <= Time.current

    errors.add(:collected_at, "cannot be in the future")
  end
end
