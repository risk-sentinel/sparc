class ControlCatalog < ApplicationRecord
  include OscalMetadata
  include Searchable
  include SafeDestroyable
  include Sluggable
  include Lifecycle
  include Approvable

  has_many :control_families, dependent: :destroy
  has_many :catalog_controls, through: :control_families
  has_many :profile_documents
  has_many :source_mappings, class_name: "ControlMapping", foreign_key: :source_catalog_id
  has_many :target_mappings, class_name: "ControlMapping", foreign_key: :target_catalog_id

  enum :status, { pending: "pending", processing: "processing", completed: "completed", failed: "failed" }

  before_validation :ensure_oscal_uuid

  validates :name, presence: true

  def total_controls
    catalog_controls.count
  end

  def oscal_document_version
    version
  end

  # First 8 characters of the SHA-256 content digest for display.
  def short_digest
    catalog_content_digest&.slice(0, 8)
  end

  # ── URL identity (#881) ───────────────────────────────────────────────────
  #
  # The catalog segment of a control URL is the OSCAL document uuid, not the
  # slug. The slug is derived from `name` and the Sluggable concern REGENERATES
  # it whenever the name changes — with no redirect — so it was never a stable
  # address. It was also ~110 characters.
  #
  # A short human label (`nist-800-53-rev5`) is not viable either: there is more
  # than one Rev 5 (5.1.0, 5.2.0, the 800-53A variant, org-tailored copies), and
  # a label collapses them. The uuid pins the exact source document, which is
  # the thing a control reference has to be traceable to.
  # Only a well-formed uuid may reach a URL. `oscal_uuid` is taken verbatim from
  # an UPLOADED OSCAL document and carries no format validation — just a
  # uniqueness index — so it is attacker-influenced input, and CodeQL was right
  # to flag it reaching an href (rb/stored-xss). `slug` is safe by construction:
  # Sluggable derives it with `source.parameterize`, which yields [a-z0-9\-_].
  UUID_FORMAT = /\A[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\z/

  def url_id
    oscal_uuid.to_s.match?(UUID_FORMAT) ? oscal_uuid : slug
  end
  # NOTE: `to_param` is deliberately NOT overridden. Doing so switched every
  # catalog URL app-wide to the uuid — including `/api/v1/control_catalogs/:id`,
  # whose identifier is a published contract. The web canonical URL is the uuid
  # (control_catalogs#show 301s onto it); changing the API identifier is tracked
  # separately on epic #895.
  # Resolve by uuid first, then slug, then id — so existing links keep working.
  def self.find_for_url(identifier)
    return nil if identifier.blank?
    find_by(oscal_uuid: identifier) ||
      find_by(slug: identifier) ||
      (identifier.to_s.match?(/\A\d+\z/) ? find_by(id: identifier) : nil)
  end

  private

  def ensure_oscal_uuid
    self.oscal_uuid ||= SecureRandom.uuid
  end

  def deletion_dependencies
    deps = []
    deps << "#{profile_documents.count} profile(s)" if profile_documents.exists?
    deps << "source for #{source_mappings.count} mapping(s)" if source_mappings.exists?
    deps << "target for #{target_mappings.count} mapping(s)" if target_mappings.exists?
    deps
  end
end
