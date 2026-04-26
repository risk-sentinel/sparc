# Managed back-matter resource for OSCAL documents.
#
# Represents a single resource in the OSCAL back-matter section with a
# persistent UUID for traceability. Can optionally link to an Evidence
# record for evidence-as-resource integration.
#
# Sources:
#   "managed"       — created by users in SPARC
#   "imported"      — preserved from OSCAL import
#   "sparc"         — auto-generated SPARC identifier
#   "authoritative" — instance/policy-curated reference; admin-only create,
#                     or arrived via promotion / federation
#
# NIST SA-10: Developer Configuration Management
# NIST AC-3 / AC-6: promotion approval gated by role + boundary scope
# NIST AU-2: every state-changing action recorded in BackMatterResourceChange
class BackMatterResource < ApplicationRecord
  UUID_V4_REGEX = /\A[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i

  PROMOTION_STATES = %w[none pending_review approved rejected].freeze
  SOURCES          = %w[managed imported sparc authoritative].freeze

  # OSCAL link relationship types per NIST SP 800-53 / OSCAL v1.1.2
  REL_VALUES = %w[
    reference
    depends-on
    validation
    proof-of-compliance
    provided-by
    used-by
    uses-service
    baseline-template
    diagram
    predecessor-version
    successor-version
    incorporated-into
  ].freeze

  # IANA media types commonly used in OSCAL compliance documents
  MEDIA_TYPE_OPTIONS = [
    [ "PDF", "application/pdf" ],
    [ "Word (.docx)", "application/vnd.openxmlformats-officedocument.wordprocessingml.document" ],
    [ "Excel (.xlsx)", "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet" ],
    [ "HTML", "text/html" ],
    [ "Plain Text", "text/plain" ],
    [ "PNG Image", "image/png" ],
    [ "JPEG Image", "image/jpeg" ],
    [ "OSCAL JSON", "application/oscal+json" ],
    [ "OSCAL XML", "application/oscal+xml" ],
    [ "OSCAL YAML", "application/oscal+yaml" ],
    [ "YAML", "application/yaml" ],
    [ "JSON", "application/json" ],
    [ "XML", "application/xml" ],
    [ "CSV", "text/csv" ]
  ].freeze

  belongs_to :resourceable, polymorphic: true, optional: true
  belongs_to :evidence, optional: true
  belongs_to :organization, optional: true
  belongs_to :promoted_from_organization,
             class_name: "Organization", optional: true
  belongs_to :promoted_from_authorization_boundary,
             class_name: "AuthorizationBoundary", optional: true
  belongs_to :approved_by_user, class_name: "User", optional: true
  belongs_to :superseded_by, class_name: "BackMatterResource", optional: true
  has_many   :supersedes, class_name: "BackMatterResource",
             foreign_key: :superseded_by_id, dependent: :nullify, inverse_of: :superseded_by
  has_many   :control_back_matter_links, dependent: :destroy
  has_many   :changes_log, class_name: "BackMatterResourceChange",
             dependent: :destroy, inverse_of: :back_matter_resource

  validates :title, presence: true
  validates :uuid, presence: true, uniqueness: true,
            format: { with: UUID_V4_REGEX, message: "must be a valid RFC 4122 v4 UUID" }
  validates :source, inclusion: { in: SOURCES }
  validates :rel, inclusion: { in: REL_VALUES, message: "must be a valid OSCAL link relationship" },
            allow_blank: true
  validates :promotion_status, inclusion: { in: PROMOTION_STATES }

  scope :managed, -> { where(source: "managed") }
  scope :imported, -> { where(source: "imported") }
  scope :authoritative, -> { where(source: "authoritative") }
  scope :for_document, ->(doc) { where(resourceable: doc) }
  scope :globally_available, -> { where(globally_available: true) }
  scope :org_available, ->(org_id) {
    where(organization_id: org_id).or(where(globally_available: true))
  }
  scope :pending_promotion, -> { where(promotion_status: "pending_review") }
  scope :active,   -> { where(archived_at: nil) }
  scope :archived, -> { where.not(archived_at: nil) }
  scope :federated, -> { where.not(federated_from_instance: nil) }

  # ── State helpers ─────────────────────────────────────────────────────
  def archived?       = archived_at.present?
  def pending_promotion? = promotion_status == "pending_review"
  def approved?       = promotion_status == "approved"
  def rejected?       = promotion_status == "rejected"
  def federated?      = federated_from_instance.present?
  def authoritative?  = source == "authoritative"

  # UUID used for cross-instance dedup. Federated resources retain their
  # source-instance UUID in `original_uuid`; locally-created resources fall
  # back to their own `uuid`.
  def federation_dedup_uuid
    original_uuid.presence || uuid
  end

  # Build an OSCAL-compliant resource hash for export.
  def to_oscal_resource
    resource = {
      "uuid"  => uuid,
      "title" => title
    }
    resource["description"] = description if description.present?

    rlinks = build_rlinks
    resource["rlinks"] = rlinks if rlinks.any?

    props = resource_data&.dig("props")
    resource["props"] = props if props.present?

    remarks = resource_data&.dig("remarks")
    resource["remarks"] = remarks if remarks.present?

    resource
  end

  private

  def build_rlinks
    links = []

    # Direct href link
    if href.present?
      link = { "href" => href }
      link["media-type"] = media_type if media_type.present?
      links << link
    end

    # Evidence file link
    if evidence&.file&.attached?
      link = { "href" => evidence.original_filename || evidence.file.filename.to_s }
      link["media-type"] = evidence.file.content_type if evidence.file.content_type.present?
      links << link
    end

    links
  end
end
